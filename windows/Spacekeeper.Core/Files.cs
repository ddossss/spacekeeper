using Microsoft.Win32.SafeHandles;
using System.Runtime.InteropServices;
using System.Security.Cryptography;

namespace Spacekeeper.Core;

public sealed record FileStamp(long Length, long Modified, long Created, long Accessed, long Changed, uint Volume, ulong ID, uint Links)
{
    public bool Matches(FileStamp other) => Length == other.Length && Modified == other.Modified && Created == other.Created &&
        Changed == other.Changed && Volume == other.Volume && ID == other.ID && Links == other.Links;
    public static FileStamp Read(string path)
    {
        var info = new FileInfo(path); info.Refresh();
        if (!info.Exists || (info.Attributes & (FileAttributes.Directory | FileAttributes.ReparsePoint | FileAttributes.Offline)) != 0 ||
            ((uint)info.Attributes & (0x00400000u | 0x00040000u)) != 0)
            throw new KeeperException("일반 로컬 파일만 처리합니다: {0}", path);
        if (!OperatingSystem.IsWindows()) return new(info.Length, info.LastWriteTimeUtc.Ticks, info.CreationTimeUtc.Ticks, info.LastAccessTimeUtc.Ticks, 0, 0, 0, 1);
        using var handle = Native.CreateFile(path, 0x80, 7, IntPtr.Zero, 3, 0x00200000, IntPtr.Zero);
        if (handle.IsInvalid || !Native.GetFileInformationByHandle(handle, out var value) ||
            !Native.GetFileInformationByHandleEx(handle, 0, out var basic, (uint)Marshal.SizeOf<Native.BasicInfo>()))
            throw new KeeperException("파일을 읽을 수 없습니다: {0}", path);
        if ((value.Attributes & (0x10u | 0x400u | 0x1000u | 0x400000u | 0x40000u)) != 0 || value.Links != 1)
            throw new KeeperException("일반 로컬 파일만 처리합니다: {0}", path);
        return new(((long)value.SizeHigh << 32) | value.SizeLow, basic.Written, basic.Created, basic.Accessed,
            basic.Changed, value.Volume, ((ulong)value.IndexHigh << 32) | value.IndexLow, value.Links);
    }
    public DateTime LastUsedUtc => OperatingSystem.IsWindows()
        ? DateTime.FromFileTimeUtc(Math.Max(Modified, Accessed)) : new DateTime(Math.Max(Modified, Accessed), DateTimeKind.Utc);
}

static class Native
{
    [StructLayout(LayoutKind.Sequential)] public struct FileInfo
    {
        public uint Attributes;
        public System.Runtime.InteropServices.ComTypes.FILETIME Creation, Access, Write;
        public uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
    }
    [StructLayout(LayoutKind.Sequential)] public struct BasicInfo { public long Created, Accessed, Written, Changed; public uint Attributes; }
    [DllImport("kernel32.dll", EntryPoint = "CreateFileW", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern SafeFileHandle CreateFile(string path, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetFileInformationByHandle(SafeFileHandle file, out FileInfo value);
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetFileInformationByHandleEx(SafeFileHandle file, int kind, out BasicInfo value, uint size);
}

public static class Safety
{
    public static StringComparer Comparer => OperatingSystem.IsWindows() ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal;
    static StringComparison Comparison => OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
    public static readonly HashSet<string> ExcludedNames = new(StringComparer.OrdinalIgnoreCase)
        { ".git", ".svn", "node_modules", ".venv", "venv", "__pycache__", "$Recycle.Bin", "System Volume Information", "Windows", "Program Files", "Program Files (x86)", "ProgramData", "AppData", "codex-work" };
    public static bool Contains(string root, string path) => Path.GetFullPath(path).StartsWith(Path.TrimEndingDirectorySeparator(Path.GetFullPath(root)) + Path.DirectorySeparatorChar, Comparison);
    public static bool Same(string a, string b) => Comparer.Equals(Path.GetFullPath(a), Path.GetFullPath(b));
    public static bool Excluded(string path, IEnumerable<string> exclusions) => exclusions.Any(p => Same(p, path) || Contains(p, path));
    public static void NoLinks(string path)
    {
        var full = Path.GetFullPath(path);
        for (string? part = full; part != null; part = Path.GetDirectoryName(part))
        {
            var attributes = File.GetAttributes(part);
            if ((attributes & FileAttributes.ReparsePoint) != 0) throw new KeeperException("심볼릭 링크 경로는 제외합니다: {0}", part);
        }
    }
    public static void Root(string path)
    {
        path = Path.GetFullPath(path); NoLinks(path);
        if (!Directory.Exists(path) || Same(path, Path.GetPathRoot(path)!)) throw new KeeperException("검사할 폴더를 선택해 주세요.");
        if (OperatingSystem.IsWindows())
        {
            if (path.StartsWith(@"\\", StringComparison.Ordinal)) throw new KeeperException("로컬 NTFS 드라이브만 지원합니다.");
            var drive = new DriveInfo(Path.GetPathRoot(path)!);
            if (drive.DriveType != DriveType.Fixed || drive.DriveFormat != "NTFS") throw new KeeperException("로컬 NTFS 드라이브만 지원합니다.");
            var protectedRoots = new[] { Environment.SpecialFolder.Windows, Environment.SpecialFolder.ProgramFiles,
                Environment.SpecialFolder.ProgramFilesX86, Environment.SpecialFolder.CommonApplicationData,
                Environment.SpecialFolder.LocalApplicationData, Environment.SpecialFolder.ApplicationData }
                .Select(Environment.GetFolderPath).Where(p => !string.IsNullOrEmpty(p));
            if (Excluded(path, protectedRoots)) throw new KeeperException("시스템·라이브러리·앱 내부는 검사 대상에서 제외합니다. 문서 폴더를 선택해 주세요.");
        }
        if (path.Split(Path.DirectorySeparatorChar).Any(p => ExcludedNames.Contains(p) && p != "codex-work"))
            throw new KeeperException("시스템·라이브러리·앱 내부는 검사 대상에서 제외합니다. 문서 폴더를 선택해 주세요.");
    }
    public static void Validate(FileEntry entry)
    {
        if (!Contains(entry.Root, entry.Path)) throw new KeeperException("검사한 폴더 밖의 파일입니다.");
        NoLinks(entry.Path);
        if (!entry.Stamp.Matches(FileStamp.Read(entry.Path))) throw new KeeperException("검사 후 파일이 변경되었습니다. 다시 검사해 주세요: {0}", entry.Path);
    }
    public static string Hash(FileEntry entry, CancellationToken token)
    {
        Validate(entry);
        using var stream = new FileStream(entry.Path, FileMode.Open, FileAccess.Read, FileShare.Read, 1024 * 1024, FileOptions.SequentialScan);
        // Validate the opened handle too, so a replaced path cannot silently change the bytes being hashed.
        if (OperatingSystem.IsWindows() && (!Native.GetFileInformationByHandle(stream.SafeFileHandle, out var handle) ||
            handle.Volume != entry.Stamp.Volume || (((ulong)handle.IndexHigh << 32) | handle.IndexLow) != entry.Stamp.ID || handle.Links != 1))
            throw new KeeperException("검사 후 파일이 변경되었습니다. 다시 검사해 주세요: {0}", entry.Path);
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        var buffer = new byte[1024 * 1024]; int count;
        while ((count = stream.Read(buffer)) > 0) { token.ThrowIfCancellationRequested(); hash.AppendData(buffer, 0, count); }
        Validate(entry); return Convert.ToHexString(hash.GetHashAndReset());
    }
}

public static class Scanner
{
    public static ScanReport Walk(IEnumerable<string> roots, CancellationToken token, long minimumBytes = 1,
        IEnumerable<string>? exclusions = null, bool cache = false, int limit = 200_000, Action<Message>? progress = null)
    {
        var result = new ScanReport(); var seen = new HashSet<string>(Safety.Comparer); var count = 0;
        var excluded = (exclusions ?? []).ToList();
        foreach (var root in roots.Select(Path.GetFullPath).Distinct(Safety.Comparer))
        {
            token.ThrowIfCancellationRequested();
            if (Safety.Excluded(root, excluded)) continue;
            if (cache) Safety.NoLinks(root); else Safety.Root(root);
            var stack = new Stack<string>(); stack.Push(root);
            while (stack.TryPop(out var directory))
            {
                token.ThrowIfCancellationRequested();
                IEnumerable<string> children;
                try { children = Directory.GetFileSystemEntries(directory); }
                catch (Exception error) when (error is IOException or UnauthorizedAccessException) { result.Issue(Message.Error(error)); continue; }
                foreach (var path in children)
                {
                    token.ThrowIfCancellationRequested();
                    if (++count > limit) { result.Truncated = true; return result; }
                    try
                    {
                        var attr = File.GetAttributes(path);
                        if ((attr & (FileAttributes.ReparsePoint | FileAttributes.Hidden | FileAttributes.System | FileAttributes.Offline)) != 0 ||
                            ((uint)attr & (0x400000u | 0x40000u)) != 0 || Safety.Excluded(path, excluded) ||
                            Safety.ExcludedNames.Contains(Path.GetFileName(path)) || Path.GetFileName(path).StartsWith('.'))
                        { result.Skipped++; continue; }
                        if (attr.HasFlag(FileAttributes.Directory)) { stack.Push(path); continue; }
                        var file = new FileEntry(path, root, FileStamp.Read(path));
                        if (file.Bytes < minimumBytes || !seen.Add(path)) continue;
                        Safety.Validate(file); result.Files.Add(file);
                        if (result.Files.Count % 150 == 0) progress?.Invoke(new("{0}개 파일 확인 중…", L.Number(result.Files.Count)));
                    }
                    catch (Exception error) when (error is IOException or UnauthorizedAccessException or KeeperException)
                    { result.Skipped++; result.Issue(Message.Error(error)); }
                }
            }
        }
        return result;
    }
    public static void FindDuplicates(ScanReport report, CancellationToken token, Action<Message>? progress = null)
    {
        var buckets = report.Files.GroupBy(f => f.Bytes).Where(g => g.Count() > 1).ToList();
        var total = buckets.Sum(b => b.Count()); var count = 0;
        foreach (var bucket in buckets)
        {
            var hashes = new Dictionary<string, List<FileEntry>>();
            foreach (var file in bucket)
            {
                token.ThrowIfCancellationRequested();
                progress?.Invoke(new("파일 내용 비교 {0} / {1} · {2}", L.Number(++count), L.Number(total), file.Name));
                try
                {
                    var hash = Safety.Hash(file, token);
                    if (!hashes.TryGetValue(hash, out var list)) hashes[hash] = list = [];
                    list.Add(file with { Hash = hash });
                }
                catch (Exception error) when (error is IOException or UnauthorizedAccessException or KeeperException) { report.Issue(Message.Error(error)); }
            }
            report.Groups.AddRange(hashes.Where(h => h.Value.Count > 1).Select(h => new DuplicateGroup(h.Key, h.Value.OrderBy(f => f.Path, Safety.Comparer).ToList())));
        }
        report.Groups = report.Groups.OrderByDescending(g => g.ExtraBytes).ToList();
    }
}

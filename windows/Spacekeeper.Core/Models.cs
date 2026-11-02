using System.Text.Json;

namespace Spacekeeper.Core;

public sealed record Settings
{
    public string Language { get; set; } = L.Language;
    public bool ScheduleEnabled { get; set; }
    public bool Daily { get; set; }
    public int Weekday { get; set; } = 1;
    public int Hour { get; set; } = 10;
    public int Minute { get; set; }
    public int MinimumDays { get; set; } = 14;
    public long MaximumBytes { get; set; } = 2L * 1024 * 1024 * 1024;
    public HashSet<string> CacheIDs { get; set; } = ["chrome", "edge", "brave", "firefox", "spotify", "vscode"];
    public List<string> Exclusions { get; set; } = [];
    public void Validate()
    {
        if (!L.Languages.Contains(Language) || Weekday is < 0 or > 6 || Hour is < 0 or > 23 || Minute is < 0 or > 59 ||
            MinimumDays is < 7 or > 365 || MaximumBytes <= 0 || MaximumBytes > 20L * 1024 * 1024 * 1024 ||
            CacheIDs.Any(id => !CacheRules.IDs.Contains(id)) || Exclusions.Any(p => !Path.IsPathFullyQualified(p)))
            throw new KeeperException("정기 청소 설정 범위를 확인해 주세요.");
    }
    public Settings Copy() => JsonSerializer.Deserialize<Settings>(JsonSerializer.Serialize(this))!;
}

public sealed record FileEntry(string Path, string Root, FileStamp Stamp, string? Hash = null)
{
    public string Name => System.IO.Path.GetFileName(Path);
    public long Bytes => Stamp.Length;
}
public sealed record DuplicateGroup(string ID, List<FileEntry> Files)
{
    public long ExtraBytes => (Files.Count - 1) * Files[0].Bytes;
}
public sealed class ScanReport
{
    public List<FileEntry> Files { get; set; } = [];
    public List<DuplicateGroup> Groups { get; set; } = [];
    public List<Message> Issues { get; set; } = [];
    public int Skipped { get; set; }
    public bool Truncated { get; set; }
    public void Issue(Message message) { if (Issues.Count < 40) Issues.Add(message); }
}
public enum CleanupKind { Cache, Duplicates, Large }
public sealed record CleanupRequest(CleanupKind Kind, List<FileEntry> Files, List<DuplicateGroup>? Groups = null, int MinimumDays = 14);
public sealed class HistoryItem
{
    public Guid ID { get; set; } = Guid.NewGuid();
    public required string Source { get; set; }
    public long Bytes { get; set; }
    public string? RecyclePath { get; set; }
    public string? RecycleParsingName { get; set; }
    public FileStamp? RecycleStamp { get; set; }
    public bool Pending { get; set; }
    public bool Restored { get; set; }
    public Message? Error { get; set; }
}
public sealed class HistoryRecord
{
    public Guid ID { get; set; } = Guid.NewGuid();
    public DateTimeOffset Date { get; set; } = DateTimeOffset.Now;
    public required string Kind { get; set; }
    public Message? Note { get; set; }
    public List<HistoryItem> Items { get; set; } = [];
    public int MovedCount => Items.Count(i => i.RecyclePath != null && !i.Restored);
    public long MovedBytes => Items.Where(i => i.RecyclePath != null && !i.Restored).Sum(i => i.Bytes);
}

public sealed class Store(string root)
{
    public string Root { get; } = Path.GetFullPath(root);
    public static string DefaultRoot => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Spacekeeper");
    static readonly JsonSerializerOptions Json = new() { WriteIndented = true };
    public Settings LoadSettings()
    {
        var file = Path.Combine(Root, "settings.json");
        var result = File.Exists(file) ? JsonSerializer.Deserialize<Settings>(File.ReadAllText(file)) ?? throw new InvalidDataException(file) : new Settings();
        result.Validate(); return result;
    }
    public void SaveSettings(Settings settings) { settings.Validate(); Write(Path.Combine(Root, "settings.json"), settings); }
    public IDisposable Acquire()
    {
        Directory.CreateDirectory(Root); Safety.NoLinks(Root);
        try { return new FileStream(Path.Combine(Root, "operation.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None); }
        catch (IOException) { throw new KeeperException("다른 정리 작업이 진행 중입니다. 잠시 후 다시 시도해 주세요."); }
    }
    public void Write<T>(string path, T value)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        Safety.NoLinks(Path.GetDirectoryName(path)!);
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            { JsonSerializer.Serialize(stream, value, Json); stream.Flush(true); }
            File.Move(temporary, path, true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
    string Header(Guid id) => Path.Combine(Root, "history", id.ToString("N"), "record.json");
    public void SaveHeader(HistoryRecord record) => Write(Header(record.ID), new HistoryRecord { ID = record.ID, Date = record.Date, Kind = record.Kind, Note = record.Note });
    // Independent atomic item records avoid rewriting O(n²) bytes for large cache cleanups.
    public void SaveItem(Guid record, HistoryItem item) => Write(Path.Combine(Root, "history", record.ToString("N"), item.ID.ToString("N") + ".json"), item);
    public List<HistoryRecord> History()
    {
        var folder = Path.Combine(Root, "history");
        if (!Directory.Exists(folder)) return [];
        var records = new List<HistoryRecord>();
        foreach (var path in Directory.EnumerateFiles(folder, "record.json", SearchOption.AllDirectories))
        {
            var record = JsonSerializer.Deserialize<HistoryRecord>(File.ReadAllText(path)) ?? throw new InvalidDataException(path);
            record.Items = Directory.EnumerateFiles(Path.GetDirectoryName(path)!, "*.json").Where(p => p != path)
                .Select(p => JsonSerializer.Deserialize<HistoryItem>(File.ReadAllText(p)) ?? throw new InvalidDataException(p)).ToList();
            records.Add(record);
        }
        return records.OrderByDescending(r => r.Date).ToList();
    }
}

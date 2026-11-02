using System.Runtime.InteropServices;

namespace Spacekeeper.Core;

public sealed record RecycleReceipt(string Path, string ParsingName);
public interface IRecycler
{
    RecycleReceipt Recycle(string path);
    string Restore(HistoryItem item);
}
public static class Sta
{
    public static Task<T> Run<T>(Func<T> action)
    {
        var completion = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
        var thread = new Thread(() => { try { completion.SetResult(action()); } catch (Exception e) { completion.SetException(e); } });
        if (OperatingSystem.IsWindows()) thread.SetApartmentState(ApartmentState.STA);
        thread.Start(); return completion.Task;
    }
}

/// Recycle-only Windows Shell operations. PreDelete refuses any non-recycle transfer.
public sealed class WindowsRecycler : IRecycler
{
    public RecycleReceipt Recycle(string path)
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException();
        var drive = new DriveInfo(System.IO.Path.GetPathRoot(path)!);
        if (drive.DriveType != DriveType.Fixed || drive.DriveFormat != "NTFS") throw new KeeperException("로컬 NTFS 드라이브만 지원합니다.");
        var sink = new Sink(recycleOnly: true);
        var operation = Create(); var source = Item(path);
        try
        {
            operation.SetOperationFlags(0x00080000 | 0x00100000 | 0x20000000 | 0x0004 | 0x0010 | 0x0400 | 0x2000);
            operation.DeleteItem(source, sink); operation.PerformOperations(); operation.GetAnyOperationsAborted(out var aborted);
            if (aborted || sink.Error < 0) Marshal.ThrowExceptionForHR(sink.Error < 0 ? sink.Error : unchecked((int)0x80004004));
            if (sink.Result == null || !File.Exists(sink.Result.Path)) throw new KeeperException("휴지통 위치를 확인할 수 없습니다. 탐색기에서 확인해 주세요.");
            return sink.Result;
        }
        finally { Marshal.FinalReleaseComObject(source); Marshal.FinalReleaseComObject(operation); }
    }
    public string Restore(HistoryItem item)
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException();
        if (File.Exists(item.Source) || Directory.Exists(item.Source)) throw new KeeperException("원래 위치에 같은 이름의 파일이 있어 덮어쓰지 않았습니다.");
        var destination = Item(System.IO.Path.GetDirectoryName(item.Source)!);
        var source = Item(item.RecycleParsingName ?? item.RecyclePath!);
        var operation = Create(); var sink = new Sink(recycleOnly: false);
        try
        {
            // Rename-on-collision prevents overwriting if a new file appears after the precheck.
            operation.SetOperationFlags(0x00100000 | 0x0004 | 0x0010 | 0x0008 | 0x0400 | 0x2000);
            operation.MoveItem(source, destination, System.IO.Path.GetFileName(item.Source), sink);
            operation.PerformOperations(); operation.GetAnyOperationsAborted(out var aborted);
            if (aborted || sink.Error < 0) Marshal.ThrowExceptionForHR(sink.Error < 0 ? sink.Error : unchecked((int)0x80004004));
            return sink.Result?.Path ?? throw new KeeperException("복원을 확인할 수 없습니다. 휴지통을 확인해 주세요.");
        }
        finally { Marshal.FinalReleaseComObject(source); Marshal.FinalReleaseComObject(destination); Marshal.FinalReleaseComObject(operation); }
    }
    static IFileOperation Create()
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException();
        return (IFileOperation)Activator.CreateInstance(Type.GetTypeFromCLSID(new("3AD05575-8857-4850-9277-11B85BDB8E09"))!)!;
    }
    static IShellItem Item(string path)
    {
        var id = new Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE");
        Marshal.ThrowExceptionForHR(SHCreateItemFromParsingName(path, IntPtr.Zero, ref id, out var item)); return item;
    }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
    static extern int SHCreateItemFromParsingName(string path, IntPtr context, ref Guid id, [MarshalAs(UnmanagedType.Interface)] out IShellItem item);

    [ComVisible(true), ClassInterface(ClassInterfaceType.None)]
    sealed class Sink(bool recycleOnly) : IProgressSink
    {
        public int Error { get; private set; }
        public RecycleReceipt? Result { get; private set; }
        int Capture(int error, IShellItem? item)
        {
            Error = error;
            if (error < 0) return error;
            if (item == null) return Error = unchecked((int)0x80004005);
            try
            {
                item.GetDisplayName(0x80058000, out var file); item.GetDisplayName(0x80028000, out var parsing);
                try { Result = new(Marshal.PtrToStringUni(file)!, Marshal.PtrToStringUni(parsing)!); }
                finally { Marshal.FreeCoTaskMem(file); Marshal.FreeCoTaskMem(parsing); }
                return 0;
            }
            catch (Exception e) { return Error = Marshal.GetHRForException(e); }
        }
        public int StartOperations() => 0;
        public int FinishOperations(int result) { if (result < 0) Error = result; return 0; }
        public int PreRenameItem(uint flags, IShellItem item, string name) => 0;
        public int PostRenameItem(uint flags, IShellItem item, string name, int result, IShellItem? created) => 0;
        public int PreMoveItem(uint flags, IShellItem item, IShellItem destination, string name) => 0;
        public int PostMoveItem(uint flags, IShellItem item, IShellItem destination, string name, int result, IShellItem? created) => Capture(result, created);
        public int PreCopyItem(uint flags, IShellItem item, IShellItem destination, string name) => 0;
        public int PostCopyItem(uint flags, IShellItem item, IShellItem destination, string name, int result, IShellItem? created) => 0;
        public int PreDeleteItem(uint flags, IShellItem item) => recycleOnly && (flags & 0x80) == 0 ? unchecked((int)0x80004004) : 0;
        public int PostDeleteItem(uint flags, IShellItem item, int result, IShellItem? created) => Capture(result, created);
        public int PreNewItem(uint flags, IShellItem destination, string name) => 0;
        public int PostNewItem(uint flags, IShellItem destination, string name, string template, uint attributes, int result, IShellItem? created) => 0;
        public int UpdateProgress(uint total, uint done) => 0;
        public int ResetTimer() => 0;
        public int PauseTimer() => 0;
        public int ResumeTimer() => 0;
    }
}

[ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IShellItem
{
    void BindToHandler(IntPtr context, ref Guid handler, ref Guid id, out IntPtr result);
    void GetParent(out IShellItem parent);
    void GetDisplayName(uint kind, out IntPtr name);
    void GetAttributes(uint mask, out uint attributes);
    void Compare(IShellItem other, uint hint, out int order);
}
[ComImport, Guid("947AAB5F-0A5C-4C13-B4D6-4BF7836FC9F8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IFileOperation
{
    void Advise(IProgressSink sink, out uint cookie);
    void Unadvise(uint cookie);
    void SetOperationFlags(uint flags);
    void SetProgressMessage([MarshalAs(UnmanagedType.LPWStr)] string message);
    void SetProgressDialog(IntPtr dialog);
    void SetProperties(IntPtr properties);
    void SetOwnerWindow(IntPtr window);
    void RenameItem(IShellItem item, [MarshalAs(UnmanagedType.LPWStr)] string name, IProgressSink sink);
    void RenameItems([MarshalAs(UnmanagedType.IUnknown)] object items, [MarshalAs(UnmanagedType.LPWStr)] string name);
    void MoveItem(IShellItem item, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string name, IProgressSink sink);
    void MoveItems([MarshalAs(UnmanagedType.IUnknown)] object items, IShellItem destination);
    void CopyItem(IShellItem item, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string name, IProgressSink sink);
    void CopyItems([MarshalAs(UnmanagedType.IUnknown)] object items, IShellItem destination);
    void DeleteItem(IShellItem item, IProgressSink sink);
    void DeleteItems([MarshalAs(UnmanagedType.IUnknown)] object items);
    void NewItem(IShellItem destination, uint attributes, [MarshalAs(UnmanagedType.LPWStr)] string name, [MarshalAs(UnmanagedType.LPWStr)] string template, IProgressSink sink);
    void PerformOperations();
    void GetAnyOperationsAborted([MarshalAs(UnmanagedType.Bool)] out bool aborted);
}
[ComVisible(true), Guid("04B0F1A7-9490-44BC-96E1-4296A31252E2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IProgressSink
{
    [PreserveSig] int StartOperations();
    [PreserveSig] int FinishOperations(int result);
    [PreserveSig] int PreRenameItem(uint flags, IShellItem item, [MarshalAs(UnmanagedType.LPWStr)] string name);
    [PreserveSig] int PostRenameItem(uint flags, IShellItem item, [MarshalAs(UnmanagedType.LPWStr)] string name, int result, IShellItem? created);
    [PreserveSig] int PreMoveItem(uint flags, IShellItem item, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string name);
    [PreserveSig] int PostMoveItem(uint flags, IShellItem item, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string name, int result, IShellItem? created);
    [PreserveSig] int PreCopyItem(uint flags, IShellItem item, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string name);
    [PreserveSig] int PostCopyItem(uint flags, IShellItem item, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string name, int result, IShellItem? created);
    [PreserveSig] int PreDeleteItem(uint flags, IShellItem item);
    [PreserveSig] int PostDeleteItem(uint flags, IShellItem item, int result, IShellItem? created);
    [PreserveSig] int PreNewItem(uint flags, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string name);
    [PreserveSig] int PostNewItem(uint flags, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string name, [MarshalAs(UnmanagedType.LPWStr)] string template, uint attributes, int result, IShellItem? created);
    [PreserveSig] int UpdateProgress(uint total, uint done);
    [PreserveSig] int ResetTimer();
    [PreserveSig] int PauseTimer();
    [PreserveSig] int ResumeTimer();
}

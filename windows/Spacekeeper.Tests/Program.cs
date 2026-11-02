using Spacekeeper.Core;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Xml.Linq;

var root = Path.GetFullPath(args.FirstOrDefault(a => !a.StartsWith("--")) ?? "codex-work/windows-tests");
Directory.CreateDirectory(root);
var tests = new List<(string, Action)>();
void Test(string name, Action action) => tests.Add((name, action));
void Check(bool condition, string message = "Assertion failed") { if (!condition) throw new Exception(message); }
void Reject(Action action) { try { action(); } catch { return; } throw new Exception("Expected rejection"); }
string Folder() { var path = Path.Combine(root, Guid.NewGuid().ToString("N")); Directory.CreateDirectory(path); return path; }
FileEntry Put(string folder, string name, string content = "same content")
{ var path = Path.Combine(folder, name); File.WriteAllText(path, content); return new(path, folder, FileStamp.Read(path)); }
ScanReport Duplicates(string folder) { var report = Scanner.Walk([folder], CancellationToken.None); Scanner.FindDuplicates(report, CancellationToken.None); return report; }
(Store, FakeRecycler, Cleaner) Setup()
{ var store = new Store(Folder()); var recycler = new FakeRecycler(Folder()); return (store, recycler, new Cleaner(store, recycler)); }

Test("exact-content groups and same-size mismatch", () => { var f = Folder(); Put(f,"a","abc"); Put(f,"b","abc"); Put(f,"c","xyz"); var r=Duplicates(f); Check(r.Groups.Count==1 && r.Groups[0].Files.Count==2 && r.Groups[0].ExtraBytes==3); });
Test("overlapping roots deduplicate", () => { var f=Folder(); Put(f,"a"); var sub=Path.Combine(f,"nested"); Directory.CreateDirectory(sub); Put(sub,"b"); Check(Scanner.Walk([f,sub,f],default).Files.Count==2); });
Test("exclusions, hidden names, dependencies, minimum size", () => { var f=Folder(); Put(f,"a","a"); Put(f,"b","longer"); Put(f,".hidden"); var n=Path.Combine(f,"node_modules"); Directory.CreateDirectory(n); Put(n,"secret"); Check(Scanner.Walk([f],default,3).Files.Count==1); Check(Scanner.Walk([f],default,exclusions:[Path.Combine(f,"b")]).Files.Count==1); });
Test("scan limit and cancellation", () => { var f=Folder(); Put(f,"a"); Put(f,"b"); Check(Scanner.Walk([f],default,limit:1).Truncated); Reject(()=>Scanner.Walk([f],new CancellationToken(true))); });
Test("root and traversal guards", () => { var f=Folder(); var entry=Put(f,"a"); Reject(()=>Safety.Root(Path.GetPathRoot(f)!)); Reject(()=>Safety.Validate(entry with { Root=Folder() })); Check(!Safety.Contains(f,f+"-sibling/a")); });
Test("symbolic links are not scanned", () => { var f=Folder(); var outside=Put(Folder(),"a"); File.CreateSymbolicLink(Path.Combine(f,"linked"),outside.Path); Check(Scanner.Walk([f],default).Files.Count==0); Reject(()=>Safety.NoLinks(Path.Combine(f,"linked"))); });
Test("stale file rejected before movement", () => { var f=Folder(); var entry=Put(f,"a"); File.AppendAllText(entry.Path,"changed"); var (_,r,c)=Setup(); var result=c.Clean(new(CleanupKind.Large,[entry]),default); Check(r.Count==0 && result.Items.Single().Error!=null && File.Exists(entry.Path)); });
Test("duplicate group must retain a copy", () => { var f=Folder(); Put(f,"a"); Put(f,"b"); var report=Duplicates(f); var (_,r,c)=Setup(); Reject(()=>c.Clean(new(CleanupKind.Duplicates,report.Groups[0].Files,report.Groups),default)); Check(r.Count==0); });
Test("changed keeper blocks duplicate cleanup", () => { var f=Folder(); Put(f,"a"); Put(f,"b"); var report=Duplicates(f); File.AppendAllText(report.Groups[0].Files[0].Path,"change"); var (_,r,c)=Setup(); Reject(()=>c.Clean(new(CleanupKind.Duplicates,[report.Groups[0].Files[1]],report.Groups),default)); Check(r.Count==0); });
Test("duplicate cleanup, journal round trip and restore", () => { var f=Folder(); Put(f,"a"); Put(f,"b"); var report=Duplicates(f); var (s,r,c)=Setup(); var record=c.Clean(new(CleanupKind.Duplicates,[report.Groups[0].Files[1]],report.Groups),default); Check(record.MovedCount==1 && r.Count==1); Check(s.History().Single().Items.Count==1); var restored=c.Restore(record.ID); Check(restored.Items.Single().Restored && File.Exists(report.Groups[0].Files[0].Path) && File.Exists(report.Groups[0].Files[1].Path)); });
Test("restore never overwrites", () => { var f=Folder(); var entry=Put(f,"a"); var (_,r,c)=Setup(); var record=c.Clean(new(CleanupKind.Large,[entry]),default); File.WriteAllText(entry.Path,"new content"); Check(!c.Restore(record.ID).Items.Single().Restored && File.ReadAllText(entry.Path)=="new content"); File.Delete(entry.Path); Check(c.Restore(record.ID).Items.Single().Restored); });
Test("tampered trash rejected", () => { var entry=Put(Folder(),"a"); var (_,_,c)=Setup(); var record=c.Clean(new(CleanupKind.Large,[entry]),default); File.AppendAllText(record.Items[0].RecyclePath!,"tampered"); Check(!c.Restore(record.ID).Items[0].Restored); });
Test("exclusion added after scan blocks cleanup", () => { var entry=Put(Folder(),"a"); var (s,r,c)=Setup(); s.SaveSettings(new Settings { Exclusions=[entry.Root] }); Check(c.Clean(new(CleanupKind.Large,[entry]),default).MovedCount==0 && r.Count==0); });
Test("operation lock excludes concurrent writes", () => { var (s,_,c)=Setup(); using var hold=s.Acquire(); Reject(()=>s.Acquire()); Reject(()=>c.Clean(new(CleanupKind.Large,[Put(Folder(),"a")]),default)); });
Test("invalid settings and corrupt settings fail closed", () => { var (s,_,_)=Setup(); Reject(()=>s.SaveSettings(new Settings { MinimumDays=0 })); Reject(()=>s.SaveSettings(new Settings { CacheIDs=["unknown"] })); File.WriteAllText(Path.Combine(s.Root,"settings.json"),"broken"); Reject(()=>s.LoadSettings()); });
Test("messages and literal argument placeholders survive serialization", () => { var message=new Message("오류: {0}","file {1} name"); L.Language="en"; Check(JsonSerializer.Deserialize<Message>(JsonSerializer.Serialize(message))!.ToString()=="Error: file {1} name"); });
Test("translation placeholder parity", () => { foreach(var entry in L.Catalog) foreach(var language in new[]{"en","ja"}) { Check(entry.Value.ContainsKey(language),entry.Key); string Parts(string s)=>string.Join(',',Regex.Matches(s,@"\{\d+\}").Select(m=>m.Value).Order()); Check(Parts(entry.Key)==Parts(entry.Value[language]),entry.Key); } });
Test("scheduler XML escapes and preserves least privilege", () => { var xml=Scheduler.Xml(new Settings{Daily=true},"C:\\A & B\\Spacekeeper.exe","C:\\state & stuff","S-1-5-21-1"); var doc=XDocument.Parse(xml); XNamespace ns="http://schemas.microsoft.com/windows/2004/02/mit/task"; Check(doc.Descendants(ns+"Command").Single().Value=="C:\\A & B\\Spacekeeper.exe"); Check(doc.Descendants(ns+"RunLevel").Single().Value=="LeastPrivilege" && doc.Descendants(ns+"ScheduleByDay").Any() && !doc.Descendants(ns+"Password").Any()); });
Test("cache allowlist does not include browser user data", () => { var f=Folder(); var p=Path.Combine(f,"Google","Chrome","User Data","Default"); Directory.CreateDirectory(Path.Combine(p,"Cache")); Put(p,"Login Data"); var rules=CacheRules.Discover(f,Folder()); Check(rules.Count==1 && rules[0].Root.EndsWith("Cache")); });
Test("cache age, running app, schedule cap and disabled schedule", () => {
    var f=Folder(); Put(f,"old","1234"); Put(f,"second","5678"); Put(f,"new","new");
    foreach(var name in new[]{"old","second"}) { File.SetLastWriteTimeUtc(Path.Combine(f,name),DateTime.UtcNow.AddDays(-40)); File.SetLastAccessTimeUtc(Path.Combine(f,name),DateTime.UtcNow.AddDays(-40)); }
    var rules=new List<CacheRule>{new("chrome","Chrome",f,"unused")}; var settings=new Settings{ScheduleEnabled=true,MaximumBytes=4};
    var report=CacheRules.Scan(settings,default,rules:rules,running:_=>false); Check(report.Files.Count==2); Check(CacheRules.Scan(settings,default,rules:rules,running:_=>true).Files.Count==0);
    var (s,r,_)=Setup(); s.SaveSettings(settings); var cleaner=new Cleaner(s,r,()=>rules,_=>false);
    var result=cleaner.Clean(new(CleanupKind.Cache,report.Files),default,true); Check(result.MovedCount==1 && result.MovedBytes==4);
    settings.ScheduleEnabled=false; s.SaveSettings(settings); Reject(()=>cleaner.Clean(new(CleanupKind.Cache,report.Files),default,true));
});
Test("unsupported cache and running app remain untouched", () => { var entry=Put(Folder(),"a"); var (s,r,_)=Setup(); var c=new Cleaner(s,r,()=>[],_=>false); Check(c.Clean(new(CleanupKind.Cache,[entry]),default).MovedCount==0); });
Test("cancellation does not move files", () => { var entry=Put(Folder(),"a"); var (_,r,c)=Setup(); Check(c.Clean(new(CleanupKind.Large,[entry]),new CancellationToken(true)).MovedCount==0 && r.Count==0); });
if (OperatingSystem.IsWindows())
{
    Test("NTFS hard links are excluded", () => { var f=Folder(); var entry=Put(f,"a"); Check(WinNative.CreateHardLink(Path.Combine(f,"b"),entry.Path,IntPtr.Zero)); Check(Scanner.Walk([f],default).Files.Count==0); });
    Test("native Recycle Bin and restore", () => { var f=Folder(); var entry=Put(f,"한글 日本語 sample.txt"); var s=new Store(Folder()); var c=new Cleaner(s,new WindowsRecycler()); var record=c.Clean(new(CleanupKind.Large,[entry]),default); Check(record.MovedCount==1 && !File.Exists(entry.Path), JsonSerializer.Serialize(record)); Check(c.Restore(record.ID).Items.Single().Restored && File.Exists(entry.Path),JsonSerializer.Serialize(s.History())); });
}
var failures=0;
foreach(var (name,action) in tests)
{
    try { if(OperatingSystem.IsWindows()) await Sta.Run(()=>{action();return true;}); else action(); Console.WriteLine("PASS " + name); }
    catch(Exception e) { failures++; Console.WriteLine("FAIL " + name + "\n" + e); }
}
Console.WriteLine($"{tests.Count-failures}/{tests.Count} passed");
return failures==0 ? 0 : 1;

sealed class FakeRecycler(string root) : IRecycler
{
    public int Count;
    public RecycleReceipt Recycle(string path) { var destination=Path.Combine(root,Guid.NewGuid().ToString("N")); File.Move(path,destination); Count++; return new(destination,destination); }
    public string Restore(HistoryItem item) { File.Move(item.RecyclePath!,item.Source,false); return item.Source; }
}
static class WinNative
{
    [DllImport("kernel32.dll",EntryPoint="CreateHardLinkW",CharSet=CharSet.Unicode,SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
    public static extern bool CreateHardLink(string name,string existing,IntPtr security);
}

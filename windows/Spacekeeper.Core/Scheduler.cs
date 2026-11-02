using System.Diagnostics;
using System.Security.Principal;
using System.Text;
using System.Xml.Linq;

namespace Spacekeeper.Core;

public static class Scheduler
{
    public static string TaskName
    {
        get { if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException(); using var identity = WindowsIdentity.GetCurrent(); return "Spacekeeper Cache Cleanup-" + identity.User!.Value; }
    }
    public static string Xml(Settings settings, string executable, string state, string sid)
    {
        settings.Validate(); XNamespace ns = "http://schemas.microsoft.com/windows/2004/02/mit/task";
        string[] days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
        var trigger = new XElement(ns + "CalendarTrigger",
            new XElement(ns + "StartBoundary", DateTime.Today.AddHours(settings.Hour).AddMinutes(settings.Minute).ToString("yyyy-MM-dd'T'HH:mm:ss", System.Globalization.CultureInfo.InvariantCulture)),
            new XElement(ns + "Enabled", true),
            settings.Daily ? new XElement(ns + "ScheduleByDay", new XElement(ns + "DaysInterval", 1)) :
                new XElement(ns + "ScheduleByWeek", new XElement(ns + "WeeksInterval", 1), new XElement(ns + "DaysOfWeek", new XElement(ns + days[settings.Weekday]))));
        return new XDocument(new XDeclaration("1.0", "utf-16", null), new XElement(ns + "Task", new XAttribute("version", "1.2"),
            new XElement(ns + "RegistrationInfo", new XElement(ns + "Description", "Spacekeeper scheduled cache cleanup")),
            new XElement(ns + "Triggers", trigger),
            new XElement(ns + "Principals", new XElement(ns + "Principal", new XAttribute("id", "CurrentUser"),
                new XElement(ns + "UserId", sid), new XElement(ns + "LogonType", "InteractiveToken"), new XElement(ns + "RunLevel", "LeastPrivilege"))),
            new XElement(ns + "Settings", new XElement(ns + "MultipleInstancesPolicy", "IgnoreNew"),
                new XElement(ns + "DisallowStartIfOnBatteries", false), new XElement(ns + "StopIfGoingOnBatteries", false),
                new XElement(ns + "StartWhenAvailable", true), new XElement(ns + "ExecutionTimeLimit", "PT2H"), new XElement(ns + "Enabled", true)),
            new XElement(ns + "Actions", new XAttribute("Context", "CurrentUser"), new XElement(ns + "Exec",
                new XElement(ns + "Command", executable), new XElement(ns + "Arguments", "--scheduled --state \"" + state + "\""))))).ToString();
    }
    static (int Exit, string Output) Run(params string[] arguments)
    {
        var start = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "schtasks.exe"))
            { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (var argument in arguments) start.ArgumentList.Add(argument);
        using var process = Process.Start(start)!;
        var output = process.StandardOutput.ReadToEndAsync(); var error = process.StandardError.ReadToEndAsync();
        if (!process.WaitForExit(30_000)) { process.Kill(true); throw new KeeperException("예약 작업 응답 시간이 초과되었습니다."); }
        Task.WaitAll(output, error); return (process.ExitCode, output.Result + error.Result);
    }
    public static bool IsRegistered => OperatingSystem.IsWindows() && Run("/Query", "/TN", TaskName, "/XML").Exit == 0;
    static void Ensure(params string[] args)
    {
        var result = Run(args);
        if (result.Exit != 0) throw new KeeperException("예약 작업을 변경할 수 없습니다: {0}", result.Output.Trim());
    }
    public static void Apply(Settings settings, Store store, string executable)
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException();
        settings.Validate();
        if (!File.Exists(executable) || !executable.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) throw new KeeperException("앱 실행 파일을 찾을 수 없습니다. 앱을 다시 빌드해 주세요.");
        using var operationLock = store.Acquire();
        var previous = store.LoadSettings(); var backup = Run("/Query", "/TN", TaskName, "/XML");
        var disabled = settings.Copy(); disabled.ScheduleEnabled = false; store.SaveSettings(disabled);
        var xml = Path.Combine(store.Root, "scheduled-task.xml");
        try
        {
            if (settings.ScheduleEnabled)
            {
                File.WriteAllText(xml, Xml(settings, executable, store.Root, WindowsIdentity.GetCurrent().User!.Value), Encoding.Unicode);
                Ensure("/Create", "/TN", TaskName, "/XML", xml, "/F");
            }
            else if (backup.Exit == 0) Ensure("/Delete", "/TN", TaskName, "/F");
            store.SaveSettings(settings);
        }
        catch
        {
            try
            {
                if (backup.Exit == 0) { File.WriteAllText(xml, backup.Output, Encoding.Unicode); Ensure("/Create", "/TN", TaskName, "/XML", xml, "/F"); }
                else if (IsRegistered) Ensure("/Delete", "/TN", TaskName, "/F");
                store.SaveSettings(previous);
            }
            catch { previous.ScheduleEnabled = false; store.SaveSettings(previous); }
            throw;
        }
        finally { if (File.Exists(xml)) File.Delete(xml); }
    }
    public static void RunScheduled(Store store)
    {
        var settings = store.LoadSettings(); L.Language = settings.Language;
        if (!settings.ScheduleEnabled) return;
        var report = CacheRules.Scan(settings, CancellationToken.None);
        if (report.Files.Count == 0)
        {
            using var operationLock = store.Acquire();
            store.SaveHeader(new HistoryRecord { Kind = "정기 캐시 청소", Note = new("정리할 오래된 캐시가 없거나 앱이 실행 중이었습니다.") });
        }
        else new Cleaner(store, new WindowsRecycler()).Clean(new(CleanupKind.Cache,
            report.Files.OrderBy(f => f.Stamp.Modified).ToList(), MinimumDays: settings.MinimumDays), CancellationToken.None, scheduled: true);
    }
}

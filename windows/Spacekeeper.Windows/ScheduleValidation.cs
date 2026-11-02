using System.Diagnostics;
using System.IO;
using Spacekeeper.Core;

namespace Spacekeeper.Windows;

internal static class ScheduleValidation
{
    public static async Task Run(Store store)
    {
        if (Scheduler.IsRegistered) throw new InvalidOperationException("An existing schedule must not be replaced by tests.");
        var settings = new Settings { ScheduleEnabled = true, CacheIDs = [], Hour = 23, Minute = 59 };
        try
        {
            Scheduler.Apply(settings, store, Environment.ProcessPath!);
            if (!Scheduler.IsRegistered || !store.LoadSettings().ScheduleEnabled) throw new Exception("Registration failed");
            var start = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "schtasks.exe")) { UseShellExecute = false, CreateNoWindow = true };
            foreach (var argument in new[] { "/Run", "/TN", Scheduler.TaskName }) start.ArgumentList.Add(argument);
            using var process = Process.Start(start)!; await process.WaitForExitAsync();
            if (process.ExitCode != 0) throw new Exception("Task launch failed");
            for (var i = 0; i < 90 && store.History().Count == 0; i++) await Task.Delay(500);
            if (store.History().Count == 0 || store.History().Any(r => r.Items.Count > 0)) throw new Exception("Expected an empty-target scheduled execution");
        }
        finally { settings.ScheduleEnabled = false; Scheduler.Apply(settings, store, Environment.ProcessPath!); }
        if (Scheduler.IsRegistered || store.LoadSettings().ScheduleEnabled) throw new Exception("Unregistration failed");
        File.WriteAllText(Path.Combine(store.Root, "schedule-result.txt"), "PASS: register, query, real task execution, no-op history, unregister, disabled state.");
    }
}

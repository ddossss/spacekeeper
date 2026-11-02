using Microsoft.Win32;

namespace Spacekeeper.Core;

public sealed record InstalledApp(string Name, string Version, string Location);
public static class InstalledApps
{
    public static List<InstalledApp> Read()
    {
        if (!OperatingSystem.IsWindows()) return [];
        var result = new List<InstalledApp>();
        foreach (var hive in new[] { RegistryHive.CurrentUser, RegistryHive.LocalMachine })
            foreach (var view in new[] { RegistryView.Registry64, RegistryView.Registry32 })
            {
                using var root = RegistryKey.OpenBaseKey(hive, view);
                using var uninstall = root.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall");
                foreach (var name in uninstall?.GetSubKeyNames() ?? [])
                {
                    using var key = uninstall!.OpenSubKey(name);
                    if (key?.GetValue("DisplayName") is not string display || string.IsNullOrWhiteSpace(display) || key.GetValue("SystemComponent") is int hidden && hidden == 1) continue;
                    result.Add(new(display, key.GetValue("DisplayVersion") as string ?? "", key.GetValue("InstallLocation") as string ?? ""));
                }
            }
        return result.DistinctBy(a => (a.Name, a.Version)).OrderBy(a => a.Name).ToList();
    }
}

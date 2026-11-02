using System.Diagnostics;

namespace Spacekeeper.Core;

public sealed record CacheRule(string ID, string Name, string Root, string ProcessName)
{
    public bool Running
    {
        get { var processes = Process.GetProcessesByName(ProcessName); foreach (var process in processes) process.Dispose(); return processes.Length > 0; }
    }
}
public static class CacheRules
{
    public static readonly HashSet<string> IDs = ["chrome", "edge", "brave", "firefox", "spotify", "vscode"];
    public static List<CacheRule> Discover(string? local = null, string? roaming = null)
    {
        local ??= Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        roaming ??= Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        var result = new List<CacheRule>();
        foreach (var (id, name, relative, process) in new[] {
            ("chrome", "Google Chrome", @"Google/Chrome/User Data", "chrome"),
            ("edge", "Microsoft Edge", @"Microsoft/Edge/User Data", "msedge"),
            ("brave", "Brave Browser", @"BraveSoftware/Brave-Browser/User Data", "brave") })
        {
            var folder = Path.Combine(local, relative.Replace('/', Path.DirectorySeparatorChar));
            foreach (var profile in Children(folder).Where(p => Path.GetFileName(p) == "Default" || Path.GetFileName(p).StartsWith("Profile ", StringComparison.Ordinal)))
                foreach (var part in new[] { "Cache", "Code Cache", "GPUCache" })
                    if (Directory.Exists(Path.Combine(profile, part))) result.Add(new(id, name, Path.Combine(profile, part), process));
        }
        foreach (var profile in Children(Path.Combine(local, "Mozilla", "Firefox", "Profiles")))
            if (Directory.Exists(Path.Combine(profile, "cache2"))) result.Add(new("firefox", "Firefox", Path.Combine(profile, "cache2"), "firefox"));
        foreach (var part in new[] { "Cache", "Code Cache", "GPUCache" })
            if (Directory.Exists(Path.Combine(roaming, "Code", part))) result.Add(new("vscode", "Visual Studio Code", Path.Combine(roaming, "Code", part), "Code"));
        if (Directory.Exists(Path.Combine(local, "Spotify", "Data"))) result.Add(new("spotify", "Spotify", Path.Combine(local, "Spotify", "Data"), "Spotify"));
        return result;
    }
    static IEnumerable<string> Children(string path)
    {
        if (!Directory.Exists(path)) return [];
        try { Safety.NoLinks(path); return Directory.GetDirectories(path); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or KeeperException) { return []; }
    }
    public static ScanReport Scan(Settings settings, CancellationToken token, Action<Message>? progress = null,
        IEnumerable<CacheRule>? rules = null, Func<CacheRule, bool>? running = null)
    {
        settings.Validate(); var result = new ScanReport(); var cutoff = DateTime.UtcNow.AddDays(-settings.MinimumDays);
        foreach (var rule in rules ?? Discover())
        {
            token.ThrowIfCancellationRequested();
            if (!settings.CacheIDs.Contains(rule.ID)) continue;
            if (running?.Invoke(rule) ?? rule.Running) { result.Issue(new("실행 중인 앱: {0}", rule.Name)); continue; }
            progress?.Invoke(new("{0} 캐시 확인 중…", rule.Name));
            try
            {
                var report = Scanner.Walk([rule.Root], token, exclusions: settings.Exclusions, cache: true);
                result.Files.AddRange(report.Files.Where(f => f.Stamp.LastUsedUtc < cutoff));
                foreach (var issue in report.Issues) result.Issue(issue);
                result.Truncated |= report.Truncated;
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException or KeeperException) { result.Issue(Message.Error(e)); }
        }
        result.Files = result.Files.DistinctBy(f => f.Path, Safety.Comparer).ToList();
        return result;
    }
}

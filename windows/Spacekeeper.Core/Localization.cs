using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Spacekeeper.Core;

public sealed record Message(string Key, params string[] Args)
{
    public override string ToString() => L.Text(Key, Args);
    public static Message Error(Exception error) => error is KeeperException keeper ? keeper.Detail : new("오류: {0}", error.Message);
}
public sealed class KeeperException(string key, params string[] args) : Exception(L.Text(key, args))
{
    public Message Detail { get; } = new(key, args);
}
public static partial class L
{
    public static readonly string[] Languages = ["ko", "ja", "en"];
    public static string Language { get; set; } = Languages.Contains(CultureInfo.CurrentUICulture.TwoLetterISOLanguageName)
        ? CultureInfo.CurrentUICulture.TwoLetterISOLanguageName : "en";
    public static CultureInfo Culture => CultureInfo.GetCultureInfo(Language);
    public static string LanguageName(string value) => value switch { "ko" => "한국어", "ja" => "日本語", _ => "English" };
    public static readonly Dictionary<string, Dictionary<string, string>> Catalog = Load();
    static Dictionary<string, Dictionary<string, string>> Load()
    {
        var result = new Dictionary<string, Dictionary<string, string>>();
        foreach (var name in new[] { "shared.json", "windows.json" })
        {
            using var stream = typeof(L).Assembly.GetManifestResourceStream(name) ?? throw new InvalidOperationException(name);
            foreach (var entry in JsonSerializer.Deserialize<Dictionary<string, Dictionary<string, string>>>(stream)!) result[entry.Key] = entry.Value;
        }
        return result;
    }
    [GeneratedRegex(@"\{(\d+)\}")] private static partial Regex Placeholder();
    public static string Text(string key, params string[] args)
    {
        var text = Language != "ko" && Catalog.TryGetValue(key, out var values) && values.TryGetValue(Language, out var translation) ? translation : key;
        return Placeholder().Replace(text, match => int.TryParse(match.Groups[1].Value, out var i) && i < args.Length ? args[i] : match.Value);
    }
    public static string Bytes(long bytes)
    {
        string[] units = ["B", "KB", "MB", "GB", "TB", "PB"];
        double n = bytes; int i = 0;
        while (n >= 1000 && i < units.Length - 1) { n /= 1000; i++; }
        return n.ToString(i == 0 ? "N0" : "0.##", Culture) + " " + units[i];
    }
    public static string Number(long value) => value.ToString("N0", Culture);
    public static string Date(DateTimeOffset value) => value.ToLocalTime().ToString("g", Culture);
}

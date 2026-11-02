using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Spacekeeper.Core;

namespace Spacekeeper.Windows;

internal static class UIValidation
{
    public static async Task<string> Run(MainWindow window, Store store)
    {
        var fixture = Path.Combine(store.Root, "documents"); Directory.CreateDirectory(fixture);
        File.WriteAllText(Path.Combine(fixture, "holiday.jpg.txt"), "Spacekeeper UI integration fixture");
        File.Copy(Path.Combine(fixture, "holiday.jpg.txt"), Path.Combine(fixture, "holiday-copy.jpg.txt"), true);
        window.Roots.Add(fixture); window.Navigate("중복 파일"); await window.ScanAsync();
        Ensure(window.LastError == null && window.Report.Groups.Count == 1, "Duplicate scan");
        window.SelectExtras(); Ensure(window.Rows.Count(r => r.Selected) == 1, "Keeper protected");
        foreach (var language in L.Languages)
        {
            window.ChangeLanguage(language);
            Ensure(window.Rows.Count(r => r.Selected) == 1, "Selection preserved after language switch");
            foreach (var page in new[] { "개요", "중복 파일", "정기 청소", "설치 앱", "정리 기록" })
            {
                window.Navigate(page);
                await window.Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle);
                window.UpdateLayout();
                var bitmap = new RenderTargetBitmap((int)window.ActualWidth, (int)window.ActualHeight, 96, 96, PixelFormats.Pbgra32);
                bitmap.Render(window); var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                using var output = File.Create(Path.Combine(store.Root, $"{language}-{Array.IndexOf(new[] { "개요", "중복 파일", "정기 청소", "설치 앱", "정리 기록" }, page)}.png")); encoder.Save(output);
            }
        }
        window.Navigate("중복 파일");
        var selected = window.Rows.Single(r => r.Selected).Path;
        await window.CleanSelectionAsync();
        Ensure(window.LastError == null && !File.Exists(selected), "UI cleanup");
        var history = store.History().First(); Ensure(history.MovedCount == 1, "Cleanup history");
        await window.RestoreAsync(history.ID);
        Ensure(window.LastError == null && File.Exists(selected) && store.History().First().Items.Single().Restored, "UI restore");
        Ensure(store.LoadSettings().Language == "en", "Language persisted");
        return "PASS: duplicate scan, keeper protection, three languages, 15 page captures, selection persistence, native recycle, history, restore.";
    }
    static void Ensure(bool value, string label) { if (!value) throw new InvalidOperationException(label); }
}

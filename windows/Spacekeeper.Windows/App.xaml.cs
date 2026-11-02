using System.IO;
using System.Windows;
using Spacekeeper.Core;

namespace Spacekeeper.Windows;

public partial class App : Application
{
    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        var index = Array.IndexOf(e.Args, "--state");
        var store = new Store(index >= 0 && index + 1 < e.Args.Length ? e.Args[index + 1] : Store.DefaultRoot);
        try
        {
            if (e.Args.Contains("--schedule-test"))
            { await ScheduleValidation.Run(store); Shutdown(0); return; }
            if (e.Args.Contains("--scheduled"))
            { Scheduler.RunScheduled(store); Shutdown(0); return; }
            var window = new MainWindow(store); MainWindow = window; window.Show();
            if (e.Args.Contains("--self-test"))
            {
                var result = await UIValidation.Run(window, store);
                File.WriteAllText(Path.Combine(store.Root, "ui-result.txt"), result);
                Shutdown(result.StartsWith("PASS", StringComparison.Ordinal) ? 0 : 1);
            }
        }
        catch (Exception error)
        {
            Directory.CreateDirectory(store.Root);
            File.AppendAllText(Path.Combine(store.Root, "errors.log"), DateTimeOffset.Now + " " + error + Environment.NewLine);
            if (!e.Args.Contains("--scheduled") && !e.Args.Contains("--self-test") && !e.Args.Contains("--schedule-test")) MessageBox.Show(Message.Error(error).ToString(), "Spacekeeper");
            Shutdown(1);
        }
    }
}

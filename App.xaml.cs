using System.IO;
using System.Windows;

namespace ScanDesk;

/// <summary>
/// Interaction logic for App.xaml
/// </summary>
public partial class App : Application
{
    public App()
    {
        // Show unexpected errors instead of closing silently, and keep a log for troubleshooting.
        DispatcherUnhandledException += (_, e) =>
        {
            try
            {
                var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "ScanDesk");
                Directory.CreateDirectory(dir);
                File.AppendAllText(Path.Combine(dir, "crash.log"),
                    $"{DateTime.Now:u}{Environment.NewLine}{e.Exception}{Environment.NewLine}{Environment.NewLine}");
            }
            catch { /* logging is best effort */ }
            MessageBox.Show(e.Exception.Message, "ScanDesk", MessageBoxButton.OK, MessageBoxImage.Error);
            e.Handled = true;
        };
    }
}


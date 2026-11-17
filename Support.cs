using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using NAPS2.Images;
using NAPS2.Scan;

namespace ScanDesk;

/// <summary>Attached properties used by the tile and button templates.</summary>
public static class Ui
{
    public static readonly DependencyProperty IconProperty =
        DependencyProperty.RegisterAttached("Icon", typeof(string), typeof(Ui), new PropertyMetadata(""));
    public static string GetIcon(DependencyObject o) => (string)o.GetValue(IconProperty);
    public static void SetIcon(DependencyObject o, string v) => o.SetValue(IconProperty, v);

    public static readonly DependencyProperty AccentProperty =
        DependencyProperty.RegisterAttached("Accent", typeof(Brush), typeof(Ui), new PropertyMetadata(Brushes.SteelBlue));
    public static Brush GetAccent(DependencyObject o) => (Brush)o.GetValue(AccentProperty);
    public static void SetAccent(DependencyObject o, Brush v) => o.SetValue(AccentProperty, v);

    public static readonly DependencyProperty SubtitleProperty =
        DependencyProperty.RegisterAttached("Subtitle", typeof(string), typeof(Ui), new PropertyMetadata(""));
    public static string GetSubtitle(DependencyObject o) => (string)o.GetValue(SubtitleProperty);
    public static void SetSubtitle(DependencyObject o, string v) => o.SetValue(SubtitleProperty, v);
}

/// <summary>One scanned page in the current batch.</summary>
public sealed class PageItem : INotifyPropertyChanged
{
    private int _number;
    private double _rotation;

    public PageItem(ProcessedImage image, BitmapSource thumb)
    {
        Image = image;
        Thumb = thumb;
    }

    public ProcessedImage Image { get; set; }
    public BitmapSource Thumb { get; }

    public int Number { get => _number; set { _number = value; Raise(); } }

    /// <summary>Rotation applied to the thumbnail so it matches the page.</summary>
    public double Rotation { get => _rotation; set { _rotation = value; Raise(); } }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? n = null) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(n));
}

public sealed record DeviceChoice(ScanDevice Device)
{
    public string Display => $"{Device.Name}   ({(Device.Driver == Driver.Twain ? "TWAIN" : "WIA")})";
    public string Key => $"{Device.Driver}|{Device.ID}";
    public override string ToString() => Display;
}

public sealed class AppSettings
{
    public string? DeviceKey { get; set; }
    public bool TwoSided { get; set; }
    public string ColorMode { get; set; } = "Color";   // Color | Gray | BW
    public int Dpi { get; set; } = 300;
    public string Paper { get; set; } = "Letter";      // Letter | Legal
    public bool SkipBlank { get; set; } = true;
    public bool Deskew { get; set; } = true;
    public bool Ocr { get; set; } = true;
    public bool AutoSave { get; set; }
    public bool OpenAfterSave { get; set; }
    public string SaveFolder { get; set; } =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "Scans");

    private static string FilePath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "ScanDesk", "settings.json");

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(FilePath))
                return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(FilePath)) ?? new AppSettings();
        }
        catch { /* fall back to defaults */ }
        return new AppSettings();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch { /* settings are a convenience; ignore failures */ }
    }
}

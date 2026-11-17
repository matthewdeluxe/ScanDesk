using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Microsoft.Win32;
using NAPS2.Images;
using NAPS2.Images.Transforms;
using NAPS2.Images.Wpf;
using NAPS2.Ocr;
using NAPS2.Pdf;
using NAPS2.Scan;
using NAPS2.Util;

namespace ScanDesk;

public partial class MainWindow : Window
{
    private readonly ScanningContext _ctx;
    private readonly ScanController _controller;
    private readonly ObservableCollection<PageItem> _pages = new();
    private readonly AppSettings _settings = AppSettings.Load();
    private CancellationTokenSource? _scanCts;
    private bool _busy;
    private string? _lastPdf;

    public MainWindow()
    {
        InitializeComponent();

        _ctx = new ScanningContext(new WpfImageContext());
        try
        {
            // Lets 32-bit TWAIN drivers (like Canon ScanGear) work from this 64-bit app.
            _ctx.SetUpWin32Worker();
        }
        catch { /* TWAIN just won't be listed */ }

        var tessdata = Path.Combine(AppContext.BaseDirectory, "tessdata");
        _ctx.OcrEngine = TesseractOcrEngine.Bundled(tessdata);

        _controller = new ScanController(_ctx);
        _controller.PageEnd += (_, _) => Dispatcher.Invoke(() =>
            SetStatus($"Scanning… {_pages.Count} page(s) so far", busy: true));

        PageList.ItemsSource = _pages;
        _pages.CollectionChanged += (_, _) => RefreshPageUi();
        ApplySettingsToUi();
        RefreshPageUi();
    }

    // ---------------------------------------------------------------- startup / devices

    private async void Window_Loaded(object sender, RoutedEventArgs e) => await LoadDevicesAsync();

    private async Task LoadDevicesAsync()
    {
        SetStatus("Looking for scanners…", busy: true);
        RefreshBtn.IsEnabled = false;
        var choices = new List<DeviceChoice>();

        foreach (var driver in new[] { Driver.Wia, Driver.Twain })
        {
            try
            {
                var list = await _controller.GetDeviceList(driver);
                // The TWAIN list can include WIA devices bridged through "wiatwain"; skip those.
                choices.AddRange(list.Where(d => !(driver == Driver.Twain && d.Name.StartsWith("WIA-", StringComparison.OrdinalIgnoreCase)))
                                     .Select(d => new DeviceChoice(d)));
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"{driver} device list failed: {ex}");
            }
        }

        DeviceBox.ItemsSource = choices;
        DeviceBox.SelectedItem =
            choices.FirstOrDefault(c => c.Key == _settings.DeviceKey)
            ?? choices.FirstOrDefault(c => c.Device.Driver == Driver.Wia)
            ?? choices.FirstOrDefault();

        RefreshBtn.IsEnabled = true;
        if (choices.Count == 0)
            SetStatus("No scanner found. Check that the scanner is on and connected, then press Refresh.", error: true);
        else
            SetStatus($"Ready — {choices.Count} scanner connection(s) found. Load the feeder and press SCAN.");
    }

    private async void Refresh_Click(object sender, RoutedEventArgs e) => await LoadDevicesAsync();

    private void DeviceBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (DeviceBox.SelectedItem is DeviceChoice c) _settings.DeviceKey = c.Key;
    }

    // ---------------------------------------------------------------- settings <-> UI

    private void ApplySettingsToUi()
    {
        (_settings.TwoSided ? TwoSided : OneSided).IsChecked = true;
        (_settings.ColorMode switch { "Gray" => GrayMode, "BW" => BwMode, _ => ColorMode }).IsChecked = true;
        (_settings.Dpi switch { 200 => Dpi200, 600 => Dpi600, _ => Dpi300 }).IsChecked = true;
        (_settings.Paper == "Legal" ? Legal : Letter).IsChecked = true;
        SkipBlank.IsChecked = _settings.SkipBlank;
        Deskew.IsChecked = _settings.Deskew;
        Ocr.IsChecked = _settings.Ocr;
        AutoSave.IsChecked = _settings.AutoSave;
        OpenAfter.IsChecked = _settings.OpenAfterSave;
        FolderBox.Text = _settings.SaveFolder;
    }

    private void ReadSettingsFromUi()
    {
        _settings.TwoSided = TwoSided.IsChecked == true;
        _settings.ColorMode = GrayMode.IsChecked == true ? "Gray" : BwMode.IsChecked == true ? "BW" : "Color";
        _settings.Dpi = Dpi200.IsChecked == true ? 200 : Dpi600.IsChecked == true ? 600 : 300;
        _settings.Paper = Legal.IsChecked == true ? "Legal" : "Letter";
        _settings.SkipBlank = SkipBlank.IsChecked == true;
        _settings.Deskew = Deskew.IsChecked == true;
        _settings.Ocr = Ocr.IsChecked == true;
        _settings.AutoSave = AutoSave.IsChecked == true;
        _settings.OpenAfterSave = OpenAfter.IsChecked == true;
        _settings.SaveFolder = FolderBox.Text.Trim();
    }

    private void Window_Closing(object? sender, System.ComponentModel.CancelEventArgs e)
    {
        if (_busy || _pages.Count > 0)
        {
            string message = _busy
                ? "A scan or save is still in progress. Close anyway? Unsaved pages will be lost."
                : $"You have {_pages.Count} unsaved page(s). Close without saving?";
            var r = MessageBox.Show(this, message, "ScanDesk", MessageBoxButton.YesNo, MessageBoxImage.Warning);
            if (r != MessageBoxResult.Yes) { e.Cancel = true; return; }
        }
        _scanCts?.Cancel();
        ReadSettingsFromUi();
        _settings.Save();
    }

    // ---------------------------------------------------------------- scanning

    private async void Scan_Click(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        if (DeviceBox.SelectedItem is not DeviceChoice choice)
        {
            SetStatus("Pick a scanner at the top right first (or press Refresh).", error: true);
            return;
        }
        ReadSettingsFromUi();
        _settings.Save();

        var options = new ScanOptions
        {
            Device = choice.Device,
            Driver = choice.Device.Driver,
            PaperSource = _settings.TwoSided ? PaperSource.Duplex : PaperSource.Feeder,
            Dpi = _settings.Dpi,
            BitDepth = _settings.ColorMode switch
            {
                "Gray" => BitDepth.Grayscale,
                "BW" => BitDepth.BlackAndWhite,
                _ => BitDepth.Color
            },
            PageSize = _settings.Paper == "Legal" ? PageSize.Legal : PageSize.Letter,
            PageAlign = HorizontalAlign.Center,
            ExcludeBlankPages = _settings.SkipBlank,
            BlankPageWhiteThreshold = 70,
            BlankPageCoverageThreshold = 15,
            AutoDeskew = _settings.Deskew,
            ThumbnailSize = 340,
            Quality = 85,
            UseNativeUI = false,
        };

        int before = _pages.Count;
        _scanCts = new CancellationTokenSource();
        SetBusy(true, scanning: true);
        SetStatus("Scanning… (feeding pages)", busy: true);

        try
        {
            await foreach (var image in _controller.Scan(options, _scanCts.Token))
            {
                AddPage(image);
                SetStatus($"Scanning… {_pages.Count - before} page(s) this batch", busy: true);
            }

            int added = _pages.Count - before;
            if (added == 0)
            {
                SetStatus(_scanCts.IsCancellationRequested
                    ? "Scan stopped."
                    : "No pages came through. Is paper loaded face-up in the document feeder?", error: !_scanCts.IsCancellationRequested);
            }
            else
            {
                SetStatus($"Added {added} page(s). {_pages.Count} total — scan more, or press Save PDF.");
            }
        }
        catch (OperationCanceledException)
        {
            SetStatus($"Scan stopped. {_pages.Count - before} page(s) kept.");
        }
        catch (Exception ex)
        {
            SetStatus(FriendlyScanError(ex), error: true);
        }
        finally
        {
            SetBusy(false);
            _scanCts.Dispose();
            _scanCts = null;
        }

        if (_settings.AutoSave && _pages.Count > before)
            await SaveAsync();
    }

    private void Stop_Click(object sender, RoutedEventArgs e)
    {
        _scanCts?.Cancel();
        SetStatus("Stopping after the current page…", busy: true);
    }

    private void AddPage(ProcessedImage image)
    {
        BitmapSource thumb;
        var t = image.PostProcessingData.Thumbnail;
        if (t != null)
        {
            thumb = t.ToBitmapSource();
        }
        else
        {
            using var rendered = image.Render();
            using var small = rendered.PerformTransform(new ThumbnailTransform(340));
            thumb = small.ToBitmapSource();
        }
        if (thumb.CanFreeze) thumb.Freeze();
        _pages.Add(new PageItem(image, thumb));
    }

    private static string FriendlyScanError(Exception ex)
    {
        var name = ex.GetType().Name;
        if (name.Contains("NoPages") || name.Contains("NoFeederPages") || ex.Message.Contains("feeder", StringComparison.OrdinalIgnoreCase) && ex.Message.Contains("empty", StringComparison.OrdinalIgnoreCase))
            return "The document feeder is empty. Load your pages face-up and try again.";
        if (name.Contains("DeviceOffline") || name.Contains("NotFound"))
            return "The scanner isn't responding. Check that it's on and connected, then press Refresh.";
        if (name.Contains("PaperJam") || ex.Message.Contains("jam", StringComparison.OrdinalIgnoreCase))
            return "Paper jam! Clear the feeder, then scan the remaining pages.";
        if (name.Contains("DeviceBusy") || ex.Message.Contains("busy", StringComparison.OrdinalIgnoreCase))
            return "The scanner is busy (printing or in use). Wait a moment and try again.";
        return $"Scan problem: {ex.Message}  (Tip: try the other connection — WIA or TWAIN — in the scanner list.)";
    }

    // ---------------------------------------------------------------- saving

    private async void Save_Click(object sender, RoutedEventArgs e) => await SaveAsync();

    private async Task SaveAsync()
    {
        if (_busy || _pages.Count == 0)
        {
            if (_pages.Count == 0) SetStatus("Nothing to save yet — scan some pages first.", error: true);
            return;
        }
        ReadSettingsFromUi();

        string folder = _settings.SaveFolder;
        if (string.IsNullOrWhiteSpace(folder))
        {
            SetStatus("Choose a folder to save into (Browse…).", error: true);
            return;
        }
        try { Directory.CreateDirectory(folder); }
        catch (Exception ex)
        {
            SetStatus($"Can't use that folder: {ex.Message}", error: true);
            return;
        }

        string baseName = MakeSafeFileName(NameBox.Text);
        if (string.IsNullOrEmpty(baseName)) baseName = $"Scan {DateTime.Now:yyyy-MM-dd HHmmss}";
        string path = UniquePath(Path.Combine(folder, baseName + ".pdf"));

        SetBusy(true);
        var images = _pages.Select(p => p.Image).ToList();
        int total = images.Count;
        SetStatus(_settings.Ocr ? $"Reading text (OCR) and saving {total} page(s)…" : $"Saving {total} page(s)…", busy: true);
        Progress.IsIndeterminate = false;
        Progress.Maximum = total;
        Progress.Value = 0;

        try
        {
            var ocr = _settings.Ocr ? new OcrParams("eng", OcrMode.Default, 0) : null;
            ProgressHandler progress = new ProgressCallback((cur, max) => Dispatcher.BeginInvoke(() =>
            {
                Progress.Maximum = Math.Max(1, max);
                Progress.Value = cur;
                SetStatus(_settings.Ocr ? $"Reading text and saving… page {Math.Min(cur + 1, max)} of {max}"
                                        : $"Saving… page {Math.Min(cur + 1, max)} of {max}", busy: true, keepProgress: true);
            }));

            // Write to a temporary file first so a failed or interrupted save never leaves a broken PDF behind.
            string temp = Path.Combine(folder, $".scandesk-{Guid.NewGuid():N}.pdf");
            try
            {
                var exporter = new PdfExporter(_ctx);
                bool ok = await Task.Run(() => exporter.Export(temp, images, new PdfExportParams(), ocr, progress));
                if (!ok) throw new IOException("The PDF could not be written.");
                File.Move(temp, path);
            }
            finally
            {
                try { if (File.Exists(temp)) File.Delete(temp); } catch { /* best effort */ }
            }

            _lastPdf = path;
            OpenLastBtn.Visibility = Visibility.Visible;
            ClearPages();
            NameBox.Text = "";
            SetStatus($"Saved {total} page(s) to {path}", success: true);

            if (_settings.OpenAfterSave) OpenWithShell(path);
        }
        catch (Exception ex)
        {
            SetStatus($"Couldn't save the PDF: {ex.Message}", error: true);
        }
        finally
        {
            SetBusy(false);
        }
    }

    private static string MakeSafeFileName(string name)
    {
        name = name.Trim();
        if (name.EndsWith(".pdf", StringComparison.OrdinalIgnoreCase)) name = name[..^4];
        foreach (var c in Path.GetInvalidFileNameChars()) name = name.Replace(c, '_');
        return name.Trim();
    }

    private static string UniquePath(string path)
    {
        if (!File.Exists(path)) return path;
        string dir = Path.GetDirectoryName(path)!, stem = Path.GetFileNameWithoutExtension(path);
        for (int i = 2; ; i++)
        {
            var p = Path.Combine(dir, $"{stem} ({i}).pdf");
            if (!File.Exists(p)) return p;
        }
    }

    private void Browse_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new OpenFolderDialog { Title = "Choose where to save your scans" };
        if (Directory.Exists(FolderBox.Text)) dlg.InitialDirectory = FolderBox.Text;
        if (dlg.ShowDialog(this) == true)
        {
            FolderBox.Text = dlg.FolderName;
            ReadSettingsFromUi();
            _settings.Save();
        }
    }

    private void OpenFolder_Click(object sender, RoutedEventArgs e)
    {
        var folder = FolderBox.Text.Trim();
        try
        {
            Directory.CreateDirectory(folder);
            OpenWithShell(folder);
        }
        catch (Exception ex) { SetStatus($"Can't open that folder: {ex.Message}", error: true); }
    }

    private void OpenLast_Click(object sender, RoutedEventArgs e)
    {
        if (_lastPdf != null && File.Exists(_lastPdf)) OpenWithShell(_lastPdf);
    }

    private static void OpenWithShell(string path) =>
        Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });

    // ---------------------------------------------------------------- page editing

    private List<PageItem> SelectedPages() => PageList.SelectedItems.Cast<PageItem>().OrderBy(_pages.IndexOf).ToList();

    private void Rotate(double degrees)
    {
        foreach (var p in SelectedPages())
        {
            p.Image = p.Image.WithTransform(new RotationTransform(degrees), disposeSelf: true);
            p.Rotation = (p.Rotation + degrees + 360) % 360;
        }
    }

    private void RotateLeft_Click(object sender, RoutedEventArgs e) => Rotate(-90);
    private void RotateRight_Click(object sender, RoutedEventArgs e) => Rotate(90);

    private void DeletePage_Click(object sender, RoutedEventArgs e)
    {
        var sel = SelectedPages();
        if (sel.Count == 0) return;
        int firstIndex = _pages.IndexOf(sel[0]);
        foreach (var p in sel)
        {
            _pages.Remove(p);
            p.Image.Dispose();
        }
        if (_pages.Count > 0) PageList.SelectedIndex = Math.Min(firstIndex, _pages.Count - 1);
        SetStatus($"Deleted {sel.Count} page(s). {_pages.Count} left.");
    }

    private void MoveLeft_Click(object sender, RoutedEventArgs e) => MoveSelected(-1);
    private void MoveRight_Click(object sender, RoutedEventArgs e) => MoveSelected(+1);

    private void MoveSelected(int delta)
    {
        if (PageList.SelectedItems.Count != 1 || PageList.SelectedItem is not PageItem p) return;
        int i = _pages.IndexOf(p), j = i + delta;
        if (j < 0 || j >= _pages.Count) return;
        _pages.Move(i, j);
        PageList.SelectedItem = p;
        PageList.ScrollIntoView(p);
    }

    private void Clear_Click(object sender, RoutedEventArgs e)
    {
        if (_pages.Count == 0) return;
        var r = MessageBox.Show(this, $"Remove all {_pages.Count} scanned page(s) without saving?", "Start over",
            MessageBoxButton.YesNo, MessageBoxImage.Question);
        if (r != MessageBoxResult.Yes) return;
        ClearPages();
        SetStatus("Cleared. Ready for the next document.");
    }

    private void ClearPages()
    {
        foreach (var p in _pages) p.Image.Dispose();
        _pages.Clear();
    }

    private void PageList_SelectionChanged(object sender, SelectionChangedEventArgs e) => RefreshPageUi();

    // ---------------------------------------------------------------- UI helpers

    private void RefreshPageUi()
    {
        for (int i = 0; i < _pages.Count; i++) _pages[i].Number = i + 1;
        PagesTitle.Text = _pages.Count == 0 ? "Pages" : $"Pages  ({_pages.Count})";
        EmptyState.Visibility = _pages.Count == 0 ? Visibility.Visible : Visibility.Collapsed;

        bool any = PageList.SelectedItems.Count > 0 && !_busy;
        bool single = PageList.SelectedItems.Count == 1 && !_busy;
        RotateLeftBtn.IsEnabled = RotateRightBtn.IsEnabled = DeletePageBtn.IsEnabled = any;
        MoveLeftBtn.IsEnabled = MoveRightBtn.IsEnabled = single;
        SaveBtn.IsEnabled = ClearBtn.IsEnabled = _pages.Count > 0 && !_busy;
    }

    private void SetBusy(bool busy, bool scanning = false)
    {
        _busy = busy;
        ScanBtn.Visibility = scanning ? Visibility.Collapsed : Visibility.Visible;
        StopBtn.Visibility = scanning ? Visibility.Visible : Visibility.Collapsed;
        ScanBtn.IsEnabled = !busy;
        SettingsPanel.IsEnabled = !busy;
        DeviceBox.IsEnabled = RefreshBtn.IsEnabled = !busy;
        PageList.IsEnabled = !busy || scanning;
        if (!busy) Progress.Visibility = Visibility.Collapsed;
        RefreshPageUi();
    }

    private void SetStatus(string text, bool busy = false, bool error = false, bool success = false, bool keepProgress = false)
    {
        StatusText.Text = text;
        StatusDot.Fill = (Brush)FindResource(error ? "Rose" : busy ? "Amber" : success ? "Blue" : "Green");
        if (!keepProgress)
        {
            Progress.Visibility = busy ? Visibility.Visible : Visibility.Collapsed;
            if (busy && !_busy) Progress.IsIndeterminate = true;
            else if (busy && StopBtn.Visibility == Visibility.Visible) Progress.IsIndeterminate = true;
        }
    }
}

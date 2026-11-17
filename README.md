# ScanDesk

A small Windows desktop app for scanning paper documents to PDF. Pick a scanner, scan one or more pages, review them, and save a single PDF with a searchable text layer (OCR).

Built with WPF on .NET 10. Scanning, OCR and PDF export use the [NAPS2 SDK](https://www.naps2.com/sdk/doc/) and Tesseract.

## Features

- Scans from WIA and TWAIN scanners (32-bit TWAIN drivers are handled through the NAPS2 worker process)
- Combines multiple pages into one PDF
- Optional OCR (English) so the PDF is searchable
- PDFs are written to a temporary file first, so a failed save never leaves a broken PDF behind
- Remembers the last scanner, save folder and options (`%AppData%\ScanDesk\settings.json`)
- Default save folder: `Documents\Scans`
- Unhandled errors are logged to `%AppData%\ScanDesk\crash.log`

## Requirements

- Windows 10 or 11, x64
- A scanner with a WIA or TWAIN driver installed
- To build: the [.NET 10 SDK](https://dotnet.microsoft.com/download)

## Build and run

```powershell
cd ScanDesk
dotnet run
```

Publish a self-contained build:

```powershell
dotnet publish -c Release -r win-x64 --self-contained
```

## Project layout

| Path | Purpose |
| --- | --- |
| `ScanDesk/MainWindow.xaml(.cs)` | Main window: device list, scanning, page list, saving |
| `ScanDesk/Support.cs` | UI helpers, device and page models, settings |
| `ScanDesk/App.xaml` | Shared styles and theme |
| `ScanDesk/tessdata/` | Tesseract English language data (`eng.traineddata`) |

## macOS plan

A Mac version is planned. The current UI is WPF, which is Windows only, so the work is:

1. Move scanning, OCR, PDF export and settings into a shared class library with no UI dependencies.
2. Build a cross-platform front end with [Avalonia](https://avaloniaui.net/), reusing the existing layout and flow.
3. Use the NAPS2 SDK's macOS drivers (Apple ImageCapture, ESCL network scanning, and optionally SANE or TWAIN) in place of WIA.
4. Swap `NAPS2.Images.Wpf` for an image package that works on Mac (for example `NAPS2.Images.ImageSharp`), and replace Windows-only calls such as the shell open.
5. Package and sign the app for macOS (an unsigned app triggers Gatekeeper warnings).

Status: not started.

## Credits and licenses

ScanDesk is released under the [MIT License](LICENSE).

It depends on:

- [NAPS2.Sdk](https://github.com/cyanfish/naps2): the SDK and image packages are LGPL 2.1 or later. They are used here as unmodified NuGet packages; keep that in mind if you redistribute binaries.
- [Tesseract OCR](https://github.com/tesseract-ocr/tesseract) and `tessdata`: Apache 2.0.

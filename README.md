# ScanDesk

A small desktop app for scanning paper documents to PDF. Pick a scanner, scan one or more pages, review them, and save a single PDF with a searchable text layer (OCR).

There are two versions:

| | Windows | macOS |
| --- | --- | --- |
| Folder | repository root | [`macOS/`](macOS) |
| Built with | WPF on .NET 10 | SwiftUI, with Liquid Glass |
| Scanning | WIA and TWAIN through the [NAPS2 SDK](https://www.naps2.com/sdk/doc/) | Apple ImageCaptureCore (USB and AirScan/network scanners) |
| OCR | Tesseract (English) | Apple Vision (detects the language) |
| Requires | Windows 10 or 11, x64 | macOS 26 Tahoe or later |

Both follow the same flow and have the same options: one- or two-sided, color mode, resolution, paper size, skip blank pages, straighten, OCR, save folder, file name, auto-save and open after saving.

# Windows

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

# macOS

A native SwiftUI app in [`macOS/`](macOS). It follows Apple's Liquid Glass design for macOS 26:

- **Sidebar and toolbar** use the system's standard components, so macOS draws them as Liquid Glass. The sidebar floats over the window, and toolbar buttons are grouped into shared glass capsules.
- **Scan** is the one prominent (tinted glass) button, as Apple recommends for a view's main action. It turns into a red **Stop** while scanning.
- **The status bar** is a glass capsule floating above the pages, which scroll underneath it.
- **The page grid** is the content layer, so it stays solid and easy to read. Glass is kept to the controls on top, never stacked glass on glass.

## Features

- Finds USB, shared and network (AirScan/eSCL, Bonjour) scanners through Apple's Image Capture. No vendor driver is needed for most AirScan scanners.
- Document feeder (with duplex if the scanner supports it) or flatbed
- Skips blank pages, straightens crooked pages, and can make the PDF searchable with Apple's Vision text recognition
- Click, ⌘-click and ⇧-click to select pages; drag to reorder; rotate, move and delete from the toolbar, the Page menu or a right-click
- **Import from iPhone or iPad** (File menu): scan a document or take a photo with your phone's camera through Continuity Camera
- Drop images or PDFs onto the window, or use File ▸ Add Images or PDFs… (⌘O), to add pages
- PDFs are written to a temporary file first, so a failed save never leaves a broken PDF behind
- Asks before closing or quitting with unsaved pages
- Remembers the last scanner, save folder and options (in the app's preferences)
- Default save folder: `~/Documents/Scans`

Keyboard shortcuts: Scan ⌘R, Stop ⌘., Save PDF ⌘S, Rotate ⌘[ / ⌘], Move earlier/later ⌥⌘← / ⌥⌘→, Delete ⌘⌫.

## Requirements

- macOS 26 Tahoe or later (Liquid Glass needs it), Apple silicon or Intel
- A scanner that shows up in macOS's Image Capture app
- To build: Xcode 26 or later

## Build and run

Open `macOS/ScanDesk.xcodeproj` in Xcode and press Run, or from Terminal:

```bash
cd macOS
xcodebuild -project ScanDesk.xcodeproj -scheme ScanDesk -configuration Release -derivedDataPath build build
open build/Build/Products/Release/ScanDesk.app
```

The project is generated from `macOS/project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen). You only need XcodeGen if you change project settings (run `xcodegen` in `macOS/`). New Swift files must also be added by running `xcodegen` again.

The app isn't sandboxed (so it can save straight into any folder you pick, like the Windows version). It's built with the hardened runtime, so it can be signed with a Developer ID and notarized for sharing. Unsigned builds trigger Gatekeeper warnings on other Macs.

## Project layout

| Path | Purpose |
| --- | --- |
| `macOS/ScanDesk/ScanDeskApp.swift` | App, window, menu commands, unsaved-pages prompt |
| `macOS/ScanDesk/ContentView.swift` | Window layout and toolbar |
| `macOS/ScanDesk/SidebarView.swift` | Scanner and option controls |
| `macOS/ScanDesk/PagesView.swift` | Page grid, selection, drag to reorder, drop and iPhone import |
| `macOS/ScanDesk/StatusBar.swift` | Floating glass status bar |
| `macOS/ScanDesk/ScanModel.swift` | App state and actions (the equivalent of `MainWindow.xaml.cs`) |
| `macOS/ScanDesk/ScannerService.swift` | Scanner discovery and scanning with ImageCaptureCore |
| `macOS/ScanDesk/PageProcessing.swift` | Blank-page detection, straightening, rotation, thumbnails, importing |
| `macOS/ScanDesk/PDFWriter.swift` | PDF export with the invisible OCR text layer |
| `macOS/ScanDesk/Settings.swift` | Saved options |

## Credits and licenses

ScanDesk is released under the [MIT License](LICENSE).

The Windows version depends on:

- [NAPS2.Sdk](https://github.com/cyanfish/naps2): the SDK and image packages are LGPL 2.1 or later. They are used here as unmodified NuGet packages; keep that in mind if you redistribute binaries.
- [Tesseract OCR](https://github.com/tesseract-ocr/tesseract) and `tessdata`: Apache 2.0.

The macOS version uses only Apple's system frameworks (SwiftUI, ImageCaptureCore, Vision, Core Graphics, PDFKit).

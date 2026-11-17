import AppKit
import Observation
import UniformTypeIdentifiers

/// One page in the current batch.
struct ScannedPage: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var quarterTurns = 0          // clockwise
    var thumbnail: CGImage

    static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.quarterTurns == b.quarterTurns }
}

struct StatusMessage: Equatable {
    enum Kind { case ready, busy, error, success }
    var text: String
    var kind: Kind
}

/// Everything the window shows, and the actions behind the toolbar and menu commands.
/// Same flow as MainWindow.xaml.cs in the Windows version.
@Observable
final class ScanModel {
    var settings = AppSettings.load() { didSet { if settings != oldValue { settings.save() } } }
    var pages: [ScannedPage] = []
    var selection: Set<ScannedPage.ID> = []
    var fileName = ""
    private(set) var status = StatusMessage(text: "Looking for scanners…", kind: .busy)
    /// 0…1 while saving; nil when the work has no measurable progress.
    private(set) var progress: Double?
    private(set) var isScanning = false
    private(set) var isSaving = false
    private(set) var lastPDF: URL?

    let scanner = ScannerService()
    @ObservationIgnored private let workFolder: URL
    @ObservationIgnored private var pageChain: Task<Void, Never>?
    @ObservationIgnored private var stopRequested = false

    /// Set once the user agrees to lose unsaved pages, so closing and quitting don't ask twice.
    @ObservationIgnored var closeConfirmed = false

    var isBusy: Bool { isScanning || isSaving }
    var hasUnsavedPages: Bool { !pages.isEmpty }

    init() {
        workFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScanDesk-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? FileManager.default.createDirectory(at: workFolder, withIntermediateDirectories: true)
    }

    // MARK: Scanners

    var selectedScanner: ScannerChoice? {
        scanner.scanners.first { $0.key == settings.deviceKey } ?? scanner.scanners.first
    }

    func refreshScanners() {
        setStatus("Looking for scanners…", .busy)
        scanner.refresh()
        Task {
            while scanner.isSearching { try? await Task.sleep(for: .milliseconds(250)) }
            guard !isBusy else { return }
            let n = scanner.scanners.count
            if n == 0 {
                setStatus("No scanner found. Check that the scanner is on and connected, then press Refresh. You can also drop images or PDFs here.", .error)
            } else {
                if settings.deviceKey == nil || !scanner.scanners.contains(where: { $0.key == settings.deviceKey }) {
                    settings.deviceKey = scanner.scanners.first?.key
                }
                setStatus("Ready — \(n) scanner\(n == 1 ? "" : "s") found. Load the feeder and press Scan.", .ready)
            }
        }
    }

    // MARK: Scanning

    func scan() async {
        guard !isBusy else { return }
        guard let choice = selectedScanner else {
            setStatus(ScanError.noScanner.localizedDescription, .error)
            return
        }
        let before = pages.count
        let s = settings
        let request = ScanRequest(source: s.source, twoSided: s.twoSided, colorMode: s.colorMode, dpi: s.dpi, paper: s.paper)
        isScanning = true
        stopRequested = false
        progress = nil
        setStatus(s.source == .feeder ? "Scanning… (feeding pages)" : "Scanning…", .busy)

        var failure: String?
        do {
            try await scanner.scan(with: choice, request: request, into: workFolder) { [weak self] url in
                self?.enqueueScannedPage(url, settings: s, batchStart: before)
            }
        } catch is CancellationError {
            // Stopped by the user; pages already scanned are kept.
        } catch {
            failure = error.localizedDescription
        }
        await pageChain?.value          // let the last pages finish processing

        isScanning = false
        let added = pages.count - before
        if let failure {
            setStatus(added > 0 ? "\(failure) \(added) page\(added == 1 ? "" : "s") kept." : failure, .error)
        } else if stopRequested {
            setStatus("Scan stopped. \(added) page\(added == 1 ? "" : "s") kept.", .ready)
        } else if added == 0 {
            setStatus("No pages came through. Is paper loaded face-up in the document feeder?", .error)
        } else {
            setStatus("Added \(added) page\(added == 1 ? "" : "s"). \(pages.count) total — scan more, or press Save PDF.", .ready)
        }

        if settings.autoSave && added > 0 && failure == nil {
            await save()
        }
    }

    func stop() {
        stopRequested = true
        scanner.cancel()
        setStatus("Stopping after the current page…", .busy)
    }

    /// Pages are cleaned up one at a time, in order, while the scanner keeps feeding.
    private func enqueueScannedPage(_ url: URL, settings s: AppSettings, batchStart: Int) {
        let previous = pageChain
        let work = workFolder
        pageChain = Task {
            await previous?.value
            let processed = await Task.detached(priority: .userInitiated) {
                PageProcessor.processScannedPage(at: url, workFolder: work, skipBlank: s.skipBlank, deskew: s.deskew, dpi: s.dpi)
            }.value
            if let processed {
                pages.append(ScannedPage(url: processed.url, thumbnail: processed.thumbnail))
            }
            if isScanning {
                let n = pages.count - batchStart
                setStatus("Scanning… \(n) page\(n == 1 ? "" : "s") this batch", .busy)
            }
        }
    }

    // MARK: Importing

    static let importableTypes: [UTType] = [.image, .pdf]

    /// Adds images or PDFs from Finder, the Add Files panel, or Continuity Camera.
    func importFiles(_ urls: [URL]) async {
        guard !isBusy, !urls.isEmpty else { return }
        let work = workFolder
        setStatus("Adding \(urls.count) file\(urls.count == 1 ? "" : "s")…", .busy)
        var added = 0
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            let processed = await Task.detached(priority: .userInitiated) {
                PageProcessor.importFile(url, workFolder: work)
            }.value
            if access { url.stopAccessingSecurityScopedResource() }
            for p in processed { pages.append(ScannedPage(url: p.url, thumbnail: p.thumbnail)) }
            added += processed.count
        }
        if added == 0 {
            setStatus("Those files couldn't be added. Use images (JPEG, PNG, HEIC, TIFF) or PDFs.", .error)
        } else {
            setStatus("Added \(added) page\(added == 1 ? "" : "s"). \(pages.count) total — scan more, or press Save PDF.", .ready)
        }
    }

    /// Continuity Camera (File ▸ Import from iPhone or iPad) hands over item providers.
    func importItemProviders(_ providers: [NSItemProvider]) async {
        var urls: [URL] = []
        for provider in providers {
            guard let type = Self.importableTypes.first(where: { t in provider.registeredContentTypes.contains { $0.conforms(to: t) } })
                    .flatMap({ t in provider.registeredContentTypes.first { $0.conforms(to: t) } })
            else { continue }
            let dest = workFolder.appendingPathComponent("import-\(UUID().uuidString)")
                .appendingPathExtension(type.preferredFilenameExtension ?? "dat")
            let ok: Bool = await withCheckedContinuation { c in
                _ = provider.loadFileRepresentation(for: type, openInPlace: false) { url, _, _ in
                    guard let url else { c.resume(returning: false); return }
                    c.resume(returning: (try? FileManager.default.copyItem(at: url, to: dest)) != nil)
                }
            }
            if ok { urls.append(dest) }
        }
        await importFiles(urls)
    }

    // MARK: Saving

    func save() async {
        guard !isBusy else { return }
        guard !pages.isEmpty else {
            setStatus("Nothing to save yet — scan some pages first.", .error)
            return
        }
        let folderPath = settings.saveFolder.trimmingCharacters(in: .whitespaces)
        guard !folderPath.isEmpty else {
            setStatus("Choose a folder to save into (Choose…).", .error)
            return
        }
        let folder = URL(fileURLWithPath: (folderPath as NSString).expandingTildeInPath, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            setStatus("Can't use that folder: \(error.localizedDescription)", .error)
            return
        }

        var base = Self.safeFileName(fileName)
        if base.isEmpty { base = "Scan \(Self.timestamp())" }
        let destination = Self.uniqueURL(folder.appendingPathComponent(base).appendingPathExtension("pdf"))

        let sources = pages.map { PDFPageSource(url: $0.url, quarterTurns: $0.quarterTurns) }
        let total = sources.count
        let ocr = settings.ocr
        isSaving = true
        progress = 0
        setStatus(ocr ? "Reading text (OCR) and saving \(total) page\(total == 1 ? "" : "s")…" : "Saving \(total) page\(total == 1 ? "" : "s")…", .busy)

        do {
            try await Task.detached(priority: .userInitiated) { [weak self] in
                try PDFWriter.write(pages: sources, to: destination, ocr: ocr) { current, max in
                    Task { @MainActor in
                        guard let self, self.isSaving else { return }
                        self.progress = Double(current) / Double(Swift.max(max, 1))
                        let n = Swift.min(current + 1, max)
                        self.setStatus(ocr ? "Reading text and saving… page \(n) of \(max)" : "Saving… page \(n) of \(max)", .busy)
                    }
                }
            }.value

            isSaving = false
            progress = nil
            lastPDF = destination
            removeAllPages()
            fileName = ""
            setStatus("Saved \(total) page\(total == 1 ? "" : "s") to \(Self.displayPath(destination))", .success)
            if settings.openAfterSave { NSWorkspace.shared.open(destination) }
        } catch {
            isSaving = false
            progress = nil
            setStatus("Couldn't save the PDF: \(error.localizedDescription)", .error)
        }
    }

    func openLastPDF() {
        if let lastPDF, FileManager.default.fileExists(atPath: lastPDF.path) { NSWorkspace.shared.open(lastPDF) }
    }

    func revealSaveFolder() {
        let folder = URL(fileURLWithPath: (settings.saveFolder as NSString).expandingTildeInPath, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if let lastPDF, lastPDF.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL,
               FileManager.default.fileExists(atPath: lastPDF.path) {
                NSWorkspace.shared.activateFileViewerSelecting([lastPDF])
            } else {
                NSWorkspace.shared.open(folder)
            }
        } catch {
            setStatus("Can't open that folder: \(error.localizedDescription)", .error)
        }
    }

    // MARK: Page editing

    private var selectedIndices: [Int] {
        pages.indices.filter { selection.contains(pages[$0].id) }
    }

    var canEditSelection: Bool { !selection.isEmpty && !isSaving }
    var canMoveSelection: Bool { selection.count == 1 && !isSaving }

    func rotateSelection(clockwise: Bool) {
        for i in selectedIndices {
            pages[i].quarterTurns = (pages[i].quarterTurns + (clockwise ? 1 : 3)) % 4
            pages[i].thumbnail = PageProcessor.rotate(pages[i].thumbnail, quarterTurns: clockwise ? 1 : 3)
        }
    }

    func deleteSelection() {
        let idx = selectedIndices
        guard let first = idx.first else { return }
        for i in idx.reversed() {
            try? FileManager.default.removeItem(at: pages[i].url)
            pages.remove(at: i)
        }
        selection = pages.isEmpty ? [] : [pages[min(first, pages.count - 1)].id]
        setStatus("Deleted \(idx.count) page\(idx.count == 1 ? "" : "s"). \(pages.count) left.", .ready)
    }

    func moveSelection(by delta: Int) {
        guard selection.count == 1, let i = selectedIndices.first else { return }
        let j = i + delta
        guard pages.indices.contains(j) else { return }
        pages.swapAt(i, j)
    }

    /// Drag-and-drop reordering in the page grid.
    func move(pageID: ScannedPage.ID, before targetID: ScannedPage.ID) {
        guard pageID != targetID,
              let from = pages.firstIndex(where: { $0.id == pageID }),
              let to = pages.firstIndex(where: { $0.id == targetID }) else { return }
        let page = pages.remove(at: from)
        pages.insert(page, at: to)
    }

    func clearAll() {
        removeAllPages()
        setStatus("Cleared. Ready for the next document.", .ready)
    }

    private func removeAllPages() {
        for p in pages { try? FileManager.default.removeItem(at: p.url) }
        pages.removeAll()
        selection.removeAll()
    }

    /// Called when the app quits.
    func cleanUp() {
        scanner.cancel()
        try? FileManager.default.removeItem(at: workFolder)
    }

    // MARK: Helpers

    private func setStatus(_ text: String, _ kind: StatusMessage.Kind) {
        status = StatusMessage(text: text, kind: kind)
    }

    static func safeFileName(_ name: String) -> String {
        var n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.lowercased().hasSuffix(".pdf") { n.removeLast(4) }
        n = n.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        while n.hasPrefix(".") { n.removeFirst() }
        return n.trimmingCharacters(in: .whitespaces)
    }

    static func uniqueURL(_ url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent(), stem = url.deletingPathExtension().lastPathComponent
        var i = 2
        while true {
            let candidate = dir.appendingPathComponent("\(stem) (\(i)).pdf")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }

    static func timestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HHmmss"
        return f.string(from: .now)
    }

    static func displayPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}

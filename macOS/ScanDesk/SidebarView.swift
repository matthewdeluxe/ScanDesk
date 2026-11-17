import SwiftUI

/// Scan options as big colored tiles, like the Windows version. The sidebar itself is drawn by
/// macOS as a floating Liquid Glass panel; the tiles inside use solid color, not more glass.
struct SidebarView: View {
    @Bindable var model: ScanModel
    @State private var choosingFolder = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header

                SectionTitle(title: "Scanner", systemImage: "scanner.fill", color: Palette.indigo)
                scannerPicker
                TileRow {
                    tile("Feeder", "Stack of pages", "tray.and.arrow.down.fill", Palette.indigo,
                         model.settings.source == .feeder, compact: true) { model.settings.source = .feeder }
                    tile("Flatbed", "One page on the glass", "rectangle.portrait.on.rectangle.portrait.fill", Palette.indigo,
                         model.settings.source == .flatbed, compact: true) { model.settings.source = .flatbed }
                }

                SectionTitle(title: "Sides", systemImage: "doc.on.doc.fill", color: Palette.sky)
                TileRow {
                    tile("One-Sided", "Front only", "doc", Palette.sky, !model.settings.twoSided) { model.settings.twoSided = false }
                    tile("Two-Sided", "Front and back", "doc.on.doc", Palette.sky, model.settings.twoSided) { model.settings.twoSided = true }
                }
                .disabled(model.settings.source == .flatbed)

                SectionTitle(title: "Color", systemImage: "paintpalette.fill", color: Palette.pink)
                TileRow {
                    tile("Color", "Photos, forms", "paintpalette", Palette.pink, model.settings.colorMode == .color) { model.settings.colorMode = .color }
                    tile("Grayscale", "Shades of gray", "circle.lefthalf.filled", Palette.violet, model.settings.colorMode == .gray) { model.settings.colorMode = .gray }
                    tile("B & W", "Text, smallest", "textformat", Palette.slate, model.settings.colorMode == .blackAndWhite) { model.settings.colorMode = .blackAndWhite }
                }

                SectionTitle(title: "Resolution & Paper", systemImage: "ruler.fill", color: Palette.teal)
                TileRow {
                    tile("200 dpi", "Fast", "hare", Palette.teal, model.settings.dpi == 200, compact: true) { model.settings.dpi = 200 }
                    tile("300 dpi", "Recommended", "star", Palette.teal, model.settings.dpi == 300, compact: true) { model.settings.dpi = 300 }
                    tile("600 dpi", "Fine detail", "plus.magnifyingglass", Palette.teal, model.settings.dpi == 600, compact: true) { model.settings.dpi = 600 }
                }
                TileRow {
                    tile("Letter", "8.5 × 11 in", "doc.plaintext", Palette.blue, model.settings.paper == .letter, compact: true) { model.settings.paper = .letter }
                    tile("Legal", "8.5 × 14 in", "doc.text", Palette.blue, model.settings.paper == .legal, compact: true) { model.settings.paper = .legal }
                }

                SectionTitle(title: "Clean Up", systemImage: "sparkles", color: Palette.orange)
                TileRow {
                    tile("Skip Blanks", "Drop empty backs", "eye.slash", Palette.orange, model.settings.skipBlank) { model.settings.skipBlank.toggle() }
                    tile("Straighten", "Fix crooked pages", "level", Palette.amber, model.settings.deskew) { model.settings.deskew.toggle() }
                    tile("OCR", "Searchable text", "text.viewfinder", Palette.green, model.settings.ocr) { model.settings.ocr.toggle() }
                }

                SectionTitle(title: "Save To", systemImage: "folder.fill", color: Palette.violet)
                saveSection
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.automatic)
        .disabled(model.isBusy)
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.settings.saveFolder = url.path }
        }
        .fileDialogMessage("Choose where to save your scans")
    }

    /// App icon, name and tagline, like the Windows header.
    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("ScanDesk")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(LinearGradient(colors: Palette.header, startPoint: .leading, endPoint: .trailing))
                Text("Feed it, scan it, file it")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    private var scannerPicker: some View {
        HStack(spacing: 8) {
            Picker("Scanner", selection: deviceBinding) {
                if model.scanner.scanners.isEmpty {
                    Text(model.scanner.isSearching ? "Searching…" : "No scanner found").tag(String?.none)
                }
                ForEach(model.scanner.scanners) { s in
                    Text("\(s.name) (\(s.connection))").tag(Optional(s.key))
                }
            }
            .labelsHidden()
            .controlSize(.large)
            .disabled(model.scanner.scanners.isEmpty)

            Button {
                model.refreshScanners()
            } label: {
                if model.scanner.isSearching {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .controlSize(.large)
            .help("Look for scanners again")
            .disabled(model.scanner.isSearching)
        }
    }

    private var saveSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill").foregroundStyle(Palette.violet)
                Text(ScanModel.displayPath(URL(fileURLWithPath: model.settings.saveFolder)))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(model.settings.saveFolder)
                Spacer(minLength: 0)
            }
            .font(.callout)

            HStack {
                Button("Choose…", systemImage: "folder.badge.gearshape") { choosingFolder = true }
                    .tint(Palette.violet)
                Button("Show in Finder", systemImage: "arrow.up.forward.app") { model.revealSaveFolder() }
                    .tint(Palette.indigo)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            HStack(spacing: 4) {
                TextField("File name", text: $model.fileName, prompt: Text("Scan date and time"))
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                Text(".pdf").foregroundStyle(.secondary)
            }
            .help("Leave blank to name the file by date and time")

            TileRow {
                tile("Auto-save", "When the feeder empties", "bolt.fill", Palette.blue, model.settings.autoSave, compact: true) {
                    model.settings.autoSave.toggle()
                }
                tile("Open After", "Show the PDF", "doc.richtext", Palette.indigo, model.settings.openAfterSave, compact: true) {
                    model.settings.openAfterSave.toggle()
                }
            }
        }
    }

    private func tile(_ title: String, _ subtitle: String, _ icon: String, _ accent: Color, _ isOn: Bool,
                      compact: Bool = false, action: @escaping () -> Void) -> some View {
        OptionTile(title: title, subtitle: subtitle, systemImage: icon, accent: accent, isOn: isOn, compact: compact, action: action)
    }

    private var deviceBinding: Binding<String?> {
        Binding(get: { model.selectedScanner?.key }, set: { model.settings.deviceKey = $0 })
    }
}

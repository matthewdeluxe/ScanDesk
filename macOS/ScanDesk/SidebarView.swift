import SwiftUI

/// Scan options. Standard controls in a sidebar list, so macOS draws the sidebar as a floating
/// Liquid Glass panel and the controls pick up their glass styling automatically.
struct SidebarView: View {
    @Bindable var model: ScanModel
    @State private var choosingFolder = false

    var body: some View {
        List {
            Section("Scanner") {
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
                    .help("Look for scanners again")
                    .disabled(model.scanner.isSearching)
                }

                Picker("Source", selection: $model.settings.source) {
                    ForEach(ScanSource.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Sides") {
                Picker("Sides", selection: $model.settings.twoSided) {
                    Label("One-Sided", systemImage: "doc").tag(false)
                    Label("Two-Sided", systemImage: "doc.on.doc").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(model.settings.source == .flatbed)
            }

            Section("Color") {
                Picker("Color", selection: $model.settings.colorMode) {
                    ForEach(ColorMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(model.settings.colorMode.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Resolution & Paper") {
                Picker("Resolution", selection: $model.settings.dpi) {
                    Text("200 dpi").tag(200)
                    Text("300 dpi").tag(300)
                    Text("600 dpi").tag(600)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(model.settings.dpi == 200 ? "Fast" : model.settings.dpi == 600 ? "Fine detail" : "Recommended")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Paper", selection: $model.settings.paper) {
                    ForEach(PaperSize.allCases) { p in Text("\(p.title)  \(p.detail)").tag(p) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section("Clean Up") {
                Toggle(isOn: $model.settings.skipBlank) {
                    Label("Skip blank pages", systemImage: "doc.badge.ellipsis")
                }
                Toggle(isOn: $model.settings.deskew) {
                    Label("Straighten pages", systemImage: "rectangle.rotate")
                }
                Toggle(isOn: $model.settings.ocr) {
                    Label("Make text searchable (OCR)", systemImage: "text.viewfinder")
                }
            }
            .toggleStyle(.switch)

            Section("Save To") {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill").foregroundStyle(.tint)
                    Text(ScanModel.displayPath(URL(fileURLWithPath: model.settings.saveFolder)))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(model.settings.saveFolder)
                    Spacer(minLength: 0)
                }
                HStack {
                    Button("Choose…") { choosingFolder = true }
                    Button("Show in Finder") { model.revealSaveFolder() }
                }
                .controlSize(.small)

                HStack(spacing: 4) {
                    TextField("File name", text: $model.fileName, prompt: Text("Scan date and time"))
                        .textFieldStyle(.roundedBorder)
                    Text(".pdf").foregroundStyle(.secondary)
                }
                .help("Leave blank to name the file by date and time")

                Toggle("Save automatically after scanning", isOn: $model.settings.autoSave)
                Toggle("Open the PDF after saving", isOn: $model.settings.openAfterSave)
            }
            .toggleStyle(.switch)
        }
        .listStyle(.sidebar)
        .disabled(model.isBusy)
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.settings.saveFolder = url.path }
        }
        .fileDialogMessage("Choose where to save your scans")
    }

    private var deviceBinding: Binding<String?> {
        Binding(get: { model.selectedScanner?.key }, set: { model.settings.deviceKey = $0 })
    }
}

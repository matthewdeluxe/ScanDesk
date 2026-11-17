import SwiftUI

struct ContentView: View {
    @Bindable var model: ScanModel
    @State private var confirmingClear = false
    @State private var importing = false

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 290, ideal: 320, max: 400)
        } detail: {
            PagesView(model: model)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    StatusBar(model: model)
                }
        }
        .navigationTitle("ScanDesk")
        .navigationSubtitle(subtitle)
        .toolbar { toolbar }
        .confirmationDialog("Remove all \(model.pages.count) scanned pages without saving?",
                            isPresented: $confirmingClear) {
            Button("Remove Pages", role: .destructive) { model.clearAll() }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: ScanModel.importableTypes,
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { Task { await model.importFiles(urls) } }
        }
        .focusedSceneValue(\.scanActions, ScanActions(model: model,
                                                      clear: { confirmingClear = true },
                                                      addFiles: { importing = true }))
        .task { model.refreshScanners() }
    }

    private var subtitle: String {
        model.pages.isEmpty ? "Feed it, scan it, file it"
            : "\(model.pages.count) page\(model.pages.count == 1 ? "" : "s")"
    }

    /// Toolbar items are drawn on Liquid Glass automatically. Related buttons are grouped so they
    /// share one glass capsule, and the main action (Scan) uses the prominent glass style.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button("Move Earlier", systemImage: "arrow.left") { model.moveSelection(by: -1) }
                .help("Move the selected page earlier")
                .disabled(!model.canMoveSelection)
            Button("Move Later", systemImage: "arrow.right") { model.moveSelection(by: 1) }
                .help("Move the selected page later")
                .disabled(!model.canMoveSelection)
        }

        ToolbarSpacer(.fixed)

        ToolbarItemGroup {
            Button("Rotate Left", systemImage: "rotate.left") { model.rotateSelection(clockwise: false) }
                .help("Rotate the selected pages left")
                .disabled(!model.canEditSelection)
            Button("Rotate Right", systemImage: "rotate.right") { model.rotateSelection(clockwise: true) }
                .help("Rotate the selected pages right")
                .disabled(!model.canEditSelection)
            Button("Delete", systemImage: "trash") { model.deleteSelection() }
                .help("Delete the selected pages")
                .disabled(!model.canEditSelection)
        }

        ToolbarSpacer(.fixed)

        ToolbarItemGroup {
            Button("Clear", systemImage: "xmark.bin") { confirmingClear = true }
                .help("Remove all pages and start over")
                .disabled(model.pages.isEmpty || model.isBusy)
            Button("Save PDF", systemImage: "square.and.arrow.down") { Task { await model.save() } }
                .help("Save all pages as one PDF")
                .disabled(model.pages.isEmpty || model.isBusy)
        }

        ToolbarSpacer(.fixed)

        ToolbarItem {
            if model.isScanning {
                Button("Stop", systemImage: "stop.fill") { model.stop() }
                    .buttonStyle(.glassProminent)
                    .tint(.red)
                    .help("Stop after the current page")
            } else {
                Button("Scan", systemImage: "scanner") { Task { await model.scan() } }
                    .buttonStyle(.glassProminent)
                    .tint(.green)
                    .help("Scan everything in the feeder")
                    .disabled(model.isBusy || model.selectedScanner == nil)
            }
        }
    }
}

/// Lets the menu bar commands reach the window's model.
struct ScanActions {
    let model: ScanModel
    let clear: () -> Void
    let addFiles: () -> Void
}

extension FocusedValues {
    @Entry var scanActions: ScanActions?
}

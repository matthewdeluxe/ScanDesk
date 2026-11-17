import SwiftUI

struct ContentView: View {
    @Bindable var model: ScanModel
    @State private var confirmingClear = false
    @State private var importing = false

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 340, ideal: 370, max: 440)
        } detail: {
            PagesView(model: model)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    BottomBar(model: model, clear: { confirmingClear = true })
                }
        }
        .tint(Palette.violet)   // the Windows version's selection and focus color
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

    /// Toolbar items are drawn on Liquid Glass automatically. Related page tools share one glass
    /// capsule. The big actions (Scan, Save PDF, Clear) float at the bottom instead, like the Windows version.
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
        }

        ToolbarSpacer(.fixed)

        ToolbarItem {
            Button("Delete Page", systemImage: "trash") { model.deleteSelection() }
                .help("Delete the selected pages")
                .disabled(!model.canEditSelection)
        }

        ToolbarSpacer(.flexible)

        ToolbarItem {
            Button("Add Images or PDFs", systemImage: "photo.badge.plus") { importing = true }
                .help("Add images or PDFs as pages")
                .disabled(model.isBusy)
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

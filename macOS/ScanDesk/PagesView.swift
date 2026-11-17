import SwiftUI
import UniformTypeIdentifiers

/// The page grid. This is the content layer, so it stays solid (no glass) for legibility;
/// glass is reserved for the controls that float above it.
struct PagesView: View {
    @Bindable var model: ScanModel
    @State private var anchor: ScannedPage.ID?
    @State private var dropTargeted = false

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 20)]

    var body: some View {
        Group {
            if model.pages.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, page in
                            PageTile(page: page, number: index + 1, isSelected: model.selection.contains(page.id))
                                .onTapGesture { select(page.id) }
                                .contextMenu { contextMenu(for: page.id) }
                                .draggable(page.id.uuidString) {
                                    Image(decorative: page.thumbnail, scale: 3).clipShape(.rect(cornerRadius: 6))
                                }
                                .dropDestination(for: String.self) { items, _ in
                                    guard let s = items.first, let id = UUID(uuidString: s) else { return false }
                                    withAnimation(.snappy) { model.move(pageID: id, before: page.id) }
                                    return true
                                }
                        }
                    }
                    .padding(24)
                    .animation(.snappy, value: model.pages)
                }
                .contentShape(.rect)
                .onTapGesture { model.selection.removeAll() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.tint, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            Task { await model.importFiles(urls) }
            return !urls.isEmpty
        } isTargeted: { dropTargeted = $0 }
        // Continuity Camera: File ▸ Import from iPhone or iPad ▸ Scan Documents / Take Photo.
        .importsItemProviders(ScanModel.importableTypes) { providers in
            Task { await model.importItemProviders(providers) }
            return true
        }
        .onDeleteCommand { model.deleteSelection() }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Put your pages in the scanner", systemImage: "doc.viewfinder")
        } description: {
            Text("Load them face-up in the document feeder, then press Scan. Scan again to add more pages to the same PDF.\nYou can also drop images or PDFs here, or use File ▸ Import from iPhone.")
        } actions: {
            Button {
                Task { await model.scan() }
            } label: {
                Label("Scan", systemImage: "scanner")
                    .padding(.horizontal, 18)
            }
            .buttonStyle(.glassProminent)
            .tint(.green)
            .controlSize(.extraLarge)
            .disabled(model.isBusy || model.selectedScanner == nil)
        }
    }

    /// Right-clicking a page outside the selection acts on just that page, like Finder.
    @ViewBuilder
    private func contextMenu(for id: ScannedPage.ID) -> some View {
        let single = !model.selection.contains(id) || model.selection.count == 1
        Button("Rotate Left", systemImage: "rotate.left") { target(id); model.rotateSelection(clockwise: false) }
        Button("Rotate Right", systemImage: "rotate.right") { target(id); model.rotateSelection(clockwise: true) }
        Divider()
        Button("Move Earlier", systemImage: "arrow.left") { target(id); model.moveSelection(by: -1) }
            .disabled(!single || model.isSaving)
        Button("Move Later", systemImage: "arrow.right") { target(id); model.moveSelection(by: 1) }
            .disabled(!single || model.isSaving)
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { target(id); model.deleteSelection() }
    }

    private func target(_ id: ScannedPage.ID) {
        if !model.selection.contains(id) { model.selection = [id] }
    }

    /// Click selects one page, ⌘-click toggles, ⇧-click selects a range — like Finder.
    private func select(_ id: ScannedPage.ID) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if model.selection.contains(id) { model.selection.remove(id) } else { model.selection.insert(id) }
            anchor = id
        } else if flags.contains(.shift), let anchor,
                  let a = model.pages.firstIndex(where: { $0.id == anchor }),
                  let b = model.pages.firstIndex(where: { $0.id == id }) {
            model.selection = Set(model.pages[min(a, b)...max(a, b)].map(\.id))
        } else {
            model.selection = [id]
            anchor = id
        }
    }
}

private struct PageTile: View {
    let page: ScannedPage
    let number: Int
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(decorative: page.thumbnail, scale: 1)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 220)
                .background(.white)
                .clipShape(.rect(cornerRadius: 6))
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isSelected ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.clear))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 3)
                }

            Text("Page \(number)")
                .font(.callout.weight(.semibold))
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(number)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

import SwiftUI
import UniformTypeIdentifiers

/// The page grid. This is the content layer, so it stays solid (no glass) for legibility;
/// glass is reserved for the controls that float above it. Behind it is a soft version of the
/// Windows header gradient, which also shows through the glass sidebar and toolbar.
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
        .background { Backdrop() }
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
        VStack(spacing: 14) {
            Image(systemName: "doc.viewfinder.fill")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(LinearGradient(colors: Palette.header, startPoint: .topLeading, endPoint: .bottomTrailing))
                .symbolEffect(.pulse, options: .repeat(2))
                .accessibilityHidden(true)
            Text("Put your pages face-up in the document feeder")
                .font(.title2.weight(.bold))
            Text("then press the green SCAN button. Scan again to add more pages to the same PDF.\nYou can also drop images or PDFs here, or use File ▸ Import from iPhone.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(40)
        .frame(maxWidth: 560)
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
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 8) {
            Image(decorative: page.thumbnail, scale: 1)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 220)
                .background(.white)
                .clipShape(.rect(cornerRadius: 6))
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)

            Text("Page \(number)")
                .font(.callout.weight(.semibold))
                .foregroundStyle(isSelected ? AnyShapeStyle(Palette.violet) : AnyShapeStyle(.primary))
        }
        // White card like the Windows page list; violet when selected.
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(Palette.violet.opacity(0.14)) : AnyShapeStyle(.background))
                .shadow(color: .black.opacity(hovering ? 0.16 : 0.08), radius: hovering ? 10 : 6, y: hovering ? 4 : 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isSelected ? Palette.violet : .clear, lineWidth: 3)
        }
        .scaleEffect(hovering ? 1.015 : 1)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(number)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// The Windows header gradient as a soft wash at the top of the page area, extended under the
/// sidebar so the glass picks up its color. Pages sit on solid white cards above it.
private struct Backdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .top) {
            (scheme == .dark ? Color(white: 0.11) : Color(hex: 0xEEF2FA))
            LinearGradient(colors: Palette.header, startPoint: .leading, endPoint: .trailing)
                .opacity(scheme == .dark ? 0.45 : 0.38)
                .frame(height: 320)
                .mask(LinearGradient(colors: [.black, .black.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom))
        }
        .ignoresSafeArea()
        .backgroundExtensionEffect()
    }
}

import SwiftUI

/// Floating controls at the bottom of the window: the status line and the big SCAN / Save PDF /
/// Clear buttons from the Windows version, as tinted Liquid Glass. They sit above the page grid,
/// which scrolls underneath them, and share one glass container so Scan and Stop morph into each other.
struct BottomBar: View {
    let model: ScanModel
    let clear: () -> Void
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 10) {
                status
                actions
            }
        }
        .frame(maxWidth: 820)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .animation(.smooth, value: model.isScanning)
        .animation(.smooth, value: model.lastPDF)
    }

    private var status: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: statusColor.opacity(0.6), radius: 3)
                    .accessibilityHidden(true)
                Text(model.status.text)
                    .font(.callout)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .contentTransition(.opacity)
                    .animation(.default, value: model.status)
                if model.status.kind == .busy {
                    if let p = model.progress {
                        ProgressView(value: p).frame(width: 140).tint(Palette.violet)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: .capsule)

            if model.lastPDF != nil && !model.isBusy {
                Button {
                    model.openLastPDF()
                } label: {
                    Label("Open Last PDF", systemImage: "doc.richtext")
                        .padding(.vertical, 3)
                }
                .buttonStyle(.glass)
                .tint(Palette.blue)
                .help("Open the PDF you just saved")
                .glassEffectID("open", in: glass)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Group {
                if model.isScanning {
                    BigActionButton(title: "STOP", subtitle: "Stop after this page", systemImage: "stop.fill",
                                    colors: Palette.stop, prominent: true) { model.stop() }
                } else {
                    BigActionButton(title: "SCAN", subtitle: model.settings.source == .feeder
                                        ? "Scan everything in the feeder" : "Scan the page on the glass",
                                    systemImage: "scanner.fill", colors: Palette.scan, prominent: true) {
                        Task { await model.scan() }
                    }
                    .disabled(model.isBusy || model.selectedScanner == nil)
                }
            }
            .glassEffectID("scan", in: glass)
            .layoutPriority(1.6)

            BigActionButton(title: "Save PDF", subtitle: model.pages.isEmpty ? "Make the PDF" : "\(model.pages.count) page\(model.pages.count == 1 ? "" : "s")",
                            systemImage: "square.and.arrow.down.fill", colors: Palette.save) {
                Task { await model.save() }
            }
            .disabled(model.pages.isEmpty || model.isBusy)
            .glassEffectID("save", in: glass)
            .layoutPriority(1.2)

            BigActionButton(title: "Clear", subtitle: "Start over", systemImage: "trash.fill", colors: Palette.clear) {
                clear()
            }
            .disabled(model.pages.isEmpty || model.isBusy)
            .glassEffectID("clear", in: glass)
            .frame(maxWidth: 200)
        }
    }

    private var statusColor: Color {
        switch model.status.kind {
        case .ready: Palette.green
        case .busy: Palette.amber
        case .error: Palette.rose
        case .success: Palette.blue
        }
    }
}

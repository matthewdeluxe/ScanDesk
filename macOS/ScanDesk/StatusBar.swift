import SwiftUI

/// Floating status capsule at the bottom of the window. It sits above the page grid,
/// so per Apple's Liquid Glass guidance it uses glass, and pages scroll underneath it.
struct StatusBar: View {
    let model: ScanModel

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(color)
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    Text(model.status.text)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .contentTransition(.opacity)
                        .animation(.default, value: model.status)
                    if model.status.kind == .busy {
                        if let p = model.progress {
                            ProgressView(value: p).frame(width: 140)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)

                if model.lastPDF != nil && !model.isBusy {
                    Button {
                        model.openLastPDF()
                    } label: {
                        Label("Open Last PDF", systemImage: "doc.richtext")
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.glass)
                    .help("Open the PDF you just saved")
                    .transition(.blurReplace)
                }
            }
        }
        .animation(.smooth, value: model.lastPDF)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .accessibilityElement(children: .contain)
    }

    private var color: Color {
        switch model.status.kind {
        case .ready: .green
        case .busy: .orange
        case .error: .red
        case .success: .blue
        }
    }
}

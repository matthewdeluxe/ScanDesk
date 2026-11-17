import SwiftUI

/// The Windows version's big selectable tile: icon, title and subtitle, outlined in its accent
/// color, filled with it when chosen. Tiles sit inside the glass sidebar, so they use solid
/// color rather than glass (Apple advises against stacking glass on glass).
struct OptionTile: View {
    let title: String
    var subtitle: String? = nil
    let systemImage: String
    let accent: Color
    let isOn: Bool
    var compact = false
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: compact ? 3 : 5) {
                Image(systemName: systemImage)
                    .font(.system(size: compact ? 18 : 22, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(accent))
                    .frame(height: compact ? 20 : 26)
                Text(title)
                    .font(.system(size: compact ? 12 : 13, weight: .semibold))
                    .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(isOn ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(.secondary))
                }
            }
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 6)
            .padding(.vertical, compact ? 8 : 11)
            .frame(maxWidth: .infinity, minHeight: compact ? 54 : 78)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isOn
                          ? AnyShapeStyle(LinearGradient(colors: [accent, accent.mix(with: .black, by: 0.18)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(accent.opacity(hovering ? 0.16 : 0.08)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(accent.opacity(isOn ? 0 : 0.55), lineWidth: 1.5)
            }
            .overlay(alignment: .topTrailing) {
                if isOn {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(accent, .white)
                        .padding(5)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .shadow(color: accent.opacity(isOn ? 0.35 : 0), radius: 6, y: 3)
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(PressScaleStyle())
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.2), value: isOn)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A row of equal-width tiles.
struct TileRow<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 8) { content }
    }
}

/// Section heading with a colored icon, like the Windows card titles.
struct SectionTitle: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label {
            Text(title).font(.system(size: 13, weight: .bold))
        } icon: {
            Image(systemName: systemImage).foregroundStyle(color)
        }
        .padding(.top, 6)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The Windows version's large action button (SCAN, Save PDF, Clear), drawn as tinted
/// Liquid Glass. These float above the pages, which is where Apple puts glass.
struct BigActionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let colors: (Color, Color)
    var prominent = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: prominent ? 28 : 22, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: prominent ? 22 : 17, weight: .heavy))
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .opacity(0.9)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: prominent ? 72 : 64)
            .background {
                // A soft gradient under the glass gives the tint the Windows button's depth.
                LinearGradient(colors: [colors.0, colors.1], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .opacity(isEnabled ? 0.55 : 0.2)
                    .clipShape(.rect(cornerRadius: 22, style: .continuous))
            }
            .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(PressScaleStyle())
        .glassEffect(.regular.tint(colors.1.opacity(isEnabled ? 0.75 : 0.3)).interactive(),
                     in: .rect(cornerRadius: 22, style: .continuous))
        .opacity(isEnabled ? 1 : 0.6)
        .scaleEffect(hovering && isEnabled ? 1.02 : 1)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.2), value: hovering)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

import SwiftUI

/// The Windows version's palette (App.xaml), so both apps feel like the same product.
enum Palette {
    static let sky = Color(hex: 0x0EA5E9)
    static let violet = Color(hex: 0x8B5CF6)
    static let teal = Color(hex: 0x0D9488)
    static let amber = Color(hex: 0xF59E0B)
    static let orange = Color(hex: 0xF97316)
    static let pink = Color(hex: 0xEC4899)
    static let green = Color(hex: 0x16A34A)
    static let blue = Color(hex: 0x2563EB)
    static let rose = Color(hex: 0xE11D48)
    /// Slate is too dark to read on a dark background, so dark mode uses a lighter slate.
    static let slate = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0x94 / 255, green: 0xA3 / 255, blue: 0xB8 / 255, alpha: 1)
            : NSColor(srgbRed: 0x47 / 255, green: 0x55 / 255, blue: 0x69 / 255, alpha: 1)
    })
    static let indigo = Color(hex: 0x4F46E5)

    /// HeaderGradient: indigo → purple → pink → orange.
    static let header = [Color(hex: 0x4F46E5), Color(hex: 0x9333EA), Color(hex: 0xEC4899), Color(hex: 0xF97316)]

    // Big button gradients, used as glass tints (start, end).
    static let scan = (Color(hex: 0x22C55E), Color(hex: 0x0D9488))
    static let save = (Color(hex: 0x3B82F6), Color(hex: 0x4F46E5))
    static let clear = (Color(hex: 0xFB7185), Color(hex: 0xE11D48))
    static let stop = (Color(hex: 0xF59E0B), Color(hex: 0xEA580C))
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

import Foundation

enum ColorMode: String, CaseIterable, Identifiable, Codable {
    case color, gray, blackAndWhite
    var id: Self { self }
    var title: String {
        switch self {
        case .color: "Color"
        case .gray: "Grayscale"
        case .blackAndWhite: "Black & White"
        }
    }
    var detail: String {
        switch self {
        case .color: "Photos, forms"
        case .gray: "Shades of gray"
        case .blackAndWhite: "Text, smallest file"
        }
    }
}

enum PaperSize: String, CaseIterable, Identifiable, Codable {
    case letter, legal
    var id: Self { self }
    var title: String { self == .letter ? "Letter" : "Legal" }
    var detail: String { self == .letter ? "8.5 × 11 in" : "8.5 × 14 in" }
    /// Size in inches.
    var inches: CGSize { self == .letter ? CGSize(width: 8.5, height: 11) : CGSize(width: 8.5, height: 14) }
}

enum ScanSource: String, CaseIterable, Identifiable, Codable {
    case feeder, flatbed
    var id: Self { self }
    var title: String { self == .feeder ? "Feeder" : "Flatbed" }
}

/// The options the user picks in the sidebar. Saved to UserDefaults
/// (the Windows version keeps the same values in %AppData%\ScanDesk\settings.json).
struct AppSettings: Codable, Equatable {
    var deviceKey: String?
    var source: ScanSource = .feeder
    var twoSided = false
    var colorMode: ColorMode = .color
    var dpi = 300
    var paper: PaperSize = .letter
    var skipBlank = true
    var deskew = true
    var ocr = true
    var autoSave = false
    var openAfterSave = false
    var saveFolder: String = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Scans").path

    private static let key = "ScanDeskSettings"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

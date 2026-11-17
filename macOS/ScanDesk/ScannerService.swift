import Foundation
import ImageCaptureCore
import Observation
import os

private let log = Logger(subsystem: "com.matthewdeluxe.ScanDesk", category: "Scanner")

/// A scanner the user can pick in the sidebar.
struct ScannerChoice: Identifiable, Hashable {
    let device: ICScannerDevice
    var id: String { key }

    /// Stable key saved in settings so the last scanner is picked again next time.
    var key: String { device.uuidString ?? device.name ?? "scanner" }

    var name: String { device.name ?? "Scanner" }

    var connection: String {
        let t = device.transportType
        if t == ICDeviceTransport.transportTypeUSB.rawValue { return "USB" }
        if t == ICDeviceTransport.transportTypeTCPIP.rawValue || t == ICDeviceTransport.transportTypeBluetooth.rawValue || device.isRemote { return "Network" }
        return "Local"
    }
}

/// What to scan with. Mirrors the options the Windows version passes to NAPS2.
struct ScanRequest {
    var source: ScanSource
    var twoSided: Bool
    var colorMode: ColorMode
    var dpi: Int
    var paper: PaperSize
}

enum ScanError: LocalizedError {
    case noScanner
    case sessionFailed(String)
    case noFeeder
    case feederEmpty
    case scanFailed(String)

    var errorDescription: String? {
        switch self {
        case .noScanner:
            "Pick a scanner in the sidebar first (or press Refresh)."
        case .sessionFailed(let m):
            "The scanner isn't responding. Check that it's on and connected, then press Refresh. (\(m))"
        case .noFeeder:
            "This scanner has no document feeder. Switch the source to Flatbed."
        case .feederEmpty:
            "The document feeder is empty. Load your pages face-up and try again."
        case .scanFailed(let m):
            ScanError.friendly(m)
        }
    }

    /// Turns driver messages into plain advice, like FriendlyScanError on Windows.
    static func friendly(_ message: String) -> String {
        let m = message.lowercased()
        if m.contains("jam") { return "Paper jam! Clear the feeder, then scan the remaining pages." }
        if m.contains("busy") || m.contains("in use") { return "The scanner is busy. Wait a moment and try again." }
        if (m.contains("feeder") || m.contains("paper")) && (m.contains("empty") || m.contains("no document") || m.contains("not loaded")) {
            return "The document feeder is empty. Load your pages face-up and try again."
        }
        if m.contains("offline") || m.contains("not found") || m.contains("disconnected") {
            return "The scanner isn't responding. Check that it's on and connected, then press Refresh."
        }
        return "Scan problem: \(message)"
    }
}

/// Finds scanners with ImageCaptureCore (USB, shared and Bonjour/AirScan network scanners)
/// and runs scans. ImageCaptureCore calls its delegates on the main thread.
@Observable
final class ScannerService: NSObject {
    private(set) var scanners: [ScannerChoice] = []
    private(set) var isSearching = false

    @ObservationIgnored private let browser = ICDeviceBrowser()
    @ObservationIgnored private var openContinuation: CheckedContinuation<Void, Error>?
    @ObservationIgnored private var selectContinuation: CheckedContinuation<Void, Error>?
    @ObservationIgnored private var scanContinuation: CheckedContinuation<Void, Error>?
    @ObservationIgnored private var onPage: ((URL) -> Void)?
    @ObservationIgnored private var activeDevice: ICScannerDevice?

    override init() {
        super.init()
        browser.delegate = self
        // Both are plain enums in Swift, so the bits are combined by hand.
        let location = ICDeviceLocationTypeMask.local.rawValue | ICDeviceLocationTypeMask.shared.rawValue
            | ICDeviceLocationTypeMask.bonjour.rawValue | ICDeviceLocationTypeMask.bluetooth.rawValue
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue: ICDeviceTypeMask.scanner.rawValue | location)!
    }

    /// Starts (or restarts) looking for scanners. Devices keep arriving for a few seconds.
    func refresh() {
        if browser.isBrowsing { browser.stop() }
        scanners.removeAll()
        isSearching = true
        browser.start()
        Task {
            try? await Task.sleep(for: .seconds(4))
            isSearching = false
        }
    }

    var isScanning: Bool { scanContinuation != nil }

    /// Scans every page in the feeder (or one flatbed page). `onPage` is called with each page's file as it arrives.
    func scan(with choice: ScannerChoice, request: ScanRequest, into folder: URL, onPage: @escaping (URL) -> Void) async throws {
        let device = choice.device
        device.delegate = self
        activeDevice = device
        self.onPage = onPage
        defer {
            self.onPage = nil
            activeDevice = nil
            device.requestCloseSession(options: nil) { _ in }
        }

        if !device.hasOpenSession {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                openContinuation = c
                device.requestOpenSession()
            }
        }

        let wantedType: ICScannerFunctionalUnitType = request.source == .feeder ? .documentFeeder : .flatbed
        let available = device.availableFunctionalUnitTypes.map { ICScannerFunctionalUnitType(rawValue: $0.uintValue) }
        if !available.contains(wantedType) {
            if wantedType == .documentFeeder { throw ScanError.noFeeder }
            throw ScanError.scanFailed("This scanner has no flatbed. Switch the source to Feeder.")
        }
        if device.selectedFunctionalUnit.type != wantedType {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                selectContinuation = c
                device.requestSelect(wantedType)
            }
        }

        let unit = device.selectedFunctionalUnit
        configure(unit, request: request)

        device.transferMode = .fileBased
        device.downloadsDirectory = folder
        device.documentName = "scan-\(UUID().uuidString.prefix(8))"
        device.documentUTI = "public.tiff"

        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            scanContinuation = c
            device.requestScan()
        }
    }

    func cancel() {
        activeDevice?.cancelScan()
    }

    private func configure(_ unit: ICScannerFunctionalUnit, request: ScanRequest) {
        unit.measurementUnit = .inches

        // Closest supported resolution to the one asked for.
        let supported = unit.supportedResolutions
        if supported.contains(request.dpi) || supported.isEmpty {
            unit.resolution = request.dpi
        } else {
            unit.resolution = supported.min(by: { abs($0 - request.dpi) < abs($1 - request.dpi) }) ?? unit.preferredResolutions.first ?? request.dpi
        }

        switch request.colorMode {
        case .color:
            unit.pixelDataType = .RGB
            unit.bitDepth = .depth8Bits
        case .gray:
            unit.pixelDataType = .gray
            unit.bitDepth = .depth8Bits
        case .blackAndWhite:
            unit.pixelDataType = .BW
            unit.bitDepth = .depth1Bit
        }

        let docType: ICScannerDocumentType = request.paper == .letter ? .typeUSLetter : .typeUSLegal
        if let feeder = unit as? ICScannerFunctionalUnitDocumentFeeder {
            feeder.documentType = docType
            feeder.duplexScanningEnabled = request.twoSided && feeder.supportsDuplexScanning
        } else if let flatbed = unit as? ICScannerFunctionalUnitFlatbed {
            flatbed.documentType = docType
        }

        // Scan area in inches, clipped to what the scanner can actually reach.
        let phys = unit.physicalSize
        let size = request.paper.inches
        let w = phys.width > 0 ? min(size.width, phys.width) : size.width
        let h = phys.height > 0 ? min(size.height, phys.height) : size.height
        unit.scanArea = NSRect(x: 0, y: 0, width: w, height: h)
    }

    private func finish(_ continuation: inout CheckedContinuation<Void, Error>?, error: Error?) {
        guard let c = continuation else { return }
        continuation = nil
        if let error { c.resume(throwing: error) } else { c.resume() }
    }
}

extension ScannerService: @preconcurrency ICDeviceBrowserDelegate {
    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let scanner = device as? ICScannerDevice else { return }
        let choice = ScannerChoice(device: scanner)
        if !scanners.contains(where: { $0.key == choice.key }) {
            scanners.append(choice)
            scanners.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        if !moreComing { isSearching = false }
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        scanners.removeAll { $0.device === device }
    }
}

extension ScannerService: @preconcurrency ICScannerDeviceDelegate {
    func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        finish(&openContinuation, error: error.map { ScanError.sessionFailed($0.localizedDescription) })
    }

    func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {}

    func didRemove(_ device: ICDevice) {
        let gone = ScanError.sessionFailed("disconnected")
        finish(&openContinuation, error: gone)
        finish(&selectContinuation, error: gone)
        finish(&scanContinuation, error: gone)
    }

    func scannerDevice(_ scanner: ICScannerDevice, didSelect functionalUnit: ICScannerFunctionalUnit, error: Error?) {
        finish(&selectContinuation, error: error.map { ScanError.scanFailed($0.localizedDescription) })
    }

    func scannerDevice(_ scanner: ICScannerDevice, didScanTo url: URL) {
        log.debug("Scanned page to \(url.path, privacy: .public)")
        onPage?(url)
    }

    func scannerDevice(_ scanner: ICScannerDevice, didCompleteScanWithError error: Error?) {
        if let error {
            let ns = error as NSError
            // Cancelling isn't a failure; pages already scanned are kept.
            // -9924 is ICReturnScanOperationCanceled.
            if ns.code == -9924 || ns.code == NSUserCancelledError {
                finish(&scanContinuation, error: CancellationError())
            } else {
                finish(&scanContinuation, error: ScanError.scanFailed(error.localizedDescription))
            }
        } else {
            finish(&scanContinuation, error: nil)
        }
    }
}

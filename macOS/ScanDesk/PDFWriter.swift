import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// One page to put in the PDF.
nonisolated struct PDFPageSource: Sendable {
    let url: URL
    let quarterTurns: Int
}

/// Writes scanned pages to a PDF, optionally with an invisible OCR text layer so the
/// PDF is searchable and text can be selected. OCR uses Apple's Vision framework
/// (the Windows version uses Tesseract through NAPS2).
nonisolated enum PDFWriter {
    enum WriteError: LocalizedError {
        case cantCreate, unreadablePage(Int)
        var errorDescription: String? {
            switch self {
            case .cantCreate: "The PDF could not be written."
            case .unreadablePage(let n): "Page \(n) could not be read."
            }
        }
    }

    /// Writes to a temporary file first and moves it into place at the end,
    /// so a failed or cancelled save never leaves a broken PDF behind.
    static func write(pages: [PDFPageSource], to destination: URL, ocr: Bool,
                      progress: @Sendable (Int, Int) -> Void) throws {
        let folder = destination.deletingLastPathComponent()
        let temp = folder.appendingPathComponent(".scandesk-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: temp) }

        let info: [CFString: Any] = [kCGPDFContextCreator: "ScanDesk", kCGPDFContextTitle: destination.deletingPathExtension().lastPathComponent]
        guard let ctx = CGContext(temp as CFURL, mediaBox: nil, info as CFDictionary) else { throw WriteError.cantCreate }

        for (index, source) in pages.enumerated() {
            progress(index, pages.count)
            try autoreleasepool {
                guard let loaded = PageProcessor.load(source.url) else { throw WriteError.unreadablePage(index + 1) }
                let image = PageProcessor.rotate(loaded, quarterTurns: source.quarterTurns)

                // Physical page size from the scan resolution. Images without a real DPI (photos)
                // are sized so their short side is 8.5 in, the width of a letter page.
                let dpi = PageProcessor.dpi(of: source.url) ?? max(Double(min(image.width, image.height)) / 8.5, 1)
                var box = CGRect(x: 0, y: 0, width: Double(image.width) / dpi * 72, height: Double(image.height) / dpi * 72)

                ctx.beginPage(mediaBox: &box)
                ctx.interpolationQuality = .high
                ctx.draw(compressed(image), in: box)
                if ocr { drawInvisibleText(for: image, in: box, context: ctx) }
                ctx.endPage()
            }
        }
        ctx.closePDF()
        progress(pages.count, pages.count)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temp, to: destination)
    }

    /// Color and gray pages go into the PDF as JPEG (Core Graphics passes JPEG data through untouched),
    /// which keeps files small. Black & white pages stay 1-bit, which compresses well by itself.
    private static func compressed(_ image: CGImage) -> CGImage {
        if image.bitsPerPixel == 1 { return image }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return image }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(dest),
              let provider = CGDataProvider(data: data),
              let jpeg = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return image }
        return jpeg
    }

    /// Recognizes text and draws it invisibly on top of the image, each line stretched to cover the words it came from.
    private static func drawInvisibleText(for image: CGImage, in box: CGRect, context ctx: CGContext) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let handler = VNImageRequestHandler(cgImage: image)
        guard (try? handler.perform([request])) != nil, let results = request.results else { return }

        ctx.saveGState()
        ctx.setTextDrawingMode(.invisible)
        for obs in results {
            guard let text = obs.topCandidates(1).first?.string, !text.isEmpty else { continue }
            // Vision's coordinates are normalized with the origin at bottom-left, like PDF.
            let r = CGRect(x: box.minX + obs.boundingBox.minX * box.width,
                           y: box.minY + obs.boundingBox.minY * box.height,
                           width: obs.boundingBox.width * box.width,
                           height: obs.boundingBox.height * box.height)
            guard r.width > 1, r.height > 1 else { continue }

            let font = CTFontCreateWithName("Helvetica" as CFString, r.height * 0.9, nil)
            let attr = NSAttributedString(string: text, attributes: [.init(kCTFontAttributeName as String): font])
            let line = CTLineCreateWithAttributedString(attr)
            var descent: CGFloat = 0
            let width = CTLineGetTypographicBounds(line, nil, &descent, nil)
            guard width > 0 else { continue }

            ctx.saveGState()
            ctx.textMatrix = .identity
            ctx.translateBy(x: r.minX, y: r.minY + descent * 0.5)
            ctx.scaleBy(x: r.width / width, y: 1)
            ctx.textPosition = .zero
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }
}

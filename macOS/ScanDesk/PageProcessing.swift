import AppKit
import CoreImage
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

/// Image work that runs off the main thread: loading, blank-page detection,
/// straightening, rotation, thumbnails and importing PDFs.
nonisolated enum PageProcessor {
    static let thumbnailSize = 420

    struct Processed: Sendable {
        let url: URL
        let thumbnail: CGImage
    }

    // MARK: Loading

    /// Loads an image file, applying any EXIF orientation (photos from iPhone often have one).
    static func load(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let orientation = props?[kCGImagePropertyOrientation] as? UInt32 ?? 1
        if orientation == 1 {
            return CGImageSourceCreateImageAtIndex(src, 0, nil)
        }
        let w = props?[kCGImagePropertyPixelWidth] as? Int ?? 4000
        let h = props?[kCGImagePropertyPixelHeight] as? Int ?? 4000
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(w, h),
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// Resolution stored in the file, or nil if missing or obviously a screen value (72 dpi).
    static func dpi(of url: URL) -> Double? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let d = props[kCGImagePropertyDPIWidth] as? Double, d >= 100 else { return nil }
        return d
    }

    static func thumbnail(of image: CGImage) -> CGImage {
        let scale = Double(thumbnailSize) / Double(max(image.width, image.height))
        guard scale < 1 else { return image }
        let w = max(1, Int(Double(image.width) * scale)), h = max(1, Int(Double(image.height) * scale))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    // MARK: Scanned pages

    /// Cleans up one page from the scanner. Returns nil if the page is blank and should be skipped.
    static func processScannedPage(at url: URL, workFolder: URL, skipBlank: Bool, deskew: Bool, dpi: Int) -> Processed? {
        guard var image = load(url) else { return nil }
        if skipBlank && isBlank(image) {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        var outURL = url
        if deskew, let angle = skewAngle(of: image), let straightened = rotate(image, byRadians: -angle) {
            image = straightened
            let dest = workFolder.appendingPathComponent("\(UUID().uuidString).png")
            if write(image, to: dest, type: .png, dpi: Double(dpi)) {
                try? FileManager.default.removeItem(at: url)
                outURL = dest
            }
        } else if url.deletingLastPathComponent() != workFolder {
            let dest = workFolder.appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension)
            if (try? FileManager.default.moveItem(at: url, to: dest)) != nil { outURL = dest }
        }
        return Processed(url: outURL, thumbnail: thumbnail(of: image))
    }

    /// A page counts as blank if almost no pixels are dark, ignoring a margin where
    /// scanner shadows and punch holes show up. Same idea as NAPS2's blank page detection.
    static func isBlank(_ image: CGImage) -> Bool {
        let w = 400
        let h = max(1, Int(Double(image.height) * Double(w) / Double(image.width)))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let _ = ctx.data else { return false }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let buf = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h)
        let mx = w / 25, my = h / 25
        var dark = 0, total = 0
        for y in my..<(h - my) {
            for x in mx..<(w - mx) {
                total += 1
                if buf[y * w + x] < 128 { dark += 1 }
            }
        }
        guard total > 0 else { return false }
        return Double(dark) / Double(total) < 0.0005
    }

    /// Estimates how crooked the page is (projection-profile method): at the right angle, the dark
    /// pixels of each line of text fall into the same few rows, so the row histogram is at its most
    /// "peaky". Tries angles up to ±10°, coarse then fine.
    /// Returns radians (counter-clockwise positive), or nil if the page is straight enough or nearly empty.
    static func skewAngle(of image: CGImage) -> Double? {
        let w = 800
        let h = max(1, Int(Double(image.height) * Double(w) / Double(image.width)))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let data = ctx.data else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let buf = data.bindMemory(to: UInt8.self, capacity: w * h)

        // Dark pixels, ignoring a margin where scanner edges and shadows show up.
        var xs: [Double] = [], ys: [Double] = []
        let mx = w / 20, my = h / 20
        for row in my..<(h - my) {
            for x in mx..<(w - mx) where buf[row * w + x] < 128 {
                xs.append(Double(x))
                ys.append(Double(h - 1 - row))        // y up, like Core Graphics
            }
        }
        guard xs.count > 500, xs.count < w * h / 3 else { return nil }   // blank or a photo

        func score(_ a: Double) -> Double {
            let s = sin(a), c = cos(a)
            let offset = Double(w + h)
            var bins = [Int](repeating: 0, count: 2 * (w + h) + 2)
            for i in xs.indices {
                bins[Int(ys[i] * c - xs[i] * s + offset)] += 1
            }
            return bins.reduce(0.0) { $0 + Double($1 * $1) }
        }

        let radian = Double.pi / 180
        var best = 0.0, bestScore = score(0)
        let straightScore = bestScore
        for step in stride(from: -10.0, through: 10.0, by: 0.5) where step != 0 {
            let s = score(step * radian)
            if s > bestScore { bestScore = s; best = step }
        }
        let coarse = best
        for step in stride(from: coarse - 0.5, through: coarse + 0.5, by: 0.1) {
            let s = score(step * radian)
            if s > bestScore { bestScore = s; best = step }
        }
        // Leave pages alone unless they're clearly crooked and the better angle is clearly better.
        guard abs(best) >= 0.3, bestScore > straightScore * 1.05 else { return nil }
        return best * radian
    }

    /// Rotates around the centre, keeping the page size and filling uncovered corners with white.
    static func rotate(_ image: CGImage, byRadians angle: Double) -> CGImage? {
        let ci = CIImage(cgImage: image)
        let extent = ci.extent
        let t = CGAffineTransform(translationX: extent.midX, y: extent.midY)
            .rotated(by: angle)
            .translatedBy(x: -extent.midX, y: -extent.midY)
        let rotated = ci.transformed(by: t, highQualityDownsample: true)
            .composited(over: CIImage(color: .white).cropped(to: extent))
            .cropped(to: extent)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let space = image.colorSpace?.model == .monochrome ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
        return context.createCGImage(rotated, from: extent, format: space.model == .monochrome ? .L8 : .RGBA8, colorSpace: space)
    }

    /// Exact quarter-turn rotation (for the rotate buttons). `quarterTurns` is clockwise.
    static func rotate(_ image: CGImage, quarterTurns: Int) -> CGImage {
        let q = ((quarterTurns % 4) + 4) % 4
        guard q != 0 else { return image }
        let swap = q % 2 == 1
        let w = swap ? image.height : image.width
        let h = swap ? image.width : image.height
        let gray = image.colorSpace?.model == .monochrome
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: gray ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: gray ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return image }
        ctx.translateBy(x: Double(w) / 2, y: Double(h) / 2)
        ctx.rotate(by: -Double(q) * .pi / 2)           // Core Graphics turns counter-clockwise
        ctx.translateBy(x: -Double(image.width) / 2, y: -Double(image.height) / 2)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage() ?? image
    }

    @discardableResult
    static func write(_ image: CGImage, to url: URL, type: UTType, dpi: Double?, quality: Double = 0.9) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { return false }
        var props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        if let dpi { props[kCGImagePropertyDPIWidth] = dpi; props[kCGImagePropertyDPIHeight] = dpi }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }

    // MARK: Importing files (Finder drops, Add Files…, Import from iPhone)

    /// Turns an image or PDF into one or more page images in the work folder.
    static func importFile(_ url: URL, workFolder: URL) -> [Processed] {
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        if type.conforms(to: .pdf) {
            return importPDF(url, workFolder: workFolder)
        }
        guard type.conforms(to: .image), let image = load(url) else { return [] }
        let dest = workFolder.appendingPathComponent("\(UUID().uuidString).jpg")
        guard write(image, to: dest, type: .jpeg, dpi: dpi(of: url)) else { return [] }
        return [Processed(url: dest, thumbnail: thumbnail(of: image))]
    }

    private static func importPDF(_ url: URL, workFolder: URL) -> [Processed] {
        guard let doc = CGPDFDocument(url as CFURL), doc.numberOfPages > 0 else { return [] }
        let dpi = 300.0
        var out: [Processed] = []
        for i in 1...doc.numberOfPages {
            guard let page = doc.page(at: i) else { continue }
            let box = page.getBoxRect(.cropBox)
            let rotation = ((page.rotationAngle % 360) + 360) % 360
            let size = rotation % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
            let w = Int(size.width / 72 * dpi), h = Int(size.height / 72 * dpi)
            guard w > 0, h > 0,
                  let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { continue }
            ctx.setFillColor(.white)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.scaleBy(x: dpi / 72, y: dpi / 72)
            ctx.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: size), rotate: 0, preserveAspectRatio: true))
            ctx.drawPDFPage(page)
            guard let image = ctx.makeImage() else { continue }
            let dest = workFolder.appendingPathComponent("\(UUID().uuidString).jpg")
            if write(image, to: dest, type: .jpeg, dpi: dpi) {
                out.append(Processed(url: dest, thumbnail: thumbnail(of: image)))
            }
        }
        return out
    }
}

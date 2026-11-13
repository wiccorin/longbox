import UIKit
import ImageIO

/// Decodes page images at a sensible size and keeps recent ones in memory.
enum PageImage {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 320 * 1024 * 1024
        return cache
    }()

    private static let trimCache = NSCache<NSURL, NSValue>()

    // MARK: Sizes

    static func pixelSize(_ url: URL) -> CGSize? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0
        else { return nil }
        return CGSize(width: width, height: height)
    }

    /// Width-over-height for every page, read from file headers without decoding.
    static func aspects(_ urls: [URL]) async -> [CGFloat] {
        await Task.detached(priority: .userInitiated) {
            urls.map { url -> CGFloat in
                guard let size = pixelSize(url) else { return 0.66 }
                return size.width / size.height
            }
        }.value
    }

    // MARK: Decoding

    /// Decodes an image so its shorter side is at most `shortSide` pixels.
    /// Limiting the short side keeps long webtoon strips sharp.
    static func downsampled(_ url: URL, shortSide: CGFloat) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else { return nil }

        var maxPixel: CGFloat = shortSide * 2
        if let size = pixelSize(url) {
            let short = min(size.width, size.height)
            let long = max(size.width, size.height)
            let scale = min(1, shortSide / short)
            maxPixel = min(long * scale, 12000)
        }

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixel, 1)
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    /// A small preview, for the page scrubber.
    static func thumbnail(_ url: URL) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            downsampled(url, shortSide: 260)
        }.value
    }

    /// A full page, optionally with its plain border cropped away.
    static func page(_ url: URL, trim: Bool = false) async -> UIImage? {
        let key = ((trim ? "t|" : "f|") + url.path) as NSString
        if let hit = cache.object(forKey: key) { return hit }

        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let decoded = downsampled(url, shortSide: 1800) else { return nil }
            guard trim, let source = decoded.cgImage else { return decoded }
            let unit = trimRect(for: url)
            if unit == PageTrim.full { return decoded }
            let crop = CGRect(
                x: unit.minX * CGFloat(source.width),
                y: unit.minY * CGFloat(source.height),
                width: unit.width * CGFloat(source.width),
                height: unit.height * CGFloat(source.height)
            ).integral
            guard let cropped = source.cropping(to: crop) else { return decoded }
            return UIImage(cgImage: cropped)
        }.value

        if let image {
            let cost = (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0)
            cache.setObject(image, forKey: key, cost: max(cost, 1))
        }
        return image
    }

    // MARK: Margins

    /// The part of a page inside its plain border, as a unit rectangle.
    static func trimRect(for url: URL) -> CGRect {
        let key = url as NSURL
        if let hit = trimCache.object(forKey: key) {
            return hit.cgRectValue
        }
        var rect = PageTrim.full
        if let small = downsampled(url, shortSide: 120)?.cgImage,
           let bitmap = GrayBitmap(small, maxSide: 220) {
            rect = PageTrim.contentRect(bitmap)
        }
        trimCache.setObject(NSValue(cgRect: rect), forKey: key)
        return rect
    }

    /// Trim rectangles for a whole book. Worked out once, then kept in `cacheFile`.
    static func trimRects(_ urls: [URL], cacheFile: URL) async -> [CGRect] {
        await Task.detached(priority: .userInitiated) { () -> [CGRect] in
            if let data = try? Data(contentsOf: cacheFile),
               let saved = try? JSONDecoder().decode([[Double]].self, from: data),
               saved.count == urls.count,
               saved.allSatisfy({ $0.count == 4 }) {
                let rects = saved.map { CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) }
                for (index, rect) in rects.enumerated() {
                    trimCache.setObject(NSValue(cgRect: rect), forKey: urls[index] as NSURL)
                }
                return rects
            }

            var rects = [CGRect](repeating: PageTrim.full, count: urls.count)
            rects.withUnsafeMutableBufferPointer { buffer in
                let base = buffer.baseAddress
                DispatchQueue.concurrentPerform(iterations: urls.count) { index in
                    base?[index] = trimRect(for: urls[index])
                }
            }

            let encoded = rects.map { [Double($0.minX), Double($0.minY), Double($0.width), Double($0.height)] }
            if let data = try? JSONEncoder().encode(encoded) {
                try? data.write(to: cacheFile, options: .atomic)
            }
            return rects
        }.value
    }
}

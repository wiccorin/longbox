import UIKit
import ImageIO

/// Decodes page images at a sensible size and keeps a few in memory.
enum PageImage {
    private static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.totalCostLimit = 320 * 1024 * 1024
        return cache
    }()

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

    /// Width-over-height for every page, read from file headers without decoding.
    static func aspects(_ urls: [URL]) async -> [CGFloat] {
        await Task.detached(priority: .userInitiated) {
            urls.map { url -> CGFloat in
                guard let size = pixelSize(url) else { return 0.66 }
                return size.width / size.height
            }
        }.value
    }

    /// A small preview, for the page scrubber.
    static func thumbnail(_ url: URL) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            downsampled(url, shortSide: 260)
        }.value
    }

    static func page(_ url: URL) async -> UIImage? {
        let key = url as NSURL
        if let hit = cache.object(forKey: key) { return hit }
        let image = await Task.detached(priority: .userInitiated) {
            downsampled(url, shortSide: 1800)
        }.value
        if let image {
            let cost = (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0)
            cache.setObject(image, forKey: key, cost: max(cost, 1))
        }
        return image
    }
}

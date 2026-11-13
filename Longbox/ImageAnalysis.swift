import Foundation
import CoreGraphics

/// A small grayscale copy of an image, for looking at its layout.
struct GrayBitmap {
    let width: Int
    let height: Int
    /// Row by row from the top, one byte per pixel.
    let pixels: [UInt8]

    init?(_ image: CGImage, maxSide: Int) {
        let longest = max(image.width, image.height)
        guard longest > 0 else { return nil }
        let scale = min(1, CGFloat(maxSide) / CGFloat(longest))
        let w = max(Int((CGFloat(image.width) * scale).rounded()), 1)
        let h = max(Int((CGFloat(image.height) * scale).rounded()), 1)

        var data = [UInt8](repeating: 0, count: w * h)
        let drawn: Bool = data.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        width = w
        height = h
        pixels = data
    }

    func at(_ x: Int, _ y: Int) -> Int {
        Int(pixels[y * width + x])
    }
}

/// Finds the plain white or black border around a page.
enum PageTrim {
    static let full = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// The part of the page worth keeping, as a unit rectangle.
    static func contentRect(_ bitmap: GrayBitmap) -> CGRect {
        let w = bitmap.width
        let h = bitmap.height
        guard w >= 16, h >= 16 else { return full }

        let corners = [bitmap.at(1, 1), bitmap.at(w - 2, 1), bitmap.at(1, h - 2), bitmap.at(w - 2, h - 2)]
        let mean = corners.reduce(0, +) / 4
        let light = mean >= 228
        let dark = mean <= 26
        guard light || dark else { return full }
        guard corners.allSatisfy({ abs($0 - mean) <= 20 }) else { return full }

        func isBlank(_ value: Int) -> Bool {
            light ? value >= 222 : value <= 32
        }
        func rowIsBlank(_ y: Int) -> Bool {
            let allowed = max(1, w * 12 / 1000)
            var ink = 0
            for x in 0..<w where !isBlank(bitmap.at(x, y)) {
                ink += 1
                if ink > allowed { return false }
            }
            return true
        }
        func columnIsBlank(_ x: Int, _ y0: Int, _ y1: Int) -> Bool {
            let allowed = max(1, (y1 - y0 + 1) * 12 / 1000)
            var ink = 0
            for y in y0...y1 where !isBlank(bitmap.at(x, y)) {
                ink += 1
                if ink > allowed { return false }
            }
            return true
        }

        let maxVertical = h / 4
        let maxHorizontal = w / 4

        var top = 0
        while top < maxVertical && rowIsBlank(top) { top += 1 }
        var bottom = h - 1
        while (h - 1 - bottom) < maxVertical && rowIsBlank(bottom) { bottom -= 1 }
        guard bottom > top else { return full }

        var left = 0
        while left < maxHorizontal && columnIsBlank(left, top, bottom) { left += 1 }
        var right = w - 1
        while (w - 1 - right) < maxHorizontal && columnIsBlank(right, top, bottom) { right -= 1 }
        guard right > left else { return full }

        // Give back a pixel on each side so no ink is clipped.
        top = max(top - 1, 0)
        left = max(left - 1, 0)
        bottom = min(bottom + 1, h - 1)
        right = min(right + 1, w - 1)

        let rect = CGRect(
            x: CGFloat(left) / CGFloat(w),
            y: CGFloat(top) / CGFloat(h),
            width: CGFloat(right - left + 1) / CGFloat(w),
            height: CGFloat(bottom - top + 1) / CGFloat(h)
        )
        if rect.width > 0.985 && rect.height > 0.985 { return full }
        return rect
    }
}

/// Finds comic panels by cutting the page along its gutters.
enum PanelDetector {
    private struct Region {
        var x0: Int
        var y0: Int
        var x1: Int
        var y1: Int
        var width: Int { x1 - x0 }
        var height: Int { y1 - y0 }
    }

    /// Panels as unit rectangles in reading order. Empty when the page has no clear gutters.
    static func panels(in image: CGImage, rightToLeft: Bool) -> [CGRect] {
        guard let bitmap = GrayBitmap(image, maxSide: 420) else { return [] }
        // Most gutters are white; some books use black.
        for light in [true, false] {
            let found = detect(bitmap, light: light, rightToLeft: rightToLeft)
            if found.count >= 2 { return found }
        }
        return []
    }

    private static func detect(_ bitmap: GrayBitmap, light: Bool, rightToLeft: Bool) -> [CGRect] {
        let w = bitmap.width
        let h = bitmap.height
        guard w >= 32, h >= 32 else { return [] }
        let stride = w + 1

        // Running totals of "ink" pixels, so any row or column span can be checked in one step.
        var totals = [Int32](repeating: 0, count: stride * (h + 1))
        for y in 0..<h {
            var row: Int32 = 0
            for x in 0..<w {
                let value = bitmap.pixels[y * w + x]
                let isGutter = light ? value >= 218 : value <= 36
                if !isGutter { row += 1 }
                totals[(y + 1) * stride + (x + 1)] = totals[y * stride + (x + 1)] + row
            }
        }
        func ink(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> Int {
            Int(totals[y1 * stride + x1] - totals[y0 * stride + x1] - totals[y1 * stride + x0] + totals[y0 * stride + x0])
        }
        func rowIsBlank(_ y: Int, _ x0: Int, _ x1: Int) -> Bool {
            ink(x0, y, x1, y + 1) <= max(1, (x1 - x0) * 3 / 1000)
        }
        func columnIsBlank(_ x: Int, _ y0: Int, _ y1: Int) -> Bool {
            ink(x, y0, x + 1, y1) <= max(1, (y1 - y0) * 3 / 1000)
        }
        func shrink(_ region: Region) -> Region? {
            var r = region
            while r.y0 < r.y1 && rowIsBlank(r.y0, r.x0, r.x1) { r.y0 += 1 }
            while r.y1 > r.y0 && rowIsBlank(r.y1 - 1, r.x0, r.x1) { r.y1 -= 1 }
            guard r.y1 > r.y0 else { return nil }
            while r.x0 < r.x1 && columnIsBlank(r.x0, r.y0, r.y1) { r.x0 += 1 }
            while r.x1 > r.x0 && columnIsBlank(r.x1 - 1, r.y0, r.y1) { r.x1 -= 1 }
            guard r.x1 > r.x0 else { return nil }
            return r
        }

        var leaves: [Region] = []

        func split(_ region: Region, horizontal: Bool, depth: Int, triedOther: Bool) {
            guard let r = shrink(region) else { return }
            if depth >= 6 {
                leaves.append(r)
                return
            }

            let minGap = max(2, (horizontal ? h : w) * 6 / 1000)
            var gaps: [(start: Int, end: Int)] = []
            if horizontal {
                var y = r.y0
                while y < r.y1 {
                    if rowIsBlank(y, r.x0, r.x1) {
                        var end = y
                        while end < r.y1 && rowIsBlank(end, r.x0, r.x1) { end += 1 }
                        if end - y >= minGap { gaps.append((y, end)) }
                        y = end
                    } else {
                        y += 1
                    }
                }
            } else {
                var x = r.x0
                while x < r.x1 {
                    if columnIsBlank(x, r.y0, r.y1) {
                        var end = x
                        while end < r.x1 && columnIsBlank(end, r.y0, r.y1) { end += 1 }
                        if end - x >= minGap { gaps.append((x, end)) }
                        x = end
                    } else {
                        x += 1
                    }
                }
            }

            if gaps.isEmpty {
                if triedOther {
                    leaves.append(r)
                } else {
                    split(r, horizontal: !horizontal, depth: depth, triedOther: true)
                }
                return
            }

            var parts: [Region] = []
            var start = horizontal ? r.y0 : r.x0
            for gap in gaps {
                if gap.start > start {
                    if horizontal {
                        parts.append(Region(x0: r.x0, y0: start, x1: r.x1, y1: gap.start))
                    } else {
                        parts.append(Region(x0: start, y0: r.y0, x1: gap.start, y1: r.y1))
                    }
                }
                start = gap.end
            }
            let limit = horizontal ? r.y1 : r.x1
            if limit > start {
                if horizontal {
                    parts.append(Region(x0: r.x0, y0: start, x1: r.x1, y1: limit))
                } else {
                    parts.append(Region(x0: start, y0: r.y0, x1: limit, y1: r.y1))
                }
            }
            // Side-by-side panels read right to left in manga.
            if !horizontal && rightToLeft {
                parts.reverse()
            }
            for part in parts {
                split(part, horizontal: !horizontal, depth: depth + 1, triedOther: false)
            }
        }

        split(Region(x0: 0, y0: 0, x1: w, y1: h), horizontal: true, depth: 0, triedOther: false)

        let minWidth = w * 8 / 100
        let minHeight = h * 6 / 100
        let kept = leaves.filter { $0.width >= minWidth && $0.height >= minHeight }
        guard kept.count >= 2, kept.count <= 24 else { return [] }

        return kept.map { region in
            CGRect(
                x: CGFloat(region.x0) / CGFloat(w),
                y: CGFloat(region.y0) / CGFloat(h),
                width: CGFloat(region.width) / CGFloat(w),
                height: CGFloat(region.height) / CGFloat(h)
            )
        }
    }
}

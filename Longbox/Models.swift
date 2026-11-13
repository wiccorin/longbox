import Foundation

enum ReadingMode: String, Codable, CaseIterable, Identifiable {
    case leftToRight
    case rightToLeft
    case vertical

    var id: String { rawValue }

    var label: String {
        switch self {
        case .leftToRight: return "Left to right"
        case .rightToLeft: return "Right to left (manga)"
        case .vertical: return "Vertical scroll"
        }
    }

    var symbol: String {
        switch self {
        case .leftToRight: return "arrow.right"
        case .rightToLeft: return "arrow.left"
        case .vertical: return "arrow.down"
        }
    }
}

struct Book: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    /// Page file names, in reading order, inside the book's folder.
    var pages: [String]
    var currentPage: Int
    var mode: ReadingMode
    var addedAt: Date
    var lastReadAt: Date?

    var pageCount: Int { pages.count }

    var progress: Double {
        guard pageCount > 1 else { return currentPage > 0 ? 1 : 0 }
        return Double(currentPage) / Double(pageCount - 1)
    }

    var isStarted: Bool { lastReadAt != nil }
    var isFinished: Bool { pageCount > 0 && currentPage >= pageCount - 1 && isStarted }
}

/// Where Longbox keeps its files on disk.
enum Storage {
    static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Longbox", isDirectory: true)
    }()

    static var booksDir: URL { root.appendingPathComponent("Books", isDirectory: true) }
    static var coversDir: URL { root.appendingPathComponent("Covers", isDirectory: true) }
    static var libraryFile: URL { root.appendingPathComponent("library.json") }

    static func folder(for id: UUID) -> URL {
        booksDir.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    static func cover(for id: UUID) -> URL {
        coversDir.appendingPathComponent(id.uuidString + ".jpg")
    }

    static func pageURLs(for book: Book) -> [URL] {
        let dir = folder(for: book.id)
        return book.pages.map { dir.appendingPathComponent($0) }
    }

    static func prepare() {
        let fm = FileManager.default
        for dir in [root, booksDir, coversDir] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}

/// Shared rules for which archive entries count as pages and how they are ordered.
enum PageNaming {
    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "bmp", "heic", "heif", "avif", "tif", "tiff"
    ]

    static func isPage(_ path: String) -> Bool {
        let parts = path.split(whereSeparator: { $0 == "/" || $0 == "\\" })
        guard let last = parts.last else { return false }
        if parts.contains(where: { $0 == "__MACOSX" }) { return false }
        if last.hasPrefix(".") { return false }
        let ext = (String(last) as NSString).pathExtension.lowercased()
        return imageExtensions.contains(ext)
    }

    /// Natural ordering, so "page2" sorts before "page10".
    static func precedes(_ a: String, _ b: String) -> Bool {
        a.localizedStandardCompare(b) == .orderedAscending
    }

    static func fileName(index: Int, originalPath: String) -> String {
        let ext = (originalPath as NSString).pathExtension.lowercased()
        return String(format: "%05d", index) + "." + (ext.isEmpty ? "jpg" : ext)
    }
}

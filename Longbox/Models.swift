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

/// A named starting point inside a book.
struct Chapter: Codable, Equatable, Identifiable {
    var title: String
    var startPage: Int

    var id: Int { startPage }

    func displayTitle(_ index: Int) -> String {
        title.isEmpty ? "Chapter \(index + 1)" : title
    }
}

/// What an extractor hands back: page files, the archive folder each came from, and any ComicInfo.xml.
struct ExtractedArchive {
    var pages: [String] = []
    var folders: [String] = []
    var comicInfo: Data?
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

    // Details. All optional so libraries saved by older builds still load.
    var series: String?
    var writer: String?
    var publisher: String?
    var year: Int?
    var month: Int?
    var summary: String?
    var chapters: [Chapter]?

    var pageCount: Int { pages.count }

    var chapterList: [Chapter] {
        (chapters ?? []).sorted { $0.startPage < $1.startPage }
    }

    /// Index into `chapterList` of the chapter containing the current page.
    var currentChapterIndex: Int? {
        let list = chapterList
        guard !list.isEmpty else { return nil }
        var found: Int?
        for (index, chapter) in list.enumerated() where chapter.startPage <= currentPage {
            found = index
        }
        return found
    }

    /// Sortable release date: year and month packed into one number.
    var releaseKey: Int? {
        guard let year else { return nil }
        return year * 100 + (month ?? 0)
    }

    var releaseText: String? {
        guard let year else { return nil }
        if let month, (1...12).contains(month) {
            return "\(DateFormatter().monthSymbols[month - 1]) \(String(year))"
        }
        return String(year)
    }

    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        var fields: [String] = [title]
        if let series { fields.append(series) }
        if let writer { fields.append(writer) }
        if let publisher { fields.append(publisher) }
        if let year { fields.append(String(year)) }
        return fields.contains {
            $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

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

/// Pulls what it can out of a file name like "Title v01 (2007) (digital)".
enum TitleParser {
    static func year(in name: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: "\\((\\d{4})\\)") else { return nil }
        let range = NSRange(name.startIndex..., in: name)
        for match in regex.matches(in: name, range: range) {
            if let found = Range(match.range(at: 1), in: name),
               let year = Int(name[found]),
               (1900...2100).contains(year) {
                return year
            }
        }
        return nil
    }

    /// Drops bracketed tags and tidies spacing.
    static func clean(_ name: String) -> String {
        var result = name.replacingOccurrences(
            of: "\\s*[\\(\\[][^\\)\\]]*[\\)\\]]",
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(of: "_", with: " ")
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? name : result
    }

    /// One chapter per archive folder, when the archive has at least two.
    static func chapters(fromFolders folders: [String]) -> [Chapter] {
        var result: [Chapter] = []
        var last: String?
        for (index, folder) in folders.enumerated() {
            if folder != last {
                let name = (folder as NSString).lastPathComponent
                result.append(Chapter(title: name, startPage: index))
                last = folder
            }
        }
        return result.count >= 2 ? result : []
    }
}

import Foundation
import CoreGraphics

extension Book {
    /// Books with the same key belong to the same series.
    var seriesKey: String? {
        guard let name = series?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !name.isEmpty
        else { return nil }
        return name
    }

    var numberText: String? {
        guard let number else { return nil }
        if number == number.rounded() {
            return String(Int(number))
        }
        return String(number)
    }
}

extension TitleParser {
    /// Splits "Saga 054", "One Piece v12" or "Akira Vol. 3" into a series name and a number.
    static func seriesAndNumber(in name: String) -> (series: String, number: Double)? {
        let cleaned = clean(name)
        let pattern = "^(.+?)[\\s\\-_,:]*(?:\\b(?:v|vol\\.?|volume|ch\\.?|chapter|issue|book|part|no\\.?)|#)?\\s*(?<![\\d.])(\\d{1,3}(?:\\.\\d)?)$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(cleaned.startIndex..., in: cleaned)
        guard let match = regex.firstMatch(in: cleaned, range: range),
              let nameRange = Range(match.range(at: 1), in: cleaned),
              let numberRange = Range(match.range(at: 2), in: cleaned),
              let number = Double(cleaned[numberRange])
        else { return nil }

        let series = cleaned[nameRange].trimmingCharacters(in: CharacterSet(charactersIn: " -_,:#"))
        guard series.count >= 2 else { return nil }
        return (series, number)
    }
}

/// Reading order inside a series: by number, then by title.
enum SeriesOrder {
    static func sorted(_ books: [Book]) -> [Book] {
        books.sorted { a, b in
            let left = a.number ?? Double.greatestFiniteMagnitude
            let right = b.number ?? Double.greatestFiniteMagnitude
            if left != right { return left < right }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }
}

/// Two or more books from one series, shown as a single stack.
struct SeriesStack: Identifiable {
    let key: String
    /// In reading order.
    let books: [Book]

    var id: String { key }
    var name: String { books.first?.series ?? key }
    var readCount: Int { books.filter { $0.isFinished }.count }

    /// The first issue that isn't finished, or the first issue if all are.
    var upNext: Book? {
        books.first { !$0.isFinished } ?? books.first
    }
}

enum LibraryItem: Identifiable {
    case single(Book)
    case stack(SeriesStack)

    var id: String {
        switch self {
        case .single(let book): return "book-" + book.id.uuidString
        case .stack(let stack): return "stack-" + stack.key
        }
    }

    private var members: [Book] {
        switch self {
        case .single(let book): return [book]
        case .stack(let stack): return stack.books
        }
    }

    var sortTitle: String {
        switch self {
        case .single(let book): return book.title
        case .stack(let stack): return stack.name
        }
    }

    var addedAt: Date { members.map { $0.addedAt }.max() ?? .distantPast }
    var activity: Date { members.map { $0.lastReadAt ?? $0.addedAt }.max() ?? .distantPast }
    var releaseKey: Int? { members.compactMap { $0.releaseKey }.min() }
}

/// How pages are grouped on screen in paged mode: one per screen, or pairs in landscape.
enum Spreads {
    static func units(count: Int, aspects: [CGFloat]?) -> [[Int]] {
        guard count > 0 else { return [] }
        guard let aspects, aspects.count == count else {
            return (0..<count).map { [$0] }
        }
        // The cover stands alone, and so does any page that is already a double-page scan.
        var result: [[Int]] = [[0]]
        var index = 1
        while index < count {
            let wide = aspects[index] > 1.05
            if !wide && index + 1 < count && aspects[index + 1] <= 1.05 {
                result.append([index, index + 1])
                index += 2
            } else {
                result.append([index])
                index += 1
            }
        }
        return result
    }
}

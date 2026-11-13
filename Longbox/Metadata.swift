import Foundation

// MARK: ComicInfo.xml

/// The fields Longbox reads from a ComicInfo.xml file inside an archive.
struct ComicInfo {
    var series: String?
    var writer: String?
    var publisher: String?
    var summary: String?
    var manga: String?
    var year: Int?
    var month: Int?
    var bookmarks: [Chapter] = []
}

final class ComicInfoParser: NSObject, XMLParserDelegate {
    private var info = ComicInfo()
    private var text = ""
    private var depth = 0
    private var sawRoot = false

    static func parse(_ data: Data) -> ComicInfo? {
        let parser = XMLParser(data: data)
        let reader = ComicInfoParser()
        parser.delegate = reader
        _ = parser.parse()
        return reader.sawRoot ? reader.info : nil
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        depth += 1
        text = ""
        if depth == 1 && elementName == "ComicInfo" {
            sawRoot = true
        }
        if elementName == "Page",
           let mark = attributeDict["Bookmark"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !mark.isEmpty,
           let image = Int(attributeDict["Image"] ?? "") {
            info.bookmarks.append(Chapter(title: mark, startPage: image))
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        defer { depth -= 1 }
        guard depth == 2 else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        switch elementName {
        case "Series": info.series = value
        case "Writer": info.writer = value
        case "Publisher": info.publisher = value
        case "Summary": info.summary = value
        case "Manga": info.manga = value
        case "Year": info.year = Int(value)
        case "Month": info.month = Int(value)
        default: break
        }
    }
}

// MARK: Online lookup

struct MetadataMatch: Identifiable {
    let id = UUID()
    var title: String
    var authors: String?
    var publisher: String?
    var year: Int?
    var month: Int?
    var summary: String?
}

enum LookupError: LocalizedError {
    case badResponse

    var errorDescription: String? {
        "The lookup service didn't answer. Check your connection and try again."
    }
}

/// Looks a title up on Google Books. Only the search text is sent.
enum MetadataLookup {
    private struct Response: Decodable {
        let items: [Item]?
    }

    private struct Item: Decodable {
        let volumeInfo: Info
    }

    private struct Info: Decodable {
        let title: String?
        let subtitle: String?
        let authors: [String]?
        let publisher: String?
        let publishedDate: String?
        let description: String?
    }

    static func search(_ query: String) async throws -> [MetadataMatch] {
        guard var components = URLComponents(string: "https://www.googleapis.com/books/v1/volumes") else {
            throw LookupError.badResponse
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: "12"),
            URLQueryItem(name: "printType", value: "books")
        ]
        guard let url = components.url else { throw LookupError.badResponse }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LookupError.badResponse
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)

        return (decoded.items ?? []).map { item in
            let info = item.volumeInfo
            var title = info.title ?? "Untitled"
            if let subtitle = info.subtitle, !subtitle.isEmpty {
                title += ": " + subtitle
            }
            let dateParts = (info.publishedDate ?? "").split(separator: "-")
            let year = dateParts.first.flatMap { Int($0) }
            let month = dateParts.count > 1 ? Int(dateParts[1]) : nil
            let authors = info.authors?.joined(separator: ", ")
            return MetadataMatch(
                title: title,
                authors: (authors?.isEmpty ?? true) ? nil : authors,
                publisher: info.publisher,
                year: year,
                month: month,
                summary: info.description
            )
        }
    }
}

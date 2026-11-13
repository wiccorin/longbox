import Foundation
import ZIPFoundation

/// Unpacks the image pages of a .cbz (zip) archive into a folder.
enum ZipExtractor {
    static func extract(archive url: URL, to folder: URL) throws -> ExtractedArchive {
        let archive = try Archive(url: url, accessMode: .read)

        var entries: [Entry] = []
        var infoEntry: Entry?
        for entry in archive {
            guard entry.type == .file else { continue }
            if PageNaming.isPage(entry.path) {
                entries.append(entry)
            } else if (entry.path as NSString).lastPathComponent.lowercased() == "comicinfo.xml" {
                infoEntry = entry
            }
        }
        entries.sort { PageNaming.precedes($0.path, $1.path) }

        var result = ExtractedArchive()
        for (index, entry) in entries.enumerated() {
            let name = PageNaming.fileName(index: index, originalPath: entry.path)
            _ = try archive.extract(entry, to: folder.appendingPathComponent(name))
            result.pages.append(name)
            result.folders.append((entry.path as NSString).deletingLastPathComponent)
        }

        if let infoEntry {
            var buffer = Data()
            let read = try? archive.extract(infoEntry) { chunk in
                buffer.append(chunk)
            }
            if read != nil && !buffer.isEmpty {
                result.comicInfo = buffer
            }
        }
        return result
    }
}

import Foundation
import Unrar

/// Unpacks the image pages of a .cbr (rar) archive into a folder.
enum RarExtractor {
    static func extract(archive url: URL, to folder: URL) throws -> ExtractedArchive {
        let archive = try Archive(fileURL: url)
        let all = try archive.entries().filter { !$0.directory }

        let entries = all
            .filter { PageNaming.isPage($0.fileName) }
            .sorted { PageNaming.precedes($0.fileName, $1.fileName) }

        var result = ExtractedArchive()
        for (index, entry) in entries.enumerated() {
            if entry.encrypted { throw ImportError.encrypted }
            let name = PageNaming.fileName(index: index, originalPath: entry.fileName)
            let data = try archive.extract(entry)
            try data.write(to: folder.appendingPathComponent(name))
            result.pages.append(name)
            let normalized = entry.fileName.replacingOccurrences(of: "\\", with: "/")
            result.folders.append((normalized as NSString).deletingLastPathComponent)
        }

        let infoEntry = all.first {
            let normalized = $0.fileName.replacingOccurrences(of: "\\", with: "/")
            return (normalized as NSString).lastPathComponent.lowercased() == "comicinfo.xml"
        }
        if let infoEntry, !infoEntry.encrypted, let data = try? archive.extract(infoEntry), !data.isEmpty {
            result.comicInfo = data
        }
        return result
    }
}

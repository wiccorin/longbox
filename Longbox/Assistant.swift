import Foundation
import Security

/// Keeps the API key in the phone's Keychain.
enum KeyStore {
    private static let service = "com.wiccorin.longbox"
    private static let account = "anthropic-api-key"

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty
        else { return nil }
        return key
    }

    /// Saves the key, or removes it when given nil. Returns false if the Keychain refused.
    @discardableResult
    static func save(_ key: String?) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        guard let key, !key.isEmpty, let data = key.data(using: .utf8) else { return true }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}

struct Pick: Identifiable, Decodable {
    let id = UUID()
    var title: String
    var creators: String?
    var why: String?

    private enum CodingKeys: String, CodingKey {
        case title, creators, why
    }
}

enum AssistantError: LocalizedError {
    case service(String)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .service(let message): return message
        case .unreadable: return "The assistant's answer couldn't be read. Try again."
        }
    }
}

/// Asks Claude for recommendations through Anthropic's API, using the reader's own key.
enum Assistant {
    static let model = "claude-haiku-5-5"

    private static let instructions = """
    You recommend comics and manga. You are given a reader's library with how long they spent reading each title. \
    Weigh the titles they spent the most time with most heavily. Recommend 6 real, published titles that are not \
    already in their library. Reply with only a JSON array of 6 objects, each with the keys "title", "creators" \
    and "why". "why" is one plain sentence that ties the pick to something specific in their reading. No other text.
    """

    /// A plain-text summary of the library, most-read first.
    static func profile(of books: [Book]) -> String {
        let ordered = books.sorted { ($0.secondsRead ?? 0) > ($1.secondsRead ?? 0) }.prefix(60)
        let lines = ordered.map { book -> String in
            var parts: [String] = [book.title]
            if let series = book.series, !series.isEmpty { parts.append("series: \(series)") }
            if let writer = book.writer, !writer.isEmpty { parts.append("by \(writer)") }
            if let publisher = book.publisher, !publisher.isEmpty { parts.append(publisher) }
            if let year = book.year { parts.append(String(year)) }
            let minutes = Int((book.secondsRead ?? 0) / 60)
            parts.append("\(minutes) minutes read")
            parts.append(book.isFinished ? "finished" : (book.isStarted ? "in progress" : "not started"))
            return "- " + parts.joined(separator: "; ")
        }
        return lines.joined(separator: "\n")
    }

    static func recommend(apiKey: String, profile: String, mood: String) async throws -> [Pick] {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw AssistantError.unreadable
        }
        var prompt = "My library:\n" + profile
        let trimmedMood = mood.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedMood.isEmpty {
            prompt += "\n\nRight now I'm in the mood for: " + trimmedMood
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1500,
            "system": instructions,
            "messages": [["role": "user", "content": prompt]]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let detail = (json?["error"] as? [String: Any])?["message"] as? String
            if status == 401 {
                throw AssistantError.service("That API key was rejected. Check it and save it again.")
            }
            throw AssistantError.service(detail ?? "The assistant didn't answer (error \(status)).")
        }

        let blocks = json?["content"] as? [[String: Any]] ?? []
        let text = blocks.compactMap { $0["text"] as? String }.joined()
        guard let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]"), start < end,
              let listData = String(text[start...end]).data(using: .utf8),
              let picks = try? JSONDecoder().decode([Pick].self, from: listData),
              !picks.isEmpty
        else { throw AssistantError.unreadable }
        return picks
    }
}

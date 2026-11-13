import SwiftUI

/// The Picks tab: what to read next from your own box, and AI recommendations for new titles.
struct PicksView: View {
    @EnvironmentObject private var store: LibraryStore

    @State private var detail: Book?
    @State private var hasKey = false
    @State private var keyDraft = ""
    @State private var mood = ""
    @State private var picks: [Pick] = []
    @State private var asking = false
    @State private var message: String?
    @State private var checkedKey = false

    /// Unfinished comics, ranked by how long you've spent with the same series, writer and publisher.
    private var localPicks: [Book] {
        var bySeries: [String: Double] = [:]
        var byWriter: [String: Double] = [:]
        var byPublisher: [String: Double] = [:]
        for book in store.books {
            let time = book.secondsRead ?? 0
            guard time > 0 else { continue }
            if let key = book.seriesKey { bySeries[key, default: 0] += time }
            if let writer = book.writer?.lowercased(), !writer.isEmpty { byWriter[writer, default: 0] += time }
            if let publisher = book.publisher?.lowercased(), !publisher.isEmpty {
                byPublisher[publisher, default: 0] += time
            }
        }

        let candidates = store.books.filter { !$0.isFinished }
        let scored: [(book: Book, score: Double)] = candidates.map { book in
            var score = 0.0
            if let key = book.seriesKey { score += 3 * (bySeries[key] ?? 0) }
            if let writer = book.writer?.lowercased() { score += 2 * (byWriter[writer] ?? 0) }
            if let publisher = book.publisher?.lowercased() { score += byPublisher[publisher] ?? 0 }
            return (book, score)
        }
        let ranked = scored.filter { $0.score > 0 }.sorted { $0.score > $1.score }.map { $0.book }
        if ranked.isEmpty {
            return Array(candidates.sorted { $0.addedAt > $1.addedAt }.prefix(6))
        }
        return Array(ranked.prefix(6))
    }

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            Halftone(color: Theme.panel).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("PICKS")
                        .font(Theme.display(50))
                        .foregroundColor(Theme.yellow)
                        .shadow(color: Theme.red, radius: 0, x: 3, y: 3)

                    fromYourBox
                    assistant
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .sheet(item: $detail) { book in
            BookDetailView(bookID: book.id)
                .environmentObject(store)
        }
        .onAppear {
            if !checkedKey {
                checkedKey = true
                hasKey = KeyStore.load() != nil
            }
        }
    }

    // MARK: From your box

    private var fromYourBox: some View {
        let books = localPicks
        return VStack(alignment: .leading, spacing: 4) {
            CaptionBox(text: "Next from your box")
            if books.isEmpty {
                Text("Add some comics and read for a while. This row fills in from where your reading time goes.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.paper.opacity(0.55))
                    .padding(.top, 12)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 18) {
                        ForEach(books) { book in
                            Button {
                                detail = book
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    CoverView(id: book.id)
                                        .inkPanel(stroke: Theme.paper, shadow: .black)
                                    Text(book.title)
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(Theme.paper)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                                .frame(width: 116)
                            }
                            .buttonStyle(PressDownStyle())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                }
                .padding(.horizontal, -16)
                Text("Ranked on this phone by time spent with the same series, writer and publisher. No AI involved.")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.paper.opacity(0.5))
            }
        }
    }

    // MARK: Assistant

    private var assistant: some View {
        VStack(alignment: .leading, spacing: 16) {
            CaptionBox(text: "Ask the assistant", shadow: Theme.cyan)

            if hasKey {
                field("In the mood for anything? (optional)", text: $mood, secure: false)

                Button(asking ? "THINKING..." : "GET PICKS") {
                    ask()
                }
                .buttonStyle(ComicButtonStyle())
                .disabled(asking || store.books.isEmpty)

                if let message {
                    Text(message)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.paper.opacity(0.8))
                }

                ForEach(picks) { pick in
                    pickCard(pick)
                }

                Text("Sends your titles, series, creators and reading times to Anthropic, billed to your API key. Recommendations come from the model's own knowledge, so check a title exists before hunting for it.")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.paper.opacity(0.5))

                Button("Remove API key") {
                    KeyStore.save(nil)
                    hasKey = false
                    picks = []
                    message = nil
                }
                .font(.footnote.weight(.semibold))
                .foregroundColor(Theme.paper.opacity(0.7))
            } else {
                Text("Get recommendations for new titles from Claude, based on what you've spent the most time reading. This needs your own Anthropic API key, made in the Claude Console. Usage is billed to that key. The key is kept in this phone's Keychain and only sent to Anthropic.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.paper.opacity(0.75))

                field("Paste API key", text: $keyDraft, secure: true)

                Button("SAVE KEY") {
                    let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if KeyStore.save(key) {
                        hasKey = true
                        keyDraft = ""
                        message = nil
                    } else {
                        message = "The key couldn't be saved on this phone."
                    }
                }
                .buttonStyle(ComicButtonStyle())
                .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let message {
                    Text(message)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.paper.opacity(0.8))
                }
            }
        }
    }

    private func field(_ prompt: String, text: Binding<String>, secure: Bool) -> some View {
        let label = Text(prompt).foregroundColor(Color.black.opacity(0.45))
        return Group {
            if secure {
                SecureField("", text: text, prompt: label)
            } else {
                TextField("", text: text, prompt: label)
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundColor(.black)
        .tint(Theme.red)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.paper)
        .overlay(Rectangle().strokeBorder(Color.black, lineWidth: 2.5))
        .background(Rectangle().fill(Theme.cyan).offset(x: 4, y: 4))
        .padding(.trailing, 4)
    }

    private func pickCard(_ pick: Pick) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pick.title)
                .font(Theme.display(22))
                .foregroundColor(.black)
            if let creators = pick.creators, !creators.isEmpty {
                Text(creators.uppercased())
                    .font(Theme.caption(10))
                    .kerning(0.4)
                    .foregroundColor(Color.black.opacity(0.65))
            }
            if let why = pick.why, !why.isEmpty {
                Text(why)
                    .font(.subheadline)
                    .foregroundColor(.black)
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.paper)
        .inkPanel(corner: 2, line: 2.5, offset: 5, stroke: .black, shadow: Theme.yellow)
        .padding(.trailing, 5)
    }

    private func ask() {
        guard !asking, let key = KeyStore.load() else {
            hasKey = false
            return
        }
        asking = true
        message = nil
        let profile = Assistant.profile(of: store.books)
        let wanted = mood
        Task { @MainActor in
            do {
                picks = try await Assistant.recommend(apiKey: key, profile: profile, mood: wanted)
            } catch {
                picks = []
                message = "Couldn't get picks: \(error.localizedDescription)"
            }
            asking = false
        }
    }
}

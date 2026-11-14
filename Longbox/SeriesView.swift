import SwiftUI

/// One series: its issues in reading order, with the next one ready to open.
struct SeriesView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    let seriesKey: String
    let fallbackName: String

    @State private var reading: Book?

    private var issues: [Book] { store.series(seriesKey) }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ink.ignoresSafeArea()
                Halftone(color: Theme.panel).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack {
                            CaptionBox(text: "Series", shadow: Theme.cyan)
                            Spacer()
                            Button {
                                dismiss()
                            } label: {
                                RoundIcon(systemName: "xmark")
                            }
                            .buttonStyle(PressDownStyle())
                            .accessibilityLabel("Close")
                        }

                        let list = issues
                        let name = list.first?.series ?? fallbackName
                        let finished = list.filter { $0.isFinished }.count

                        VStack(alignment: .leading, spacing: 8) {
                            Text(name)
                                .font(Theme.display(34))
                                .foregroundColor(Theme.yellow)
                                .shadow(color: Theme.red, radius: 0, x: 3, y: 3)
                            Text("\(finished) OF \(list.count) READ")
                                .font(Theme.caption(11))
                                .italic()
                                .kerning(0.5)
                                .monospacedDigit()
                                .foregroundColor(Theme.paper.opacity(0.7))
                        }

                        if let next = list.first(where: { !$0.isFinished }) ?? list.first {
                            Button(next.isStarted && !next.isFinished ? "CONTINUE" : "READ NEXT") {
                                reading = next
                            }
                            .buttonStyle(ComicButtonStyle())
                        }

                        if list.isEmpty {
                            Text("This series has no issues left in the box.")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(Theme.paper.opacity(0.55))
                        } else {
                            VStack(alignment: .leading, spacing: 14) {
                                CaptionBox(text: "\(list.count) issues")
                                ForEach(list) { book in
                                    NavigationLink(value: book.id) {
                                        issueRow(book)
                                    }
                                    .buttonStyle(PressDownStyle())
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 40)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                BookDetailView(bookID: id, siblings: issues.map { $0.id })
                    .environmentObject(store)
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
        .presentationDragIndicator(.visible)
        .fullScreenCover(item: $reading) { book in
            ReaderHost(bookID: book.id)
                .environmentObject(store)
        }
    }

    private func issueRow(_ book: Book) -> some View {
        let isCurrent = book.isStarted && !book.isFinished
        return HStack(spacing: 12) {
            CoverView(id: book.id)
                .frame(width: 52)
                .inkPanel(corner: 3, line: 2, offset: 3, stroke: Theme.paper, shadow: .black)

            VStack(alignment: .leading, spacing: 4) {
                if let number = book.numberText {
                    Text("#\(number)")
                        .font(Theme.display(20))
                        .monospacedDigit()
                        .foregroundColor(Theme.yellow)
                }
                Text(book.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(Theme.paper)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(status(book))
                    .font(Theme.caption(10))
                    .kerning(0.4)
                    .monospacedDigit()
                    .foregroundColor(Theme.paper.opacity(0.6))
            }
            Spacer(minLength: 0)

            if isCurrent {
                CaptionBox(text: "Reading", shadow: .black, size: 10)
            } else if book.isFinished {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .black))
                    .foregroundColor(Theme.paper)
                    .accessibilityLabel("Read")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel)
        .inkPanel(
            corner: 4,
            line: 2,
            offset: 4,
            stroke: isCurrent ? Theme.yellow : Theme.paper.opacity(0.35),
            shadow: .black
        )
        .padding(.trailing, 4)
        // Issues you've finished step back.
        .opacity(book.isFinished ? 0.4 : 1)
    }

    private func status(_ book: Book) -> String {
        if book.isFinished { return "FINISHED" }
        if book.isStarted { return "PAGE \(book.currentPage + 1) OF \(book.pageCount)" }
        return "\(book.pageCount) PAGES"
    }
}

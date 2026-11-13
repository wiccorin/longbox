import SwiftUI

/// Files a comic under a series by hand, for when the file name didn't say enough.
struct GroupSeriesView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    let bookID: UUID

    @State private var query = ""
    @State private var newName = ""

    private var book: Book? { store.book(bookID) }

    private func matches(_ text: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return needle.isEmpty || text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private var seriesChoices: [(key: String, name: String, count: Int)] {
        store.seriesList.filter { $0.key != book?.seriesKey && matches($0.name) }
    }

    private var looseComics: [Book] {
        store.books
            .filter { $0.id != bookID && $0.seriesKey == nil && matches($0.title) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                if let book, let series = book.series, book.seriesKey != nil {
                    Section {
                        Button(role: .destructive) {
                            store.ungroup(bookID)
                            dismiss()
                        } label: {
                            Text("Remove from \(series)")
                        }
                    } header: {
                        Text("Currently in \(series)")
                    }
                }

                Section {
                    HStack {
                        TextField("Series name", text: $newName)
                            .autocorrectionDisabled()
                        Button("Group") {
                            store.group(bookID, withSeries: newName)
                            dismiss()
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Name the series")
                }

                if !seriesChoices.isEmpty {
                    Section("Series in your box") {
                        ForEach(seriesChoices, id: \.key) { choice in
                            Button {
                                store.group(bookID, withSeries: choice.name)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(choice.name)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Text(choice.count == 1 ? "1 comic" : "\(choice.count) comics")
                                        .font(.caption)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if !looseComics.isEmpty {
                    Section {
                        ForEach(looseComics) { other in
                            Button {
                                store.group(bookID, withBook: other.id)
                                dismiss()
                            } label: {
                                Text(other.title)
                                    .foregroundColor(.primary)
                            }
                        }
                    } header: {
                        Text("Other comics")
                    } footer: {
                        Text("Picking a comic starts a series with it. Fix issue numbers in Edit if the order comes out wrong.")
                    }
                }
            }
            .searchable(text: $query, prompt: "Find a series or comic")
            .navigationTitle("Group series with")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

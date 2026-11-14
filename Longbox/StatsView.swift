import SwiftUI

/// The Stats tab: where your reading time has gone.
struct StatsView: View {
    @EnvironmentObject private var store: LibraryStore

    private struct Day: Identifiable {
        let date: Date
        let seconds: Double
        let isToday: Bool
        var id: Date { date }
    }

    private struct Ranked: Identifiable {
        let name: String
        let seconds: Double
        var id: String { name }
    }

    private var calendar: Calendar { Calendar.current }

    private var lastTwoWeeks: [Day] {
        let today = calendar.startOfDay(for: Date())
        return (0..<14).reversed().compactMap { back -> Day? in
            guard let date = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            return Day(date: date, seconds: store.seconds(on: date), isToday: back == 0)
        }
    }

    /// Five full weeks ending with the current one.
    private var calendarDays: [Date] {
        let today = calendar.startOfDay(for: Date())
        guard let week = calendar.dateInterval(of: .weekOfYear, for: today),
              let start = calendar.date(byAdding: .day, value: -28, to: week.start)
        else { return [] }
        return (0..<35).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func ranked(by key: (Book) -> String?) -> [Ranked] {
        var totals: [String: Double] = [:]
        var names: [String: String] = [:]
        for book in store.books {
            let time = book.secondsRead ?? 0
            guard time > 0, let name = key(book)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                continue
            }
            let id = name.lowercased()
            totals[id, default: 0] += time
            if names[id] == nil { names[id] = name }
        }
        return totals
            .map { Ranked(name: names[$0.key] ?? $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        let totalSeconds = store.books.reduce(0.0) { $0 + ($1.secondsRead ?? 0) }
        let pages = store.books.reduce(0) { $0 + ($1.isStarted ? $1.currentPage + 1 : 0) }
        let finished = store.books.filter { $0.isFinished }.count

        return ZStack {
            Theme.ink.ignoresSafeArea()
            Halftone(color: Theme.panel).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("STATS")
                        .font(Theme.display(50))
                        .foregroundColor(Theme.yellow)
                        .shadow(color: Theme.red, radius: 0, x: 3, y: 3)

                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                        spacing: 18
                    ) {
                        tile("TIME READ", totalSeconds >= 60 ? ReadingTime.words(totalSeconds).uppercased() : "0M")
                        tile("PAGES READ", "\(pages)")
                        tile("FINISHED", "\(finished)")
                        tile("CLIPPINGS", "\(store.clips.count)")
                        tile("STREAK", store.streak == 1 ? "1 DAY" : "\(store.streak) DAYS")
                        tile("BEST STREAK", store.longestStreak == 1 ? "1 DAY" : "\(store.longestStreak) DAYS")
                    }
                    .padding(.trailing, 4)

                    chart
                    streakCalendar
                    ranking("Most-read series", ranked { $0.series ?? $0.title })
                    ranking("Most-read writers", ranked { $0.writer })
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: Pieces

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Theme.display(28))
                .monospacedDigit()
                .foregroundColor(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(Theme.caption(10))
                .kerning(0.6)
                .foregroundColor(Color.black.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(Theme.paper)
        .inkPanel(corner: 4, line: 2.5, offset: 4, stroke: .black, shadow: Theme.cyan)
    }

    private var chart: some View {
        let days = lastTwoWeeks
        let peak = max(days.map { $0.seconds }.max() ?? 0, 60)
        let height: CGFloat = 130
        return VStack(alignment: .leading, spacing: 14) {
            CaptionBox(text: "Minutes per day, last 14 days")
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(days) { day in
                        let minutes = Int((day.seconds / 60).rounded())
                        VStack(spacing: 4) {
                            Text(minutes > 0 ? "\(minutes)" : " ")
                                .font(.system(size: 9, weight: .heavy))
                                .monospacedDigit()
                                .foregroundColor(.black)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Rectangle()
                                .fill(day.isToday ? Theme.red : Theme.cyan)
                                .frame(height: day.seconds > 0 ? max(height * CGFloat(day.seconds / peak), 4) : 2)
                                .overlay(Rectangle().strokeBorder(Color.black, lineWidth: day.seconds > 0 ? 1.5 : 0))
                            Text(calendar.veryShortWeekdaySymbols[calendar.component(.weekday, from: day.date) - 1])
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundColor(Color.black.opacity(day.isToday ? 1 : 0.55))
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(day.date.formatted(date: .abbreviated, time: .omitted))
                        .accessibilityValue("\(minutes) minutes")
                    }
                }
                .frame(height: height + 34, alignment: .bottom)

                Text("Today is red. Daily tracking began when this screen was added; earlier reading counts in the totals only.")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color.black.opacity(0.6))
            }
            .padding(14)
            .background(Theme.paper)
            .inkPanel(corner: 4, line: 2.5, offset: 5, stroke: .black, shadow: Theme.yellow)
            .padding(.trailing, 5)
        }
    }

    private var streakCalendar: some View {
        let days = calendarDays
        let today = calendar.startOfDay(for: Date())
        let grid = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        return VStack(alignment: .leading, spacing: 14) {
            CaptionBox(text: "Reading days, last 5 weeks")
            LazyVGrid(columns: grid, spacing: 6) {
                ForEach(days.prefix(7), id: \.self) { date in
                    Text(calendar.veryShortWeekdaySymbols[calendar.component(.weekday, from: date) - 1])
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(Theme.paper.opacity(0.6))
                }
                ForEach(days, id: \.self) { date in
                    let read = store.didRead(on: date)
                    let future = date > today
                    Text("\(calendar.component(.day, from: date))")
                        .font(.system(size: 12, weight: .heavy))
                        .monospacedDigit()
                        .foregroundColor(read ? .black : Theme.paper.opacity(future ? 0.2 : 0.6))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(read ? Theme.yellow : Theme.panel)
                        .overlay(
                            Rectangle().strokeBorder(
                                date == today ? Theme.red : Color.black,
                                lineWidth: date == today ? 3 : 1.5
                            )
                        )
                        .accessibilityLabel(date.formatted(date: .abbreviated, time: .omitted))
                        .accessibilityValue(read ? "Read" : "No reading")
                }
            }
            Text("Yellow days had reading. Today is outlined in red.")
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.paper.opacity(0.5))
        }
    }

    private func ranking(_ title: String, _ rows: [Ranked]) -> some View {
        let peak = rows.first?.seconds ?? 1
        return VStack(alignment: .leading, spacing: 14) {
            CaptionBox(text: title)
            if rows.isEmpty {
                Text("Nothing to rank yet. This fills in as you read.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.paper.opacity(0.55))
            } else {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.name)
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(Theme.paper)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(ReadingTime.words(row.seconds).uppercased())
                                .font(Theme.caption(11))
                                .monospacedDigit()
                                .foregroundColor(Theme.yellow)
                        }
                        ChunkyProgress(
                            value: row.seconds / max(peak, 1),
                            fill: Theme.yellow,
                            track: Theme.panel,
                            border: Theme.paper,
                            height: 10
                        )
                    }
                }
            }
        }
    }
}

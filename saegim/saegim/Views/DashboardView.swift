//
//  DashboardView.swift
//  saegim
//

import SwiftUI
import SwiftData

struct DashboardView: View {
    @Query private var cards: [Card]
    @State private var stats: (total: Int, due: Int, learned: Int) = (0, 0, 0)
    @State private var activityData: [Date: Int] = [:]

    var body: some View {
        ScrollHeader(title: "Dashboard") {
            VStack(alignment: .leading, spacing: 24) {
                // Stats row
                HStack(spacing: 16) {
                    StatCard(title: "Total Cards", value: "\(stats.total)", icon: "rectangle.stack", color: .blue)
                    StatCard(title: "Due Today", value: "\(stats.due)", icon: "clock", color: .orange)
                    StatCard(title: "Learned", value: "\(stats.learned)", icon: "checkmark.circle", color: .green)
                }

                // Activity widget
                VStack(alignment: .leading, spacing: 12) {
                    Text("Activity")
                        .font(.headline)

                    ActivityGrid(activityData: activityData)
                }
            }
            .padding(32)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .onAppear { updateStats() }
        .onChange(of: cards.count) { _, _ in updateStats() }
    }

    private func updateStats() {
        var due = 0
        var learned = 0
        let calendar = Calendar.current
        var activity: [Date: Int] = [:]

        for card in cards {
            if card.isDue { due += 1 }
            if card.repetitions > 0 { learned += 1 }
            if let lastReview = card.lastReviewDate {
                let day = calendar.startOfDay(for: lastReview)
                activity[day, default: 0] += 1
            }
        }

        stats = (cards.count, due, learned)
        activityData = activity
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

            Text(value)
                .font(.system(size: 32, weight: .bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ActivityGrid: View {
    let activityData: [Date: Int]

    private let columns = 53 // weeks in a year
    private let rows = 7 // days in a week
    private let cellSize: CGFloat = 12
    private let cellSpacing: CGFloat = 3

    private func dateFor(week: Int, day: Int) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayWeekday = calendar.component(.weekday, from: today)

        // Calculate the start of the grid (53 weeks ago, adjusted to start on Sunday)
        let daysFromStart = (columns - 1 - week) * 7 + (todayWeekday - 1 - day)
        return calendar.date(byAdding: .day, value: -daysFromStart, to: today) ?? today
    }

    private func activityLevel(for date: Date) -> Int {
        let count = activityData[date] ?? 0
        if count == 0 { return 0 }
        if count <= 2 { return 1 }
        if count <= 5 { return 2 }
        if count <= 10 { return 3 }
        return 4
    }

    private func colorFor(level: Int) -> Color {
        switch level {
        case 0: return Color.primary.opacity(0.1)
        case 1: return Color.green.opacity(0.3)
        case 2: return Color.green.opacity(0.5)
        case 3: return Color.green.opacity(0.7)
        default: return Color.green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Month labels
            HStack(spacing: 0) {
                ForEach(monthLabels(), id: \.offset) { label in
                    Text(label.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: CGFloat(label.weeks) * (cellSize + cellSpacing), alignment: .leading)
                }
            }
            .padding(.leading, 20)

            HStack(alignment: .top, spacing: 4) {
                // Day labels
                VStack(spacing: cellSpacing) {
                    ForEach(0..<rows, id: \.self) { day in
                        Text(dayLabel(for: day))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: cellSize)
                    }
                }

                // Grid
                HStack(spacing: cellSpacing) {
                    ForEach(0..<columns, id: \.self) { week in
                        VStack(spacing: cellSpacing) {
                            ForEach(0..<rows, id: \.self) { day in
                                let date = dateFor(week: week, day: day)
                                let level = activityLevel(for: date)

                                RoundedRectangle(cornerRadius: 2)
                                    .fill(colorFor(level: level))
                                    .frame(width: cellSize, height: cellSize)
                                    .help(tooltipFor(date: date, count: activityData[date] ?? 0))
                            }
                        }
                    }
                }
            }

            // Legend
            HStack(spacing: 4) {
                Spacer()
                Text("Less")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colorFor(level: level))
                        .frame(width: cellSize, height: cellSize)
                }

                Text("More")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
    }

    private func dayLabel(for index: Int) -> String {
        switch index {
        case 1: return "M"
        case 3: return "W"
        case 5: return "F"
        default: return ""
        }
    }

    private func monthLabels() -> [(name: String, weeks: Int, offset: Int)] {
        let calendar = Calendar.current
        var result: [(name: String, weeks: Int, offset: Int)] = []
        var currentMonth = -1
        var weekCount = 0
        var offset = 0

        for week in 0..<columns {
            let date = dateFor(week: week, day: 0)
            let month = calendar.component(.month, from: date)

            if month != currentMonth {
                if currentMonth != -1 {
                    result.append((
                        name: calendar.shortMonthSymbols[currentMonth - 1],
                        weeks: weekCount,
                        offset: offset
                    ))
                    offset += weekCount
                }
                currentMonth = month
                weekCount = 1
            } else {
                weekCount += 1
            }
        }

        // Add last month
        if currentMonth != -1 {
            result.append((
                name: calendar.shortMonthSymbols[currentMonth - 1],
                weeks: weekCount,
                offset: offset
            ))
        }

        return result
    }

    private func tooltipFor(date: Date, count: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let dateStr = formatter.string(from: date)

        if count == 0 {
            return "No reviews on \(dateStr)"
        } else if count == 1 {
            return "1 review on \(dateStr)"
        } else {
            return "\(count) reviews on \(dateStr)"
        }
    }
}

#Preview {
    DashboardView()
        .modelContainer(for: [Card.self, Deck.self], inMemory: true)
}

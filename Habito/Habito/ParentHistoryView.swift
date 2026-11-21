//
//  ParentHistoryView.swift
//  Habito
//
//  One card per day, newest first: how many tasks were done, a progress
//  bar and every task of that day. Older days load as you scroll.
//

import SwiftUI

struct HistoryView: View {
    @Environment(ParentSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    @State private var days: [HistoryDay] = []
    @State private var oldestLoaded = Calendar.current.startOfDay(for: Date())
    @State private var loaded = false
    @State private var isLoadingMore = false
    @State private var canLoadMore = true
    @State private var loadError: String?

    private static let pageDays = 7

    /// Days on which no task was due are left out.
    private var visibleDays: [HistoryDay] { days.filter { $0.total > 0 } }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if !loaded {
                        ProgressView().padding(.top, 40)
                    } else {
                        if let loadError {
                            Text(loadError)
                                .font(.footnote)
                                .foregroundStyle(Color.habitoRed)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }
                        if visibleDays.isEmpty && loadError == nil {
                            VStack(spacing: 4) {
                                Text("No history yet").font(.headline)
                                Text("Days appear here once tasks have been due.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                            .padding(.horizontal, 16)
                            .habitoCard()
                        }
                        ForEach(visibleDays) { day in
                            DayCard(day: day)
                        }
                        if canLoadMore && !days.isEmpty {
                            Color.clear
                                .frame(height: 1)
                                .onAppear { Task { await loadMore() } }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(HabitoBackground())
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await Task { await load() }.value
            }
        }
        .task { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
    }

    /// The last seven days, from scratch.
    private func load() async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let from = calendar.date(byAdding: .day, value: -(Self.pageDays - 1), to: today) ?? today
        do {
            let page = try await HabitoAPI.history(from: from, to: today)
            days = page
            oldestLoaded = from
            canLoadMore = page.contains { $0.total > 0 }
            loadError = nil
        } catch {
            if session.handle(error) { return }
            loadError = error.habitoMessage
        }
        loaded = true
    }

    /// The seven days before the oldest one shown. Stops once a whole week had no tasks.
    private func loadMore() async {
        guard canLoadMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let calendar = Calendar.current
        guard
            let to = calendar.date(byAdding: .day, value: -1, to: oldestLoaded),
            let from = calendar.date(byAdding: .day, value: -(Self.pageDays - 1), to: to)
        else { return }
        do {
            let page = try await HabitoAPI.history(from: from, to: to)
            days += page
            oldestLoaded = from
            canLoadMore = page.contains { $0.total > 0 }
        } catch {
            if session.handle(error) { return }
            // Leave what is on screen alone; scrolling up and down tries again.
        }
    }
}

private struct DayCard: View {
    let day: HistoryDay

    private var fraction: Double { day.total == 0 ? 0 : Double(day.done) / Double(day.total) }

    private var label: String {
        guard let date = HabitoAPI.date(fromDay: day.date) else { return day.date }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    /// Done first, then what is still open, then what was missed.
    private var sortedTasks: [HistoryTask] {
        let rank = ["done": 0, "open": 1, "upcoming": 2, "missed": 3]
        return (day.tasks ?? []).enumerated()
            .sorted { (rank[$0.element.status] ?? 4, $0.offset) < (rank[$1.element.status] ?? 4, $1.offset) }
            .map(\.element)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.headline)
                Spacer()
                Text("\(day.done) of \(day.total) done")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HabitoProgressBar(fraction: fraction, height: 4).padding(.top, 9)

            if !sortedTasks.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sortedTasks.enumerated()), id: \.offset) { _, task in
                        HStack(spacing: 9) {
                            StatusIcon(status: task.status, size: 14)
                            Text(task.title)
                                .font(.subheadline)
                                .foregroundStyle(task.status == "done" || task.status == "missed" ? .primary : .secondary)
                        }
                        .frame(height: 26)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(task.title), \(task.status)")
                    }
                }
                .padding(.top, 11)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .habitoCard()
        .accessibilityElement(children: .contain)
    }
}

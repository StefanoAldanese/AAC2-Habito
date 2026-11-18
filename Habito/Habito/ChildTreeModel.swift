//
//  ChildTreeModel.swift
//  Habito
//
//  The tree screen's state and server work, with no animation in it: today's
//  tasks, which spot on the tree each apple hangs on, which apples are new,
//  refreshing on a shake, and marking a task done when an apple is eaten.
//

import Foundation
import Observation

@MainActor
@Observable
final class ChildTreeModel {
    /// What a finished server call means for the screen.
    enum Outcome: Equatable {
        case done
        case gone(String)        // the task no longer exists or is not due today
        case failed(String)      // try again later; the apple goes back on the tree
        case signedOut
    }

    /// The day the server says it is, and its tasks.
    private(set) var date: String?
    private(set) var tasks: [TaskItem] = []
    private(set) var loaded = false
    private(set) var loadError: String?
    private(set) var isRefreshing = false

    /// Apples that appeared after the first load: they grow in slowly.
    private(set) var arrivals: Set<String> = []

    /// Spot on the tree for each open task. A task keeps its spot until it is done.
    private var spots: [String: Int] = [:]
    /// Every task id seen since the screen opened, to tell new tasks apart.
    private var known: Set<String> = []
    private var lastShakeRefresh = Date.distantPast

    static let shakeCooldown: TimeInterval = 2

    var openTasks: [TaskItem] { tasks.filter { !$0.isDone } }
    var doneCount: Int { tasks.filter(\.isDone).count }

    /// Today's share of tasks done, 0 to 1. Zero when there are no tasks.
    var todayFraction: Double {
        tasks.isEmpty ? 0 : Double(doneCount) / Double(tasks.count)
    }

    /// Apples on the tree: open tasks that have a spot (at most ten at a time).
    var hanging: [(task: TaskItem, spot: Int)] {
        openTasks.compactMap { task in spots[task.id].map { (task, $0) } }
            .sorted { $0.spot < $1.spot }
    }

    // MARK: Loading

    /// Loads today's tasks. Returns false when the device was signed out.
    @discardableResult
    func load() async -> Bool {
        do {
            let fresh = try await HabitoAPI.childToday()
            apply(fresh)
            loadError = nil
        } catch {
            if (error as? APIError)?.isSignedOut == true { return false }
            if !error.isCancellation, !loaded { loadError = error.habitoMessage }
        }
        loaded = true
        return true
    }

    /// A shake: fetch new tasks, unless a refresh is running or one ran moments ago.
    /// Returns whether a refresh was started.
    func refreshAfterShake() async -> Bool? {
        let now = Date()
        guard !isRefreshing, now.timeIntervalSince(lastShakeRefresh) >= Self.shakeCooldown else { return nil }
        lastShakeRefresh = now
        isRefreshing = true
        defer { isRefreshing = false }
        return await load()
    }

    private func apply(_ fresh: TodayList) {
        let firstLoad = !loaded || date != fresh.date
        if date != fresh.date {
            // A new day: every apple is today's, none of them "arrives".
            spots = [:]
            known = []
            arrivals = []
        }
        date = fresh.date
        tasks = fresh.tasks

        let open = fresh.tasks.filter { !$0.isDone }
        let openIDs = Set(open.map(\.id))
        spots = spots.filter { openIDs.contains($0.key) }
        var free = Array(Set(0..<TreeLayout.spotCount).subtracting(spots.values)).sorted()
        for task in open where spots[task.id] == nil {
            guard !free.isEmpty else { break }
            spots[task.id] = free.removeFirst()
        }

        let ids = Set(fresh.tasks.map(\.id))
        if !firstLoad {
            arrivals.formUnion(ids.subtracting(known))
        }
        arrivals.formIntersection(openIDs)
        known.formUnion(ids)
    }

    /// The view calls this once an apple has finished growing in.
    func arrived(_ id: String) {
        arrivals.remove(id)
    }

    // MARK: Completing

    /// The apple was eaten: tell the server the task is done. The server records it and
    /// sends the parent's notification; then today's list is reloaded.
    func complete(_ task: TaskItem) async -> Outcome {
        do {
            try await HabitoAPI.markDone(id: task.id)
        } catch {
            let api = error as? APIError
            if api?.isSignedOut == true { return .signedOut }
            switch api?.code {
            case "not_due_today":
                _ = await load()
                return .gone("This task isn’t for today any more.")
            case "not_found":
                _ = await load()
                return .gone("This task was removed.")
            default:
                return .failed(error.habitoMessage)
            }
        }
        // Mark it done right away so the bar moves, then confirm with the server.
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            let old = tasks[index]
            tasks[index] = TaskItem(id: old.id, title: old.title, description: old.description,
                                    repeatKind: old.repeatKind, dueDate: old.dueDate, status: "done", doneAt: Date())
            spots[task.id] = nil
        }
        _ = await load()
        return .done
    }

    /// Today's list in the shape the game counts perfect days from.
    var todayList: TodayList? {
        date.map { TodayList(date: $0, tasks: tasks) }
    }
}

//
//  ChildTreeModel.swift
//  Habito
//
//  The tree screen's state and server work, with no animation in it: today's
//  tasks, which spot on the tree each apple hangs on, which apples are new,
//  and refreshing on a shake.
//
//  An apple's life: it hangs locked while its task is open. "I did it!" marks
//  the task done on the server (which notifies the parent) and the apple turns
//  ripe: now it can be picked. Feeding it to the caterpillar eats it; that part
//  stays on this phone. Ripe apples are remembered for the day.
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

    /// Tasks done on the server whose apple has not been eaten yet: these can be picked.
    private(set) var ripe: Set<String>

    /// Spot on the tree for each apple. A task keeps its spot until its apple is eaten.
    private var spots: [String: Int] = [:]
    /// Every task id seen since the screen opened, to tell new tasks apart.
    private var known: Set<String> = []
    private var lastShakeRefresh = Date.distantPast

    static let shakeCooldown: TimeInterval = 2

    private let defaults: UserDefaults
    private enum Key {
        static let ripeDate = "child.ripe.date"
        static let ripeIDs = "child.ripe.ids"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ripe = Set(defaults.stringArray(forKey: Key.ripeIDs) ?? [])
        date = defaults.string(forKey: Key.ripeDate)
    }

    /// Tasks whose apple is still on the tree: open ones (locked) and ripe ones.
    var onTree: [TaskItem] { tasks.filter { !$0.isDone || ripe.contains($0.id) } }
    private var eatenCount: Int { tasks.filter { $0.isDone && !ripe.contains($0.id) }.count }

    func isRipe(_ id: String) -> Bool { ripe.contains(id) }

    /// Today's share of apples eaten, 0 to 1. Zero when there are no tasks.
    var todayFraction: Double {
        tasks.isEmpty ? 0 : Double(eatenCount) / Double(tasks.count)
    }

    /// Apples on the tree with their spot (at most ten at a time).
    var hanging: [(task: TaskItem, spot: Int)] {
        onTree.compactMap { task in spots[task.id].map { (task, $0) } }
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
            // A new day: every apple is today's, none of them "arrives", none is ripe.
            spots = [:]
            known = []
            arrivals = []
            ripe = []
        }
        date = fresh.date
        tasks = fresh.tasks

        // A ripe apple stays ripe while its task is done (the parent can undo it).
        ripe.formIntersection(fresh.tasks.filter(\.isDone).map(\.id))
        saveRipe()

        let hangingTasks = onTree
        let hangingIDs = Set(hangingTasks.map(\.id))
        spots = spots.filter { hangingIDs.contains($0.key) }
        var free = Array(Set(0..<TreeLayout.spotCount).subtracting(spots.values)).sorted()
        for task in hangingTasks where spots[task.id] == nil {
            guard !free.isEmpty else { break }
            spots[task.id] = free.removeFirst()
        }

        let ids = Set(fresh.tasks.map(\.id))
        if !firstLoad {
            arrivals.formUnion(ids.subtracting(known))
        }
        arrivals.formIntersection(hangingIDs)
        known.formUnion(ids)
    }

    /// The view calls this once an apple has finished growing in.
    func arrived(_ id: String) {
        arrivals.remove(id)
    }

    // MARK: Completing

    /// "I did it!": tell the server the task is done. The server records it and sends the
    /// parent's notification; the apple turns ripe and can be picked.
    func markDone(_ task: TaskItem) async -> Outcome {
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
        ripe.insert(task.id)
        saveRipe()
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            let old = tasks[index]
            tasks[index] = TaskItem(id: old.id, title: old.title, description: old.description,
                                    repeatKind: old.repeatKind, dueDate: old.dueDate, status: "done", doneAt: Date())
        }
        _ = await load()
        return .done
    }

    /// The caterpillar ate a ripe apple. Nothing to tell the server: the task is already done.
    func eat(_ task: TaskItem) {
        guard ripe.remove(task.id) != nil else { return }
        spots[task.id] = nil
        saveRipe()
    }

    private func saveRipe() {
        defaults.set(date, forKey: Key.ripeDate)
        defaults.set(ripe.sorted(), forKey: Key.ripeIDs)
    }

    /// Today's list in the shape the game counts perfect days from: an apple not yet eaten
    /// counts as not done, so the day is perfect once the last apple is eaten.
    var todayList: TodayList? {
        date.map { day in
            TodayList(date: day, tasks: tasks.map { task in
                guard ripe.contains(task.id) else { return task }
                return TaskItem(id: task.id, title: task.title, description: task.description,
                                repeatKind: task.repeatKind, dueDate: task.dueDate, status: "open", doneAt: nil)
            })
        }
    }
}

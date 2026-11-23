//
//  ParentHomeView.swift
//  Habito
//
//  The parent's main screen: today's progress and today's tasks. Tap a task
//  to open it and see its description, Undo completion, Edit task and
//  Delete task.
//

import SwiftUI

struct HomeView: View {
    @Environment(ParentSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    @State private var tasks: [TaskItem] = []
    @State private var loaded = false
    @State private var loadError: String?
    @State private var expandedID: String?
    @State private var editor: TaskEditorTarget?
    @State private var pendingDelete: TaskItem?
    @State private var confirmLogOut = false
    @State private var actionError: String?
    /// "Ali finished Make the bed", shown for a few seconds when the child eats an apple.
    @State private var finished: String?
    @State private var finishedID = 0
    @State private var finishedCount = 0

    /// How often Home checks for tasks the child finished, while it is on screen.
    private static let pollInterval: Duration = .seconds(15)

    private var title: String {
        session.childName.isEmpty ? "Tasks" : "\(session.childName)’s Tasks"
    }

    private var doneCount: Int { tasks.filter(\.isDone).count }

    /// Tasks still to do come first; finished ones sink to the bottom.
    private var ordered: [TaskItem] {
        tasks.filter { !$0.isDone } + tasks.filter(\.isDone)
    }

    private enum Block: Identifiable {
        case group([TaskItem])
        case expanded(TaskItem)

        var id: String {
            switch self {
            case .group(let items): "group-" + items.map(\.id).joined(separator: ",")
            case .expanded(let item): "open-" + item.id
            }
        }
    }

    /// The open task is a card of its own; the tasks around it stay grouped in lists.
    private var blocks: [Block] {
        var result: [Block] = []
        var run: [TaskItem] = []
        for task in ordered {
            if task.id == expandedID {
                if !run.isEmpty { result.append(.group(run)); run = [] }
                result.append(.expanded(task))
            } else {
                run.append(task)
            }
        }
        if !run.isEmpty { result.append(.group(run)) }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ProgressCard(done: doneCount, total: tasks.count)
                    content
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(HabitoBackground())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { codeMenu }
                ToolbarItem(placement: .topBarTrailing) { addButton }
            }
            .refreshable { await load() }
        }
        .task { await load() }
        .task { await session.load() }
        .task {
            // While Home is on screen, keep up with the child's phone.
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                if Task.isCancelled { break }
                if scenePhase == .active { await load() }
            }
        }
        .overlay(alignment: .top) {
            if let finished {
                Label(finished, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.habitoGreenDeep)
                    .lineLimit(2)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .habitoGlass(in: Capsule())
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { self.finished = nil }
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(.snappy, value: finished)
        .sensoryFeedback(.success, trigger: finishedCount)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
        .sheet(item: $editor) { target in
            TaskEditorSheet(target: target) { Task { await load() } }
        }
        // A centered dialog with Cancel and Delete side by side, like Log out below.
        .alert(
            pendingDelete.map { "Delete “\($0.title)”?" } ?? "Delete task?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { task in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { delete(task) }
        } message: { _ in
            Text("Days already in History stay as they are.")
        }
        .alert("Log out of Habito?", isPresented: $confirmLogOut) {
            Button("Cancel", role: .cancel) {}
            Button("Log out", role: .destructive) { Task { await session.logOut() } }
        }
        .alert(
            "Couldn’t finish that",
            isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
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
            if tasks.isEmpty && loadError == nil {
                VStack(spacing: 4) {
                    Text("No tasks for today").font(.headline)
                    Text("Tap + to add one.").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .habitoCard()
            }
            ForEach(blocks) { block in
                switch block {
                case .group(let items):
                    TaskGroupCard(tasks: items, onOpen: toggle)
                case .expanded(let item):
                    ExpandedTaskCard(
                        task: item,
                        onCollapse: { toggle(item) },
                        onUndo: { undo(item) },
                        onEdit: { editor = .edit(item) },
                        onDelete: { pendingDelete = item }
                    )
                }
            }
        }
    }

    // MARK: Toolbar

    private var codeMenu: some View {
        Menu {
            Button {
                UIPasteboard.general.string = session.roomCode
            } label: {
                Label("Copy code", systemImage: "doc.on.doc")
            }
            .disabled(session.roomCode.isEmpty)
            Button(role: .destructive) {
                confirmLogOut = true
            } label: {
                Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            HStack(spacing: 6) {
                Text("Code").foregroundStyle(.secondary)
                Text(session.roomCode.isEmpty ? "······" : session.roomCode)
                    .fontWeight(.semibold)
                    .tracking(0.9)
                    .foregroundStyle(.primary)
            }
        }
        .tint(.primary) // the toolbar would otherwise colour the whole label green
        .accessibilityLabel(session.roomCode.isEmpty ? "Room code" : "Room code \(session.roomCode.map(String.init).joined(separator: " "))")
        .accessibilityHint("Opens a menu to copy the code or log out")
    }

    private var addButton: some View {
        Button {
            editor = .new
        } label: {
            Image(systemName: "plus")
        }
        .habitoProminentButton()
        .accessibilityLabel("New task")
    }

    // MARK: Actions

    private func toggle(_ task: TaskItem) {
        withAnimation(.snappy) {
            expandedID = expandedID == task.id ? nil : task.id
        }
    }

    private func undo(_ task: TaskItem) {
        // If the mark is already gone (another phone, or the day changed), the
        // reload below simply shows how things are now.
        Task { await run(ignoring: "not_done") { try await HabitoAPI.undo(id: task.id) } }
    }

    private func delete(_ task: TaskItem) {
        Task {
            await run { try await HabitoAPI.deleteTask(id: task.id) }
            expandedID = nil
        }
    }

    private func run(ignoring code: String? = nil, _ work: () async throws -> Void) async {
        do {
            try await work()
        } catch {
            if session.handle(error) { return }
            if (error as? APIError)?.code != code { actionError = error.habitoMessage }
        }
        await load()
    }

    /// Tasks that were open on the last check and are done now: the child just finished them.
    private func announceFinished(old: [TaskItem], new: [TaskItem]) {
        let wasOpen = Set(old.filter { !$0.isDone }.map(\.id))
        let justDone = new.filter { $0.isDone && wasOpen.contains($0.id) }
        guard !justDone.isEmpty else { return }
        let who = session.childName.isEmpty ? "Your child" : session.childName
        finished = justDone.count == 1
            ? "\(who) finished “\(justDone[0].title)”"
            : "\(who) finished \(justDone.count) tasks"
        finishedCount += 1
        finishedID += 1
        let id = finishedID
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if finishedID == id { finished = nil }
        }
        AccessibilityNotification.Announcement(finished ?? "").post()
    }

    private func load() async {
        do {
            let fresh = try await HabitoAPI.today()
            if loaded { announceFinished(old: tasks, new: fresh) }
            tasks = fresh
            loadError = nil
            if let id = expandedID, !fresh.contains(where: { $0.id == id }) { expandedID = nil }
        } catch {
            if session.handle(error) { return }
            loadError = error.habitoMessage
        }
        loaded = true
    }
}

// MARK: - Pieces

private struct ProgressCard: View {
    let done: Int
    let total: Int

    private var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
    private var percent: Int { Int((fraction * 100).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Daily progress").font(.headline)
                    Text(total == 0 ? "No tasks today" : "\(done) of \(total) completed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if total > 0 {
                    Text("\(percent)%")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.habitoGreenDeep)
                }
            }
            HabitoProgressBar(fraction: fraction, height: 6)
        }
        .padding(.horizontal, 16)
        .padding(.top, 15)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .habitoCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(total == 0 ? "Daily progress. No tasks today." : "Daily progress. \(done) of \(total) completed, \(percent) percent.")
    }
}

/// "Completed at 8:15 AM" in green, or "Not completed · Due today".
private struct StatusLine: View {
    let task: TaskItem

    var body: some View {
        if task.isDone {
            let time = task.doneAt?.formatted(date: .omitted, time: .shortened)
            Text(time.map { "Completed at \($0)" } ?? "Completed")
                .font(.footnote)
                .foregroundStyle(Color.habitoGreenDeep)
        } else {
            Text("Not completed · Due today")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// Tasks that are not open, in one card with a line between them.
private struct TaskGroupCard: View {
    let tasks: [TaskItem]
    let onOpen: (TaskItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                if index > 0 { Divider().padding(.leading, 54) }
                Button { onOpen(task) } label: { TaskRow(task: task) }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows the task’s details")
            }
        }
        .habitoCard()
    }
}

private struct TaskRow: View {
    let task: TaskItem

    var body: some View {
        HStack(spacing: 12) {
            StatusIcon(status: task.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                StatusLine(task: task)
            }
            Spacer(minLength: 8)
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.habitoGreenDeep)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// The task the parent opened: description, Undo completion, Edit task, Delete task.
private struct ExpandedTaskCard: View {
    let task: TaskItem
    let onCollapse: () -> Void
    let onUndo: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onCollapse) {
                HStack(alignment: .top, spacing: 12) {
                    StatusIcon(status: task.status).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(task.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        StatusLine(task: task)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 17)
            .accessibilityHint("Closes the details")

            if !task.descriptionText.isEmpty {
                Text(task.descriptionText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 13)
            }

            if task.isDone {
                Button(action: onUndo) {
                    Label("Undo completion", systemImage: "arrow.uturn.backward")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.habitoGreenDeep)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.habitoGreen.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }

            Divider().padding(.top, 16)

            HStack(spacing: 0) {
                Button(action: onEdit) {
                    Label("Edit task", systemImage: "pencil")
                        .foregroundStyle(Color.habitoGreenDeep)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .contentShape(Rectangle())
                }
                Divider().frame(height: 28)
                Button(role: .destructive, action: onDelete) {
                    Label("Delete task", systemImage: "trash")
                        .foregroundStyle(Color.habitoRed)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
        }
        .habitoCard()
    }
}

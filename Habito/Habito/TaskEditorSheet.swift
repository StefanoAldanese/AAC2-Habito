//
//  TaskEditorSheet.swift
//  Habito
//
//  One sheet for both New Task (from the + button) and Edit Task (from an
//  open task). X discards, the green check saves.
//

import SwiftUI

enum TaskEditorTarget: Identifiable {
    case new
    case edit(TaskItem)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let task): task.id
        }
    }
}

struct TaskEditorSheet: View {
    let target: TaskEditorTarget
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ParentSession.self) private var session

    @State private var title: String
    @State private var details: String
    @State private var daily: Bool
    @State private var isBusy = false
    @State private var errorText: String?
    @FocusState private var titleFocused: Bool

    private static let titleLimit = 80
    private static let detailsLimit = 500

    init(target: TaskEditorTarget, onSaved: @escaping () -> Void) {
        self.target = target
        self.onSaved = onSaved
        switch target {
        case .new:
            _title = State(initialValue: "")
            _details = State(initialValue: "")
            _daily = State(initialValue: true)
        case .edit(let task):
            _title = State(initialValue: task.title)
            _details = State(initialValue: task.descriptionText)
            _daily = State(initialValue: task.isDaily)
        }
    }

    private var original: TaskItem? {
        if case .edit(let task) = target { return task }
        return nil
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedDetails: String { details.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var titleChanged: Bool { trimmedTitle != original?.title }
    private var detailsChanged: Bool { trimmedDetails != original?.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var dailyChanged: Bool { daily != original?.isDaily }

    /// A title is needed, and an edit needs something to have changed.
    private var canSave: Bool {
        guard !trimmedTitle.isEmpty, !isBusy else { return false }
        return original == nil || titleChanged || detailsChanged || dailyChanged
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(spacing: 0) {
                        TextField("Title", text: $title)
                            .focused($titleFocused)
                            .submitLabel(.done)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 52)
                        Divider().padding(.leading, 16)
                        TextField("Description", text: $details, axis: .vertical)
                            .lineLimit(3...6)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 15)
                            .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
                    }
                    .habitoCard()

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Repeat Daily", isOn: $daily)
                            .tint(.habitoGreen)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 52)
                            .habitoCard()
                        Text("Turn off for a one-time task, due today.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                    }

                    if let errorText {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(Color.habitoRed)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(original == nil ? "New Task" : "Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .tint(.primary)
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        if isBusy { ProgressView() } else { Image(systemName: "checkmark") }
                    }
                    .habitoProminentButton()
                    .disabled(!canSave)
                    .accessibilityLabel("Save")
                }
            }
            .onChange(of: title) { _, new in
                if new.count > Self.titleLimit { title = String(new.prefix(Self.titleLimit)) }
            }
            .onChange(of: details) { _, new in
                if new.count > Self.detailsLimit { details = String(new.prefix(Self.detailsLimit)) }
            }
            .onAppear { if original == nil { titleFocused = true } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isBusy)
    }

    private func save() async {
        guard canSave else { return }
        isBusy = true
        errorText = nil
        defer { isBusy = false }
        do {
            if let original {
                // Only what changed, so an edit can never overwrite something it did not touch.
                var fields: [String: Any] = [:]
                if titleChanged { fields["title"] = trimmedTitle }
                if detailsChanged { fields["description"] = trimmedDetails }
                if dailyChanged { fields["repeat"] = daily ? "daily" : "once" }
                try await HabitoAPI.updateTask(id: original.id, fields: fields)
            } else {
                try await HabitoAPI.createTask(title: trimmedTitle, description: trimmedDetails, daily: daily)
            }
            onSaved()
            dismiss()
        } catch {
            if session.handle(error) { return }
            errorText = error.habitoMessage
        }
    }
}

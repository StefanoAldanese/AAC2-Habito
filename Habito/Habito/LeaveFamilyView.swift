//
//  LeaveFamilyView.swift
//  Habito
//
//  Leaving the family, from the top of the Butterflies page. So that a tap by
//  accident (or a curious friend) cannot do it, the child types the family's
//  six-character code again, in the same boxes as when they joined.
//

import SwiftUI
import KeychainSwift

struct LeaveFamilyView: View {
    /// Called once the right code was typed: sign this phone out of the family.
    let onLeave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var code = ""
    @State private var errorText: String?
    @State private var shakes = 0
    @State private var isChecking = false
    @FocusState private var isFocused: Bool

    private var isComplete: Bool { code.count == RoomCodeEntry.length }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                OnboardingHeader(
                    title: "Leave this family?",
                    subtitle: "Type your family’s 6-character code to leave.\nYour butterflies stay on this phone."
                )
                .padding(.top, 24)

                RoomCodeEntry(code: $code, isError: errorText != nil, shakes: shakes, isFocused: $isFocused) {
                    Task { await check() }
                }
                .padding(.top, 40)

                RoomCodeError(text: errorText)
                    .padding(.top, 20)

                Button(role: .destructive) { Task { await check() } } label: {
                    ZStack {
                        Text("Leave family").opacity(isChecking ? 0 : 1)
                        if isChecking { ProgressView().tint(.white) }
                    }
                    .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(Color.habitoRed)
                .disabled(!isComplete || isChecking)
                .padding(.top, 12)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.25), value: errorText)
            .background(HabitoBackground())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sensoryFeedback(.error, trigger: shakes)
            .onChange(of: code) {
                if errorText != nil { errorText = nil }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(400))
                isFocused = true
            }
        }
    }

    private func check() async {
        guard isComplete, !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        // The code saved when this phone joined; phones that joined before it was saved ask the server.
        var expected = KeychainSwift().get(HabitoAPI.childRoomCodeKey)
        if expected == nil {
            do {
                expected = try await HabitoAPI.childRoomCode()
            } catch let error as APIError where error.isSignedOut {
                // This phone is no longer in the family anyway (the code was used on another phone).
                leave()
                return
            } catch {
                if error.isCancellation { return }
                show("Couldn’t check the code right now. Try again when you’re online.")
                return
            }
        }
        guard let expected else {
            show("Couldn’t check the code right now. Try again later.")
            return
        }
        if code == expected.uppercased() {
            leave()
        } else {
            show("That’s not your family’s code. Ask your parent for it.")
        }
    }

    private func leave() {
        isFocused = false
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            onLeave()
        }
    }

    private func show(_ text: String) {
        errorText = text
        if !reduceMotion {
            withAnimation(.linear(duration: 0.45)) { shakes += 1 }
        } else {
            shakes += 1
        }
        AccessibilityNotification.Announcement(text).post()
    }
}

#Preview {
    Text("Butterflies").sheet(isPresented: .constant(true)) { LeaveFamilyView {} }
}

//
//  ChildInsertCodeView.swift
//  Habito
//
//  The child's first screen: the six-character room code from the parent's
//  phone, one box per character like a one-time-code screen. A wrong code
//  turns the boxes red, shakes them and explains underneath.
//
//  The boxes themselves (RoomCodeEntry) are used again when the child leaves
//  the family: they must type the code once more.
//

import SwiftUI
import KeychainSwift

struct ChildInsertCodeView: View {
    @State private var code = ""
    @State private var isBusy = false
    @State private var errorText: String?
    @State private var shakes = 0
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isComplete: Bool { code.count == RoomCodeEntry.length }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(
                title: "Join your family",
                subtitle: "Enter the 6-character code\nfrom your parent’s phone"
            )
            .padding(.top, 56)

            RoomCodeEntry(code: $code, isError: errorText != nil, shakes: shakes, isFocused: $isFocused) {
                Task { await join() }
            }
            .padding(.top, 48)

            RoomCodeError(text: errorText)
                .padding(.top, 20)

            Button { Task { await join() } } label: {
                ZStack {
                    Text("Next").opacity(isBusy ? 0 : 1)
                    if isBusy { ProgressView() }
                }
                .frame(minWidth: 64)
            }
            .habitoCapsuleButton()
            .disabled(!isComplete)
            .padding(.top, 12)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.25), value: errorText)
        .background(HabitoBackground())
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.error, trigger: shakes)
        .onChange(of: code) {
            if errorText != nil { errorText = nil } // editing the code starts over
        }
        .task {
            // The keyboard comes up by itself, once the screen has finished sliding in.
            try? await Task.sleep(for: .milliseconds(350))
            isFocused = true
        }
    }

    // MARK: Logic

    private func join() async {
        guard isComplete, !isBusy else { return }
        isBusy = true
        errorText = nil
        defer { isBusy = false }
        do {
            let token = try await HabitoAPI.join(code: code)
            // The child token never expires and has no refresh token. It only stops working if
            // the parent links a new device.
            guard KeychainSwift().set(token, forKey: HabitoAPI.childTokenKey) else {
                throw APIError(status: 0, code: "keychain", message: "Couldn’t save the login on this phone.")
            }
            // Kept so that leaving the family can ask for the same code again.
            KeychainSwift().set(code, forKey: HabitoAPI.childRoomCodeKey)
            // The token is in the Keychain: let ContentView swap to the child's screens.
            ChildGame.startNewChild()
            ParentSession.refreshRoot()
        } catch {
            if error.isCancellation { return }
            show(message(for: error))
        }
    }

    private func message(for error: Error) -> String {
        if let api = error as? APIError, api.code == "invalid_code" {
            return "That code isn’t right. Check it with your parent and try again."
        }
        return error.habitoMessage
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

// MARK: - The six boxes

/// Six boxes drawn over one tiny real text field. The field does the typing (so deleting,
/// pasting and the keyboard's suggestions all work); tapping the boxes brings the keyboard up.
/// Animate `shakes` from n to n + 1 to shake the boxes.
struct RoomCodeEntry: View {
    static let length = 6

    @Binding var code: String
    var isError: Bool
    var shakes: Int
    var isFocused: FocusState<Bool>.Binding
    var onSubmit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The box waiting for the next character (the last one once the code is full).
    private var activeIndex: Int { min(code.count, Self.length - 1) }

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .focused(isFocused)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .onSubmit(onSubmit)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityHidden(true)

            HStack(spacing: 8) {
                ForEach(0..<Self.length, id: \.self) { index in
                    CodeBox(
                        character: character(at: index),
                        state: state(for: index),
                        reduceMotion: reduceMotion
                    )
                }
            }
            .modifier(ShakeEffect(shakes: CGFloat(shakes)))
        }
        .contentShape(Rectangle())
        .onTapGesture { isFocused.wrappedValue = true }
        .onChange(of: code) { _, new in
            let cleaned = Self.clean(new)
            if cleaned != new { code = cleaned }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("roomCodeBoxes")
        .accessibilityLabel("Room code")
        .accessibilityValue(code.isEmpty ? "Empty" : "\(code.map(String.init).joined(separator: " ")), \(code.count) of \(Self.length)")
        .accessibilityHint("Double-tap to type the six characters")
        .accessibilityAddTraits(.isButton)
    }

    private func character(at index: Int) -> String {
        guard index < code.count else { return "" }
        return String(code[code.index(code.startIndex, offsetBy: index)])
    }

    private func state(for index: Int) -> CodeBox.State {
        if isError { return .error }
        if isFocused.wrappedValue && index == activeIndex { return .active }
        return .normal
    }

    /// Letters and digits only, upper case, at most six: what a paste or a stray key may bring in.
    static func clean(_ text: String) -> String {
        String(text.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(length))
    }
}

/// The red line under the boxes. Takes no room until there is something to say.
struct RoomCodeError: View {
    let text: String?

    var body: some View {
        Group {
            if let text {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .padding(.top, 1)
                    Text(text)
                        .multilineTextAlignment(.center)
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.habitoRed)
                .padding(.horizontal, 36)
                .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - One box

private struct CodeBox: View {
    enum State { case normal, active, error }

    let character: String
    let state: State
    let reduceMotion: Bool

    @SwiftUI.State private var caretVisible = true

    private var borderColor: Color {
        switch state {
        case .normal: Color.primary.opacity(0.14)
        case .active: Color.habitoGreen
        case .error: Color.habitoRed
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.habitoCard)
                .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
                .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
            if state == .error {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.habitoRed.opacity(0.07))
            }
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(borderColor, lineWidth: state == .normal ? 1 : 2)

            Text(character)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(state == .error ? Color.habitoRed : Color.primary)

            if state == .active && character.isEmpty {
                Capsule()
                    .fill(Color.habitoGreen)
                    .frame(width: 2, height: 28)
                    .opacity(caretVisible ? 1 : 0)
            }
        }
        .frame(width: 48, height: 60)
        .animation(.easeOut(duration: 0.15), value: state)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                caretVisible = false
            }
        }
    }
}

// MARK: - Shake

/// A short side-to-side shake: animate `shakes` from n to n + 1.
private struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 9 * sin(shakes * .pi * 3), y: 0))
    }
}

#Preview {
    NavigationStack { ChildInsertCodeView() }
}

//
//  ChildInsertCodeView.swift
//  Habito
//
//  The child's first screen: the six-character room code from the parent's
//  phone, one box per character like a one-time-code screen. A wrong code
//  turns the boxes red, shakes them and explains underneath.
//

import SwiftUI
import KeychainSwift

struct ChildInsertCodeView: View {
    @State private var code = ""
    @State private var isBusy = false
    @State private var errorText: String?
    @State private var shakes = 0
    @State private var isJoined = false
    @State private var childToken = ""
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let length = 6

    private var isComplete: Bool { code.count == Self.length }

    /// The box waiting for the next character (the last one once the code is full).
    private var activeIndex: Int { min(code.count, Self.length - 1) }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(
                title: "Join your family",
                subtitle: "Enter the 6-character code\nfrom your parent’s phone"
            )
            .padding(.top, 56)

            boxes
                .padding(.top, 48)

            errorLine
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
        .navigationDestination(isPresented: $isJoined) {
            ChildTaskView(token: childToken)
        }
        .sensoryFeedback(.error, trigger: shakes)
        .onChange(of: code) { _, new in
            let cleaned = Self.clean(new)
            if cleaned != new {
                code = cleaned
            } else if errorText != nil {
                errorText = nil // editing the code starts over
            }
        }
        .task {
            // The keyboard comes up by itself, once the screen has finished sliding in.
            try? await Task.sleep(for: .milliseconds(350))
            isFocused = true
        }
    }

    // MARK: Pieces

    /// Six boxes drawn over one tiny real text field. The field does the typing (so deleting,
    /// pasting and the keyboard's suggestions all work); tapping the boxes brings the keyboard up.
    private var boxes: some View {
        ZStack {
            TextField("", text: $code)
                .focused($isFocused)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .onSubmit { Task { await join() } }
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
        .onTapGesture { isFocused = true }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("roomCodeBoxes")
        .accessibilityLabel("Room code")
        .accessibilityValue(code.isEmpty ? "Empty" : "\(code.map(String.init).joined(separator: " ")), \(code.count) of \(Self.length)")
        .accessibilityHint("Double-tap to type the six characters")
        .accessibilityAddTraits(.isButton)
    }

    /// Takes no room until there is something to say; the button glides down when it appears.
    private var errorLine: some View {
        Group {
            if let errorText {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .padding(.top, 1)
                    Text(errorText)
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

    private func character(at index: Int) -> String {
        guard index < code.count else { return "" }
        return String(code[code.index(code.startIndex, offsetBy: index)])
    }

    private func state(for index: Int) -> CodeBox.State {
        if errorText != nil { return .error }
        if isFocused && index == activeIndex { return .active }
        return .normal
    }

    // MARK: Logic

    /// Letters and digits only, upper case, at most six: what a paste or a stray key may bring in.
    private static func clean(_ text: String) -> String {
        String(text.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(length))
    }

    private func join() async {
        guard isComplete, !isBusy else { return }
        isBusy = true
        errorText = nil
        defer { isBusy = false }
        do {
            let token = try await HabitoAPI.join(code: code)
            // The child token never expires and has no refresh token. It only stops working if
            // the parent links a new device.
            guard KeychainSwift().set(token, forKey: "child_token") else {
                throw APIError(status: 0, code: "keychain", message: "Couldn’t save the login on this phone.")
            }
            childToken = token
            isJoined = true
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

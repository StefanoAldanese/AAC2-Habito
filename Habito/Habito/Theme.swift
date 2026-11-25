//
//  Theme.swift
//  Habito
//
//  The parent app's look: Apple system green as the accent, white cards with
//  22 pt corners, a soft green fade at the top of every screen. Colours adapt
//  to dark mode.
//

import SwiftUI
import UIKit

// MARK: - Colours

extension Color {
    /// A colour that changes between light and dark mode.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    /// Fills: progress bars, switches, the Confirm button.
    static let habitoGreen = Color(light: 0x34C759, dark: 0x30D158)
    /// Text and icons that need to read well on a white card.
    static let habitoGreenDeep = Color(light: 0x248A3D, dark: 0x30D158)
    /// Delete and missed tasks only.
    static let habitoRed = Color(light: 0xD70015, dark: 0xFF453A)
    /// White in light mode.
    static let habitoCard = Color(uiColor: .secondarySystemGroupedBackground)
    /// The green at the very top of a screen.
    static let habitoWash = Color(light: 0xEAF6E6, dark: 0x13261A)
    /// Empty circles for tasks that are not done.
    static let habitoInactive = Color(light: 0xC0C0C4, dark: 0x636366)
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Screen background

/// White, with a soft green at the top that has faded out by the middle of the screen.
struct HabitoBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color(uiColor: .systemBackground)
            LinearGradient(
                colors: [.habitoWash, Color(uiColor: .systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 720)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Cards

private struct HabitoCard: ViewModifier {
    let corner: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color.habitoCard)
                    .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
                    .shadow(color: .black.opacity(0.07), radius: 11, y: 4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            }
    }
}

extension View {
    /// A white card with rounded corners and a soft shadow.
    func habitoCard(corner: CGFloat = 22) -> some View {
        modifier(HabitoCard(corner: corner))
    }
}

// MARK: - Glass

extension View {
    /// Liquid Glass on iOS 26; a translucent material on earlier versions.
    @ViewBuilder
    func habitoGlass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.6), lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
    }
}

// MARK: - Buttons

extension View {
    /// A native capsule button with a text label: tinted Liquid Glass on iOS 26,
    /// a filled capsule on earlier versions. Sized to its label, not full width.
    @ViewBuilder
    func habitoCapsuleButton() -> some View {
        if #available(iOS 26, *) {
            buttonStyle(.glassProminent).buttonBorderShape(.capsule).controlSize(.large).tint(.habitoGreen)
        } else {
            buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large).tint(.habitoGreen)
        }
    }
}

extension View {
    /// The green button for + and the save check: tinted Liquid Glass on iOS 26,
    /// a round prominent button on earlier versions.
    @ViewBuilder
    func habitoProminentButton() -> some View {
        if #available(iOS 26, *) {
            buttonStyle(.glassProminent).tint(.habitoGreen)
        } else {
            buttonStyle(.borderedProminent).buttonBorderShape(.circle).tint(.habitoGreen)
        }
    }
}

/// The full-width green capsule at the bottom of onboarding screens.
struct HabitoPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background {
                Capsule()
                    .fill(Color.habitoGreen)
                    .shadow(color: Color.habitoGreenDeep.opacity(0.2), radius: 8, y: 6)
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Onboarding pieces

/// Four steps: role, sign-up, code, congratulations.
struct StepBar: View {
    let step: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...4, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? Color.habitoGreen : Color.secondary.opacity(0.22))
                    .frame(width: 44, height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step) of 4")
    }
}

/// Centered title and subtitle at the top of an onboarding screen.
struct OnboardingHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
}

/// The Confirm / Sign up / Log in button, pinned above the keyboard or home indicator.
struct BottomButton: View {
    let title: String
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(isBusy ? 0 : 1)
                if isBusy { ProgressView().tint(.white) }
            }
        }
        .buttonStyle(HabitoPrimaryButtonStyle())
        // On iPad it stays as wide as the form above it instead of spanning the screen.
        .frame(maxWidth: 420)
        .padding(.horizontal, 41)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Progress and status

struct HabitoProgressBar: View {
    let fraction: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.habitoGreenDeep.opacity(0.13))
                Capsule()
                    .fill(Color.habitoGreen)
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// done = green check, missed = red cross, anything else (open, upcoming) = empty circle.
struct StatusIcon: View {
    let status: String
    var size: CGFloat = 22

    var body: some View {
        Group {
            switch status {
            case "done":
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.habitoGreenDeep)
            case "missed":
                Image(systemName: "xmark.circle.fill").foregroundStyle(Color.habitoRed)
            default:
                Image(systemName: "circle").foregroundStyle(Color.habitoInactive)
            }
        }
        .font(.system(size: size))
        .accessibilityHidden(true)
    }
}

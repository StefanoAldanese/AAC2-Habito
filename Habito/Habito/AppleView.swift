//
//  AppleView.swift
//  Habito
//
//  One apple on the tree, animation only: it swings like a pendulum when the
//  phone is shaken, grows in slowly when its task is new, and regrows after it
//  fell off.
//

import SwiftUI

struct AppleView: View {
    let size: CGSize
    /// Changes on every shake.
    var swing: Int
    /// Bigger or smaller swings, so the apples do not move in step.
    var swingStrength: Double
    /// Changes when the apple should grow back on its spot.
    var regrow: Int
    /// Hidden while the apple is in the child's hand or being eaten.
    var hidden: Bool
    /// Called once a slowly growing apple is fully grown.
    var onGrown: () -> Void = {}

    @State private var scale: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let arrivalDuration: Double = 3
    static let regrowDuration: Double = 1.5

    init(size: CGSize, swing: Int, swingStrength: Double, regrow: Int, hidden: Bool, growsSlowly: Bool, onGrown: @escaping () -> Void = {}) {
        self.size = size
        self.swing = swing
        self.swingStrength = swingStrength
        self.regrow = regrow
        self.hidden = hidden
        self.onGrown = onGrown
        _scale = State(initialValue: growsSlowly ? 0 : 1)
        self.growsSlowly = growsSlowly
    }

    private let growsSlowly: Bool

    var body: some View {
        Image("Apple")
            .resizable()
            .frame(width: size.width, height: size.height)
            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
            .scaleEffect(scale, anchor: .top)
            .keyframeAnimator(initialValue: 0.0, trigger: reduceMotion ? 0 : swing) { content, angle in
                content.rotationEffect(.degrees(angle * swingStrength), anchor: .top)
            } keyframes: { _ in
                // A damped pendulum, with a little jitter on the way.
                CubicKeyframe(24, duration: 0.16)
                CubicKeyframe(-20, duration: 0.2)
                CubicKeyframe(15, duration: 0.2)
                CubicKeyframe(-11, duration: 0.22)
                CubicKeyframe(7, duration: 0.22)
                CubicKeyframe(-4, duration: 0.24)
                CubicKeyframe(1.5, duration: 0.24)
                CubicKeyframe(0, duration: 0.26)
            }
            .opacity(hidden ? 0 : 1)
            .onAppear {
                guard growsSlowly else { return }
                withAnimation(.easeOut(duration: reduceMotion ? 0.3 : Self.arrivalDuration)) {
                    scale = 1
                } completion: {
                    onGrown()
                }
            }
            .onChange(of: hidden) { _, isHidden in
                // Off the tree the spot is empty; it only fills again by regrowing.
                if isHidden {
                    var instant = Transaction()
                    instant.disablesAnimations = true
                    withTransaction(instant) { scale = 0 }
                }
            }
            .onChange(of: regrow) {
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) { scale = 0 }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(30))
                    withAnimation(.spring(duration: reduceMotion ? 0.3 : Self.regrowDuration, bounce: 0.35)) {
                        scale = 1
                    }
                }
            }
    }
}

/// An apple that came off the tree and is falling out of the screen.
struct FallingApple: Identifiable {
    let id = UUID()
    let taskID: String
    let start: CGPoint
    let velocity: CGVector
    let spin: Double
    let startDate: Date
    /// Size against an apple on the tree: one pulled off is drawn bigger, as it is in the hand.
    var scale: Double = 1.3

    static let gravity: Double = 2600

    func position(at date: Date) -> CGPoint {
        let t = max(0, date.timeIntervalSince(startDate))
        return CGPoint(x: start.x + velocity.dx * t, y: start.y + velocity.dy * t + 0.5 * Self.gravity * t * t)
    }

    func angle(at date: Date) -> Double {
        spin * max(0, date.timeIntervalSince(startDate))
    }

    /// How long until it has left a screen of this size (at most 2.5 seconds).
    func timeToLeave(_ screen: CGSize) -> Double {
        var t = 0.0
        while t < 2.5 {
            t += 1 / 60
            let p = CGPoint(x: start.x + velocity.dx * t, y: start.y + velocity.dy * t + 0.5 * Self.gravity * t * t)
            if p.y > screen.height + 60 || p.x < -60 || p.x > screen.width + 60 { return t }
        }
        return t
    }
}

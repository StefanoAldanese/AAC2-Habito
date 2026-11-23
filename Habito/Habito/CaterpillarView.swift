//
//  CaterpillarView.swift
//  Habito
//
//  The caterpillar and its moods, animation only: mouth open or closed, dizzy
//  spiral eyes after a shake, a wobble while shaken and a happy squash after eating.
//

import SwiftUI

struct CaterpillarView: View {
    var mouthOpen: Bool
    var dizzy: Bool
    /// Changes on every shake: the body wobbles.
    var wobble: Int
    /// Changes on every apple eaten: the body squashes and bounces.
    var chew: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The eyes in the caterpillar picture (1933 x 803 pixels in the drawing), as fractions of it.
    /// (Written as decimals: whole-number literals here would pick CGRect's Int initialiser
    /// and divide to zero.)
    private static let eyes: [CGRect] = [
        CGRect(x: 138.0 / 1933, y: 324.0 / 803, width: 172.0 / 1933, height: 302.0 / 803),
        CGRect(x: 436.0 / 1933, y: 324.0 / 803, width: 172.0 / 1933, height: 304.0 / 803),
    ]

    var body: some View {
        Image(mouthOpen ? "CaterpillarOpen" : "Caterpillar")
            .resizable()
            .overlay {
                if dizzy {
                    GeometryReader { proxy in
                        ForEach(0..<Self.eyes.count, id: \.self) { index in
                            let eye = Self.eyes[index]
                            DizzyEye(clockwise: index == 0, still: reduceMotion)
                                .frame(width: eye.width * proxy.size.width, height: eye.height * proxy.size.height)
                                .position(x: eye.midX * proxy.size.width, y: eye.midY * proxy.size.height)
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
                }
            }
            .animation(.easeOut(duration: 0.2), value: dizzy)
            .keyframeAnimator(initialValue: 0.0, trigger: reduceMotion ? 0 : wobble) { content, angle in
                content.rotationEffect(.degrees(angle), anchor: UnitPoint(x: 0.4, y: 0.95))
            } keyframes: { _ in
                CubicKeyframe(-5, duration: 0.12)
                CubicKeyframe(5, duration: 0.14)
                CubicKeyframe(-4, duration: 0.14)
                CubicKeyframe(3, duration: 0.14)
                CubicKeyframe(-1.5, duration: 0.14)
                CubicKeyframe(0, duration: 0.16)
            }
            .keyframeAnimator(initialValue: CGSize(width: 1, height: 1), trigger: chew) { content, scale in
                content.scaleEffect(scale, anchor: UnitPoint(x: 0.2, y: 0.95))
            } keyframes: { _ in
                SpringKeyframe(CGSize(width: 1.04, height: 0.93), duration: 0.12)
                SpringKeyframe(CGSize(width: 0.98, height: 1.05), duration: 0.14)
                SpringKeyframe(CGSize(width: 1.02, height: 0.97), duration: 0.12)
                SpringKeyframe(CGSize(width: 1, height: 1), duration: 0.2)
            }
            .accessibilityElement()
            .accessibilityLabel("Caterpillar")
            .accessibilityValue(dizzy ? "dizzy" : (mouthOpen ? "mouth open" : "smiling"))
            .accessibilityIdentifier("caterpillar")
    }
}

/// One dizzy eye: a white eye with a dark spiral turning in it.
private struct DizzyEye: View {
    let clockwise: Bool
    let still: Bool

    var body: some View {
        GeometryReader { proxy in
            let line = max(1.2, min(proxy.size.width, proxy.size.height) * 0.07)
            TimelineView(.animation(paused: still)) { context in
                let turns = context.date.timeIntervalSinceReferenceDate * 1.6
                let rotation = (clockwise ? 1.0 : -1.0) * turns.truncatingRemainder(dividingBy: 1) * 2 * .pi
                ZStack {
                    Ellipse().fill(.white)
                    Spiral(rotation: rotation)
                        .stroke(Color(red: 0.07, green: 0.07, blue: 0.09), style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .padding(line * 0.9)
                    Ellipse().stroke(Color(red: 0.07, green: 0.07, blue: 0.09), lineWidth: line * 0.9)
                }
                .clipShape(Ellipse())
            }
        }
    }
}

/// Three turns, from the middle out.
private struct Spiral: Shape {
    var rotation: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let turns = 3.0
        let steps = 140
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let angle = t * turns * 2 * .pi + rotation
            let point = CGPoint(x: center.x + cos(angle) * t * rect.width / 2,
                                y: center.y + sin(angle) * t * rect.height / 2)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

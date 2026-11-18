//
//  ButterflyRevealView.swift
//  Habito
//
//  Seven perfect days: a white glow grows out of the caterpillar until the whole
//  screen is white, then the new butterfly appears. With Reduce Motion on, the
//  screen cross-fades instead of flashing.
//

import SwiftUI

struct ButterflyRevealView: View {
    let kind: ButterflyKind
    let onSee: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0: nothing yet. 1: all white. 2: the butterfly.
    @State private var phase = 0
    @State private var spin = false

    private let gold = Color(red: 0.969, green: 0.851, blue: 0.298)
    private let sky = Color(red: 0.486, green: 0.784, blue: 1.0)

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // The glow grows out of the caterpillar, in the bottom right corner.
                Circle()
                    .fill(RadialGradient(colors: [.white, .white.opacity(0.92), .white.opacity(0)], center: .center, startRadius: 0, endRadius: 400))
                    .frame(width: 800, height: 800)
                    .scaleEffect(phase >= 1 ? 4 : 0.05)
                    .position(x: proxy.size.width * 0.78, y: proxy.size.height * 0.8)
                Color.white.opacity(phase >= 1 ? 1 : 0)

                if phase >= 2 {
                    content
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .sensoryFeedback(.impact(weight: .heavy), trigger: phase) { _, new in new == 2 }
        .onAppear(perform: start)
    }

    private var content: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            // The rays are wider than the screen; as an overlay they do not widen the layout.
            Color.clear
                .frame(height: 320)
                .overlay {
                    ZStack {
                        Rays()
                            .fill(gold.opacity(0.32))
                            .frame(width: 640, height: 640)
                            .mask(RadialGradient(colors: [.black, .black.opacity(0.5), .clear], center: .center, startRadius: 40, endRadius: 320))
                            .rotationEffect(.degrees(spin ? 360 : 0))
                            .animation(reduceMotion ? nil : .linear(duration: 40).repeatForever(autoreverses: false), value: spin)
                        sparkle(gold, size: 22, x: -134, y: -96)
                        sparkle(sky, size: 14, x: 128, y: -112)
                        sparkle(gold, size: 26, x: 146, y: 90)
                        sparkle(sky, size: 12, x: -150, y: 108)
                        sparkle(gold, size: 11, x: 92, y: 168)
                        Image(kind.image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 290)
                            .shadow(color: Color(red: 0.08, green: 0.12, blue: 0.04).opacity(0.18), radius: 10, y: 14)
                    }
                }
                .accessibilityHidden(true)

            Text("A new butterfly!")
                .font(.largeTitle.weight(.bold))
                .padding(.top, 24)
            Text("Your caterpillar grew into a")
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            Text(kind.name)
                .font(.title2.weight(.bold))
            Spacer(minLength: 20)
            Button("See my butterflies", action: onSee)
                .buttonStyle(HabitoPrimaryButtonStyle())
                .padding(.horizontal, 41)
                .padding(.bottom, 40)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.black)
        .frame(maxWidth: 500)
    }

    private func sparkle(_ color: Color, size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Image(systemName: "sparkle")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(color)
            .offset(x: x, y: y)
    }

    private func start() {
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.5)) { phase = 2 }
            return
        }
        // A soft flash: the white fades in over about half a second, once.
        withAnimation(.easeIn(duration: 0.6)) { phase = 1 }
        Task {
            try? await Task.sleep(for: .milliseconds(750))
            withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) { phase = 2 }
            spin = true
        }
    }
}

/// Eighteen soft rays around the new butterfly.
private struct Rays: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = max(rect.width, rect.height) / 2
        let count = 18
        for index in 0..<count {
            let start = Double(index) / Double(count) * 2 * .pi
            let end = start + 2 * .pi / Double(count) * 0.45
            path.move(to: center)
            path.addArc(center: center, radius: radius, startAngle: .radians(start), endAngle: .radians(end), clockwise: false)
            path.closeSubpath()
        }
        return path
    }
}

//
//  ChildGardenView.swift
//  Habito
//
//  The Garden tab (beta): two flower beds on the hill. The child's favourite
//  butterflies (the ones with a heart in the collection) live here: they flutter
//  around, land on a flower, shrink to the flower's size, rest a while with their
//  wings slowly opening and closing, and fly off again.
//

import SwiftUI

struct ChildGardenView: View {
    /// Switches to the Butterflies tab (the guide's button).
    var openButterflies: () -> Void = {}

    @Environment(ChildGame.self) private var game
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flock = GardenFlock()

    /// At most this many butterflies in the garden at once: the newest favourites.
    private static let most = 8

    private var visitors: [Int] {
        Array(game.favourites.filter { $0 < game.butterflies }.sorted(by: >).prefix(Self.most))
    }

    var body: some View {
        GeometryReader { proxy in
            // The same 402 x 870 design frame as the tree, fitted and anchored to the bottom.
            let layout = TreeLayout(size: proxy.size)
            ZStack(alignment: .topLeading) {
                // Sky and grass carry on past the picture's edges on other screen shapes.
                VStack(spacing: 0) {
                    Color.gardenSky.frame(height: max(0, layout.point(0, 293).y))
                    Color.gardenGrass
                }
                Image("GardenScene")
                    .resizable()
                    .frame(width: layout.scenery.width, height: layout.scenery.height)
                    .position(x: layout.scenery.midX, y: layout.scenery.midY)
                    .accessibilityHidden(true)
                butterflies(layout)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            // With no butterflies yet the garden goes soft behind the message.
            .blur(radius: visitors.isEmpty ? 9 : 0, opaque: true)
            .animation(.easeInOut(duration: 0.35), value: visitors.isEmpty)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("garden")
        // The guide stays readable and its button tappable for VoiceOver too.
        .overlay {
            if visitors.isEmpty { hint }
        }
    }

    private var accessibilityText: String {
        switch visitors.count {
        case 0: "Garden with flower beds. No butterflies yet."
        case 1: "Garden with flower beds and 1 butterfly."
        default: "Garden with flower beds and \(visitors.count) butterflies."
        }
    }

    private func butterflies(_ layout: TreeLayout) -> some View {
        TimelineView(.animation(paused: visitors.isEmpty || reduceMotion)) { context in
            let now = context.date
            ZStack(alignment: .topLeading) {
                ForEach(visitors, id: \.self) { number in
                    let pose = reduceMotion ? flock.still(number, among: visitors) : flock.pose(of: number, at: now)
                    let width = pose.width / GardenFlock.drawingShare * layout.scale
                    Image(ButterflyKind.of(number).image)
                        .resizable()
                        .frame(width: width, height: width * GardenFlock.pictureAspect)
                        // Wings beating: the picture narrows and widens.
                        .scaleEffect(x: pose.wings, y: 1)
                        .rotationEffect(.degrees(pose.tilt))
                        .shadow(color: .black.opacity(pose.resting ? 0.12 : 0.18), radius: pose.resting ? 1 : 3, y: pose.resting ? 1 : 6)
                        .position(layout.point(pose.point.x, pose.point.y))
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// With no favourites yet: the garden goes soft and pale, and a two-page guide sits on it.
    private var hint: some View {
        ZStack {
            // A light veil over the blur so the words read clearly. Not a box: it covers everything.
            LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.25), .white.opacity(0.45)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            GardenGuide(openButterflies: openButterflies)
        }
        .transition(.opacity)
    }
}

// MARK: - The picture guide

/// Two pages, swiped like a picture book: first a butterfly's card with an
/// arrow to its heart, then the same butterfly flying in the garden. Big pictures and big words,
/// so a child can read them.
private struct GardenGuide: View {
    let openButterflies: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var current = 0
    private let example = ButterflyKind.all[1]

    private static let ink = Color(red: 0.07, green: 0.19, blue: 0.11)

    var body: some View {
        VStack(spacing: 18) {
            TabView(selection: $current) {
                page(step: 1, title: "Pick a favourite",
                     text: "Open Butterflies and tap the heart on the one you love.") { side in
                    heartPicture(side)
                }
                .tag(0)
                page(step: 2, title: "Watch it fly",
                     text: "Your favourites come to live here, flying from flower to flower.") { side in
                    gardenPicture(side)
                }
                .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            dots

            Button(action: openButterflies) {
                Label("Go to Butterflies", systemImage: "heart.fill")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .padding(.horizontal, 10)
            }
            .habitoCapsuleButton()
        }
        // Clear of the status bar above and the tab bar below.
        .padding(.top, 64)
        .padding(.bottom, 112)
    }

    /// Our own page dots in the garden's green, with nothing behind them.
    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(0..<2, id: \.self) { index in
                Capsule()
                    .fill(Color.gardenLeaf.opacity(index == current ? 1 : 0.28))
                    .frame(width: index == current ? 24 : 8, height: 8)
            }
        }
        .animation(.snappy, value: current)
        .accessibilityHidden(true)
    }

    /// One page, straight on the soft garden: a small step label, a big title, one line of
    /// help, and the picture, as large as the page allows.
    private func page<Picture: View>(step: Int, title: String, text: String,
                                     @ViewBuilder picture: @escaping (CGFloat) -> Picture) -> some View {
        GeometryReader { proxy in
            // The words take about 125 points; the picture gets the rest, square and as big as fits.
            let side = max(140, min(proxy.size.width, proxy.size.height - 133, 400))
            VStack(spacing: 0) {
                Text("STEP \(step) OF 2")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(Color.habitoGreenDeep)
                Text(title)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(Self.ink)
                    .padding(.top, 6)
                Text(text)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(Self.ink.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300)
                    .padding(.top, 6)
                Spacer(minLength: 8)
                picture(side)
                    .frame(width: side, height: side)
                Spacer(minLength: 0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .padding(.horizontal, 8)
    }

    /// Step 1: the butterfly, big, with its heart button beside it and a red arrow onto the heart.
    /// No frame around it: it floats on the soft garden.
    private func heartPicture(_ side: CGFloat) -> some View {
        let heart = CGPoint(x: side * 0.83, y: side * 0.3)
        let button = side * 0.19
        let arrow = CGSize(width: side * 0.22, height: side * 0.17)
        return ZStack {
            Image(example.image)
                .resizable()
                .scaledToFit()
                .frame(width: side * 0.86)
                .shadow(color: Self.ink.opacity(0.22), radius: 14, y: 10)
                .position(x: side * 0.44, y: side * 0.62)
            // The heart button, as on a butterfly's card, gently beating.
            Circle()
                .fill(.white)
                .shadow(color: Self.ink.opacity(0.2), radius: 8, y: 4)
                .overlay {
                    Image(systemName: "heart.fill")
                        .font(.system(size: button * 0.46, weight: .semibold))
                        .foregroundStyle(Color.habitoRed)
                        .phaseAnimator(reduceMotion ? [1.0] : [1.0, 1.2]) { content, scale in
                            content.scaleEffect(scale)
                        } animation: { _ in .easeInOut(duration: 0.55) }
                }
                .frame(width: button, height: button)
                .position(heart)
            // The arrow arcs over and comes down onto the top of the button.
            CuteArrow(from: UnitPoint(x: 0.05, y: 0.12), to: UnitPoint(x: 0.85, y: 1), bend: -0.45)
                .stroke(Color.habitoRed, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .frame(width: arrow.width, height: arrow.height)
                .phaseAnimator(reduceMotion ? [0.0] : [0.0, 1.0]) { content, t in
                    content.offset(y: 4 * t)
                } animation: { _ in .easeInOut(duration: 0.55) }
                .position(x: heart.x - arrow.width * 0.35, y: heart.y - button / 2 - 6 - arrow.height / 2)
        }
        .frame(width: side, height: side)
    }

    /// Step 2: the right-hand flower bed of the garden, fading softly away at its edges (no frame),
    /// with the butterfly fluttering over it.
    private func gardenPicture(_ side: CGFloat) -> some View {
        // Show about 220 design points of the garden around the flower bed's middle.
        let scale = side / 220
        let focus = CGPoint(x: 300, y: 450)
        return ZStack {
            Image("GardenScene")
                .resizable()
                .frame(width: 402 * scale, height: 870 * scale)
                .offset(x: (201 - focus.x) * scale, y: (435 - focus.y) * scale)
                .frame(width: side, height: side)
                .mask(
                    RadialGradient(stops: [.init(color: .black, location: 0.55), .init(color: .clear, location: 1)],
                                   center: .center, startRadius: 0, endRadius: side * 0.5)
                )
            TimelineView(.animation(paused: reduceMotion)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                Image(example.image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: side * 0.34)
                    .scaleEffect(x: reduceMotion ? 1 : 0.35 + 0.65 * abs(cos(2 * .pi * 2.2 * t)), y: 1)
                    .shadow(color: .black.opacity(0.2), radius: 5, y: 9)
                    .offset(x: reduceMotion ? 0 : side * 0.08 * sin(t * 0.9),
                            y: reduceMotion ? -side * 0.12 : -side * 0.12 + side * 0.04 * sin(t * 1.7))
            }
        }
        .frame(width: side, height: side)
    }
}

/// A friendly curved arrow with a little open arrowhead, drawn in its own box
/// from one point to another (as fractions of the box).
private struct CuteArrow: Shape {
    var from: UnitPoint
    var to: UnitPoint
    /// How far the curve bows to one side, as a share of its length.
    var bend: CGFloat

    func path(in rect: CGRect) -> Path {
        let a = CGPoint(x: rect.minX + from.x * rect.width, y: rect.minY + from.y * rect.height)
        let b = CGPoint(x: rect.minX + to.x * rect.width, y: rect.minY + to.y * rect.height)
        let length = hypot(b.x - a.x, b.y - a.y)
        let normal = length > 0 ? CGPoint(x: -(b.y - a.y) / length, y: (b.x - a.x) / length) : .zero
        let control = CGPoint(x: (a.x + b.x) / 2 + normal.x * bend * length, y: (a.y + b.y) / 2 + normal.y * bend * length)
        var path = Path()
        path.move(to: a)
        path.addQuadCurve(to: b, control: control)
        // The head follows the curve's direction at its end.
        let angle = atan2(b.y - control.y, b.x - control.x)
        let head = max(6, length * 0.28)
        for side in [-0.5, 0.5] {
            let wing = angle + .pi + side * 1.1
            path.move(to: b)
            path.addLine(to: CGPoint(x: b.x + cos(wing) * head, y: b.y + sin(wing) * head))
        }
        return path
    }
}

// MARK: - How the butterflies move

/// Plans each butterfly's day ahead in short legs, in design points: a few loops through
/// the air, a glide down onto a free flower (shrinking to the flower's size), a rest there,
/// then off again. Two butterflies never sit on the same flower at once.
///
/// A plain class kept in @State: the view reads poses from it every frame and it extends
/// its plans as time goes on, without making SwiftUI redraw on its own.
final class GardenFlock {
    struct Pose {
        var point: CGPoint
        /// Width of the butterfly drawing itself, in design points.
        var width: CGFloat
        /// 1 = wings open, smaller = wings tipping up.
        var wings: CGFloat
        var tilt: Double
        var resting: Bool
    }

    /// A flower head a butterfly can land on: its middle and how wide it is.
    struct Flower {
        let x: CGFloat, y: CGFloat, width: CGFloat
    }

    /// The flower heads in the garden picture (sunflowers, roses, the little pink flower, daisies).
    static let flowers: [Flower] = [
        Flower(x: 386, y: 363, width: 32), Flower(x: 328, y: 387, width: 34), Flower(x: 370, y: 408, width: 49),
        Flower(x: 81, y: 495, width: 43), Flower(x: 130, y: 514, width: 51),
        Flower(x: 381, y: 498, width: 39), Flower(x: 330, y: 506, width: 30), Flower(x: 289, y: 514, width: 38),
        Flower(x: 26, y: 523, width: 43), Flower(x: 352, y: 533, width: 35), Flower(x: 18, y: 608, width: 35),
        Flower(x: 39, y: 420, width: 21),
        Flower(x: 294, y: 395, width: 20), Flower(x: 271, y: 409, width: 20), Flower(x: 247, y: 429, width: 20),
        Flower(x: 68, y: 581, width: 24), Flower(x: 88, y: 616, width: 24), Flower(x: 51, y: 622, width: 24),
    ]

    /// The butterfly pictures are 900 x 773 with the drawing 816 points wide in the middle.
    static let drawingShare: CGFloat = 816.0 / 900
    static let pictureAspect: CGFloat = 773.0 / 900
    /// The drawing's height for each point of its width.
    static let drawingAspect: CGFloat = 598.0 / 816

    static let flyingWidth: CGFloat = 46
    /// Where they fly: over the hill and the beds, under the sky's top.
    static let air = CGRect(x: 30, y: 150, width: 342, height: 480)

    private struct Leg {
        let start: Date, end: Date
        let from: CGPoint, control: CGPoint, to: CGPoint
        let fromWidth: CGFloat, toWidth: CGFloat
        let resting: Bool
        let tilt: Double
        let phase: Double
    }

    private var legs: [Int: [Leg]] = [:]
    /// When each flower is taken.
    private var bookings: [Int: [(start: Date, end: Date)]] = [:]

    func pose(of number: Int, at date: Date) -> Pose {
        if legs[number] == nil { begin(number, at: date) }
        while let last = legs[number]?.last, last.end < date.addingTimeInterval(4) { plan(number, after: last) }
        legs[number]?.removeAll { $0.end < date.addingTimeInterval(-2) }
        guard let leg = legs[number]?.first(where: { $0.end >= date }) else {
            return Pose(point: CGPoint(x: Self.air.midX, y: Self.air.midY), width: Self.flyingWidth, wings: 1, tilt: 0, resting: false)
        }
        let span = leg.end.timeIntervalSince(leg.start)
        let u = span > 0 ? min(1, max(0, date.timeIntervalSince(leg.start) / span)) : 1
        let t = date.timeIntervalSinceReferenceDate

        if leg.resting {
            // Sitting on the flower, wings slowly opening and closing.
            let wings = 0.62 + 0.38 * abs(cos(2 * .pi * 0.32 * t + leg.phase))
            return Pose(point: leg.to, width: leg.toWidth, wings: CGFloat(wings), tilt: leg.tilt, resting: true)
        }
        // Smooth start and stop along a curve, with a little bobbing up and down in the middle.
        let e = CGFloat(u * u * (3 - 2 * u))
        var point = Self.bezier(leg.from, leg.control, leg.to, e)
        point.y += CGFloat(6 * sin(2 * .pi * 1.3 * t + leg.phase) * sin(.pi * u))
        // Shrinking to the flower's size happens near the end of a landing (and growing at take-off).
        let grow = leg.toWidth < leg.fromWidth ? pow(e, 2) : 1 - pow(1 - e, 2)
        let width = leg.fromWidth + (leg.toWidth - leg.fromWidth) * grow
        // Leaning a little the way it is going.
        let ahead = Self.bezier(leg.from, leg.control, leg.to, min(1, e + 0.02))
        let lean = Double(max(-18, min(18, (ahead.x - point.x) * 4)))
        let wings = 0.3 + 0.7 * abs(cos(2 * .pi * 5.5 * t + leg.phase))
        return Pose(point: point, width: width, wings: CGFloat(wings), tilt: lean, resting: false)
    }

    /// Reduce Motion: every butterfly simply sits on its own flower.
    func still(_ number: Int, among visitors: [Int]) -> Pose {
        let index = (visitors.firstIndex(of: number) ?? 0) * 5 % Self.flowers.count
        let flower = Self.flowers[index]
        return Pose(point: Self.seat(on: flower), width: flower.width, wings: 1, tilt: 0, resting: true)
    }

    // MARK: Planning

    private func begin(_ number: Int, at date: Date) {
        let start = Self.randomAir()
        let hold = Leg(start: date, end: date.addingTimeInterval(.random(in: 0...0.6)), from: start, control: start, to: start,
                       fromWidth: Self.flyingWidth, toWidth: Self.flyingWidth, resting: false, tilt: 0, phase: .random(in: 0...6))
        legs[number] = [hold]
    }

    private func plan(_ number: Int, after last: Leg) {
        var next: [Leg] = []
        if last.resting || Bool.random() || last.toWidth < Self.flyingWidth {
            // Take off or keep wandering: one loop through the air.
            next.append(fly(from: last.to, width: last.toWidth, to: Self.randomAir(), toWidth: Self.flyingWidth, at: last.end))
        } else if let landing = land(from: last.to, at: last.end) {
            next.append(contentsOf: landing)
        } else {
            next.append(fly(from: last.to, width: last.toWidth, to: Self.randomAir(), toWidth: Self.flyingWidth, at: last.end))
        }
        legs[number, default: []].append(contentsOf: next)
    }

    private func fly(from: CGPoint, width: CGFloat, to: CGPoint, toWidth: CGFloat, at start: Date) -> Leg {
        let distance = hypot(to.x - from.x, to.y - from.y)
        let duration = max(1.4, Double(distance) / 62)
        // Bend the path to one side so it is a curve, not a straight line.
        let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        let bend = distance * CGFloat.random(in: 0.2...0.45) * (Bool.random() ? 1 : -1)
        let normal = distance > 0 ? CGPoint(x: -(to.y - from.y) / distance, y: (to.x - from.x) / distance) : .zero
        let control = CGPoint(x: mid.x + normal.x * bend, y: mid.y + normal.y * bend)
        return Leg(start: start, end: start.addingTimeInterval(duration), from: from, control: control, to: to,
                   fromWidth: width, toWidth: toWidth, resting: false, tilt: 0, phase: .random(in: 0...6))
    }

    /// Glide onto a flower that is free for the whole visit, then rest there.
    private func land(from point: CGPoint, at start: Date) -> [Leg]? {
        let rest = Double.random(in: 3.5...7)
        for index in Self.flowers.indices.shuffled() {
            let flower = Self.flowers[index]
            let seat = Self.seat(on: flower)
            let glide = fly(from: point, width: Self.flyingWidth, to: seat, toWidth: flower.width, at: start)
            let leave = glide.end.addingTimeInterval(rest)
            let taken = bookings[index, default: []].contains { $0.start < leave.addingTimeInterval(1) && glide.end.addingTimeInterval(-1) < $0.end }
            if taken { continue }
            bookings[index, default: []].removeAll { $0.end < start.addingTimeInterval(-10) }
            bookings[index, default: []].append((glide.end, leave))
            let sit = Leg(start: glide.end, end: leave, from: seat, control: seat, to: seat, fromWidth: flower.width, toWidth: flower.width,
                          resting: true, tilt: .random(in: -10...10), phase: .random(in: 0...6))
            return [glide, sit]
        }
        return nil
    }

    /// Sitting on a flower: the butterfly's body a little above the flower's middle.
    private static func seat(on flower: Flower) -> CGPoint {
        CGPoint(x: flower.x, y: flower.y - flower.width * drawingAspect * 0.22)
    }

    private static func randomAir() -> CGPoint {
        CGPoint(x: .random(in: air.minX...air.maxX), y: .random(in: air.minY...air.maxY))
    }

    private static func bezier(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        let s = 1 - t
        return CGPoint(x: s * s * a.x + 2 * s * t * c.x + t * t * b.x, y: s * s * a.y + 2 * s * t * c.y + t * t * b.y)
    }
}

#Preview {
    ChildGardenView().environment(ChildGame())
}

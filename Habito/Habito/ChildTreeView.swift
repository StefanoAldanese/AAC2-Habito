//
//  ChildTreeView.swift
//  Habito
//
//  The child's main screen, where the animations come together: the tree with
//  one apple per task, the caterpillar on its leaf and the progress bar on top.
//
//  - Tap an apple to hear its task. "I did it!" marks the task done on the server
//    (ChildTreeModel) and the apple turns ripe.
//  - Grab a ripe apple to snap it off and carry it; near the caterpillar it opens
//    its mouth. Drop it in to feed it. Locked apples stay on the tree.
//  - Let go anywhere else, or throw it, and it falls away and regrows.
//  - Shake the phone: dizzy caterpillar, swaying tree, a leaf or two drifting down,
//    swinging apples, and new tasks grow in as new apples.
//

import SwiftUI
import KeychainSwift

// MARK: - Layout

/// Where things sit. Drawn for a 402 x 870 point phone (the garden picture), scaled to fit
/// the screen and anchored to its bottom, so the grass always reaches the bottom edge.
/// Above and beside the picture, plain sky and grass colours carry on.
struct TreeLayout {
    let size: CGSize

    static let design = CGSize(width: 402, height: 870)

    var scale: CGFloat { min(size.width / Self.design.width, size.height / Self.design.height) }
    private var left: CGFloat { (size.width - Self.design.width * scale) / 2 }
    private var top: CGFloat { size.height - Self.design.height * scale }

    /// A point of the 402 x 870 design, on this screen.
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: left + x * scale, y: top + y * scale)
    }

    func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(origin: point(x, y), size: CGSize(width: width * scale, height: height * scale))
    }

    /// Sky, bushes, hill, plants and the leaf: one picture.
    var scenery: CGRect { rect(0, 0, 402, 870) }
    var tree: CGRect { rect(39, 117.17, 320.6, 416.4) }
    /// Where the hill meets the sky, for the colour beside a picture narrower than the screen.
    var horizon: CGFloat { point(0, 431).y }

    /// The ten apple spots on the tree's leaves, in design points.
    private static let spots: [(CGFloat, CGFloat)] = [
        (150, 160), (240, 150), (300, 200), (95, 215), (185, 205),
        (325, 265), (120, 280), (255, 255), (75, 325), (300, 320),
    ]
    static let spotCount = spots.count

    func spot(_ index: Int) -> CGPoint {
        let (x, y) = Self.spots[index]
        return point(x, y)
    }

    var apple: CGSize { CGSize(width: 34 * scale, height: 40.6 * scale) }

    /// The caterpillar lies on the leaf at the bottom, its head on the left.
    var caterpillar: CGRect { rect(53.57, 590.86, 312.83, 129.95) }
    /// The middle of its open mouth.
    var mouth: CGPoint { point(113.6, 700) }
}

// MARK: - Screen

struct ChildTreeView: View {
    @Environment(ChildGame.self) private var game
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var model = ChildTreeModel()

    // Interaction and animation state; the model never sees these.
    @State private var bubble: String?
    /// The apple in the child's hand, and where the finger is.
    @State private var carried: String?
    @State private var hand: CGPoint = .zero
    /// The apple going into the mouth while the server is told.
    @State private var eating: String?
    @State private var swallowing = false
    @State private var falling: [FallingApple] = []
    /// Leaves shaken off the tree, drifting down.
    @State private var leaves: [FallingLeaf] = []
    /// Apples that fell off: their spot stays empty until they regrow.
    @State private var offTree: Set<String> = []
    /// Set while a finger is on an apple; reset by the system if the drag is cancelled.
    @GestureState private var dragging: String?
    @State private var regrow: [String: Int] = [:]

    @State private var shake = 0
    @State private var lastShakeEffect = Date.distantPast
    @State private var dizzy = false
    @State private var dizzyToken = 0
    @State private var chew = 0
    @State private var snapped = 0
    @State private var fed = 0
    @State private var ripened = 0

    @State private var message: String?
    @State private var messageID = 0

    var body: some View {
        GeometryReader { proxy in
            let layout = TreeLayout(size: proxy.size)
            ZStack(alignment: .topLeading) {
                scenery(layout)
                ForEach(model.hanging, id: \.task.id) { item in
                    apple(item.task, spot: item.spot, layout: layout)
                }
                fallingLeaves(layout)
                caterpillar(layout)
                speech(layout)
                fallingApples(layout)
                inHand(layout)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .coordinateSpace(name: "tree")
            .onChange(of: model.fellOff) { _, new in
                guard !new.isEmpty else { return }
                for apple in model.takeFellOff() { fallOff(apple, layout: layout) }
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottomLeading) { debugShakeButton }
        .task {
            await reload()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await reload() } }
        }
        .onChange(of: bubble) { _, new in
            if new == nil { Speaker.shared.stop() }
        }
        .onChange(of: dragging) { _, new in
            // The system cancelled the drag (a call, a system gesture): drop the apple.
            guard new == nil, let id = carried, let task = model.onTree.first(where: { $0.id == id }) else { return }
            drop(task, at: hand, velocity: CGVector(dx: 0, dy: -80), screen: UIScreen.main.bounds.size)
        }
        .onShake { phase in
            shaken()
            if phase == .ended { Task { await refreshAfterShake() } }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: snapped)
        .sensoryFeedback(.success, trigger: fed)
        .sensoryFeedback(.impact(weight: .medium), trigger: ripened)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: shake)
    }

    // MARK: Layers

    private var topBar: some View {
        ChildProgressBar(steps: game.steps, today: model.todayFraction)
            .padding(.horizontal, 16)
            .padding(.top, 4)
    }

    /// Messages come from the caterpillar: a little cloud above its head.
    private func speech(_ layout: TreeLayout) -> some View {
        Color.clear
            .frame(width: 1, height: 1)
            .overlay(alignment: .bottomLeading) {
                if let message {
                    SpeechCloud(text: message)
                        .frame(width: min(320, max(200, 300 * layout.scale)), alignment: .bottomLeading)
                        .id(messageID)
                        .transition(.scale(scale: 0.3, anchor: .bottomLeading).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.68), value: messageID)
            .animation(.easeOut(duration: 0.2), value: message == nil)
            .position(layout.point(30, 578))
            .allowsHitTesting(false)
    }

    private func scenery(_ layout: TreeLayout) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                Color.gardenSky.frame(height: max(0, layout.horizon))
                Color.gardenGrass
            }
            placed("Scenery", in: layout.scenery)
            // The whole tree sways from its roots when the phone is shaken.
            placed("Tree", in: layout.tree)
                .keyframeAnimator(initialValue: Rustle(), trigger: reduceMotion ? 0 : shake) { content, rustle in
                    content.rotationEffect(.degrees(rustle.angle), anchor: UnitPoint(x: 0.5, y: 0.97))
                } keyframes: { _ in
                    KeyframeTrack(\.angle) {
                        CubicKeyframe(1.6, duration: 0.08); CubicKeyframe(-1.4, duration: 0.1)
                        CubicKeyframe(1.1, duration: 0.1); CubicKeyframe(-0.8, duration: 0.11)
                        CubicKeyframe(0.5, duration: 0.13); CubicKeyframe(-0.25, duration: 0.15)
                        CubicKeyframe(0, duration: 0.2)
                    }
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func placed(_ name: String, in rect: CGRect) -> some View {
        Image(name)
            .resizable()
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    private func caterpillar(_ layout: TreeLayout) -> some View {
        CaterpillarView(mouthOpen: mouthOpen(layout), dizzy: dizzy, wobble: shake, chew: chew)
            .frame(width: layout.caterpillar.width, height: layout.caterpillar.height)
            .position(x: layout.caterpillar.midX, y: layout.caterpillar.midY)
            .allowsHitTesting(false)
    }

    /// The mouth opens while an apple is carried close, and while it is eaten.
    private func mouthOpen(_ layout: TreeLayout) -> Bool {
        if eating != nil { return true }
        guard carried != nil else { return false }
        return distance(hand, layout.mouth) < Reach.open * layout.scale
    }

    private func apple(_ task: TaskItem, spot: Int, layout: TreeLayout) -> some View {
        let home = layout.spot(spot)
        let away = carried == task.id || eating == task.id || offTree.contains(task.id)
        let ripe = model.isRipe(task.id)
        return AppleView(
            size: layout.apple,
            swing: shake,
            swingStrength: 0.75 + Double((spot * 37) % 50) / 100,
            regrow: regrow[task.id, default: 0],
            hidden: away,
            growsSlowly: model.arrivals.contains(task.id),
            onGrown: { model.arrived(task.id) }
        )
        // A ripe apple glows: it can be picked.
        .shadow(color: ripe ? .white : .clear, radius: 4)
        .shadow(color: ripe ? Color.habitoGreen.opacity(0.9) : .clear, radius: 9)
        .animation(.easeOut(duration: 0.4), value: ripe)
        .frame(width: max(56, layout.apple.width + 18), height: max(56, layout.apple.height + 18))
        .contentShape(Rectangle())
        .onTapGesture { bubble = task.id }
        // Only a ripe apple can be picked. (Ripeness does not change during a drag, so
        // the drag is never switched off mid-way.)
        .gesture(drag(task, home: home, layout: layout), including: ripe && eating == nil ? .all : .none)
        .popover(
            isPresented: Binding(get: { bubble == task.id }, set: { if !$0, bubble == task.id { bubble = nil } }),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            TaskBubble(task: task, isRipe: ripe) { await markDone(task) }
        }
        .position(home)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Apple: \(task.title)")
        .accessibilityValue(away ? "Off the tree" : (ripe ? "Ready to feed" : "On the tree"))
        .accessibilityHint(ripe ? "Drag it to the caterpillar to feed it" : "Opens the task")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Feed the caterpillar") {
            if ripe, eating == nil { eat(task, from: home, mouth: layout.mouth) }
        }
    }

    /// The apple following the finger, and the one going into the mouth.
    @ViewBuilder
    private func inHand(_ layout: TreeLayout) -> some View {
        if carried != nil || eating != nil {
            Image("Apple")
                .resizable()
                .frame(width: layout.apple.width, height: layout.apple.height)
                .scaleEffect(swallowing ? 0.2 : 1.45)
                .opacity(swallowing ? 0 : 1)
                .shadow(color: .black.opacity(0.3), radius: 6, y: 6)
                .position(hand)
                .allowsHitTesting(false)
        }
    }

    private func fallingApples(_ layout: TreeLayout) -> some View {
        TimelineView(.animation(paused: falling.isEmpty)) { context in
            ZStack(alignment: .topLeading) {
                ForEach(falling) { apple in
                    Image("Apple")
                        .resizable()
                        .frame(width: layout.apple.width * apple.scale, height: layout.apple.height * apple.scale)
                        .rotationEffect(.degrees(apple.angle(at: context.date)))
                        .position(apple.position(at: context.date))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func fallingLeaves(_ layout: TreeLayout) -> some View {
        TimelineView(.animation(paused: leaves.isEmpty)) { context in
            ZStack(alignment: .topLeading) {
                ForEach(leaves) { leaf in
                    let state = leaf.state(at: context.date)
                    Image("FallingLeaf")
                        .resizable()
                        .frame(width: leaf.size * layout.scale, height: leaf.size * 0.73 * layout.scale)
                        .scaleEffect(x: leaf.mirrored ? -1 : 1)
                        // A flat leaf turning in the air: it narrows as it tips over.
                        .scaleEffect(x: 1, y: state.squash)
                        .rotationEffect(.degrees(state.angle))
                        .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1.5)
                        .opacity(state.opacity)
                        .position(layout.point(state.point.x, state.point.y))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var debugShakeButton: some View {
        #if DEBUG
        // UI tests cannot shake the simulator; this lets them. Never in a release build.
        if ProcessInfo.processInfo.environment["HABITO_TEST_SHAKE"] == "1" {
            Button("Test shake") {
                NotificationCenter.default.post(name: .habitoShakeBegan, object: nil)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    NotificationCenter.default.post(name: .habitoShakeEnded, object: nil)
                }
            }
            .font(.caption2)
            .opacity(0.02)
            .padding(30)
            .accessibilityIdentifier("debugShake")
        }
        #endif
    }

    // MARK: Drag and drop

    private enum Reach {
        /// The mouth opens when the apple is this close (in design points).
        static let open: CGFloat = 150
        /// Dropped this close, the apple is eaten.
        static let eat: CGFloat = 95
        /// Let go faster than this (points per second) and the apple is thrown.
        static let throwSpeed: CGFloat = 700
    }

    private func drag(_ task: TaskItem, home: CGPoint, layout: TreeLayout) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("tree"))
            .updating($dragging) { _, state, _ in state = task.id }
            .onChanged { value in
                if carried == nil {
                    bubble = nil
                    snapped += 1
                    hand = home
                    carried = task.id
                    withAnimation(.spring(response: 0.18, dampingFraction: 0.7)) { hand = value.location }
                } else {
                    hand = value.location
                }
            }
            .onEnded { value in
                if distance(value.location, layout.mouth) < Reach.eat * layout.scale {
                    eat(task, from: value.location, mouth: layout.mouth)
                } else {
                    let speed = hypot(value.velocity.width, value.velocity.height)
                    let thrown = speed > Reach.throwSpeed
                    let velocity = thrown
                        ? CGVector(dx: value.velocity.width.clamped(-3200, 3200), dy: value.velocity.height.clamped(-3200, 3200))
                        : CGVector(dx: Double.random(in: -60...60), dy: -80)
                    drop(task, at: value.location, velocity: velocity, screen: layout.size)
                }
            }
    }

    /// Let go away from the mouth: the apple falls out of the screen and regrows on its spot.
    private func drop(_ task: TaskItem, at point: CGPoint, velocity: CGVector, screen: CGSize) {
        offTree.insert(task.id)
        carried = nil
        let apple = FallingApple(taskID: task.id, start: point, velocity: velocity,
                                 spin: Double.random(in: 200...420) * (velocity.dx < 0 ? -1 : 1), startDate: .now)
        falling.append(apple)
        // Wait until it has left the screen, and a beat longer, before it grows back.
        let leave = max(0.8, apple.timeToLeave(screen))
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(leave))
            falling.removeAll { $0.id == apple.id }
            offTree.remove(task.id)
            regrow[task.id, default: 0] += 1
        }
    }

    /// The parent deleted the task (or it is no longer for today): its apple drops off the tree,
    /// out of the hand if the child is holding it, and does not grow back.
    private func fallOff(_ apple: ChildTreeModel.FellOff, layout: TreeLayout) {
        if bubble == apple.id { bubble = nil }
        // Already falling after a drop, or going into the mouth: nothing more to show.
        guard eating != apple.id, !offTree.contains(apple.id) else { return }
        let inHand = carried == apple.id
        if inHand { carried = nil }
        let fall = FallingApple(
            taskID: apple.id,
            start: inHand ? hand : layout.spot(apple.spot),
            velocity: CGVector(dx: Double.random(in: -90...90), dy: -70),
            spin: Double.random(in: 160...320) * (Bool.random() ? 1 : -1),
            startDate: .now,
            scale: inHand ? 1.3 : 1
        )
        falling.append(fall)
        let leave = fall.timeToLeave(layout.size)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(leave))
            falling.removeAll { $0.id == fall.id }
        }
    }

    /// Dropped on the mouth: the apple goes in, then the model tells the server.
    private func eat(_ task: TaskItem, from point: CGPoint, mouth: CGPoint) {
        bubble = nil
        hand = point
        eating = task.id
        carried = nil
        withAnimation(.easeIn(duration: 0.22)) {
            hand = mouth
            swallowing = true
        } completion: {
            Task { await finishEating(task) }
        }
    }

    private func finishEating(_ task: TaskItem) async {
        model.eat(task)
        chew += 1
        fed += 1
        if let today = model.todayList { game.record(today) }
        eating = nil
        swallowing = false
    }

    /// "I did it!": the server marks the task done and tells the parent; the apple ripens.
    private func markDone(_ task: TaskItem) async {
        switch await model.markDone(task) {
        case .done:
            ripened += 1
            bubble = nil
            // The first time only: after that the child knows what to do.
            if !UserDefaults.standard.bool(forKey: ChildGame.feedHintKey) {
                UserDefaults.standard.set(true, forKey: ChildGame.feedHintKey)
                show("Well done! Now pull the apple off and feed me!")
            }
        case .gone(let text):
            bubble = nil
            show(text)
        case .failed(let text):
            show(text)
        case .signedOut:
            signOut()
        }
    }

    // MARK: Shake

    /// The look of a shake. Runs at most every 0.8 seconds however hard the phone is shaken.
    private func shaken() {
        let now = Date()
        guard now.timeIntervalSince(lastShakeEffect) > 0.8 else { return }
        lastShakeEffect = now
        bubble = nil
        shake += 1
        if !reduceMotion { dropLeaves() }
        dizzyToken += 1
        let token = dizzyToken
        dizzy = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            if dizzyToken == token { dizzy = false }
        }
    }

    /// One or two leaves come off the tree with each shake, and drift down to the grass.
    private func dropLeaves() {
        let now = Date()
        leaves.removeAll { $0.isGone(at: now) }
        guard leaves.count < 6 else { return }
        let count = Int.random(in: 1...2)
        var spots = FallingLeaf.starts.shuffled()
        for index in 0..<count {
            let leaf = FallingLeaf(from: spots.removeFirst(), delay: 0.05 + Double(index) * Double.random(in: 0.25...0.6), now: now)
            leaves.append(leaf)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(leaf.lifetime + 0.2))
                leaves.removeAll { $0.id == leaf.id }
            }
        }
    }

    /// Fetching new tasks after a shake. The model skips it when one ran moments ago.
    private func refreshAfterShake() async {
        let before = model.onTree.count
        guard let stillJoined = await model.refreshAfterShake() else { return }
        guard stillJoined else { signOut(); return }
        if let today = model.todayList { game.record(today) }
        let added = model.arrivals.count
        if model.loadError == nil, added > 0 {
            show(added == 1 ? "A new apple is growing!" : "\(added) new apples are growing!")
        } else if model.onTree.count == before {
            show("No new tasks yet.")
        }
    }

    // MARK: Helpers

    private func reload() async {
        guard await model.load() else { signOut(); return }
        if let today = model.todayList { game.record(today) }
        if let error = model.loadError { show(error) }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func show(_ text: String) {
        messageID += 1
        let id = messageID
        message = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(text.count > 30 ? 4 : 3))
            if messageID == id { message = nil }
        }
    }

    /// The parent's code was used on another device: back to the start.
    private func signOut() {
        KeychainSwift().delete(HabitoAPI.childTokenKey)
        ParentSession.refreshRoot()
    }
}

/// How far the tree leans during a shake.
private struct Rustle {
    var angle: Double = 0
}

extension Color {
    /// The garden picture's sky and grass, to carry on past its edges.
    static let gardenSky = Color(red: 158 / 255, green: 227 / 255, blue: 235 / 255)
    static let gardenGrass = Color(red: 195 / 255, green: 1, blue: 198 / 255)
    /// The dark green of the leaf.
    static let gardenLeaf = Color(red: 12 / 255, green: 76 / 255, blue: 41 / 255)
}

/// A leaf shaken off the tree. It is light: it speeds up only a little, then drifts down
/// slowly, swaying from side to side and tipping as it swings, and settles on the grass
/// before fading away. Everything is in design points (see TreeLayout).
struct FallingLeaf: Identifiable {
    let id = UUID()
    let start: CGPoint
    let delay: Double
    let startDate: Date
    /// Where it settles on the grass.
    let ground: CGFloat
    /// Falling speed once it has picked up speed, points per second.
    let speed: CGFloat
    let sway: CGFloat
    let period: Double
    let phase: Double
    let drift: CGFloat
    let tilt: Double
    let size: CGFloat
    let mirrored: Bool
    /// Seconds from letting go until it lies on the grass.
    let landing: Double

    static let rest = 0.9
    static let fade = 1.0

    /// Places among the outer leaves of the tree where a leaf can come loose.
    static let starts: [CGPoint] = [
        CGPoint(x: 70, y: 300), CGPoint(x: 335, y: 290), CGPoint(x: 110, y: 185), CGPoint(x: 300, y: 165),
        CGPoint(x: 205, y: 140), CGPoint(x: 55, y: 240), CGPoint(x: 350, y: 235), CGPoint(x: 260, y: 315),
        CGPoint(x: 140, y: 335), CGPoint(x: 230, y: 230),
    ]

    init(from start: CGPoint, delay: Double, now: Date) {
        self.start = CGPoint(x: start.x + .random(in: -12...12), y: start.y + .random(in: -8...8))
        self.delay = delay
        startDate = now
        ground = .random(in: 470...560)
        speed = .random(in: 48...68)
        sway = .random(in: 18...30)
        period = .random(in: 1.5...2.1)
        phase = .random(in: 0...(2 * .pi))
        drift = .random(in: -14...14)
        tilt = .random(in: -20...20)
        size = .random(in: 28...34)
        mirrored = Bool.random()
        // When does it reach the grass? Step through the fall once.
        var t = 0.0
        while t < 20, Self.fallen(t, speed: speed) < ground - self.start.y { t += 1.0 / 60 }
        landing = t
    }

    /// The whole life of the leaf, from the shake until it has faded.
    var lifetime: Double { delay + landing + Self.rest + Self.fade }

    func isGone(at date: Date) -> Bool { date.timeIntervalSince(startDate) > lifetime }

    /// Distance fallen after `t` seconds: it reaches its slow speed within about half a second.
    private static func fallen(_ t: Double, speed: CGFloat) -> CGFloat {
        let settle = 0.45
        return speed * CGFloat(t - settle * (1 - exp(-t / settle)))
    }

    func state(at date: Date) -> (point: CGPoint, angle: Double, squash: CGFloat, opacity: Double) {
        let elapsed = date.timeIntervalSince(startDate) - delay
        let t = min(max(0, elapsed), landing)
        let wave = 2 * Double.pi * t / period + phase
        let x = start.x + drift * CGFloat(t) + sway * CGFloat(sin(wave) - sin(phase))
        let y = start.y + Self.fallen(t, speed: speed)
        // It tips the way it is swinging, and turns its face a little as it does.
        let angle = tilt + 32 * cos(wave)
        let squash = CGFloat(0.75 + 0.25 * abs(cos(wave)))
        var opacity = 1.0
        if elapsed < 0 { opacity = 0 }
        else if elapsed < 0.2 { opacity = elapsed / 0.2 }
        let resting = elapsed - landing
        if resting > Self.rest { opacity = max(0, 1 - (resting - Self.rest) / Self.fade) }
        return (CGPoint(x: x, y: y), angle, squash, opacity)
    }
}

private extension CGFloat {
    func clamped(_ low: CGFloat, _ high: CGFloat) -> CGFloat { Swift.min(high, Swift.max(low, self)) }
}

// MARK: - What the caterpillar says

/// The caterpillar's words in a puffy white cloud, like the one it dreams in on the
/// Butterflies page, with two little outlined bubbles leading down to its head.
private struct SpeechCloud: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.1, green: 0.17, blue: 0.12))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 26)
                .padding(.vertical, 20)
                .background(CloudShape().fill(.white).shadow(color: .black.opacity(0.1), radius: 8, y: 4))
            Circle().fill(.white).stroke(Color.gardenLeaf, lineWidth: 2)
                .frame(width: 16, height: 16).padding(.leading, 48).padding(.top, 6)
            Circle().fill(.white).stroke(Color.gardenLeaf, lineWidth: 2)
                .frame(width: 9, height: 9).padding(.leading, 64)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Caterpillar says: \(text)")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Round puffs around a soft body, sized from the box's height so any text fits.
private struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let h = rect.height, w = rect.width
        func puff(_ x: CGFloat, _ y: CGFloat, _ d: CGFloat) {
            path.addEllipse(in: CGRect(x: rect.minX + x - d / 2, y: rect.minY + y - d / 2, width: d, height: d))
        }
        // the body
        path.addRoundedRect(in: CGRect(x: rect.minX, y: rect.minY + h * 0.16, width: w, height: h * 0.7),
                            cornerSize: CGSize(width: h * 0.35, height: h * 0.35), style: .continuous)
        // big puffs along the top, smaller ones underneath, one at each end
        let top = max(2, Int((w - h * 0.6) / (h * 0.8)))
        for i in 0..<top {
            let x = h * 0.6 + (w - h * 1.2) * CGFloat(i) / CGFloat(top - 1)
            puff(x, h * 0.34, h * (i % 2 == 0 ? 0.86 : 1.02))
        }
        for i in 0..<(top - 1) {
            let x = h * 0.6 + (w - h * 1.2) * (CGFloat(i) + 0.5) / CGFloat(top - 1)
            puff(x, h * 0.7, h * 0.74)
        }
        puff(h * 0.42, h * 0.56, h * 0.84)
        puff(w - h * 0.42, h * 0.52, h * 0.8)
        return path
    }
}

// MARK: - The bubble from an apple

private struct TaskBubble: View {
    let task: TaskItem
    let isRipe: Bool
    let onDone: () async -> Void
    @State private var isBusy = false

    private var spoken: String {
        task.descriptionText.isEmpty ? task.title : "\(task.title). \(task.descriptionText)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(task.title)
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            if !task.descriptionText.isEmpty {
                Text(task.descriptionText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            Button { Speaker.shared.say(spoken) } label: {
                Label("Read aloud", systemImage: "speaker.wave.2.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color.habitoGreen, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
            if isRipe {
                Label("Done! Pull the apple off and feed it to the caterpillar.", systemImage: "hand.draw.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.habitoGreenDeep)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            } else {
                Button {
                    guard !isBusy else { return }
                    isBusy = true
                    Task {
                        await onDone()
                        isBusy = false
                    }
                } label: {
                    ZStack {
                        Text("I did it!").opacity(isBusy ? 0 : 1)
                        if isBusy { ProgressView().tint(Color.habitoGreenDeep) }
                    }
                    .font(.headline)
                    .foregroundStyle(Color.habitoGreenDeep)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color.habitoGreen.opacity(0.18), in: Capsule())
                    .overlay(Capsule().stroke(Color.habitoGreen, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .padding(.top, 10)
            }
        }
        .padding(18)
        .frame(width: 300, alignment: .leading)
        .presentationCompactAdaptation(.popover)
    }
}

// MARK: - Progress bar

/// Seven perfect days turn the caterpillar into a butterfly. Today's step fills as
/// apples are eaten.
struct ChildProgressBar: View {
    let steps: Int
    /// Today's share of tasks done, 0 to 1.
    var today: Double = 0
    private let goal = ChildGame.daysPerButterfly

    private var isFull: Bool { steps >= goal }
    private var title: String {
        let left = goal - steps
        if left <= 0 { return "Butterfly time!" }
        return left == 1 ? "1 more perfect day" : "\(left) more perfect days"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image("BarCaterpillar")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 36)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.footnote.weight(.semibold))
                    Spacer(minLength: 6)
                    Text("\(steps) of \(goal)")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    ForEach(0..<goal, id: \.self) { index in
                        segment(fill: index < steps ? 1 : (index == steps ? min(max(today, 0), 0.999) : 0))
                    }
                }
            }

            Image("BarButterfly")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 36)
                .scaleEffect(isFull ? 1.15 : 1)
        }
        .padding(.horizontal, 8)
        .frame(height: 56)
        .frame(maxWidth: 420)
        .habitoGlass(in: Capsule())
        .animation(.snappy, value: steps)
        .animation(.easeOut(duration: 0.6), value: today)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(steps) of \(goal) perfect days.")
        .accessibilityValue(today > 0 && !isFull ? "Today \(Int((today * 100).rounded())) percent done" : "")
    }

    private func segment(fill: Double) -> some View {
        Capsule()
            .fill(Color.primary.opacity(0.16))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.habitoGreen)
                        .frame(width: fill > 0 ? max(proxy.size.height, proxy.size.width * fill) : 0)
                }
            }
            .clipShape(Capsule())
            .frame(height: 8)
    }
}

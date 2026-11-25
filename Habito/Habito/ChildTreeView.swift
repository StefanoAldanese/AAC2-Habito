//
//  ChildTreeView.swift
//  Habito
//
//  The child's main screen, where the animations come together: the tree with
//  one apple per task, the caterpillar on its leaf and the progress bar on top.
//
//  - A task not done yet is a blossom. Tap it to hear the task. "I did it!" marks the
//    task done on the server (ChildTreeModel) and the blossom turns into an apple,
//    dropping a few petals.
//  - Grab an apple to snap it off and carry it; near the caterpillar it opens its
//    mouth. Drop it in to feed it. Blossoms stay on the tree.
//  - Let go anywhere else, or throw it, and it falls away and regrows.
//  - Shake the phone (on iPad: rub a finger back and forth on the garden): dizzy
//    caterpillar, swaying tree, a leaf or two drifting down,
//    swinging apples, and new tasks grow in as new apples.
//

import SwiftUI
import KeychainSwift

// MARK: - Layout

/// Where things sit on the child's screens, in the design's own points.
///
/// - iPhone: a 402 x 870 picture, scaled to fit and anchored to the bottom, so the grass
///   always reaches the bottom edge; plain sky and grass carry on above and beside it.
/// - iPad: a wide 1366 x 1024 picture that fills the screen in either orientation. Held
///   upright, its sides are trimmed; on a wider iPad a little of the sky is.
///
/// The iPad drawings are the same tree and caterpillar, bigger, so every position on the
/// iPad is worked out from the iPhone one, relative to the tree or the caterpillar.
struct TreeLayout {
    let size: CGSize
    var pad: Bool = TreeLayout.isPad
    /// iPad, when the picture is wider than the screen (held upright): the design x kept in
    /// the middle, so the caterpillar is not cut off at the side.
    var focusX: CGFloat = 640

    static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var design: CGSize { pad ? CGSize(width: 1366, height: 1024) : CGSize(width: 402, height: 870) }

    var scale: CGFloat {
        pad ? max(size.width / design.width, size.height / design.height)
            : min(size.width / design.width, size.height / design.height)
    }
    private var left: CGFloat {
        let overflow = size.width - design.width * scale // zero or less
        guard pad, overflow < 0 else { return overflow / 2 }
        return min(0, max(overflow, size.width / 2 - focusX * scale))
    }
    /// iPhone: anchored to the bottom. iPad: what does not fit is trimmed a bit more at the top
    /// (sky) than at the bottom (where the caterpillar lies).
    private var top: CGFloat { pad ? (size.height - design.height * scale) * 0.6 : size.height - design.height * scale }

    /// How much bigger things like apples and leaves are drawn on the iPad's bigger tree.
    var detail: CGFloat { pad ? Self.padTree.width / Self.phoneTree.width : 1 }
    /// Points on screen for one design point of an apple, leaf or reach distance.
    var unit: CGFloat { scale * detail }

    /// A point of the design, on this screen.
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: left + x * scale, y: top + y * scale)
    }

    func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(origin: point(x, y), size: CGSize(width: width * scale, height: height * scale))
    }

    func rect(_ r: CGRect) -> CGRect { rect(r.minX, r.minY, r.width, r.height) }

    /// The whole picture.
    var scenery: CGRect { rect(0, 0, design.width, design.height) }
    var tree: CGRect { rect(pad ? Self.padTree : Self.phoneTree) }
    /// iPad only: the plants, grass tufts and leaf drawn in front of the tree.
    var front: CGRect { rect(21.5, 555, 1305, 469) }
    /// iPhone: where the hill meets the sky, for the colour beside a narrower picture.
    var horizon: CGFloat { point(0, 431).y }

    private static let phoneTree = CGRect(x: 39, y: 117.17, width: 320.6, height: 416.4)
    /// The iPad tree is drawn at 88% of its size in the picture, shrunk towards its roots, so its
    /// top and blossoms sit clear below the progress bar while the trunk stays where it stood.
    private static let padTree: CGRect = {
        let drawn = CGRect(x: 426.5, y: 108.5, width: 511, height: 663.5), k: CGFloat = 0.88
        return CGRect(x: drawn.midX - drawn.width * k / 2, y: drawn.maxY - drawn.height * k,
                      width: drawn.width * k, height: drawn.height * k)
    }()
    private static let phoneCaterpillar = CGRect(x: 53.57, y: 590.86, width: 312.83, height: 129.95)
    private static let padCaterpillar = CGRect(x: 376, y: 768, width: 475, height: 198)

    /// An iPhone point on the tree, at the same place on this device's tree, in design points.
    private func onTree(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        guard pad else { return CGPoint(x: x, y: y) }
        let from = Self.phoneTree, to = Self.padTree
        return CGPoint(x: to.minX + (x - from.minX) / from.width * to.width,
                       y: to.minY + (y - from.minY) / from.height * to.height)
    }

    /// An iPhone point near the caterpillar, at the same place by this device's caterpillar.
    private func byCaterpillar(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        guard pad else { return CGPoint(x: x, y: y) }
        let from = Self.phoneCaterpillar, to = Self.padCaterpillar
        return CGPoint(x: to.minX + (x - from.minX) / from.width * to.width,
                       y: to.minY + (y - from.minY) / from.height * to.height)
    }

    /// The ten apple spots on the tree's leaves (iPhone design points).
    private static let spots: [(CGFloat, CGFloat)] = [
        (150, 160), (240, 150), (300, 200), (95, 215), (185, 205),
        (325, 265), (120, 280), (255, 255), (75, 325), (300, 320),
    ]
    static let spotCount = spots.count

    func spot(_ index: Int) -> CGPoint {
        let p = designSpot(index)
        return point(p.x, p.y)
    }

    /// A spot in design points, for things that move in design points (falling petals).
    func designSpot(_ index: Int) -> CGPoint {
        onTree(Self.spots[index].0, Self.spots[index].1)
    }

    /// Where a shaken leaf can come loose, in design points.
    var leafStarts: [CGPoint] { FallingLeaf.starts.map { onTree($0.x, $0.y) } }
    /// How far down the screen fallen leaves come to rest, in design points.
    var ground: ClosedRange<CGFloat> { onTree(0, 470).y...onTree(0, 560).y }

    var apple: CGSize { CGSize(width: 34 * unit, height: 40.6 * unit) }

    /// The caterpillar lies on the leaf at the bottom, its head on the left.
    var caterpillar: CGRect { rect(pad ? Self.padCaterpillar : Self.phoneCaterpillar) }
    /// The middle of its open mouth.
    var mouth: CGPoint { let p = byCaterpillar(113.6, 700); return point(p.x, p.y) }
    /// The bottom-left corner of the speech cloud, just above its head.
    var speech: CGPoint { let p = byCaterpillar(30, 578); return point(p.x, p.y) }
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
    /// iPad: rubbing a finger back and forth on the garden does what a shake does on iPhone.
    @State private var wiggle = WiggleTracker()
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
                if layout.pad { wiggleArea }
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
                        .frame(width: min(layout.pad ? 420 : 320, max(200, 300 * layout.unit)), alignment: .bottomLeading)
                        .id(messageID)
                        .transition(.scale(scale: 0.3, anchor: .bottomLeading).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.68), value: messageID)
            .animation(.easeOut(duration: 0.2), value: message == nil)
            .position(layout.speech)
            .allowsHitTesting(false)
    }

    private func scenery(_ layout: TreeLayout) -> some View {
        ZStack(alignment: .topLeading) {
            if layout.pad {
                placed("PadTreeScenery", in: layout.scenery)
            } else {
                VStack(spacing: 0) {
                    Color.gardenSky.frame(height: max(0, layout.horizon))
                    Color.gardenGrass
                }
                placed("Scenery", in: layout.scenery)
            }
            // The whole tree sways from its roots when the phone is shaken.
            placed(layout.pad ? "PadTree" : "Tree", in: layout.tree)
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
            if layout.pad {
                placed("PadTreeFront", in: layout.front)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// iPad only: the whole garden behind the apples listens for a finger rubbed back and forth.
    /// Apples, the caterpillar and the bar keep their own taps and drags on top of it.
    private var wiggleArea: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard wiggle.add(value.location, at: .now) else { return }
                        // Like a shake: dizzy caterpillar, swaying tree, then a look for new tasks.
                        shaken()
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(450))
                            await refreshAfterShake()
                        }
                    }
                    .onEnded { _ in wiggle.reset() }
            )
            .accessibilityElement()
            .accessibilityLabel("Garden")
            .accessibilityHint("Rub your finger back and forth to look for new tasks")
            .accessibilityAction(named: "Look for new tasks") {
                shaken()
                Task { await refreshAfterShake() }
            }
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
        return distance(hand, layout.mouth) < Reach.open * layout.unit
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
            ripe: ripe,
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
        .accessibilityValue(away ? "Off the tree" : (ripe ? "Ready to feed" : "Blossom"))
        .accessibilityHint(ripe ? "Drag it to the caterpillar to feed it" : "Opens the task. When it is done, the blossom becomes an apple")
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
                    let blossom = apple.image == "Blossom"
                    Image(apple.image)
                        .resizable()
                        .frame(width: layout.apple.width * apple.scale * (blossom ? 1.12 : 1),
                               height: (blossom ? layout.apple.width * 1.12 : layout.apple.height) * apple.scale)
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
                    Image(leaf.image)
                        .resizable()
                        .frame(width: leaf.size * layout.unit, height: leaf.size * leaf.aspect * layout.unit)
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
                if distance(value.location, layout.mouth) < Reach.eat * layout.unit {
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
            scale: inHand ? 1.3 : 1,
            image: apple.ripe || inHand ? "Apple" : "Blossom"
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
            if !reduceMotion, let spot = model.hanging.first(where: { $0.task.id == task.id })?.spot {
                dropPetals(from: TreeLayout(size: .zero).designSpot(spot))
            }
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

    /// The blossom has turned into an apple: a few of its petals float down.
    private func dropPetals(from point: CGPoint) {
        let now = Date()
        for index in 0..<3 {
            let design = TreeLayout(size: .zero)
            let petal = FallingLeaf(from: point, delay: 0.1 + Double(index) * 0.15, now: now,
                                    ground: design.ground, detail: design.detail,
                                    image: "Petal", aspect: 1.28, sizes: 9...12, spread: 7)
            leaves.append(petal)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(petal.lifetime + 0.2))
                leaves.removeAll { $0.id == petal.id }
            }
        }
    }

    /// One or two leaves come off the tree with each shake, and drift down to the grass.
    private func dropLeaves() {
        let now = Date()
        leaves.removeAll { $0.isGone(at: now) }
        guard leaves.count < 6 else { return }
        let count = Int.random(in: 1...2)
        // Only the design-point answers are needed here, which do not depend on the screen size.
        let design = TreeLayout(size: .zero)
        var spots = design.leafStarts.shuffled()
        for index in 0..<count {
            let leaf = FallingLeaf(from: spots.removeFirst(), delay: 0.05 + Double(index) * Double.random(in: 0.25...0.6), now: now,
                                   ground: design.ground, detail: design.detail)
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
        KeychainSwift().delete(HabitoAPI.childRoomCodeKey)
        ParentSession.refreshRoot()
    }
}

/// Spots a finger rubbed quickly back and forth: four or more changes of direction, each after
/// a real movement, within a second and a half. One rub counts once until the finger lifts.
struct WiggleTracker {
    private var anchor: CGPoint?
    private var direction: CGVector = .zero
    private var turns: [Date] = []
    private var fired = false

    static let step: CGFloat = 14
    static let turnsNeeded = 4
    static let window: TimeInterval = 1.5

    /// Feeds the finger's position; true when this movement completes a wiggle.
    mutating func add(_ point: CGPoint, at date: Date) -> Bool {
        guard let start = anchor else { anchor = point; return false }
        let dx = point.x - start.x, dy = point.y - start.y
        guard hypot(dx, dy) >= Self.step else { return false }
        let now = CGVector(dx: dx, dy: dy)
        // A turn: this stretch goes against the last one (they point more than 90° apart).
        if direction != .zero, now.dx * direction.dx + now.dy * direction.dy < 0 {
            turns.append(date)
        }
        direction = now
        anchor = point
        turns.removeAll { date.timeIntervalSince($0) > Self.window }
        guard !fired, turns.count >= Self.turnsNeeded else { return false }
        fired = true
        return true
    }

    mutating func reset() { self = WiggleTracker() }
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

/// A leaf shaken off the tree, or a petal from a blossom that became an apple. It is light: it speeds up only a little, then drifts down
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
    /// The picture, and its height for each point of width.
    let image: String
    let aspect: CGFloat
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

    /// A leaf by default; a blossom's petals use the same drift with their own picture.
    /// `ground` is where it may come to rest and `detail` how much bigger the tree is drawn
    /// (iPad), both in design points; `sizes` is in the iPhone's points.
    init(from start: CGPoint, delay: Double, now: Date, ground: ClosedRange<CGFloat> = 470...560, detail: CGFloat = 1,
         image: String = "FallingLeaf", aspect: CGFloat = 0.73,
         sizes: ClosedRange<CGFloat> = 28...34, spread: CGFloat = 12) {
        let spread = spread * detail
        self.start = CGPoint(x: start.x + .random(in: -spread...spread), y: start.y + .random(in: -spread * 0.7...spread * 0.7))
        self.image = image
        self.aspect = aspect
        self.delay = delay
        startDate = now
        self.ground = .random(in: ground)
        speed = .random(in: 48...68) * detail
        sway = .random(in: 18...30) * detail
        period = .random(in: 1.5...2.1)
        phase = .random(in: 0...(2 * .pi))
        drift = .random(in: -14...14) * detail
        tilt = .random(in: -20...20)
        size = .random(in: sizes)
        mirrored = Bool.random()
        // When does it reach the grass? Step through the fall once.
        var t = 0.0
        while t < 20, Self.fallen(t, speed: speed) < self.ground - self.start.y { t += 1.0 / 60 }
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

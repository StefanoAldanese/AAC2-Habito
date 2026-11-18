//
//  ChildTreeView.swift
//  Habito
//
//  The child's main screen, where the animations come together: the tree with
//  one apple per task, the caterpillar in the corner and the progress bar on top.
//
//  - Tap an apple to hear its task. "I did it!" marks the task done on the server
//    (ChildTreeModel) and the apple turns ripe.
//  - Grab a ripe apple to snap it off and carry it; near the caterpillar it opens
//    its mouth. Drop it in to feed it. Locked apples stay on the tree.
//  - Let go anywhere else, or throw it, and it falls away and regrows.
//  - Shake the phone: dizzy caterpillar, rustling leaves, swinging apples, and new
//    tasks grow in as new apples.
//

import SwiftUI
import KeychainSwift

// MARK: - Layout

/// Where things sit. Drawn for a 402 x 874 point phone, scaled to fit the screen and
/// anchored to its bottom, so the grass always reaches the bottom edge.
struct TreeLayout {
    let size: CGSize

    var scale: CGFloat { min(size.width / 402, size.height / 874) }
    private var left: CGFloat { (size.width - 402 * scale) / 2 }
    private var top: CGFloat { size.height - 874 * scale }

    /// A point of the 402 x 874 design, on this screen.
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: left + x * scale, y: top + y * scale)
    }

    func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(origin: point(x, y), size: CGSize(width: width * scale, height: height * scale))
    }

    /// The backyard picture spans design x -800 to 1202, so wide screens stay covered.
    var yard: CGRect { rect(-800, 0, 2002, 874) }
    var front: CGRect { rect(0, 0, 402, 874) }
    var tree: CGRect { rect(-99, 56, 600, 600 * 909 / 840) }

    /// Where the sky turns white: just above the fence.
    var skyEnd: CGFloat { min(1, max(0.3, point(0, 600).y / max(size.height, 1))) }

    /// The ten apple spots, taken from the apple picture of the tree (1680 pixels wide,
    /// drawn here 600 points wide).
    private static let spots: [(Double, Double)] = [
        (803, 501), (1202, 645), (520, 622), (657, 1047), (1116, 776),
        (394, 859), (1011, 493), (1166, 984), (1234, 779), (988, 929),
    ]
    static let spotCount = spots.count

    func spot(_ index: Int) -> CGPoint {
        let (x, y) = Self.spots[index]
        return point(-99 + x * 600 / 1680, 56 + y * 600 / 1680)
    }

    var apple: CGSize { CGSize(width: 38 * scale, height: 31 * scale) }

    /// The caterpillar hugs the screen's right edge: 560 x 283 points, its left edge 197
    /// points in from the right, its top 354 points above the bottom, turned 20 degrees.
    var caterpillarSize: CGSize { CGSize(width: 560 * scale, height: 283 * scale) }
    var caterpillarCenter: CGPoint {
        CGPoint(x: size.width - 197 * scale + 280 * scale, y: size.height - 354 * scale + 141.5 * scale)
    }
    /// The middle of its open mouth.
    var mouth: CGPoint { CGPoint(x: size.width - 131.7 * scale, y: size.height - 185.4 * scale) }
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
                caterpillar(layout)
                fallingApples(layout)
                inHand(layout)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .coordinateSpace(name: "tree")
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
        VStack(spacing: 10) {
            ChildProgressBar(steps: game.steps, today: model.todayFraction)
            if let message {
                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .habitoGlass(in: Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .animation(.snappy, value: message)
    }

    private func scenery(_ layout: TreeLayout) -> some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.827, green: 0.922, blue: 0.984), location: 0),
                    .init(color: Color(red: 0.918, green: 0.965, blue: 0.996), location: layout.skyEnd * 0.55),
                    .init(color: .white, location: layout.skyEnd),
                ],
                startPoint: .top, endPoint: .bottom
            )
            placed("Backyard", in: layout.yard)
            placed("Tree", in: layout.tree)
            // The leaf clumps again, over the tree, so they can rustle on their own.
            placed("TreeLeaves", in: layout.tree)
                .keyframeAnimator(initialValue: Rustle(), trigger: reduceMotion ? 0 : shake) { content, rustle in
                    content
                        .offset(x: rustle.x * layout.scale, y: rustle.y * layout.scale)
                        .rotationEffect(.degrees(rustle.angle), anchor: UnitPoint(x: 0.5, y: 0.75))
                } keyframes: { _ in
                    KeyframeTrack(\.x) {
                        CubicKeyframe(3.5, duration: 0.07); CubicKeyframe(-3, duration: 0.08)
                        CubicKeyframe(2.8, duration: 0.08); CubicKeyframe(-2.4, duration: 0.08)
                        CubicKeyframe(2, duration: 0.09); CubicKeyframe(-1.5, duration: 0.1)
                        CubicKeyframe(1, duration: 0.12); CubicKeyframe(0, duration: 0.16)
                    }
                    KeyframeTrack(\.y) {
                        CubicKeyframe(-1.5, duration: 0.09); CubicKeyframe(1.2, duration: 0.09)
                        CubicKeyframe(-1, duration: 0.1); CubicKeyframe(0.8, duration: 0.11)
                        CubicKeyframe(0, duration: 0.2)
                    }
                    KeyframeTrack(\.angle) {
                        CubicKeyframe(1.2, duration: 0.12); CubicKeyframe(-1, duration: 0.14)
                        CubicKeyframe(0.7, duration: 0.14); CubicKeyframe(-0.4, duration: 0.16)
                        CubicKeyframe(0, duration: 0.2)
                    }
                }
            placed("BackyardFront", in: layout.front)
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
            .frame(width: layout.caterpillarSize.width, height: layout.caterpillarSize.height)
            .rotationEffect(.degrees(20), anchor: UnitPoint(x: 0.16, y: 0.6))
            .position(layout.caterpillarCenter)
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
                        .frame(width: layout.apple.width * 1.3, height: layout.apple.height * 1.3)
                        .rotationEffect(.degrees(apple.angle(at: context.date)))
                        .position(apple.position(at: context.date))
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
            show("Well done! Now pull the apple off and feed the caterpillar.")
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
        dizzyToken += 1
        let token = dizzyToken
        dizzy = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            if dizzyToken == token { dizzy = false }
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
            try? await Task.sleep(for: .seconds(3))
            if messageID == id { message = nil }
        }
    }

    /// The parent's code was used on another device: back to the start.
    private func signOut() {
        KeychainSwift().delete(HabitoAPI.childTokenKey)
        ParentSession.refreshRoot()
    }
}

/// How far the leaf clumps are pushed during a shake.
private struct Rustle {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var angle: Double = 0
}

private extension CGFloat {
    func clamped(_ low: CGFloat, _ high: CGFloat) -> CGFloat { Swift.min(high, Swift.max(low, self)) }
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
            Image("CaterpillarFace")
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .background(Color(red: 0.85, green: 0.94, blue: 0.72))
                .clipShape(Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)

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

            ZStack {
                Circle().fill(isFull ? Color.habitoGreen : Color.primary.opacity(0.10))
                Image("TabButterfly")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22)
                    .foregroundStyle(isFull ? Color.white : Color.secondary)
            }
            .frame(width: 40, height: 40)
            .overlay(Circle().stroke(isFull ? Color.white : .clear, lineWidth: 2))
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

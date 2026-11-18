//
//  ChildTreeView.swift
//  Habito
//
//  The child's main screen: the tree with one apple per task, the caterpillar
//  in the corner and the progress bar on top. Tap an apple to hear the task and
//  say "I did it!"; then drag the apple into the caterpillar's mouth, which marks
//  the task done.
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

    @State private var today: TodayList?
    /// Apples the child said "I did it!" for: these can be dragged.
    @State private var unlocked: Set<String> = []
    @State private var bubble: String?
    /// The apple in the child's hand, and where the finger is.
    @State private var carried: String?
    @State private var hand: CGPoint = .zero
    /// The apple flying into the mouth while the server is told.
    @State private var eating: String?
    @State private var swallowing = false
    @State private var fed = 0
    @State private var unlockedFeedback = 0
    @State private var message: String?
    @State private var messageID = 0

    /// Which apple hangs on which spot. A task keeps its spot all day; a task after the
    /// tenth waits for a spot that an eaten apple left free.
    private var hanging: [(task: TaskItem, spot: Int)] {
        let all = today?.tasks ?? []
        var result: [(task: TaskItem, spot: Int)] = []
        var free: [Int] = []
        for (index, task) in all.prefix(TreeLayout.spotCount).enumerated() {
            if task.isDone { free.append(index) } else { result.append((task, index)) }
        }
        if all.count < TreeLayout.spotCount { free += Array(all.count..<TreeLayout.spotCount) }
        free.sort()
        for task in all.dropFirst(TreeLayout.spotCount) where !task.isDone {
            guard !free.isEmpty else { break }
            result.append((task, free.removeFirst()))
        }
        return result
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = TreeLayout(size: proxy.size)
            ZStack(alignment: .topLeading) {
                scenery(layout)
                ForEach(hanging, id: \.task.id) { item in
                    apple(item.task, spot: item.spot, layout: layout)
                }
                caterpillar(layout)
                if carried != nil || eating != nil {
                    Image("Apple")
                        .resizable()
                        .frame(width: layout.apple.width, height: layout.apple.height)
                        .scaleEffect(swallowing ? 0.25 : 1.45)
                        .opacity(swallowing ? 0 : 1)
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 6)
                        .position(hand)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .coordinateSpace(name: "tree")
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            VStack(spacing: 10) {
                ChildProgressBar(steps: game.steps)
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
        .task {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
        .onChange(of: bubble) { _, new in
            if new == nil { Speaker.shared.stop() }
        }
        .sensoryFeedback(.success, trigger: fed)
        .sensoryFeedback(.impact(weight: .medium), trigger: unlockedFeedback)
    }

    // MARK: Pieces

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
        Image(carried != nil || eating != nil ? "CaterpillarOpen" : "Caterpillar")
            .resizable()
            .frame(width: layout.caterpillarSize.width, height: layout.caterpillarSize.height)
            .rotationEffect(.degrees(20), anchor: UnitPoint(x: 0.16, y: 0.6))
            .position(layout.caterpillarCenter)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func apple(_ task: TaskItem, spot: Int, layout: TreeLayout) -> some View {
        let isUnlocked = unlocked.contains(task.id)
        let isAway = carried == task.id || eating == task.id
        let home = layout.spot(spot)
        return Image("Apple")
            .resizable()
            .frame(width: layout.apple.width, height: layout.apple.height)
            .shadow(color: isUnlocked ? .white : .clear, radius: 4)
            .shadow(color: isUnlocked ? Color.habitoGreen.opacity(0.9) : .black.opacity(0.25), radius: isUnlocked ? 9 : 1.5, y: isUnlocked ? 0 : 1)
            .phaseAnimator([0.0, -7.0, 7.0]) { content, angle in
                // An unlocked apple keeps swinging on its stalk: "pick me".
                content.rotationEffect(.degrees(isUnlocked && !reduceMotion ? angle : 0), anchor: .top)
            } animation: { _ in .easeInOut(duration: 0.45) }
            .frame(width: max(56, layout.apple.width + 18), height: max(56, layout.apple.height + 18))
            .contentShape(Rectangle())
            .opacity(isAway ? 0 : 1)
            .onTapGesture { bubble = task.id }
            .gesture(drag(task, home: home, layout: layout), including: isUnlocked && eating == nil ? .all : .none)
            .popover(
                isPresented: Binding(get: { bubble == task.id }, set: { if !$0, bubble == task.id { bubble = nil } }),
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .top
            ) {
                TaskBubble(task: task, isUnlocked: isUnlocked) { unlock(task) }
            }
            .position(home)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Apple: \(task.title)")
            .accessibilityHint(isUnlocked ? "Drag it to the caterpillar to feed it" : "Opens the task")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Feed the caterpillar") {
                if isUnlocked, eating == nil { feed(task, mouth: layout.mouth) }
            }
    }

    private func drag(_ task: TaskItem, home: CGPoint, layout: TreeLayout) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("tree"))
            .onChanged { value in
                if carried == nil {
                    bubble = nil
                    carried = task.id
                }
                hand = value.location
            }
            .onEnded { value in
                let distance = hypot(value.location.x - layout.mouth.x, value.location.y - layout.mouth.y)
                if distance < 95 * layout.scale {
                    feed(task, mouth: layout.mouth)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        hand = home
                    } completion: {
                        if carried == task.id { carried = nil }
                    }
                }
            }
    }

    // MARK: Actions

    private func unlock(_ task: TaskItem) {
        unlocked.insert(task.id)
        unlockedFeedback += 1
        bubble = nil
        show("Now feed the apple to the caterpillar!")
    }

    private func feed(_ task: TaskItem, mouth: CGPoint) {
        eating = task.id
        carried = nil
        withAnimation(.easeIn(duration: 0.25)) {
            hand = mouth
            swallowing = true
        } completion: {
            Task { await tellServer(task) }
        }
    }

    private func tellServer(_ task: TaskItem) async {
        do {
            try await HabitoAPI.markDone(id: task.id)
            unlocked.remove(task.id)
            fed += 1
            await load()
        } catch {
            if (error as? APIError)?.isSignedOut == true { signOut(); return }
            switch (error as? APIError)?.code {
            case "not_due_today":
                show("This task isn’t for today any more.")
                await load()
            case "not_found":
                show("This task was removed.")
                await load()
            default:
                show(error.habitoMessage)
            }
        }
        eating = nil
        swallowing = false
    }

    private func load() async {
        do {
            let fresh = try await HabitoAPI.childToday()
            today = fresh
            game.record(fresh)
            let open = Set(fresh.tasks.filter { !$0.isDone }.map(\.id))
            unlocked.formIntersection(open)
            if let bubble, !open.contains(bubble) { self.bubble = nil }
        } catch {
            if (error as? APIError)?.isSignedOut == true { signOut(); return }
            if error.isCancellation { return }
            if today == nil { show(error.habitoMessage) }
        }
    }

    private func show(_ text: String) {
        messageID += 1
        let id = messageID
        message = text
        Task {
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

// MARK: - The bubble from an apple

private struct TaskBubble: View {
    let task: TaskItem
    let isUnlocked: Bool
    let onDone: () -> Void

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
                    .foregroundStyle(Color.habitoGreenDeep)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color.habitoGreen.opacity(0.16), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 14)

            if isUnlocked {
                Label("Now drag the apple to the caterpillar!", systemImage: "hand.draw.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.habitoGreenDeep)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            } else {
                Button(action: onDone) {
                    Text("I did it!")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.habitoGreen, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }
        }
        .padding(18)
        .frame(width: 300, alignment: .leading)
        .presentationCompactAdaptation(.popover)
    }
}

// MARK: - Progress bar

/// Seven perfect days turn the caterpillar into a butterfly.
struct ChildProgressBar: View {
    let steps: Int
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
                        Capsule()
                            .fill(index < steps ? Color.habitoGreen : Color.primary.opacity(0.16))
                            .frame(height: 8)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(steps) of \(goal) perfect days.")
    }
}

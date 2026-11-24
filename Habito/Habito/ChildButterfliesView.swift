//
//  ChildButterfliesView.swift
//  Habito
//
//  "My Collection": one card for every kind of butterfly, from common to legendary.
//  Kinds not found yet are grey with a padlock; found ones show the butterfly and its
//  name, and open it over the page. Below, the caterpillar dreams on its leaf.
//  The button at the top right leaves the family, after asking.
//

import SwiftUI
import KeychainSwift

struct ChildButterfliesView: View {
    @Environment(ChildGame.self) private var game
    @Binding var open: Int?
    @State private var confirmLeave = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 3)

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Text("My Collection")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Color(red: 0.06, green: 0.07, blue: 0.08))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 44)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .trailing) { leaveButton }
                    .padding(.top, 18)
                    .accessibilityAddTraits(.isHeader)
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(ButterflyKind.all.indices, id: \.self) { index in
                        card(index)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 260) // room to scroll the cards clear of the caterpillar
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(CollectionBackground())
        .alert("Leave this family?", isPresented: $confirmLeave) {
            Button("Cancel", role: .cancel) {}
            Button("Leave", role: .destructive) { leave() }
        } message: {
            Text("You will need the family code again to come back. Your butterflies stay on this phone.")
        }
    }

    /// Top right: leave the family, after asking.
    private var leaveButton: some View {
        Button { confirmLeave = true } label: {
            Image(systemName: "rectangle.portrait.and.arrow.right")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.habitoRed)
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.75), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Leave this family")
    }

    /// The butterflies the child has of kind `index`, newest first.
    private func found(_ index: Int) -> [Int] {
        (0..<game.butterflies).reversed().filter { $0 % ButterflyKind.all.count == index }
    }

    @ViewBuilder
    private func card(_ index: Int) -> some View {
        let kind = ButterflyKind.all[index]
        let numbers = found(index)
        if let newest = numbers.first {
            Button {
                withAnimation(.snappy) { open = newest }
            } label: {
                CollectionCard(kind: kind, count: numbers.count)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(kind.name), \(kind.rarity.rawValue)" + (numbers.count > 1 ? ", \(numbers.count) found" : ""))
        } else {
            CollectionCard(kind: kind, count: 0)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Not found yet, \(kind.rarity.rawValue)")
        }
    }

    private func leave() {
        KeychainSwift().delete(HabitoAPI.childTokenKey)
        ParentSession.refreshRoot()
    }
}

/// One card: the butterfly (or its locked shadow), its rarity, and its name underneath.
private struct CollectionCard: View {
    let kind: ButterflyKind
    /// How many of this kind the child has; 0 means locked.
    let count: Int

    private var locked: Bool { count == 0 }

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(white: 0.95))
                    if locked {
                        Image(kind.image)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(Color(white: 0.78))
                            .padding(8)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                    } else {
                        Image(kind.image)
                            .resizable()
                            .scaledToFit()
                            .padding(6)
                            .shadow(color: .black.opacity(0.14), radius: 3, y: 3)
                    }
                }
                .aspectRatio(1.25, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    if count > 1 {
                        Text("×\(count)")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.habitoGreenDeep, in: Capsule())
                            .padding(4)
                    }
                }
                Text(kind.rarity.rawValue)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(Color(white: 0.24))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(kind.rarity.color, in: Capsule())
            }
            .padding(7)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(white: 0.8), lineWidth: 2.5))

            Text(locked ? "???" : kind.name)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color(white: 0.22))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

extension ButterflyKind.Rarity {
    var color: Color {
        switch self {
        case .common: Color(red: 0.37, green: 0.78, blue: 0.32)
        case .rare: Color(red: 0.97, green: 0.80, blue: 0.27)
        case .epic: Color(red: 0.87, green: 0.58, blue: 0.87)
        case .legendary: Color(red: 0.53, green: 0.92, blue: 0.95)
        }
    }
}

/// Sky, a green hill, and the caterpillar on its bitten leaf, dreaming of a butterfly.
private struct CollectionBackground: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                Color.gardenSky
                Hill()
                    .fill(Color.gardenGrass)
                Hill()
                    .stroke(Color.gardenLeaf, lineWidth: 3)
                DreamingCaterpillar()
                    .frame(width: min(size.width * 0.78, 420))
                    .position(x: min(size.width * 0.78, 420) / 2 - size.width * 0.04,
                              y: size.height - min(size.width * 0.78, 420) * 0.47)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// The top of the grass: a low curve, higher on the right.
private struct Hill: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX - 4, y: rect.height * 0.66))
        path.addQuadCurve(to: CGPoint(x: rect.maxX + 4, y: rect.height * 0.58),
                          control: CGPoint(x: rect.width * 0.55, y: rect.height * 0.54))
        path.addLine(to: CGPoint(x: rect.maxX + 4, y: rect.maxY + 4))
        path.addLine(to: CGPoint(x: rect.minX - 4, y: rect.maxY + 4))
        path.closeSubpath()
        return path
    }
}

/// The leaf from the garden with a bite out of it, the caterpillar on it, and a thought bubble.
/// Laid out in the leaf picture's own 402 x 313.6 points.
private struct DreamingCaterpillar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let s = proxy.size.width / 402
            ZStack(alignment: .topLeading) {
                Image("LeafBitten")
                    .resizable()
                    .frame(width: 402 * s, height: 313.64 * s)
                Image("Caterpillar")
                    .resizable()
                    .frame(width: 312.83 * s, height: 129.95 * s)
                    .offset(x: 53.57 * s, y: 86.09 * s)
                ThoughtBubble()
                    .frame(width: 120 * s, height: 104 * s)
                    .offset(x: 120 * s, y: -38 * s)
                    .phaseAnimator(reduceMotion ? [0.0] : [0.0, 1.0]) { content, phase in
                        content.offset(y: -4 * s * phase)
                    } animation: { _ in .easeInOut(duration: 1.6) }
            }
        }
        .aspectRatio(402 / 313.64, contentMode: .fit)
    }
}

/// A white cloud with a butterfly in it, and two little bubbles leading down to the head.
private struct ThoughtBubble: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            ZStack(alignment: .topLeading) {
                Group {
                    Circle().frame(width: w * 0.42).offset(x: w * 0.1, y: h * 0.08)
                    Circle().frame(width: w * 0.5).offset(x: w * 0.38, y: 0)
                    Circle().frame(width: w * 0.38).offset(x: w * 0.6, y: h * 0.2)
                    Circle().frame(width: w * 0.44).offset(x: w * 0.02, y: h * 0.26)
                    Capsule().frame(width: w * 0.8, height: h * 0.36).offset(x: w * 0.12, y: h * 0.3)
                }
                .foregroundStyle(.white)
                Image("TabButterfly")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.gardenLeaf)
                    .frame(width: w * 0.42)
                    .offset(x: w * 0.3, y: h * 0.14)
                Circle().stroke(Color.gardenLeaf, lineWidth: 2).fill(.white)
                    .frame(width: w * 0.13).offset(x: w * 0.12, y: h * 0.72)
                Circle().stroke(Color.gardenLeaf, lineWidth: 2).fill(.white)
                    .frame(width: w * 0.08).offset(x: w * 0.02, y: h * 0.88)
            }
        }
    }
}

// MARK: - One butterfly, over the page

struct ButterflyDetailView: View {
    let number: Int
    let onClose: () -> Void
    @Environment(ChildGame.self) private var game
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The card grows in by itself; the blurred page behind only fades.
    @State private var shown = false

    var body: some View {
        let kind = ButterflyKind.of(number)
        let isFavourite = game.favourites.contains(number)
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color(red: 0.08, green: 0.18, blue: 0.24).opacity(0.22))
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                HStack {
                    roundButton("xmark", label: "Close", action: onClose)
                    Spacer()
                    roundButton(isFavourite ? "heart.fill" : "heart", label: isFavourite ? "Remove from favourites" : "Add to favourites",
                                tint: isFavourite ? Color.habitoRed : .primary) {
                        game.toggleFavourite(number)
                    }
                    .sensoryFeedback(.selection, trigger: isFavourite)
                }
                Text(kind.name)
                    .font(.system(size: 30, weight: .bold))
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
                Text(kind.latin)
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                Text(kind.rarity.rawValue)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(white: 0.24))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .background(kind.rarity.color, in: Capsule())
                    .padding(.top, 8)
                Image(kind.image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 300)
                    .shadow(color: Color(red: 0.08, green: 0.12, blue: 0.04).opacity(0.18), radius: 10, y: 12)
                    .padding(.vertical, 20)
                    .accessibilityHidden(true)
                Text(kind.about)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(red: 0.235, green: 0.235, blue: 0.263).opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
            }
            .padding(16)
            .padding(.bottom, 20)
            .frame(maxWidth: 362)
            .background(Color.habitoCard, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
            .shadow(color: Color(red: 0.04, green: 0.12, blue: 0.2).opacity(0.3), radius: 30, y: 24)
            .padding(.horizontal, 20)
            .scaleEffect(shown || reduceMotion ? 1 : 0.92)
        }
        .onAppear { withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { shown = true } }
    }

    private func roundButton(_ symbol: String, label: String, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(Color.primary.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

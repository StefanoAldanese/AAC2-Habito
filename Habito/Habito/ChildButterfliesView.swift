//
//  ChildButterfliesView.swift
//  Habito
//
//  The child's collection: one card per butterfly earned, newest first. Tapping
//  a card opens it over the page. "Leave this family" sits at the very end.
//

import SwiftUI
import KeychainSwift

struct ChildButterfliesView: View {
    @Environment(ChildGame.self) private var game
    @Binding var open: Int?
    @State private var confirmLeave = false

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    if game.butterflies == 0 {
                        empty
                    } else {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(Array((0..<game.butterflies).reversed()), id: \.self) { number in
                                card(number)
                            }
                        }
                    }
                    Button("Leave this family", role: .destructive) { confirmLeave = true }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.habitoRed)
                        .padding(.bottom, 8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(ChildSky())
            .navigationTitle("Butterflies")
            .confirmationDialog("Leave this family?", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("Leave", role: .destructive) { leave() }
            } message: {
                Text("You will need the family code again to come back. Your butterflies stay on this phone.")
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image("TabButterfly")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 44)
                .foregroundStyle(Color.habitoGreenDeep)
                .padding(.bottom, 6)
            Text("No butterflies yet").font(.headline)
            Text("Seven perfect days turn your caterpillar into a butterfly.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .habitoCard()
    }

    private func card(_ number: Int) -> some View {
        let kind = ButterflyKind.of(number)
        return Button {
            withAnimation(.snappy) { open = number }
        } label: {
            VStack(spacing: 2) {
                Image(kind.image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 118)
                    .shadow(color: Color(red: 0.08, green: 0.12, blue: 0.04).opacity(0.16), radius: 5, y: 5)
                    .padding(.bottom, 8)
                Text(kind.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(kind.latin)
                    .font(.footnote)
                    .italic()
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .habitoCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(kind.name), \(kind.latin)")
    }

    private func leave() {
        KeychainSwift().delete(HabitoAPI.childTokenKey)
        ParentSession.refreshRoot()
    }
}

/// The pale sky behind the Butterflies page, with two clouds.
struct ChildSky: View {
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.827, green: 0.922, blue: 0.984), location: 0),
                    .init(color: Color(red: 0.918, green: 0.965, blue: 0.996), location: 0.38),
                    .init(color: .white, location: 0.72),
                ],
                startPoint: .top, endPoint: .bottom
            )
            Image("SkyClouds")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 520)
        }
        .ignoresSafeArea()
    }
}

// MARK: - One butterfly, over the page

struct ButterflyDetailView: View {
    let number: Int
    let onClose: () -> Void
    @Environment(ChildGame.self) private var game

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
        }
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

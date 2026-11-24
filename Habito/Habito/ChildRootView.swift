//
//  ChildRootView.swift
//  Habito
//
//  What a joined child sees: a tab bar with Tree and Butterflies. The butterfly
//  pop-up and the butterfly reveal sit above the tab bar.
//

import SwiftUI

struct ChildRootView: View {
    enum Section { case tree, butterflies }

    @State private var game = ChildGame()
    @State private var section = Section.tree
    @State private var openButterfly: Int?

    var body: some View {
        TabView(selection: $section) {
            ChildTreeView()
                .tabItem { Label("Tree", systemImage: "tree.fill") }
                .tag(Section.tree)
            ChildButterfliesView(open: $openButterfly)
                .tabItem { Label { Text("Butterflies") } icon: { Image("TabButterfly") } }
                .tag(Section.butterflies)
        }
        .tint(.habitoGreenDeep)
        .overlay {
            if let number = openButterfly {
                ButterflyDetailView(number: number) {
                    withAnimation(.snappy) { openButterfly = nil }
                }
                // Fade only: scaling would shrink the blur and show the page at the edges.
                .transition(.opacity)
            }
        }
        .overlay {
            if let number = game.revealing {
                ButterflyRevealView(kind: ButterflyKind.of(number)) {
                    game.finishReveal()
                    section = .butterflies
                }
                .transition(.opacity)
            }
        }
        .environment(game)
        // Seven perfect days: let the full bar show for a moment, then the reveal.
        .task(id: "\(game.isReadyForButterfly)-\(game.butterflies)") {
            guard game.isReadyForButterfly else { return }
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            section = .tree
            openButterfly = nil
            game.startReveal()
        }
        // The garden is a picture with a light sky; it stays light in dark mode.
        .preferredColorScheme(.light)
    }
}

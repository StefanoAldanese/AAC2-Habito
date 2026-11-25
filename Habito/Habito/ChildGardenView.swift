//
//  ChildGardenView.swift
//  Habito
//
//  The Garden tab (beta): two flower beds on the hill, as drawn. For now it is
//  only the scene; nothing in it changes yet.
//

import SwiftUI

struct ChildGardenView: View {
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
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Garden with flower beds")
        .accessibilityIdentifier("garden")
    }
}

#Preview {
    ChildGardenView()
}

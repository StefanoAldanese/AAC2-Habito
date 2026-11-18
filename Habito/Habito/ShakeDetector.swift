//
//  ShakeDetector.swift
//  Habito
//
//  Passes the iPhone's shake gesture to SwiftUI: `.onShake { phase in ... }`.
//  The window is the first place UIKit offers motion events that no view took.
//

import SwiftUI
import UIKit

extension Notification.Name {
    static let habitoShakeBegan = Notification.Name("habitoShakeBegan")
    static let habitoShakeEnded = Notification.Name("habitoShakeEnded")
}

extension UIWindow {
    open override func motionBegan(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .habitoShakeBegan, object: nil)
        }
        super.motionBegan(motion, with: event)
    }

    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .habitoShakeEnded, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}

enum ShakePhase { case began, ended }

extension View {
    /// Runs `action` when the phone starts being shaken and again when the shake ends.
    func onShake(perform action: @escaping (ShakePhase) -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .habitoShakeBegan)) { _ in action(.began) }
            .onReceive(NotificationCenter.default.publisher(for: .habitoShakeEnded)) { _ in action(.ended) }
    }
}

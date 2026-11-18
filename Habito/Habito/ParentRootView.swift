//
//  ParentRootView.swift
//  Habito
//
//  What a logged-in parent sees: a tab bar with Home and History.
//

import SwiftUI
import Observation

/// What the parent screens share: the room code and the child's name,
/// both read from the server.
@Observable
final class ParentSession {
    var roomCode = ""
    var childName = ""

    func load() async {
        do {
            let parent = try await HabitoAPI.me()
            roomCode = parent.roomCode
            childName = parent.childName ?? ""
        } catch {
            handle(error)
        }
    }

    func logOut() async {
        await ParentAuth.logout()
        Self.refreshRoot()
    }

    /// Call when a request says the login is no longer valid.
    func expire() {
        ParentAuth.clearLocal()
        Self.refreshRoot()
    }

    /// Returns true when the error was dealt with here (the parent was signed out, or the
    /// request was simply cancelled), so the caller has nothing to show.
    @discardableResult
    func handle(_ error: Error) -> Bool {
        if (error as? APIError)?.isSignedOut == true {
            expire()
            return true
        }
        return error.isCancellation
    }

    /// Makes ContentView look at the Keychain again.
    static func refreshRoot() {
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: "authTrigger") + 1, forKey: "authTrigger")
    }
}

struct ParentRootView: View {
    @State private var session = ParentSession()

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            HistoryView()
                .tabItem { Label("History", systemImage: "calendar") }
        }
        .tint(.habitoGreenDeep)
        .environment(session)
    }
}

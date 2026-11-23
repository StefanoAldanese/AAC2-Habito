//
//  ChildGame.swift
//  Habito
//
//  The child's game, kept on this phone: the perfect days counted so far and
//  the butterflies they turned into. Seven perfect days make a butterfly. A day
//  without every task done simply does not count; it never takes progress away.
//

import Foundation
import Observation

@Observable
final class ChildGame {
    static let daysPerButterfly = 7

    /// Days on which every task was done, as the server writes them (2026-11-18).
    private(set) var perfectDays: Set<String>
    /// Butterflies the child has already seen appear.
    private(set) var butterflies: Int
    /// Butterflies the child marked with the heart.
    private(set) var favourites: Set<Int>
    /// The butterfly being revealed right now, by its number.
    private(set) var revealing: Int?

    private let defaults: UserDefaults

    private enum Key {
        static let perfectDays = "child.perfectDays"
        static let butterflies = "child.butterflies"
        static let favourites = "child.favourites"
        static let startingButterflies = "child.startingButterflies"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        perfectDays = Set(defaults.stringArray(forKey: Key.perfectDays) ?? [])
        butterflies = defaults.integer(forKey: Key.butterflies)
        favourites = Set((defaults.array(forKey: Key.favourites) as? [Int]) ?? [])
    }

    /// Perfect days that already turned into butterflies. Butterflies given at the start
    /// came with no days of their own.
    private var daysUsed: Int {
        max(0, butterflies - startingButterflies) * Self.daysPerButterfly
    }
    private var startingButterflies: Int { defaults.integer(forKey: Key.startingButterflies) }

    /// Steps filled on the progress bar: perfect days since the last butterfly, at most seven.
    var steps: Int {
        min(Self.daysPerButterfly, max(0, perfectDays.count - daysUsed))
    }

    var isReadyForButterfly: Bool { steps == Self.daysPerButterfly }

    /// Counts the day as perfect once it had tasks and all of them are done. Once counted,
    /// a day stays counted.
    func record(_ today: TodayList) {
        guard !today.tasks.isEmpty, today.tasks.allSatisfy(\.isDone) else { return }
        if perfectDays.insert(today.date).inserted {
            defaults.set(perfectDays.sorted(), forKey: Key.perfectDays)
        }
    }

    func startReveal() {
        guard isReadyForButterfly, revealing == nil else { return }
        revealing = butterflies
    }

    /// The child has seen the new butterfly: it joins the collection, the bar starts again.
    func finishReveal() {
        guard revealing != nil else { return }
        butterflies += 1
        revealing = nil
        defaults.set(butterflies, forKey: Key.butterflies)
    }

    // MARK: Presentation start

    /// For presenting: a newly joined child starts with this many butterflies...
    static let demoButterflies = 2
    /// ...and this many perfect days before today, so one perfect day today makes a
    /// butterfly. Set both to 0 to start every child from scratch.
    static let demoPerfectDays = 6

    /// A child just joined with the code: start the game over with the presentation
    /// start. Clears favourites and any ripe apples left from an earlier child.
    static func startNewChild(defaults: UserDefaults = .standard, today: Date = Date()) {
        let calendar = Calendar.current
        let days = (1...max(1, demoPerfectDays)).prefix(demoPerfectDays).compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: today).map(HabitoAPI.dayString)
        }
        defaults.set(days.sorted(), forKey: Key.perfectDays)
        // Earlier butterflies used up their seven days each; these six count toward the next.
        defaults.set(demoButterflies, forKey: Key.butterflies)
        defaults.set(demoButterflies, forKey: Key.startingButterflies)
        defaults.removeObject(forKey: Key.favourites)
        defaults.removeObject(forKey: "child.ripe.date")
        defaults.removeObject(forKey: "child.ripe.ids")
    }

    func toggleFavourite(_ number: Int) {
        if favourites.contains(number) { favourites.remove(number) } else { favourites.insert(number) }
        defaults.set(favourites.sorted(), forKey: Key.favourites)
    }
}

/// One kind of butterfly. The caterpillar turns into them in this order, then starts over.
struct ButterflyKind {
    let name: String
    let latin: String
    let about: String
    let image: String

    static let all: [ButterflyKind] = [
        ButterflyKind(name: "Monarch", latin: "Danaus plexippus",
                      about: "Monarchs fly thousands of kilometres every autumn, from Canada all the way to Mexico. Their caterpillars eat only milkweed, which makes them taste bad to birds.",
                      image: "Butterfly-monarch"),
        ButterflyKind(name: "Swallowtail", latin: "Papilio machaon",
                      about: "Swallowtails are named after the two little tails on their back wings, which look like the tail of a swallow. Their caterpillars are green with black bands and orange dots.",
                      image: "Butterfly-swallowtail"),
        ButterflyKind(name: "Blue Morpho", latin: "Morpho menelaus",
                      about: "The bright blue of a morpho is not paint: tiny scales on its wings bend the light. Underneath, its wings are brown, so it seems to vanish when it closes them.",
                      image: "Butterfly-morpho"),
        ButterflyKind(name: "Peacock", latin: "Aglais io",
                      about: "The big eye spots on a peacock butterfly scare birds away. When it is in danger, it flashes them open and even makes a hissing sound with its wings.",
                      image: "Butterfly-peacock"),
        ButterflyKind(name: "Brimstone", latin: "Gonepteryx rhamni",
                      about: "Brimstones are among the first butterflies of spring, and they can live for about a year, much longer than most butterflies. Their leaf-shaped wings hide them among leaves.",
                      image: "Butterfly-brimstone"),
        ButterflyKind(name: "Purple Emperor", latin: "Apatura iris",
                      about: "The purple emperor lives high in the treetops of old woods. Only the males shine purple, and only when the light hits their wings from the right angle.",
                      image: "Butterfly-emperor"),
    ]

    /// The kind of the child's butterfly number `number` (counting from 0).
    static func of(_ number: Int) -> ButterflyKind { all[number % all.count] }
}

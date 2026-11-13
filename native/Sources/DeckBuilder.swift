import Foundation

@MainActor
final class DeckBuilder {
    var faction = "realms"
    var leaderKey = ""
    var counts: [String: Int] = [:]
    var title = ""
    var editingIndex: Int?
    var scrollL: Float = 0, scrollR: Float = 0
    var limit: [String: Int]?
    var ownedLeaders: [String]?
    var careerMode: Bool { limit != nil }
    func cap(_ d: CardData) -> Int { min(d.count, limit?[d.key] ?? d.count) }
    func loadCareer() {
        let c = Career.shared
        faction = c.faction; leaderKey = c.leader; counts = c.deck; title = ""; editingIndex = nil
        limit = c.collection; ownedLeaders = c.leaders; scrollL = 0; scrollR = 0
    }
    var gd: GameData { GameData.shared }

    static let factionsOrder = ["realms", "nilfgaard", "monsters", "scoiatael", "skellige", "witcher_universe", "toussaint", "lyria_rivia",
                                "syndicate", "zerrikania", "redania", "velen", "wild_hunt", "novigrad", "ofir"]

    func leaders() -> [CardData] { gd.cards.values.filter { $0.isLeader && $0.faction == faction && (ownedLeaders?.contains($0.key) ?? true) }.sorted { $0.key < $1.key } }
    func collection() -> [CardData] {
        gd.cards.values.filter { d in
            if d.isLeader { return false }
            if let l = limit { return (l[d.key] ?? 0) > 0 }
            let parts = d.deck.split(separator: " ").map(String.init)
            if parts.first == "neutral" { return true }
            if d.isSpecial || d.isWeather { return parts.count == 1 || parts[1] == faction }
            return parts.first == faction
        }.sorted { a, b in
            func rank(_ d: CardData) -> Int { d.isLeader ? 0 : (d.isWeather ? 1 : (d.isSpecial ? 2 : 3)) }
            if rank(a) != rank(b) { return rank(a) < rank(b) }
            if a.strength != b.strength { return a.strength > b.strength }
            return a.name < b.name
        }
    }
    func load(_ d: DeckData, customIndex: Int?) {
        faction = d.faction; leaderKey = d.leader; title = d.title; editingIndex = customIndex; limit = nil; ownedLeaders = nil
        counts = [:]
        for (k, n) in d.cards { counts[k, default: 0] += n }
        scrollL = 0; scrollR = 0
    }
    func newDeck(_ f: String) {
        limit = nil; ownedLeaders = nil
        faction = f; leaderKey = leaders().first?.key ?? ""; counts = [:]; title = ""; editingIndex = nil; scrollL = 0; scrollR = 0
    }
    var deckCards: [CardData] { collection().filter { (counts[$0.key] ?? 0) > 0 } }
    var stats: (total: Int, units: Int, specials: Int, strength: Int, heroes: Int) {
        var t = 0, u = 0, s = 0, str = 0, h = 0
        for (k, n) in counts { guard let d = gd.cards[k] else { continue }
            t += n
            if d.isUnit { u += n; str += d.strength * n; if d.isHero { h += n } } else { s += n }
        }
        return (t, u, s, str, h)
    }
    var valid: Bool { let s = stats; return s.units >= 22 && s.specials <= 10 && !leaderKey.isEmpty }
    func add(_ d: CardData) {
        let n = counts[d.key] ?? 0
        guard n < cap(d) else { return }
        if (d.isSpecial || d.isWeather) && stats.specials >= 10 { return }
        counts[d.key] = n + 1
    }
    func remove(_ d: CardData) { let n = (counts[d.key] ?? 0) - 1; counts[d.key] = n > 0 ? n : nil }
    func asDeck() -> DeckData {
        DeckData(title: title.isEmpty ? L2("Moja talia", "My deck") + " — " + gd.factionName(faction) : title, description: "", leader: leaderKey, faction: faction,
                 cards: counts.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
    }

    static func loadCustom() -> [DeckData] {
        guard let arr = SaveStore.shared["customDecks"] as? [[String: Any]] else { return [] }
        return arr.compactMap { e in
            guard let f = e["faction"] as? String, let l = e["leader"] as? String, let cs = e["cards"] as? [[Any]] else { return nil }
            return DeckData(title: e["title"] as? String ?? "", description: "", leader: l, faction: f,
                            cards: cs.compactMap { p in (p.first as? String).map { ($0, (p.last as? NSNumber)?.intValue ?? 1) } })
        }
    }
    static func saveCustom(_ decks: [DeckData]) {
        let arr: [[String: Any]] = decks.map { ["title": $0.title, "faction": $0.faction, "leader": $0.leader, "cards": $0.cards.map { [$0.0, $0.1] }] }
        SaveStore.shared["customDecks"] = arr
    }
    func save() {
        if careerMode { let c = Career.shared; c.deck = counts.filter { $0.value > 0 }; c.leader = leaderKey; c.save(); return }
        var all = DeckBuilder.loadCustom()
        let d = asDeck()
        if let i = editingIndex, i < all.count { all[i] = d } else { all.append(d); editingIndex = all.count - 1 }
        DeckBuilder.saveCustom(all)
    }
}


// Deck-building model: available cards and leaders, deck limits, custom decks and the career deck.
import Foundation

/// Editable deck: faction, leader and card counts, with optional career card limits.
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
    /// Maximum copies of a card allowed in the deck.
    func cap(_ cardData: CardData) -> Int { min(cardData.count, limit?[cardData.key] ?? cardData.count) }
    /// Loads the career deck and the owned cards as limits.
    func loadCareer() {
        let career = Career.shared
        faction = career.faction; leaderKey = career.leader; counts = career.deck; title = ""; editingIndex = nil
        limit = career.collection; ownedLeaders = career.leaders; scrollL = 0; scrollR = 0
    }
    var gameData: GameData { GameData.shared }

    static let factionsOrder = ["realms", "nilfgaard", "monsters", "scoiatael", "skellige", "witcher_universe", "toussaint", "lyria_rivia",
                                "syndicate", "zerrikania", "redania", "velen", "wild_hunt", "novigrad", "ofir"]

    /// Leaders available for the current faction.
    func leaders() -> [CardData] { gameData.cards.values.filter { $0.isLeader && $0.faction == faction && (ownedLeaders?.contains($0.key) ?? true) }.sorted { $0.key < $1.key } }
    /// Cards that can be added for the current faction, sorted for display.
    func collection() -> [CardData] {
        gameData.cards.values.filter { cardData in
            if cardData.isLeader { return false }
            if let limits = limit { return (limits[cardData.key] ?? 0) > 0 }
            let parts = cardData.deck.split(separator: " ").map(String.init)
            if parts.first == "neutral" { return true }
            if cardData.isSpecial || cardData.isWeather { return parts.count == 1 || parts[1] == faction }
            return parts.first == faction
        }.sorted { first, second in
            /// Sort order: units first, then specials and weather.
            func rank(_ cardData: CardData) -> Int { cardData.isLeader ? 0 : (cardData.isWeather ? 1 : (cardData.isSpecial ? 2 : 3)) }
            if rank(first) != rank(second) { return rank(first) < rank(second) }
            if first.strength != second.strength { return first.strength > second.strength }
            return first.name < second.name
        }
    }
    /// Loads an existing deck for editing.
    func load(_ deck: DeckData, customIndex: Int?) {
        faction = deck.faction; leaderKey = deck.leader; title = deck.title; editingIndex = customIndex; limit = nil; ownedLeaders = nil
        counts = [:]
        for (key, copies) in deck.cards { counts[key, default: 0] += copies }
        scrollL = 0; scrollR = 0
    }
    /// Starts an empty deck for a faction.
    func newDeck(_ chosenFaction: String) {
        limit = nil; ownedLeaders = nil
        faction = chosenFaction; leaderKey = leaders().first?.key ?? ""; counts = [:]; title = ""; editingIndex = nil; scrollL = 0; scrollR = 0
    }
    var deckCards: [CardData] { collection().filter { (counts[$0.key] ?? 0) > 0 } }
    var stats: (total: Int, units: Int, specials: Int, strength: Int, heroes: Int) {
        var total = 0, units = 0, specials = 0, strength = 0, heroes = 0
        for (key, copies) in counts { guard let cardData = gameData.cards[key] else { continue }
            total += copies
            if cardData.isUnit { units += copies; strength += cardData.strength * copies; if cardData.isHero { heroes += copies } } else { specials += copies }
        }
        return (total, units, specials, strength, heroes)
    }
    var valid: Bool { let deckStats = stats; return deckStats.units >= 22 && deckStats.specials <= 10 && !leaderKey.isEmpty }
    /// Adds one copy of a card.
    func add(_ cardData: CardData) {
        let current = counts[cardData.key] ?? 0
        guard current < cap(cardData) else { return }
        if (cardData.isSpecial || cardData.isWeather) && stats.specials >= 10 { return }
        counts[cardData.key] = current + 1
    }
    /// Removes one copy of a card.
    func remove(_ cardData: CardData) { let remaining = (counts[cardData.key] ?? 0) - 1; counts[cardData.key] = remaining > 0 ? remaining : nil }
    /// Converts the builder state into a playable deck.
    func asDeck() -> DeckData {
        DeckData(title: title.isEmpty ? L("My deck") + " — " + gameData.factionName(faction) : title, description: "", leader: leaderKey, faction: faction,
                 cards: counts.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
    }

    /// Reads the player's custom decks from the save file.
    static func loadCustom() -> [DeckData] {
        guard let savedDecks = SaveStore.shared["customDecks"] as? [[String: Any]] else { return [] }
        return savedDecks.compactMap { entry in
            guard let savedFaction = entry["faction"] as? String, let savedLeader = entry["leader"] as? String, let cardList = entry["cards"] as? [[Any]] else { return nil }
            return DeckData(title: entry["title"] as? String ?? "", description: "", leader: savedLeader, faction: savedFaction,
                            cards: cardList.compactMap { pair in (pair.first as? String).map { ($0, (pair.last as? NSNumber)?.intValue ?? 1) } })
        }
    }
    /// Writes the player's custom decks to the save file.
    static func saveCustom(_ decks: [DeckData]) {
        let encoded: [[String: Any]] = decks.map { ["title": $0.title, "faction": $0.faction, "leader": $0.leader, "cards": $0.cards.map { [$0.0, $0.1] }] }
        SaveStore.shared["customDecks"] = encoded
    }
    /// Saves the edited deck (custom deck or career deck).
    func save() {
        if careerMode { let career = Career.shared; career.deck = counts.filter { $0.value > 0 }; career.leader = leaderKey; career.save(); return }
        var all = DeckBuilder.loadCustom()
        let deck = asDeck()
        if let i = editingIndex, i < all.count { all[i] = deck } else { all.append(deck); editingIndex = all.count - 1 }
        DeckBuilder.saveCustom(all)
    }
}


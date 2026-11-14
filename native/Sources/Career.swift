// Career mode: generated chapters, opponents, rewards and the player's collection.
import CoreGraphics
import Foundation




/// Deterministic xorshift random generator, so a career seed always produces the same chapters.
struct SeededRNG: RandomNumberGenerator {
    var s: UInt64
    init(_ seed: Int) { s = UInt64(bitPattern: Int64(seed)) &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> UInt64 { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s }
}

/// One career opponent: display name, portrait card, faction, card strength cap, hero count and boss flag.
struct CareerFight {
    let name: String
    let portrait: String
    let faction: String
    let cap: Int
    let heroes: Int
    let boss: Bool
}

/// Career mode state and generation.
@MainActor final class Career {
    static let shared = Career()
    var gameData: GameData { GameData.shared }

    var faction = ""
    var difficulty = 1
    var leaders: [String] = []
    var leader = ""
    var collection: [String: Int] = [:]
    var deck: [String: Int] = [:]
    var beaten: Set<Int> = []
    var seed = 0
    var active: Bool { !faction.isEmpty }

    static let difficultyNames: [String] = ["Easy", "Normal", "Hard"]
    var chapterCount: Int { [6, 8, 10][difficulty] }
    static let places: [String] = ["White Orchard", "Velen", "Novigrad", "Oxenfurt", "Vizima", "Kaer Morhen", "Skellige", "Toussaint", "Beauclair", "Cintra", "Mahakam", "Brokilon", "Kovir", "Vengerberg", "Zerrikania", "Ofir", "Crow's Perch", "Gors Velen", "Lyria", "Rivia", "Nilfgaard"]

    var rngBase: Int { seed &* 31 &+ difficulty }
    var cache: [Int: (title: String, fights: [CareerFight])] = [:]
    var cacheKey = ""
    /// Returns the title and the four fights of chapter `c` (cached per seed, difficulty and language).
    func chapter(_ chapter: Int) -> (title: String, fights: [CareerFight]) {
        let key = "\(seed)|\(difficulty)|\(gameData.language)"
        if key != cacheKey { cache = [:]; cacheKey = key }
        if let v = cache[chapter] { return v }
        let v = makeChapter(chapter); cache[chapter] = v; return v
    }
    /// Generates a chapter: three regular opponents and a boss whose strength grows with progress.
    func makeChapter(_ chapter: Int) -> (title: String, fights: [CareerFight]) {
        var rng = SeededRNG(rngBase &+ chapter &* 1_000_003)
        var orng = SeededRNG(rngBase)
        let order = Career.places.indices.shuffled(using: &orng)
        let place = Career.places[order[chapter % order.count]]
        let last = chapter == chapterCount - 1
        let d = difficulty - 1
        let progress = Float(chapter) / Float(max(1, chapterCount - 1))
        let base = Int((progress * 6).rounded()) + (d < 0 ? -1 : d)
        let h = max(0, Int((progress * 3).rounded()) + d - 1)
        var fights: [CareerFight] = []
        for k in 0..<4 {
            let boss = k == 3
            let fac = DeckBuilder.factionsOrder.randomElement(using: &rng) ?? "realms"
            var cap = boss ? base + 2 : base + (k == 2 ? 1 : 0)
            if cap >= 11 || (boss && last) { cap = 99 }
            let heroes = boss ? min(7, h + 1 + (last ? 2 : 0)) : max(0, h - 1 + (k == 2 ? 1 : 0))
            let tmp = CareerFight(name: "", portrait: "", faction: fac, cap: max(2, cap), heroes: heroes, boss: boss)
            let dk = opponentDeck(index(chapter, k), tmp)
            let pk: String = boss ? dk.leader : (dk.cards.compactMap { gameData.cards[$0.0] }.filter { $0.isUnit }.max { $0.strength < $1.strength }?.key ?? dk.leader)
            let nm = gameData.cards[pk].map { gameData.cardName($0) } ?? fac
            fights.append(CareerFight(name: nm, portrait: pk, faction: fac, cap: tmp.cap, heroes: heroes, boss: boss))
        }
        return (L(place), fights)
    }
    /// Global index of fight `k` in chapter `c`.
    func index(_ chapter: Int, _ slot: Int) -> Int { chapter * 4 + slot }
    /// Whether fight `k` of chapter `c` can be played.
    func unlocked(_ chapter: Int, _ slot: Int) -> Bool {
        if chapter > 0 && !beaten.contains(index(chapter - 1, 3)) { return false }
        return slot < 3 || (0..<3).allSatisfy { beaten.contains(index(chapter, $0)) }
    }
    var currentChapter: Int { (0..<chapterCount).first { !beaten.contains(index($0, 3)) } ?? chapterCount - 1 }
    var finished: Bool { beaten.contains(index(chapterCount - 1, 3)) }
    var totalFights: Int { chapterCount * 4 }

    init() { load() }
    /// Loads the career from the save file.
    func load() {
        faction = ""; leaders = []; leader = ""; collection = [:]; deck = [:]; beaten = []
        guard let o = SaveStore.shared["career"] as? [String: Any] else { return }
        faction = o["faction"] as? String ?? ""
        leaders = o["leaders"] as? [String] ?? []
        leader = o["leader"] as? String ?? leaders.first ?? ""
        collection = (o["collection"] as? [String: Int]) ?? [:]
        deck = (o["deck"] as? [String: Int]) ?? [:]
        beaten = Set((o["beaten"] as? [Int]) ?? [])
        seed = o["seed"] as? Int ?? 0
        difficulty = o["difficulty"] as? Int ?? 1
    }
    /// Stores the career in the save file.
    func save() {
        SaveStore.shared["career"] = active ? ["faction": faction, "leaders": leaders, "leader": leader, "collection": collection,
                                               "deck": deck, "beaten": Array(beaten).sorted(), "seed": seed, "difficulty": difficulty] as [String: Any] : nil
    }
    /// Abandons the current career.
    func reset() { faction = ""; leaders = []; leader = ""; collection = [:]; deck = [:]; beaten = []; save() }

    /// All cards of a faction that can appear in decks.
    func pool(_ faction: String) -> [CardData] { let b = DeckBuilder(); b.faction = faction; return b.collection() }

    /// Starts a new career: random seed, first leader and a starter deck of weak units.
    func start(_ f: String, difficulty level: Int = 1) {
        faction = f; difficulty = level; beaten = []; seed = Int.random(in: 1...999_999)
        let p = pool(f)
        let leaderCards = gameData.cards.values.filter { $0.isLeader && $0.faction == f }.sorted { $0.key < $1.key }
        leaders = leaderCards.first.map { [$0.key] } ?? []; leader = leaders.first ?? ""
        var cap = 6 - (difficulty - 1), units: [CardData] = []
        while true {
            units = p.filter { $0.isUnit && !$0.isHero && $0.strength <= cap && !$0.abilities.contains("spy") }
            if units.reduce(0, { $0 + $1.count }) >= 24 || cap > 12 { break }
            cap += 1
        }
        collection = [:]
        var n = 0
        for u in units.sorted(by: { $0.strength > $1.strength }) where n < 22 { let c = min(u.count, 22 - n); collection[u.key] = c; n += c }
        for w in p.filter({ $0.isWeather }).prefix(2) { collection[w.key] = 1 }
        for k in ["spe_horn", "spe_decoy"] where gameData.cards[k] != nil { collection[k] = 1 }
        deck = collection
        save()
    }
    var playerDeck: DeckData {
        DeckData(title: L("Career deck"), description: "", leader: leader, faction: faction,
                 cards: deck.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
    }
    var deckUnits: Int { deck.reduce(0) { $0 + ((gameData.cards[$1.key]?.isUnit ?? false) ? $1.value : 0) } }

    /// Builds the opponent's deck for a fight (premade deck for the final boss).
    func opponentDeck(_ fightIndex: Int, _ f: CareerFight) -> DeckData {
        if f.boss && f.cap >= 99 {
            var r = SeededRNG(rngBase &+ fightIndex)
            let pre = gameData.decks.filter { $0.faction == f.faction }
            if let d = pre.randomElement(using: &r) { return d }
        }
        var rng = SeededRNG(rngBase &+ fightIndex &* 7919)
        let p = pool(f.faction)
        var cap = f.cap
        while cap < 15 && p.filter({ $0.isUnit && !$0.isHero && $0.strength <= cap }).reduce(0, { $0 + $1.count }) < 18 { cap += 1 }
        let pool = p.filter { $0.isUnit && !$0.isHero && $0.strength <= cap && (f.boss || !$0.abilities.contains("spy")) }.shuffled(using: &rng)
        let units = f.boss ? pool : pool.sorted { $0.strength < $1.strength }
        let heroes = p.filter { $0.isUnit && $0.isHero }.shuffled(using: &rng).prefix(f.heroes)
        let specials = p.filter { !$0.isUnit }.shuffled(using: &rng).prefix(min(4, f.heroes))
        var cards: [(String, Int)] = heroes.map { ($0.key, 1) }
        var n = cards.count
        for u in units where n < 20 { let c = min(u.count, 20 - n); cards.append((u.key, c)); n += c }
        cards += specials.map { ($0.key, 1) }
        let leaderCards = gameData.cards.values.filter { $0.isLeader && $0.faction == f.faction }.sorted { $0.key < $1.key }
        let lead = f.boss ? (leaderCards.last ?? leaderCards.first) : leaderCards.first
        return DeckData(title: f.name, description: "", leader: lead?.key ?? "", faction: f.faction, cards: cards)
    }

    /// Three cards offered as a reward after winning a fight.
    func rewardOptions(_ fightIndex: Int) -> [String] {
        let c = fightIndex / 4, boss = fightIndex % 4 == 3
        let progress = Float(c) / Float(max(1, chapterCount - 1))
        let cap = progress > 0.8 ? 99 : 5 + Int(progress * 7)
        var rng = SeededRNG(seed &+ fightIndex * 104_729 &+ beaten.count)
        let p = pool(faction).filter { (collection[$0.key] ?? 0) < $0.count }
        var cand = boss ? p.filter { $0.isUnit && $0.isHero } : p.filter { !$0.isHero && (!$0.isUnit || $0.strength <= cap) }
        if cand.count < 3 { cand = p }
        cand.sort { ($0.isUnit ? $0.strength : 3) > ($1.isUnit ? $1.strength : 3) }
        let top = Array(cand.prefix(max(6, cand.count / 2))).shuffled(using: &rng)
        return Array(top.prefix(3)).map { $0.key }
    }
    /// Marks a fight as won; bosses also unlock a new leader, whose key is returned.
    func win(_ fightIndex: Int) -> String? {
        beaten.insert(fightIndex)
        var newLeader: String?
        if fightIndex % 4 == 3 {
            let leaderCards = gameData.cards.values.filter { $0.isLeader && $0.faction == faction }.sorted { $0.key < $1.key }
            if let l = leaderCards.first(where: { !leaders.contains($0.key) }) { leaders.append(l.key); newLeader = l.key }
        }
        save()
        return newLeader
    }
    /// Adds a reward card to the collection and, if possible, to the deck.
    func take(_ key: String) {
        collection[key, default: 0] += 1
        let specials = deck.reduce(0) { $0 + ((gameData.cards[$1.key]?.isUnit ?? true) ? 0 : $1.value) }
        if gameData.cards[key]?.isUnit == true || specials < 10 { deck[key, default: 0] += 1 }
        save()
    }
}

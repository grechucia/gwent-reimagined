import CoreGraphics
import Foundation


@MainActor final class SaveStore {
    static let shared = SaveStore()
    private(set) var data: [String: Any] = [:]
    static let fileName = "GwentReimagined-save.json"

    static let testDir = ProcessInfo.processInfo.environment["GWENT_SAVEDIR"]
    var dirPath: String? { SaveStore.testDir ?? UserDefaults.standard.string(forKey: "saveDir") }
    var chosen: Bool { dirPath != nil }
    var displayPath: String {
        if ProcessInfo.processInfo.environment["GWENT_SHOT"] == "1" { return "~/Library/Application Support/GwentReimagined" }
        #if os(iOS)
        if dir.path == SaveStore.localDir.path { return L2("Pliki → Na moim iPhonie → GwentReimagined", "Files → On My iPhone → GwentReimagined") }
        return dir.lastPathComponent
        #else
        return (dir.path as NSString).abbreviatingWithTildeInPath
        #endif
    }
    var dir: URL { URL(fileURLWithPath: dirPath ?? SaveStore.localDir.path) }
    var fileURL: URL { dir.appendingPathComponent(SaveStore.fileName) }

    static var localDir: URL {
        #if os(macOS)
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("GwentReimagined")
        #else
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #endif
    }
    static var iCloudDir: URL? {
        #if os(iOS)
        return nil
        #endif
        let docs = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        return FileManager.default.fileExists(atPath: docs.path) ? docs.appendingPathComponent("GwentReimagined") : nil
    }

    init() {
        load()
        if data["customDecks"] == nil, let a = UserDefaults.standard.array(forKey: "customDecks") { data["customDecks"] = a }
        if data["favoriteDeck"] == nil, let f = UserDefaults.standard.string(forKey: "favoriteDeck") { data["favoriteDeck"] = f }
    }
    func load() {
        if let d = try? Data(contentsOf: fileURL), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { data = o }
    }
    func save() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let d = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: fileURL, options: .atomic) }
    }
    subscript(_ key: String) -> Any? {
        get { data[key] }
        set { data[key] = newValue; save() }
    }
    func choose(_ url: URL) {
        let current = data
        if SaveStore.testDir != nil { return }
        UserDefaults.standard.set(url.path, forKey: "saveDir")
        if FileManager.default.fileExists(atPath: fileURL.path) { load() } else { data = current; save() }
    }
}


struct SeededRNG: RandomNumberGenerator {
    var s: UInt64
    init(_ seed: Int) { s = UInt64(bitPattern: Int64(seed)) &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> UInt64 { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s }
}

struct CareerFight {
    let name: String
    let portrait: String
    let faction: String
    let cap: Int
    let heroes: Int
    let boss: Bool
}

@MainActor final class Career {
    static let shared = Career()
    var gd: GameData { GameData.shared }

    var faction = ""
    var difficulty = 1
    var leaders: [String] = []
    var leader = ""
    var collection: [String: Int] = [:]
    var deck: [String: Int] = [:]
    var beaten: Set<Int> = []
    var seed = 0
    var active: Bool { !faction.isEmpty }

    static let difficultyNames: [(String, String)] = [("Łatwy", "Easy"), ("Normalny", "Normal"), ("Trudny", "Hard")]
    var chapterCount: Int { [6, 8, 10][difficulty] }
    static let places: [(String, String)] = [
        ("Biały Sad", "White Orchard"), ("Velen", "Velen"), ("Novigrad", "Novigrad"), ("Oxenfurt", "Oxenfurt"), ("Wyzima", "Vizima"),
        ("Kaer Morhen", "Kaer Morhen"), ("Skellige", "Skellige"), ("Toussaint", "Toussaint"), ("Beauclair", "Beauclair"), ("Cintra", "Cintra"),
        ("Mahakam", "Mahakam"), ("Brokilon", "Brokilon"), ("Kovir", "Kovir"), ("Vengerberg", "Vengerberg"), ("Zerrikania", "Zerrikania"),
        ("Ofir", "Ofir"), ("Mirt", "Crow's Perch"), ("Gors Velen", "Gors Velen"), ("Lyria", "Lyria"), ("Rivia", "Rivia"), ("Nilfgaard", "Nilfgaard")]

    private var rngBase: Int { seed &* 31 &+ difficulty }
    private var cache: [Int: (title: String, fights: [CareerFight])] = [:]
    private var cacheKey = ""
    func chapter(_ c: Int) -> (title: String, fights: [CareerFight]) {
        let key = "\(seed)|\(difficulty)|\(gd.language)"
        if key != cacheKey { cache = [:]; cacheKey = key }
        if let v = cache[c] { return v }
        let v = makeChapter(c); cache[c] = v; return v
    }
    private func makeChapter(_ c: Int) -> (title: String, fights: [CareerFight]) {
        var rng = SeededRNG(rngBase &+ c &* 1_000_003)
        var orng = SeededRNG(rngBase)
        let order = Career.places.indices.shuffled(using: &orng)
        let place = Career.places[order[c % order.count]]
        let last = c == chapterCount - 1
        let d = difficulty - 1
        let progress = Float(c) / Float(max(1, chapterCount - 1))
        let base = 2 + Int((progress * 7).rounded()) + (d < 0 ? -2 : d)
        let h = max(0, Int((progress * 4).rounded()) + d - 1)
        var fights: [CareerFight] = []
        for k in 0..<4 {
            let boss = k == 3
            let fac = DeckBuilder.factionsOrder.randomElement(using: &rng) ?? "realms"
            var cap = boss ? base + 2 : base + (k == 2 ? 1 : 0)
            if cap >= 11 || (boss && last) { cap = 99 }
            let heroes = boss ? min(7, h + 1 + (last ? 2 : 0)) : max(0, h - 1 + (k == 2 ? 1 : 0))
            let tmp = CareerFight(name: "", portrait: "", faction: fac, cap: max(2, cap), heroes: heroes, boss: boss)
            let dk = opponentDeck(index(c, k), tmp)
            let pk: String = boss ? dk.leader : (dk.cards.compactMap { gd.cards[$0.0] }.filter { $0.isUnit }.max { $0.strength < $1.strength }?.key ?? dk.leader)
            let nm = gd.cards[pk].map { gd.cardName($0) } ?? fac
            fights.append(CareerFight(name: nm, portrait: pk, faction: fac, cap: tmp.cap, heroes: heroes, boss: boss))
        }
        return (L2(place.0, place.1), fights)
    }
    func index(_ c: Int, _ k: Int) -> Int { c * 4 + k }
    func unlocked(_ c: Int, _ k: Int) -> Bool {
        if c > 0 && !beaten.contains(index(c - 1, 3)) { return false }
        return k < 3 || (0..<3).allSatisfy { beaten.contains(index(c, $0)) }
    }
    var currentChapter: Int { (0..<chapterCount).first { !beaten.contains(index($0, 3)) } ?? chapterCount - 1 }
    var finished: Bool { beaten.contains(index(chapterCount - 1, 3)) }
    var totalFights: Int { chapterCount * 4 }

    init() { load() }
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
    func save() {
        SaveStore.shared["career"] = active ? ["faction": faction, "leaders": leaders, "leader": leader, "collection": collection,
                                               "deck": deck, "beaten": Array(beaten).sorted(), "seed": seed, "difficulty": difficulty] as [String: Any] : nil
    }
    func reset() { faction = ""; leaders = []; leader = ""; collection = [:]; deck = [:]; beaten = []; save() }

    func pool(_ f: String) -> [CardData] { let b = DeckBuilder(); b.faction = f; return b.collection() }

    func start(_ f: String, difficulty dif: Int = 1) {
        faction = f; difficulty = dif; beaten = []; seed = Int.random(in: 1...999_999)
        let p = pool(f)
        let ls = gd.cards.values.filter { $0.isLeader && $0.faction == f }.sorted { $0.key < $1.key }
        leaders = ls.first.map { [$0.key] } ?? []; leader = leaders.first ?? ""
        var cap = 4 - (difficulty - 1), units: [CardData] = []
        while true {
            units = p.filter { $0.isUnit && !$0.isHero && $0.strength <= cap && !$0.abilities.contains("spy") }
            if units.reduce(0, { $0 + $1.count }) >= 24 || cap > 12 { break }
            cap += 1
        }
        collection = [:]
        var n = 0
        for u in units.sorted(by: { $0.strength < $1.strength }) where n < 25 { let c = min(u.count, 25 - n); collection[u.key] = c; n += c }
        for w in p.filter({ $0.isWeather }).prefix(2) { collection[w.key] = 1 }
        deck = collection
        save()
    }
    var playerDeck: DeckData {
        DeckData(title: L2("Talia kariery", "Career deck"), description: "", leader: leader, faction: faction,
                 cards: deck.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
    }
    var deckUnits: Int { deck.reduce(0) { $0 + ((gd.cards[$1.key]?.isUnit ?? false) ? $1.value : 0) } }

    func opponentDeck(_ fi: Int, _ f: CareerFight) -> DeckData {
        if f.boss && f.cap >= 99 {
            var r = SeededRNG(rngBase &+ fi)
            let pre = gd.decks.filter { $0.faction == f.faction }
            if let d = pre.randomElement(using: &r) { return d }
        }
        var rng = SeededRNG(rngBase &+ fi &* 7919)
        let p = pool(f.faction)
        var cap = f.cap
        while cap < 15 && p.filter({ $0.isUnit && !$0.isHero && $0.strength <= cap }).reduce(0, { $0 + $1.count }) < 22 { cap += 1 }
        let units = p.filter { $0.isUnit && !$0.isHero && $0.strength <= cap }.shuffled(using: &rng)
        let heroes = p.filter { $0.isUnit && $0.isHero }.shuffled(using: &rng).prefix(f.heroes)
        let specials = p.filter { !$0.isUnit }.shuffled(using: &rng).prefix(min(6, 1 + f.heroes))
        var cards: [(String, Int)] = heroes.map { ($0.key, 1) }
        var n = cards.count
        for u in units where n < 25 { let c = min(u.count, 25 - n); cards.append((u.key, c)); n += c }
        cards += specials.map { ($0.key, 1) }
        let ls = gd.cards.values.filter { $0.isLeader && $0.faction == f.faction }.sorted { $0.key < $1.key }
        let lead = f.boss ? (ls.last ?? ls.first) : ls.first
        return DeckData(title: f.name, description: "", leader: lead?.key ?? "", faction: f.faction, cards: cards)
    }

    func rewardOptions(_ fi: Int) -> [String] {
        let c = fi / 4, boss = fi % 4 == 3
        let progress = Float(c) / Float(max(1, chapterCount - 1))
        let cap = progress > 0.8 ? 99 : 5 + Int(progress * 7)
        var rng = SeededRNG(seed &+ fi * 104_729 &+ beaten.count)
        let p = pool(faction).filter { (collection[$0.key] ?? 0) < $0.count }
        var cand = boss ? p.filter { $0.isUnit && $0.isHero } : p.filter { !$0.isHero && (!$0.isUnit || $0.strength <= cap) }
        if cand.count < 3 { cand = p }
        cand.sort { ($0.isUnit ? $0.strength : 3) > ($1.isUnit ? $1.strength : 3) }
        let top = Array(cand.prefix(max(6, cand.count / 2))).shuffled(using: &rng)
        return Array(top.prefix(3)).map { $0.key }
    }
    func win(_ fi: Int) -> String? {
        beaten.insert(fi)
        var newLeader: String?
        if fi % 4 == 3 {
            let ls = gd.cards.values.filter { $0.isLeader && $0.faction == faction }.sorted { $0.key < $1.key }
            if let l = ls.first(where: { !leaders.contains($0.key) }) { leaders.append(l.key); newLeader = l.key }
        }
        save()
        return newLeader
    }
    func take(_ key: String) {
        collection[key, default: 0] += 1
        let specials = deck.reduce(0) { $0 + ((gd.cards[$1.key]?.isUnit ?? true) ? 0 : $1.value) }
        if gd.cards[key]?.isUnit == true || specials < 10 { deck[key, default: 0] += 1 }
        save()
    }
}

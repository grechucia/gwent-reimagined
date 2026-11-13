import Foundation

enum RowType: Int, CaseIterable { case close = 0, ranged = 1, siege = 2
    static func from(_ s: String) -> RowType? { ["close": .close, "ranged": .ranged, "siege": .siege][s] }
}

@MainActor
final class Card {
    private static var nextId = 1
    let id: Int
    private(set) var data: CardData
    weak var owner: Player?
    var power = 0
    var locked = false
    var heroOverride: Bool?
    var baseOverride: Int?
    var setTo: Int?
    var tempStrength: Int?
    var multiplier = 1
    var bonus = 0
    var siegeMult = 1
    var immortalRounds = 0
    var keepNextRound = false
    var playedTurn = -1
    var revertTo: String?
    var diedRound = -1
    var pos = SIMD2<Float>(0, 0)
    var hasPos = false
    var lift: Float = 0
    var flash: Float = 0
    init(_ d: CardData, owner: Player?) { id = Card.nextId; Card.nextId += 1; data = d; self.owner = owner; power = d.strength }
    var key: String { data.key }
    var basePower: Int { baseOverride ?? data.strength }
    var hero: Bool { heroOverride ?? data.isHero }
    func has(_ a: String) -> Bool { data.abilities.contains(a) }
    var activeAbilities: [String] { locked ? [] : data.abilities }
    func act(_ a: String) -> Bool { !locked && data.abilities.contains(a) }
    var groupKey: String { data.target.isEmpty ? data.key : data.target }
    var school: String? { data.abilities.last.flatMap { $0.hasPrefix("witcher_") ? $0 : nil } }
    var isUnit: Bool { data.isUnit }
    var allowedRows: [RowType] {
        switch data.row {
        case "close": return [.close]
        case "ranged": return [.ranged]
        case "siege": return [.siege]
        case "agile", "agile_cr", "agile_close_ranged": return [.close, .ranged]
        case "agile_cs", "agile_close_siege": return [.close, .siege]
        case "agile_rs", "agile_ranged_siege": return [.ranged, .siege]
        case "agile_crs", "agile_close_ranged_siege": return [.close, .ranged, .siege]
        default: return [.close]
        }
    }
    var specialKind: String? { (data.isSpecial || data.isWeather) ? data.abilities.first : nil }
    func transform(into d: CardData) { data = d; baseOverride = nil; setTo = nil; flash = 1 }
    func resetRoundState() { tempStrength = nil }
}

@MainActor
final class Row {
    var cards: [Card] = []
    var specials: [Card] = []
    var total = 0
    var lock: Card?
    var curse: Card?
    var ambush: Card?
    var door = false
    var leaderHorn = false
    var factionMorale = 0
    var shielded: Bool { specials.contains { $0.specialKind?.hasPrefix("shield") == true } }
    var hornCount: Int { specials.filter { $0.specialKind == "horn" }.count + cards.filter { $0.act("horn") }.count + (leaderHorn ? 1 : 0) }
}

@MainActor
final class Player {
    let isAI: Bool
    let deckData: DeckData
    var faction: String { deckData.faction }
    var leader: Card
    var deck: [Card] = [], hand: [Card] = [], grave: [Card] = []
    let rows = [Row(), Row(), Row()]
    var weather: [Set<String>] = [[], [], []]
    var gems = 2
    var passed = false
    var total = 0
    weak var opponent: Player!
    var leaderUses = 1
    var factionUsedGame = false
    var factionUsedRound = false
    var monstersUsed = false
    var drawOpponentLeft = 3
    var sigismundSaved = false
    var halfWeather = false
    var aamadBonus = 0
    var forcedCard: Card?
    var comradeUsedRound = false
    var lostUnitThisTurn = false
    var fleetDrawsRound = 0
    var fleetPending = 0
    var lastRoundWon = false
    init(deck: DeckData, isAI: Bool) {
        self.isAI = isAI; deckData = deck
        let gd = GameData.shared!
        leader = Card(gd.cards[deck.leader]!, owner: nil)
        leader.owner = self
        if leader.data.abilities.last == "holger_blakhand" { leaderUses = 2 }
        for (k, n) in deck.cards { if let d = gd.cards[k] { for _ in 0..<max(1, n) { self.deck.append(Card(d, owner: self)) } } }
        self.deck.shuffle()
    }
    var rowCards: [Card] { rows.flatMap { $0.cards } }
    func row(_ r: RowType) -> Row { rows[r.rawValue] }
    func rowOf(_ c: Card) -> RowType? { for r in RowType.allCases where rows[r.rawValue].cards.contains(where: { $0 === c }) { return r }; return nil }
    var leaderAbility: String { leader.data.abilities.last ?? "" }
}

enum GameEvent { case notify(String, icon: String?); case sound(String); case flash(Card); case anim(Card, String); case burn(Card); case coin(Bool) }

struct Choice {
    enum Kind {
        case cards([Card], min: Int, max: Int)
        case rows([(Player, RowType)])
        case options([String])
        case reveal([Card])
    }
    let player: Player
    let title: String
    let kind: Kind
    let canCancel: Bool
    let ai: () -> [Int]
}

@MainActor
final class Game {
    let me: Player, op: Player
    var weatherCards: [Card] = []
    var current: Player
    var round = 1
    var turn = 0
    var history: [(me: Int, op: Int, winner: Player?)] = []
    enum Phase { case redraw, play, roundEnd, over }
    var phase: Phase = .redraw
    var events: [GameEvent] = []
    var choice: Choice?
    private var choiceCont: CheckedContinuation<[Int]?, Never>?
    var busy = false
    var redrawsLeft = 2
    var lastRoundWinner: Player?
    var winner: Player?
    var autoHuman = false
    var aiPlayer: Player?
    var spyMult: Double = 1
    var whorshipMult = 1
    var medicPicks = 1
    var navigatorShield = false
    var maxDoors = 1
    var gd: GameData { GameData.shared }

    init(myDeck: DeckData, opDeck: DeckData) {
        me = Player(deck: myDeck, isAI: false)
        op = Player(deck: opDeck, isAI: true)
        me.opponent = op; op.opponent = me
        current = me
        for p in [me, op] { applyPassiveLeader(p) }
        for p in [me, op] {
            if p.faction == "syndicate" { summonToBoard(p, key: "sy_sigi_reuven") }
            if p.leaderAbility == "ofir_aamad_crown" { summonToBoard(p, key: "ofir_ofieri_prince") }
            let hand = 10 + (p.faction == "wild_hunt" ? 1 : 0) + (p.leaderAbility == "francesca_daisy" ? 3 : 0)
            draw(p, hand, silent: true)
        }
        redrawsLeft = redrawCount(me)
        aiRedraw(op)
        recalc()
    }
    private func redrawCount(_ p: Player) -> Int { 2 + (p.faction == "toussaint" ? 1 : 0) + (p.faction == "novigrad" ? 1 : 0) }
    private func applyPassiveLeader(_ p: Player) {
        switch p.leaderAbility {
        case "eredin_treacherous": spyMult *= 2
        case "vilgefortz_magician_kovir": spyMult *= 0.5
        case "zerrikanterment": whorshipMult = 2
        case "meve_white_queen": medicPicks = 2
        case "imlerith_general": navigatorShield = true
        case "caranthir_navigator": maxDoors = 2
        default: break
        }
    }
    private func summonToBoard(_ p: Player, key: String) {
        let c: Card
        if let i = p.deck.firstIndex(where: { $0.key == key }) { c = p.deck.remove(at: i) }
        else if let d = gd.cards[key] { c = Card(d, owner: p) } else { return }
        c.owner = p
        p.row(c.allowedRows.first ?? .close).cards.append(c)
    }

    var showChoices = false
    func choose(_ c: Choice) async -> [Int]? {
        if autoHuman && showChoices && !c.player.isAI {
            choice = c
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            choice = nil
            return c.ai()
        }
        if c.player.isAI || autoHuman { return c.ai() }
        choice = c
        return await withCheckedContinuation { cont in choiceCont = cont }
    }
    func resolveChoice(_ r: [Int]?) {
        let k = choiceCont
        choice = nil; choiceCont = nil
        k?.resume(returning: r)
    }
    private func pickCards(_ p: Player, _ title: String, _ cards: [Card], min: Int = 1, max: Int = 1, cancel: Bool = false,
                           ai: @escaping ([Card]) -> [Card]) async -> [Card] {
        guard !cards.isEmpty else { return [] }
        let r = await choose(Choice(player: p, title: title, kind: .cards(cards, min: min, max: Swift.min(max, cards.count)), canCancel: cancel) {
            ai(cards).compactMap { c in cards.firstIndex { $0 === c } }
        }) ?? []
        return r.compactMap { $0 < cards.count ? cards[$0] : nil }
    }
    private func pickOne(_ p: Player, _ title: String, _ cards: [Card], cancel: Bool = false, ai: @escaping ([Card]) -> Card?) async -> Card? {
        await pickCards(p, title, cards, max: 1, cancel: cancel) { cs in ai(cs).map { [$0] } ?? [] }.first
    }
    private func pickRow(_ p: Player, _ title: String, _ rows: [(Player, RowType)], ai: @escaping () -> Int) async -> (Player, RowType)? {
        guard !rows.isEmpty else { return nil }
        if rows.count == 1 { return rows[0] }
        guard let i = await choose(Choice(player: p, title: title, kind: .rows(rows), canCancel: false) { [ai()] })?.first, i < rows.count else { return rows[0] }
        return rows[i]
    }
    private func pickOption(_ p: Player, _ title: String, _ opts: [String], ai: @escaping () -> Int) async -> Int {
        (await choose(Choice(player: p, title: title, kind: .options(opts), canCancel: false) { [ai()] }))?.first ?? 0
    }
    private func reveal(_ p: Player, _ title: String, _ cards: [Card]) async {
        guard !cards.isEmpty else { return }
        _ = await choose(Choice(player: p, title: title, kind: .reveal(cards), canCancel: true) { [] })
    }
    var paused = false
    func pause(_ s: Double) async {
        try? await Task.sleep(nanoseconds: UInt64((autoHuman ? s * 0.3 : s) * 1_000_000_000))
        while paused { try? await Task.sleep(nanoseconds: 100_000_000) }
    }
    static let animIcons: Set<String> = ["adaptive", "aerondight", "ambush", "bond", "chernobog", "clairvoyance", "clear", "comrade", "cull", "curse", "decoration",
        "doppler", "emissary", "goetia", "horn", "immortal", "invoke", "knockback", "lock", "mardroeme", "medic", "monster_toussaint", "morale", "morana",
        "muster", "necrophage", "ofiri_envoy", "omen", "perun", "resilience", "rune_call", "seize", "shield", "soothsayer", "spy", "stribog",
        "summon_one_of", "svarog", "trade", "triglav", "veles"]
    static func animName(_ a: String) -> String? {
        if a == "toussaint_wine" { return "wine" }
        if a.hasPrefix("wish") { return "wish" }
        if a == "witch_hunt" { return "execute" }
        if a.hasPrefix("shield") { return "shield" }
        return animIcons.contains(a) ? a : nil
    }
    func animate(_ c: Card, _ name: String, wait: Bool = true) async {
        guard let n = Game.animName(name) ?? (name == "hero" ? "hero" : nil) else { return }
        events.append(.anim(c, n))
        if wait { await pause(0.7) }
    }
    func note(_ t: String, _ icon: String? = nil) { events.append(.notify(t, icon: icon)) }
    func sound(_ s: String) { events.append(.sound(s)) }

    func draw(_ p: Player, _ n: Int, silent: Bool = false) {
        for _ in 0..<n {
            guard !p.deck.isEmpty else { return }
            p.hand.append(p.deck.removeFirst())
            if p.leaderAbility == "ofir_aamad" && phase == .play { p.aamadBonus += 1 }
        }
        if !silent { recalc() }
    }
    func redraw(_ c: Card) -> Card? {
        guard phase == .redraw, redrawsLeft > 0, let i = me.hand.firstIndex(where: { $0 === c }), !me.deck.isEmpty else { return nil }
        let n = me.deck.removeFirst()
        me.hand[i] = n
        me.deck.insert(c, at: Int.random(in: 0...me.deck.count))
        redrawsLeft -= 1
        sound("redraw")
        return n
    }
    private func aiRedraw(_ p: Player) {
        if p.leaderAbility == "francesca_daisy" {
            for _ in 0..<2 { if let w = p.hand.min(by: { aiCardValue($0) < aiCardValue($1) }) { p.hand.removeAll { $0 === w }; p.deck.insert(w, at: Int.random(in: 0...p.deck.count)) } }
        }
        for _ in 0..<redrawCount(p) {
            let worst = p.hand.filter { $0.isUnit && !$0.hero && !$0.has("spy") && !$0.has("medic") && !$0.has("muster") && !$0.has("bond") }
                .min { $0.basePower < $1.basePower }
            guard let w = worst, w.basePower <= 3, !p.deck.isEmpty, let i = p.hand.firstIndex(where: { $0 === w }) else { return }
            p.hand[i] = p.deck.removeFirst()
            p.deck.insert(w, at: Int.random(in: 0...p.deck.count))
        }
    }
    func daisyReturn() async {
        if me.leaderAbility == "francesca_daisy" {
            let back = await pickCards(me, L("Choose 2 cards to put back into your deck"), me.hand, min: 2, max: 2) { cs in Array(cs.sorted { self.aiCardValue($0) < self.aiCardValue($1) }.prefix(2)) }
            for c in back { me.hand.removeAll { $0 === c }; me.deck.insert(c, at: Int.random(in: 0...me.deck.count)) }
        }
    }
    func finishRedraw() {
        guard phase == .redraw, !busy else { return }
        busy = true
        Task { @MainActor in
            await self.daisyReturn()
            self.phase = .play
            self.current = Bool.random() ? self.me : self.op
            self.sound("coin")
            self.events.append(.coin(self.current === self.me))
            await self.pause(1.6)
            self.note(self.current === self.me ? L("You will go first") : L("Your opponent will go first"), self.current === self.me ? "notif_me_coin" : "notif_op_coin")
            await self.startRound()
            self.busy = false
        }
    }

    private func startRound() async {
        turn += 1
        for p in [me, op] {
            p.aamadBonus = 0; p.comradeUsedRound = false; p.factionUsedRound = false; p.fleetDrawsRound = 0; p.halfWeather = false
        }
        note(L("Round Start") + " · \(round)", "notif_round_start")
        sound(round == 1 ? "round1_start" : "round_win")
        if round > 1 {
            for p in [me, op] {
                if p.faction == "realms" && lastRoundWinner !== p { draw(p, 1); note(L("Northern Realms faction ability triggered - North draws an additional card."), "notif_north") }
                if p.faction == "zerrikania" && lastRoundWinner === p.opponent {
                    let opts = p.grave.filter { $0.isUnit }
                    if let c = await pickOne(p, L("Which card to restore from your grave?"), opts, cancel: true, ai: { cs in cs.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                        p.grave.removeAll { $0 === c }
                        await placeUnit(c, by: p, row: c.allowedRows.first ?? .close)
                        note(L("Zerrikania ability used - Unit restored from discard pile."), "notif_zerrikania")
                    }
                }
                if p.faction == "skellige" && round == 3 {
                    let opts = p.grave.filter { $0.isUnit }.shuffled().prefix(2)
                    for c in opts { p.grave.removeAll { $0 === c }; await placeUnit(c, by: p, row: c.allowedRows.randomElement() ?? .close) }
                    if !opts.isEmpty { note(p === me ? L("Skellige Ability Triggered!") : L("Opponent Skellige Ability Triggered!"), "notif_skellige") }
                }
            }
        }
        for p in [me, op] where p.faction == "wild_hunt" {
            let leaders = gd.cards.values.filter { $0.isLeader && $0.key.hasPrefix("wh_") }.sorted { $0.key < $1.key }
            let cards = leaders.map { Card($0, owner: p) }
            if let c = await pickOne(p, L("Select the next leader to start the round with"), cards, ai: { cs in cs.randomElement() }) {
                p.leader = c; p.leaderUses = 1; applyPassiveLeader(p)
            }
        }
        for p in [me, op] {
            if p.leaderAbility == "king_bran", p.leaderUses > 0 {
                let yes = await pickOption(p, L("Bring the Skellige Storm?"), [L("Bring the Storm [E]"), L("Maybe later [Q]")]) { (self.round > 1 || p.deck.contains { $0.has("storm") }) ? 0 : 1 }
                if yes == 0 { p.leaderUses = 0; p.halfWeather = true
                    if let s = p.deck.first(where: { $0.has("storm") }) { p.deck.removeAll { $0 === s }; p.hand.append(s) } }
            }
            if p.leaderAbility == "madman_lugos", p.leaderUses > 0, p.opponent.hand.count >= 2 {
                let yes = await pickOption(p, L("Discard a card from the hand of the opponent?"), [L("Discard a card [E]"), L("Maybe later [Q]")]) { self.round >= 2 ? 0 : 1 }
                if yes == 0 {
                    p.leaderUses = 0
                    let two = Array(p.opponent.hand.shuffled().prefix(2))
                    if let c = await pickOne(p, L("Which card to discard?"), two, ai: { cs in cs.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                        p.opponent.hand.removeAll { $0 === c }; p.opponent.grave.append(c)
                    }
                }
            }
        }
        for p in [me, op] where p.faction == "scoiatael" {
            let i = await pickOption(p, L("Who should go first?"), [L("Go First [E]"), L("Let Opponent Start [Q]")]) { 1 }
            current = i == 0 ? p : p.opponent
            if p === op { note(L("Opponent used the Scoia'tael faction perk to go first."), "notif_scoiatael") }
            break
        }
        await beginTurn()
    }

    private func beginTurn() async {
        recalc()
        if me.passed && op.passed { await endRound(); return }
        if current.passed { current = current.opponent }
        if current.hand.isEmpty && !current.passed && !canActWithoutCards(current) { await pass(current); return }
        if current === me { note(L("Your turn!"), "notif_me_turn"); sound("turn_me") } else { sound("turn_op") }
    }
    private func canActWithoutCards(_ p: Player) -> Bool { leaderAvailable(p) || factionActive(p) != nil }

    func pass(_ p: Player) async {
        guard phase == .play, !p.passed else { return }
        p.passed = true
        sound("pass")
        note(p === me ? L("Round passed") : L("Your opponent has passed"), "notif_round_passed")
        if p === current { current = p.opponent }
        await beginTurn()
    }

    private func endTurn(_ p: Player) async {
        recalc()
        let doors = RowType.allCases.filter { p.row($0).door }
        if !doors.isEmpty, let top = p.deck.first {
            p.deck.removeFirst()
            if top.isUnit, let r = doors.first(where: { top.allowedRows.contains($0) }) {
                await placeUnit(top, by: p, row: r)
            } else if !top.isUnit {
                p.hand.append(top)
            } else { p.deck.insert(top, at: Int.random(in: 0...p.deck.count)) }
        }
        for q in [p, p.opponent!] where q.faction == "velen" && q.lostUnitThisTurn {
            q.lostUnitThisTurn = false
            let n = 1 + q.rowCards.filter { $0.act("soothsayer") }.count
            if q.leaderAbility == "lady_wood_brewess", q.deck.count >= 2 {
                let two = Array(q.deck.prefix(2))
                if let c = await pickOne(q, L("Choose a unit to play immediately"), two, ai: { cs in cs.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                    q.deck.removeAll { $0 === c }
                    if c.isUnit { await placeUnit(c, by: q, row: c.allowedRows.first ?? .close) } else { q.hand.append(c) }
                    q.deck.shuffle()
                }
            } else { draw(q, n) }
            note(L("Velen ability triggered: Player will draw a card"), "notif_velen")
        }
        recalc()
        turn += 1
        if !p.opponent.passed { current = p.opponent }
        await beginTurn()
    }

    private func endRound() async {
        phase = .roundEnd
        recalc()
        for p in [me, op] where p.faction == "monsters" && !p.monstersUsed && !p.rowCards.isEmpty {
            let yes = await pickOption(p, L("Would you like to retake one of your cards?"), [L("Retake a card [E]"), L("Not yet [Q]")]) { self.round >= 2 ? 0 : 1 }
            if yes == 0, let c = await pickOne(p, L("Which card to retake?"), p.rowCards, ai: { cs in cs.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                p.monstersUsed = true
                if let r = p.rowOf(c) { p.row(r).cards.removeAll { $0 === c } }
                resetCard(c); p.hand.append(c)
                note(L("Monsters faction ability triggered - monsters retake one card to their hand"), "notif_monsters")
            }
        }
        recalc()
        let a = me.total, b = op.total
        var w: Player? = a > b ? me : (b > a ? op : nil)
        if w == nil {
            let nm = me.faction == "nilfgaard", no = op.faction == "nilfgaard"
            if nm != no { w = nm ? me : op; note(L("Nilfgaard wins draws"), "notif_nilfgaard") }
        }
        history.append((a, b, w))
        lastRoundWinner = w
        if let w = w { w.opponent.gems -= 1 } else { me.gems -= 1; op.gems -= 1 }
        if w === me { note(L("You won the round!"), "notif_win_round"); sound("round_win") }
        else if w === op { note(L("Your opponent won the round"), "notif_lose_round"); sound("round_lose") }
        else { note(L("The round ended in a draw"), "notif_draw_round") }
        await cleanupRound()
        if me.gems <= 0 || op.gems <= 0 || round >= 3 {
            phase = .over
            winner = me.gems > op.gems ? me : (op.gems > me.gems ? op : nil)
            sound(winner === me ? "game_win" : "game_lose")
            recalc()
            return
        }
        round += 1
        me.passed = false; op.passed = false
        current = w ?? current
        phase = .play
        await startRound()
    }

    private func resetCard(_ c: Card) {
        c.locked = false; c.setTo = nil; c.tempStrength = nil; c.multiplier = 1; c.bonus = 0; c.siegeMult = 1
        c.baseOverride = nil; c.heroOverride = nil; c.keepNextRound = false
    }
    private func cleanupRound() async {
        var avengers: [(Card, Player, RowType)] = []
        for p in [me, op] {
            for c in p.rowCards where c.act("resilience") {
                let key = c.data.abilities.last ?? ""
                if p.rowCards.filter({ $0 !== c && $0.data.abilities.contains(key) }).count >= 1 { c.keepNextRound = true }
            }
        }
        for p in [me, op] {
            for r in RowType.allCases {
                let row = p.row(r)
                var stay: [Card] = []
                for c in row.cards {
                    if c.immortalRounds > 1 { c.immortalRounds -= 1; stay.append(c); continue }
                    if c.keepNextRound { c.keepNextRound = false; stay.append(c); continue }
                    if c.data.abilities.contains(where: { $0.hasPrefix("avenger") }) && !c.locked { avengers.append((c, p, r)) }
                    resetCard(c); c.diedRound = round
                    (c.owner ?? p).grave.append(c)
                }
                row.cards = stay
                for s in row.specials { (s.owner ?? p).grave.append(s) }
                row.specials.removeAll(); row.lock = nil; row.curse = nil; row.ambush = nil; row.door = false; row.leaderHorn = false; row.factionMorale = 0
                p.weather[r.rawValue].removeAll()
            }
            for c in p.hand + p.deck { c.tempStrength = nil }
            p.forcedCard = nil
        }
        for c in weatherCards { (c.owner ?? me).grave.append(c) }
        weatherCards.removeAll()
        for p in [me, op] where p.fleetPending > 0 { draw(p, p.fleetPending); p.fleetPending = 0 }
        if round < 3 {
            for (c, p, r) in avengers {
                for t in c.data.targets {
                    guard let d = gd.cards[t], d.isUnit else { continue }
                    if let i = p.deck.firstIndex(where: { $0.key == t }) { let n = p.deck.remove(at: i); p.row(RowType.from(d.row) ?? r).cards.append(n); n.flash = 1 }
                    else { let n = Card(d, owner: p); p.row(RowType.from(d.row) ?? r).cards.append(n); n.flash = 1 }
                }
            }
        }
        recalc()
    }

    func validRows(for c: Card, by p: Player) -> [RowType] {
        if c.isUnit {
            if c.act("ambush") || c.has("ambush") { return RowType.allCases }
            return c.allowedRows
        }
        switch c.specialKind ?? "" {
        case "horn", "mardroeme", "morale": return RowType.allCases.filter { r in !p.row(r).specials.contains { $0.specialKind == c.specialKind } }
        case "toussaint_wine": return [.close, .ranged].filter { !p.row($0).specials.contains { $0.specialKind == "toussaint_wine" } }
        case "shield": return RowType.allCases.filter { !p.row($0).shielded }
        case "shield_c": return [.close]
        case "shield_r": return [.ranged]
        case "shield_s": return [.siege]
        case "door": return RowType.allCases.filter { !p.row($0).door }
        default: return []
        }
    }
    func enemyRowTargets(for c: Card, by p: Player) -> [RowType] {
        switch c.specialKind ?? "" {
        case "lock": return RowType.allCases.filter { p.opponent.row($0).lock == nil }
        case "knockback": return [.close, .ranged]
        default: return []
        }
    }
    func curseRows(by p: Player) -> [(Player, RowType)] {
        [p, p.opponent].flatMap { q in RowType.allCases.filter { q.row($0).curse == nil }.map { (q, $0) } }
    }
    func decoyTargets(for p: Player) -> [Card] { p.rowCards.filter { !$0.hero && $0.key != "spe_decoy" && $0.immortalRounds == 0 } }

    func humanPlay(_ c: Card, row: RowType? = nil, rowOwner: Player? = nil, target: Card? = nil) {
        guard !busy, phase == .play, current === me, me.hand.contains(where: { $0 === c }) else { return }
        busy = true
        Task { @MainActor in await self.play(c, by: self.me, row: row, rowOwner: rowOwner, target: target); self.busy = false }
    }
    func humanPass() { guard !busy, phase == .play, current === me else { return }; busy = true; Task { @MainActor in await self.pass(self.me); self.busy = false } }

    func play(_ c: Card, by p: Player, row: RowType? = nil, rowOwner: Player? = nil, target: Card? = nil) async {
        guard phase == .play, current === p, let hi = p.hand.firstIndex(where: { $0 === c }) else { return }
        if let f = p.forcedCard, f !== c, p.hand.contains(where: { $0 === f }) { return }
        p.forcedCard = nil
        p.hand.remove(at: hi)
        c.owner = p
        c.flash = 1
        if c.data.isWeather { await playWeather(c, by: p, row: row) }
        else if c.data.isSpecial { await playSpecial(c, by: p, row: row, rowOwner: rowOwner, target: target) }
        else { await placeUnit(c, by: p, row: row ?? c.allowedRows.first ?? .close) }
        await endTurn(p)
    }

    func placeUnit(_ c: Card, by p: Player, row r0: RowType, side forcedSide: Player? = nil) async {
        var r = r0
        let isSpy = c.has("spy") || c.has("emissary") || c.has("ofiri_envoy")
        let side: Player = forcedSide ?? (isSpy ? p.opponent : p)
        if !c.isUnit { p.hand.append(c); return }
        if !c.data.row.hasPrefix("agile") && !c.has("ambush"), let fixed = RowType.from(c.data.row) { r = fixed }
        c.owner = p
        c.playedTurn = turn
        let row = side.row(r)
        if let curse = row.curse, !c.hero {
            row.curse = nil; (curse.owner ?? p).grave.append(curse)
            side.grave.append(c); c.diedRound = round
            note(gd.abilityName("curse")); sound("curse")
            return
        }
        row.cards.append(c)
        c.flash = 1
        sound(c.hero ? "hero" : "card")
        if let lk = row.lock, !c.hero, !c.data.abilities.filter({ $0 != "hero" }).isEmpty {
            c.locked = true; row.lock = nil; (lk.owner ?? p).grave.append(lk); sound("lock"); events.append(.anim(c, "lock"))
        }
        if let amb = side.opponent.row(r).cards.first(where: { $0.act("ambush") && $0.owner === side.opponent }), side === p {
            let o = side.opponent!
            o.row(r).cards.removeAll { $0 === amb }; o.grave.append(amb)
            draw(o, 2); sound("ambush")
        }
        if isSpy && side.leaderAbility == "novigrad_sigismund2" { draw(side, 1) }
        recalc()
        await pause(0.3)
        if c.hero { events.append(.anim(c, "hero")) }
        if c.locked { await animate(c, "lock"); return }
        if c.act("bond") {
            let group = row.cards.filter { $0.act("bond") && $0.groupKey == c.groupKey }
            if group.count > 1 { for g in group { await animate(g, "bond", wait: false) }; await pause(0.7) }
        } else if let a = c.data.abilities.reversed().first(where: { Game.animName($0) != nil }) {
            await animate(c, a)
        } else if c.hero { await pause(0.6) }
        await unitAbilities(c, by: p, side: side, row: r)
        recalc()
    }

    private func unitAbilities(_ c: Card, by p: Player, side: Player, row r: RowType) async {
        let o = p.opponent!
        for a in c.data.abilities {
            switch a {
            case "spy":
                if p.faction == "toussaint" {
                    let three = Array(p.deck.prefix(3))
                    if let k = await pickOne(p, L("Choose the card to draw and keep"), three, ai: { cs in cs.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                        p.deck.removeAll { $0 === k }; p.hand.append(k); p.deck.shuffle()
                    }
                } else { await spyDraw(p, 2) }
                sound("spy")
            case "emissary":
                let i = await pickOption(p, L("Choose the effect of the emissary"), [L("Draw 1 card [E]"), L("Look first 4 cards [Q]")]) { 0 }
                if i == 0 { await spyDraw(p, 1) } else { await reorderTop(p, 4) }
                sound("emissary")
            case "ofiri_envoy":
                let i = p.drawOpponentLeft > 0 && !o.deck.isEmpty
                    ? await pickOption(p, L("From which deck to draw the next card? (Ofiri Envoy can draw from opponent's deck only once)"), [L("Own deck [E]"), L("Opponent's deck [Q]")]) { 0 } : 0
                if i == 1 { p.drawOpponentLeft = 0; if let t = o.deck.first { o.deck.removeFirst(); t.owner = p; p.hand.append(t) }; draw(p, 1) } else { draw(p, 2) }
                sound("ofiri_envoy")
            case "medic": await medic(p)
            case "muster": await muster(c, p, r)
            case "invoke":
                let opts = p.deck.filter { c.data.targets.contains($0.key) || ($0.groupKey == c.groupKey && $0 !== c && !c.data.target.isEmpty) }
                if let t = await pickOne(p, L("Choose one card to play."), opts, ai: { $0.first }) { p.deck.removeAll { $0 === t }; await placeUnit(t, by: p, row: t.allowedRows.first ?? r); sound("invoke") }
            case "summon_one_of":
                let opts = (p.deck + p.hand + p.grave).filter { c.data.targets.contains($0.key) }
                if let t = await pickOne(p, L("Choose one card to play."), opts, ai: { cs in cs.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                    p.deck.removeAll { $0 === t }; p.hand.removeAll { $0 === t }; p.grave.removeAll { $0 === t }
                    await placeUnit(t, by: p, row: t.allowedRows.first ?? r)
                }
            case "scorch_c", "scorch_r", "scorch_s":
                let t: RowType = a == "scorch_c" ? .close : (a == "scorch_r" ? .ranged : .siege)
                await rowScorch(o, t)
            case "scorch": await scorch(except: c)
            case "cull": await cull(except: c)
            case "mardroeme": await berserk(side, r)
            case "berserker": if side.row(r).specials.contains(where: { $0.specialKind == "mardroeme" }) || side.row(r).cards.contains(where: { $0.act("mardroeme") }) { await berserk(side, r) }
            case "witch_hunt":
                let opp = o.row(r)
                if opp.shielded { break }
                let units = opp.cards.filter { !$0.hero && $0.immortalRounds == 0 }
                if let mn = units.map({ $0.power }).min() {
                    let cands = units.filter { $0.power == mn }
                    if let t = await pickOne(p, L("Choose which enemy card to destroy"), cands, ai: { $0.first }) { await destroy(t, side: o) }
                }
            case "necrophage":
                let opts = p.grave.filter { $0.isUnit }
                let picks = await pickCards(p, L("Choose up to 2 cards to take from your grave back to your deck."), opts, min: 0, max: 2, cancel: true) { cs in Array(cs.sorted { self.aiCardValue($0) > self.aiCardValue($1) }.prefix(2)) }
                for x in picks { p.grave.removeAll { $0 === x }; resetCard(x); p.deck.insert(x, at: Int.random(in: 0...p.deck.count)) }
            case "goetia":
                if let d = await pickOne(p, L("Choose a card to draw from your deck."), p.deck, ai: { cs in cs.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                    p.deck.removeAll { $0 === d }; p.hand.append(d)
                    if let back = await pickOne(p, L("Which card to put back into your deck?"), p.hand, ai: { cs in cs.min { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                        p.hand.removeAll { $0 === back }; p.deck.insert(back, at: Int.random(in: 0...p.deck.count))
                    }
                }
            case "sage": await reorderTop(p, 4)
            case "zirael":
                let five = Array(p.deck.prefix(5))
                let picks = await pickCards(p, L("Choose up to 2 cards to draw and keep in your hand"), five, min: 0, max: 2) { cs in Array(cs.sorted { self.aiCardValue($0) > self.aiCardValue($1) }.prefix(2)) }
                for x in picks { p.deck.removeAll { $0 === x }; p.hand.append(x) }
                p.deck.shuffle()
            case "naglfar":
                let opts = p.deck.filter { $0.data.name.contains("Naglfar") && $0.isUnit }
                let picks = await pickCards(p, L("Choose up to 2 cards to play right away."), opts, min: 0, max: 2) { cs in Array(cs.prefix(2)) }
                for x in picks { p.deck.removeAll { $0 === x }; await placeUnit(x, by: p, row: x.allowedRows.first ?? .siege) }
            case "bait":
                let opts = p.deck.filter { $0.has("bond") }
                if let t = await pickOne(p, L("Choose one card to play."), opts, ai: { cs in cs.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                    p.deck.removeAll { $0 === t }; await placeUnit(t, by: p, row: t.allowedRows.first ?? r)
                }
            case "clairvoyance":
                let i = await pickOption(p, L("Clairvoyance Options"), [L("View Deck [E]"), L("Spy Enemy [Q]")]) { 1 }
                if i == 0 { await reveal(p, L("Clairvoyance: Top 3 cards of your deck (click to close)"), Array(p.deck.prefix(3))) }
                else { await reveal(p, L("Clairvoyance: 3 random cards of enemy hand (click to close)"), Array(o.hand.shuffled().prefix(3))) }
            case "trade":
                if let t = await pickOne(p, L("Select a card from the opponent's deck to buy."), o.deck, ai: { cs in cs.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                    o.deck.removeAll { $0 === t }; t.owner = p; p.hand.append(t)
                    if let rune = p.deck.first(where: { $0.key.hasPrefix("ofir_") && $0.data.isSpecial }) { p.deck.removeAll { $0 === rune }; rune.owner = o; o.hand.append(rune) }
                    sound("trade")
                }
            case "rune_call":
                let opts = p.deck.filter { $0.key.hasPrefix("ofir_") && $0.data.isSpecial }
                if let t = await pickOne(p, L("Choose 1 runestone from your deck to add to your hand."), opts, ai: { $0.randomElement() }) { p.deck.removeAll { $0 === t }; p.hand.append(t) }
            case "omen":
                if let d = gd.cards["nv_catanddog"] { p.hand.append(Card(d, owner: p)) }
            case "wish1", "wish2", "wish3":
                await djinnWish(a, c, p)
            case "doppler":
                let opts = o.row(r).cards.filter { !$0.hero && $0.isUnit }
                if let t = await pickOne(p, L("Choose an enemy unit from the opposite row to transform Doppler into."), opts, ai: { cs in cs.max { $0.basePower < $1.basePower } }) {
                    c.baseOverride = t.basePower; sound("doppler"); await animate(c, "doppler")
                }
            case "aerondight":
                let opts = p.rowCards.filter { $0 !== c && !$0.hero }
                if let t = await pickOne(p, L("Choose which card to equip with Aerondight."), opts, ai: { cs in cs.max { $0.basePower < $1.basePower } }) {
                    if let tr = p.rowOf(t) { p.row(tr).cards.removeAll { $0 === t } }
                    p.row(.siege).cards.append(t); t.siegeMult = 3
                }
            case "immortal": c.immortalRounds = 2
            case "toussaint_wine": break
            default: break
            }
        }
    }

    private func spyDraw(_ p: Player, _ n: Int) async {
        let o = p.opponent!
        for _ in 0..<n {
            if p.leaderAbility == "emhyr_whiteflame" && p.drawOpponentLeft > 0 && !o.deck.isEmpty {
                let i = await pickOption(p, L("Choose deck to draw from"), [L("Own deck [E]"), L("Opponent's deck [Q]")]) { 1 }
                if i == 1, let t = o.deck.first { o.deck.removeFirst(); t.owner = p; p.hand.append(t); p.drawOpponentLeft -= 1; continue }
            }
            draw(p, 1)
        }
    }
    private func reorderTop(_ p: Player, _ n: Int) async {
        let top = Array(p.deck.prefix(n))
        guard !top.isEmpty else { return }
        let order = await pickCards(p, L("Re-order the cards back into the deck"), top, min: top.count, max: top.count) { cs in cs.sorted { self.aiCardValue($0) > self.aiCardValue($1) } }
        p.deck.removeFirst(top.count)
        p.deck.insert(contentsOf: order.isEmpty ? top : order, at: 0)
    }
    private func medic(_ p: Player) async {
        sound("med")
        for _ in 0..<medicPicks {
            let opts = p.grave.filter { $0.isUnit && !$0.hero }
            guard let c = await pickOne(p, L("Which card to restore from your grave?"), opts, cancel: true, ai: { cs in cs.max { self.aiCardValue($0) < self.aiCardValue($1) } }) else { return }
            p.grave.removeAll { $0 === c }
            resetCard(c)
            await placeUnit(c, by: p, row: c.allowedRows.first ?? .close)
        }
    }
    private func muster(_ c: Card, _ p: Player, _ r: RowType) async {
        let key = c.groupKey
        let fromHand = p.hand.filter { $0 !== c && $0.groupKey == key && $0.isUnit }
        let fromDeck = p.deck.filter { $0.groupKey == key && $0.isUnit }
        if fromHand.isEmpty && fromDeck.isEmpty { return }
        for m in fromHand + fromDeck {
            p.hand.removeAll { $0 === m }; p.deck.removeAll { $0 === m }
            let rr = c.data.row.hasPrefix("agile") ? r : (RowType.from(m.data.row) ?? m.allowedRows.first ?? r)
            m.owner = p; m.playedTurn = turn
            p.row(rr).cards.append(m); m.flash = 1
        }
        sound("ally")
        recalc()
    }
    private func berserk(_ side: Player, _ r: RowType) async {
        for c in side.row(r).cards where c.act("berserker") {
            if let t = c.data.targets.first, let d = gd.cards[t] { c.transform(into: d); events.append(.anim(c, "mardroeme")) }
        }
        sound("mardroeme")
        recalc()
    }
    private func djinnWish(_ a: String, _ c: Card, _ p: Player) async {
        let o = p.opponent!
        let minStr = a == "wish3" ? 7 : 6
        let costs = p.rowCards.filter { $0 !== c && !$0.hero && $0.basePower >= minStr }
        guard let cost = costs.max(by: { $0.power < $1.power }) else { return }
        await destroy(cost, side: p)
        switch a {
        case "wish1":
            let three = Array(o.hand.shuffled().prefix(3))
            if let t = await pickOne(p, L("The Djinn grants your wish: Choose 1 enemy card to steal."), three, ai: { cs in cs.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                o.hand.removeAll { $0 === t }; t.owner = p; p.hand.append(t)
            }
        case "wish2":
            let three = Array(p.deck.prefix(3))
            if let t = await pickOne(p, L("The Djinn grants your second wish: Choose 1 card from your deck to draw."), three, ai: { cs in cs.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                p.deck.removeAll { $0 === t }; p.hand.append(t)
            }
            c.immortalRounds = max(c.immortalRounds, 1)
        default:
            let opts = o.rowCards.filter { !$0.hero && $0.immortalRounds == 0 }
            if let t = await pickOne(p, L("The Djinn grants your third wish: Choose 1 enemy unit to destroy."), opts, ai: { cs in cs.max { $0.power < $1.power } }) { await destroy(t, side: o) }
            c.immortalRounds = max(c.immortalRounds, 1)
        }
    }

    private func playSpecial(_ c: Card, by p: Player, row: RowType?, rowOwner: Player?, target: Card?) async {
        let o = p.opponent!
        let kind = c.specialKind ?? ""
        switch kind {
        case "horn", "mardroeme", "morale", "toussaint_wine", "shield", "shield_c", "shield_r", "shield_s":
            var r = row
            if r == nil { r = await pickRow(p, L("Select a card on your side of the board."), validRows(for: c, by: p).map { (p, $0) }) { 0 }?.1 }
            guard let rr = r else { p.grave.append(c); return }
            p.row(rr).specials.append(c)
            await animate(c, kind)
            sound(kind == "horn" ? "horn" : (kind == "mardroeme" ? "mardroeme" : (kind.hasPrefix("shield") ? "shield" : "moral")))
            if kind == "mardroeme" { await berserk(p, rr) }
        case "door":
            var r = row
            if r == nil { r = await pickRow(p, L("Select a card on your side of the board."), validRows(for: c, by: p).map { (p, $0) }) { 0 }?.1 }
            let open = RowType.allCases.filter { p.row($0).door }
            if let rr = r, open.count < maxDoors { p.row(rr).door = true }
            p.grave.append(c); sound("door")
        case "decoy":
            if let t = target, let r = p.rowOf(t), let i = p.row(r).cards.firstIndex(where: { $0 === t }) {
                p.row(r).cards[i] = c
                resetCard(t); t.owner = p; p.hand.append(t)
                sound("decoy")
            } else { p.grave.append(c) }
        case "scorch": await scorch(except: nil); p.grave.append(c)
        case "cull": await cull(except: nil); p.grave.append(c)
        case "clear": await clearWeather(); p.grave.append(c)
        case "lock":
            var r = row
            if r == nil { r = await pickRow(p, L("Select a card on your side of the board."), enemyRowTargets(for: c, by: p).map { (o, $0) }) { Int.random(in: 0..<3) }?.1 }
            if let rr = r { o.row(rr).lock = c } else { p.grave.append(c) }
            sound("lock")
        case "curse":
            var dest: (Player, RowType)? = rowOwner.flatMap { q in row.map { (q, $0) } }
            if dest == nil { dest = await pickRow(p, gd.abilityName("curse"), curseRows(by: p)) { 3 + Int.random(in: 0..<3) } }
            if let (q, rr) = dest { q.row(rr).curse = c } else { p.grave.append(c) }
            sound("curse")
        case "knockback":
            var r = row
            if r == nil { r = await pickRow(p, gd.abilityName("knockback"), [(o, .close), (o, .ranged)]) { 0 }?.1 }
            if let rr = r {
                let dest: RowType = rr == .close ? .ranged : .siege
                let moving = o.row(rr).cards.filter { !$0.hero }
                o.row(rr).cards.removeAll { m in moving.contains { $0 === m } }
                o.row(dest).cards.append(contentsOf: moving)
                sound("knockback")
            }
            p.grave.append(c)
        case "seize": await seize(p, .close); p.grave.append(c)
        case "bank": draw(p, 1); sound("game_buy"); p.grave.append(c)
        case "skellige_fleet":
            if p.fleetDrawsRound < 3 {
                let i = await pickOption(p, L("Draw now or more later?"), [L("Draw 1 now [E]"), L("Draw 2 later [Q]")]) { 0 }
                if i == 0 { draw(p, 1); p.fleetDrawsRound += 1 } else { p.fleetPending += 2; p.fleetDrawsRound += 2 }
            }
            p.row(.siege).specials.append(c)
        case "royal_decree":
            p.grave.append(c)
            await leaderEffect(p, free: true)
        case "decoration":
            let opts = p.rowCards.filter { !$0.hero }
            if let t = await pickOne(p, L("Choose a unit to promote to Hero."), opts, ai: { cs in cs.max { $0.power < $1.power } }) { t.heroOverride = true; t.flash = 1; await animate(t, "decoration") }
            p.grave.append(c); sound("decoration")
        case "chernobog", "perun":
            let opts = p.row(kind == "chernobog" ? .close : .ranged).cards.filter { !$0.hero }
            if let t = await pickOne(p, kind == "chernobog" ? L("Choose which unit to double with Chernobog runestone") : L("Choose which unit to grant +5 strength with Perun runestone"), opts, ai: { cs in cs.max { $0.power < $1.power } }) {
                if kind == "chernobog" { t.multiplier *= 2 } else { t.bonus += 5 }; t.flash = 1; await animate(t, kind)
            }
            p.grave.append(c); sound("rune_call")
        case "svarog", "morana":
            let opts = o.row(kind == "svarog" ? .siege : .close).cards.filter { !$0.hero }
            if let t = await pickOne(p, kind == "svarog" ? L("Choose which enemy siege unit to reduce to 1 with Svarog.") : L("Choose which enemy close unit to reduce to 1 with Morana."), opts, ai: { cs in cs.max { $0.power < $1.power } }) { t.setTo = 1; t.flash = 1; await animate(t, kind) }
            p.grave.append(c); sound("rune_call")
        case "triglav":
            let opts = o.rowCards.filter { $0.hero }
            if let t = await pickOne(p, L("Choose the enemy hero to weaken."), opts, ai: { cs in cs.max { $0.power < $1.power } }) { t.heroOverride = false; t.flash = 1; await animate(t, "triglav") }
            p.grave.append(c); sound("triglav")
        case "veles":
            if let t = p.rowCards.filter({ !$0.hero }).max(by: { $0.power < $1.power }) {
                if let tr = p.rowOf(t) { p.row(tr).cards.removeAll { $0 === t } }
                p.row(.siege).cards.append(t); t.siegeMult = 2; await animate(t, "veles")
            }
            p.grave.append(c); sound("veles")
        case "devana":
            for t in o.row(.ranged).cards where !t.hero { t.setTo = 2; t.flash = 1 }
            p.grave.append(c); sound("rune_call")
        case "zoria":
            o.weather[RowType.close.rawValue].insert("frost")
            p.grave.append(c); sound("cold")
        case "stribog":
            let units = o.row(.ranged).cards.filter { !$0.hero }
            if let mn = units.map({ $0.power }).min() {
                for t in units where t.power == mn { o.row(.ranged).cards.removeAll { $0 === t }; t.owner = p; p.row(.ranged).cards.append(t) }
            }
            p.grave.append(c); sound("rune_call")
        default:
            p.grave.append(c)
        }
        recalc()
    }

    private func seize(_ p: Player, _ r: RowType) async {
        let o = p.opponent!
        if o.row(r).shielded { return }
        let units = o.row(r).cards.filter { !$0.hero && $0.immortalRounds == 0 }
        guard let mn = units.map({ $0.power }).min() else { return }
        for t in units where t.power == mn {
            o.row(r).cards.removeAll { $0 === t }
            t.owner = p; t.locked = true
            p.row(r).cards.append(t); t.flash = 1; events.append(.anim(t, "seize"))
        }
        sound("seize")
    }

    private func weatherRows(_ a: String, _ c: Card) -> [RowType] {
        switch a {
        case "frost", "spider_web": return [.close]
        case "fog", "tse_tse": return [.ranged]
        case "rain", "dragon_wrath": return [.siege]
        case "sandstorm": return [.close, .ranged]
        case "white_frost":
            switch c.data.row { case "agile_cs": return [.close, .siege]; case "agile_rs": return [.ranged, .siege]; default: return [.close, .ranged] }
        default: return []
        }
    }
    private func playWeather(_ c: Card, by p: Player, row: RowType?) async {
        let a = c.data.abilities.first ?? ""
        if a == "clear" { await clearWeather(); (c.owner ?? p).grave.append(c); return }
        var rows = weatherRows(a, c)
        if a == "storm" {
            let i = await pickOption(p, L("Skellige Storm can either target Close/Ranged rows or Ranged/Siege rows, which one to target?"), [L("Close + Ranged [E]"), L("Ranged + Siege [Q]")]) {
                let o = p.opponent!
                return o.row(.close).total + o.row(.ranged).total - p.row(.close).total - p.row(.ranged).total >= o.row(.ranged).total + o.row(.siege).total - p.row(.ranged).total - p.row(.siege).total ? 0 : 1
            }
            rows = i == 0 ? [.close, .ranged] : [.ranged, .siege]
        }
        if rows.allSatisfy({ me.weather[$0.rawValue].contains(a) && op.weather[$0.rawValue].contains(a) }) { (c.owner ?? p).grave.append(c); return }
        for q in [me, op] { for r in rows { q.weather[r.rawValue].insert(a) } }
        weatherCards.append(c)
        sound(["frost": "cold", "fog": "fog", "rain": "rain", "storm": "rain", "white_frost": "cold", "sandstorm": "sandstorm", "spider_web": "spider_web", "tse_tse": "tse_tse", "dragon_wrath": "dragon_wrath"][a] ?? "rain")
        if a == "fog" {
            for q in [me, op] {
                for x in (q.deck + q.grave).filter({ $0.has("fog_summoning") }) {
                    q.deck.removeAll { $0 === x }; q.grave.removeAll { $0 === x }
                    resetCard(x); x.owner = q; q.row(x.allowedRows.first ?? .ranged).cards.append(x); x.flash = 1
                }
            }
        }
        recalc()
    }
    private func clearWeather() async {
        for c in weatherCards { c.owner?.grave.append(c) }
        weatherCards.removeAll()
        for q in [me, op] { for i in 0..<3 { q.weather[i].removeAll() } }
        sound("clear")
        recalc()
    }

    private func protected(_ c: Card, side: Player) async -> Bool {
        if c.immortalRounds > 0 { return true }
        if navigatorShield && c.has("door_o") && (side.leaderAbility == "imlerith_general") { return true }
        if side.leaderAbility == "novigrad_sigismund" && !side.sigismundSaved { side.sigismundSaved = true; note(L("Sigismund Dijkstra prevented the death of a friendly unit.")); return true }
        if !side.comradeUsedRound, side.rowCards.contains(where: { $0.act("comrade") }) {
            let i = await pickOption(side, L("Do you want to save Comrade too?"), [L("Save it [E]"), L("Let it die [Q]")]) { 0 }
            if i == 0 { side.comradeUsedRound = true; sound("comrade"); return true }
        }
        return false
    }
    func destroy(_ c: Card, side: Player, burn: Bool = true) async {
        guard let r = side.rowOf(c) else { return }
        if await protected(c, side: side) { c.flash = 1; await animate(c, "comrade"); return }
        if burn { events.append(.burn(c)); await pause(0.75) }
        side.row(r).cards.removeAll { $0 === c }
        events.append(.flash(c))
        resetCard(c); c.diedRound = round
        (c.owner ?? side).grave.append(c)
        side.lostUnitThisTurn = true
        if c.data.abilities.contains(where: { $0.hasPrefix("avenger") }) {
            for t in c.data.targets {
                guard let d = gd.cards[t], d.isUnit else { continue }
                let n: Card
                if let i = side.deck.firstIndex(where: { $0.key == t }) { n = side.deck.remove(at: i) } else { n = Card(d, owner: side) }
                n.owner = side; side.row(RowType.from(d.row) ?? r).cards.append(n); n.flash = 1
            }
        }
    }
    private func scorch(except: Card?) async {
        recalc()
        var all: [(Card, Player)] = []
        for p in [me, op] { for r in RowType.allCases where !p.row(r).shielded { for c in p.row(r).cards where !c.hero && c !== except && c.key != "spe_decoy" { all.append((c, p)) } } }
        guard let maxP = all.map({ $0.0.power }).max(), maxP > 0 else { return }
        sound("scorch")
        let victims = all.filter { $0.0.power == maxP }
        for (c, _) in victims { events.append(.burn(c)) }
        await pause(0.75)
        for (c, p) in victims { await destroy(c, side: p, burn: false) }
        recalc()
    }
    private func cull(except: Card?) async {
        recalc()
        var all: [(Card, Player)] = []
        for p in [me, op] { for r in RowType.allCases where !p.row(r).shielded { for c in p.row(r).cards where !c.hero && c !== except && c.key != "spe_decoy" { all.append((c, p)) } } }
        guard let mn = all.map({ $0.0.power }).min() else { return }
        sound("cull")
        let victims = all.filter { $0.0.power == mn }
        for (c, _) in victims { events.append(.burn(c)) }
        await pause(0.75)
        for (c, p) in victims { await destroy(c, side: p, burn: false) }
        recalc()
    }
    private func rowScorch(_ side: Player, _ t: RowType) async {
        recalc()
        let row = side.row(t)
        guard row.total >= 10, !row.shielded else { return }
        let units = row.cards.filter { !$0.hero && $0.key != "spe_decoy" }
        guard let maxP = units.map({ $0.power }).max(), maxP > 0 else { return }
        sound("scorch")
        let victims = units.filter { $0.power == maxP }
        for c in victims { events.append(.burn(c)) }
        await pause(0.75)
        for c in victims { await destroy(c, side: side, burn: false) }
        recalc()
    }

    static let passiveLeaders: Set<String> = ["eredin_treacherous", "vilgefortz_magician_kovir", "emhyr_whiteflame", "imlerith_general", "meve_white_queen",
                                              "novigrad_sigismund", "novigrad_sigismund2", "ofir_aamad", "zerrikanterment", "caranthir_navigator",
                                              "ofir_aamad_crown", "lady_wood_brewess", "francesca_daisy", "king_bran", "madman_lugos"]
    func leaderAvailable(_ p: Player) -> Bool { p.leaderUses > 0 && !Game.passiveLeaders.contains(p.leaderAbility) }
    func humanLeader() {
        guard !busy, phase == .play, current === me, leaderAvailable(me) else { return }
        busy = true
        Task { @MainActor in
            await self.useLeader(self.me)
            self.busy = false
        }
    }
    func useLeader(_ p: Player) async {
        guard phase == .play, current === p, leaderAvailable(p) else { return }
        p.leaderUses -= 1
        p.leader.flash = 1
        sound("leader")
        note(p === me ? gd.cardName(p.leader.data) : L("Opponent uses leader"), p === op ? "notif_\(p.faction)" : nil)
        await leaderEffect(p, free: false)
        await endTurn(p)
    }
    func leaderEffect(_ p: Player, free: Bool) async {
        let o = p.opponent!
        func best(_ cs: [Card]) -> Card? { cs.max { self.aiCardValue($0) < self.aiCardValue($1) } }
        switch p.leaderAbility {
        case "foltest_king":
            let opts = p.deck.filter { $0.has("fog") || $0.has("rain") }
            if let t = await pickOne(p, L("Which weather card to play? Impenetrable Fog or Torrential Rain?"), opts, ai: { $0.first }) { p.deck.removeAll { $0 === t }; t.owner = p; await playWeather(t, by: p, row: nil) }
        case "eredin_king":
            let opts = p.deck.filter { $0.data.isWeather }
            if let t = await pickOne(p, L("Choose a weather card to play"), opts, ai: { $0.first }) { p.deck.removeAll { $0 === t }; t.owner = p; await playWeather(t, by: p, row: nil) }
        case "foltest_lord", "vilgefortz_sorcerer": await clearWeather()
        case "foltest_siegemaster": p.row(.siege).leaderHorn = true; sound("horn")
        case "francesca_beautiful": p.row(.ranged).leaderHorn = true; sound("horn")
        case "foltest_son": await rowScorch(o, .ranged)
        case "foltest_steelforged": await rowScorch(o, .siege)
        case "francesca_queen", "cosimo_malaspina": await rowScorch(o, .close)
        case "meve_princess", "carlo_varese":
            recalc()
            if let r = RowType.allCases.filter({ o.row($0).total >= 10 }).max(by: { o.row($0).total < o.row($1).total }) { await rowScorch(o, r) }
        case "emhyr_imperial":
            let opts = o.grave.filter { $0.isUnit && !$0.hero }
            if let t = await pickOne(p, L("Which card to draw?"), opts, ai: best) { o.grave.removeAll { $0 === t }; resetCard(t); t.owner = p; p.hand.append(t) }
            if let back = await pickOne(p, L("Which card to put back into the deck?"), p.hand, ai: { cs in cs.min { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                p.hand.removeAll { $0 === back }; p.deck.append(back)
            }
        case "emhyr_emperor":
            let four = Array(o.hand.shuffled().prefix(4))
            if let t = await pickOne(p, L("Which card should your opponent play on the next round?"), four, ai: { cs in cs.min { self.aiCardValue($0) < self.aiCardValue($1) } }) { o.forcedCard = t }
        case "emhyr_relentless":
            if let t = await pickOne(p, L("Which card to destroy?"), p.rowCards, ai: { cs in cs.min { $0.power < $1.power } }) { await destroy(t, side: p) }
            let opts = p.deck.filter { $0.has("spy") || $0.has("emissary") }
            if let t = await pickOne(p, L("Which Spy/Emissary card to draw?"), opts, ai: { $0.first }) { p.deck.removeAll { $0 === t }; p.hand.append(t) }
        case "emhyr_invader":
            for q in [p, o] {
                let opts = q.grave.filter { $0.isUnit }
                let t = q === p ? await pickOne(p, L("Which card to restore from your grave?"), opts, ai: best) : opts.randomElement()
                if let t = t { q.grave.removeAll { $0 === t }; resetCard(t); await placeUnit(t, by: q, row: t.allowedRows.first ?? .close, side: q) }
            }
        case "eredin_commander":
            let picks = await pickCards(p, L("Choose on your battlefield two or less unit and/or hero cards and take them into your hand."), p.rowCards, min: 0, max: 2) { cs in Array(cs.filter { $0.has("spy") || $0.has("medic") }.prefix(2)) }
            for t in picks { if let r = p.rowOf(t) { p.row(r).cards.removeAll { $0 === t } }; resetCard(t); p.hand.append(t) }
        case "eredin_bringer_of_death":
            if let t = await pickOne(p, L("Which card to restore from your grave?"), p.grave.filter { $0.isUnit }, ai: best) { p.grave.removeAll { $0 === t }; resetCard(t); p.hand.append(t) }
        case "eredin_destroyer":
            let disc = await pickCards(p, L("Which card to discard?"), p.hand, min: min(2, p.hand.count), max: 2) { cs in Array(cs.sorted { self.aiCardValue($0) < self.aiCardValue($1) }.prefix(2)) }
            for t in disc { p.hand.removeAll { $0 === t }; p.grave.append(t) }
            if let t = await pickOne(p, L("Which card to draw?"), p.deck, ai: best) { p.deck.removeAll { $0 === t }; p.hand.append(t) }
        case "francesca_pureblood", "francesca_hope":
            let target = p.leaderAbility == "francesca_pureblood" ? o : p
            let n = p.leaderAbility == "francesca_pureblood" ? 3 : 4
            let picks = await pickCards(p, gd.abilityDesc(p.leaderAbility), target.rowCards.filter { !$0.hero }, min: 0, max: n) { cs in Array(cs.prefix(n)) }
            for t in picks {
                guard let from = target.rowOf(t) else { continue }
                let dests = RowType.allCases.filter { $0 != from }.map { (target, $0) }
                if let (_, d) = await pickRow(p, gd.cardName(t.data), dests, ai: { target === o ? (o.weather[dests[0].1.rawValue].isEmpty ? 1 : 0) : 0 }) {
                    target.row(from).cards.removeAll { $0 === t }; target.row(d).cards.append(t)
                }
            }
        case "crach_an_craite":
            let keep = await pickOne(p, L("Would you like to select a card to keep in your graveyard?"), p.grave, cancel: true, ai: { _ in nil })
            for q in [p, o] {
                for c in q.grave where c !== keep { resetCard(c); q.deck.append(c) }
                q.grave = keep != nil && q === p ? [keep!] : []
                q.deck.shuffle()
            }
        case "birna":
            let opts = p.deck.filter { $0.has("mardroeme") || $0.has("berserker") }
            if let t = await pickOne(p, gd.abilityDesc("birna"), opts, ai: best) {
                p.deck.removeAll { $0 === t }
                if t.isUnit { await placeUnit(t, by: p, row: t.allowedRows.first ?? .close) } else { p.hand.append(t) }
            }
        case "holger_blakhand":
            let opts = (p.rowCards + o.rowCards).filter { !$0.hero }
            if let t = await pickOne(p, L("Change the strength of a card?"), opts, ai: { cs in cs.filter { $0.owner === p }.min { $0.power < $1.power } ?? cs.first }) {
                let v = await pickOption(p, L("Select a new base power"), (1...10).map { "\($0)" }) { (t.owner === p) ? 9 : 0 }
                t.tempStrength = v + 1; t.flash = 1
            }
        case "radovid_king_redania", "nibras":
            let three = Array(p.deck.filter { !$0.data.isSpecial && !$0.data.isWeather && !$0.has("spy") && !$0.has("emissary") && !$0.has("ofiri_envoy") }.prefix(3))
            if let t = await pickOne(p, L("Choose a unit to play immediately"), three, ai: best) {
                p.deck.removeAll { $0 === t }
                if t.isUnit { await placeUnit(t, by: p, row: t.allowedRows.first ?? .close) }
                p.deck.shuffle()
            }
        case "radovid_mad_king":
            recalc()
            let all = (p.rowCards + o.rowCards)
            if let mx = all.map({ $0.power }).max() {
                let cands = all.filter { $0.power == mx }
                if let t = await pickOne(p, L("Choose the card to destroy"), cands, ai: { cs in cs.first { $0.owner === o } ?? cs.first }) { await destroy(t, side: o.rowCards.contains { $0 === t } ? o : p) }
            }
        case "radovid_strategist":
            if let t = await pickOne(p, L("Choose the hero to take back into your hand"), p.rowCards.filter { $0.hero }, ai: best) { if let r = p.rowOf(t) { p.row(r).cards.removeAll { $0 === t } }; p.hand.append(t) }
        case "anna_henrietta_duchess":
            if let t = await pickOne(p, L("Choose the hero to play"), p.grave.filter { $0.hero && $0.isUnit }, ai: best) { p.grave.removeAll { $0 === t }; await placeUnit(t, by: p, row: t.allowedRows.first ?? .close) }
        case "anna_henrietta_ladyship":
            let opts = (p.rowCards + o.rowCards).filter { $0.revertTo != nil }
            if let t = await pickOne(p, L("Choose the monster to revert to its primal form."), opts, ai: { $0.first }), let k = t.revertTo, let d = gd.cards[k] { t.transform(into: d); t.revertTo = nil }
        case "anna_henrietta_little_weasel":
            if let t = await pickOne(p, L("Choose the enemy hero to demote."), o.rowCards.filter { $0.hero }, ai: best) { t.heroOverride = false; t.flash = 1 }
        case "lady_wood_whispess":
            let opts = p.grave.filter { $0.isUnit && $0.diedRound == round }
            let picks = await pickCards(p, gd.abilityDesc("lady_wood_whispess"), opts, min: 0, max: 3) { cs in Array(cs.sorted { self.aiCardValue($0) > self.aiCardValue($1) }.prefix(3)) }
            for t in picks { p.grave.removeAll { $0 === t }; p.hand.append(t) }
        case "lady_wood_weavess":
            if let t = p.deck.first(where: { $0.specialKind == "curse" }) {
                p.deck.removeAll { $0 === t }; t.owner = p
                if let (q, r) = await pickRow(p, gd.abilityName("curse"), curseRows(by: p), ai: { 3 }) { q.row(r).curse = t }
            }
        case "ghost_tree":
            recalc()
            let all = (p.rowCards + o.rowCards).filter { !$0.hero }
            if let mn = all.map({ $0.power }).min() {
                let cands = all.filter { $0.power == mn }
                if let t = await pickOne(p, L("Choose which enemy card to destroy"), cands, ai: { cs in cs.first { $0.owner === o } ?? cs.first }) { await destroy(t, side: o.rowCards.contains { $0 === t } ? o : p) }
            }
        case "auberon_king":
            let navs = (p.deck + p.grave).filter { $0.has("door_o") }
            let picks = await pickCards(p, gd.abilityDesc("auberon_king"), navs, min: 0, max: navs.count) { $0 }
            for t in picks { p.deck.removeAll { $0 === t }; p.grave.removeAll { $0 === t }; p.hand.append(t) }
            if !picks.isEmpty {
                let back = await pickCards(p, L("Which card to put back into the deck?"), p.hand.filter { c in !picks.contains { $0 === c } }, min: picks.count, max: picks.count) { cs in Array(cs.sorted { self.aiCardValue($0) < self.aiCardValue($1) }.prefix(picks.count)) }
                for t in back { p.hand.removeAll { $0 === t }; p.deck.insert(t, at: Int.random(in: 0...p.deck.count)) }
            }
        case "winter_queen":
            let opts = p.deck.filter { $0.data.isSpecial || $0.data.isWeather }
            if let t = await pickOne(p, L("Choose a special card to play immediatly."), opts, ai: { $0.first }) {
                p.deck.removeAll { $0 === t }; t.owner = p
                if t.data.isWeather { await playWeather(t, by: p, row: nil) } else { await playSpecial(t, by: p, row: nil, rowOwner: nil, target: nil) }
            }
        case "alzur_maker":
            if let t = await pickOne(p, gd.abilityDesc("alzur_maker"), p.rowCards.filter { !$0.hero }, ai: { cs in cs.min { $0.power < $1.power } }) {
                await destroy(t, side: p)
                if let d = gd.cards["wu_koshchey"] { await placeUnit(Card(d, owner: p), by: p, row: .close) }
            }
        case "cyprian_wiley": await seize(p, .close)
        case "francis_bedlam":
            for q in [p, o] { for c in q.rowCards where c.has("spy") || c.has("emissary") { await destroy(c, side: q) } }
        case "gudrun_bjornsdottir":
            let crew = (p.deck + p.hand + p.grave).filter { $0.key == "sy_flyndr_crew" }
            if crew.isEmpty, let d = gd.cards["sy_flyndr_crew"] { await placeUnit(Card(d, owner: p), by: p, row: .close) }
            for t in crew { p.deck.removeAll { $0 === t }; p.hand.removeAll { $0 === t }; p.grave.removeAll { $0 === t }; resetCard(t); await placeUnit(t, by: p, row: .close) }
        case "cyrus_hemmelfart":
            if let d = gd.cards["spe_dimeritium_shackles"], let (_, r) = await pickRow(p, gd.abilityDesc("cyrus_hemmelfart"), RowType.allCases.map { (o, $0) }, ai: { Int.random(in: 0..<3) }) {
                o.row(r).lock = Card(d, owner: p)
            }
        case "cyrus_hemmelfart1":
            if let d = gd.cards["nv_inquisitional_pyres"] { await placeUnit(Card(d, owner: p), by: p, row: .close) }
        case "azar_javed":
            recalc()
            if let t = o.rowCards.filter({ $0.hero }).min(by: { $0.power < $1.power }) { await destroy(t, side: o) }
        case "baal_zebuth":
            let picks = await pickCards(p, gd.abilityDesc("baal_zebuth"), o.grave, min: 0, max: 2) { cs in Array(cs.sorted { self.aiCardValue($0) > self.aiCardValue($1) }.prefix(2)) }
            for t in picks { o.grave.removeAll { $0 === t }; resetCard(t); o.deck.append(t) }
            o.deck.shuffle()
        case "rarog":
            if let t = p.grave.randomElement() {
                p.grave.removeAll { $0 === t }; resetCard(t); p.hand.append(t)
                for c in p.grave { resetCard(c); p.deck.append(c) }
                p.grave.removeAll(); p.deck.shuffle()
            }
        case "nibras_gale":
            let three = Array(o.deck.prefix(3))
            if let t = await pickOne(p, L("Choose a card to add to your hand (others will be discarded)"), three, ai: best) {
                o.deck.removeAll { x in three.contains { $0 === x } }
                t.owner = p; p.hand.append(t)
                for x in three where x !== t { o.grave.append(x) }
            }
        default: break
        }
        recalc()
    }

    func factionActive(_ p: Player) -> String? {
        switch p.faction {
        case "witcher_universe": return p.factionUsedRound ? nil : "skip_round"
        case "redania": return p.factionUsedGame ? nil : "skip_game"
        case "lyria_rivia": return p.factionUsedGame ? nil : "morale"
        case "ofir": return p.factionUsedGame || !p.deck.contains(where: { $0.data.isWeather }) ? nil : "weather"
        case "toussaint": return p.rowCards.contains(where: { $0.act("monster_toussaint") && $0.playedTurn < turn - 1 }) ? "transform" : nil
        default: return nil
        }
    }
    func humanFaction() {
        guard !busy, phase == .play, current === me, factionActive(me) != nil else { return }
        busy = true
        Task { @MainActor in await self.useFaction(self.me); self.busy = false }
    }
    func useFaction(_ p: Player) async {
        guard let f = factionActive(p), current === p else { return }
        switch f {
        case "skip_round":
            p.factionUsedRound = true
            note(L("Witcher Universe used its faction ability and skipped a turn"), "notif_witcher_universe")
        case "skip_game":
            p.factionUsedGame = true
            note(L("Redania used its faction ability and skipped a turn"), "notif_redania")
        case "morale":
            if let (_, r) = await pickRow(p, gd.factionDesc("lyria_rivia"), RowType.allCases.map { (p, $0) }, ai: { RowType.allCases.map { p.row($0).cards.count }.enumerated().max { $0.1 < $1.1 }!.0 }) {
                p.row(r).factionMorale += 1; p.factionUsedGame = true
                note(L("Lyria & Rivia ability used - Morale Boost effect applied to a row."), "notif_lyria_rivia"); sound("moral")
            }
        case "weather":
            let opts = p.deck.filter { $0.data.isWeather }
            if let t = await pickOne(p, L("Choose a weather card to play"), opts, ai: { $0.first }) {
                p.factionUsedGame = true; p.deck.removeAll { $0 === t }; t.owner = p
                await playWeather(t, by: p, row: nil)
                note(L("Ofir faction ability used - Weather card played from deck."), "notif_ofir")
            }
        case "transform":
            let opts = p.rowCards.filter { $0.act("monster_toussaint") && $0.playedTurn < turn - 1 }
            if let t = await pickOne(p, L("Choose which monster to transform."), opts, ai: best1), let k = t.data.targets.first, let d = gd.cards[k] {
                t.revertTo = t.key
                t.transform(into: d); t.playedTurn = turn
                sound("monster_toussaint")
                await unitAbilities(t, by: p, side: p, row: p.rowOf(t) ?? .close)
            }
        default: break
        }
        recalc()
        await endTurn(p)
    }
    private func best1(_ cs: [Card]) -> Card? { cs.max { aiCardValue($0) < aiCardValue($1) } }

    func recalc() {
        for p in [me, op] {
            let side = p.rowCards
            let inspires = side.filter { $0.act("inspire") }
            let maxInspire = inspires.map { $0.basePower }.max() ?? 0
            let whorshippers = side.filter { $0.act("whorshipper") }.count
            var schools: [String: Int] = [:]
            for c in side where !c.locked { if let s = c.school { schools[s, default: 0] += 1 } }
            for r in RowType.allCases {
                let row = p.row(r)
                let bondCounts = Dictionary(grouping: row.cards.filter { $0.act("bond") }, by: { $0.groupKey }).mapValues { $0.count }
                let morale = row.cards.filter { $0.act("morale") }.count + row.specials.filter { $0.specialKind == "morale" }.count + row.factionMorale
                let wine = row.specials.filter { $0.specialKind == "toussaint_wine" }.count + row.cards.filter { $0.act("toussaint_wine") }.count
                let horns = row.hornCount
                let w = p.weather[r.rawValue]
                var sum = 0
                for c in row.cards {
                    c.power = cardScore(c, r, p, bondCounts: bondCounts, morale: morale, wine: wine, horns: horns, weather: w,
                                        inspire: inspires.count > 1 ? maxInspire : nil, whorshippers: whorshippers, schools: schools)
                    sum += c.power
                }
                row.total = sum
            }
            p.total = p.rows.reduce(0) { $0 + $1.total } + p.aamadBonus
        }
    }
    func cardScore(_ c: Card, _ r: RowType, _ p: Player, bondCounts: [String: Int], morale: Int, wine: Int, horns: Int, weather w: Set<String>,
                   inspire: Int?, whorshippers: Int, schools: [String: Int]) -> Int {
        if c.key == "spe_decoy" { return 0 }
        var t = c.tempStrength ?? c.basePower
        if c.hero { return t * c.multiplier + c.bonus }
        if c.has("spy") || c.has("emissary") || c.has("ofiri_envoy") { t = Int(floor(spyMult * Double(t))) }
        if let ins = inspire, c.act("inspire") { t = ins }
        if let s = c.setTo { t = s }
        if !w.isEmpty {
            let immune = w.allSatisfy { ($0 == "fog" && c.has("fog_summoning")) || ($0 == "sandstorm" && c.has("sandstorm_immunity")) }
            if !immune {
                let limit = c.has("adaptive") ? 2 : 1
                t = p.halfWeather ? max(min(limit, t), t / 2) : min(limit, t)
            }
        }
        if c.act("bond"), let b = bondCounts[c.groupKey], b > 1 { t *= b }
        t += max(0, morale - (c.act("morale") ? 1 : 0))
        t += 2 * max(0, wine - (c.act("toussaint_wine") ? 1 : 0))
        if let s = c.school, !c.locked, let n = schools[s], n > 1 { t += (n - 1) * 2 }
        if c.act("whorshipped") && whorshippers > 0 { t += whorshippers * whorshipMult }
        if horns - (c.act("horn") ? 1 : 0) > 0 { t *= 2 }
        t = t * c.multiplier + c.bonus
        if r == .siege { t *= c.siegeMult }
        return t
    }

    func surrender() {
        guard phase != .over else { return }
        phase = .over; me.gems = 0; winner = op
        sound("game_lose")
        if choiceCont != nil { resolveChoice(nil) }
    }
    func aiCardValue(_ c: Card) -> Int {
        c.basePower + (c.hero ? 3 : 0) + (c.has("spy") ? 6 : 0) + (c.has("medic") ? 5 : 0) + (c.has("muster") ? 4 : 0) +
            (c.data.isSpecial || c.data.isWeather ? 4 : 0)
    }
}

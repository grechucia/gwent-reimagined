// Game rules: cards, rows, players, rounds, turns and every card / leader / faction ability.
import Foundation

/// Board row: close combat, ranged or siege.
enum RowType: Int, CaseIterable { case close = 0, ranged = 1, siege = 2
    /// Parses a row name from the card data.
    static func from(_ text: String) -> RowType? { ["close": .close, "ranged": .ranged, "siege": .siege][text] }
}

/// A card instance in a game, with its current power and state.
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
    /// Whether the card has an ability.
    func has(_ ability: String) -> Bool { data.abilities.contains(ability) }
    var activeAbilities: [String] { locked ? [] : data.abilities }
    /// Whether the card's ability is active (it is not locked).
    func act(_ ability: String) -> Bool { !locked && data.abilities.contains(ability) }
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
    /// Changes the card into another card (e.g. berserker transformation).
    func transform(into cardData: CardData) { data = cardData; baseOverride = nil; setTo = nil; flash = 1 }
    /// Clears per-round modifiers.
    func resetRoundState() { tempStrength = nil }
}

/// One row of a player's board side: cards, special slot and row effects.
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

/// A player: deck, hand, graveyard, rows, leader, lives and pass state.
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
        let gameData = GameData.shared!
        leader = Card(gameData.cards[deck.leader]!, owner: nil)
        leader.owner = self
        if leader.data.abilities.last == "holger_blakhand" { leaderUses = 2 }
        for (k, n) in deck.cards { if let d = gameData.cards[k] { for _ in 0..<max(1, n) { self.deck.append(Card(d, owner: self)) } } }
        self.deck.shuffle()
    }
    var rowCards: [Card] { rows.flatMap { $0.cards } }
    /// The given row of this player.
    func row(_ rowType: RowType) -> Row { rows[rowType.rawValue] }
    /// The row a card currently lies in.
    func rowOf(_ card: Card) -> RowType? { for r in RowType.allCases where rows[r.rawValue].cards.contains(where: { $0 === card }) { return r }; return nil }
    var leaderAbility: String { leader.data.abilities.last ?? "" }
}

/// Events the engine emits for the UI: notifications, sounds and animations.
enum GameEvent { case notify(String, icon: String?); case sound(String); case flash(Card); case anim(Card, String); case burn(Card); case coin(Bool) }

/// A decision the engine asks a player to make (cards, rows or options).
struct Choice {
    /// What kind of selection is requested.
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

/// The game: two players, rounds, turns and all rule logic.
@MainActor
final class Game {
    let human: Player, computer: Player
    var weatherCards: [Card] = []
    var current: Player
    var round = 1
    /// AI strength for the computer opponent: 0 = easy, 1 = normal, 2 = hard.
    var aiLevel = 1
    var turn = 0
    var history: [(human: Int, computer: Int, winner: Player?)] = []
    /// Current phase of the match.
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
    var gameData: GameData { GameData.shared }

    init(myDeck: DeckData, opDeck: DeckData) {
        human = Player(deck: myDeck, isAI: false)
        computer = Player(deck: opDeck, isAI: true)
        human.opponent = computer; computer.opponent = human
        current = human
        for player in [human, computer] { applyPassiveLeader(player) }
        for player in [human, computer] {
            if player.faction == "syndicate" { summonToBoard(player, key: "sy_sigi_reuven") }
            if player.leaderAbility == "ofir_aamad_crown" { summonToBoard(player, key: "ofir_ofieri_prince") }
            let hand = 10 + (player.faction == "wild_hunt" ? 1 : 0) + (player.leaderAbility == "francesca_daisy" ? 3 : 0)
            draw(player, hand, silent: true)
        }
        redrawsLeft = redrawCount(human)
        aiRedraw(computer)
        recalc()
    }
    /// How many cards a player may redraw at the start.
    private func redrawCount(_ player: Player) -> Int { 2 + (player.faction == "toussaint" ? 1 : 0) + (player.faction == "novigrad" ? 1 : 0) }
    /// Applies leader abilities that work passively.
    private func applyPassiveLeader(_ player: Player) {
        switch player.leaderAbility {
        case "eredin_treacherous": spyMult *= 2
        case "vilgefortz_magician_kovir": spyMult *= 0.5
        case "zerrikanterment": whorshipMult = 2
        case "meve_white_queen": medicPicks = 2
        case "imlerith_general": navigatorShield = true
        case "caranthir_navigator": maxDoors = 2
        default: break
        }
    }
    /// Puts a card with the given key directly on the board.
    private func summonToBoard(_ player: Player, key: String) {
        let c: Card
        if let i = player.deck.firstIndex(where: { $0.key == key }) { c = player.deck.remove(at: i) }
        else if let d = gameData.cards[key] { c = Card(d, owner: player) } else { return }
        c.owner = player
        player.row(c.allowedRows.first ?? .close).cards.append(c)
    }

    var showChoices = false
    /// Asks a player to choose; the AI answers automatically, the human through the UI.
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
    /// Called by the UI with the human's answer to the pending choice.
    func resolveChoice(_ r: [Int]?) {
        let k = choiceCont
        choice = nil; choiceCont = nil
        k?.resume(returning: r)
    }
    /// Asks a player to pick several cards.
    private func pickCards(_ p: Player, _ title: String, _ cards: [Card], min: Int = 1, max: Int = 1, cancel: Bool = false,
                           ai: @escaping ([Card]) -> [Card]) async -> [Card] {
        guard !cards.isEmpty else { return [] }
        let r = await choose(Choice(player: p, title: title, kind: .cards(cards, min: min, max: Swift.min(max, cards.count)), canCancel: cancel) {
            ai(cards).compactMap { c in cards.firstIndex { $0 === c } }
        }) ?? []
        return r.compactMap { $0 < cards.count ? cards[$0] : nil }
    }
    /// Asks a player to pick one card.
    private func pickOne(_ player: Player, _ title: String, _ cards: [Card], cancel: Bool = false, ai: @escaping ([Card]) -> Card?) async -> Card? {
        await pickCards(player, title, cards, max: 1, cancel: cancel) { cs in ai(cs).map { [$0] } ?? [] }.first
    }
    /// Asks a player to pick a row.
    private func pickRow(_ p: Player, _ title: String, _ rows: [(Player, RowType)], ai: @escaping () -> Int) async -> (Player, RowType)? {
        guard !rows.isEmpty else { return nil }
        if rows.count == 1 { return rows[0] }
        guard let i = await choose(Choice(player: p, title: title, kind: .rows(rows), canCancel: false) { [ai()] })?.first, i < rows.count else { return rows[0] }
        return rows[i]
    }
    /// Asks a player to pick one of several options.
    private func pickOption(_ p: Player, _ title: String, _ opts: [String], ai: @escaping () -> Int) async -> Int {
        (await choose(Choice(player: p, title: title, kind: .options(opts), canCancel: false) { [ai()] }))?.first ?? 0
    }
    /// Shows cards to the player (e.g. the opponent's hand).
    private func reveal(_ p: Player, _ title: String, _ cards: [Card]) async {
        guard !cards.isEmpty else { return }
        _ = await choose(Choice(player: p, title: title, kind: .reveal(cards), canCancel: true) { [] })
    }
    var paused = false
    /// Waits so the UI can show animations.
    func pause(_ s: Double) async {
        try? await Task.sleep(nanoseconds: UInt64((autoHuman ? s * 0.3 : s) * 1_000_000_000))
        while paused { try? await Task.sleep(nanoseconds: 100_000_000) }
    }
    static let animIcons: Set<String> = ["adaptive", "aerondight", "ambush", "bond", "chernobog", "clairvoyance", "clear", "comrade", "cull", "curse", "decoration",
        "doppler", "emissary", "goetia", "horn", "immortal", "invoke", "knockback", "lock", "mardroeme", "medic", "monster_toussaint", "morale", "morana",
        "muster", "necrophage", "ofiri_envoy", "omen", "perun", "resilience", "rune_call", "seize", "shield", "soothsayer", "spy", "stribog",
        "summon_one_of", "svarog", "trade", "triglav", "veles"]
    /// Animation name used for an ability.
    static func animName(_ ability: String) -> String? {
        if ability == "toussaint_wine" { return "wine" }
        if ability.hasPrefix("wish") { return "wish" }
        if ability == "witch_hunt" { return "execute" }
        if ability.hasPrefix("shield") { return "shield" }
        return animIcons.contains(ability) ? ability : nil
    }
    /// Plays a card animation, optionally waiting for it.
    func animate(_ card: Card, _ name: String, wait: Bool = true) async {
        guard let n = Game.animName(name) ?? (name == "hero" ? "hero" : nil) else { return }
        events.append(.anim(card, n))
        if wait { await pause(0.7) }
    }
    /// Shows a notification banner.
    func note(_ text: String, _ icon: String? = nil) { events.append(.notify(text, icon: icon)) }
    /// Plays a sound effect.
    func sound(_ text: String) { events.append(.sound(text)) }

    /// Draws `n` cards from the deck into the hand.
    func draw(_ player: Player, _ count: Int, silent: Bool = false) {
        for _ in 0..<count {
            guard !player.deck.isEmpty else { return }
            player.hand.append(player.deck.removeFirst())
            if player.leaderAbility == "ofir_aamad" && phase == .play { player.aamadBonus += 1 }
        }
        if !silent { recalc() }
    }
    /// Swaps a card in hand for a random card from the deck (redraw phase).
    func redraw(_ card: Card) -> Card? {
        guard phase == .redraw, redrawsLeft > 0, let i = human.hand.firstIndex(where: { $0 === card }), !human.deck.isEmpty else { return nil }
        let n = human.deck.removeFirst()
        human.hand[i] = n
        human.deck.insert(card, at: Int.random(in: 0...human.deck.count))
        redrawsLeft -= 1
        sound("redraw")
        return n
    }
    /// AI decision for the redraw phase.
    private func aiRedraw(_ player: Player) {
        if player.leaderAbility == "francesca_daisy" {
            for _ in 0..<2 { if let w = player.hand.min(by: { aiCardValue($0) < aiCardValue($1) }) { player.hand.removeAll { $0 === w }; player.deck.insert(w, at: Int.random(in: 0...player.deck.count)) } }
        }
        for _ in 0..<redrawCount(player) {
            let worst = player.hand.filter { $0.isUnit && !$0.hero && !$0.has("spy") && !$0.has("medic") && !$0.has("muster") && !$0.has("bond") }
                .min { $0.basePower < $1.basePower }
            guard let w = worst, w.basePower <= 3, !player.deck.isEmpty, let i = player.hand.firstIndex(where: { $0 === w }) else { return }
            player.hand[i] = player.deck.removeFirst()
            player.deck.insert(w, at: Int.random(in: 0...player.deck.count))
        }
    }
    /// Handles the Daisy of the Valley ability after the redraw.
    func daisyReturn() async {
        if human.leaderAbility == "francesca_daisy" {
            let back = await pickCards(human, L("Choose 2 cards to put back into your deck"), human.hand, min: 2, max: 2) { cs in Array(cs.sorted { self.aiCardValue($0) < self.aiCardValue($1) }.prefix(2)) }
            for c in back { human.hand.removeAll { $0 === c }; human.deck.insert(c, at: Int.random(in: 0...human.deck.count)) }
        }
    }
    /// Ends the redraw phase and starts the first round.
    func finishRedraw() {
        guard phase == .redraw, !busy else { return }
        busy = true
        Task { @MainActor in
            await self.daisyReturn()
            self.phase = .play
            self.current = Bool.random() ? self.human : self.computer
            self.sound("coin")
            self.events.append(.coin(self.current === self.human))
            await self.pause(1.6)
            self.note(self.current === self.human ? L("You will go first") : L("Your opponent will go first"), self.current === self.human ? "notif_me_coin" : "notif_op_coin")
            await self.startRound()
            self.busy = false
        }
    }

    /// Starts a round: faction bonuses, who goes first, turn loop.
    private func startRound() async {
        turn += 1
        for player in [human, computer] {
            player.aamadBonus = 0; player.comradeUsedRound = false; player.factionUsedRound = false; player.fleetDrawsRound = 0; player.halfWeather = false
        }
        note(L("Round Start") + " · \(round)", "notif_round_start")
        sound(round == 1 ? "round1_start" : "round_win")
        if round > 1 {
            for player in [human, computer] {
                if player.faction == "realms" && lastRoundWinner !== player { draw(player, 1); note(L("Northern Realms faction ability triggered - North draws an additional card."), "notif_north") }
                if player.faction == "zerrikania" && lastRoundWinner === player.opponent {
                    let opts = player.grave.filter { $0.isUnit }
                    if let c = await pickOne(player, L("Which card to restore from your grave?"), opts, cancel: true, ai: { cs in cs.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                        player.grave.removeAll { $0 === c }
                        await placeUnit(c, by: player, row: c.allowedRows.first ?? .close)
                        note(L("Zerrikania ability used - Unit restored from discard pile."), "notif_zerrikania")
                    }
                }
                if player.faction == "skellige" && round == 3 {
                    let opts = player.grave.filter { $0.isUnit }.shuffled().prefix(2)
                    for c in opts { player.grave.removeAll { $0 === c }; await placeUnit(c, by: player, row: c.allowedRows.randomElement() ?? .close) }
                    if !opts.isEmpty { note(player === human ? L("Skellige Ability Triggered!") : L("Opponent Skellige Ability Triggered!"), "notif_skellige") }
                }
            }
        }
        for player in [human, computer] where player.faction == "wild_hunt" {
            let leaders = gameData.cards.values.filter { $0.isLeader && $0.key.hasPrefix("wh_") }.sorted { $0.key < $1.key }
            let cards = leaders.map { Card($0, owner: player) }
            if let c = await pickOne(player, L("Select the next leader to start the round with"), cards, ai: { cs in cs.randomElement() }) {
                player.leader = c; player.leaderUses = 1; applyPassiveLeader(player)
            }
        }
        for player in [human, computer] {
            if player.leaderAbility == "king_bran", player.leaderUses > 0 {
                let yes = await pickOption(player, L("Bring the Skellige Storm?"), [L("Bring the Storm [E]"), L("Maybe later [Q]")]) { (self.round > 1 || player.deck.contains { $0.has("storm") }) ? 0 : 1 }
                if yes == 0 { player.leaderUses = 0; player.halfWeather = true
                    if let s = player.deck.first(where: { $0.has("storm") }) { player.deck.removeAll { $0 === s }; player.hand.append(s) } }
            }
            if player.leaderAbility == "madman_lugos", player.leaderUses > 0, player.opponent.hand.count >= 2 {
                let yes = await pickOption(player, L("Discard a card from the hand of the opponent?"), [L("Discard a card [E]"), L("Maybe later [Q]")]) { self.round >= 2 ? 0 : 1 }
                if yes == 0 {
                    player.leaderUses = 0
                    let two = Array(player.opponent.hand.shuffled().prefix(2))
                    if let c = await pickOne(player, L("Which card to discard?"), two, ai: { cs in cs.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                        player.opponent.hand.removeAll { $0 === c }; player.opponent.grave.append(c)
                    }
                }
            }
        }
        for player in [human, computer] where player.faction == "scoiatael" {
            let i = await pickOption(player, L("Who should go first?"), [L("Go First [E]"), L("Let Opponent Start [Q]")]) { 1 }
            current = i == 0 ? player : player.opponent
            if player === computer { note(L("Opponent used the Scoia'tael faction perk to go first."), "notif_scoiatael") }
            break
        }
        await beginTurn()
    }

    /// Starts the current player's turn.
    private func beginTurn() async {
        recalc()
        if human.passed && computer.passed { await endRound(); return }
        if current.passed { current = current.opponent }
        if current.hand.isEmpty && !current.passed && !canActWithoutCards(current) { await pass(current); return }
        if current === human { note(L("Your turn!"), "notif_me_turn"); sound("turn_me") } else { sound("turn_op") }
    }
    /// Whether a player can still act without cards in hand.
    private func canActWithoutCards(_ player: Player) -> Bool { leaderAvailable(player) || factionActive(player) != nil }

    /// The player passes for the rest of the round.
    func pass(_ player: Player) async {
        guard phase == .play, !player.passed else { return }
        player.passed = true
        sound("pass")
        note(player === human ? L("Round passed") : L("Your opponent has passed"), "notif_round_passed")
        if player === current { current = player.opponent }
        await beginTurn()
    }

    /// Ends a turn and gives control to the other player.
    private func endTurn(_ player: Player) async {
        recalc()
        let doors = RowType.allCases.filter { player.row($0).door }
        if !doors.isEmpty, let top = player.deck.first {
            player.deck.removeFirst()
            if top.isUnit, let r = doors.first(where: { top.allowedRows.contains($0) }) {
                await placeUnit(top, by: player, row: r)
            } else if !top.isUnit {
                player.hand.append(top)
            } else { player.deck.insert(top, at: Int.random(in: 0...player.deck.count)) }
        }
        for q in [player, player.opponent!] where q.faction == "velen" && q.lostUnitThisTurn {
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
        if !player.opponent.passed { current = player.opponent }
        await beginTurn()
    }

    /// Scores the round, removes a life from the loser and checks for the end of the match.
    private func endRound() async {
        phase = .roundEnd
        recalc()
        for player in [human, computer] where player.faction == "monsters" && !player.monstersUsed && !player.rowCards.isEmpty {
            let yes = await pickOption(player, L("Would you like to retake one of your cards?"), [L("Retake a card [E]"), L("Not yet [Q]")]) { self.round >= 2 ? 0 : 1 }
            if yes == 0, let c = await pickOne(player, L("Which card to retake?"), player.rowCards, ai: { cs in cs.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                player.monstersUsed = true
                if let r = player.rowOf(c) { player.row(r).cards.removeAll { $0 === c } }
                resetCard(c); player.hand.append(c)
                note(L("Monsters faction ability triggered - monsters retake one card to their hand"), "notif_monsters")
            }
        }
        recalc()
        let a = human.total, b = computer.total
        var w: Player? = a > b ? human : (b > a ? computer : nil)
        if w == nil {
            let nm = human.faction == "nilfgaard", no = computer.faction == "nilfgaard"
            if nm != no { w = nm ? human : computer; note(L("Nilfgaard wins draws"), "notif_nilfgaard") }
        }
        history.append((a, b, w))
        lastRoundWinner = w
        if let w = w { w.opponent.gems -= 1 } else { human.gems -= 1; computer.gems -= 1 }
        if w === human { note(L("You won the round!"), "notif_win_round"); sound("round_win") }
        else if w === computer { note(L("Your opponent won the round"), "notif_lose_round"); sound("round_lose") }
        else { note(L("The round ended in a draw"), "notif_draw_round") }
        await cleanupRound()
        if human.gems <= 0 || computer.gems <= 0 || round >= 3 {
            phase = .over
            winner = human.gems > computer.gems ? human : (computer.gems > human.gems ? computer : nil)
            sound(winner === human ? "game_win" : "game_lose")
            recalc()
            return
        }
        round += 1
        human.passed = false; computer.passed = false
        current = w ?? current
        phase = .play
        await startRound()
    }

    /// Returns a card to its base state when it leaves the board.
    private func resetCard(_ card: Card) {
        card.locked = false; card.setTo = nil; card.tempStrength = nil; card.multiplier = 1; card.bonus = 0; card.siegeMult = 1
        card.baseOverride = nil; card.heroOverride = nil; card.keepNextRound = false
    }
    /// Clears the board after a round, keeping cards that stay.
    private func cleanupRound() async {
        var avengers: [(Card, Player, RowType)] = []
        for player in [human, computer] {
            for c in player.rowCards where c.act("resilience") {
                let key = c.data.abilities.last ?? ""
                if player.rowCards.filter({ $0 !== c && $0.data.abilities.contains(key) }).count >= 1 { c.keepNextRound = true }
            }
        }
        for player in [human, computer] {
            for r in RowType.allCases {
                let row = player.row(r)
                var stay: [Card] = []
                for card in row.cards {
                    if card.immortalRounds > 1 { card.immortalRounds -= 1; stay.append(card); continue }
                    if card.keepNextRound { card.keepNextRound = false; stay.append(card); continue }
                    if card.data.abilities.contains(where: { $0.hasPrefix("avenger") }) && !card.locked { avengers.append((card, player, r)) }
                    resetCard(card); card.diedRound = round
                    (card.owner ?? player).grave.append(card)
                }
                row.cards = stay
                for s in row.specials { (s.owner ?? player).grave.append(s) }
                row.specials.removeAll(); row.lock = nil; row.curse = nil; row.ambush = nil; row.door = false; row.leaderHorn = false; row.factionMorale = 0
                player.weather[r.rawValue].removeAll()
            }
            for card in player.hand + player.deck { card.tempStrength = nil }
            player.forcedCard = nil
        }
        for card in weatherCards { (card.owner ?? human).grave.append(card) }
        weatherCards.removeAll()
        for player in [human, computer] where player.fleetPending > 0 { draw(player, player.fleetPending); player.fleetPending = 0 }
        if round < 3 {
            for (card, player, r) in avengers {
                for t in card.data.targets {
                    guard let d = gameData.cards[t], d.isUnit else { continue }
                    if let i = player.deck.firstIndex(where: { $0.key == t }) { let n = player.deck.remove(at: i); player.row(RowType.from(d.row) ?? r).cards.append(n); n.flash = 1 }
                    else { let n = Card(d, owner: player); player.row(RowType.from(d.row) ?? r).cards.append(n); n.flash = 1 }
                }
            }
        }
        recalc()
    }

    /// Rows where a card may be played.
    func validRows(for card: Card, by player: Player) -> [RowType] {
        if card.isUnit {
            if card.act("ambush") || card.has("ambush") { return RowType.allCases }
            return card.allowedRows
        }
        switch card.specialKind ?? "" {
        case "horn", "mardroeme", "morale": return RowType.allCases.filter { r in !player.row(r).specials.contains { $0.specialKind == card.specialKind } }
        case "toussaint_wine": return [.close, .ranged].filter { !player.row($0).specials.contains { $0.specialKind == "toussaint_wine" } }
        case "shield": return RowType.allCases.filter { !player.row($0).shielded }
        case "shield_c": return [.close]
        case "shield_r": return [.ranged]
        case "shield_s": return [.siege]
        case "door": return RowType.allCases.filter { !player.row($0).door }
        default: return []
        }
    }
    /// Enemy rows a card may target.
    func enemyRowTargets(for card: Card, by player: Player) -> [RowType] {
        switch card.specialKind ?? "" {
        case "lock": return RowType.allCases.filter { player.opponent.row($0).lock == nil }
        case "knockback": return [.close, .ranged]
        default: return []
        }
    }
    /// Rows that can receive a curse.
    func curseRows(by player: Player) -> [(Player, RowType)] {
        [player, player.opponent].flatMap { q in RowType.allCases.filter { q.row($0).curse == nil }.map { (q, $0) } }
    }
    /// Cards that a decoy can swap with.
    func decoyTargets(for player: Player) -> [Card] { player.rowCards.filter { !$0.hero && $0.key != "spe_decoy" && $0.immortalRounds == 0 } }

    /// The human plays a card.
    func humanPlay(_ card: Card, row: RowType? = nil, rowOwner: Player? = nil, target: Card? = nil) {
        guard !busy, phase == .play, current === human, human.hand.contains(where: { $0 === card }) else { return }
        busy = true
        Task { @MainActor in await self.play(card, by: self.human, row: row, rowOwner: rowOwner, target: target); self.busy = false }
    }
    /// The human passes.
    func humanPass() { guard !busy, phase == .play, current === human else { return }; busy = true; Task { @MainActor in await self.pass(self.human); self.busy = false } }

    /// Plays a unit, special or weather card for a player.
    func play(_ card: Card, by player: Player, row: RowType? = nil, rowOwner: Player? = nil, target: Card? = nil) async {
        guard phase == .play, current === player, let hi = player.hand.firstIndex(where: { $0 === card }) else { return }
        if let f = player.forcedCard, f !== card, player.hand.contains(where: { $0 === f }) { return }
        player.forcedCard = nil
        player.hand.remove(at: hi)
        card.owner = player
        card.flash = 1
        if card.data.isWeather { await playWeather(card, by: player, row: row) }
        else if card.data.isSpecial { await playSpecial(card, by: player, row: row, rowOwner: rowOwner, target: target) }
        else { await placeUnit(card, by: player, row: row ?? card.allowedRows.first ?? .close) }
        await endTurn(player)
    }

    /// Places a unit on a row and triggers its abilities.
    func placeUnit(_ card: Card, by player: Player, row requestedRow: RowType, side forcedSide: Player? = nil) async {
        var r = requestedRow
        let isSpy = card.has("spy") || card.has("emissary") || card.has("ofiri_envoy")
        let side: Player = forcedSide ?? (isSpy ? player.opponent : player)
        if !card.isUnit { player.hand.append(card); return }
        if !card.data.row.hasPrefix("agile") && !card.has("ambush"), let fixed = RowType.from(card.data.row) { r = fixed }
        card.owner = player
        card.playedTurn = turn
        let row = side.row(r)
        if let curse = row.curse, !card.hero {
            row.curse = nil; (curse.owner ?? player).grave.append(curse)
            side.grave.append(card); card.diedRound = round
            note(gameData.abilityName("curse")); sound("curse")
            return
        }
        row.cards.append(card)
        card.flash = 1
        sound(card.hero ? "hero" : "card")
        if let lk = row.lock, !card.hero, !card.data.abilities.filter({ $0 != "hero" }).isEmpty {
            card.locked = true; row.lock = nil; (lk.owner ?? player).grave.append(lk); sound("lock"); events.append(.anim(card, "lock"))
        }
        if let amb = side.opponent.row(r).cards.first(where: { $0.act("ambush") && $0.owner === side.opponent }), side === player {
            let o = side.opponent!
            o.row(r).cards.removeAll { $0 === amb }; o.grave.append(amb)
            draw(o, 2); sound("ambush")
        }
        if isSpy && side.leaderAbility == "novigrad_sigismund2" { draw(side, 1) }
        recalc()
        await pause(0.3)
        if card.hero { events.append(.anim(card, "hero")) }
        if card.locked { await animate(card, "lock"); return }
        if card.act("bond") {
            let group = row.cards.filter { $0.act("bond") && $0.groupKey == card.groupKey }
            if group.count > 1 { for g in group { await animate(g, "bond", wait: false) }; await pause(0.7) }
        } else if let a = card.data.abilities.reversed().first(where: { Game.animName($0) != nil }) {
            await animate(card, a)
        } else if card.hero { await pause(0.6) }
        await unitAbilities(card, by: player, side: side, row: r)
        recalc()
    }

    /// Resolves the abilities of a unit that was just placed.
    private func unitAbilities(_ card: Card, by player: Player, side: Player, row rowType: RowType) async {
        let o = player.opponent!
        for a in card.data.abilities {
            switch a {
            case "spy":
                if player.faction == "toussaint" {
                    let three = Array(player.deck.prefix(3))
                    if let k = await pickOne(player, L("Choose the card to draw and keep"), three, ai: { cs in cs.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                        player.deck.removeAll { $0 === k }; player.hand.append(k); player.deck.shuffle()
                    }
                } else { await spyDraw(player, 2) }
                sound("spy")
            case "emissary":
                let i = await pickOption(player, L("Choose the effect of the emissary"), [L("Draw 1 card [E]"), L("Look first 4 cards [Q]")]) { 0 }
                if i == 0 { await spyDraw(player, 1) } else { await reorderTop(player, 4) }
                sound("emissary")
            case "ofiri_envoy":
                let i = player.drawOpponentLeft > 0 && !o.deck.isEmpty
                    ? await pickOption(player, L("From which deck to draw the next card? (Ofiri Envoy can draw from opponent's deck only once)"), [L("Own deck [E]"), L("Opponent's deck [Q]")]) { 0 } : 0
                if i == 1 { player.drawOpponentLeft = 0; if let t = o.deck.first { o.deck.removeFirst(); t.owner = player; player.hand.append(t) }; draw(player, 1) } else { draw(player, 2) }
                sound("ofiri_envoy")
            case "medic": await medic(player)
            case "muster": await muster(card, player, rowType)
            case "invoke":
                let opts = player.deck.filter { card.data.targets.contains($0.key) || ($0.groupKey == card.groupKey && $0 !== card && !card.data.target.isEmpty) }
                if let t = await pickOne(player, L("Choose one card to play."), opts, ai: { $0.first }) { player.deck.removeAll { $0 === t }; await placeUnit(t, by: player, row: t.allowedRows.first ?? rowType); sound("invoke") }
            case "summon_one_of":
                let opts = (player.deck + player.hand + player.grave).filter { card.data.targets.contains($0.key) }
                if let t = await pickOne(player, L("Choose one card to play."), opts, ai: { cs in cs.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                    player.deck.removeAll { $0 === t }; player.hand.removeAll { $0 === t }; player.grave.removeAll { $0 === t }
                    await placeUnit(t, by: player, row: t.allowedRows.first ?? rowType)
                }
            case "scorch_c", "scorch_r", "scorch_s":
                let t: RowType = a == "scorch_c" ? .close : (a == "scorch_r" ? .ranged : .siege)
                await rowScorch(o, t)
            case "scorch": await scorch(except: card)
            case "cull": await cull(except: card)
            case "mardroeme": await berserk(side, rowType)
            case "berserker": if side.row(rowType).specials.contains(where: { $0.specialKind == "mardroeme" }) || side.row(rowType).cards.contains(where: { $0.act("mardroeme") }) { await berserk(side, rowType) }
            case "witch_hunt":
                let opp = o.row(rowType)
                if opp.shielded { break }
                let units = opp.cards.filter { !$0.hero && $0.immortalRounds == 0 }
                if let mn = units.map({ $0.power }).min() {
                    let cands = units.filter { $0.power == mn }
                    if let t = await pickOne(player, L("Choose which enemy card to destroy"), cands, ai: { $0.first }) { await destroy(t, side: o) }
                }
            case "necrophage":
                let opts = player.grave.filter { $0.isUnit }
                let picks = await pickCards(player, L("Choose up to 2 cards to take from your grave back to your deck."), opts, min: 0, max: 2, cancel: true) { cs in Array(cs.sorted { self.aiCardValue($0) > self.aiCardValue($1) }.prefix(2)) }
                for x in picks { player.grave.removeAll { $0 === x }; resetCard(x); player.deck.insert(x, at: Int.random(in: 0...player.deck.count)) }
            case "goetia":
                if let d = await pickOne(player, L("Choose a card to draw from your deck."), player.deck, ai: { cs in cs.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                    player.deck.removeAll { $0 === d }; player.hand.append(d)
                    if let back = await pickOne(player, L("Which card to put back into your deck?"), player.hand, ai: { cs in cs.min { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                        player.hand.removeAll { $0 === back }; player.deck.insert(back, at: Int.random(in: 0...player.deck.count))
                    }
                }
            case "sage": await reorderTop(player, 4)
            case "zirael":
                let five = Array(player.deck.prefix(5))
                let picks = await pickCards(player, L("Choose up to 2 cards to draw and keep in your hand"), five, min: 0, max: 2) { cs in Array(cs.sorted { self.aiCardValue($0) > self.aiCardValue($1) }.prefix(2)) }
                for x in picks { player.deck.removeAll { $0 === x }; player.hand.append(x) }
                player.deck.shuffle()
            case "naglfar":
                let opts = player.deck.filter { $0.data.name.contains("Naglfar") && $0.isUnit }
                let picks = await pickCards(player, L("Choose up to 2 cards to play right away."), opts, min: 0, max: 2) { cs in Array(cs.prefix(2)) }
                for x in picks { player.deck.removeAll { $0 === x }; await placeUnit(x, by: player, row: x.allowedRows.first ?? .siege) }
            case "bait":
                let opts = player.deck.filter { $0.has("bond") }
                if let t = await pickOne(player, L("Choose one card to play."), opts, ai: { cs in cs.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                    player.deck.removeAll { $0 === t }; await placeUnit(t, by: player, row: t.allowedRows.first ?? rowType)
                }
            case "clairvoyance":
                let i = await pickOption(player, L("Clairvoyance Options"), [L("View Deck [E]"), L("Spy Enemy [Q]")]) { 1 }
                if i == 0 { await reveal(player, L("Clairvoyance: Top 3 cards of your deck (click to close)"), Array(player.deck.prefix(3))) }
                else { await reveal(player, L("Clairvoyance: 3 random cards of enemy hand (click to close)"), Array(o.hand.shuffled().prefix(3))) }
            case "trade":
                if let t = await pickOne(player, L("Select a card from the opponent's deck to buy."), o.deck, ai: { cs in cs.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                    o.deck.removeAll { $0 === t }; t.owner = player; player.hand.append(t)
                    if let rune = player.deck.first(where: { $0.key.hasPrefix("ofir_") && $0.data.isSpecial }) { player.deck.removeAll { $0 === rune }; rune.owner = o; o.hand.append(rune) }
                    sound("trade")
                }
            case "rune_call":
                let opts = player.deck.filter { $0.key.hasPrefix("ofir_") && $0.data.isSpecial }
                if let t = await pickOne(player, L("Choose 1 runestone from your deck to add to your hand."), opts, ai: { $0.randomElement() }) { player.deck.removeAll { $0 === t }; player.hand.append(t) }
            case "omen":
                if let d = gameData.cards["nv_catanddog"] { player.hand.append(Card(d, owner: player)) }
            case "wish1", "wish2", "wish3":
                await djinnWish(a, card, player)
            case "doppler":
                let opts = o.row(rowType).cards.filter { !$0.hero && $0.isUnit }
                if let t = await pickOne(player, L("Choose an enemy unit from the opposite row to transform Doppler into."), opts, ai: { cs in cs.max { $0.basePower < $1.basePower } }) {
                    card.baseOverride = t.basePower; sound("doppler"); await animate(card, "doppler")
                }
            case "aerondight":
                let opts = player.rowCards.filter { $0 !== card && !$0.hero }
                if let t = await pickOne(player, L("Choose which card to equip with Aerondight."), opts, ai: { cs in cs.max { $0.basePower < $1.basePower } }) {
                    if let tr = player.rowOf(t) { player.row(tr).cards.removeAll { $0 === t } }
                    player.row(.siege).cards.append(t); t.siegeMult = 3
                }
            case "immortal": card.immortalRounds = 2
            case "toussaint_wine": break
            default: break
            }
        }
    }

    /// Spy: the player draws cards.
    private func spyDraw(_ player: Player, _ count: Int) async {
        let o = player.opponent!
        for _ in 0..<count {
            if player.leaderAbility == "emhyr_whiteflame" && player.drawOpponentLeft > 0 && !o.deck.isEmpty {
                let i = await pickOption(player, L("Choose deck to draw from"), [L("Own deck [E]"), L("Opponent's deck [Q]")]) { 1 }
                if i == 1, let t = o.deck.first { o.deck.removeFirst(); t.owner = player; player.hand.append(t); player.drawOpponentLeft -= 1; continue }
            }
            draw(player, 1)
        }
    }
    /// Lets the player reorder the top cards of the deck.
    private func reorderTop(_ player: Player, _ count: Int) async {
        let top = Array(player.deck.prefix(count))
        guard !top.isEmpty else { return }
        let order = await pickCards(player, L("Re-order the cards back into the deck"), top, min: top.count, max: top.count) { cs in cs.sorted { self.aiCardValue($0) > self.aiCardValue($1) } }
        player.deck.removeFirst(top.count)
        player.deck.insert(contentsOf: order.isEmpty ? top : order, at: 0)
    }
    /// Medic: revives a unit from the graveyard.
    private func medic(_ player: Player) async {
        sound("med")
        for _ in 0..<medicPicks {
            let opts = player.grave.filter { $0.isUnit && !$0.hero }
            guard let c = await pickOne(player, L("Which card to restore from your grave?"), opts, cancel: true, ai: { cs in cs.max { self.aiCardValue($0) < self.aiCardValue($1) } }) else { return }
            player.grave.removeAll { $0 === c }
            resetCard(c)
            await placeUnit(c, by: player, row: c.allowedRows.first ?? .close)
        }
    }
    /// Muster: plays every copy of the card from deck and hand.
    private func muster(_ card: Card, _ player: Player, _ rowType: RowType) async {
        let key = card.groupKey
        let fromHand = player.hand.filter { $0 !== card && $0.groupKey == key && $0.isUnit }
        let fromDeck = player.deck.filter { $0.groupKey == key && $0.isUnit }
        if fromHand.isEmpty && fromDeck.isEmpty { return }
        for m in fromHand + fromDeck {
            player.hand.removeAll { $0 === m }; player.deck.removeAll { $0 === m }
            let rowArea = card.data.row.hasPrefix("agile") ? rowType : (RowType.from(m.data.row) ?? m.allowedRows.first ?? rowType)
            m.owner = player; m.playedTurn = turn
            player.row(rowArea).cards.append(m); m.flash = 1
        }
        sound("ally")
        recalc()
    }
    /// Berserker: transforms berserkers on a row when mardroeme is present.
    private func berserk(_ side: Player, _ rowType: RowType) async {
        for c in side.row(rowType).cards where c.act("berserker") {
            if let t = c.data.targets.first, let d = gameData.cards[t] { c.transform(into: d); events.append(.anim(c, "mardroeme")) }
        }
        sound("mardroeme")
        recalc()
    }
    /// Djinn: grants one of the wishes.
    private func djinnWish(_ ability: String, _ card: Card, _ player: Player) async {
        let o = player.opponent!
        let minStr = ability == "wish3" ? 7 : 6
        let costs = player.rowCards.filter { $0 !== card && !$0.hero && $0.basePower >= minStr }
        guard let cost = costs.max(by: { $0.power < $1.power }) else { return }
        await destroy(cost, side: player)
        switch ability {
        case "wish1":
            let three = Array(o.hand.shuffled().prefix(3))
            if let t = await pickOne(player, L("The Djinn grants your wish: Choose 1 enemy card to steal."), three, ai: { cs in cs.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                o.hand.removeAll { $0 === t }; t.owner = player; player.hand.append(t)
            }
        case "wish2":
            let three = Array(player.deck.prefix(3))
            if let t = await pickOne(player, L("The Djinn grants your second wish: Choose 1 card from your deck to draw."), three, ai: { cs in cs.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                player.deck.removeAll { $0 === t }; player.hand.append(t)
            }
            card.immortalRounds = max(card.immortalRounds, 1)
        default:
            let opts = o.rowCards.filter { !$0.hero && $0.immortalRounds == 0 }
            if let t = await pickOne(player, L("The Djinn grants your third wish: Choose 1 enemy unit to destroy."), opts, ai: { cs in cs.max { $0.power < $1.power } }) { await destroy(t, side: o) }
            card.immortalRounds = max(card.immortalRounds, 1)
        }
    }

    /// Resolves a special (non-weather) card.
    private func playSpecial(_ card: Card, by player: Player, row: RowType?, rowOwner: Player?, target: Card?) async {
        let o = player.opponent!
        let kind = card.specialKind ?? ""
        switch kind {
        case "horn", "mardroeme", "morale", "toussaint_wine", "shield", "shield_c", "shield_r", "shield_s":
            var r = row
            if r == nil { r = await pickRow(player, L("Select a card on your side of the board."), validRows(for: card, by: player).map { (player, $0) }) { 0 }?.1 }
            guard let rowArea = r else { player.grave.append(card); return }
            player.row(rowArea).specials.append(card)
            await animate(card, kind)
            sound(kind == "horn" ? "horn" : (kind == "mardroeme" ? "mardroeme" : (kind.hasPrefix("shield") ? "shield" : "moral")))
            if kind == "mardroeme" { await berserk(player, rowArea) }
        case "door":
            var r = row
            if r == nil { r = await pickRow(player, L("Select a card on your side of the board."), validRows(for: card, by: player).map { (player, $0) }) { 0 }?.1 }
            let open = RowType.allCases.filter { player.row($0).door }
            if let rowArea = r, open.count < maxDoors { player.row(rowArea).door = true }
            player.grave.append(card); sound("door")
        case "decoy":
            if let t = target, let r = player.rowOf(t), let i = player.row(r).cards.firstIndex(where: { $0 === t }) {
                player.row(r).cards[i] = card
                resetCard(t); t.owner = player; player.hand.append(t)
                sound("decoy")
            } else { player.grave.append(card) }
        case "scorch": await scorch(except: nil); player.grave.append(card)
        case "cull": await cull(except: nil); player.grave.append(card)
        case "clear": await clearWeather(); player.grave.append(card)
        case "lock":
            var r = row
            if r == nil { r = await pickRow(player, L("Select a card on your side of the board."), enemyRowTargets(for: card, by: player).map { (o, $0) }) { Int.random(in: 0..<3) }?.1 }
            if let rowArea = r { o.row(rowArea).lock = card } else { player.grave.append(card) }
            sound("lock")
        case "curse":
            var dest: (Player, RowType)? = rowOwner.flatMap { q in row.map { (q, $0) } }
            if dest == nil { dest = await pickRow(player, gameData.abilityName("curse"), curseRows(by: player)) { 3 + Int.random(in: 0..<3) } }
            if let (q, rowArea) = dest { q.row(rowArea).curse = card } else { player.grave.append(card) }
            sound("curse")
        case "knockback":
            var r = row
            if r == nil { r = await pickRow(player, gameData.abilityName("knockback"), [(o, .close), (o, .ranged)]) { 0 }?.1 }
            if let rowArea = r {
                let dest: RowType = rowArea == .close ? .ranged : .siege
                let moving = o.row(rowArea).cards.filter { !$0.hero }
                o.row(rowArea).cards.removeAll { m in moving.contains { $0 === m } }
                o.row(dest).cards.append(contentsOf: moving)
                sound("knockback")
            }
            player.grave.append(card)
        case "seize": await seize(player, .close); player.grave.append(card)
        case "bank": draw(player, 1); sound("game_buy"); player.grave.append(card)
        case "skellige_fleet":
            if player.fleetDrawsRound < 3 {
                let i = await pickOption(player, L("Draw now or more later?"), [L("Draw 1 now [E]"), L("Draw 2 later [Q]")]) { 0 }
                if i == 0 { draw(player, 1); player.fleetDrawsRound += 1 } else { player.fleetPending += 2; player.fleetDrawsRound += 2 }
            }
            player.row(.siege).specials.append(card)
        case "royal_decree":
            player.grave.append(card)
            await leaderEffect(player, free: true)
        case "decoration":
            let opts = player.rowCards.filter { !$0.hero }
            if let t = await pickOne(player, L("Choose a unit to promote to Hero."), opts, ai: { cs in cs.max { $0.power < $1.power } }) { t.heroOverride = true; t.flash = 1; await animate(t, "decoration") }
            player.grave.append(card); sound("decoration")
        case "chernobog", "perun":
            let opts = player.row(kind == "chernobog" ? .close : .ranged).cards.filter { !$0.hero }
            if let t = await pickOne(player, kind == "chernobog" ? L("Choose which unit to double with Chernobog runestone") : L("Choose which unit to grant +5 strength with Perun runestone"), opts, ai: { cs in cs.max { $0.power < $1.power } }) {
                if kind == "chernobog" { t.multiplier *= 2 } else { t.bonus += 5 }; t.flash = 1; await animate(t, kind)
            }
            player.grave.append(card); sound("rune_call")
        case "svarog", "morana":
            let opts = o.row(kind == "svarog" ? .siege : .close).cards.filter { !$0.hero }
            if let t = await pickOne(player, kind == "svarog" ? L("Choose which enemy siege unit to reduce to 1 with Svarog.") : L("Choose which enemy close unit to reduce to 1 with Morana."), opts, ai: { cs in cs.max { $0.power < $1.power } }) { t.setTo = 1; t.flash = 1; await animate(t, kind) }
            player.grave.append(card); sound("rune_call")
        case "triglav":
            let opts = o.rowCards.filter { $0.hero }
            if let t = await pickOne(player, L("Choose the enemy hero to weaken."), opts, ai: { cs in cs.max { $0.power < $1.power } }) { t.heroOverride = false; t.flash = 1; await animate(t, "triglav") }
            player.grave.append(card); sound("triglav")
        case "veles":
            if let t = player.rowCards.filter({ !$0.hero }).max(by: { $0.power < $1.power }) {
                if let tr = player.rowOf(t) { player.row(tr).cards.removeAll { $0 === t } }
                player.row(.siege).cards.append(t); t.siegeMult = 2; await animate(t, "veles")
            }
            player.grave.append(card); sound("veles")
        case "devana":
            for t in o.row(.ranged).cards where !t.hero { t.setTo = 2; t.flash = 1 }
            player.grave.append(card); sound("rune_call")
        case "zoria":
            o.weather[RowType.close.rawValue].insert("frost")
            player.grave.append(card); sound("cold")
        case "stribog":
            let units = o.row(.ranged).cards.filter { !$0.hero }
            if let mn = units.map({ $0.power }).min() {
                for t in units where t.power == mn { o.row(.ranged).cards.removeAll { $0 === t }; t.owner = player; player.row(.ranged).cards.append(t) }
            }
            player.grave.append(card); sound("rune_call")
        default:
            player.grave.append(card)
        }
        recalc()
    }

    /// Seize: steals the weakest enemy unit from a row.
    private func seize(_ player: Player, _ rowType: RowType) async {
        let o = player.opponent!
        if o.row(rowType).shielded { return }
        let units = o.row(rowType).cards.filter { !$0.hero && $0.immortalRounds == 0 }
        guard let mn = units.map({ $0.power }).min() else { return }
        for t in units where t.power == mn {
            o.row(rowType).cards.removeAll { $0 === t }
            t.owner = player; t.locked = true
            player.row(rowType).cards.append(t); t.flash = 1; events.append(.anim(t, "seize"))
        }
        sound("seize")
    }

    /// Rows affected by a weather ability.
    private func weatherRows(_ ability: String, _ card: Card) -> [RowType] {
        switch ability {
        case "frost", "spider_web": return [.close]
        case "fog", "tse_tse": return [.ranged]
        case "rain", "dragon_wrath": return [.siege]
        case "sandstorm": return [.close, .ranged]
        case "white_frost":
            switch card.data.row { case "agile_cs": return [.close, .siege]; case "agile_rs": return [.ranged, .siege]; default: return [.close, .ranged] }
        default: return []
        }
    }
    /// Plays a weather card.
    private func playWeather(_ card: Card, by player: Player, row: RowType?) async {
        let a = card.data.abilities.first ?? ""
        if a == "clear" { await clearWeather(); (card.owner ?? player).grave.append(card); return }
        var rows = weatherRows(a, card)
        if a == "storm" {
            let i = await pickOption(player, L("Skellige Storm can either target Close/Ranged rows or Ranged/Siege rows, which one to target?"), [L("Close + Ranged [E]"), L("Ranged + Siege [Q]")]) {
                let o = player.opponent!
                return o.row(.close).total + o.row(.ranged).total - player.row(.close).total - player.row(.ranged).total >= o.row(.ranged).total + o.row(.siege).total - player.row(.ranged).total - player.row(.siege).total ? 0 : 1
            }
            rows = i == 0 ? [.close, .ranged] : [.ranged, .siege]
        }
        if rows.allSatisfy({ human.weather[$0.rawValue].contains(a) && computer.weather[$0.rawValue].contains(a) }) { (card.owner ?? player).grave.append(card); return }
        for q in [human, computer] { for r in rows { q.weather[r.rawValue].insert(a) } }
        weatherCards.append(card)
        sound(["frost": "cold", "fog": "fog", "rain": "rain", "storm": "rain", "white_frost": "cold", "sandstorm": "sandstorm", "spider_web": "spider_web", "tse_tse": "tse_tse", "dragon_wrath": "dragon_wrath"][a] ?? "rain")
        if a == "fog" {
            for q in [human, computer] {
                for x in (q.deck + q.grave).filter({ $0.has("fog_summoning") }) {
                    q.deck.removeAll { $0 === x }; q.grave.removeAll { $0 === x }
                    resetCard(x); x.owner = q; q.row(x.allowedRows.first ?? .ranged).cards.append(x); x.flash = 1
                }
            }
        }
        recalc()
    }
    /// Removes all weather.
    private func clearWeather() async {
        for c in weatherCards { c.owner?.grave.append(c) }
        weatherCards.removeAll()
        for q in [human, computer] { for i in 0..<3 { q.weather[i].removeAll() } }
        sound("clear")
        recalc()
    }

    /// Whether a card is protected from destruction (e.g. by a shield).
    private func protected(_ card: Card, side: Player) async -> Bool {
        if card.immortalRounds > 0 { return true }
        if navigatorShield && card.has("door_o") && (side.leaderAbility == "imlerith_general") { return true }
        if side.leaderAbility == "novigrad_sigismund" && !side.sigismundSaved { side.sigismundSaved = true; note(L("Sigismund Dijkstra prevented the death of a friendly unit.")); return true }
        if !side.comradeUsedRound, side.rowCards.contains(where: { $0.act("comrade") }) {
            let i = await pickOption(side, L("Do you want to save Comrade too?"), [L("Save it [E]"), L("Let it die [Q]")]) { 0 }
            if i == 0 { side.comradeUsedRound = true; sound("comrade"); return true }
        }
        return false
    }
    /// Destroys a card and moves it to the graveyard.
    func destroy(_ card: Card, side: Player, burn: Bool = true) async {
        guard let r = side.rowOf(card) else { return }
        if await protected(card, side: side) { card.flash = 1; await animate(card, "comrade"); return }
        if burn { events.append(.burn(card)); await pause(0.75) }
        side.row(r).cards.removeAll { $0 === card }
        events.append(.flash(card))
        resetCard(card); card.diedRound = round
        (card.owner ?? side).grave.append(card)
        side.lostUnitThisTurn = true
        if card.data.abilities.contains(where: { $0.hasPrefix("avenger") }) {
            for t in card.data.targets {
                guard let d = gameData.cards[t], d.isUnit else { continue }
                let n: Card
                if let i = side.deck.firstIndex(where: { $0.key == t }) { n = side.deck.remove(at: i) } else { n = Card(d, owner: side) }
                n.owner = side; side.row(RowType.from(d.row) ?? r).cards.append(n); n.flash = 1
            }
        }
    }
    /// Scorch: destroys the strongest units on the whole board.
    private func scorch(except: Card?) async {
        recalc()
        var all: [(Card, Player)] = []
        for player in [human, computer] { for r in RowType.allCases where !player.row(r).shielded { for c in player.row(r).cards where !c.hero && c !== except && c.key != "spe_decoy" { all.append((c, player)) } } }
        guard let maxP = all.map({ $0.0.power }).max(), maxP > 0 else { return }
        sound("scorch")
        let victims = all.filter { $0.0.power == maxP }
        for (c, _) in victims { events.append(.burn(c)) }
        await pause(0.75)
        for (c, player) in victims { await destroy(c, side: player, burn: false) }
        recalc()
    }
    /// Cull: destroys the weakest units on the whole board.
    private func cull(except: Card?) async {
        recalc()
        var all: [(Card, Player)] = []
        for player in [human, computer] { for r in RowType.allCases where !player.row(r).shielded { for c in player.row(r).cards where !c.hero && c !== except && c.key != "spe_decoy" { all.append((c, player)) } } }
        guard let mn = all.map({ $0.0.power }).min() else { return }
        sound("cull")
        let victims = all.filter { $0.0.power == mn }
        for (c, _) in victims { events.append(.burn(c)) }
        await pause(0.75)
        for (c, player) in victims { await destroy(c, side: player, burn: false) }
        recalc()
    }
    /// Row scorch: destroys the strongest units of one row if the row is strong enough.
    private func rowScorch(_ side: Player, _ rowType: RowType) async {
        recalc()
        let row = side.row(rowType)
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
    /// Whether a player's leader ability can still be used.
    func leaderAvailable(_ player: Player) -> Bool { player.leaderUses > 0 && !Game.passiveLeaders.contains(player.leaderAbility) }
    /// The human uses the leader ability.
    func humanLeader() {
        guard !busy, phase == .play, current === human, leaderAvailable(human) else { return }
        busy = true
        Task { @MainActor in
            await self.useLeader(self.human)
            self.busy = false
        }
    }
    /// Uses a player's leader ability.
    func useLeader(_ player: Player) async {
        guard phase == .play, current === player, leaderAvailable(player) else { return }
        player.leaderUses -= 1
        player.leader.flash = 1
        sound("leader")
        note(player === human ? gameData.cardName(player.leader.data) : L("Opponent uses leader"), player === computer ? "notif_\(player.faction)" : nil)
        await leaderEffect(player, free: false)
        await endTurn(player)
    }
    /// Resolves every leader ability.
    func leaderEffect(_ player: Player, free: Bool) async {
        let o = player.opponent!
        /// Strongest card of a list.
        func best(_ cards: [Card]) -> Card? { cards.max { self.aiCardValue($0) < self.aiCardValue($1) } }
        switch player.leaderAbility {
        case "foltest_king":
            let opts = player.deck.filter { $0.has("fog") || $0.has("rain") }
            if let t = await pickOne(player, L("Which weather card to play? Impenetrable Fog or Torrential Rain?"), opts, ai: { $0.first }) { player.deck.removeAll { $0 === t }; t.owner = player; await playWeather(t, by: player, row: nil) }
        case "eredin_king":
            let opts = player.deck.filter { $0.data.isWeather }
            if let t = await pickOne(player, L("Choose a weather card to play"), opts, ai: { $0.first }) { player.deck.removeAll { $0 === t }; t.owner = player; await playWeather(t, by: player, row: nil) }
        case "foltest_lord", "vilgefortz_sorcerer": await clearWeather()
        case "foltest_siegemaster": player.row(.siege).leaderHorn = true; sound("horn")
        case "francesca_beautiful": player.row(.ranged).leaderHorn = true; sound("horn")
        case "foltest_son": await rowScorch(o, .ranged)
        case "foltest_steelforged": await rowScorch(o, .siege)
        case "francesca_queen", "cosimo_malaspina": await rowScorch(o, .close)
        case "meve_princess", "carlo_varese":
            recalc()
            if let r = RowType.allCases.filter({ o.row($0).total >= 10 }).max(by: { o.row($0).total < o.row($1).total }) { await rowScorch(o, r) }
        case "emhyr_imperial":
            let opts = o.grave.filter { $0.isUnit && !$0.hero }
            if let t = await pickOne(player, L("Which card to draw?"), opts, ai: best) { o.grave.removeAll { $0 === t }; resetCard(t); t.owner = player; player.hand.append(t) }
            if let back = await pickOne(player, L("Which card to put back into the deck?"), player.hand, ai: { cs in cs.min { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                player.hand.removeAll { $0 === back }; player.deck.append(back)
            }
        case "emhyr_emperor":
            let four = Array(o.hand.shuffled().prefix(4))
            if let t = await pickOne(player, L("Which card should your opponent play on the next round?"), four, ai: { cs in cs.min { self.aiCardValue($0) < self.aiCardValue($1) } }) { o.forcedCard = t }
        case "emhyr_relentless":
            if let t = await pickOne(player, L("Which card to destroy?"), player.rowCards, ai: { cs in cs.min { $0.power < $1.power } }) { await destroy(t, side: player) }
            let opts = player.deck.filter { $0.has("spy") || $0.has("emissary") }
            if let t = await pickOne(player, L("Which Spy/Emissary card to draw?"), opts, ai: { $0.first }) { player.deck.removeAll { $0 === t }; player.hand.append(t) }
        case "emhyr_invader":
            for q in [player, o] {
                let opts = q.grave.filter { $0.isUnit }
                let t = q === player ? await pickOne(player, L("Which card to restore from your grave?"), opts, ai: best) : opts.randomElement()
                if let t = t { q.grave.removeAll { $0 === t }; resetCard(t); await placeUnit(t, by: q, row: t.allowedRows.first ?? .close, side: q) }
            }
        case "eredin_commander":
            let picks = await pickCards(player, L("Choose on your battlefield two or less unit and/or hero cards and take them into your hand."), player.rowCards, min: 0, max: 2) { cs in Array(cs.filter { $0.has("spy") || $0.has("medic") }.prefix(2)) }
            for t in picks { if let r = player.rowOf(t) { player.row(r).cards.removeAll { $0 === t } }; resetCard(t); player.hand.append(t) }
        case "eredin_bringer_of_death":
            if let t = await pickOne(player, L("Which card to restore from your grave?"), player.grave.filter { $0.isUnit }, ai: best) { player.grave.removeAll { $0 === t }; resetCard(t); player.hand.append(t) }
        case "eredin_destroyer":
            let disc = await pickCards(player, L("Which card to discard?"), player.hand, min: min(2, player.hand.count), max: 2) { cs in Array(cs.sorted { self.aiCardValue($0) < self.aiCardValue($1) }.prefix(2)) }
            for t in disc { player.hand.removeAll { $0 === t }; player.grave.append(t) }
            if let t = await pickOne(player, L("Which card to draw?"), player.deck, ai: best) { player.deck.removeAll { $0 === t }; player.hand.append(t) }
        case "francesca_pureblood", "francesca_hope":
            let target = player.leaderAbility == "francesca_pureblood" ? o : player
            let n = player.leaderAbility == "francesca_pureblood" ? 3 : 4
            let picks = await pickCards(player, gameData.abilityDesc(player.leaderAbility), target.rowCards.filter { !$0.hero }, min: 0, max: n) { cs in Array(cs.prefix(n)) }
            for t in picks {
                guard let from = target.rowOf(t) else { continue }
                let dests = RowType.allCases.filter { $0 != from }.map { (target, $0) }
                if let (_, d) = await pickRow(player, gameData.cardName(t.data), dests, ai: { target === o ? (o.weather[dests[0].1.rawValue].isEmpty ? 1 : 0) : 0 }) {
                    target.row(from).cards.removeAll { $0 === t }; target.row(d).cards.append(t)
                }
            }
        case "crach_an_craite":
            let keep = await pickOne(player, L("Would you like to select a card to keep in your graveyard?"), player.grave, cancel: true, ai: { _ in nil })
            for q in [player, o] {
                for card in q.grave where card !== keep { resetCard(card); q.deck.append(card) }
                q.grave = keep != nil && q === player ? [keep!] : []
                q.deck.shuffle()
            }
        case "birna":
            let opts = player.deck.filter { $0.has("mardroeme") || $0.has("berserker") }
            if let t = await pickOne(player, gameData.abilityDesc("birna"), opts, ai: best) {
                player.deck.removeAll { $0 === t }
                if t.isUnit { await placeUnit(t, by: player, row: t.allowedRows.first ?? .close) } else { player.hand.append(t) }
            }
        case "holger_blakhand":
            let opts = (player.rowCards + o.rowCards).filter { !$0.hero }
            if let t = await pickOne(player, L("Change the strength of a card?"), opts, ai: { cs in cs.filter { $0.owner === player }.min { $0.power < $1.power } ?? cs.first }) {
                let v = await pickOption(player, L("Select a new base power"), (1...10).map { "\($0)" }) { (t.owner === player) ? 9 : 0 }
                t.tempStrength = v + 1; t.flash = 1
            }
        case "radovid_king_redania", "nibras":
            let three = Array(player.deck.filter { !$0.data.isSpecial && !$0.data.isWeather && !$0.has("spy") && !$0.has("emissary") && !$0.has("ofiri_envoy") }.prefix(3))
            if let t = await pickOne(player, L("Choose a unit to play immediately"), three, ai: best) {
                player.deck.removeAll { $0 === t }
                if t.isUnit { await placeUnit(t, by: player, row: t.allowedRows.first ?? .close) }
                player.deck.shuffle()
            }
        case "radovid_mad_king":
            recalc()
            let all = (player.rowCards + o.rowCards)
            if let mx = all.map({ $0.power }).max() {
                let cands = all.filter { $0.power == mx }
                if let t = await pickOne(player, L("Choose the card to destroy"), cands, ai: { cs in cs.first { $0.owner === o } ?? cs.first }) { await destroy(t, side: o.rowCards.contains { $0 === t } ? o : player) }
            }
        case "radovid_strategist":
            if let t = await pickOne(player, L("Choose the hero to take back into your hand"), player.rowCards.filter { $0.hero }, ai: best) { if let r = player.rowOf(t) { player.row(r).cards.removeAll { $0 === t } }; player.hand.append(t) }
        case "anna_henrietta_duchess":
            if let t = await pickOne(player, L("Choose the hero to play"), player.grave.filter { $0.hero && $0.isUnit }, ai: best) { player.grave.removeAll { $0 === t }; await placeUnit(t, by: player, row: t.allowedRows.first ?? .close) }
        case "anna_henrietta_ladyship":
            let opts = (player.rowCards + o.rowCards).filter { $0.revertTo != nil }
            if let t = await pickOne(player, L("Choose the monster to revert to its primal form."), opts, ai: { $0.first }), let k = t.revertTo, let d = gameData.cards[k] { t.transform(into: d); t.revertTo = nil }
        case "anna_henrietta_little_weasel":
            if let t = await pickOne(player, L("Choose the enemy hero to demote."), o.rowCards.filter { $0.hero }, ai: best) { t.heroOverride = false; t.flash = 1 }
        case "lady_wood_whispess":
            let opts = player.grave.filter { $0.isUnit && $0.diedRound == round }
            let picks = await pickCards(player, gameData.abilityDesc("lady_wood_whispess"), opts, min: 0, max: 3) { cs in Array(cs.sorted { self.aiCardValue($0) > self.aiCardValue($1) }.prefix(3)) }
            for t in picks { player.grave.removeAll { $0 === t }; player.hand.append(t) }
        case "lady_wood_weavess":
            if let t = player.deck.first(where: { $0.specialKind == "curse" }) {
                player.deck.removeAll { $0 === t }; t.owner = player
                if let (q, r) = await pickRow(player, gameData.abilityName("curse"), curseRows(by: player), ai: { 3 }) { q.row(r).curse = t }
            }
        case "ghost_tree":
            recalc()
            let all = (player.rowCards + o.rowCards).filter { !$0.hero }
            if let mn = all.map({ $0.power }).min() {
                let cands = all.filter { $0.power == mn }
                if let t = await pickOne(player, L("Choose which enemy card to destroy"), cands, ai: { cs in cs.first { $0.owner === o } ?? cs.first }) { await destroy(t, side: o.rowCards.contains { $0 === t } ? o : player) }
            }
        case "auberon_king":
            let navs = (player.deck + player.grave).filter { $0.has("door_o") }
            let picks = await pickCards(player, gameData.abilityDesc("auberon_king"), navs, min: 0, max: navs.count) { $0 }
            for t in picks { player.deck.removeAll { $0 === t }; player.grave.removeAll { $0 === t }; player.hand.append(t) }
            if !picks.isEmpty {
                let back = await pickCards(player, L("Which card to put back into the deck?"), player.hand.filter { card in !picks.contains { $0 === card } }, min: picks.count, max: picks.count) { cs in Array(cs.sorted { self.aiCardValue($0) < self.aiCardValue($1) }.prefix(picks.count)) }
                for t in back { player.hand.removeAll { $0 === t }; player.deck.insert(t, at: Int.random(in: 0...player.deck.count)) }
            }
        case "winter_queen":
            let opts = player.deck.filter { $0.data.isSpecial || $0.data.isWeather }
            if let t = await pickOne(player, L("Choose a special card to play immediatly."), opts, ai: { $0.first }) {
                player.deck.removeAll { $0 === t }; t.owner = player
                if t.data.isWeather { await playWeather(t, by: player, row: nil) } else { await playSpecial(t, by: player, row: nil, rowOwner: nil, target: nil) }
            }
        case "alzur_maker":
            if let t = await pickOne(player, gameData.abilityDesc("alzur_maker"), player.rowCards.filter { !$0.hero }, ai: { cs in cs.min { $0.power < $1.power } }) {
                await destroy(t, side: player)
                if let d = gameData.cards["wu_koshchey"] { await placeUnit(Card(d, owner: player), by: player, row: .close) }
            }
        case "cyprian_wiley": await seize(player, .close)
        case "francis_bedlam":
            for q in [player, o] { for card in q.rowCards where card.has("spy") || card.has("emissary") { await destroy(card, side: q) } }
        case "gudrun_bjornsdottir":
            let crew = (player.deck + player.hand + player.grave).filter { $0.key == "sy_flyndr_crew" }
            if crew.isEmpty, let d = gameData.cards["sy_flyndr_crew"] { await placeUnit(Card(d, owner: player), by: player, row: .close) }
            for t in crew { player.deck.removeAll { $0 === t }; player.hand.removeAll { $0 === t }; player.grave.removeAll { $0 === t }; resetCard(t); await placeUnit(t, by: player, row: .close) }
        case "cyrus_hemmelfart":
            if let d = gameData.cards["spe_dimeritium_shackles"], let (_, r) = await pickRow(player, gameData.abilityDesc("cyrus_hemmelfart"), RowType.allCases.map { (o, $0) }, ai: { Int.random(in: 0..<3) }) {
                o.row(r).lock = Card(d, owner: player)
            }
        case "cyrus_hemmelfart1":
            if let d = gameData.cards["nv_inquisitional_pyres"] { await placeUnit(Card(d, owner: player), by: player, row: .close) }
        case "azar_javed":
            recalc()
            if let t = o.rowCards.filter({ $0.hero }).min(by: { $0.power < $1.power }) { await destroy(t, side: o) }
        case "baal_zebuth":
            let picks = await pickCards(player, gameData.abilityDesc("baal_zebuth"), o.grave, min: 0, max: 2) { cs in Array(cs.sorted { self.aiCardValue($0) > self.aiCardValue($1) }.prefix(2)) }
            for t in picks { o.grave.removeAll { $0 === t }; resetCard(t); o.deck.append(t) }
            o.deck.shuffle()
        case "rarog":
            if let t = player.grave.randomElement() {
                player.grave.removeAll { $0 === t }; resetCard(t); player.hand.append(t)
                for card in player.grave { resetCard(card); player.deck.append(card) }
                player.grave.removeAll(); player.deck.shuffle()
            }
        case "nibras_gale":
            let three = Array(o.deck.prefix(3))
            if let t = await pickOne(player, L("Choose a card to add to your hand (others will be discarded)"), three, ai: best) {
                o.deck.removeAll { x in three.contains { $0 === x } }
                t.owner = player; player.hand.append(t)
                for x in three where x !== t { o.grave.append(x) }
            }
        default: break
        }
        recalc()
    }

    /// The faction ability that can be activated now, if any.
    func factionActive(_ player: Player) -> String? {
        switch player.faction {
        case "witcher_universe": return player.factionUsedRound ? nil : "skip_round"
        case "redania": return player.factionUsedGame ? nil : "skip_game"
        case "lyria_rivia": return player.factionUsedGame ? nil : "morale"
        case "ofir": return player.factionUsedGame || !player.deck.contains(where: { $0.data.isWeather }) ? nil : "weather"
        case "toussaint": return player.rowCards.contains(where: { $0.act("monster_toussaint") && $0.playedTurn < turn - 1 }) ? "transform" : nil
        default: return nil
        }
    }
    /// The human uses the faction ability.
    func humanFaction() {
        guard !busy, phase == .play, current === human, factionActive(human) != nil else { return }
        busy = true
        Task { @MainActor in await self.useFaction(self.human); self.busy = false }
    }
    /// Uses a player's active faction ability.
    func useFaction(_ player: Player) async {
        guard let f = factionActive(player), current === player else { return }
        switch f {
        case "skip_round":
            player.factionUsedRound = true
            note(L("Witcher Universe used its faction ability and skipped a turn"), "notif_witcher_universe")
        case "skip_game":
            player.factionUsedGame = true
            note(L("Redania used its faction ability and skipped a turn"), "notif_redania")
        case "morale":
            if let (_, r) = await pickRow(player, gameData.factionDesc("lyria_rivia"), RowType.allCases.map { (player, $0) }, ai: { RowType.allCases.map { player.row($0).cards.count }.enumerated().max { $0.1 < $1.1 }!.0 }) {
                player.row(r).factionMorale += 1; player.factionUsedGame = true
                note(L("Lyria & Rivia ability used - Morale Boost effect applied to a row."), "notif_lyria_rivia"); sound("moral")
            }
        case "weather":
            let opts = player.deck.filter { $0.data.isWeather }
            if let t = await pickOne(player, L("Choose a weather card to play"), opts, ai: { $0.first }) {
                player.factionUsedGame = true; player.deck.removeAll { $0 === t }; t.owner = player
                await playWeather(t, by: player, row: nil)
                note(L("Ofir faction ability used - Weather card played from deck."), "notif_ofir")
            }
        case "transform":
            let opts = player.rowCards.filter { $0.act("monster_toussaint") && $0.playedTurn < turn - 1 }
            if let t = await pickOne(player, L("Choose which monster to transform."), opts, ai: best1), let k = t.data.targets.first, let d = gameData.cards[k] {
                t.revertTo = t.key
                t.transform(into: d); t.playedTurn = turn
                sound("monster_toussaint")
                await unitAbilities(t, by: player, side: player, row: player.rowOf(t) ?? .close)
            }
        default: break
        }
        recalc()
        await endTurn(player)
    }
    /// Strongest card of a list.
    private func best1(_ cards: [Card]) -> Card? { cards.max { aiCardValue($0) < aiCardValue($1) } }

    /// Recalculates the power of every card on the board.
    func recalc() {
        for player in [human, computer] {
            let side = player.rowCards
            let inspires = side.filter { $0.act("inspire") }
            let maxInspire = inspires.map { $0.basePower }.max() ?? 0
            let whorshippers = side.filter { $0.act("whorshipper") }.count
            var schools: [String: Int] = [:]
            for c in side where !c.locked { if let s = c.school { schools[s, default: 0] += 1 } }
            for r in RowType.allCases {
                let row = player.row(r)
                let bondCounts = Dictionary(grouping: row.cards.filter { $0.act("bond") }, by: { $0.groupKey }).mapValues { $0.count }
                let morale = row.cards.filter { $0.act("morale") }.count + row.specials.filter { $0.specialKind == "morale" }.count + row.factionMorale
                let wine = row.specials.filter { $0.specialKind == "toussaint_wine" }.count + row.cards.filter { $0.act("toussaint_wine") }.count
                let horns = row.hornCount
                let w = player.weather[r.rawValue]
                var sum = 0
                for card in row.cards {
                    card.power = cardScore(card, r, player, bondCounts: bondCounts, morale: morale, wine: wine, horns: horns, weather: w,
                                        inspire: inspires.count > 1 ? maxInspire : nil, whorshippers: whorshippers, schools: schools)
                    sum += card.power
                }
                row.total = sum
            }
            player.total = player.rows.reduce(0) { $0 + $1.total } + player.aamadBonus
        }
    }
    /// Power of a single card on a row after weather, horns, bonds and morale.
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

    /// The human gives up the match.
    func surrender() {
        guard phase != .over else { return }
        phase = .over; human.gems = 0; winner = computer
        sound("game_lose")
        if choiceCont != nil { resolveChoice(nil) }
    }
    /// Rough value of a card used by AI heuristics.
    func aiCardValue(_ card: Card) -> Int {
        card.basePower + (card.hero ? 3 : 0) + (card.has("spy") ? 6 : 0) + (card.has("medic") ? 5 : 0) + (card.has("muster") ? 4 : 0) +
            (card.data.isSpecial || card.data.isWeather ? 4 : 0)
    }
}

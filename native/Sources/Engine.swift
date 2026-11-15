// Game rules: cards, rows, players, rounds, turns and every card / leader / faction ability.
import Foundation

/// Board row: close combat, ranged or siege.
enum RowType: Int, CaseIterable { case close = 0, ranged = 1, siege = 2
    /// Parses a row name from the card data.
    static func from(_ rowName: String) -> RowType? { ["close": .close, "ranged": .ranged, "siege": .siege][rowName] }
}

/// A card instance in a game, with its current power and state.
@MainActor
final class Card {
    static var nextId = 1
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
        for (key, copies) in deck.cards { if let cardData = gameData.cards[key] { for _ in 0..<max(1, copies) { self.deck.append(Card(cardData, owner: self)) } } }
        self.deck.shuffle()
    }
    var rowCards: [Card] { rows.flatMap { $0.cards } }
    /// The given row of this player.
    func row(_ rowType: RowType) -> Row { rows[rowType.rawValue] }
    /// The row a card currently lies in.
    func rowOf(_ card: Card) -> RowType? { for rowType in RowType.allCases where rows[rowType.rawValue].cards.contains(where: { $0 === card }) { return rowType }; return nil }
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
    let aiAnswer: () -> [Int]
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
    var choiceCont: CheckedContinuation<[Int]?, Never>?
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
    func redrawCount(_ player: Player) -> Int { 2 + (player.faction == "toussaint" ? 1 : 0) + (player.faction == "novigrad" ? 1 : 0) }
    /// Applies leader abilities that work passively.
    func applyPassiveLeader(_ player: Player) {
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
    func summonToBoard(_ player: Player, key: String) {
        let card: Card
        if let i = player.deck.firstIndex(where: { $0.key == key }) { card = player.deck.remove(at: i) }
        else if let cardData = gameData.cards[key] { card = Card(cardData, owner: player) } else { return }
        card.owner = player
        player.row(card.allowedRows.first ?? .close).cards.append(card)
    }

    var showChoices = false
    /// Asks a player to choose; the AI answers automatically, the human through the UI.
    func choose(_ request: Choice) async -> [Int]? {
        if autoHuman && showChoices && !request.player.isAI {
            choice = request
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            choice = nil
            return request.aiAnswer()
        }
        if request.player.isAI || autoHuman { return request.aiAnswer() }
        choice = request
        return await withCheckedContinuation { continuation in choiceCont = continuation }
    }
    /// Called by the UI with the human's answer to the pending choice.
    func resolveChoice(_ answer: [Int]?) {
        let continuation = choiceCont
        choice = nil; choiceCont = nil
        continuation?.resume(returning: answer)
    }
    /// Asks a player to pick several cards.
    func pickCards(_ player: Player, _ title: String, _ cards: [Card], min: Int = 1, max: Int = 1, cancel: Bool = false,
                           ai: @escaping ([Card]) -> [Card]) async -> [Card] {
        guard !cards.isEmpty else { return [] }
        let selection = await choose(Choice(player: player, title: title, kind: .cards(cards, min: min, max: Swift.min(max, cards.count)), canCancel: cancel) {
            ai(cards).compactMap { pickedCard in cards.firstIndex { $0 === pickedCard } }
        }) ?? []
        return selection.compactMap { $0 < cards.count ? cards[$0] : nil }
    }
    /// Asks a player to pick one card.
    func pickOne(_ player: Player, _ title: String, _ cards: [Card], cancel: Bool = false, ai aiPick: @escaping ([Card]) -> Card?) async -> Card? {
        await pickCards(player, title, cards, max: 1, cancel: cancel) { candidates in aiPick(candidates).map { [$0] } ?? [] }.first
    }
    /// Asks a player to pick a row.
    func pickRow(_ player: Player, _ title: String, _ rows: [(Player, RowType)], ai: @escaping () -> Int) async -> (Player, RowType)? {
        guard !rows.isEmpty else { return nil }
        if rows.count == 1 { return rows[0] }
        guard let i = await choose(Choice(player: player, title: title, kind: .rows(rows), canCancel: false) { [ai()] })?.first, i < rows.count else { return rows[0] }
        return rows[i]
    }
    /// Asks a player to pick one of several options.
    func pickOption(_ player: Player, _ title: String, _ opts: [String], ai aiPick: @escaping () -> Int) async -> Int {
        (await choose(Choice(player: player, title: title, kind: .options(opts), canCancel: false) { [aiPick()] }))?.first ?? 0
    }
    /// Shows cards to the player (e.g. the opponent's hand).
    func reveal(_ player: Player, _ title: String, _ cards: [Card]) async {
        guard !cards.isEmpty else { return }
        _ = await choose(Choice(player: player, title: title, kind: .reveal(cards), canCancel: true) { [] })
    }
    var paused = false
    /// Waits so the UI can show animations.
    func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64((autoHuman ? seconds * 0.3 : seconds) * 1_000_000_000))
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
        guard let animation = Game.animName(name) ?? (name == "hero" ? "hero" : nil) else { return }
        events.append(.anim(card, animation))
        if wait { await pause(0.7) }
    }
    /// Shows a notification banner.
    func note(_ text: String, _ icon: String? = nil) { events.append(.notify(text, icon: icon)) }
    /// Plays a sound effect.
    func sound(_ name: String) { events.append(.sound(name)) }

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
        let drawn = human.deck.removeFirst()
        human.hand[i] = drawn
        human.deck.insert(card, at: Int.random(in: 0...human.deck.count))
        redrawsLeft -= 1
        sound("redraw")
        return drawn
    }
    /// AI decision for the redraw phase.
    func aiRedraw(_ player: Player) {
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
            let back = await pickCards(human, L("Choose 2 cards to put back into your deck"), human.hand, min: 2, max: 2) { candidates in Array(candidates.sorted { self.aiCardValue($0) < self.aiCardValue($1) }.prefix(2)) }
            for returned in back { human.hand.removeAll { $0 === returned }; human.deck.insert(returned, at: Int.random(in: 0...human.deck.count)) }
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
    func startRound() async {
        turn += 1
        // Reset per-round flags of both players.
        for player in [human, computer] {
            player.aamadBonus = 0; player.comradeUsedRound = false; player.factionUsedRound = false; player.fleetDrawsRound = 0; player.halfWeather = false
        }
        // Announce the round.
        note(L("Round Start") + " · \(round)", "notif_round_start")
        sound(round == 1 ? "round1_start" : "round_win")
        // Faction perks that trigger at the start of rounds 2 and 3 (Northern Realms, Zerrikania, Skellige).
        if round > 1 {
            for player in [human, computer] {
                if player.faction == "realms" && lastRoundWinner !== player { draw(player, 1); note(L("Northern Realms faction ability triggered - North draws an additional card."), "notif_north") }
                if player.faction == "zerrikania" && lastRoundWinner === player.opponent {
                    let options = player.grave.filter { $0.isUnit }
                    if let card = await pickOne(player, L("Which card to restore from your grave?"), options, cancel: true, ai: { candidates in candidates.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                        player.grave.removeAll { $0 === card }
                        await placeUnit(card, by: player, row: card.allowedRows.first ?? .close)
                        note(L("Zerrikania ability used - Unit restored from discard pile."), "notif_zerrikania")
                    }
                }
                if player.faction == "skellige" && round == 3 {
                    let options = player.grave.filter { $0.isUnit }.shuffled().prefix(2)
                    for card in options { player.grave.removeAll { $0 === card }; await placeUnit(card, by: player, row: card.allowedRows.randomElement() ?? .close) }
                    if !options.isEmpty { note(player === human ? L("Skellige Ability Triggered!") : L("Opponent Skellige Ability Triggered!"), "notif_skellige") }
                }
            }
        }
        // Wild Hunt picks which of its leaders to use this round.
        for player in [human, computer] where player.faction == "wild_hunt" {
            let leaders = gameData.cards.values.filter { $0.isLeader && $0.key.hasPrefix("wh_") }.sorted { $0.key < $1.key }
            let cards = leaders.map { Card($0, owner: player) }
            if let card = await pickOne(player, L("Select the next leader to start the round with"), cards, ai: { candidates in candidates.randomElement() }) {
                player.leader = card; player.leaderUses = 1; applyPassiveLeader(player)
            }
        }
        for player in [human, computer] {
            // Leaders that offer a decision at the start of a round.
            if player.leaderAbility == "king_bran", player.leaderUses > 0 {
                let answer = await pickOption(player, L("Bring the Skellige Storm?"), [L("Bring the Storm [E]"), L("Maybe later [Q]")]) { (self.round > 1 || player.deck.contains { $0.has("storm") }) ? 0 : 1 }
                if answer == 0 { player.leaderUses = 0; player.halfWeather = true
                    if let topCard = player.deck.first(where: { $0.has("storm") }) { player.deck.removeAll { $0 === topCard }; player.hand.append(topCard) } }
            }
            if player.leaderAbility == "madman_lugos", player.leaderUses > 0, player.opponent.hand.count >= 2 {
                let answer = await pickOption(player, L("Discard a card from the hand of the opponent?"), [L("Discard a card [E]"), L("Maybe later [Q]")]) { self.round >= 2 ? 0 : 1 }
                if answer == 0 {
                    player.leaderUses = 0
                    let twoCards = Array(player.opponent.hand.shuffled().prefix(2))
                    if let card = await pickOne(player, L("Which card to discard?"), twoCards, ai: { candidates in candidates.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                        player.opponent.hand.removeAll { $0 === card }; player.opponent.grave.append(card)
                    }
                }
            }
        }
        // Scoia'tael decides who goes first.
        for player in [human, computer] where player.faction == "scoiatael" {
            let answer = await pickOption(player, L("Who should go first?"), [L("Go First [E]"), L("Let Opponent Start [Q]")]) { 1 }
            current = answer == 0 ? player : player.opponent
            if player === computer { note(L("Opponent used the Scoia'tael faction perk to go first."), "notif_scoiatael") }
            break
        }
        await beginTurn()
    }

    /// Starts the current player's turn.
    func beginTurn() async {
        recalc()
        if human.passed && computer.passed { await endRound(); return }
        if current.passed { current = current.opponent }
        if current.hand.isEmpty && !current.passed && !canActWithoutCards(current) { await pass(current); return }
        if current === human { note(L("Your turn!"), "notif_me_turn"); sound("turn_me") } else { sound("turn_op") }
    }
    /// Whether a player can still act without cards in hand.
    func canActWithoutCards(_ player: Player) -> Bool { leaderAvailable(player) || factionActive(player) != nil }

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
    func endTurn(_ player: Player) async {
        recalc()
        let doors = RowType.allCases.filter { player.row($0).door }
        if !doors.isEmpty, let top = player.deck.first {
            player.deck.removeFirst()
            if top.isUnit, let doorRow = doors.first(where: { top.allowedRows.contains($0) }) {
                await placeUnit(top, by: player, row: doorRow)
            } else if !top.isUnit {
                player.hand.append(top)
            } else { player.deck.insert(top, at: Int.random(in: 0...player.deck.count)) }
        }
        for side in [player, player.opponent!] where side.faction == "velen" && side.lostUnitThisTurn {
            side.lostUnitThisTurn = false
            let extraDraws = 1 + side.rowCards.filter { $0.act("soothsayer") }.count
            if side.leaderAbility == "lady_wood_brewess", side.deck.count >= 2 {
                let twoCards = Array(side.deck.prefix(2))
                if let card = await pickOne(side, L("Choose a unit to play immediately"), twoCards, ai: { candidates in candidates.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                    side.deck.removeAll { $0 === card }
                    if card.isUnit { await placeUnit(card, by: side, row: card.allowedRows.first ?? .close) } else { side.hand.append(card) }
                    side.deck.shuffle()
                }
            } else { draw(side, extraDraws) }
            note(L("Velen ability triggered: Player will draw a card"), "notif_velen")
        }
        recalc()
        turn += 1
        if !player.opponent.passed { current = player.opponent }
        await beginTurn()
    }

    /// Scores the round, removes a life from the loser and checks for the end of the match.
    func endRound() async {
        phase = .roundEnd
        recalc()
        // Monsters may take one card back to hand before the round is scored.
        for player in [human, computer] where player.faction == "monsters" && !player.monstersUsed && !player.rowCards.isEmpty {
            let answer = await pickOption(player, L("Would you like to retake one of your cards?"), [L("Retake a card [E]"), L("Not yet [Q]")]) { self.round >= 2 ? 0 : 1 }
            if answer == 0, let card = await pickOne(player, L("Which card to retake?"), player.rowCards, ai: { candidates in candidates.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                player.monstersUsed = true
                if let rowType = player.rowOf(card) { player.row(rowType).cards.removeAll { $0 === card } }
                resetCard(card); player.hand.append(card)
                note(L("Monsters faction ability triggered - monsters retake one card to their hand"), "notif_monsters")
            }
        }
        recalc()
        // Decide the round winner; Nilfgaard wins draws against other factions.
        let humanScore = human.total, computerScore = computer.total
        var roundWinner: Player? = humanScore > computerScore ? human : (computerScore > humanScore ? computer : nil)
        if roundWinner == nil {
            let humanIsNilfgaard = human.faction == "nilfgaard", computerIsNilfgaard = computer.faction == "nilfgaard"
            if humanIsNilfgaard != computerIsNilfgaard { roundWinner = humanIsNilfgaard ? human : computer; note(L("Nilfgaard wins draws"), "notif_nilfgaard") }
        }
        // Record the result and take a life from the loser (both on a draw).
        history.append((humanScore, computerScore, roundWinner))
        lastRoundWinner = roundWinner
        if let roundWinner = roundWinner { roundWinner.opponent.gems -= 1 } else { human.gems -= 1; computer.gems -= 1 }
        if roundWinner === human { note(L("You won the round!"), "notif_win_round"); sound("round_win") }
        else if roundWinner === computer { note(L("Your opponent won the round"), "notif_lose_round"); sound("round_lose") }
        else { note(L("The round ended in a draw"), "notif_draw_round") }
        // Clear the board, then end the match after the third round or when someone has no lives left.
        await cleanupRound()
        if human.gems <= 0 || computer.gems <= 0 || round >= 3 {
            phase = .over
            winner = human.gems > computer.gems ? human : (computer.gems > human.gems ? computer : nil)
            sound(winner === human ? "game_win" : "game_lose")
            recalc()
            return
        }
        // Otherwise prepare the next round; the round winner moves first.
        round += 1
        human.passed = false; computer.passed = false
        current = roundWinner ?? current
        phase = .play
        await startRound()
    }

    /// Returns a card to its base state when it leaves the board.
    func resetCard(_ card: Card) {
        card.locked = false; card.setTo = nil; card.tempStrength = nil; card.multiplier = 1; card.bonus = 0; card.siegeMult = 1
        card.baseOverride = nil; card.heroOverride = nil; card.keepNextRound = false
    }
    /// Clears the board after a round, keeping cards that stay.
    func cleanupRound() async {
        var avengers: [(Card, Player, RowType)] = []
        for player in [human, computer] {
            for unit in player.rowCards where unit.act("resilience") {
                let key = unit.data.abilities.last ?? ""
                if player.rowCards.filter({ $0 !== unit && $0.data.abilities.contains(key) }).count >= 1 { unit.keepNextRound = true }
            }
        }
        for player in [human, computer] {
            for rowType in RowType.allCases {
                let row = player.row(rowType)
                var stay: [Card] = []
                for card in row.cards {
                    if card.immortalRounds > 1 { card.immortalRounds -= 1; stay.append(card); continue }
                    if card.keepNextRound { card.keepNextRound = false; stay.append(card); continue }
                    if card.data.abilities.contains(where: { $0.hasPrefix("avenger") }) && !card.locked { avengers.append((card, player, rowType)) }
                    resetCard(card); card.diedRound = round
                    (card.owner ?? player).grave.append(card)
                }
                row.cards = stay
                for special in row.specials { (special.owner ?? player).grave.append(special) }
                row.specials.removeAll(); row.lock = nil; row.curse = nil; row.ambush = nil; row.door = false; row.leaderHorn = false; row.factionMorale = 0
                player.weather[rowType.rawValue].removeAll()
            }
            for card in player.hand + player.deck { card.tempStrength = nil }
            player.forcedCard = nil
        }
        for card in weatherCards { (card.owner ?? human).grave.append(card) }
        weatherCards.removeAll()
        for player in [human, computer] where player.fleetPending > 0 { draw(player, player.fleetPending); player.fleetPending = 0 }
        if round < 3 {
            for (card, player, r) in avengers {
                for targetKey in card.data.targets {
                    guard let cardData = gameData.cards[targetKey], cardData.isUnit else { continue }
                    if let i = player.deck.firstIndex(where: { $0.key == targetKey }) { let summoned = player.deck.remove(at: i); player.row(RowType.from(cardData.row) ?? r).cards.append(summoned); summoned.flash = 1 }
                    else { let newCard = Card(cardData, owner: player); player.row(RowType.from(cardData.row) ?? r).cards.append(newCard); newCard.flash = 1 }
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
        case "horn", "mardroeme", "morale": return RowType.allCases.filter { candidateRow in !player.row(candidateRow).specials.contains { $0.specialKind == card.specialKind } }
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
        [player, player.opponent].flatMap { side in RowType.allCases.filter { side.row($0).curse == nil }.map { (side, $0) } }
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
        guard phase == .play, current === player, let handIndex = player.hand.firstIndex(where: { $0 === card }) else { return }
        if let forced = player.forcedCard, forced !== card, player.hand.contains(where: { $0 === forced }) { return }
        player.forcedCard = nil
        player.hand.remove(at: handIndex)
        card.owner = player
        card.flash = 1
        if card.data.isWeather { await playWeather(card, by: player, row: row) }
        else if card.data.isSpecial { await playSpecial(card, by: player, row: row, rowOwner: rowOwner, target: target) }
        else { await placeUnit(card, by: player, row: row ?? card.allowedRows.first ?? .close) }
        await endTurn(player)
    }

    /// Places a unit on a row and triggers its abilities.
    func placeUnit(_ card: Card, by player: Player, row requestedRow: RowType, side forcedSide: Player? = nil) async {
        var chosenRow = requestedRow
        let isSpy = card.has("spy") || card.has("emissary") || card.has("ofiri_envoy")
        let side: Player = forcedSide ?? (isSpy ? player.opponent : player)
        if !card.isUnit { player.hand.append(card); return }
        if !card.data.row.hasPrefix("agile") && !card.has("ambush"), let fixed = RowType.from(card.data.row) { chosenRow = fixed }
        card.owner = player
        card.playedTurn = turn
        let row = side.row(chosenRow)
        if let curse = row.curse, !card.hero {
            row.curse = nil; (curse.owner ?? player).grave.append(curse)
            side.grave.append(card); card.diedRound = round
            note(gameData.abilityName("curse")); sound("curse")
            return
        }
        row.cards.append(card)
        card.flash = 1
        sound(card.hero ? "hero" : "card")
        if let lockCard = row.lock, !card.hero, !card.data.abilities.filter({ $0 != "hero" }).isEmpty {
            card.locked = true; row.lock = nil; (lockCard.owner ?? player).grave.append(lockCard); sound("lock"); events.append(.anim(card, "lock"))
        }
        if let ambusher = side.opponent.row(chosenRow).cards.first(where: { $0.act("ambush") && $0.owner === side.opponent }), side === player {
            let o = side.opponent!
            o.row(chosenRow).cards.removeAll { $0 === ambusher }; o.grave.append(ambusher)
            draw(o, 2); sound("ambush")
        }
        if isSpy && side.leaderAbility == "novigrad_sigismund2" { draw(side, 1) }
        recalc()
        await pause(0.3)
        if card.hero { events.append(.anim(card, "hero")) }
        if card.locked { await animate(card, "lock"); return }
        if card.act("bond") {
            let group = row.cards.filter { $0.act("bond") && $0.groupKey == card.groupKey }
            if group.count > 1 { for member in group { await animate(member, "bond", wait: false) }; await pause(0.7) }
        } else if let animatedAbility = card.data.abilities.reversed().first(where: { Game.animName($0) != nil }) {
            await animate(card, animatedAbility)
        } else if card.hero { await pause(0.6) }
        await unitAbilities(card, by: player, side: side, row: chosenRow)
        recalc()
    }

    static let passiveLeaders: Set<String> = ["eredin_treacherous", "vilgefortz_magician_kovir", "emhyr_whiteflame", "imlerith_general", "meve_white_queen",
                                              "novigrad_sigismund", "novigrad_sigismund2", "ofir_aamad", "zerrikanterment", "caranthir_navigator",
                                              "ofir_aamad_crown", "lady_wood_brewess", "francesca_daisy", "king_bran", "madman_lugos"]

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

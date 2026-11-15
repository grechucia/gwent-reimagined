// Computer opponent: generates every legal move, scores it by simulating the board, and decides when to pass.
import Foundation

/// A candidate AI action with its evaluated value and the point gain it produces.
struct AIMove { let card: Card?; let row: RowType?; let rowOwner: Player?; let target: Card?; let value: Double; let gain: Int; let kind: Kind
    /// Whether the move plays a card, uses the leader or uses the faction ability.
    enum Kind { case card, leader, faction }
}

/// Heuristic weights used when valuing moves (in points of score difference).
enum AIWeights {
    /// Extra value for every muster copy that would follow the card.
    static let perMusterCopy = 2.5
    /// Extra value for reviving a unit with a medic.
    static let medic = 3.0
    /// Extra value for every berserker that a card would transform.
    static let perBerserker = 4.0
    /// Extra value for every berserker on a row when playing Mardroeme.
    static let perMardroemeBerserker = 5.0
    /// Card advantage from a spy (two extra cards).
    static let spy = 9.0
    /// Small cost of playing a weather card.
    static let weatherPenalty = -1.5
    /// Abilities that bring extra cards or flexibility, each worth a small bonus.
    static let utilityAbilities = ["necrophage", "goetia", "sage", "zirael", "naglfar", "bait", "invoke", "summon_one_of", "trade", "rune_call",
                                   "omen", "clairvoyance", "witch_hunt", "doppler", "aerondight", "wish1", "wish2", "wish3", "cull"]
    static let utilityAbility = 2.5
}

/// Collects the candidate moves of one evaluation and turns score changes into move values.
@MainActor
final class MoveCollector {
    /// Score difference (AI minus opponent) before any move.
    let baseScore: Int
    private(set) var moves: [AIMove] = []
    init(baseScore: Int) { self.baseScore = baseScore }

    /// Adds a card move. Its value is the score gain plus a bonus, minus the cost of spending the card.
    func add(_ card: Card, row: RowType? = nil, owner: Player? = nil, target: Card? = nil, scoreAfter: Int, bonus: Double) {
        let cost = Double(card.basePower) * 0.35 + (card.hero ? 2 : 0)
        let gain = scoreAfter - baseScore
        moves.append(AIMove(card: card, row: row, rowOwner: owner, target: target, value: Double(gain) + bonus - cost, gain: gain, kind: .card))
    }
    /// Adds a leader or faction move with an already computed value.
    func append(_ move: AIMove) { moves.append(move) }
}

/// AI logic implemented as an extension of the game engine.
@MainActor
extension Game {
    /// Snapshot of the board used to try a move and roll it back.
    struct Snap { var rows: [[Card]]; var specials: [[Card]]; var weather: [[Set<String>]]; var horns: [Bool] }
    /// Captures the current board state.
    func snap() -> Snap {
        let allRows = human.rows + computer.rows
        return Snap(rows: allRows.map { $0.cards }, specials: allRows.map { $0.specials }, weather: [human.weather, computer.weather], horns: allRows.map { $0.leaderHorn })
    }
    /// Restores a board state captured with snap().
    func restore(_ snapshot: Snap) {
        for (i, rowIndex) in (human.rows + computer.rows).enumerated() { rowIndex.cards = snapshot.rows[i]; rowIndex.specials = snapshot.specials[i]; rowIndex.leaderHorn = snapshot.horns[i] }
        human.weather = snapshot.weather[0]; computer.weather = snapshot.weather[1]
    }
    /// Returns how much the score difference changes for `ai` if `apply` is executed (the board is restored afterwards).
    func diffAfter(_ player: Player, _ apply: () -> Void) -> Int {
        let snapshot = snap()
        apply(); recalc()
        let scoreAfterMove = player.total - player.opponent.total
        restore(snapshot); recalc()
        return scoreAfterMove
    }
    /// Simulates removing the strongest non-hero units from the given rows (scorch-like effects).
    func killMax(_ cards: [Card], in rows: [Row]) {
        guard let highestPower = cards.filter({ !$0.hero }).map({ $0.power }).max(), highestPower > 0 else { return }
        for targetRow in rows where !targetRow.shielded { targetRow.cards.removeAll { !$0.hero && $0.power == highestPower && $0.immortalRounds == 0 } }
    }

    /// Lists every possible move for the AI player together with its estimated value.
    func aiMoves(for player: Player) -> [AIMove] {
        recalc()
        let collector = MoveCollector(baseScore: player.total - player.opponent.total)
        let playableCards = player.forcedCard.map { forced in player.hand.filter { $0 === forced } } ?? player.hand
        for card in playableCards {
            if card.isUnit { evaluateUnit(card, for: player, into: collector) }
            else if card.data.isWeather { evaluateWeather(card, for: player, into: collector) }
            else { evaluateSpecial(card, for: player, into: collector) }
        }
        if leaderAvailable(player) && player.forcedCard == nil { evaluateLeader(for: player, into: collector) }
        if let ability = factionActive(player), player.forcedCard == nil { evaluateFaction(ability, for: player, into: collector) }
        return collector.moves
    }

    /// Unit card: tries every row it can go to and simulates its main abilities (muster, medic, scorch, berserker).
    func evaluateUnit(_ card: Card, for player: Player, into collector: MoveCollector) {
        let enemy = player.opponent!
        let rows = card.has("ambush") ? [RowType.close] : card.allowedRows
        let isSpy = card.has("spy") || card.has("emissary") || card.has("ofiri_envoy")
        let side = isSpy ? enemy : player
        for rowType in rows {
            var bonus = 0.0
            let scoreAfter = diffAfter(player) {
                side.row(rowType).cards.append(card)
                if card.has("muster") {
                    let copies = (player.hand + player.deck).filter { $0 !== card && $0.groupKey == card.groupKey && $0.isUnit }
                    for copy in copies {
                        let copyRow = card.data.row.hasPrefix("agile") ? rowType : (RowType.from(copy.data.row) ?? rowType)
                        player.row(copyRow).cards.append(copy)
                    }
                    bonus += Double(copies.count) * AIWeights.perMusterCopy
                }
                if card.has("medic"), let revived = player.grave.filter({ $0.isUnit && !$0.hero }).max(by: { aiCardValue($0) < aiCardValue($1) }) {
                    player.row(revived.allowedRows.first ?? .close).cards.append(revived)
                    bonus += AIWeights.medic
                }
                recalc()
                for ability in card.data.abilities where ability.hasPrefix("scorch_") {
                    let targetRow = enemy.row(Game.scorchRow(for: ability))
                    if targetRow.total >= 10 { killMax(targetRow.cards, in: [targetRow]) }
                }
                if card.has("scorch") { killMax((player.rowCards + enemy.rowCards).filter { $0 !== card }, in: player.rows + enemy.rows) }
                let triggersBerserkers = card.has("mardroeme") || (card.has("berserker") && side.row(rowType).specials.contains { $0.specialKind == "mardroeme" })
                if triggersBerserkers {
                    bonus += Double(side.row(rowType).cards.filter { $0.has("berserker") }.count) * AIWeights.perBerserker
                }
            }
            if isSpy { bonus += AIWeights.spy }
            for ability in AIWeights.utilityAbilities where card.has(ability) { bonus += AIWeights.utilityAbility }
            collector.add(card, row: rowType, scoreAfter: scoreAfter, bonus: bonus)
        }
    }

    /// Weather card: simulates the weather on the rows it affects (storm can hit two different row pairs).
    func evaluateWeather(_ card: Card, for player: Player, into collector: MoveCollector) {
        let ability = card.data.abilities.first ?? ""
        let variants: [[RowType]] = ability == "storm" ? [[.close, .ranged], [.ranged, .siege]] : [weatherRows(ability, card)]
        var bestScore = Int.min
        for affectedRows in variants {
            let scoreAfter = diffAfter(player) {
                for side in [human, computer] {
                    if ability == "clear" { for i in 0..<3 { side.weather[i].removeAll() } }
                    else { for rowType in affectedRows { side.weather[rowType.rawValue].insert(ability) } }
                }
            }
            bestScore = max(bestScore, scoreAfter)
        }
        collector.add(card, scoreAfter: bestScore, bonus: AIWeights.weatherPenalty)
    }

    /// Special (non-weather) card: simulates or estimates the effect of each special kind.
    func evaluateSpecial(_ card: Card, for player: Player, into collector: MoveCollector) {
        let enemy = player.opponent!
        let base = collector.baseScore
        let kind = card.specialKind ?? ""
        switch kind {
        case "horn", "morale", "toussaint_wine", "mardroeme":
            for rowType in validRows(for: card, by: player) {
                let scoreAfter = diffAfter(player) { player.row(rowType).specials.append(card) }
                let berserkerBonus = kind == "mardroeme" ? Double(player.row(rowType).cards.filter { $0.has("berserker") }.count) * AIWeights.perMardroemeBerserker : 0
                collector.add(card, row: rowType, owner: player, scoreAfter: scoreAfter, bonus: berserkerBonus - 2.5)
            }
        case "shield", "shield_c", "shield_r", "shield_s":
            for rowType in validRows(for: card, by: player) {
                let threatened = enemy.hand.contains { $0.has("scorch") || $0.specialKind == "scorch" } || player.row(rowType).total >= 10
                collector.add(card, row: rowType, owner: player, scoreAfter: base, bonus: threatened ? Double(player.row(rowType).total) * 0.25 : -3)
            }
        case "lock":
            if let rowType = enemyRowTargets(for: card, by: player).first {
                collector.add(card, row: rowType, owner: enemy, scoreAfter: base, bonus: enemy.hand.count > 3 ? 2 : -2)
            }
        case "curse":
            collector.add(card, row: .close, owner: enemy, scoreAfter: base, bonus: enemy.hand.count > 3 ? 2.5 : -2)
        case "knockback":
            for rowType in [RowType.close, .ranged] {
                let scoreAfter = diffAfter(player) {
                    let destination: RowType = rowType == .close ? .ranged : .siege
                    let pushed = enemy.row(rowType).cards.filter { !$0.hero }
                    enemy.row(rowType).cards.removeAll { card in pushed.contains { $0 === card } }
                    enemy.row(destination).cards.append(contentsOf: pushed)
                }
                collector.add(card, row: rowType, owner: enemy, scoreAfter: scoreAfter, bonus: -1)
            }
        case "seize":
            collector.add(card, scoreAfter: diffAfter(player) { stealWeakest(from: enemy.row(.close), to: player.row(.close)) }, bonus: 0)
        case "stribog":
            collector.add(card, scoreAfter: diffAfter(player) { stealWeakest(from: enemy.row(.ranged), to: player.row(.ranged)) }, bonus: 0)
        case "scorch":
            collector.add(card, scoreAfter: diffAfter(player) { recalc(); killMax(player.rowCards + enemy.rowCards, in: player.rows + enemy.rows) }, bonus: -2)
        case "cull":
            let scoreAfter = diffAfter(player) {
                recalc()
                let units = (player.rowCards + enemy.rowCards).filter { !$0.hero }
                if let lowestPower = units.map({ $0.power }).min() {
                    for boardRow in player.rows + enemy.rows where !boardRow.shielded { boardRow.cards.removeAll { !$0.hero && $0.power == lowestPower } }
                }
            }
            collector.add(card, scoreAfter: scoreAfter, bonus: -1)
        case "clear":
            collector.add(card, scoreAfter: diffAfter(player) { for side in [human, computer] { for i in 0..<3 { side.weather[i].removeAll() } } }, bonus: -1)
        case "decoy":
            for target in decoyTargets(for: player) {
                let scoreAfter = diffAfter(player) { if let targetRow = player.rowOf(target) { player.row(targetRow).cards.removeAll { $0 === target } } }
                let bonus: Double = target.has("spy") ? AIWeights.spy : (target.has("medic") ? 4 : 0.5)
                collector.add(card, target: target, scoreAfter: scoreAfter, bonus: bonus)
            }
        case "bank", "skellige_fleet":
            collector.add(card, scoreAfter: base, bonus: 5)
        case "decoration":
            if !player.rowCards.filter({ !$0.hero }).isEmpty { collector.add(card, scoreAfter: base, bonus: 3) }
        case "royal_decree":
            if !Game.passiveLeaders.contains(player.leaderAbility) { collector.add(card, scoreAfter: base, bonus: 3) }
        case "door":
            if player.deck.contains(where: { $0.isUnit }) { collector.add(card, row: validRows(for: card, by: player).first, owner: player, scoreAfter: base, bonus: 3) }
        case "chernobog":
            if let strongest = strongestNonHero(player.row(.close).cards) { collector.add(card, scoreAfter: base + strongest.power, bonus: -1) }
        case "perun":
            if !player.row(.ranged).cards.filter({ !$0.hero }).isEmpty { collector.add(card, scoreAfter: base + 5, bonus: -1) }
        case "svarog", "morana":
            if let strongest = strongestNonHero(enemy.row(kind == "svarog" ? .siege : .close).cards) { collector.add(card, scoreAfter: base + strongest.power - 1, bonus: -1) }
        case "triglav":
            if !enemy.rowCards.filter({ $0.hero }).isEmpty { collector.add(card, scoreAfter: base, bonus: 2) }
        case "veles":
            if let strongest = strongestNonHero(player.rowCards) { collector.add(card, scoreAfter: base + strongest.power, bonus: -1) }
        case "devana":
            let loss = enemy.row(.ranged).cards.filter { !$0.hero }.map { max(0, $0.power - 2) }.reduce(0, +)
            collector.add(card, scoreAfter: base + loss, bonus: -1)
        case "zoria":
            collector.add(card, scoreAfter: diffAfter(player) { enemy.weather[0].insert("frost") }, bonus: -1)
        default:
            break
        }
    }

    /// Leader ability: simulated when its effect is simple, otherwise valued higher in later rounds.
    func evaluateLeader(for player: Player, into collector: MoveCollector) {
        let enemy = player.opponent!
        let ability = player.leaderAbility
        var scoreAfter: Int?
        switch ability {
        case "foltest_siegemaster": scoreAfter = diffAfter(player) { player.row(.siege).leaderHorn = true }
        case "francesca_beautiful": scoreAfter = diffAfter(player) { player.row(.ranged).leaderHorn = true }
        case "foltest_lord", "vilgefortz_sorcerer": scoreAfter = diffAfter(player) { for side in [human, computer] { for i in 0..<3 { side.weather[i].removeAll() } } }
        case "foltest_son", "foltest_steelforged", "francesca_queen", "cosimo_malaspina":
            let rowType: RowType = ability == "foltest_son" ? .ranged : (ability == "foltest_steelforged" ? .siege : .close)
            let targetRow = enemy.row(rowType)
            scoreAfter = targetRow.total >= 10 ? diffAfter(player) { killMax(targetRow.cards, in: [targetRow]) } : collector.baseScore - 5
        default: scoreAfter = nil
        }
        if let scoreAfter = scoreAfter {
            let gain = scoreAfter - collector.baseScore
            collector.append(AIMove(card: nil, row: nil, rowOwner: nil, target: nil, value: Double(gain) - 2, gain: gain, kind: .leader))
        } else {
            let value = 3.0 + Double(round) * 1.5 - Double(player.hand.count) * 0.3
            collector.append(AIMove(card: nil, row: nil, rowOwner: nil, target: nil, value: value, gain: 0, kind: .leader))
        }
    }

    /// Faction ability that can be activated during the turn.
    func evaluateFaction(_ ability: String, for player: Player, into collector: MoveCollector) {
        switch ability {
        case "morale":
            let fullestRow = RowType.allCases.max { player.row($0).cards.count < player.row($1).cards.count }!
            let gain = diffAfter(player) { player.row(fullestRow).factionMorale += 1 } - collector.baseScore
            collector.append(AIMove(card: nil, row: nil, rowOwner: nil, target: nil, value: Double(gain) - 1, gain: gain, kind: .faction))
        case "weather": collector.append(AIMove(card: nil, row: nil, rowOwner: nil, target: nil, value: 2, gain: 0, kind: .faction))
        case "transform": collector.append(AIMove(card: nil, row: nil, rowOwner: nil, target: nil, value: 4, gain: 3, kind: .faction))
        default: break
        }
    }

    /// Moves the weakest non-hero units of one row to another (seize-like effects), used in simulations.
    func stealWeakest(from source: Row, to destination: Row) {
        let units = source.cards.filter { !$0.hero }
        guard let lowestPower = units.map({ $0.power }).min() else { return }
        for unit in units where unit.power == lowestPower {
            source.cards.removeAll { $0 === unit }
            destination.cards.append(unit)
        }
    }

    /// The strongest non-hero card of a list.
    func strongestNonHero(_ cards: [Card]) -> Card? { cards.filter { !$0.hero }.max { $0.power < $1.power } }

    /// Row hit by a row-scorch ability ("scorch_c", "scorch_r" or "scorch_s").
    static func scorchRow(for ability: String) -> RowType { ability == "scorch_c" ? .close : (ability == "scorch_r" ? .ranged : .siege) }

    /// Chooses the move to play, or nil to pass, using round state and the configured difficulty.
    func aiDecide(for requestedPlayer: Player? = nil) -> AIMove? {
        let player = requestedPlayer ?? computer, foe: Player = player.opponent
        recalc()
        // Nothing left to play: pass.
        if player.hand.isEmpty && !leaderAvailable(player) { return nil }
        // Positive lead means the AI is ahead in the current round.
        let lead = player.total - foe.total
        let moves = aiMoves(for: player).sorted { $0.value > $1.value }
        guard let best = moves.first else { return nil }
        // A card that must be played this turn always wins.
        if let forced = player.forcedCard, let forcedMove = moves.first(where: { $0.card === forced }) { return forcedMove }
        // Easy and normal opponents sometimes deviate from the best move.
        if player === computer && aiLevel < 2, let weakerMove = weakenedChoice(moves, ai: player, foe: foe, lead: lead) { return weakerMove }
        // With one life left the AI cannot afford to lose this round.
        let mustWin = player.gems == 1
        // The opponent passed: play the cheapest card that takes the lead, or pass if already ahead.
        if foe.passed {
            if lead > 0 { return nil }
            if let winningMove = moves.filter({ lead + $0.gain > 0 }).min(by: { ($0.card?.basePower ?? 0) < ($1.card?.basePower ?? 0) }) { return winningMove }
            let potential = moves.map { max(0, $0.gain) }.reduce(0, +)
            if mustWin || lead + potential > 0 { return best }
            return nil
        }
        // Comfortable lead: pass to save cards.
        if !mustWin && lead >= 14 && player.hand.count <= foe.hand.count { return nil }
        // Hopeless first round: pass and keep cards for later rounds.
        if !mustWin && round == 1 && foe.gems == 2 && lead < -25 && player.hand.count < foe.hand.count { return nil }
        // Every move would cost more than it gains while ahead: pass.
        if best.value < -6 && !mustWin && lead > 0 { return nil }
        return best
    }

    /// Easier opponents sometimes play a weaker move instead of the best one, and pass less cleverly.
    func weakenedChoice(_ moves: [AIMove], ai player: Player, foe: Player, lead: Int) -> AIMove? {
        let mistake: Double = aiLevel == 0 ? 0.5 : 0.2
        guard moves.count > 1, Double.random(in: 0..<1) < mistake else { return nil }
        if aiLevel == 0 && !foe.passed && lead > 0 && player.gems == 2 && Double.random(in: 0..<1) < 0.3 { return nil }
        let pool = moves.prefix(aiLevel == 0 ? max(2, moves.count / 2) : min(3, moves.count)).dropFirst()
        return pool.randomElement()
    }

    /// Performs the AI player's turn.
    func aiTurn(_ player: Player) async {
        guard phase == .play, current === player, !busy else { return }
        busy = true
        defer { busy = false }
        aiPlayer = player
        let move = aiDecide(for: player)
        if let factionAbility = factionActive(player), factionAbility.hasPrefix("skip"), (move?.value ?? -10) < 0, !player.opponent.passed {
            await useFaction(player); return
        }
        guard let chosenMove = move else { await pass(player); return }
        switch chosenMove.kind {
        case .leader: await useLeader(player)
        case .faction: await useFaction(player)
        case .card:
            if let card = chosenMove.card { await play(card, by: player, row: chosenMove.row, rowOwner: chosenMove.rowOwner, target: chosenMove.target) } else { await pass(player) }
        }
    }
}

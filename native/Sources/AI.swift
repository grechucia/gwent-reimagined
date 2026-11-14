// Computer opponent: generates every legal move, scores it by simulating the board, and decides when to pass.
import Foundation

/// A candidate AI action with its evaluated value and the point gain it produces.
struct AIMove { let card: Card?; let row: RowType?; let rowOwner: Player?; let target: Card?; let value: Double; let gain: Int; let kind: Kind
    /// Whether the move plays a card, uses the leader or uses the faction ability.
    enum Kind { case card, leader, faction }
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
    func diffAfter(_ ai: Player, _ apply: () -> Void) -> Int {
        let snapshot = snap()
        apply(); recalc()
        let scoreBefore = ai.total - ai.opponent.total
        restore(snapshot); recalc()
        return scoreBefore
    }
    /// Simulates removing the strongest non-hero units from the given rows (scorch-like effects).
    func killMax(_ cards: [Card], in rows: [Row]) {
        guard let highestPower = cards.filter({ !$0.hero }).map({ $0.power }).max(), highestPower > 0 else { return }
        for targetRow in rows where !targetRow.shielded { targetRow.cards.removeAll { !$0.hero && $0.power == highestPower && $0.immortalRounds == 0 } }
    }

    /// Lists every possible move for the AI player together with its estimated value.
    func aiMoves(for ai: Player) -> [AIMove] {
        let foe: Player = ai.opponent
        recalc()
        let base = ai.total - foe.total
        var moves: [AIMove] = []
        let hand = ai.forcedCard.map { f in ai.hand.filter { $0 === f } } ?? ai.hand
        /// Records one candidate move.
        func add(_ c: Card?, _ rowType: RowType?, _ owner: Player?, _ t: Card?, _ scoreAfter: Int, _ extra: Double, _ kind: AIMove.Kind = .card) {
            let cost = c.map { Double($0.basePower) * 0.35 + ($0.hero ? 2 : 0) } ?? 0
            moves.append(AIMove(card: c, row: rowType, rowOwner: owner, target: t, value: Double(scoreAfter - base) + extra - cost, gain: scoreAfter - base, kind: kind))
        }
        for handCard in hand {
            if handCard.isUnit {
                let rows = handCard.has("ambush") ? [RowType.close] : handCard.allowedRows
                for rowType in rows {
                    let isSpy = handCard.has("spy") || handCard.has("emissary") || handCard.has("ofiri_envoy")
                    let side = isSpy ? foe : ai
                    var extra = 0.0
                    let scoreGain = diffAfter(ai) {
                        side.row(rowType).cards.append(handCard)
                        if handCard.has("muster") {
                            let ms = (ai.hand + ai.deck).filter { $0 !== handCard && $0.groupKey == handCard.groupKey && $0.isUnit }
                            for candidateMove in ms { ai.row(handCard.data.row.hasPrefix("agile") ? rowType : (RowType.from(candidateMove.data.row) ?? rowType)).cards.append(candidateMove) }
                            extra += Double(ms.count) * 2.5
                        }
                        if handCard.has("medic"), let best = ai.grave.filter({ $0.isUnit && !$0.hero }).max(by: { aiCardValue($0) < aiCardValue($1) }) {
                            ai.row(best.allowedRows.first ?? .close).cards.append(best); extra += 3
                        }
                        recalc()
                        for ability in handCard.data.abilities where ability.hasPrefix("scorch_") {
                            let scorchRow: RowType = ability == "scorch_c" ? .close : (ability == "scorch_r" ? .ranged : .siege)
                            if foe.row(scorchRow).total >= 10 { killMax(foe.row(scorchRow).cards, in: [foe.row(scorchRow)]) }
                        }
                        if handCard.has("scorch") { killMax((ai.rowCards + foe.rowCards).filter { $0 !== handCard }, in: ai.rows + foe.rows) }
                        if handCard.has("mardroeme") || (handCard.has("berserker") && side.row(rowType).specials.contains { $0.specialKind == "mardroeme" }) {
                            for berserker in side.row(rowType).cards where berserker.has("berserker") { extra += 4; _ = berserker }
                        }
                    }
                    if isSpy { extra += 9 }
                    for ability in ["necrophage", "goetia", "sage", "zirael", "naglfar", "bait", "invoke", "summon_one_of", "trade", "rune_call", "omen", "clairvoyance", "witch_hunt", "doppler", "aerondight", "wish1", "wish2", "wish3", "cull"] where handCard.has(ability) { extra += 2.5 }
                    add(handCard, rowType, nil, nil, scoreGain, extra)
                }
            } else if handCard.data.isWeather {
                let a = handCard.data.abilities.first ?? ""
                var options: [[RowType]] = []
                switch a {
                case "storm": options = [[.close, .ranged], [.ranged, .siege]]
                case "clear": options = [[]]
                case "frost", "spider_web": options = [[.close]]
                case "fog", "tse_tse": options = [[.ranged]]
                case "rain", "dragon_wrath": options = [[.siege]]
                case "sandstorm": options = [[.close, .ranged]]
                case "white_frost": options = [handCard.data.row == "agile_cs" ? [.close, .siege] : (handCard.data.row == "agile_rs" ? [.ranged, .siege] : [.close, .ranged])]
                default: options = [[]]
                }
                var bestD = Int.min
                for option in options {
                    let scoreGain = diffAfter(ai) {
                        if a == "clear" { for side in [human, computer] { for i in 0..<3 { side.weather[i].removeAll() } } }
                        else { for side in [human, computer] { for rowType in option { side.weather[rowType.rawValue].insert(a) } } }
                    }
                    bestD = max(bestD, scoreGain)
                }
                add(handCard, nil, nil, nil, bestD, -1.5)
            } else {
                let k = handCard.specialKind ?? ""
                switch k {
                case "horn", "morale", "toussaint_wine", "mardroeme":
                    for rowType in validRows(for: handCard, by: ai) {
                        var extra = 0.0
                        let scoreGain = diffAfter(ai) { ai.row(rowType).specials.append(handCard) }
                        if k == "mardroeme" { extra = Double(ai.row(rowType).cards.filter { $0.has("berserker") }.count) * 5 }
                        add(handCard, rowType, ai, nil, scoreGain, extra - 2.5)
                    }
                case "shield", "shield_c", "shield_r", "shield_s":
                    for rowType in validRows(for: handCard, by: ai) {
                        let danger = foe.hand.contains { $0.has("scorch") || $0.specialKind == "scorch" } || ai.row(rowType).total >= 10
                        add(handCard, rowType, ai, nil, base, danger ? Double(ai.row(rowType).total) * 0.25 : -3)
                    }
                case "lock":
                    if let rowType = enemyRowTargets(for: handCard, by: ai).first { add(handCard, rowType, foe, nil, base, foe.hand.count > 3 ? 2 : -2) }
                case "curse":
                    add(handCard, .close, foe, nil, base, foe.hand.count > 3 ? 2.5 : -2)
                case "knockback":
                    for rowType in [RowType.close, .ranged] {
                        let scoreGain = diffAfter(ai) {
                            let dest: RowType = rowType == .close ? .ranged : .siege
                            let enemyCards = foe.row(rowType).cards.filter { !$0.hero }
                            foe.row(rowType).cards.removeAll { x in enemyCards.contains { $0 === x } }; foe.row(dest).cards.append(contentsOf: enemyCards)
                        }
                        add(handCard, rowType, foe, nil, scoreGain, -1)
                    }
                case "seize":
                    let d = diffAfter(ai) {
                        let enemyCards = foe.row(.close).cards.filter { !$0.hero }
                        if let lowestPower = enemyCards.map({ $0.power }).min() { for t in enemyCards where t.power == lowestPower { foe.row(.close).cards.removeAll { $0 === t }; ai.row(.close).cards.append(t) } }
                    }
                    add(handCard, nil, nil, nil, d, 0)
                case "scorch":
                    let d = diffAfter(ai) { recalc(); killMax(ai.rowCards + foe.rowCards, in: ai.rows + foe.rows) }
                    add(handCard, nil, nil, nil, d, -2)
                case "cull":
                    let d = diffAfter(ai) {
                        recalc()
                        let all = (ai.rowCards + foe.rowCards).filter { !$0.hero }
                        if let lowestPower = all.map({ $0.power }).min() { for r in ai.rows + foe.rows where !r.shielded { r.cards.removeAll { !$0.hero && $0.power == lowestPower } } }
                    }
                    add(handCard, nil, nil, nil, d, -1)
                case "clear":
                    let d = diffAfter(ai) { for q in [human, computer] { for i in 0..<3 { q.weather[i].removeAll() } } }
                    add(handCard, nil, nil, nil, d, -1)
                case "decoy":
                    for decoyTargetCards in decoyTargets(for: ai) {
                        let scoreGain = diffAfter(ai) { if let r = ai.rowOf(decoyTargetCards) { ai.row(r).cards.removeAll { $0 === decoyTargetCards } } }
                        let bonus: Double = decoyTargetCards.has("spy") ? 9 : (decoyTargetCards.has("medic") ? 4 : 0.5)
                        add(handCard, nil, nil, decoyTargetCards, scoreGain, bonus)
                    }
                case "bank", "skellige_fleet": add(handCard, nil, nil, nil, base, 5)
                case "decoration": if !ai.rowCards.filter({ !$0.hero }).isEmpty { add(handCard, nil, nil, nil, base, 3) }
                case "royal_decree": if !Game.passiveLeaders.contains(ai.leaderAbility) { add(handCard, nil, nil, nil, base, 3) }
                case "door": if ai.deck.contains(where: { $0.isUnit }) { add(handCard, validRows(for: handCard, by: ai).first, ai, nil, base, 3) }
                case "chernobog":
                    if let strongestCloseUnit = ai.row(.close).cards.filter({ !$0.hero }).max(by: { $0.power < $1.power }) { add(handCard, nil, nil, nil, base + strongestCloseUnit.power, -1) }
                case "perun": if !ai.row(.ranged).cards.filter({ !$0.hero }).isEmpty { add(handCard, nil, nil, nil, base + 5, -1) }
                case "svarog", "morana":
                    if let enemyCandidates = foe.row(k == "svarog" ? .siege : .close).cards.filter({ !$0.hero }).max(by: { $0.power < $1.power }) { add(handCard, nil, nil, nil, base + enemyCandidates.power - 1, -1) }
                case "triglav": if !foe.rowCards.filter({ $0.hero }).isEmpty { add(handCard, nil, nil, nil, base, 2) }
                case "veles":
                    if let candidates = ai.rowCards.filter({ !$0.hero }).max(by: { $0.power < $1.power }) { add(handCard, nil, nil, nil, base + candidates.power, -1) }
                case "devana":
                    let loss = foe.row(.ranged).cards.filter { !$0.hero }.map { max(0, $0.power - 2) }.reduce(0, +)
                    add(handCard, nil, nil, nil, base + loss, -1)
                case "zoria":
                    let d = diffAfter(ai) { foe.weather[0].insert("frost") }
                    add(handCard, nil, nil, nil, d, -1)
                case "stribog":
                    let scoreGain = diffAfter(ai) {
                        let enemyCards = foe.row(.ranged).cards.filter { !$0.hero }
                        if let lowestPower = enemyCards.map({ $0.power }).min() { for candidates in enemyCards where candidates.power == lowestPower { foe.row(.ranged).cards.removeAll { $0 === candidates }; ai.row(.ranged).cards.append(candidates) } }
                    }
                    add(handCard, nil, nil, nil, scoreGain, 0)
                default: break
                }
            }
        }
        if leaderAvailable(ai) && ai.forcedCard == nil {
            let la = ai.leaderAbility
            var leaderGain: Int? = nil
            switch la {
            case "foltest_siegemaster": leaderGain = diffAfter(ai) { ai.row(.siege).leaderHorn = true }
            case "francesca_beautiful": leaderGain = diffAfter(ai) { ai.row(.ranged).leaderHorn = true }
            case "foltest_lord", "vilgefortz_sorcerer": leaderGain = diffAfter(ai) { for side in [human, computer] { for i in 0..<3 { side.weather[i].removeAll() } } }
            case "foltest_son", "foltest_steelforged", "francesca_queen", "cosimo_malaspina":
                let hornRow: RowType = la == "foltest_son" ? .ranged : (la == "foltest_steelforged" ? .siege : .close)
                leaderGain = foe.row(hornRow).total >= 10 ? diffAfter(ai) { killMax(foe.row(hornRow).cards, in: [foe.row(hornRow)]) } : base - 5
            default: leaderGain = nil
            }
            if let leaderGain = leaderGain { moves.append(AIMove(card: nil, row: nil, rowOwner: nil, target: nil, value: Double(leaderGain - base) - 2, gain: leaderGain - base, kind: .leader)) }
            else {
                let leaderValue = 3.0 + Double(round) * 1.5 - Double(ai.hand.count) * 0.3
                moves.append(AIMove(card: nil, row: nil, rowOwner: nil, target: nil, value: leaderValue, gain: 0, kind: .leader))
            }
        }
        if let factionAbility = factionActive(ai), ai.forcedCard == nil {
            switch factionAbility {
            case "morale":
                let fullestRow = RowType.allCases.max { ai.row($0).cards.count < ai.row($1).cards.count }!
                let scoreGain = diffAfter(ai) { ai.row(fullestRow).factionMorale += 1 }
                moves.append(AIMove(card: nil, row: nil, rowOwner: nil, target: nil, value: Double(scoreGain - base) - 1, gain: scoreGain - base, kind: .faction))
            case "weather": moves.append(AIMove(card: nil, row: nil, rowOwner: nil, target: nil, value: 2, gain: 0, kind: .faction))
            case "transform": moves.append(AIMove(card: nil, row: nil, rowOwner: nil, target: nil, value: 4, gain: 3, kind: .faction))
            default: break
            }
        }
        return moves
    }

    /// Chooses the move to play, or nil to pass, using round state and the configured difficulty.
    func aiDecide(for requestedPlayer: Player? = nil) -> AIMove? {
        let ai = requestedPlayer ?? computer, foe: Player = ai.opponent
        recalc()
        // Nothing left to play: pass.
        if ai.hand.isEmpty && !leaderAvailable(ai) { return nil }
        // Positive lead means the AI is ahead in the current round.
        let lead = ai.total - foe.total
        let moves = aiMoves(for: ai).sorted { $0.value > $1.value }
        guard let best = moves.first else { return nil }
        // A card that must be played this turn always wins.
        if let forced = ai.forcedCard, let m = moves.first(where: { $0.card === forced }) { return m }
        // Easy and normal opponents sometimes deviate from the best move.
        if ai === computer && aiLevel < 2, let weakerMove = weakenedChoice(moves, ai: ai, foe: foe, lead: lead) { return weakerMove }
        // With one life left the AI cannot afford to lose this round.
        let mustWin = ai.gems == 1
        // The opponent passed: play the cheapest card that takes the lead, or pass if already ahead.
        if foe.passed {
            if lead > 0 { return nil }
            if let winningMove = moves.filter({ lead + $0.gain > 0 }).min(by: { ($0.card?.basePower ?? 0) < ($1.card?.basePower ?? 0) }) { return winningMove }
            let potential = moves.map { max(0, $0.gain) }.reduce(0, +)
            if mustWin || lead + potential > 0 { return best }
            return nil
        }
        // Comfortable lead: pass to save cards.
        if !mustWin && lead >= 14 && ai.hand.count <= foe.hand.count { return nil }
        // Hopeless first round: pass and keep cards for later rounds.
        if !mustWin && round == 1 && foe.gems == 2 && lead < -25 && ai.hand.count < foe.hand.count { return nil }
        // Every move would cost more than it gains while ahead: pass.
        if best.value < -6 && !mustWin && lead > 0 { return nil }
        return best
    }

    /// Easier opponents sometimes play a weaker move instead of the best one, and pass less cleverly.
    func weakenedChoice(_ moves: [AIMove], ai: Player, foe: Player, lead: Int) -> AIMove? {
        let mistake: Double = aiLevel == 0 ? 0.5 : 0.2
        guard moves.count > 1, Double.random(in: 0..<1) < mistake else { return nil }
        if aiLevel == 0 && !foe.passed && lead > 0 && ai.gems == 2 && Double.random(in: 0..<1) < 0.3 { return nil }
        let pool = moves.prefix(aiLevel == 0 ? max(2, moves.count / 2) : min(3, moves.count)).dropFirst()
        return pool.randomElement()
    }

    /// Performs the AI player's turn.
    func aiTurn(_ ai: Player) async {
        guard phase == .play, current === ai, !busy else { return }
        busy = true
        defer { busy = false }
        aiPlayer = ai
        let move = aiDecide(for: ai)
        if let factionAbility = factionActive(ai), factionAbility.hasPrefix("skip"), (move?.value ?? -10) < 0, !ai.opponent.passed {
            await useFaction(ai); return
        }
        guard let mv = move else { await pass(ai); return }
        switch mv.kind {
        case .leader: await useLeader(ai)
        case .faction: await useFaction(ai)
        case .card:
            if let card = mv.card { await play(card, by: ai, row: mv.row, rowOwner: mv.rowOwner, target: mv.target) } else { await pass(ai) }
        }
    }
}

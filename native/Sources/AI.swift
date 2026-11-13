import Foundation

struct AIMove { let card: Card?; let row: RowType?; let rowOwner: Player?; let target: Card?; let value: Double; let gain: Int; let kind: Kind
    enum Kind { case card, leader, faction }
}

@MainActor
extension Game {
    private struct Snap { var rows: [[Card]]; var specials: [[Card]]; var weather: [[Set<String>]]; var horns: [Bool] }
    private func snap() -> Snap {
        let rs = me.rows + op.rows
        return Snap(rows: rs.map { $0.cards }, specials: rs.map { $0.specials }, weather: [me.weather, op.weather], horns: rs.map { $0.leaderHorn })
    }
    private func restore(_ s: Snap) {
        for (i, r) in (me.rows + op.rows).enumerated() { r.cards = s.rows[i]; r.specials = s.specials[i]; r.leaderHorn = s.horns[i] }
        me.weather = s.weather[0]; op.weather = s.weather[1]
    }
    private func diffAfter(_ ai: Player, _ apply: () -> Void) -> Int {
        let s = snap()
        apply(); recalc()
        let d = ai.total - ai.opponent.total
        restore(s); recalc()
        return d
    }
    private func killMax(_ cards: [Card], in rows: [Row]) {
        guard let mx = cards.filter({ !$0.hero }).map({ $0.power }).max(), mx > 0 else { return }
        for r in rows where !r.shielded { r.cards.removeAll { !$0.hero && $0.power == mx && $0.immortalRounds == 0 } }
    }

    func aiMoves(for ai: Player) -> [AIMove] {
        let foe: Player = ai.opponent
        recalc()
        let base = ai.total - foe.total
        var moves: [AIMove] = []
        let hand = ai.forcedCard.map { f in ai.hand.filter { $0 === f } } ?? ai.hand
        func add(_ c: Card?, _ r: RowType?, _ ro: Player?, _ t: Card?, _ d: Int, _ extra: Double, _ kind: AIMove.Kind = .card) {
            let cost = c.map { Double($0.basePower) * 0.35 + ($0.hero ? 2 : 0) } ?? 0
            moves.append(AIMove(card: c, row: r, rowOwner: ro, target: t, value: Double(d - base) + extra - cost, gain: d - base, kind: kind))
        }
        for c in hand {
            if c.isUnit {
                let rows = c.has("ambush") ? [RowType.close] : c.allowedRows
                for r in rows {
                    let isSpy = c.has("spy") || c.has("emissary") || c.has("ofiri_envoy")
                    let side = isSpy ? foe : ai
                    var extra = 0.0
                    let d = diffAfter(ai) {
                        side.row(r).cards.append(c)
                        if c.has("muster") {
                            let ms = (ai.hand + ai.deck).filter { $0 !== c && $0.groupKey == c.groupKey && $0.isUnit }
                            for m in ms { ai.row(c.data.row.hasPrefix("agile") ? r : (RowType.from(m.data.row) ?? r)).cards.append(m) }
                            extra += Double(ms.count) * 2.5
                        }
                        if c.has("medic"), let best = ai.grave.filter({ $0.isUnit && !$0.hero }).max(by: { aiCardValue($0) < aiCardValue($1) }) {
                            ai.row(best.allowedRows.first ?? .close).cards.append(best); extra += 3
                        }
                        recalc()
                        for a in c.data.abilities where a.hasPrefix("scorch_") {
                            let t: RowType = a == "scorch_c" ? .close : (a == "scorch_r" ? .ranged : .siege)
                            if foe.row(t).total >= 10 { killMax(foe.row(t).cards, in: [foe.row(t)]) }
                        }
                        if c.has("scorch") { killMax((ai.rowCards + foe.rowCards).filter { $0 !== c }, in: ai.rows + foe.rows) }
                        if c.has("mardroeme") || (c.has("berserker") && side.row(r).specials.contains { $0.specialKind == "mardroeme" }) {
                            for b in side.row(r).cards where b.has("berserker") { extra += 4; _ = b }
                        }
                    }
                    if isSpy { extra += 9 }
                    for a in ["necrophage", "goetia", "sage", "zirael", "naglfar", "bait", "invoke", "summon_one_of", "trade", "rune_call", "omen", "clairvoyance", "witch_hunt", "doppler", "aerondight", "wish1", "wish2", "wish3", "cull"] where c.has(a) { extra += 2.5 }
                    add(c, r, nil, nil, d, extra)
                }
            } else if c.data.isWeather {
                let a = c.data.abilities.first ?? ""
                var options: [[RowType]] = []
                switch a {
                case "storm": options = [[.close, .ranged], [.ranged, .siege]]
                case "clear": options = [[]]
                case "frost", "spider_web": options = [[.close]]
                case "fog", "tse_tse": options = [[.ranged]]
                case "rain", "dragon_wrath": options = [[.siege]]
                case "sandstorm": options = [[.close, .ranged]]
                case "white_frost": options = [c.data.row == "agile_cs" ? [.close, .siege] : (c.data.row == "agile_rs" ? [.ranged, .siege] : [.close, .ranged])]
                default: options = [[]]
                }
                var bestD = Int.min
                for o in options {
                    let d = diffAfter(ai) {
                        if a == "clear" { for q in [me, op] { for i in 0..<3 { q.weather[i].removeAll() } } }
                        else { for q in [me, op] { for r in o { q.weather[r.rawValue].insert(a) } } }
                    }
                    bestD = max(bestD, d)
                }
                add(c, nil, nil, nil, bestD, -1.5)
            } else {
                let k = c.specialKind ?? ""
                switch k {
                case "horn", "morale", "toussaint_wine", "mardroeme":
                    for r in validRows(for: c, by: ai) {
                        var extra = 0.0
                        let d = diffAfter(ai) { ai.row(r).specials.append(c) }
                        if k == "mardroeme" { extra = Double(ai.row(r).cards.filter { $0.has("berserker") }.count) * 5 }
                        add(c, r, ai, nil, d, extra - 2.5)
                    }
                case "shield", "shield_c", "shield_r", "shield_s":
                    for r in validRows(for: c, by: ai) {
                        let danger = foe.hand.contains { $0.has("scorch") || $0.specialKind == "scorch" } || ai.row(r).total >= 10
                        add(c, r, ai, nil, base, danger ? Double(ai.row(r).total) * 0.25 : -3)
                    }
                case "lock":
                    if let r = enemyRowTargets(for: c, by: ai).first { add(c, r, foe, nil, base, foe.hand.count > 3 ? 2 : -2) }
                case "curse":
                    add(c, .close, foe, nil, base, foe.hand.count > 3 ? 2.5 : -2)
                case "knockback":
                    for r in [RowType.close, .ranged] {
                        let d = diffAfter(ai) {
                            let dest: RowType = r == .close ? .ranged : .siege
                            let mv = foe.row(r).cards.filter { !$0.hero }
                            foe.row(r).cards.removeAll { x in mv.contains { $0 === x } }; foe.row(dest).cards.append(contentsOf: mv)
                        }
                        add(c, r, foe, nil, d, -1)
                    }
                case "seize":
                    let d = diffAfter(ai) {
                        let units = foe.row(.close).cards.filter { !$0.hero }
                        if let mn = units.map({ $0.power }).min() { for t in units where t.power == mn { foe.row(.close).cards.removeAll { $0 === t }; ai.row(.close).cards.append(t) } }
                    }
                    add(c, nil, nil, nil, d, 0)
                case "scorch":
                    let d = diffAfter(ai) { recalc(); killMax(ai.rowCards + foe.rowCards, in: ai.rows + foe.rows) }
                    add(c, nil, nil, nil, d, -2)
                case "cull":
                    let d = diffAfter(ai) {
                        recalc()
                        let all = (ai.rowCards + foe.rowCards).filter { !$0.hero }
                        if let mn = all.map({ $0.power }).min() { for r in ai.rows + foe.rows where !r.shielded { r.cards.removeAll { !$0.hero && $0.power == mn } } }
                    }
                    add(c, nil, nil, nil, d, -1)
                case "clear":
                    let d = diffAfter(ai) { for q in [me, op] { for i in 0..<3 { q.weather[i].removeAll() } } }
                    add(c, nil, nil, nil, d, -1)
                case "decoy":
                    for t in decoyTargets(for: ai) {
                        let d = diffAfter(ai) { if let r = ai.rowOf(t) { ai.row(r).cards.removeAll { $0 === t } } }
                        let bonus: Double = t.has("spy") ? 9 : (t.has("medic") ? 4 : 0.5)
                        add(c, nil, nil, t, d, bonus)
                    }
                case "bank", "skellige_fleet": add(c, nil, nil, nil, base, 5)
                case "decoration": if !ai.rowCards.filter({ !$0.hero }).isEmpty { add(c, nil, nil, nil, base, 3) }
                case "royal_decree": if !Game.passiveLeaders.contains(ai.leaderAbility) { add(c, nil, nil, nil, base, 3) }
                case "door": if ai.deck.contains(where: { $0.isUnit }) { add(c, validRows(for: c, by: ai).first, ai, nil, base, 3) }
                case "chernobog":
                    if let t = ai.row(.close).cards.filter({ !$0.hero }).max(by: { $0.power < $1.power }) { add(c, nil, nil, nil, base + t.power, -1) }
                case "perun": if !ai.row(.ranged).cards.filter({ !$0.hero }).isEmpty { add(c, nil, nil, nil, base + 5, -1) }
                case "svarog", "morana":
                    if let t = foe.row(k == "svarog" ? .siege : .close).cards.filter({ !$0.hero }).max(by: { $0.power < $1.power }) { add(c, nil, nil, nil, base + t.power - 1, -1) }
                case "triglav": if !foe.rowCards.filter({ $0.hero }).isEmpty { add(c, nil, nil, nil, base, 2) }
                case "veles":
                    if let t = ai.rowCards.filter({ !$0.hero }).max(by: { $0.power < $1.power }) { add(c, nil, nil, nil, base + t.power, -1) }
                case "devana":
                    let loss = foe.row(.ranged).cards.filter { !$0.hero }.map { max(0, $0.power - 2) }.reduce(0, +)
                    add(c, nil, nil, nil, base + loss, -1)
                case "zoria":
                    let d = diffAfter(ai) { foe.weather[0].insert("frost") }
                    add(c, nil, nil, nil, d, -1)
                case "stribog":
                    let d = diffAfter(ai) {
                        let units = foe.row(.ranged).cards.filter { !$0.hero }
                        if let mn = units.map({ $0.power }).min() { for t in units where t.power == mn { foe.row(.ranged).cards.removeAll { $0 === t }; ai.row(.ranged).cards.append(t) } }
                    }
                    add(c, nil, nil, nil, d, 0)
                default: break
                }
            }
        }
        if leaderAvailable(ai) && ai.forcedCard == nil {
            let la = ai.leaderAbility
            var d: Int? = nil
            switch la {
            case "foltest_siegemaster": d = diffAfter(ai) { ai.row(.siege).leaderHorn = true }
            case "francesca_beautiful": d = diffAfter(ai) { ai.row(.ranged).leaderHorn = true }
            case "foltest_lord", "vilgefortz_sorcerer": d = diffAfter(ai) { for q in [me, op] { for i in 0..<3 { q.weather[i].removeAll() } } }
            case "foltest_son", "foltest_steelforged", "francesca_queen", "cosimo_malaspina":
                let t: RowType = la == "foltest_son" ? .ranged : (la == "foltest_steelforged" ? .siege : .close)
                d = foe.row(t).total >= 10 ? diffAfter(ai) { killMax(foe.row(t).cards, in: [foe.row(t)]) } : base - 5
            default: d = nil
            }
            if let d = d { moves.append(AIMove(card: nil, row: nil, rowOwner: nil, target: nil, value: Double(d - base) - 2, gain: d - base, kind: .leader)) }
            else {
                let v = 3.0 + Double(round) * 1.5 - Double(ai.hand.count) * 0.3
                moves.append(AIMove(card: nil, row: nil, rowOwner: nil, target: nil, value: v, gain: 0, kind: .leader))
            }
        }
        if let f = factionActive(ai), ai.forcedCard == nil {
            switch f {
            case "morale":
                let r = RowType.allCases.max { ai.row($0).cards.count < ai.row($1).cards.count }!
                let d = diffAfter(ai) { ai.row(r).factionMorale += 1 }
                moves.append(AIMove(card: nil, row: nil, rowOwner: nil, target: nil, value: Double(d - base) - 1, gain: d - base, kind: .faction))
            case "weather": moves.append(AIMove(card: nil, row: nil, rowOwner: nil, target: nil, value: 2, gain: 0, kind: .faction))
            case "transform": moves.append(AIMove(card: nil, row: nil, rowOwner: nil, target: nil, value: 4, gain: 3, kind: .faction))
            default: break
            }
        }
        return moves
    }

    func aiDecide(for ai0: Player? = nil) -> AIMove? {
        let ai = ai0 ?? op, foe: Player = ai.opponent
        recalc()
        if ai.hand.isEmpty && !leaderAvailable(ai) { return nil }
        let lead = ai.total - foe.total
        let moves = aiMoves(for: ai).sorted { $0.value > $1.value }
        guard let best = moves.first else { return nil }
        if let f = ai.forcedCard, let m = moves.first(where: { $0.card === f }) { return m }
        let mustWin = ai.gems == 1
        if foe.passed {
            if lead > 0 { return nil }
            if let win = moves.filter({ lead + $0.gain > 0 }).min(by: { ($0.card?.basePower ?? 0) < ($1.card?.basePower ?? 0) }) { return win }
            let potential = moves.map { max(0, $0.gain) }.reduce(0, +)
            if mustWin || lead + potential > 0 { return best }
            return nil
        }
        if !mustWin && lead >= 14 && ai.hand.count <= foe.hand.count { return nil }
        if !mustWin && round == 1 && foe.gems == 2 && lead < -25 && ai.hand.count < foe.hand.count { return nil }
        if best.value < -6 && !mustWin && lead > 0 { return nil }
        return best
    }

    func aiTurn(_ ai: Player) async {
        guard phase == .play, current === ai, !busy else { return }
        busy = true
        defer { busy = false }
        aiPlayer = ai
        let m = aiDecide(for: ai)
        if let f = factionActive(ai), f.hasPrefix("skip"), (m?.value ?? -10) < 0, !ai.opponent.passed {
            await useFaction(ai); return
        }
        guard let mv = m else { await pass(ai); return }
        switch mv.kind {
        case .leader: await useLeader(ai)
        case .faction: await useFaction(ai)
        case .card:
            if let c = mv.card { await play(c, by: ai, row: mv.row, rowOwner: mv.rowOwner, target: mv.target) } else { await pass(ai) }
        }
    }
}

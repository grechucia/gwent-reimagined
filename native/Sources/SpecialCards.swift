// Special and weather cards, plus destruction effects (scorch, cull, row scorch, seize).
import Foundation

extension Game {
    /// Resolves a special (non-weather) card.
    func playSpecial(_ card: Card, by player: Player, row: RowType?, rowOwner: Player?, target: Card?) async {
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
    func seize(_ player: Player, _ rowType: RowType) async {
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
    func weatherRows(_ ability: String, _ card: Card) -> [RowType] {
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
    func playWeather(_ card: Card, by player: Player, row: RowType?) async {
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
    func clearWeather() async {
        for c in weatherCards { c.owner?.grave.append(c) }
        weatherCards.removeAll()
        for q in [human, computer] { for i in 0..<3 { q.weather[i].removeAll() } }
        sound("clear")
        recalc()
    }

    /// Whether a card is protected from destruction (e.g. by a shield).
    func protected(_ card: Card, side: Player) async -> Bool {
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
    func scorch(except: Card?) async {
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
    func cull(except: Card?) async {
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
    func rowScorch(_ side: Player, _ rowType: RowType) async {
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
}

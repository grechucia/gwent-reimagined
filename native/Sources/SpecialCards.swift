// Special and weather cards, plus destruction effects (scorch, cull, row scorch, seize).
import Foundation

extension Game {
    /// Resolves a special (non-weather) card.
    func playSpecial(_ card: Card, by player: Player, row: RowType?, rowOwner: Player?, target: Card?) async {
        let opponent = player.opponent!
        let kind = card.specialKind ?? ""
        switch kind {
        // Commander's Horn: Doubles the strength of all unit cards in that row. Limited to 1 per row. | Mardroeme: Triggers transformation of all Berserker cards on the same row. | Morale Boost: Adds +1 to…
        case "horn", "mardroeme", "morale", "toussaint_wine", "shield", "shield_c", "shield_r", "shield_s": await specialHorn(card, by: player, row: row, rowOwner: rowOwner, target: target, kind: kind)
        // Dimensional Door: While the door is active, at the end of each of your turns you should draw one card from your deck. If the row of the card matches the row of the door, play it immediatly,…
        case "door": await specialDoor(card, by: player, row: row, rowOwner: rowOwner, target: target, kind: kind)
        // Decoy: Swap with a card on the battlefield to return it to your hand.
        case "decoy": await specialDecoy(card, by: player, row: row, rowOwner: rowOwner, target: target, kind: kind)
        // Scorch: Discard after playing. Kills the strongest card(s) on the battlefield.
        case "scorch": await scorch(except: nil); player.grave.append(card)
        // Cull: Kills the weakest card(s) on the battlefield.
        case "cull": await cull(except: nil); player.grave.append(card)
        // Clear Weather: Removes all Weather Cards (Biting Frost, Impenetrable Fog and Torrential Rain) effects.
        case "clear": await clearWeather(); player.grave.append(card)
        // Lock: Lock/cancels the ability of the next unit played in that row (ignores units without abilities and heroes).
        case "lock": await specialLock(card, by: player, row: row, rowOwner: rowOwner, target: target, kind: kind)
        // Curse: Place on your or opponent's battlefield on any row. Next unit card (not hero) that will be placed on this row will be destroyed and it's abilities will not work
        case "curse": await specialCurse(card, by: player, row: row, rowOwner: rowOwner, target: target, kind: kind)
        // Knockback: Pushes all units of the selected row (Melee or Ranged) or row back towards the Siege row, ignores shields.
        case "knockback": await specialKnockback(card, by: player, row: row, rowOwner: rowOwner, target: target, kind: kind)
        // Seize: Move the Melee unit(s) with the lowest strength on your side of the board/ Their abilities won't work anymore.
        case "seize": await seize(player, .close); player.grave.append(card)
        // Bank: Draw a card from your deck.
        case "bank": draw(player, 1); sound("game_buy"); player.grave.append(card)
        // Skellige Fleet: Place on your battlefield and either draw from your deck 1 top card instantly OR draw 2 top cards at the end of this round. In one round you can draw by Skellige Fleet no more than…
        case "skellige_fleet": await specialSkelligeFleet(card, by: player, row: row, rowOwner: rowOwner, target: target, kind: kind)
        // Royal Decree: Use your leader's ability
        case "royal_decree": await specialRoyalDecree(card, by: player, row: row, rowOwner: rowOwner, target: target, kind: kind)
        // Decoration: Promote a friendly unit to Hero status
        case "decoration": await specialDecoration(card, by: player, row: row, rowOwner: rowOwner, target: target, kind: kind)
        // Chernobog: Double the strength of any unit card in your Close combat row. Discard after playing. | Perun: Add +5 strength to any unit card in your Ranged row. Discard after playing.
        case "chernobog", "perun": await specialChernobog(card, by: player, row: row, rowOwner: rowOwner, target: target, kind: kind)
        // Svarog: Choose an enemy unit in the Siege row and reduce its strength to 1. Discard after playing. | Morana: Choose an enemy unit in the Close row and reduce its strength to 1. Discard after playing.
        case "svarog", "morana": await specialSvarog(card, by: player, row: row, rowOwner: rowOwner, target: target, kind: kind)
        // Triglav's Weaken: Choose an enemy hero card and weaken it by removing its Hero status. Discard after playing.
        case "triglav": await specialTriglav(card, by: player, row: row, rowOwner: rowOwner, target: target, kind: kind)
        // Veles: Move your strongest unit card to the Siege row. While there, its strength is doubled. Discard after playing.
        case "veles": await specialVeles(card, by: player, row: row, rowOwner: rowOwner, target: target, kind: kind)
        // Devana's Hunt: Reduce the strength of all non-hero enemy units in the Ranged row to 2. Discard after playing.
        case "devana": await specialDevana(card, by: player, row: row, rowOwner: rowOwner, target: target, kind: kind)
        // Zoria's Frost: Freeze the opponent's Close combat row. Discard after playing.
        case "zoria": await specialZoria(card, by: player, row: row, rowOwner: rowOwner, target: target, kind: kind)
        // Stribog: Move the enemy Ranged unit(s) with the lowest strength to your side of the board. Discard after playing.
        case "stribog": await specialStribog(card, by: player, row: row, rowOwner: rowOwner, target: target, kind: kind)
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
        // Biting Frost: Sets the strength of all Close Combat cards to 1 for both players. | Giant Spider Webs: Sets the strength of all Close Combat cards to 1 for both players.
        case "frost", "spider_web": return [.close]
        // Impenetrable Fog: Sets the strength of all Ranged Combat cards to 1 for both players. | Tse Tse Flies: Sets the strength of all Ranged Combat cards to 1 for both players.
        case "fog", "tse_tse": return [.ranged]
        // Torrential Rain: Sets the strength of all Siege Combat cards to 1 for both players. | Dragon Wrath: Sets the strength of all Siege Combat cards to 1 for both players.
        case "rain", "dragon_wrath": return [.siege]
        // Sandstorm: Reduces the Strength of all Close Combat and Ranged Combat Units to 1 (non-Hero units only).
        case "sandstorm": return [.close, .ranged]
        // White Frost: Sets the strength of all cards on the 2 corresponding rows to 1 for both players.
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
            let answer = await pickOption(player, L("Skellige Storm can either target Close/Ranged rows or Ranged/Siege rows, which one to target?"), [L("Close + Ranged [E]"), L("Ranged + Siege [Q]")]) {
                let o = player.opponent!
                return o.row(.close).total + o.row(.ranged).total - player.row(.close).total - player.row(.ranged).total >= o.row(.ranged).total + o.row(.siege).total - player.row(.ranged).total - player.row(.siege).total ? 0 : 1
            }
            rows = answer == 0 ? [.close, .ranged] : [.ranged, .siege]
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
            let answer = await pickOption(side, L("Do you want to save Comrade too?"), [L("Save it [E]"), L("Let it die [Q]")]) { 0 }
            if answer == 0 { side.comradeUsedRound = true; sound("comrade"); return true }
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

    /// Commander's Horn: Doubles the strength of all unit cards in that row. Limited to 1 per row. | Mardroeme: Triggers transformation of all Berserker cards on the same row. | Morale Boost: Adds +1 to…
    func specialHorn(_ card: Card, by player: Player, row: RowType?, rowOwner: Player?, target: Card?, kind: String) async {
        var r = row
        if r == nil { r = await pickRow(player, L("Select a card on your side of the board."), validRows(for: card, by: player).map { (player, $0) }) { 0 }?.1 }
        guard let chosenRow = r else { player.grave.append(card); return }
        player.row(chosenRow).specials.append(card)
        await animate(card, kind)
        sound(kind == "horn" ? "horn" : (kind == "mardroeme" ? "mardroeme" : (kind.hasPrefix("shield") ? "shield" : "moral")))
        if kind == "mardroeme" { await berserk(player, chosenRow) }
    }

    /// Dimensional Door: While the door is active, at the end of each of your turns you should draw one card from your deck. If the row of the card matches the row of the door, play it immediatly,…
    func specialDoor(_ card: Card, by player: Player, row: RowType?, rowOwner: Player?, target: Card?, kind: String) async {
        var r = row
        if r == nil { r = await pickRow(player, L("Select a card on your side of the board."), validRows(for: card, by: player).map { (player, $0) }) { 0 }?.1 }
        let open = RowType.allCases.filter { player.row($0).door }
        if let chosenRow = r, open.count < maxDoors { player.row(chosenRow).door = true }
        player.grave.append(card); sound("door")
    }

    /// Decoy: Swap with a card on the battlefield to return it to your hand.
    func specialDecoy(_ card: Card, by player: Player, row: RowType?, rowOwner: Player?, target: Card?, kind: String) async {
        if let t = target, let r = player.rowOf(t), let i = player.row(r).cards.firstIndex(where: { $0 === t }) {
            player.row(r).cards[i] = card
            resetCard(t); t.owner = player; player.hand.append(t)
            sound("decoy")
        } else { player.grave.append(card) }
    }

    /// Lock: Lock/cancels the ability of the next unit played in that row (ignores units without abilities and heroes).
    func specialLock(_ card: Card, by player: Player, row: RowType?, rowOwner: Player?, target: Card?, kind: String) async {
        let opponent = player.opponent!
        var r = row
        if r == nil { r = await pickRow(player, L("Select a card on your side of the board."), enemyRowTargets(for: card, by: player).map { (opponent, $0) }) { Int.random(in: 0..<3) }?.1 }
        if let chosenRow = r { opponent.row(chosenRow).lock = card } else { player.grave.append(card) }
        sound("lock")
    }

    /// Curse: Place on your or opponent's battlefield on any row. Next unit card (not hero) that will be placed on this row will be destroyed and it's abilities will not work
    func specialCurse(_ card: Card, by player: Player, row: RowType?, rowOwner: Player?, target: Card?, kind: String) async {
        var dest: (Player, RowType)? = rowOwner.flatMap { q in row.map { (q, $0) } }
        if dest == nil { dest = await pickRow(player, gameData.abilityName("curse"), curseRows(by: player)) { 3 + Int.random(in: 0..<3) } }
        if let (q, rowArea) = dest { q.row(rowArea).curse = card } else { player.grave.append(card) }
        sound("curse")
    }

    /// Knockback: Pushes all units of the selected row (Melee or Ranged) or row back towards the Siege row, ignores shields.
    func specialKnockback(_ card: Card, by player: Player, row: RowType?, rowOwner: Player?, target: Card?, kind: String) async {
        let opponent = player.opponent!
        var r = row
        if r == nil { r = await pickRow(player, gameData.abilityName("knockback"), [(opponent, .close), (opponent, .ranged)]) { 0 }?.1 }
        if let chosenRow = r {
            let dest: RowType = chosenRow == .close ? .ranged : .siege
            let moving = opponent.row(chosenRow).cards.filter { !$0.hero }
            opponent.row(chosenRow).cards.removeAll { m in moving.contains { $0 === m } }
            opponent.row(dest).cards.append(contentsOf: moving)
            sound("knockback")
        }
        player.grave.append(card)
    }

    /// Skellige Fleet: Place on your battlefield and either draw from your deck 1 top card instantly OR draw 2 top cards at the end of this round. In one round you can draw by Skellige Fleet no more than…
    func specialSkelligeFleet(_ card: Card, by player: Player, row: RowType?, rowOwner: Player?, target: Card?, kind: String) async {
        if player.fleetDrawsRound < 3 {
            let answer = await pickOption(player, L("Draw now or more later?"), [L("Draw 1 now [E]"), L("Draw 2 later [Q]")]) { 0 }
            if answer == 0 { draw(player, 1); player.fleetDrawsRound += 1 } else { player.fleetPending += 2; player.fleetDrawsRound += 2 }
        }
        player.row(.siege).specials.append(card)
    }

    /// Royal Decree: Use your leader's ability
    func specialRoyalDecree(_ card: Card, by player: Player, row: RowType?, rowOwner: Player?, target: Card?, kind: String) async {
        player.grave.append(card)
        await leaderEffect(player, free: true)
    }

    /// Decoration: Promote a friendly unit to Hero status
    func specialDecoration(_ card: Card, by player: Player, row: RowType?, rowOwner: Player?, target: Card?, kind: String) async {
        let options = player.rowCards.filter { !$0.hero }
        if let t = await pickOne(player, L("Choose a unit to promote to Hero."), options, ai: { candidates in candidates.max { $0.power < $1.power } }) { t.heroOverride = true; t.flash = 1; await animate(t, "decoration") }
        player.grave.append(card); sound("decoration")
    }

    /// Chernobog: Double the strength of any unit card in your Close combat row. Discard after playing. | Perun: Add +5 strength to any unit card in your Ranged row. Discard after playing.
    func specialChernobog(_ card: Card, by player: Player, row: RowType?, rowOwner: Player?, target: Card?, kind: String) async {
        let options = player.row(kind == "chernobog" ? .close : .ranged).cards.filter { !$0.hero }
        if let t = await pickOne(player, kind == "chernobog" ? L("Choose which unit to double with Chernobog runestone") : L("Choose which unit to grant +5 strength with Perun runestone"), options, ai: { candidates in candidates.max { $0.power < $1.power } }) {
            if kind == "chernobog" { t.multiplier *= 2 } else { t.bonus += 5 }; t.flash = 1; await animate(t, kind)
        }
        player.grave.append(card); sound("rune_call")
    }

    /// Svarog: Choose an enemy unit in the Siege row and reduce its strength to 1. Discard after playing. | Morana: Choose an enemy unit in the Close row and reduce its strength to 1. Discard after playing.
    func specialSvarog(_ card: Card, by player: Player, row: RowType?, rowOwner: Player?, target: Card?, kind: String) async {
        let opponent = player.opponent!
        let options = opponent.row(kind == "svarog" ? .siege : .close).cards.filter { !$0.hero }
        if let t = await pickOne(player, kind == "svarog" ? L("Choose which enemy siege unit to reduce to 1 with Svarog.") : L("Choose which enemy close unit to reduce to 1 with Morana."), options, ai: { candidates in candidates.max { $0.power < $1.power } }) { t.setTo = 1; t.flash = 1; await animate(t, kind) }
        player.grave.append(card); sound("rune_call")
    }

    /// Triglav's Weaken: Choose an enemy hero card and weaken it by removing its Hero status. Discard after playing.
    func specialTriglav(_ card: Card, by player: Player, row: RowType?, rowOwner: Player?, target: Card?, kind: String) async {
        let opponent = player.opponent!
        let options = opponent.rowCards.filter { $0.hero }
        if let t = await pickOne(player, L("Choose the enemy hero to weaken."), options, ai: { candidates in candidates.max { $0.power < $1.power } }) { t.heroOverride = false; t.flash = 1; await animate(t, "triglav") }
        player.grave.append(card); sound("triglav")
    }

    /// Veles: Move your strongest unit card to the Siege row. While there, its strength is doubled. Discard after playing.
    func specialVeles(_ card: Card, by player: Player, row: RowType?, rowOwner: Player?, target: Card?, kind: String) async {
        if let t = player.rowCards.filter({ !$0.hero }).max(by: { $0.power < $1.power }) {
            if let tr = player.rowOf(t) { player.row(tr).cards.removeAll { $0 === t } }
            player.row(.siege).cards.append(t); t.siegeMult = 2; await animate(t, "veles")
        }
        player.grave.append(card); sound("veles")
    }

    /// Devana's Hunt: Reduce the strength of all non-hero enemy units in the Ranged row to 2. Discard after playing.
    func specialDevana(_ card: Card, by player: Player, row: RowType?, rowOwner: Player?, target: Card?, kind: String) async {
        let opponent = player.opponent!
        for t in opponent.row(.ranged).cards where !t.hero { t.setTo = 2; t.flash = 1 }
        player.grave.append(card); sound("rune_call")
    }

    /// Zoria's Frost: Freeze the opponent's Close combat row. Discard after playing.
    func specialZoria(_ card: Card, by player: Player, row: RowType?, rowOwner: Player?, target: Card?, kind: String) async {
        let opponent = player.opponent!
        opponent.weather[RowType.close.rawValue].insert("frost")
        player.grave.append(card); sound("cold")
    }

    /// Stribog: Move the enemy Ranged unit(s) with the lowest strength to your side of the board. Discard after playing.
    func specialStribog(_ card: Card, by player: Player, row: RowType?, rowOwner: Player?, target: Card?, kind: String) async {
        let opponent = player.opponent!
        let units = opponent.row(.ranged).cards.filter { !$0.hero }
        if let mn = units.map({ $0.power }).min() {
            for t in units where t.power == mn { opponent.row(.ranged).cards.removeAll { $0 === t }; t.owner = player; player.row(.ranged).cards.append(t) }
        }
        player.grave.append(card); sound("rune_call")
    }
}

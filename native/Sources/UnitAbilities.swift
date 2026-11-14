// Unit abilities: what happens when a unit card is placed (spy, medic, muster, berserker, djinn...).
import Foundation

extension Game {
    /// Resolves the abilities of a unit that was just placed.
    func unitAbilities(_ card: Card, by player: Player, side: Player, row rowType: RowType) async {
        let o = player.opponent!
        for a in card.data.abilities {
            switch a {
            // Spy: Place on your opponent's battlefield (counts towards your opponent's total) and draw 2 cards from your deck.
            case "spy":
                if player.faction == "toussaint" {
                    let three = Array(player.deck.prefix(3))
                    if let k = await pickOne(player, L("Choose the card to draw and keep"), three, ai: { candidates in candidates.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                        player.deck.removeAll { $0 === k }; player.hand.append(k); player.deck.shuffle()
                    }
                } else { await spyDraw(player, 2) }
                sound("spy")
            // Emissary: Place on your opponent's battlefield (counts towards your opponent's total), either draw one card or look first 4 and put them back in order of choice, Once per round, some of these can…
            case "emissary":
                let answer = await pickOption(player, L("Choose the effect of the emissary"), [L("Draw 1 card [E]"), L("Look first 4 cards [Q]")]) { 0 }
                if answer == 0 { await spyDraw(player, 1) } else { await reorderTop(player, 4) }
                sound("emissary")
            // Ofiri Envoy: Place on the opponent's field. Draw 1 card from the opponent's deck and 1 from yours, or draw 2 cards from your deck.
            case "ofiri_envoy":
                let answer = player.drawOpponentLeft > 0 && !o.deck.isEmpty
                    ? await pickOption(player, L("From which deck to draw the next card? (Ofiri Envoy can draw from opponent's deck only once)"), [L("Own deck [E]"), L("Opponent's deck [Q]")]) { 0 } : 0
                if answer == 1 { player.drawOpponentLeft = 0; if let t = o.deck.first { o.deck.removeFirst(); t.owner = player; player.hand.append(t) }; draw(player, 1) } else { draw(player, 2) }
                sound("ofiri_envoy")
            // Medic: Choose one card from your discard pile and play it instantly (no Heroes or Special Cards).
            case "medic": await medic(player)
            // Muster: Find any cards with the same name in your deck and play them instantly.
            case "muster": await muster(card, player, rowType)
            // Invoke: Invokes one of the available associated cards from the deck.
            case "invoke":
                let options = player.deck.filter { card.data.targets.contains($0.key) || ($0.groupKey == card.groupKey && $0 !== card && !card.data.target.isEmpty) }
                if let t = await pickOne(player, L("Choose one card to play."), options, ai: { $0.first }) { player.deck.removeAll { $0 === t }; await placeUnit(t, by: player, row: t.allowedRows.first ?? rowType); sound("invoke") }
            // Summon One Of: Summons from anywhere (deck, grave or hand) one of the associated card of choice
            case "summon_one_of":
                let options = (player.deck + player.hand + player.grave).filter { card.data.targets.contains($0.key) }
                if let t = await pickOne(player, L("Choose one card to play."), options, ai: { candidates in candidates.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                    player.deck.removeAll { $0 === t }; player.hand.removeAll { $0 === t }; player.grave.removeAll { $0 === t }
                    await placeUnit(t, by: player, row: t.allowedRows.first ?? rowType)
                }
            // Scorch Close: Destroy your enemy's strongest Close Combat unit(s) if the combined strength of all his or her Close Combat units is 10 or more. | Scorch Ranged: Destroy your enemy's strongest…
            case "scorch_c", "scorch_r", "scorch_s":
                let t: RowType = a == "scorch_c" ? .close : (a == "scorch_r" ? .ranged : .siege)
                await rowScorch(o, t)
            // Scorch: Discard after playing. Kills the strongest card(s) on the battlefield.
            case "scorch": await scorch(except: card)
            // Cull: Kills the weakest card(s) on the battlefield.
            case "cull": await cull(except: card)
            // Mardroeme: Triggers transformation of all Berserker cards on the same row.
            case "mardroeme": await berserk(side, rowType)
            // Berserker: Transforms into a bear when a Mardroeme card is on its row.
            case "berserker": if side.row(rowType).specials.contains(where: { $0.specialKind == "mardroeme" }) || side.row(rowType).cards.contains(where: { $0.act("mardroeme") }) { await berserk(side, rowType) }
            // Witch Hunt: Destroy the weakest unit on the opposite row. If there are several, choose one.
            case "witch_hunt":
                let opp = o.row(rowType)
                if opp.shielded { break }
                let units = opp.cards.filter { !$0.hero && $0.immortalRounds == 0 }
                if let mn = units.map({ $0.power }).min() {
                    let cands = units.filter { $0.power == mn }
                    if let t = await pickOne(player, L("Choose which enemy card to destroy"), cands, ai: { $0.first }) { await destroy(t, side: o) }
                }
            // Necrophage: Choose up to 2 unit cards from your discard pile and shuffle them back into your deck.
            case "necrophage":
                let options = player.grave.filter { $0.isUnit }
                let picks = await pickCards(player, L("Choose up to 2 cards to take from your grave back to your deck."), options, min: 0, max: 2, cancel: true) { candidates in Array(candidates.sorted { self.aiCardValue($0) > self.aiCardValue($1) }.prefix(2)) }
                for x in picks { player.grave.removeAll { $0 === x }; resetCard(x); player.deck.insert(x, at: Int.random(in: 0...player.deck.count)) }
            // Goetia: Place on your battlefield and take 1 card from your deck to your hand, then choose any 1 card from your hand and shuffle it into your deck.
            case "goetia":
                if let d = await pickOne(player, L("Choose a card to draw from your deck."), player.deck, ai: { candidates in candidates.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                    player.deck.removeAll { $0 === d }; player.hand.append(d)
                    if let back = await pickOne(player, L("Which card to put back into your deck?"), player.hand, ai: { candidates in candidates.min { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                        player.hand.removeAll { $0 === back }; player.deck.insert(back, at: Int.random(in: 0...player.deck.count))
                    }
                }
            // Sage: Place on your battlefield and draw 4 cards from your deck. Look at them and put them back at the top or bottom of the deck in the order of your choice.
            case "sage": await reorderTop(player, 4)
            // Zirael: Place on your battlefield. Reveal 5 cards from your deck and choose up to 2 to add to your hand. Shuffle the rest back into the deck.
            case "zirael":
                let five = Array(player.deck.prefix(5))
                let picks = await pickCards(player, L("Choose up to 2 cards to draw and keep in your hand"), five, min: 0, max: 2) { candidates in Array(candidates.sorted { self.aiCardValue($0) > self.aiCardValue($1) }.prefix(2)) }
                for x in picks { player.deck.removeAll { $0 === x }; player.hand.append(x) }
                player.deck.shuffle()
            // Naglfar: Place on your battlefield and draw 2 cards or less from your deck with the word 'Naglfar' in their name and play them immediatly.
            case "naglfar":
                let options = player.deck.filter { $0.data.name.contains("Naglfar") && $0.isUnit }
                let picks = await pickCards(player, L("Choose up to 2 cards to play right away."), options, min: 0, max: 2) { candidates in Array(candidates.prefix(2)) }
                for x in picks { player.deck.removeAll { $0 === x }; await placeUnit(x, by: player, row: x.allowedRows.first ?? .siege) }
            // Bait: Place on your battlefield and draw from your deck one card with Tight Bond ability. Play it immediatly.
            case "bait":
                let options = player.deck.filter { $0.has("bond") }
                if let t = await pickOne(player, L("Choose one card to play."), options, ai: { candidates in candidates.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                    player.deck.removeAll { $0 === t }; await placeUnit(t, by: player, row: t.allowedRows.first ?? rowType)
                }
            // Clairvoyance: Choose to either look at the top 3 cards of your deck OR look at 3 random cards in your opponent's hand.
            case "clairvoyance":
                let answer = await pickOption(player, L("Clairvoyance Options"), [L("View Deck [E]"), L("Spy Enemy [Q]")]) { 1 }
                if answer == 0 { await reveal(player, L("Clairvoyance: Top 3 cards of your deck (click to close)"), Array(player.deck.prefix(3))) }
                else { await reveal(player, L("Clairvoyance: 3 random cards of enemy hand (click to close)"), Array(o.hand.shuffled().prefix(3))) }
            // Trade: Choose 1 card from the enemy's deck. Trade 1 of your runes from your deck to their hand.
            case "trade":
                if let t = await pickOne(player, L("Select a card from the opponent's deck to buy."), o.deck, ai: { candidates in candidates.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                    o.deck.removeAll { $0 === t }; t.owner = player; player.hand.append(t)
                    if let rune = player.deck.first(where: { $0.key.hasPrefix("ofir_") && $0.data.isSpecial }) { player.deck.removeAll { $0 === rune }; rune.owner = o; o.hand.append(rune) }
                    sound("trade")
                }
            // Rune Crafting: Choose and add a Rune card from your deck to your hand.
            case "rune_call":
                let options = player.deck.filter { $0.key.hasPrefix("ofir_") && $0.data.isSpecial }
                if let t = await pickOne(player, L("Choose 1 runestone from your deck to add to your hand."), options, ai: { $0.randomElement() }) { player.deck.removeAll { $0 === t }; player.hand.append(t) }
            // Omen: Create a copy of Cat and Dog and add it to your hand.
            case "omen":
                if let d = gameData.cards["nv_catanddog"] { player.hand.append(Card(d, owner: player)) }
            // Malicious Wish 1: Choose 1 of 3 random cards from the enemy hand. Cost: Destroy your strongest non-hero unit (Strength ≥ 6). | Malicious Wish 2: Choose 1 of the top 3 cards from your deck. Cost:…
            case "wish1", "wish2", "wish3":
                await djinnWish(a, card, player)
            // Doppler: Choose an enemy unit (not hero or special) from the opposite row and transform into a basic copy of it (stats only, no abilities).
            case "doppler":
                let options = o.row(rowType).cards.filter { !$0.hero && $0.isUnit }
                if let t = await pickOne(player, L("Choose an enemy unit from the opposite row to transform Doppler into."), options, ai: { candidates in candidates.max { $0.basePower < $1.basePower } }) {
                    card.baseOverride = t.basePower; sound("doppler"); await animate(card, "doppler")
                }
            // Aerondight: Place this card on the board, then move the unit with the highest original strength to the siege row. While there, triple its strength.
            case "aerondight":
                let options = player.rowCards.filter { $0 !== card && !$0.hero }
                if let t = await pickOne(player, L("Choose which card to equip with Aerondight."), options, ai: { candidates in candidates.max { $0.basePower < $1.basePower } }) {
                    if let tr = player.rowOf(t) { player.row(tr).cards.removeAll { $0 === t } }
                    player.row(.siege).cards.append(t); t.siegeMult = 3
                }
            // Immortal: Card stays on the battlefield for 2 rounds and cannot be destroyed by another ability
            case "immortal": card.immortalRounds = 2
            // Toussaint Wine: Placed on Melee or Ranged row, boosts all units of the selected row by two. Limited to one per row.
            case "toussaint_wine": break
            default: break
            }
        }
    }

    /// Spy: the player draws cards.
    func spyDraw(_ player: Player, _ count: Int) async {
        let o = player.opponent!
        for _ in 0..<count {
            if player.leaderAbility == "emhyr_whiteflame" && player.drawOpponentLeft > 0 && !o.deck.isEmpty {
                let answer = await pickOption(player, L("Choose deck to draw from"), [L("Own deck [E]"), L("Opponent's deck [Q]")]) { 1 }
                if answer == 1, let t = o.deck.first { o.deck.removeFirst(); t.owner = player; player.hand.append(t); player.drawOpponentLeft -= 1; continue }
            }
            draw(player, 1)
        }
    }

    /// Lets the player reorder the top cards of the deck.
    func reorderTop(_ player: Player, _ count: Int) async {
        let top = Array(player.deck.prefix(count))
        guard !top.isEmpty else { return }
        let order = await pickCards(player, L("Re-order the cards back into the deck"), top, min: top.count, max: top.count) { candidates in candidates.sorted { self.aiCardValue($0) > self.aiCardValue($1) } }
        player.deck.removeFirst(top.count)
        player.deck.insert(contentsOf: order.isEmpty ? top : order, at: 0)
    }

    /// Medic: revives a unit from the graveyard.
    func medic(_ player: Player) async {
        sound("med")
        for _ in 0..<medicPicks {
            let options = player.grave.filter { $0.isUnit && !$0.hero }
            guard let card = await pickOne(player, L("Which card to restore from your grave?"), options, cancel: true, ai: { candidates in candidates.max { self.aiCardValue($0) < self.aiCardValue($1) } }) else { return }
            player.grave.removeAll { $0 === card }
            resetCard(card)
            await placeUnit(card, by: player, row: card.allowedRows.first ?? .close)
        }
    }

    /// Muster: plays every copy of the card from deck and hand.
    func muster(_ card: Card, _ player: Player, _ rowType: RowType) async {
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
    func berserk(_ side: Player, _ rowType: RowType) async {
        for c in side.row(rowType).cards where c.act("berserker") {
            if let t = c.data.targets.first, let d = gameData.cards[t] { c.transform(into: d); events.append(.anim(c, "mardroeme")) }
        }
        sound("mardroeme")
        recalc()
    }

    /// Djinn: grants one of the wishes.
    func djinnWish(_ ability: String, _ card: Card, _ player: Player) async {
        let o = player.opponent!
        let minStr = ability == "wish3" ? 7 : 6
        let costs = player.rowCards.filter { $0 !== card && !$0.hero && $0.basePower >= minStr }
        guard let cost = costs.max(by: { $0.power < $1.power }) else { return }
        await destroy(cost, side: player)
        switch ability {
        // Malicious Wish 1: Choose 1 of 3 random cards from the enemy hand. Cost: Destroy your strongest non-hero unit (Strength ≥ 6).
        case "wish1":
            let three = Array(o.hand.shuffled().prefix(3))
            if let t = await pickOne(player, L("The Djinn grants your wish: Choose 1 enemy card to steal."), three, ai: { candidates in candidates.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                o.hand.removeAll { $0 === t }; t.owner = player; player.hand.append(t)
            }
        // Malicious Wish 2: Choose 1 of the top 3 cards from your deck. Cost: Destroy your strongest non-hero unit (Strength ≥ 6). This card is immune.
        case "wish2":
            let three = Array(player.deck.prefix(3))
            if let t = await pickOne(player, L("The Djinn grants your second wish: Choose 1 card from your deck to draw."), three, ai: { candidates in candidates.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                player.deck.removeAll { $0 === t }; player.hand.append(t)
            }
            card.immortalRounds = max(card.immortalRounds, 1)
        default:
            let options = o.rowCards.filter { !$0.hero && $0.immortalRounds == 0 }
            if let t = await pickOne(player, L("The Djinn grants your third wish: Choose 1 enemy unit to destroy."), options, ai: { candidates in candidates.max { $0.power < $1.power } }) { await destroy(t, side: o) }
            card.immortalRounds = max(card.immortalRounds, 1)
        }
    }
}

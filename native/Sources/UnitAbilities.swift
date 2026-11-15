// Unit abilities: what happens when a unit card is placed (spy, medic, muster, berserker, djinn...).
import Foundation

extension Game {
    /// Resolves the abilities of a unit that was just placed.
    func unitAbilities(_ card: Card, by player: Player, side: Player, row rowType: RowType) async {
        let opponent = player.opponent!
        for ability in card.data.abilities {
            switch ability {
            // Spy: Place on your opponent's battlefield (counts towards your opponent's total) and draw 2 cards from your deck.
            case "spy": await abilitySpy(card, by: player, side: side, row: rowType, ability: ability)
            // Emissary: Place on your opponent's battlefield (counts towards your opponent's total), either draw one card or look first 4 and put them back in order of choice, Once per round, some of these can…
            case "emissary": await abilityEmissary(card, by: player, side: side, row: rowType, ability: ability)
            // Ofiri Envoy: Place on the opponent's field. Draw 1 card from the opponent's deck and 1 from yours, or draw 2 cards from your deck.
            case "ofiri_envoy": await abilityOfiriEnvoy(card, by: player, side: side, row: rowType, ability: ability)
            // Medic: Choose one card from your discard pile and play it instantly (no Heroes or Special Cards).
            case "medic": await medic(player)
            // Muster: Find any cards with the same name in your deck and play them instantly.
            case "muster": await muster(card, player, rowType)
            // Invoke: Invokes one of the available associated cards from the deck.
            case "invoke": await abilityInvoke(card, by: player, side: side, row: rowType, ability: ability)
            // Summon One Of: Summons from anywhere (deck, grave or hand) one of the associated card of choice
            case "summon_one_of": await abilitySummonOneOf(card, by: player, side: side, row: rowType, ability: ability)
            // Scorch Close: Destroy your enemy's strongest Close Combat unit(s) if the combined strength of all his or her Close Combat units is 10 or more. | Scorch Ranged: Destroy your enemy's strongest…
            case "scorch_c", "scorch_r", "scorch_s": await abilityScorchC(card, by: player, side: side, row: rowType, ability: ability)
            // Scorch: Discard after playing. Kills the strongest card(s) on the battlefield.
            case "scorch": await scorch(except: card)
            // Cull: Kills the weakest card(s) on the battlefield.
            case "cull": await cull(except: card)
            // Mardroeme: Triggers transformation of all Berserker cards on the same row.
            case "mardroeme": await berserk(side, rowType)
            // Berserker: Transforms into a bear when a Mardroeme card is on its row.
            case "berserker": if side.row(rowType).specials.contains(where: { $0.specialKind == "mardroeme" }) || side.row(rowType).cards.contains(where: { $0.act("mardroeme") }) { await berserk(side, rowType) }
            // Witch Hunt: Destroy the weakest unit on the opposite row. If there are several, choose one.
            case "witch_hunt": await abilityWitchHunt(card, by: player, side: side, row: rowType, ability: ability)
            // Necrophage: Choose up to 2 unit cards from your discard pile and shuffle them back into your deck.
            case "necrophage": await abilityNecrophage(card, by: player, side: side, row: rowType, ability: ability)
            // Goetia: Place on your battlefield and take 1 card from your deck to your hand, then choose any 1 card from your hand and shuffle it into your deck.
            case "goetia": await abilityGoetia(card, by: player, side: side, row: rowType, ability: ability)
            // Sage: Place on your battlefield and draw 4 cards from your deck. Look at them and put them back at the top or bottom of the deck in the order of your choice.
            case "sage": await reorderTop(player, 4)
            // Zirael: Place on your battlefield. Reveal 5 cards from your deck and choose up to 2 to add to your hand. Shuffle the rest back into the deck.
            case "zirael": await abilityZirael(card, by: player, side: side, row: rowType, ability: ability)
            // Naglfar: Place on your battlefield and draw 2 cards or less from your deck with the word 'Naglfar' in their name and play them immediatly.
            case "naglfar": await abilityNaglfar(card, by: player, side: side, row: rowType, ability: ability)
            // Bait: Place on your battlefield and draw from your deck one card with Tight Bond ability. Play it immediatly.
            case "bait": await abilityBait(card, by: player, side: side, row: rowType, ability: ability)
            // Clairvoyance: Choose to either look at the top 3 cards of your deck OR look at 3 random cards in your opponent's hand.
            case "clairvoyance": await abilityClairvoyance(card, by: player, side: side, row: rowType, ability: ability)
            // Trade: Choose 1 card from the enemy's deck. Trade 1 of your runes from your deck to their hand.
            case "trade": await abilityTrade(card, by: player, side: side, row: rowType, ability: ability)
            // Rune Crafting: Choose and add a Rune card from your deck to your hand.
            case "rune_call": await abilityRuneCall(card, by: player, side: side, row: rowType, ability: ability)
            // Omen: Create a copy of Cat and Dog and add it to your hand.
            case "omen":
                if let cardData = gameData.cards["nv_catanddog"] { player.hand.append(Card(cardData, owner: player)) }
            // Malicious Wish 1: Choose 1 of 3 random cards from the enemy hand. Cost: Destroy your strongest non-hero unit (Strength ≥ 6). | Malicious Wish 2: Choose 1 of the top 3 cards from your deck. Cost:…
            case "wish1", "wish2", "wish3":
                await djinnWish(ability, card, player)
            // Doppler: Choose an enemy unit (not hero or special) from the opposite row and transform into a basic copy of it (stats only, no abilities).
            case "doppler": await abilityDoppler(card, by: player, side: side, row: rowType, ability: ability)
            // Aerondight: Place this card on the board, then move the unit with the highest original strength to the siege row. While there, triple its strength.
            case "aerondight": await abilityAerondight(card, by: player, side: side, row: rowType, ability: ability)
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
        let opponent = player.opponent!
        for _ in 0..<count {
            if player.leaderAbility == "emhyr_whiteflame" && player.drawOpponentLeft > 0 && !opponent.deck.isEmpty {
                let answer = await pickOption(player, L("Choose deck to draw from"), [L("Own deck [E]"), L("Opponent's deck [Q]")]) { 1 }
                if answer == 1, let topCard = opponent.deck.first { opponent.deck.removeFirst(); topCard.owner = player; player.hand.append(topCard); player.drawOpponentLeft -= 1; continue }
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
        for musterCards in fromHand + fromDeck {
            player.hand.removeAll { $0 === musterCards }; player.deck.removeAll { $0 === musterCards }
            let musterRow = card.data.row.hasPrefix("agile") ? rowType : (RowType.from(musterCards.data.row) ?? musterCards.allowedRows.first ?? rowType)
            musterCards.owner = player; musterCards.playedTurn = turn
            player.row(musterRow).cards.append(musterCards); musterCards.flash = 1
        }
        sound("ally")
        recalc()
    }

    /// Berserker: transforms berserkers on a row when mardroeme is present.
    func berserk(_ side: Player, _ rowType: RowType) async {
        for berserker in side.row(rowType).cards where berserker.act("berserker") {
            if let targetKey = berserker.data.targets.first, let transformData = gameData.cards[targetKey] { berserker.transform(into: transformData); events.append(.anim(berserker, "mardroeme")) }
        }
        sound("mardroeme")
        recalc()
    }

    /// Djinn: grants one of the wishes.
    func djinnWish(_ ability: String, _ card: Card, _ player: Player) async {
        let opponent = player.opponent!
        let minStr = ability == "wish3" ? 7 : 6
        let costs = player.rowCards.filter { $0 !== card && !$0.hero && $0.basePower >= minStr }
        guard let cost = costs.max(by: { $0.power < $1.power }) else { return }
        await destroy(cost, side: player)
        switch ability {
        // Malicious Wish 1: Choose 1 of 3 random cards from the enemy hand. Cost: Destroy your strongest non-hero unit (Strength ≥ 6).
        case "wish1":
            let three = Array(opponent.hand.shuffled().prefix(3))
            if let chosen = await pickOne(player, L("The Djinn grants your wish: Choose 1 enemy card to steal."), three, ai: { candidates in candidates.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                opponent.hand.removeAll { $0 === chosen }; chosen.owner = player; player.hand.append(chosen)
            }
        // Malicious Wish 2: Choose 1 of the top 3 cards from your deck. Cost: Destroy your strongest non-hero unit (Strength ≥ 6). This card is immune.
        case "wish2":
            let three = Array(player.deck.prefix(3))
            if let chosen = await pickOne(player, L("The Djinn grants your second wish: Choose 1 card from your deck to draw."), three, ai: { candidates in candidates.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                player.deck.removeAll { $0 === chosen }; player.hand.append(chosen)
            }
            card.immortalRounds = max(card.immortalRounds, 1)
        default:
            let options = opponent.rowCards.filter { !$0.hero && $0.immortalRounds == 0 }
            if let chosen = await pickOne(player, L("The Djinn grants your third wish: Choose 1 enemy unit to destroy."), options, ai: { candidates in candidates.max { $0.power < $1.power } }) { await destroy(chosen, side: opponent) }
            card.immortalRounds = max(card.immortalRounds, 1)
        }
    }

    /// Spy: Place on your opponent's battlefield (counts towards your opponent's total) and draw 2 cards from your deck.
    func abilitySpy(_ card: Card, by player: Player, side: Player, row rowType: RowType, ability: String) async {
        if player.faction == "toussaint" {
            let three = Array(player.deck.prefix(3))
            if let chosen = await pickOne(player, L("Choose the card to draw and keep"), three, ai: { candidates in candidates.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                player.deck.removeAll { $0 === chosen }; player.hand.append(chosen); player.deck.shuffle()
            }
        } else { await spyDraw(player, 2) }
        sound("spy")
    }

    /// Emissary: Place on your opponent's battlefield (counts towards your opponent's total), either draw one card or look first 4 and put them back in order of choice, Once per round, some of these can…
    func abilityEmissary(_ card: Card, by player: Player, side: Player, row rowType: RowType, ability: String) async {
        let answer = await pickOption(player, L("Choose the effect of the emissary"), [L("Draw 1 card [E]"), L("Look first 4 cards [Q]")]) { 0 }
        if answer == 0 { await spyDraw(player, 1) } else { await reorderTop(player, 4) }
        sound("emissary")
    }

    /// Ofiri Envoy: Place on the opponent's field. Draw 1 card from the opponent's deck and 1 from yours, or draw 2 cards from your deck.
    func abilityOfiriEnvoy(_ card: Card, by player: Player, side: Player, row rowType: RowType, ability: String) async {
        let opponent = player.opponent!
        let answer = player.drawOpponentLeft > 0 && !opponent.deck.isEmpty
            ? await pickOption(player, L("From which deck to draw the next card? (Ofiri Envoy can draw from opponent's deck only once)"), [L("Own deck [E]"), L("Opponent's deck [Q]")]) { 0 } : 0
        if answer == 1 { player.drawOpponentLeft = 0; if let topCard = opponent.deck.first { opponent.deck.removeFirst(); topCard.owner = player; player.hand.append(topCard) }; draw(player, 1) } else { draw(player, 2) }
        sound("ofiri_envoy")
    }

    /// Invoke: Invokes one of the available associated cards from the deck.
    func abilityInvoke(_ card: Card, by player: Player, side: Player, row rowType: RowType, ability: String) async {
        let options = player.deck.filter { card.data.targets.contains($0.key) || ($0.groupKey == card.groupKey && $0 !== card && !card.data.target.isEmpty) }
        if let chosen = await pickOne(player, L("Choose one card to play."), options, ai: { $0.first }) { player.deck.removeAll { $0 === chosen }; await placeUnit(chosen, by: player, row: chosen.allowedRows.first ?? rowType); sound("invoke") }
    }

    /// Summon One Of: Summons from anywhere (deck, grave or hand) one of the associated card of choice
    func abilitySummonOneOf(_ card: Card, by player: Player, side: Player, row rowType: RowType, ability: String) async {
        let options = (player.deck + player.hand + player.grave).filter { card.data.targets.contains($0.key) }
        if let chosen = await pickOne(player, L("Choose one card to play."), options, ai: { candidates in candidates.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
            player.deck.removeAll { $0 === chosen }; player.hand.removeAll { $0 === chosen }; player.grave.removeAll { $0 === chosen }
            await placeUnit(chosen, by: player, row: chosen.allowedRows.first ?? rowType)
        }
    }

    /// Scorch Close: Destroy your enemy's strongest Close Combat unit(s) if the combined strength of all his or her Close Combat units is 10 or more. | Scorch Ranged: Destroy your enemy's strongest…
    func abilityScorchC(_ card: Card, by player: Player, side: Player, row rowType: RowType, ability: String) async {
        let opponent = player.opponent!
        let scorchRow: RowType = ability == "scorch_c" ? .close : (ability == "scorch_r" ? .ranged : .siege)
        await rowScorch(opponent, scorchRow)
    }

    /// Witch Hunt: Destroy the weakest unit on the opposite row. If there are several, choose one.
    func abilityWitchHunt(_ card: Card, by player: Player, side: Player, row rowType: RowType, ability: String) async {
        let opponent = player.opponent!
        let enemyRow = opponent.row(rowType)
        if enemyRow.shielded { return }
        let candidates = enemyRow.cards.filter { !$0.hero && $0.immortalRounds == 0 }
        if let lowestPower = candidates.map({ $0.power }).min() {
            let cands = candidates.filter { $0.power == lowestPower }
            if let chosen = await pickOne(player, L("Choose which enemy card to destroy"), cands, ai: { $0.first }) { await destroy(chosen, side: opponent) }
        }
    }

    /// Necrophage: Choose up to 2 unit cards from your discard pile and shuffle them back into your deck.
    func abilityNecrophage(_ card: Card, by player: Player, side: Player, row rowType: RowType, ability: String) async {
        let options = player.grave.filter { $0.isUnit }
        let picked = await pickCards(player, L("Choose up to 2 cards to take from your grave back to your deck."), options, min: 0, max: 2, cancel: true) { candidates in Array(candidates.sorted { self.aiCardValue($0) > self.aiCardValue($1) }.prefix(2)) }
        for x in picked { player.grave.removeAll { $0 === x }; resetCard(x); player.deck.insert(x, at: Int.random(in: 0...player.deck.count)) }
    }

    /// Goetia: Place on your battlefield and take 1 card from your deck to your hand, then choose any 1 card from your hand and shuffle it into your deck.
    func abilityGoetia(_ card: Card, by player: Player, side: Player, row rowType: RowType, ability: String) async {
        if let chosen = await pickOne(player, L("Choose a card to draw from your deck."), player.deck, ai: { candidates in candidates.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
            player.deck.removeAll { $0 === chosen }; player.hand.append(chosen)
            if let back = await pickOne(player, L("Which card to put back into your deck?"), player.hand, ai: { candidates in candidates.min { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                player.hand.removeAll { $0 === back }; player.deck.insert(back, at: Int.random(in: 0...player.deck.count))
            }
        }
    }

    /// Zirael: Place on your battlefield. Reveal 5 cards from your deck and choose up to 2 to add to your hand. Shuffle the rest back into the deck.
    func abilityZirael(_ card: Card, by player: Player, side: Player, row rowType: RowType, ability: String) async {
        let five = Array(player.deck.prefix(5))
        let picked = await pickCards(player, L("Choose up to 2 cards to draw and keep in your hand"), five, min: 0, max: 2) { candidates in Array(candidates.sorted { self.aiCardValue($0) > self.aiCardValue($1) }.prefix(2)) }
        for x in picked { player.deck.removeAll { $0 === x }; player.hand.append(x) }
        player.deck.shuffle()
    }

    /// Naglfar: Place on your battlefield and draw 2 cards or less from your deck with the word 'Naglfar' in their name and play them immediatly.
    func abilityNaglfar(_ card: Card, by player: Player, side: Player, row rowType: RowType, ability: String) async {
        let options = player.deck.filter { $0.data.name.contains("Naglfar") && $0.isUnit }
        let picked = await pickCards(player, L("Choose up to 2 cards to play right away."), options, min: 0, max: 2) { candidates in Array(candidates.prefix(2)) }
        for x in picked { player.deck.removeAll { $0 === x }; await placeUnit(x, by: player, row: x.allowedRows.first ?? .siege) }
    }

    /// Bait: Place on your battlefield and draw from your deck one card with Tight Bond ability. Play it immediatly.
    func abilityBait(_ card: Card, by player: Player, side: Player, row rowType: RowType, ability: String) async {
        let options = player.deck.filter { $0.has("bond") }
        if let chosen = await pickOne(player, L("Choose one card to play."), options, ai: { candidates in candidates.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
            player.deck.removeAll { $0 === chosen }; await placeUnit(chosen, by: player, row: chosen.allowedRows.first ?? rowType)
        }
    }

    /// Clairvoyance: Choose to either look at the top 3 cards of your deck OR look at 3 random cards in your opponent's hand.
    func abilityClairvoyance(_ card: Card, by player: Player, side: Player, row rowType: RowType, ability: String) async {
        let opponent = player.opponent!
        let answer = await pickOption(player, L("Clairvoyance Options"), [L("View Deck [E]"), L("Spy Enemy [Q]")]) { 1 }
        if answer == 0 { await reveal(player, L("Clairvoyance: Top 3 cards of your deck (click to close)"), Array(player.deck.prefix(3))) }
        else { await reveal(player, L("Clairvoyance: 3 random cards of enemy hand (click to close)"), Array(opponent.hand.shuffled().prefix(3))) }
    }

    /// Trade: Choose 1 card from the enemy's deck. Trade 1 of your runes from your deck to their hand.
    func abilityTrade(_ card: Card, by player: Player, side: Player, row rowType: RowType, ability: String) async {
        let opponent = player.opponent!
        if let chosen = await pickOne(player, L("Select a card from the opponent's deck to buy."), opponent.deck, ai: { candidates in candidates.max { self.aiCardValue($0) < self.aiCardValue($1) } }) {
            opponent.deck.removeAll { $0 === chosen }; chosen.owner = player; player.hand.append(chosen)
            if let rune = player.deck.first(where: { $0.key.hasPrefix("ofir_") && $0.data.isSpecial }) { player.deck.removeAll { $0 === rune }; rune.owner = opponent; opponent.hand.append(rune) }
            sound("trade")
        }
    }

    /// Rune Crafting: Choose and add a Rune card from your deck to your hand.
    func abilityRuneCall(_ card: Card, by player: Player, side: Player, row rowType: RowType, ability: String) async {
        let options = player.deck.filter { $0.key.hasPrefix("ofir_") && $0.data.isSpecial }
        if let chosen = await pickOne(player, L("Choose 1 runestone from your deck to add to your hand."), options, ai: { $0.randomElement() }) { player.deck.removeAll { $0 === chosen }; player.hand.append(chosen) }
    }

    /// Doppler: Choose an enemy unit (not hero or special) from the opposite row and transform into a basic copy of it (stats only, no abilities).
    func abilityDoppler(_ card: Card, by player: Player, side: Player, row rowType: RowType, ability: String) async {
        let opponent = player.opponent!
        let options = opponent.row(rowType).cards.filter { !$0.hero && $0.isUnit }
        if let chosen = await pickOne(player, L("Choose an enemy unit from the opposite row to transform Doppler into."), options, ai: { candidates in candidates.max { $0.basePower < $1.basePower } }) {
            card.baseOverride = chosen.basePower; sound("doppler"); await animate(card, "doppler")
        }
    }

    /// Aerondight: Place this card on the board, then move the unit with the highest original strength to the siege row. While there, triple its strength.
    func abilityAerondight(_ card: Card, by player: Player, side: Player, row rowType: RowType, ability: String) async {
        let options = player.rowCards.filter { $0 !== card && !$0.hero }
        if let chosen = await pickOne(player, L("Choose which card to equip with Aerondight."), options, ai: { candidates in candidates.max { $0.basePower < $1.basePower } }) {
            if let currentRow = player.rowOf(chosen) { player.row(currentRow).cards.removeAll { $0 === chosen } }
            player.row(.siege).cards.append(chosen); chosen.siegeMult = 3
        }
    }
}

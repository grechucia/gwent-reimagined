// Leader abilities: availability, activation and the effect of every leader card.
import Foundation

extension Game {
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
        // Pick an Impenetrable Fog or Torrential Rain card from your deck and play it instantly.
        case "foltest_king":
            let options = player.deck.filter { $0.has("fog") || $0.has("rain") }
            if let t = await pickOne(player, L("Which weather card to play? Impenetrable Fog or Torrential Rain?"), options, ai: { $0.first }) { player.deck.removeAll { $0 === t }; t.owner = player; await playWeather(t, by: player, row: nil) }
        // Pick any weather card from your deck and play it instantly.
        case "eredin_king":
            let options = player.deck.filter { $0.data.isWeather }
            if let t = await pickOne(player, L("Choose a weather card to play"), options, ai: { $0.first }) { player.deck.removeAll { $0 === t }; t.owner = player; await playWeather(t, by: player, row: nil) }
        // Clear any weather effects (resulting from Biting Frost, Torrential Rain or Impenetrable Fog cards) in play. | Clear all weather effects in play.
        case "foltest_lord", "vilgefortz_sorcerer": await clearWeather()
        // Doubles the strength of all your Siege units (unless a Commander's Horn is also present on that row).
        case "foltest_siegemaster": player.row(.siege).leaderHorn = true; sound("horn")
        // Doubles the strength of all your Ranged Combat units (unless a Commander's Horn is also present on that row).
        case "francesca_beautiful": player.row(.ranged).leaderHorn = true; sound("horn")
        // Destroy your enemy's strongest Ranged Combat unit(s) if the combined strength of all his or her Ranged Combat units is 10 or more.
        case "foltest_son": await rowScorch(o, .ranged)
        // Destroy your enemy's strongest Siege unit(s) if the combined strength of all his or her Siege units is 10 or more.
        case "foltest_steelforged": await rowScorch(o, .siege)
        // Destroy your enemy's strongest Close Combat unit(s) if the combined strength of all his or her Close Combat units is 10 or more. | Destroy your enemy's strongest Melee unit(s) if the combined…
        case "francesca_queen", "cosimo_malaspina": await rowScorch(o, .close)
        // If the opponent has a total of 10 or higher on one row, destroy that row's strongest card(s) (affects only the opponent's side of the battle field).
        case "meve_princess", "carlo_varese":
            recalc()
            if let r = RowType.allCases.filter({ o.row($0).total >= 10 }).max(by: { o.row($0).total < o.row($1).total }) { await rowScorch(o, r) }
        // Draw an opponent's discarded non-hero unit into your hand. Then put any card from your hand on the bottom of your deck.
        case "emhyr_imperial":
            let options = o.grave.filter { $0.isUnit && !$0.hero }
            if let t = await pickOne(player, L("Which card to draw?"), options, ai: best) { o.grave.removeAll { $0 === t }; resetCard(t); t.owner = player; player.hand.append(t) }
            if let back = await pickOne(player, L("Which card to put back into the deck?"), player.hand, ai: { candidates in candidates.min { self.aiCardValue($0) < self.aiCardValue($1) } }) {
                player.hand.removeAll { $0 === back }; player.deck.append(back)
            }
        // Look at 4 random cards in your opponent's hand. Choose one. Opponent must play this card on his next turn (if he does not fold).
        case "emhyr_emperor":
            let four = Array(o.hand.shuffled().prefix(4))
            if let t = await pickOne(player, L("Which card should your opponent play on the next round?"), four, ai: { candidates in candidates.min { self.aiCardValue($0) < self.aiCardValue($1) } }) { o.forcedCard = t }
        // Destroy one unit or hero card on your battlefield. Then draw any one Spy or Emissary card from your deck into your hand.
        case "emhyr_relentless":
            if let t = await pickOne(player, L("Which card to destroy?"), player.rowCards, ai: { candidates in candidates.min { $0.power < $1.power } }) { await destroy(t, side: player) }
            let options = player.deck.filter { $0.has("spy") || $0.has("emissary") }
            if let t = await pickOne(player, L("Which Spy/Emissary card to draw?"), options, ai: { $0.first }) { player.deck.removeAll { $0 === t }; player.hand.append(t) }
        // Play a unit or hero card from each player's discard pile onto their respective side of the field.
        case "emhyr_invader":
            for q in [player, o] {
                let options = q.grave.filter { $0.isUnit }
                let t = q === player ? await pickOne(player, L("Which card to restore from your grave?"), options, ai: best) : options.randomElement()
                if let t = t { q.grave.removeAll { $0 === t }; resetCard(t); await placeUnit(t, by: q, row: t.allowedRows.first ?? .close, side: q) }
            }
        // Choose on your battlefield two or less unit and/or hero cards and take them into your hand.
        case "eredin_commander":
            let picks = await pickCards(player, L("Choose on your battlefield two or less unit and/or hero cards and take them into your hand."), player.rowCards, min: 0, max: 2) { candidates in Array(candidates.filter { $0.has("spy") || $0.has("medic") }.prefix(2)) }
            for t in picks { if let r = player.rowOf(t) { player.row(r).cards.removeAll { $0 === t } }; resetCard(t); player.hand.append(t) }
        // Eredin : Bringer of Death: Restore a unit card from your discard pile to your hand.
        case "eredin_bringer_of_death":
            if let t = await pickOne(player, L("Which card to restore from your grave?"), player.grave.filter { $0.isUnit }, ai: best) { player.grave.removeAll { $0 === t }; resetCard(t); player.hand.append(t) }
        // Discard 2 cards and draw 1 card of your choice from your deck.
        case "eredin_destroyer":
            let disc = await pickCards(player, L("Which card to discard?"), player.hand, min: min(2, player.hand.count), max: 2) { candidates in Array(candidates.sorted { self.aiCardValue($0) < self.aiCardValue($1) }.prefix(2)) }
            for t in disc { player.hand.removeAll { $0 === t }; player.grave.append(t) }
            if let t = await pickOne(player, L("Which card to draw?"), player.deck, ai: best) { player.deck.removeAll { $0 === t }; player.hand.append(t) }
        // Choose 3 or less unit and/or hero cards, which lie on the opponent's battlefield. Move these cards to any other opponent's row (rows). | Choose 4 or less unit and/or hero cards, which lie on your…
        case "francesca_pureblood", "francesca_hope":
            let target = player.leaderAbility == "francesca_pureblood" ? o : player
            let n = player.leaderAbility == "francesca_pureblood" ? 3 : 4
            let picks = await pickCards(player, gameData.abilityDesc(player.leaderAbility), target.rowCards.filter { !$0.hero }, min: 0, max: n) { candidates in Array(candidates.prefix(n)) }
            for t in picks {
                guard let from = target.rowOf(t) else { continue }
                let dests = RowType.allCases.filter { $0 != from }.map { (target, $0) }
                if let (_, d) = await pickRow(player, gameData.cardName(t.data), dests, ai: { target === o ? (o.weather[dests[0].1.rawValue].isEmpty ? 1 : 0) : 0 }) {
                    target.row(from).cards.removeAll { $0 === t }; target.row(d).cards.append(t)
                }
            }
        // Shuffle all cards from each player's graveyard back into their decks. You can keep one of the cards in the graveyard.
        case "crach_an_craite":
            let keep = await pickOne(player, L("Would you like to select a card to keep in your graveyard?"), player.grave, cancel: true, ai: { _ in nil })
            for q in [player, o] {
                for card in q.grave where card !== keep { resetCard(card); q.deck.append(card) }
                q.grave = keep != nil && q === player ? [keep!] : []
                q.deck.shuffle()
            }
        // Draw from your deck any card with Mardroeme or Werewolf ability. Units are played immediately, specials are added to your hand.
        case "birna":
            let options = player.deck.filter { $0.has("mardroeme") || $0.has("berserker") }
            if let t = await pickOne(player, gameData.abilityDesc("birna"), options, ai: best) {
                player.deck.removeAll { $0 === t }
                if t.isUnit { await placeUnit(t, by: player, row: t.allowedRows.first ?? .close) } else { player.hand.append(t) }
            }
        // Set a card's strength up to 10. Resets after round. (2 uses/battle).
        case "holger_blakhand":
            let options = (player.rowCards + o.rowCards).filter { !$0.hero }
            if let t = await pickOne(player, L("Change the strength of a card?"), options, ai: { candidates in candidates.filter { $0.owner === player }.min { $0.power < $1.power } ?? candidates.first }) {
                let v = await pickOption(player, L("Select a new base power"), (1...10).map { "\($0)" }) { (t.owner === player) ? 9 : 0 }
                t.tempStrength = v + 1; t.flash = 1
            }
        // Draw three cards from your deck (excluding special cards, spies, and envoys). Play one of them immediately, shuffle the other two back into the deck. | Draw 3 cards from your deck, except special…
        case "radovid_king_redania", "nibras":
            let three = Array(player.deck.filter { !$0.data.isSpecial && !$0.data.isWeather && !$0.has("spy") && !$0.has("emissary") && !$0.has("ofiri_envoy") }.prefix(3))
            if let t = await pickOne(player, L("Choose a unit to play immediately"), three, ai: best) {
                player.deck.removeAll { $0 === t }
                if t.isUnit { await placeUnit(t, by: player, row: t.allowedRows.first ?? .close) }
                player.deck.shuffle()
            }
        // Destroy the strongest card on the battlefield (it must be a unit or a hero). If there are several strongest cards, choose and destroy only one of them.
        case "radovid_mad_king":
            recalc()
            let all = (player.rowCards + o.rowCards)
            if let mx = all.map({ $0.power }).max() {
                let cands = all.filter { $0.power == mx }
                if let t = await pickOne(player, L("Choose the card to destroy"), cands, ai: { candidates in candidates.first { $0.owner === o } ?? candidates.first }) { await destroy(t, side: o.rowCards.contains { $0 === t } ? o : player) }
            }
        // Choose one hero card on your battlefield. Take it back to your hand.
        case "radovid_strategist":
            if let t = await pickOne(player, L("Choose the hero to take back into your hand"), player.rowCards.filter { $0.hero }, ai: best) { if let r = player.rowOf(t) { player.row(r).cards.removeAll { $0 === t } }; player.hand.append(t) }
        // Pick one hero card from your grave and play it immediately.
        case "anna_henrietta_duchess":
            if let t = await pickOne(player, L("Choose the hero to play"), player.grave.filter { $0.hero && $0.isUnit }, ai: best) { player.grave.removeAll { $0 === t }; await placeUnit(t, by: player, row: t.allowedRows.first ?? .close) }
        // Choose a second-form Toussaint Monster on the battlefield to play its weaker form. You can transform it back later.
        case "anna_henrietta_ladyship":
            let options = (player.rowCards + o.rowCards).filter { $0.revertTo != nil }
            if let t = await pickOne(player, L("Choose the monster to revert to its primal form."), options, ai: { $0.first }), let k = t.revertTo, let d = gameData.cards[k] { t.transform(into: d); t.revertTo = nil }
        // Choose an enemy hero card and remove its Hero status.
        case "anna_henrietta_little_weasel":
            if let t = await pickOne(player, L("Choose the enemy hero to demote."), o.rowCards.filter { $0.hero }, ai: best) { t.heroOverride = false; t.flash = 1 }
        // Take from your discard pile in your hand 3 or less unit cards, that died in the current round.
        case "lady_wood_whispess":
            let options = player.grave.filter { $0.isUnit && $0.diedRound == round }
            let picks = await pickCards(player, gameData.abilityDesc("lady_wood_whispess"), options, min: 0, max: 3) { candidates in Array(candidates.sorted { self.aiCardValue($0) > self.aiCardValue($1) }.prefix(3)) }
            for t in picks { player.grave.removeAll { $0 === t }; player.hand.append(t) }
        // Draw a Curse card from your deck and play it immediatly.
        case "lady_wood_weavess":
            if let t = player.deck.first(where: { $0.specialKind == "curse" }) {
                player.deck.removeAll { $0 === t }; t.owner = player
                if let (q, r) = await pickRow(player, gameData.abilityName("curse"), curseRows(by: player), ai: { 3 }) { q.row(r).curse = t }
            }
        // Destroy the weakest unit card on the battlefield (any player). If there are several, choose one.
        case "ghost_tree":
            recalc()
            let all = (player.rowCards + o.rowCards).filter { !$0.hero }
            if let mn = all.map({ $0.power }).min() {
                let cands = all.filter { $0.power == mn }
                if let t = await pickOne(player, L("Choose which enemy card to destroy"), cands, ai: { candidates in candidates.first { $0.owner === o } ?? candidates.first }) { await destroy(t, side: o.rowCards.contains { $0 === t } ? o : player) }
            }
        // Draw from your deck or graveyard any number of Navigator cards. Then choose in your hand the same number of cards and put them back in any place of the deck.
        case "auberon_king":
            let navs = (player.deck + player.grave).filter { $0.has("door_o") }
            let picks = await pickCards(player, gameData.abilityDesc("auberon_king"), navs, min: 0, max: navs.count) { $0 }
            for t in picks { player.deck.removeAll { $0 === t }; player.grave.removeAll { $0 === t }; player.hand.append(t) }
            if !picks.isEmpty {
                let back = await pickCards(player, L("Which card to put back into the deck?"), player.hand.filter { card in !picks.contains { $0 === card } }, min: picks.count, max: picks.count) { candidates in Array(candidates.sorted { self.aiCardValue($0) < self.aiCardValue($1) }.prefix(picks.count)) }
                for t in back { player.hand.removeAll { $0 === t }; player.deck.insert(t, at: Int.random(in: 0...player.deck.count)) }
            }
        // Draw any special card from your deck and play it immediatly.
        case "winter_queen":
            let options = player.deck.filter { $0.data.isSpecial || $0.data.isWeather }
            if let t = await pickOne(player, L("Choose a special card to play immediatly."), options, ai: { $0.first }) {
                player.deck.removeAll { $0 === t }; t.owner = player
                if t.data.isWeather { await playWeather(t, by: player, row: nil) } else { await playSpecial(t, by: player, row: nil, rowOwner: nil, target: nil) }
            }
        // Destroy one of your units on the board and summon a Koshchey.
        case "alzur_maker":
            if let t = await pickOne(player, gameData.abilityDesc("alzur_maker"), player.rowCards.filter { !$0.hero }, ai: { candidates in candidates.min { $0.power < $1.power } }) {
                await destroy(t, side: player)
                if let d = gameData.cards["wu_koshchey"] { await placeUnit(Card(d, owner: player), by: player, row: .close) }
            }
        // Seize the unit(s) with the lowest strength of the opponents melee row.
        case "cyprian_wiley": await seize(player, .close)
        // Send all spy unit cards to the grave of the side they are on.
        case "francis_bedlam":
            for q in [player, o] { for card in q.rowCards where card.has("spy") || card.has("emissary") { await destroy(card, side: q) } }
        // Summon Flyndr's Crew
        case "gudrun_bjornsdottir":
            let crew = (player.deck + player.hand + player.grave).filter { $0.key == "sy_flyndr_crew" }
            if crew.isEmpty, let d = gameData.cards["sy_flyndr_crew"] { await placeUnit(Card(d, owner: player), by: player, row: .close) }
            for t in crew { player.deck.removeAll { $0 === t }; player.hand.removeAll { $0 === t }; player.grave.removeAll { $0 === t }; resetCard(t); await placeUnit(t, by: player, row: .close) }
        // Play a Dimeritum Shackles card in any of the opponent's row.
        case "cyrus_hemmelfart":
            if let d = gameData.cards["spe_dimeritium_shackles"], let (_, r) = await pickRow(player, gameData.abilityDesc("cyrus_hemmelfart"), RowType.allCases.map { (o, $0) }, ai: { Int.random(in: 0..<3) }) {
                o.row(r).lock = Card(d, owner: player)
            }
        // Once per game: Play an Inquisitional Pyres card on the appropriate row.
        case "cyrus_hemmelfart1":
            if let d = gameData.cards["nv_inquisitional_pyres"] { await placeUnit(Card(d, owner: player), by: player, row: .close) }
        // Destroy the enemy's weakest hero card (max 1 card).
        case "azar_javed":
            recalc()
            if let t = o.rowCards.filter({ $0.hero }).min(by: { $0.power < $1.power }) { await destroy(t, side: o) }
        // Select 2 cards from your opponent's discard pile and shuffle them back into his/her deck.
        case "baal_zebuth":
            let picks = await pickCards(player, gameData.abilityDesc("baal_zebuth"), o.grave, min: 0, max: 2) { candidates in Array(candidates.sorted { self.aiCardValue($0) > self.aiCardValue($1) }.prefix(2)) }
            for t in picks { o.grave.removeAll { $0 === t }; resetCard(t); o.deck.append(t) }
            o.deck.shuffle()
        // Draw a random card from the discard pile to your hand (any card) and then shuffle the rest back into the deck.
        case "rarog":
            if let t = player.grave.randomElement() {
                player.grave.removeAll { $0 === t }; resetCard(t); player.hand.append(t)
                for card in player.grave { resetCard(card); player.deck.append(card) }
                player.grave.removeAll(); player.deck.shuffle()
            }
        // Once per game, you may look at the top 3 cards of your opponent's deck. Add one to your hand and put the remaining cards into their discard pile.
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
}

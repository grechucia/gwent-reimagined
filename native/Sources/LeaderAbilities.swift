// Leader abilities: availability, activation and the effect of every leader card.
import Foundation

extension Game {
    /// The most valuable card of a list, judged by the AI card value.
    func strongestCard(_ cards: [Card]) -> Card? { cards.max { self.aiCardValue($0) < self.aiCardValue($1) } }

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
        let opponent = player.opponent!
        switch player.leaderAbility {
        // Pick an Impenetrable Fog or Torrential Rain card from your deck and play it instantly.
        case "foltest_king": await leaderFoltestKing(player, free: free)
        // Pick any weather card from your deck and play it instantly.
        case "eredin_king": await leaderEredinKing(player, free: free)
        // Clear any weather effects (resulting from Biting Frost, Torrential Rain or Impenetrable Fog cards) in play. | Clear all weather effects in play.
        case "foltest_lord", "vilgefortz_sorcerer": await clearWeather()
        // Doubles the strength of all your Siege units (unless a Commander's Horn is also present on that row).
        case "foltest_siegemaster": player.row(.siege).leaderHorn = true; sound("horn")
        // Doubles the strength of all your Ranged Combat units (unless a Commander's Horn is also present on that row).
        case "francesca_beautiful": player.row(.ranged).leaderHorn = true; sound("horn")
        // Destroy your enemy's strongest Ranged Combat unit(s) if the combined strength of all his or her Ranged Combat units is 10 or more.
        case "foltest_son": await rowScorch(opponent, .ranged)
        // Destroy your enemy's strongest Siege unit(s) if the combined strength of all his or her Siege units is 10 or more.
        case "foltest_steelforged": await rowScorch(opponent, .siege)
        // Destroy your enemy's strongest Close Combat unit(s) if the combined strength of all his or her Close Combat units is 10 or more. | Destroy your enemy's strongest Melee unit(s) if the combined…
        case "francesca_queen", "cosimo_malaspina": await rowScorch(opponent, .close)
        // If the opponent has a total of 10 or higher on one row, destroy that row's strongest card(s) (affects only the opponent's side of the battle field).
        case "meve_princess", "carlo_varese": await leaderMevePrincess(player, free: free)
        // Draw an opponent's discarded non-hero unit into your hand. Then put any card from your hand on the bottom of your deck.
        case "emhyr_imperial": await leaderEmhyrImperial(player, free: free)
        // Look at 4 random cards in your opponent's hand. Choose one. Opponent must play this card on his next turn (if he does not fold).
        case "emhyr_emperor": await leaderEmhyrEmperor(player, free: free)
        // Destroy one unit or hero card on your battlefield. Then draw any one Spy or Emissary card from your deck into your hand.
        case "emhyr_relentless": await leaderEmhyrRelentless(player, free: free)
        // Play a unit or hero card from each player's discard pile onto their respective side of the field.
        case "emhyr_invader": await leaderEmhyrInvader(player, free: free)
        // Choose on your battlefield two or less unit and/or hero cards and take them into your hand.
        case "eredin_commander": await leaderEredinCommander(player, free: free)
        // Eredin : Bringer of Death: Restore a unit card from your discard pile to your hand.
        case "eredin_bringer_of_death":
            if let chosen = await pickOne(player, L("Which card to restore from your grave?"), player.grave.filter { $0.isUnit }, ai: strongestCard) { player.grave.removeAll { $0 === chosen }; resetCard(chosen); player.hand.append(chosen) }
        // Discard 2 cards and draw 1 card of your choice from your deck.
        case "eredin_destroyer": await leaderEredinDestroyer(player, free: free)
        // Choose 3 or less unit and/or hero cards, which lie on the opponent's battlefield. Move these cards to any other opponent's row (rows). | Choose 4 or less unit and/or hero cards, which lie on your…
        case "francesca_pureblood", "francesca_hope": await leaderFrancescaPureblood(player, free: free)
        // Shuffle all cards from each player's graveyard back into their decks. You can keep one of the cards in the graveyard.
        case "crach_an_craite": await leaderCrachAnCraite(player, free: free)
        // Draw from your deck any card with Mardroeme or Werewolf ability. Units are played immediately, specials are added to your hand.
        case "birna": await leaderBirna(player, free: free)
        // Set a card's strength up to 10. Resets after round. (2 uses/battle).
        case "holger_blakhand": await leaderHolgerBlakhand(player, free: free)
        // Draw three cards from your deck (excluding special cards, spies, and envoys). Play one of them immediately, shuffle the other two back into the deck. | Draw 3 cards from your deck, except special…
        case "radovid_king_redania", "nibras": await leaderRadovidKingRedania(player, free: free)
        // Destroy the strongest card on the battlefield (it must be a unit or a hero). If there are several strongest cards, choose and destroy only one of them.
        case "radovid_mad_king": await leaderRadovidMadKing(player, free: free)
        // Choose one hero card on your battlefield. Take it back to your hand.
        case "radovid_strategist":
            if let chosen = await pickOne(player, L("Choose the hero to take back into your hand"), player.rowCards.filter { $0.hero }, ai: strongestCard) { if let rowType = player.rowOf(chosen) { player.row(rowType).cards.removeAll { $0 === chosen } }; player.hand.append(chosen) }
        // Pick one hero card from your grave and play it immediately.
        case "anna_henrietta_duchess":
            if let chosen = await pickOne(player, L("Choose the hero to play"), player.grave.filter { $0.hero && $0.isUnit }, ai: strongestCard) { player.grave.removeAll { $0 === chosen }; await placeUnit(chosen, by: player, row: chosen.allowedRows.first ?? .close) }
        // Choose a second-form Toussaint Monster on the battlefield to play its weaker form. You can transform it back later.
        case "anna_henrietta_ladyship": await leaderAnnaHenriettaLadyship(player, free: free)
        // Choose an enemy hero card and remove its Hero status.
        case "anna_henrietta_little_weasel":
            if let chosen = await pickOne(player, L("Choose the enemy hero to demote."), opponent.rowCards.filter { $0.hero }, ai: strongestCard) { chosen.heroOverride = false; chosen.flash = 1 }
        // Take from your discard pile in your hand 3 or less unit cards, that died in the current round.
        case "lady_wood_whispess": await leaderLadyWoodWhispess(player, free: free)
        // Draw a Curse card from your deck and play it immediatly.
        case "lady_wood_weavess": await leaderLadyWoodWeavess(player, free: free)
        // Destroy the weakest unit card on the battlefield (any player). If there are several, choose one.
        case "ghost_tree": await leaderGhostTree(player, free: free)
        // Draw from your deck or graveyard any number of Navigator cards. Then choose in your hand the same number of cards and put them back in any place of the deck.
        case "auberon_king": await leaderAuberonKing(player, free: free)
        // Draw any special card from your deck and play it immediatly.
        case "winter_queen": await leaderWinterQueen(player, free: free)
        // Destroy one of your units on the board and summon a Koshchey.
        case "alzur_maker": await leaderAlzurMaker(player, free: free)
        // Seize the unit(s) with the lowest strength of the opponents melee row.
        case "cyprian_wiley": await seize(player, .close)
        // Send all spy unit cards to the grave of the side they are on.
        case "francis_bedlam":
            for q in [player, opponent] { for card in q.rowCards where card.has("spy") || card.has("emissary") { await destroy(card, side: q) } }
        // Summon Flyndr's Crew
        case "gudrun_bjornsdottir": await leaderGudrunBjornsdottir(player, free: free)
        // Play a Dimeritum Shackles card in any of the opponent's row.
        case "cyrus_hemmelfart": await leaderCyrusHemmelfart(player, free: free)
        // Once per game: Play an Inquisitional Pyres card on the appropriate row.
        case "cyrus_hemmelfart1":
            if let cardData = gameData.cards["nv_inquisitional_pyres"] { await placeUnit(Card(cardData, owner: player), by: player, row: .close) }
        // Destroy the enemy's weakest hero card (max 1 card).
        case "azar_javed": await leaderAzarJaved(player, free: free)
        // Select 2 cards from your opponent's discard pile and shuffle them back into his/her deck.
        case "baal_zebuth": await leaderBaalZebuth(player, free: free)
        // Draw a random card from the discard pile to your hand (any card) and then shuffle the rest back into the deck.
        case "rarog": await leaderRarog(player, free: free)
        // Once per game, you may look at the top 3 cards of your opponent's deck. Add one to your hand and put the remaining cards into their discard pile.
        case "nibras_gale": await leaderNibrasGale(player, free: free)
        default: break
        }
        recalc()
    }

    /// Pick an Impenetrable Fog or Torrential Rain card from your deck and play it instantly.
    func leaderFoltestKing(_ player: Player, free: Bool) async {
        let options = player.deck.filter { $0.has("fog") || $0.has("rain") }
        if let chosen = await pickOne(player, L("Which weather card to play? Impenetrable Fog or Torrential Rain?"), options, ai: { $0.first }) { player.deck.removeAll { $0 === chosen }; chosen.owner = player; await playWeather(chosen, by: player, row: nil) }
    }

    /// Pick any weather card from your deck and play it instantly.
    func leaderEredinKing(_ player: Player, free: Bool) async {
        let options = player.deck.filter { $0.data.isWeather }
        if let chosen = await pickOne(player, L("Choose a weather card to play"), options, ai: { $0.first }) { player.deck.removeAll { $0 === chosen }; chosen.owner = player; await playWeather(chosen, by: player, row: nil) }
    }

    /// If the opponent has a total of 10 or higher on one row, destroy that row's strongest card(s) (affects only the opponent's side of the battle field).
    func leaderMevePrincess(_ player: Player, free: Bool) async {
        let opponent = player.opponent!
        recalc()
        if let strongRows = RowType.allCases.filter({ opponent.row($0).total >= 10 }).max(by: { opponent.row($0).total < opponent.row($1).total }) { await rowScorch(opponent, strongRows) }
    }

    /// Draw an opponent's discarded non-hero unit into your hand. Then put any card from your hand on the bottom of your deck.
    func leaderEmhyrImperial(_ player: Player, free: Bool) async {
        let opponent = player.opponent!
        let options = opponent.grave.filter { $0.isUnit && !$0.hero }
        if let chosen = await pickOne(player, L("Which card to draw?"), options, ai: strongestCard) { opponent.grave.removeAll { $0 === chosen }; resetCard(chosen); chosen.owner = player; player.hand.append(chosen) }
        if let back = await pickOne(player, L("Which card to put back into the deck?"), player.hand, ai: { candidates in candidates.min { self.aiCardValue($0) < self.aiCardValue($1) } }) {
            player.hand.removeAll { $0 === back }; player.deck.append(back)
        }
    }

    /// Look at 4 random cards in your opponent's hand. Choose one. Opponent must play this card on his next turn (if he does not fold).
    func leaderEmhyrEmperor(_ player: Player, free: Bool) async {
        let opponent = player.opponent!
        let four = Array(opponent.hand.shuffled().prefix(4))
        if let chosen = await pickOne(player, L("Which card should your opponent play on the next round?"), four, ai: { candidates in candidates.min { self.aiCardValue($0) < self.aiCardValue($1) } }) { opponent.forcedCard = chosen }
    }

    /// Destroy one unit or hero card on your battlefield. Then draw any one Spy or Emissary card from your deck into your hand.
    func leaderEmhyrRelentless(_ player: Player, free: Bool) async {
        if let chosen = await pickOne(player, L("Which card to destroy?"), player.rowCards, ai: { candidates in candidates.min { $0.power < $1.power } }) { await destroy(chosen, side: player) }
        let options = player.deck.filter { $0.has("spy") || $0.has("emissary") }
        if let chosen = await pickOne(player, L("Which Spy/Emissary card to draw?"), options, ai: { $0.first }) { player.deck.removeAll { $0 === chosen }; player.hand.append(chosen) }
    }

    /// Play a unit or hero card from each player's discard pile onto their respective side of the field.
    func leaderEmhyrInvader(_ player: Player, free: Bool) async {
        let opponent = player.opponent!
        for q in [player, opponent] {
            let options = q.grave.filter { $0.isUnit }
            let t = q === player ? await pickOne(player, L("Which card to restore from your grave?"), options, ai: strongestCard) : options.randomElement()
            if let t = t { q.grave.removeAll { $0 === t }; resetCard(t); await placeUnit(t, by: q, row: t.allowedRows.first ?? .close, side: q) }
        }
    }

    /// Choose on your battlefield two or less unit and/or hero cards and take them into your hand.
    func leaderEredinCommander(_ player: Player, free: Bool) async {
        let picked = await pickCards(player, L("Choose on your battlefield two or less unit and/or hero cards and take them into your hand."), player.rowCards, min: 0, max: 2) { candidates in Array(candidates.filter { $0.has("spy") || $0.has("medic") }.prefix(2)) }
        for card in picked { if let currentRow = player.rowOf(card) { player.row(currentRow).cards.removeAll { $0 === card } }; resetCard(card); player.hand.append(card) }
    }

    /// Discard 2 cards and draw 1 card of your choice from your deck.
    func leaderEredinDestroyer(_ player: Player, free: Bool) async {
        let disc = await pickCards(player, L("Which card to discard?"), player.hand, min: min(2, player.hand.count), max: 2) { candidates in Array(candidates.sorted { self.aiCardValue($0) < self.aiCardValue($1) }.prefix(2)) }
        for card in disc { player.hand.removeAll { $0 === card }; player.grave.append(card) }
        if let chosen = await pickOne(player, L("Which card to draw?"), player.deck, ai: strongestCard) { player.deck.removeAll { $0 === chosen }; player.hand.append(chosen) }
    }

    /// Choose 3 or less unit and/or hero cards, which lie on the opponent's battlefield. Move these cards to any other opponent's row (rows). | Choose 4 or less unit and/or hero cards, which lie on your…
    func leaderFrancescaPureblood(_ player: Player, free: Bool) async {
        let opponent = player.opponent!
        let target = player.leaderAbility == "francesca_pureblood" ? opponent : player
        let maxCount = player.leaderAbility == "francesca_pureblood" ? 3 : 4
        let picks = await pickCards(player, gameData.abilityDesc(player.leaderAbility), target.rowCards.filter { !$0.hero }, min: 0, max: maxCount) { candidates in Array(candidates.prefix(maxCount)) }
        for card in picks {
            guard let from = target.rowOf(card) else { continue }
            let dests = RowType.allCases.filter { $0 != from }.map { (target, $0) }
            if let (_, d) = await pickRow(player, gameData.cardName(card.data), dests, ai: { target === opponent ? (opponent.weather[dests[0].1.rawValue].isEmpty ? 1 : 0) : 0 }) {
                target.row(from).cards.removeAll { $0 === card }; target.row(d).cards.append(card)
            }
        }
    }

    /// Shuffle all cards from each player's graveyard back into their decks. You can keep one of the cards in the graveyard.
    func leaderCrachAnCraite(_ player: Player, free: Bool) async {
        let opponent = player.opponent!
        let keep = await pickOne(player, L("Would you like to select a card to keep in your graveyard?"), player.grave, cancel: true, ai: { _ in nil })
        for side in [player, opponent] {
            for card in side.grave where card !== keep { resetCard(card); side.deck.append(card) }
            side.grave = keep != nil && side === player ? [keep!] : []
            side.deck.shuffle()
        }
    }

    /// Draw from your deck any card with Mardroeme or Werewolf ability. Units are played immediately, specials are added to your hand.
    func leaderBirna(_ player: Player, free: Bool) async {
        let options = player.deck.filter { $0.has("mardroeme") || $0.has("berserker") }
        if let chosen = await pickOne(player, gameData.abilityDesc("birna"), options, ai: strongestCard) {
            player.deck.removeAll { $0 === chosen }
            if chosen.isUnit { await placeUnit(chosen, by: player, row: chosen.allowedRows.first ?? .close) } else { player.hand.append(chosen) }
        }
    }

    /// Set a card's strength up to 10. Resets after round. (2 uses/battle).
    func leaderHolgerBlakhand(_ player: Player, free: Bool) async {
        let opponent = player.opponent!
        let options = (player.rowCards + opponent.rowCards).filter { !$0.hero }
        if let chosen = await pickOne(player, L("Change the strength of a card?"), options, ai: { candidates in candidates.filter { $0.owner === player }.min { $0.power < $1.power } ?? candidates.first }) {
            let v = await pickOption(player, L("Select a new base power"), (1...10).map { "\($0)" }) { (chosen.owner === player) ? 9 : 0 }
            chosen.tempStrength = v + 1; chosen.flash = 1
        }
    }

    /// Draw three cards from your deck (excluding special cards, spies, and envoys). Play one of them immediately, shuffle the other two back into the deck. | Draw 3 cards from your deck, except special…
    func leaderRadovidKingRedania(_ player: Player, free: Bool) async {
        let three = Array(player.deck.filter { !$0.data.isSpecial && !$0.data.isWeather && !$0.has("spy") && !$0.has("emissary") && !$0.has("ofiri_envoy") }.prefix(3))
        if let chosen = await pickOne(player, L("Choose a unit to play immediately"), three, ai: strongestCard) {
            player.deck.removeAll { $0 === chosen }
            if chosen.isUnit { await placeUnit(chosen, by: player, row: chosen.allowedRows.first ?? .close) }
            player.deck.shuffle()
        }
    }

    /// Destroy the strongest card on the battlefield (it must be a unit or a hero). If there are several strongest cards, choose and destroy only one of them.
    func leaderRadovidMadKing(_ player: Player, free: Bool) async {
        let opponent = player.opponent!
        recalc()
        let all = (player.rowCards + opponent.rowCards)
        if let highestPower = all.map({ $0.power }).max() {
            let cands = all.filter { $0.power == highestPower }
            if let chosen = await pickOne(player, L("Choose the card to destroy"), cands, ai: { candidates in candidates.first { $0.owner === opponent } ?? candidates.first }) { await destroy(chosen, side: opponent.rowCards.contains { $0 === chosen } ? opponent : player) }
        }
    }

    /// Choose a second-form Toussaint Monster on the battlefield to play its weaker form. You can transform it back later.
    func leaderAnnaHenriettaLadyship(_ player: Player, free: Bool) async {
        let opponent = player.opponent!
        let options = (player.rowCards + opponent.rowCards).filter { $0.revertTo != nil }
        if let chosen = await pickOne(player, L("Choose the monster to revert to its primal form."), options, ai: { $0.first }), let originalKey = chosen.revertTo, let d = gameData.cards[originalKey] { chosen.transform(into: d); chosen.revertTo = nil }
    }

    /// Take from your discard pile in your hand 3 or less unit cards, that died in the current round.
    func leaderLadyWoodWhispess(_ player: Player, free: Bool) async {
        let options = player.grave.filter { $0.isUnit && $0.diedRound == round }
        let picked = await pickCards(player, gameData.abilityDesc("lady_wood_whispess"), options, min: 0, max: 3) { candidates in Array(candidates.sorted { self.aiCardValue($0) > self.aiCardValue($1) }.prefix(3)) }
        for card in picked { player.grave.removeAll { $0 === card }; player.hand.append(card) }
    }

    /// Draw a Curse card from your deck and play it immediatly.
    func leaderLadyWoodWeavess(_ player: Player, free: Bool) async {
        if let topCard = player.deck.first(where: { $0.specialKind == "curse" }) {
            player.deck.removeAll { $0 === topCard }; topCard.owner = player
            if let (q, r) = await pickRow(player, gameData.abilityName("curse"), curseRows(by: player), ai: { 3 }) { q.row(r).curse = topCard }
        }
    }

    /// Destroy the weakest unit card on the battlefield (any player). If there are several, choose one.
    func leaderGhostTree(_ player: Player, free: Bool) async {
        let opponent = player.opponent!
        recalc()
        let all = (player.rowCards + opponent.rowCards).filter { !$0.hero }
        if let lowestPower = all.map({ $0.power }).min() {
            let cands = all.filter { $0.power == lowestPower }
            if let chosen = await pickOne(player, L("Choose which enemy card to destroy"), cands, ai: { candidates in candidates.first { $0.owner === opponent } ?? candidates.first }) { await destroy(chosen, side: opponent.rowCards.contains { $0 === chosen } ? opponent : player) }
        }
    }

    /// Draw from your deck or graveyard any number of Navigator cards. Then choose in your hand the same number of cards and put them back in any place of the deck.
    func leaderAuberonKing(_ player: Player, free: Bool) async {
        let navs = (player.deck + player.grave).filter { $0.has("door_o") }
        let picked = await pickCards(player, gameData.abilityDesc("auberon_king"), navs, min: 0, max: navs.count) { $0 }
        for card in picked { player.deck.removeAll { $0 === card }; player.grave.removeAll { $0 === card }; player.hand.append(card) }
        if !picked.isEmpty {
            let back = await pickCards(player, L("Which card to put back into the deck?"), player.hand.filter { card in !picked.contains { $0 === card } }, min: picked.count, max: picked.count) { candidates in Array(candidates.sorted { self.aiCardValue($0) < self.aiCardValue($1) }.prefix(picked.count)) }
            for card in back { player.hand.removeAll { $0 === card }; player.deck.insert(card, at: Int.random(in: 0...player.deck.count)) }
        }
    }

    /// Draw any special card from your deck and play it immediatly.
    func leaderWinterQueen(_ player: Player, free: Bool) async {
        let options = player.deck.filter { $0.data.isSpecial || $0.data.isWeather }
        if let chosen = await pickOne(player, L("Choose a special card to play immediatly."), options, ai: { $0.first }) {
            player.deck.removeAll { $0 === chosen }; chosen.owner = player
            if chosen.data.isWeather { await playWeather(chosen, by: player, row: nil) } else { await playSpecial(chosen, by: player, row: nil, rowOwner: nil, target: nil) }
        }
    }

    /// Destroy one of your units on the board and summon a Koshchey.
    func leaderAlzurMaker(_ player: Player, free: Bool) async {
        if let chosen = await pickOne(player, gameData.abilityDesc("alzur_maker"), player.rowCards.filter { !$0.hero }, ai: { candidates in candidates.min { $0.power < $1.power } }) {
            await destroy(chosen, side: player)
            if let cardData = gameData.cards["wu_koshchey"] { await placeUnit(Card(cardData, owner: player), by: player, row: .close) }
        }
    }

    /// Summon Flyndr's Crew
    func leaderGudrunBjornsdottir(_ player: Player, free: Bool) async {
        let crew = (player.deck + player.hand + player.grave).filter { $0.key == "sy_flyndr_crew" }
        if crew.isEmpty, let cardData = gameData.cards["sy_flyndr_crew"] { await placeUnit(Card(cardData, owner: player), by: player, row: .close) }
        for crewMember in crew { player.deck.removeAll { $0 === crewMember }; player.hand.removeAll { $0 === crewMember }; player.grave.removeAll { $0 === crewMember }; resetCard(crewMember); await placeUnit(crewMember, by: player, row: .close) }
    }

    /// Play a Dimeritum Shackles card in any of the opponent's row.
    func leaderCyrusHemmelfart(_ player: Player, free: Bool) async {
        let opponent = player.opponent!
        if let shacklesData = gameData.cards["spe_dimeritium_shackles"], let (_, r) = await pickRow(player, gameData.abilityDesc("cyrus_hemmelfart"), RowType.allCases.map { (opponent, $0) }, ai: { Int.random(in: 0..<3) }) {
            opponent.row(r).lock = Card(shacklesData, owner: player)
        }
    }

    /// Destroy the enemy's weakest hero card (max 1 card).
    func leaderAzarJaved(_ player: Player, free: Bool) async {
        let opponent = player.opponent!
        recalc()
        if let candidates = opponent.rowCards.filter({ $0.hero }).min(by: { $0.power < $1.power }) { await destroy(candidates, side: opponent) }
    }

    /// Select 2 cards from your opponent's discard pile and shuffle them back into his/her deck.
    func leaderBaalZebuth(_ player: Player, free: Bool) async {
        let opponent = player.opponent!
        let picked = await pickCards(player, gameData.abilityDesc("baal_zebuth"), opponent.grave, min: 0, max: 2) { candidates in Array(candidates.sorted { self.aiCardValue($0) > self.aiCardValue($1) }.prefix(2)) }
        for card in picked { opponent.grave.removeAll { $0 === card }; resetCard(card); opponent.deck.append(card) }
        opponent.deck.shuffle()
    }

    /// Draw a random card from the discard pile to your hand (any card) and then shuffle the rest back into the deck.
    func leaderRarog(_ player: Player, free: Bool) async {
        if let revived = player.grave.randomElement() {
            player.grave.removeAll { $0 === revived }; resetCard(revived); player.hand.append(revived)
            for card in player.grave { resetCard(card); player.deck.append(card) }
            player.grave.removeAll(); player.deck.shuffle()
        }
    }

    /// Once per game, you may look at the top 3 cards of your opponent's deck. Add one to your hand and put the remaining cards into their discard pile.
    func leaderNibrasGale(_ player: Player, free: Bool) async {
        let opponent = player.opponent!
        let three = Array(opponent.deck.prefix(3))
        if let chosen = await pickOne(player, L("Choose a card to add to your hand (others will be discarded)"), three, ai: strongestCard) {
            opponent.deck.removeAll { x in three.contains { $0 === x } }
            chosen.owner = player; player.hand.append(chosen)
            for x in three where x !== chosen { opponent.grave.append(x) }
        }
    }
}

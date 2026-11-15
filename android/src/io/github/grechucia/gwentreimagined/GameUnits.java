// Unit abilities: what happens when a unit card is placed (spy, medic, muster, berserker, djinn...).
package io.github.grechucia.gwentreimagined;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import static io.github.grechucia.gwentreimagined.GameData.L;

/** Unit ability layer of the engine. */
abstract class GameUnits extends GameScoring {
    GameUnits(DeckData myDeck, DeckData opponentDeck) { super(myDeck, opponentDeck); }

    // Implemented by the special-card layer.
    abstract void destroy(Card card, Player side, boolean burn);
    abstract void scorch(Card except);
    abstract void cull(Card except);
    abstract void rowScorch(Player side, RowType rowType);

    /** Resolves the abilities of a unit that was just placed. */
    @Override void unitAbilities(Card card, Player player, Player side, RowType rowType) {
        for (String ability : new ArrayList<>(card.data().abilities)) {
            switch (ability) {
                // Spy: place on the opponent's side and draw 2 cards.
                case "spy": abilitySpy(card, player); break;
                // Emissary: draw one card or look at the top 4 and reorder them.
                case "emissary": abilityEmissary(player); break;
                // Ofiri Envoy: draw 1 card from the opponent's deck and 1 from yours, or 2 from yours.
                case "ofiri_envoy": abilityOfiriEnvoy(player); break;
                // Medic: play a unit from the discard pile.
                case "medic": medic(player); break;
                // Muster: play every card with the same name from deck and hand.
                case "muster": muster(card, player, rowType); break;
                // Invoke: play one of the associated cards from the deck.
                case "invoke": abilityInvoke(card, player, rowType); break;
                // Summon One Of: summon one associated card from anywhere.
                case "summon_one_of": abilitySummonOneOf(card, player, rowType); break;
                // Row scorch: destroy the strongest enemy unit(s) of one row if the row has 10 or more strength.
                case "scorch_c": case "scorch_r": case "scorch_s": rowScorch(player.opponent, scorchRow(ability)); break;
                // Scorch: destroy the strongest card(s) on the battlefield.
                case "scorch": scorch(card); break;
                // Cull: destroy the weakest card(s) on the battlefield.
                case "cull": cull(card); break;
                // Mardroeme: transform every berserker on the row.
                case "mardroeme": berserk(side, rowType); break;
                // Berserker: transform when a Mardroeme is on the row.
                case "berserker": {
                    boolean mardroeme = false;
                    for (Card s : side.row(rowType).specials) if ("mardroeme".equals(s.specialKind())) mardroeme = true;
                    for (Card c : side.row(rowType).cards) if (c.act("mardroeme")) mardroeme = true;
                    if (mardroeme) berserk(side, rowType);
                    break;
                }
                // Witch Hunt: destroy the weakest unit on the opposite row.
                case "witch_hunt": abilityWitchHunt(player, rowType); break;
                // Necrophage: shuffle up to 2 units from the discard pile back into the deck.
                case "necrophage": abilityNecrophage(player); break;
                // Goetia: take 1 card from the deck, then put 1 card from the hand back.
                case "goetia": abilityGoetia(player); break;
                // Sage: look at the top 4 cards and reorder them.
                case "sage": reorderTop(player, 4); break;
                // Zirael: reveal 5 cards and keep up to 2.
                case "zirael": abilityZirael(player); break;
                // Naglfar: play up to 2 Naglfar cards from the deck.
                case "naglfar": abilityNaglfar(player); break;
                // Bait: play a Tight Bond card from the deck.
                case "bait": abilityBait(player, rowType); break;
                // Clairvoyance: look at your top 3 cards or 3 random cards of the enemy hand.
                case "clairvoyance": abilityClairvoyance(player); break;
                // Trade: buy a card from the enemy deck and give them one of your runes.
                case "trade": abilityTrade(player); break;
                // Rune Crafting: add a rune from the deck to the hand.
                case "rune_call": abilityRuneCall(player); break;
                // Omen: add a copy of Cat and Dog to the hand.
                case "omen": { CardData d = gameData().cards.get("nv_catanddog"); if (d != null) player.hand.add(new Card(d, player)); break; }
                // Malicious Wishes of the Djinn.
                case "wish1": case "wish2": case "wish3": djinnWish(ability, card, player); break;
                // Doppler: copy the strength of an enemy unit on the opposite row.
                case "doppler": abilityDoppler(card, player, rowType); break;
                // Aerondight: move the strongest unit to the siege row and triple it.
                case "aerondight": abilityAerondight(card, player); break;
                // Immortal: stays on the battlefield for 2 rounds.
                case "immortal": card.immortalRounds = 2; break;
                default: break;
            }
        }
    }

    /** Row hit by a row-scorch ability ("scorch_c", "scorch_r" or "scorch_s"). */
    static RowType scorchRow(String ability) { return ability.equals("scorch_c") ? RowType.CLOSE : (ability.equals("scorch_r") ? RowType.RANGED : RowType.SIEGE); }

    /** Spy: the player draws cards. */
    void spyDraw(Player player, int count) {
        Player opponent = player.opponent;
        for (int i = 0; i < count; i++) {
            if (player.leaderAbility().equals("emhyr_whiteflame") && player.drawOpponentLeft > 0 && !opponent.deck.isEmpty()) {
                int answer = pickOption(player, L("Choose deck to draw from"), Arrays.asList(L("Own deck [E]"), L("Opponent's deck [Q]")), () -> 1);
                if (answer == 1 && !opponent.deck.isEmpty()) {
                    Card topCard = opponent.deck.remove(0); topCard.owner = player; player.hand.add(topCard); player.drawOpponentLeft -= 1; continue;
                }
            }
            draw(player, 1);
        }
    }
    /** Lets the player reorder the top cards of the deck. */
    void reorderTop(Player player, int count) {
        List<Card> top = new ArrayList<>(player.deck.subList(0, Math.min(count, player.deck.size())));
        if (top.isEmpty()) return;
        List<Card> order = pickCards(player, L("Re-order the cards back into the deck"), top, top.size(), top.size(), false, this::byValueDescending);
        for (int i = 0; i < top.size(); i++) player.deck.remove(0);
        player.deck.addAll(0, order.isEmpty() ? top : order);
    }
    /** Medic: revives a unit from the graveyard. */
    void medic(Player player) {
        sound("med");
        for (int i = 0; i < medicPicks; i++) {
            List<Card> options = filter(player.grave, c -> c.isUnit() && !c.hero());
            Card card = pickOne(player, L("Which card to restore from your grave?"), options, true, this::mostValuable);
            if (card == null) return;
            player.grave.remove(card);
            resetCard(card);
            placeUnit(card, player, card.firstRow(), null);
        }
    }
    /** Muster: plays every copy of the card from deck and hand. */
    void muster(Card card, Player player, RowType rowType) {
        String key = card.groupKey();
        List<Card> fromHand = filter(player.hand, c -> c != card && c.groupKey().equals(key) && c.isUnit());
        List<Card> fromDeck = filter(player.deck, c -> c.groupKey().equals(key) && c.isUnit());
        if (fromHand.isEmpty() && fromDeck.isEmpty()) return;
        List<Card> all = new ArrayList<>(fromHand); all.addAll(fromDeck);
        for (Card copy : all) {
            player.hand.remove(copy); player.deck.remove(copy);
            RowType fixed = RowType.from(copy.data().row);
            RowType musterRow = card.data().row.startsWith("agile") ? rowType : (fixed != null ? fixed : copy.firstRow());
            copy.owner = player; copy.playedTurn = turn;
            player.row(musterRow).cards.add(copy); copy.flash = 1;
        }
        sound("ally");
        recalc();
    }
    /** Berserker: transforms berserkers on a row when mardroeme is present. */
    void berserk(Player side, RowType rowType) {
        for (Card berserker : new ArrayList<>(side.row(rowType).cards)) {
            if (!berserker.act("berserker") || berserker.data().targets.isEmpty()) continue;
            CardData transformData = gameData().cards.get(berserker.data().targets.get(0));
            if (transformData != null) { berserker.transform(transformData); events.add(GameEvent.anim(berserker, "mardroeme")); }
        }
        sound("mardroeme");
        recalc();
    }
    /** Djinn: grants one of the wishes. */
    void djinnWish(String ability, Card card, Player player) {
        Player opponent = player.opponent;
        int minStrength = ability.equals("wish3") ? 7 : 6;
        Card cost = filter(player.rowCards(), c -> c != card && !c.hero() && c.basePower() >= minStrength).stream().max(Comparator.comparingInt(c -> c.power)).orElse(null);
        if (cost == null) return;
        destroy(cost, player, true);
        switch (ability) {
            case "wish1": {
                List<Card> shuffled = new ArrayList<>(opponent.hand); Collections.shuffle(shuffled);
                List<Card> three = new ArrayList<>(shuffled.subList(0, Math.min(3, shuffled.size())));
                Card chosen = pickOne(player, L("The Djinn grants your wish: Choose 1 enemy card to steal."), three, this::mostValuable);
                if (chosen != null) { opponent.hand.remove(chosen); chosen.owner = player; player.hand.add(chosen); }
                break;
            }
            case "wish2": {
                List<Card> three = new ArrayList<>(player.deck.subList(0, Math.min(3, player.deck.size())));
                Card chosen = pickOne(player, L("The Djinn grants your second wish: Choose 1 card from your deck to draw."), three, this::mostValuable);
                if (chosen != null) { player.deck.remove(chosen); player.hand.add(chosen); }
                card.immortalRounds = Math.max(card.immortalRounds, 1);
                break;
            }
            default: {
                List<Card> options = filter(opponent.rowCards(), c -> !c.hero() && c.immortalRounds == 0);
                Card chosen = pickOne(player, L("The Djinn grants your third wish: Choose 1 enemy unit to destroy."), options, this::strongestByPower);
                if (chosen != null) destroy(chosen, opponent, true);
                card.immortalRounds = Math.max(card.immortalRounds, 1);
            }
        }
    }

    /** Spy ability; Toussaint spies let the player choose 1 of the top 3 cards instead. */
    void abilitySpy(Card card, Player player) {
        if (player.faction().equals("toussaint")) {
            List<Card> three = new ArrayList<>(player.deck.subList(0, Math.min(3, player.deck.size())));
            Card chosen = pickOne(player, L("Choose the card to draw and keep"), three, this::mostValuable);
            if (chosen != null) { player.deck.remove(chosen); player.hand.add(chosen); Collections.shuffle(player.deck); }
        } else spyDraw(player, 2);
        sound("spy");
    }
    void abilityEmissary(Player player) {
        int answer = pickOption(player, L("Choose the effect of the emissary"), Arrays.asList(L("Draw 1 card [E]"), L("Look first 4 cards [Q]")), () -> 0);
        if (answer == 0) spyDraw(player, 1); else reorderTop(player, 4);
        sound("emissary");
    }
    void abilityOfiriEnvoy(Player player) {
        Player opponent = player.opponent;
        int answer = player.drawOpponentLeft > 0 && !opponent.deck.isEmpty()
            ? pickOption(player, L("From which deck to draw the next card? (Ofiri Envoy can draw from opponent's deck only once)"), Arrays.asList(L("Own deck [E]"), L("Opponent's deck [Q]")), () -> 0) : 0;
        if (answer == 1) {
            player.drawOpponentLeft = 0;
            if (!opponent.deck.isEmpty()) { Card topCard = opponent.deck.remove(0); topCard.owner = player; player.hand.add(topCard); }
            draw(player, 1);
        } else draw(player, 2);
        sound("ofiri_envoy");
    }
    void abilityInvoke(Card card, Player player, RowType rowType) {
        List<Card> options = filter(player.deck, c -> card.data().targets.contains(c.key()) || (c.groupKey().equals(card.groupKey()) && c != card && !card.data().target.isEmpty()));
        Card chosen = pickOne(player, L("Choose one card to play."), options, candidates -> candidates.isEmpty() ? null : candidates.get(0));
        if (chosen != null) { player.deck.remove(chosen); placeUnit(chosen, player, chosen.firstRow(), null); sound("invoke"); }
    }
    void abilitySummonOneOf(Card card, Player player, RowType rowType) {
        List<Card> all = new ArrayList<>(player.deck); all.addAll(player.hand); all.addAll(player.grave);
        List<Card> options = filter(all, c -> card.data().targets.contains(c.key()));
        Card chosen = pickOne(player, L("Choose one card to play."), options, this::mostValuable);
        if (chosen != null) { player.deck.remove(chosen); player.hand.remove(chosen); player.grave.remove(chosen); placeUnit(chosen, player, chosen.firstRow(), null); }
    }
    void abilityWitchHunt(Player player, RowType rowType) {
        Player opponent = player.opponent;
        Row enemyRow = opponent.row(rowType);
        if (enemyRow.shielded()) return;
        List<Card> candidates = filter(enemyRow.cards, c -> !c.hero() && c.immortalRounds == 0);
        if (candidates.isEmpty()) return;
        int lowestPower = candidates.stream().mapToInt(c -> c.power).min().getAsInt();
        List<Card> weakest = filter(candidates, c -> c.power == lowestPower);
        Card chosen = pickOne(player, L("Choose which enemy card to destroy"), weakest, c -> c.isEmpty() ? null : c.get(0));
        if (chosen != null) destroy(chosen, opponent, true);
    }
    void abilityNecrophage(Player player) {
        List<Card> options = filter(player.grave, Card::isUnit);
        List<Card> picked = pickCards(player, L("Choose up to 2 cards to take from your grave back to your deck."), options, 0, 2, true, c -> topByValue(c, 2));
        for (Card x : picked) { player.grave.remove(x); resetCard(x); insertRandomly(player.deck, x); }
    }
    void abilityGoetia(Player player) {
        Card chosen = pickOne(player, L("Choose a card to draw from your deck."), player.deck, this::mostValuable);
        if (chosen == null) return;
        player.deck.remove(chosen); player.hand.add(chosen);
        Card back = pickOne(player, L("Which card to put back into your deck?"), player.hand, c -> c.stream().min(Comparator.comparingInt(this::aiCardValue)).orElse(null));
        if (back != null) { player.hand.remove(back); insertRandomly(player.deck, back); }
    }
    void abilityZirael(Player player) {
        List<Card> five = new ArrayList<>(player.deck.subList(0, Math.min(5, player.deck.size())));
        List<Card> picked = pickCards(player, L("Choose up to 2 cards to draw and keep in your hand"), five, 0, 2, false, c -> topByValue(c, 2));
        for (Card x : picked) { player.deck.remove(x); player.hand.add(x); }
        Collections.shuffle(player.deck);
    }
    void abilityNaglfar(Player player) {
        List<Card> options = filter(player.deck, c -> c.data().name.contains("Naglfar") && c.isUnit());
        List<Card> picked = pickCards(player, L("Choose up to 2 cards to play right away."), options, 0, 2, false, c -> new ArrayList<>(c.subList(0, Math.min(2, c.size()))));
        for (Card x : picked) { player.deck.remove(x); placeUnit(x, player, x.firstRow(), null); }
    }
    void abilityBait(Player player, RowType rowType) {
        List<Card> options = filter(player.deck, c -> c.has("bond"));
        Card chosen = pickOne(player, L("Choose one card to play."), options, this::mostValuable);
        if (chosen != null) { player.deck.remove(chosen); placeUnit(chosen, player, chosen.firstRow(), null); }
    }
    void abilityClairvoyance(Player player) {
        Player opponent = player.opponent;
        int answer = pickOption(player, L("Clairvoyance Options"), Arrays.asList(L("View Deck [E]"), L("Spy Enemy [Q]")), () -> 1);
        if (answer == 0) reveal(player, L("Clairvoyance: Top 3 cards of your deck (click to close)"), new ArrayList<>(player.deck.subList(0, Math.min(3, player.deck.size()))));
        else {
            List<Card> shuffled = new ArrayList<>(opponent.hand); Collections.shuffle(shuffled);
            reveal(player, L("Clairvoyance: 3 random cards of enemy hand (click to close)"), new ArrayList<>(shuffled.subList(0, Math.min(3, shuffled.size()))));
        }
    }
    void abilityTrade(Player player) {
        Player opponent = player.opponent;
        Card chosen = pickOne(player, L("Select a card from the opponent's deck to buy."), opponent.deck, this::mostValuable);
        if (chosen == null) return;
        opponent.deck.remove(chosen); chosen.owner = player; player.hand.add(chosen);
        Card rune = first(player.deck, c -> c.key().startsWith("ofir_") && c.data().isSpecial());
        if (rune != null) { player.deck.remove(rune); rune.owner = opponent; opponent.hand.add(rune); }
        sound("trade");
    }
    void abilityRuneCall(Player player) {
        List<Card> options = filter(player.deck, c -> c.key().startsWith("ofir_") && c.data().isSpecial());
        Card chosen = pickOne(player, L("Choose 1 runestone from your deck to add to your hand."), options, c -> c.isEmpty() ? null : c.get(RANDOM.nextInt(c.size())));
        if (chosen != null) { player.deck.remove(chosen); player.hand.add(chosen); }
    }
    void abilityDoppler(Card card, Player player, RowType rowType) {
        List<Card> options = filter(player.opponent.row(rowType).cards, c -> !c.hero() && c.isUnit());
        Card chosen = pickOne(player, L("Choose an enemy unit from the opposite row to transform Doppler into."), options, c -> c.stream().max(Comparator.comparingInt(Card::basePower)).orElse(null));
        if (chosen != null) { card.baseOverride = chosen.basePower(); sound("doppler"); animate(card, "doppler"); }
    }
    void abilityAerondight(Card card, Player player) {
        List<Card> options = filter(player.rowCards(), c -> c != card && !c.hero());
        Card chosen = pickOne(player, L("Choose which card to equip with Aerondight."), options, c -> c.stream().max(Comparator.comparingInt(Card::basePower)).orElse(null));
        if (chosen == null) return;
        RowType currentRow = player.rowOf(chosen);
        if (currentRow != null) player.row(currentRow).cards.remove(chosen);
        player.row(RowType.SIEGE).cards.add(chosen); chosen.siegeMult = 3;
    }

    // MARK: Helpers

    /** Cards sorted from the most to the least valuable. */
    List<Card> byValueDescending(List<Card> cards) { List<Card> s = new ArrayList<>(cards); s.sort((a, b) -> aiCardValue(b) - aiCardValue(a)); return s; }
    /** The most valuable `count` cards. */
    List<Card> topByValue(List<Card> cards, int count) { List<Card> s = byValueDescending(cards); return new ArrayList<>(s.subList(0, Math.min(count, s.size()))); }
    /** The card with the highest current power. */
    Card strongestByPower(List<Card> cards) { return cards.stream().max(Comparator.comparingInt(c -> c.power)).orElse(null); }
}

// Leader abilities: availability, activation and the effect of every leader card.
package io.github.grechucia.gwentreimagined;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import static io.github.grechucia.gwentreimagined.GameData.L;

/** Leader ability layer of the engine. */
abstract class GameLeaders extends GameSpecials {
    GameLeaders(DeckData myDeck, DeckData opponentDeck) { super(myDeck, opponentDeck); }

    /** The most valuable card of a list, judged by the AI card value. */
    Card strongestCard(List<Card> cards) { return mostValuable(cards); }
    /** The least valuable card of a list. */
    Card weakestCard(List<Card> cards) { return cards.stream().min(Comparator.comparingInt(this::aiCardValue)).orElse(null); }
    static Card firstOf(List<Card> cards) { return cards.isEmpty() ? null : cards.get(0); }

    /** Whether a player's leader ability can still be used. */
    @Override boolean leaderAvailable(Player player) { return player.leaderUses > 0 && !PASSIVE_LEADERS.contains(player.leaderAbility()); }

    /** The human uses the leader ability. */
    void humanLeader() {
        if (busy || phase != Phase.PLAY || current != human || !leaderAvailable(human)) return;
        busy = true;
        GameThread.launch(() -> { useLeader(human); busy = false; });
    }
    /** Uses a player's leader ability and ends the turn. */
    void useLeader(Player player) {
        if (phase != Phase.PLAY || current != player || !leaderAvailable(player)) return;
        player.leaderUses -= 1;
        player.leader.flash = 1;
        sound("leader");
        note(player == human ? gameData().cardName(player.leader.data()) : L("Opponent uses leader"), player == computer ? "notif_" + player.faction() : null);
        leaderEffect(player, false);
        endTurn(player);
    }

    /** Resolves every leader ability. */
    @Override void leaderEffect(Player player, boolean free) {
        Player opponent = player.opponent;
        switch (player.leaderAbility()) {
            // Pick an Impenetrable Fog or Torrential Rain card from your deck and play it instantly.
            case "foltest_king": playWeatherFromDeck(player, filter(player.deck, c -> c.has("fog") || c.has("rain")), L("Which weather card to play? Impenetrable Fog or Torrential Rain?")); break;
            // Pick any weather card from your deck and play it instantly.
            case "eredin_king": playWeatherFromDeck(player, filter(player.deck, c -> c.data().isWeather()), L("Choose a weather card to play")); break;
            // Clear all weather effects in play.
            case "foltest_lord": case "vilgefortz_sorcerer": clearWeather(); break;
            // Doubles the strength of all your Siege units (unless a Commander's Horn is also present on that row).
            case "foltest_siegemaster": player.row(RowType.SIEGE).leaderHorn = true; sound("horn"); break;
            // Doubles the strength of all your Ranged Combat units (unless a Commander's Horn is also present on that row).
            case "francesca_beautiful": player.row(RowType.RANGED).leaderHorn = true; sound("horn"); break;
            // Destroy the enemy's strongest unit(s) of a row if that row has 10 or more strength.
            case "foltest_son": rowScorch(opponent, RowType.RANGED); break;
            case "foltest_steelforged": rowScorch(opponent, RowType.SIEGE); break;
            case "francesca_queen": case "cosimo_malaspina": rowScorch(opponent, RowType.CLOSE); break;
            // Scorch the enemy's strongest row (10 or more strength).
            case "meve_princess": case "carlo_varese": leaderMevePrincess(player); break;
            // Take a unit from the enemy discard pile, then put a card from your hand back into the deck.
            case "emhyr_imperial": leaderEmhyrImperial(player); break;
            // Choose which card the opponent must play next.
            case "emhyr_emperor": leaderEmhyrEmperor(player); break;
            // Destroy one of your units and draw a Spy/Emissary from your deck.
            case "emhyr_relentless": leaderEmhyrRelentless(player); break;
            // Revive a unit from each player's discard pile.
            case "emhyr_invader": leaderEmhyrInvader(player); break;
            // Take up to 2 of your cards from the battlefield back into your hand.
            case "eredin_commander": leaderEredinCommander(player); break;
            // Take a unit from your discard pile into your hand.
            case "eredin_bringer_of_death": {
                Card chosen = pickOne(player, L("Which card to restore from your grave?"), filter(player.grave, Card::isUnit), this::strongestCard);
                if (chosen != null) { player.grave.remove(chosen); resetCard(chosen); player.hand.add(chosen); }
                break;
            }
            // Discard 2 cards, then draw any card from your deck.
            case "eredin_destroyer": leaderEredinDestroyer(player); break;
            // Move units between rows.
            case "francesca_pureblood": case "francesca_hope": leaderFrancescaPureblood(player); break;
            // Shuffle all discard piles back into the decks.
            case "crach_an_craite": leaderCrachAnCraite(player); break;
            // Play a Mardroeme or Berserker card from your deck.
            case "birna": leaderBirna(player); break;
            // Change the base strength of a unit.
            case "holger_blakhand": leaderHolgerBlakhand(player); break;
            // Look at the top 3 units of your deck and play one.
            case "radovid_king_redania": case "nibras": leaderRadovidKingRedania(player); break;
            // Destroy the strongest card on the battlefield.
            case "radovid_mad_king": leaderRadovidMadKing(player); break;
            // Take one of your heroes from the battlefield back into your hand.
            case "radovid_strategist": {
                Card chosen = pickOne(player, L("Choose the hero to take back into your hand"), filter(player.rowCards(), Card::hero), this::strongestCard);
                if (chosen != null) { RowType rowType = player.rowOf(chosen); if (rowType != null) player.row(rowType).cards.remove(chosen); player.hand.add(chosen); }
                break;
            }
            // Play a hero from your discard pile.
            case "anna_henrietta_duchess": {
                Card chosen = pickOne(player, L("Choose the hero to play"), filter(player.grave, c -> c.hero() && c.isUnit()), this::strongestCard);
                if (chosen != null) { player.grave.remove(chosen); placeUnit(chosen, player, chosen.firstRow(), null); }
                break;
            }
            // Revert a transformed monster to its original form.
            case "anna_henrietta_ladyship": leaderAnnaHenriettaLadyship(player); break;
            // Demote an enemy hero.
            case "anna_henrietta_little_weasel": {
                Card chosen = pickOne(player, L("Choose the enemy hero to demote."), filter(opponent.rowCards(), Card::hero), this::strongestCard);
                if (chosen != null) { chosen.heroOverride = false; chosen.flash = 1; }
                break;
            }
            // Take up to 3 units that died this round back into your hand.
            case "lady_wood_whispess": leaderLadyWoodWhispess(player); break;
            // Place a curse from your deck on a row.
            case "lady_wood_weavess": leaderLadyWoodWeavess(player); break;
            // Destroy the weakest card on the battlefield.
            case "ghost_tree": leaderGhostTree(player); break;
            // Take navigator cards into your hand.
            case "auberon_king": leaderAuberonKing(player); break;
            // Play a special or weather card from your deck.
            case "winter_queen": leaderWinterQueen(player); break;
            // Sacrifice a unit to summon Koshchey.
            case "alzur_maker": leaderAlzurMaker(player); break;
            // Seize the weakest enemy close combat unit.
            case "cyprian_wiley": seize(player, RowType.CLOSE); break;
            // Destroy every spy and emissary on the battlefield.
            case "francis_bedlam":
                for (Player side : Arrays.asList(player, opponent))
                    for (Card card : side.rowCards()) if (card.has("spy") || card.has("emissary")) destroy(card, side, true);
                break;
            // Summon the Flyndr crew.
            case "gudrun_bjornsdottir": leaderGudrunBjornsdottir(player); break;
            // Lock an enemy row with Dimeritium Shackles.
            case "cyrus_hemmelfart": leaderCyrusHemmelfart(player); break;
            // Summon the Inquisitional Pyres.
            case "cyrus_hemmelfart1": {
                CardData d = gameData().cards.get("nv_inquisitional_pyres");
                if (d != null) placeUnit(new Card(d, player), player, RowType.CLOSE, null);
                break;
            }
            // Destroy the weakest enemy hero.
            case "azar_javed": {
                recalc();
                Card weakestHero = filter(opponent.rowCards(), Card::hero).stream().min(Comparator.comparingInt(c -> c.power)).orElse(null);
                if (weakestHero != null) destroy(weakestHero, opponent, true);
                break;
            }
            // Shuffle up to 2 cards of the enemy discard pile back into their deck.
            case "baal_zebuth": leaderBaalZebuth(player); break;
            // Take a random card from your discard pile and shuffle the rest into your deck.
            case "rarog": leaderRarog(player); break;
            // Take 1 of the top 3 cards of the enemy deck and discard the others.
            case "nibras_gale": leaderNibrasGale(player); break;
            default: break;
        }
        recalc();
    }

    void playWeatherFromDeck(Player player, List<Card> options, String title) {
        Card chosen = pickOne(player, title, options, GameLeaders::firstOf);
        if (chosen != null) { player.deck.remove(chosen); chosen.owner = player; playWeather(chosen, player, null); }
    }
    void leaderMevePrincess(Player player) {
        Player opponent = player.opponent;
        recalc();
        RowType strongest = null;
        for (RowType t : RowType.values()) if (opponent.row(t).total >= 10 && (strongest == null || opponent.row(t).total > opponent.row(strongest).total)) strongest = t;
        if (strongest != null) rowScorch(opponent, strongest);
    }
    void leaderEmhyrImperial(Player player) {
        Player opponent = player.opponent;
        Card chosen = pickOne(player, L("Which card to draw?"), filter(opponent.grave, c -> c.isUnit() && !c.hero()), this::strongestCard);
        if (chosen != null) { opponent.grave.remove(chosen); resetCard(chosen); chosen.owner = player; player.hand.add(chosen); }
        Card back = pickOne(player, L("Which card to put back into the deck?"), player.hand, this::weakestCard);
        if (back != null) { player.hand.remove(back); player.deck.add(back); }
    }
    void leaderEmhyrEmperor(Player player) {
        Player opponent = player.opponent;
        List<Card> shuffled = new ArrayList<>(opponent.hand); Collections.shuffle(shuffled);
        List<Card> four = new ArrayList<>(shuffled.subList(0, Math.min(4, shuffled.size())));
        Card chosen = pickOne(player, L("Which card should your opponent play on the next round?"), four, this::weakestCard);
        if (chosen != null) opponent.forcedCard = chosen;
    }
    void leaderEmhyrRelentless(Player player) {
        Card sacrificed = pickOne(player, L("Which card to destroy?"), player.rowCards(), c -> c.stream().min(Comparator.comparingInt(x -> x.power)).orElse(null));
        if (sacrificed != null) destroy(sacrificed, player, true);
        Card chosen = pickOne(player, L("Which Spy/Emissary card to draw?"), filter(player.deck, c -> c.has("spy") || c.has("emissary")), GameLeaders::firstOf);
        if (chosen != null) { player.deck.remove(chosen); player.hand.add(chosen); }
    }
    void leaderEmhyrInvader(Player player) {
        for (Player side : Arrays.asList(player, player.opponent)) {
            List<Card> options = filter(side.grave, Card::isUnit);
            Card revived = side == player ? pickOne(player, L("Which card to restore from your grave?"), options, this::strongestCard)
                                          : (options.isEmpty() ? null : options.get(RANDOM.nextInt(options.size())));
            if (revived != null) { side.grave.remove(revived); resetCard(revived); placeUnit(revived, side, revived.firstRow(), side); }
        }
    }
    void leaderEredinCommander(Player player) {
        List<Card> picked = pickCards(player, L("Choose on your battlefield two or less unit and/or hero cards and take them into your hand."), player.rowCards(), 0, 2, false,
            c -> { List<Card> f = filter(c, x -> x.has("spy") || x.has("medic")); return new ArrayList<>(f.subList(0, Math.min(2, f.size()))); });
        for (Card card : picked) { RowType r = player.rowOf(card); if (r != null) player.row(r).cards.remove(card); resetCard(card); player.hand.add(card); }
    }
    void leaderEredinDestroyer(Player player) {
        List<Card> discarded = pickCards(player, L("Which card to discard?"), player.hand, Math.min(2, player.hand.size()), 2, false,
            c -> { List<Card> s = new ArrayList<>(c); s.sort(Comparator.comparingInt(this::aiCardValue)); return new ArrayList<>(s.subList(0, Math.min(2, s.size()))); });
        for (Card card : discarded) { player.hand.remove(card); player.grave.add(card); }
        Card chosen = pickOne(player, L("Which card to draw?"), player.deck, this::strongestCard);
        if (chosen != null) { player.deck.remove(chosen); player.hand.add(chosen); }
    }
    void leaderFrancescaPureblood(Player player) {
        Player opponent = player.opponent;
        boolean pureblood = player.leaderAbility().equals("francesca_pureblood");
        Player target = pureblood ? opponent : player;
        int maxCount = pureblood ? 3 : 4;
        List<Card> picks = pickCards(player, gameData().abilityDesc(player.leaderAbility()), filter(target.rowCards(), c -> !c.hero()), 0, maxCount, false,
            c -> new ArrayList<>(c.subList(0, Math.min(maxCount, c.size()))));
        for (Card card : picks) {
            RowType from = target.rowOf(card);
            if (from == null) continue;
            List<SideRow> destinations = new ArrayList<>();
            for (RowType t : RowType.values()) if (t != from) destinations.add(new SideRow(target, t));
            SideRow destination = pickRow(player, gameData().cardName(card.data()), destinations,
                () -> target == opponent ? (opponent.weather.get(destinations.get(0).row.index()).isEmpty() ? 1 : 0) : 0);
            if (destination != null) { target.row(from).cards.remove(card); target.row(destination.row).cards.add(card); }
        }
    }
    void leaderCrachAnCraite(Player player) {
        Card keep = pickOne(player, L("Would you like to select a card to keep in your graveyard?"), player.grave, true, c -> null);
        for (Player side : Arrays.asList(player, player.opponent)) {
            for (Card card : side.grave) if (card != keep) { resetCard(card); side.deck.add(card); }
            side.grave = new ArrayList<>();
            if (keep != null && side == player) side.grave.add(keep);
            Collections.shuffle(side.deck);
        }
    }
    void leaderBirna(Player player) {
        Card chosen = pickOne(player, gameData().abilityDesc("birna"), filter(player.deck, c -> c.has("mardroeme") || c.has("berserker")), this::strongestCard);
        if (chosen == null) return;
        player.deck.remove(chosen);
        if (chosen.isUnit()) placeUnit(chosen, player, chosen.firstRow(), null); else player.hand.add(chosen);
    }
    void leaderHolgerBlakhand(Player player) {
        List<Card> options = new ArrayList<>(player.rowCards()); options.addAll(player.opponent.rowCards());
        options = filter(options, c -> !c.hero());
        Card chosen = pickOne(player, L("Change the strength of a card?"), options,
            c -> { Card own = filter(c, x -> x.owner == player).stream().min(Comparator.comparingInt(x -> x.power)).orElse(null); return own != null ? own : firstOf(c); });
        if (chosen == null) return;
        List<String> values = new ArrayList<>(); for (int i = 1; i <= 10; i++) values.add(String.valueOf(i));
        int value = pickOption(player, L("Select a new base power"), values, () -> chosen.owner == player ? 9 : 0);
        chosen.tempStrength = value + 1; chosen.flash = 1;
    }
    void leaderRadovidKingRedania(Player player) {
        List<Card> units = filter(player.deck, c -> !c.data().isSpecial() && !c.data().isWeather() && !c.has("spy") && !c.has("emissary") && !c.has("ofiri_envoy"));
        List<Card> three = new ArrayList<>(units.subList(0, Math.min(3, units.size())));
        Card chosen = pickOne(player, L("Choose a unit to play immediately"), three, this::strongestCard);
        if (chosen == null) return;
        player.deck.remove(chosen);
        if (chosen.isUnit()) placeUnit(chosen, player, chosen.firstRow(), null);
        Collections.shuffle(player.deck);
    }
    /** Destroys one of the board cards with the given power (the AI prefers enemy cards). */
    private void destroyOneWithPower(Player player, List<Card> candidates, String title) {
        Player opponent = player.opponent;
        Card chosen = pickOne(player, title, candidates, c -> { Card enemy = first(c, x -> x.owner == opponent); return enemy != null ? enemy : firstOf(c); });
        if (chosen != null) destroy(chosen, opponent.rowCards().contains(chosen) ? opponent : player, true);
    }
    void leaderRadovidMadKing(Player player) {
        recalc();
        List<Card> all = new ArrayList<>(player.rowCards()); all.addAll(player.opponent.rowCards());
        if (all.isEmpty()) return;
        int highestPower = all.stream().mapToInt(c -> c.power).max().getAsInt();
        destroyOneWithPower(player, filter(all, c -> c.power == highestPower), L("Choose the card to destroy"));
    }
    void leaderGhostTree(Player player) {
        recalc();
        List<Card> all = new ArrayList<>(player.rowCards()); all.addAll(player.opponent.rowCards());
        all = filter(all, c -> !c.hero());
        if (all.isEmpty()) return;
        int lowestPower = all.stream().mapToInt(c -> c.power).min().getAsInt();
        destroyOneWithPower(player, filter(all, c -> c.power == lowestPower), L("Choose which enemy card to destroy"));
    }
    void leaderAnnaHenriettaLadyship(Player player) {
        List<Card> options = new ArrayList<>(player.rowCards()); options.addAll(player.opponent.rowCards());
        Card chosen = pickOne(player, L("Choose the monster to revert to its primal form."), filter(options, c -> c.revertTo != null), GameLeaders::firstOf);
        if (chosen == null || chosen.revertTo == null) return;
        CardData originalData = gameData().cards.get(chosen.revertTo);
        if (originalData != null) { chosen.transform(originalData); chosen.revertTo = null; }
    }
    void leaderLadyWoodWhispess(Player player) {
        List<Card> picked = pickCards(player, gameData().abilityDesc("lady_wood_whispess"), filter(player.grave, c -> c.isUnit() && c.diedRound == round), 0, 3, false, c -> topByValue(c, 3));
        for (Card card : picked) { player.grave.remove(card); player.hand.add(card); }
    }
    void leaderLadyWoodWeavess(Player player) {
        Card curse = first(player.deck, c -> "curse".equals(c.specialKind()));
        if (curse == null) return;
        player.deck.remove(curse); curse.owner = player;
        SideRow destination = pickRow(player, gameData().abilityName("curse"), curseRows(player), () -> 3);
        if (destination != null) destination.player.row(destination.row).curse = curse;
    }
    void leaderAuberonKing(Player player) {
        List<Card> pool = new ArrayList<>(player.deck); pool.addAll(player.grave);
        List<Card> navigators = filter(pool, c -> c.has("door_o"));
        List<Card> picked = pickCards(player, gameData().abilityDesc("auberon_king"), navigators, 0, navigators.size(), false, c -> c);
        for (Card card : picked) { player.deck.remove(card); player.grave.remove(card); player.hand.add(card); }
        if (picked.isEmpty()) return;
        List<Card> back = pickCards(player, L("Which card to put back into the deck?"), filter(player.hand, c -> !picked.contains(c)), picked.size(), picked.size(), false,
            c -> { List<Card> s = new ArrayList<>(c); s.sort(Comparator.comparingInt(this::aiCardValue)); return new ArrayList<>(s.subList(0, Math.min(picked.size(), s.size()))); });
        for (Card card : back) { player.hand.remove(card); insertRandomly(player.deck, card); }
    }
    void leaderWinterQueen(Player player) {
        Card chosen = pickOne(player, L("Choose a special card to play immediatly."), filter(player.deck, c -> c.data().isSpecial() || c.data().isWeather()), GameLeaders::firstOf);
        if (chosen == null) return;
        player.deck.remove(chosen); chosen.owner = player;
        if (chosen.data().isWeather()) playWeather(chosen, player, null); else playSpecial(chosen, player, null, null, null);
    }
    void leaderAlzurMaker(Player player) {
        Card chosen = pickOne(player, gameData().abilityDesc("alzur_maker"), filter(player.rowCards(), c -> !c.hero()), c -> c.stream().min(Comparator.comparingInt(x -> x.power)).orElse(null));
        if (chosen == null) return;
        destroy(chosen, player, true);
        CardData d = gameData().cards.get("wu_koshchey");
        if (d != null) placeUnit(new Card(d, player), player, RowType.CLOSE, null);
    }
    void leaderGudrunBjornsdottir(Player player) {
        List<Card> pool = new ArrayList<>(player.deck); pool.addAll(player.hand); pool.addAll(player.grave);
        List<Card> crew = filter(pool, c -> c.key().equals("sy_flyndr_crew"));
        CardData d = gameData().cards.get("sy_flyndr_crew");
        if (crew.isEmpty() && d != null) placeUnit(new Card(d, player), player, RowType.CLOSE, null);
        for (Card member : crew) { player.deck.remove(member); player.hand.remove(member); player.grave.remove(member); resetCard(member); placeUnit(member, player, RowType.CLOSE, null); }
    }
    void leaderCyrusHemmelfart(Player player) {
        Player opponent = player.opponent;
        CardData shackles = gameData().cards.get("spe_dimeritium_shackles");
        if (shackles == null) return;
        SideRow destination = pickRow(player, gameData().abilityDesc("cyrus_hemmelfart"), sideRows(opponent, Arrays.asList(RowType.values())), () -> RANDOM.nextInt(3));
        if (destination != null) opponent.row(destination.row).lock = new Card(shackles, player);
    }
    void leaderBaalZebuth(Player player) {
        Player opponent = player.opponent;
        List<Card> picked = pickCards(player, gameData().abilityDesc("baal_zebuth"), opponent.grave, 0, 2, false, c -> topByValue(c, 2));
        for (Card card : picked) { opponent.grave.remove(card); resetCard(card); opponent.deck.add(card); }
        Collections.shuffle(opponent.deck);
    }
    void leaderRarog(Player player) {
        if (player.grave.isEmpty()) return;
        Card revived = player.grave.get(RANDOM.nextInt(player.grave.size()));
        player.grave.remove(revived); resetCard(revived); player.hand.add(revived);
        for (Card card : player.grave) { resetCard(card); player.deck.add(card); }
        player.grave.clear(); Collections.shuffle(player.deck);
    }
    void leaderNibrasGale(Player player) {
        Player opponent = player.opponent;
        List<Card> three = new ArrayList<>(opponent.deck.subList(0, Math.min(3, opponent.deck.size())));
        Card chosen = pickOne(player, L("Choose a card to add to your hand (others will be discarded)"), three, this::strongestCard);
        if (chosen == null) return;
        opponent.deck.removeAll(three);
        chosen.owner = player; player.hand.add(chosen);
        for (Card x : three) if (x != chosen) opponent.grave.add(x);
    }
}

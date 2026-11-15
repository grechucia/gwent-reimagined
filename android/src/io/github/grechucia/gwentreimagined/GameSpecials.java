// Special and weather cards, plus destruction effects (scorch, cull, row scorch, seize).
package io.github.grechucia.gwentreimagined;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import static io.github.grechucia.gwentreimagined.GameData.L;

/** Special card layer of the engine. */
abstract class GameSpecials extends GameUnits {
    GameSpecials(DeckData myDeck, DeckData opponentDeck) { super(myDeck, opponentDeck); }

    // Implemented by the leader layer.
    abstract void leaderEffect(Player player, boolean free);

    /** Resolves a special (non-weather) card. */
    @Override void playSpecial(Card card, Player player, RowType row, Player rowOwner, Card target) {
        String kind = card.specialKind() == null ? "" : card.specialKind();
        switch (kind) {
            // Horn, Mardroeme, morale, wine and shields go into a row's special slot.
            case "horn": case "mardroeme": case "morale": case "toussaint_wine": case "shield": case "shield_c": case "shield_r": case "shield_s":
                specialRowSlot(card, player, row, kind); break;
            case "door": specialDoor(card, player, row); break;
            case "decoy": specialDecoy(card, player, target); break;
            case "scorch": scorch(null); player.grave.add(card); break;
            case "cull": cull(null); player.grave.add(card); break;
            case "clear": clearWeather(); player.grave.add(card); break;
            case "lock": specialLock(card, player, row); break;
            case "curse": specialCurse(card, player, row, rowOwner); break;
            case "knockback": specialKnockback(card, player, row); break;
            case "seize": seize(player, RowType.CLOSE); player.grave.add(card); break;
            case "bank": draw(player, 1); sound("game_buy"); player.grave.add(card); break;
            case "skellige_fleet": specialSkelligeFleet(card, player); break;
            case "royal_decree": player.grave.add(card); leaderEffect(player, true); break;
            case "decoration": specialDecoration(card, player); break;
            case "chernobog": case "perun": specialChernobog(card, player, kind); break;
            case "svarog": case "morana": specialSvarog(card, player, kind); break;
            case "triglav": specialTriglav(card, player); break;
            case "veles": specialVeles(card, player); break;
            case "devana":
                for (Card unit : player.opponent.row(RowType.RANGED).cards) if (!unit.hero()) { unit.setTo = 2; unit.flash = 1; }
                player.grave.add(card); sound("rune_call"); break;
            case "zoria":
                player.opponent.weather.get(RowType.CLOSE.index()).add("frost");
                player.grave.add(card); sound("cold"); break;
            case "stribog":
                stealWeakest(player.opponent, player, RowType.RANGED, false);
                player.grave.add(card); sound("rune_call"); break;
            default: player.grave.add(card);
        }
        recalc();
    }

    /** Seize: steals the weakest enemy unit(s) of a row; they stay locked. */
    void seize(Player player, RowType rowType) {
        if (player.opponent.row(rowType).shielded()) return;
        stealWeakest(player.opponent, player, rowType, true);
        sound("seize");
    }
    /** Moves the weakest non-hero units of an enemy row to the player's row. */
    void stealWeakest(Player from, Player to, RowType rowType, boolean lockStolen) {
        List<Card> units = filter(from.row(rowType).cards, c -> !c.hero() && (!lockStolen || c.immortalRounds == 0));
        if (units.isEmpty()) return;
        int lowestPower = units.stream().mapToInt(c -> c.power).min().getAsInt();
        for (Card unit : units) {
            if (unit.power != lowestPower) continue;
            from.row(rowType).cards.remove(unit);
            unit.owner = to;
            if (lockStolen) { unit.locked = true; unit.flash = 1; events.add(GameEvent.anim(unit, "seize")); }
            to.row(rowType).cards.add(unit);
        }
    }

    /** Rows affected by a weather ability. */
    List<RowType> weatherRows(String ability, Card card) {
        switch (ability) {
            case "frost": case "spider_web": return Arrays.asList(RowType.CLOSE);
            case "fog": case "tse_tse": return Arrays.asList(RowType.RANGED);
            case "rain": case "dragon_wrath": return Arrays.asList(RowType.SIEGE);
            case "sandstorm": return Arrays.asList(RowType.CLOSE, RowType.RANGED);
            case "white_frost":
                switch (card.data().row) {
                    case "agile_cs": return Arrays.asList(RowType.CLOSE, RowType.SIEGE);
                    case "agile_rs": return Arrays.asList(RowType.RANGED, RowType.SIEGE);
                    default: return Arrays.asList(RowType.CLOSE, RowType.RANGED);
                }
            default: return new ArrayList<>();
        }
    }
    private static final Map<String, String> WEATHER_SOUNDS = new HashMap<>();
    static {
        String[][] s = {{"frost", "cold"}, {"fog", "fog"}, {"rain", "rain"}, {"storm", "rain"}, {"white_frost", "cold"}, {"sandstorm", "sandstorm"},
                        {"spider_web", "spider_web"}, {"tse_tse", "tse_tse"}, {"dragon_wrath", "dragon_wrath"}};
        for (String[] p : s) WEATHER_SOUNDS.put(p[0], p[1]);
    }
    /** Plays a weather card. */
    @Override void playWeather(Card card, Player player, RowType row) {
        String ability = card.data().abilities.isEmpty() ? "" : card.data().abilities.get(0);
        Player owner = card.owner != null ? card.owner : player;
        if (ability.equals("clear")) { clearWeather(); owner.grave.add(card); return; }
        List<RowType> rows = weatherRows(ability, card);
        if (ability.equals("storm")) {
            Player opponent = player.opponent;
            int answer = pickOption(player, L("Skellige Storm can either target Close/Ranged rows or Ranged/Siege rows, which one to target?"),
                Arrays.asList(L("Close + Ranged [E]"), L("Ranged + Siege [Q]")), () ->
                    opponent.row(RowType.CLOSE).total + opponent.row(RowType.RANGED).total - player.row(RowType.CLOSE).total - player.row(RowType.RANGED).total
                        >= opponent.row(RowType.RANGED).total + opponent.row(RowType.SIEGE).total - player.row(RowType.RANGED).total - player.row(RowType.SIEGE).total ? 0 : 1);
            rows = answer == 0 ? Arrays.asList(RowType.CLOSE, RowType.RANGED) : Arrays.asList(RowType.RANGED, RowType.SIEGE);
        }
        boolean alreadyActive = true;
        for (RowType r : rows) if (!(human.weather.get(r.index()).contains(ability) && computer.weather.get(r.index()).contains(ability))) alreadyActive = false;
        if (alreadyActive) { owner.grave.add(card); return; }
        for (Player side : players()) for (RowType r : rows) side.weather.get(r.index()).add(ability);
        weatherCards.add(card);
        String soundName = WEATHER_SOUNDS.get(ability);
        sound(soundName != null ? soundName : "rain");
        if (ability.equals("fog")) {
            for (Player side : players()) {
                List<Card> pool = new ArrayList<>(side.deck); pool.addAll(side.grave);
                for (Card x : filter(pool, c -> c.has("fog_summoning"))) {
                    side.deck.remove(x); side.grave.remove(x);
                    resetCard(x); x.owner = side; side.row(x.firstRow()).cards.add(x); x.flash = 1;
                }
            }
        }
        recalc();
    }
    /** Removes all weather. */
    void clearWeather() {
        for (Card weatherCard : weatherCards) if (weatherCard.owner != null) weatherCard.owner.grave.add(weatherCard);
        weatherCards.clear();
        for (Player side : players()) for (int i = 0; i < 3; i++) side.weather.get(i).clear();
        sound("clear");
        recalc();
    }

    /** Whether a card is protected from destruction (immortal, Sigismund, Comrade...). */
    boolean isProtected(Card card, Player side) {
        if (card.immortalRounds > 0) return true;
        if (navigatorShield && card.has("door_o") && side.leaderAbility().equals("imlerith_general")) return true;
        if (side.leaderAbility().equals("novigrad_sigismund") && !side.sigismundSaved) {
            side.sigismundSaved = true; note(L("Sigismund Dijkstra prevented the death of a friendly unit.")); return true;
        }
        if (!side.comradeUsedRound && side.rowCards().stream().anyMatch(c -> c.act("comrade"))) {
            int answer = pickOption(side, L("Do you want to save Comrade too?"), Arrays.asList(L("Save it [E]"), L("Let it die [Q]")), () -> 0);
            if (answer == 0) { side.comradeUsedRound = true; sound("comrade"); return true; }
        }
        return false;
    }
    /** Destroys a card and moves it to the graveyard (avengers summon their replacement). */
    @Override void destroy(Card card, Player side, boolean burn) {
        RowType currentRow = side.rowOf(card);
        if (currentRow == null) return;
        if (isProtected(card, side)) { card.flash = 1; animate(card, "comrade"); return; }
        if (burn) { events.add(GameEvent.burn(card)); pause(0.75); }
        side.row(currentRow).cards.remove(card);
        events.add(GameEvent.flash(card));
        resetCard(card); card.diedRound = round;
        (card.owner != null ? card.owner : side).grave.add(card);
        side.lostUnitThisTurn = true;
        boolean avenger = false; for (String a : card.data().abilities) if (a.startsWith("avenger")) avenger = true;
        if (!avenger) return;
        for (String targetKey : card.data().targets) {
            CardData cardData = gameData().cards.get(targetKey);
            if (cardData == null || !cardData.isUnit()) continue;
            Card summoned = first(side.deck, c -> c.key().equals(targetKey));
            if (summoned != null) side.deck.remove(summoned); else summoned = new Card(cardData, side);
            summoned.owner = side;
            RowType targetRow = RowType.from(cardData.row);
            side.row(targetRow != null ? targetRow : currentRow).cards.add(summoned); summoned.flash = 1;
        }
    }
    /** Units that scorch/cull can hit: non-hero units on unshielded rows. */
    private List<Object[]> boardTargets(Card except) {
        List<Object[]> all = new ArrayList<>();
        for (Player player : players()) for (RowType rowType : RowType.values()) {
            if (player.row(rowType).shielded()) continue;
            for (Card unit : player.row(rowType).cards) if (!unit.hero() && unit != except && !unit.key().equals("spe_decoy")) all.add(new Object[]{unit, player});
        }
        return all;
    }
    /** Burns the given victims after a short animation. */
    private void burnAll(List<Object[]> victims) {
        for (Object[] v : victims) events.add(GameEvent.burn((Card) v[0]));
        pause(0.75);
        for (Object[] v : victims) destroy((Card) v[0], (Player) v[1], false);
        recalc();
    }
    /** Scorch: destroys the strongest units on the whole board. */
    @Override void scorch(Card except) {
        recalc();
        List<Object[]> all = boardTargets(except);
        int maxPower = all.stream().mapToInt(v -> ((Card) v[0]).power).max().orElse(0);
        if (maxPower <= 0) return;
        sound("scorch");
        burnAll(filter(all, v -> ((Card) v[0]).power == maxPower));
    }
    /** Cull: destroys the weakest units on the whole board. */
    @Override void cull(Card except) {
        recalc();
        List<Object[]> all = boardTargets(except);
        if (all.isEmpty()) return;
        int lowestPower = all.stream().mapToInt(v -> ((Card) v[0]).power).min().getAsInt();
        sound("cull");
        burnAll(filter(all, v -> ((Card) v[0]).power == lowestPower));
    }
    /** Row scorch: destroys the strongest units of one row if the row is strong enough. */
    @Override void rowScorch(Player side, RowType rowType) {
        recalc();
        Row row = side.row(rowType);
        if (row.total < 10 || row.shielded()) return;
        List<Card> candidates = filter(row.cards, c -> !c.hero() && !c.key().equals("spe_decoy"));
        int maxPower = candidates.stream().mapToInt(c -> c.power).max().orElse(0);
        if (maxPower <= 0) return;
        sound("scorch");
        List<Object[]> victims = new ArrayList<>();
        for (Card c : candidates) if (c.power == maxPower) victims.add(new Object[]{c, side});
        burnAll(victims);
    }

    /** Rows of one side as pickable targets. */
    List<SideRow> sideRows(Player side, List<RowType> rows) { List<SideRow> r = new ArrayList<>(); for (RowType t : rows) r.add(new SideRow(side, t)); return r; }

    /** Horn, Mardroeme, morale, wine or shield placed in a row's special slot. */
    void specialRowSlot(Card card, Player player, RowType row, String kind) {
        RowType chosenRow = row;
        if (chosenRow == null) { SideRow r = pickRow(player, L("Select a card on your side of the board."), sideRows(player, validRows(card, player)), () -> 0); chosenRow = r == null ? null : r.row; }
        if (chosenRow == null) { player.grave.add(card); return; }
        player.row(chosenRow).specials.add(card);
        animate(card, kind);
        sound(kind.equals("horn") ? "horn" : (kind.equals("mardroeme") ? "mardroeme" : (kind.startsWith("shield") ? "shield" : "moral")));
        if (kind.equals("mardroeme")) berserk(player, chosenRow);
    }
    void specialDoor(Card card, Player player, RowType row) {
        RowType chosenRow = row;
        if (chosenRow == null) { SideRow r = pickRow(player, L("Select a card on your side of the board."), sideRows(player, validRows(card, player)), () -> 0); chosenRow = r == null ? null : r.row; }
        int open = 0; for (RowType t : RowType.values()) if (player.row(t).door) open++;
        if (chosenRow != null && open < maxDoors) player.row(chosenRow).door = true;
        player.grave.add(card); sound("door");
    }
    void specialDecoy(Card card, Player player, Card target) {
        RowType targetRow = target == null ? null : player.rowOf(target);
        if (targetRow != null) {
            List<Card> cards = player.row(targetRow).cards;
            cards.set(cards.indexOf(target), card);
            resetCard(target); target.owner = player; player.hand.add(target);
            sound("decoy");
        } else player.grave.add(card);
    }
    void specialLock(Card card, Player player, RowType row) {
        Player opponent = player.opponent;
        RowType chosenRow = row;
        if (chosenRow == null) { SideRow r = pickRow(player, L("Select a card on your side of the board."), sideRows(opponent, enemyRowTargets(card, player)), () -> RANDOM.nextInt(3)); chosenRow = r == null ? null : r.row; }
        if (chosenRow != null) opponent.row(chosenRow).lock = card; else player.grave.add(card);
        sound("lock");
    }
    void specialCurse(Card card, Player player, RowType row, Player rowOwner) {
        SideRow destination = rowOwner != null && row != null ? new SideRow(rowOwner, row) : null;
        if (destination == null) destination = pickRow(player, gameData().abilityName("curse"), curseRows(player), () -> 3 + RANDOM.nextInt(3));
        if (destination != null) destination.player.row(destination.row).curse = card; else player.grave.add(card);
        sound("curse");
    }
    void specialKnockback(Card card, Player player, RowType row) {
        Player opponent = player.opponent;
        RowType chosenRow = row;
        if (chosenRow == null) { SideRow r = pickRow(player, gameData().abilityName("knockback"), sideRows(opponent, Arrays.asList(RowType.CLOSE, RowType.RANGED)), () -> 0); chosenRow = r == null ? null : r.row; }
        if (chosenRow != null) {
            RowType destination = chosenRow == RowType.CLOSE ? RowType.RANGED : RowType.SIEGE;
            List<Card> moving = filter(opponent.row(chosenRow).cards, c -> !c.hero());
            opponent.row(chosenRow).cards.removeAll(moving);
            opponent.row(destination).cards.addAll(moving);
            sound("knockback");
        }
        player.grave.add(card);
    }
    void specialSkelligeFleet(Card card, Player player) {
        if (player.fleetDrawsRound < 3) {
            int answer = pickOption(player, L("Draw now or more later?"), Arrays.asList(L("Draw 1 now [E]"), L("Draw 2 later [Q]")), () -> 0);
            if (answer == 0) { draw(player, 1); player.fleetDrawsRound += 1; } else { player.fleetPending += 2; player.fleetDrawsRound += 2; }
        }
        player.row(RowType.SIEGE).specials.add(card);
    }
    void specialDecoration(Card card, Player player) {
        List<Card> options = filter(player.rowCards(), c -> !c.hero());
        Card chosen = pickOne(player, L("Choose a unit to promote to Hero."), options, this::strongestByPower);
        if (chosen != null) { chosen.heroOverride = true; chosen.flash = 1; animate(chosen, "decoration"); }
        player.grave.add(card); sound("decoration");
    }
    void specialChernobog(Card card, Player player, String kind) {
        boolean chernobog = kind.equals("chernobog");
        List<Card> options = filter(player.row(chernobog ? RowType.CLOSE : RowType.RANGED).cards, c -> !c.hero());
        Card chosen = pickOne(player, chernobog ? L("Choose which unit to double with Chernobog runestone") : L("Choose which unit to grant +5 strength with Perun runestone"), options, this::strongestByPower);
        if (chosen != null) { if (chernobog) chosen.multiplier *= 2; else chosen.bonus += 5; chosen.flash = 1; animate(chosen, kind); }
        player.grave.add(card); sound("rune_call");
    }
    void specialSvarog(Card card, Player player, String kind) {
        boolean svarog = kind.equals("svarog");
        List<Card> options = filter(player.opponent.row(svarog ? RowType.SIEGE : RowType.CLOSE).cards, c -> !c.hero());
        Card chosen = pickOne(player, svarog ? L("Choose which enemy siege unit to reduce to 1 with Svarog.") : L("Choose which enemy close unit to reduce to 1 with Morana."), options, this::strongestByPower);
        if (chosen != null) { chosen.setTo = 1; chosen.flash = 1; animate(chosen, kind); }
        player.grave.add(card); sound("rune_call");
    }
    void specialTriglav(Card card, Player player) {
        List<Card> options = filter(player.opponent.rowCards(), Card::hero);
        Card chosen = pickOne(player, L("Choose the enemy hero to weaken."), options, this::strongestByPower);
        if (chosen != null) { chosen.heroOverride = false; chosen.flash = 1; animate(chosen, "triglav"); }
        player.grave.add(card); sound("triglav");
    }
    void specialVeles(Card card, Player player) {
        Card strongest = filter(player.rowCards(), c -> !c.hero()).stream().max(Comparator.comparingInt(c -> c.power)).orElse(null);
        if (strongest != null) {
            RowType currentRow = player.rowOf(strongest);
            if (currentRow != null) player.row(currentRow).cards.remove(strongest);
            player.row(RowType.SIEGE).cards.add(strongest); strongest.siegeMult = 2; animate(strongest, "veles");
        }
        player.grave.add(card); sound("veles");
    }
}

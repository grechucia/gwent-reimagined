// Game model: board rows, card instances, players, engine events and choices.
package io.github.grechucia.gwentreimagined;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.function.Supplier;

/** Board row: close combat, ranged or siege. */
enum RowType {
    CLOSE, RANGED, SIEGE;
    /** Parses a row name from the card data. */
    static RowType from(String rowName) {
        switch (rowName) { case "close": return CLOSE; case "ranged": return RANGED; case "siege": return SIEGE; default: return null; }
    }
    int index() { return ordinal(); }
}

/** A card instance in a game, with its current power and state. */
final class Card {
    static int nextId = 1;
    final int id;
    private CardData data;
    Player owner;
    int power;
    boolean locked;
    Boolean heroOverride;
    Integer baseOverride, setTo, tempStrength;
    int multiplier = 1, bonus, siegeMult = 1, immortalRounds;
    boolean keepNextRound;
    int playedTurn = -1, diedRound = -1;
    String revertTo;
    /** Screen position and animation state used by the UI. */
    float posX, posY, lift, flash;
    boolean hasPos;

    Card(CardData d, Player owner) { id = nextId++; data = d; this.owner = owner; power = d.strength; }
    CardData data() { return data; }
    String key() { return data.key; }
    int basePower() { return baseOverride != null ? baseOverride : data.strength; }
    boolean hero() { return heroOverride != null ? heroOverride : data.isHero(); }
    /** Whether the card has an ability. */
    boolean has(String ability) { return data.abilities.contains(ability); }
    /** Whether the card's ability is active (it is not locked). */
    boolean act(String ability) { return !locked && data.abilities.contains(ability); }
    /** Cards with the same group key form bonds and musters. */
    String groupKey() { return data.target.isEmpty() ? data.key : data.target; }
    /** Witcher school ability, if any. */
    String school() {
        if (data.abilities.isEmpty()) return null;
        String last = data.abilities.get(data.abilities.size() - 1);
        return last.startsWith("witcher_") ? last : null;
    }
    boolean isUnit() { return data.isUnit(); }
    List<RowType> allowedRows() {
        switch (data.row) {
            case "close": return Arrays.asList(RowType.CLOSE);
            case "ranged": return Arrays.asList(RowType.RANGED);
            case "siege": return Arrays.asList(RowType.SIEGE);
            case "agile": case "agile_cr": case "agile_close_ranged": return Arrays.asList(RowType.CLOSE, RowType.RANGED);
            case "agile_cs": case "agile_close_siege": return Arrays.asList(RowType.CLOSE, RowType.SIEGE);
            case "agile_rs": case "agile_ranged_siege": return Arrays.asList(RowType.RANGED, RowType.SIEGE);
            case "agile_crs": case "agile_close_ranged_siege": return Arrays.asList(RowType.CLOSE, RowType.RANGED, RowType.SIEGE);
            default: return Arrays.asList(RowType.CLOSE);
        }
    }
    RowType firstRow() { return allowedRows().get(0); }
    /** Ability of a special or weather card. */
    String specialKind() { return (data.isSpecial() || data.isWeather()) && !data.abilities.isEmpty() ? data.abilities.get(0) : null; }
    /** Changes the card into another card (e.g. berserker transformation). */
    void transform(CardData into) { data = into; baseOverride = null; setTo = null; flash = 1; }
}

/** One row of a player's board side: cards, special slot and row effects. */
final class Row {
    List<Card> cards = new ArrayList<>();
    List<Card> specials = new ArrayList<>();
    int total;
    Card lock, curse, ambush;
    boolean door, leaderHorn;
    int factionMorale;
    boolean shielded() { for (Card s : specials) { String k = s.specialKind(); if (k != null && k.startsWith("shield")) return true; } return false; }
    int hornCount() {
        int n = leaderHorn ? 1 : 0;
        for (Card s : specials) if ("horn".equals(s.specialKind())) n++;
        for (Card c : cards) if (c.act("horn")) n++;
        return n;
    }
}

/** A player: deck, hand, graveyard, rows, leader, lives and pass state. */
final class Player {
    final boolean isAI;
    final DeckData deckData;
    Card leader;
    List<Card> deck = new ArrayList<>(), hand = new ArrayList<>(), grave = new ArrayList<>();
    final Row[] rows = {new Row(), new Row(), new Row()};
    final List<Set<String>> weather = Arrays.asList(new HashSet<>(), new HashSet<>(), new HashSet<>());
    int gems = 2, total, leaderUses = 1, drawOpponentLeft = 3, aamadBonus, fleetDrawsRound, fleetPending;
    boolean passed, factionUsedGame, factionUsedRound, monstersUsed, sigismundSaved, halfWeather, comradeUsedRound, lostUnitThisTurn, lastRoundWon;
    Player opponent;
    Card forcedCard;

    Player(DeckData deck, boolean isAI) {
        this.isAI = isAI; deckData = deck;
        GameData gameData = GameData.shared;
        leader = new Card(gameData.cards.get(deck.leader), null);
        leader.owner = this;
        if ("holger_blakhand".equals(leaderAbility())) leaderUses = 2;
        for (DeckEntry e : deck.cards) {
            CardData cardData = gameData.cards.get(e.key);
            if (cardData != null) for (int i = 0; i < Math.max(1, e.count); i++) this.deck.add(new Card(cardData, this));
        }
        java.util.Collections.shuffle(this.deck);
    }
    String faction() { return deckData.faction; }
    List<Card> rowCards() { List<Card> all = new ArrayList<>(); for (Row r : rows) all.addAll(r.cards); return all; }
    Row row(RowType t) { return rows[t.index()]; }
    /** The row a card currently lies in. */
    RowType rowOf(Card card) { for (RowType t : RowType.values()) if (rows[t.index()].cards.contains(card)) return t; return null; }
    String leaderAbility() { List<String> a = leader.data().abilities; return a.isEmpty() ? "" : a.get(a.size() - 1); }
    List<Row> rowList() { return Arrays.asList(rows); }
}

/** Events the engine emits for the UI: notifications, sounds and animations. */
final class GameEvent {
    enum Kind { NOTIFY, SOUND, FLASH, ANIM, BURN, COIN }
    final Kind kind; final String text, icon; final Card card; final boolean flag;
    private GameEvent(Kind kind, String text, String icon, Card card, boolean flag) { this.kind = kind; this.text = text; this.icon = icon; this.card = card; this.flag = flag; }
    static GameEvent notify(String text, String icon) { return new GameEvent(Kind.NOTIFY, text, icon, null, false); }
    static GameEvent sound(String name) { return new GameEvent(Kind.SOUND, name, null, null, false); }
    static GameEvent flash(Card c) { return new GameEvent(Kind.FLASH, null, null, c, false); }
    static GameEvent anim(Card c, String name) { return new GameEvent(Kind.ANIM, name, null, c, false); }
    static GameEvent burn(Card c) { return new GameEvent(Kind.BURN, null, null, c, false); }
    static GameEvent coin(boolean humanFirst) { return new GameEvent(Kind.COIN, null, null, null, humanFirst); }
}

/** A target row on a specific side of the board. */
final class SideRow {
    final Player player; final RowType row;
    SideRow(Player player, RowType row) { this.player = player; this.row = row; }
}

/** A decision the engine asks a player to make (cards, rows or options). */
final class Choice {
    enum Kind { CARDS, ROWS, OPTIONS, REVEAL }
    final Player player; final String title; final Kind kind; final boolean canCancel;
    final List<Card> cards; final int min, max;
    final List<SideRow> rows; final List<String> options;
    final Supplier<int[]> aiAnswer;
    Choice(Player player, String title, Kind kind, boolean canCancel, List<Card> cards, int min, int max, List<SideRow> rows, List<String> options, Supplier<int[]> aiAnswer) {
        this.player = player; this.title = title; this.kind = kind; this.canCancel = canCancel; this.cards = cards; this.min = min; this.max = max;
        this.rows = rows; this.options = options; this.aiAnswer = aiAnswer;
    }
}

/** Score of one finished round. */
final class RoundResult {
    final int human, computer; final Player winner;
    RoundResult(int human, int computer, Player winner) { this.human = human; this.computer = computer; this.winner = winner; }
}

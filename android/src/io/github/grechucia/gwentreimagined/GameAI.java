// Computer opponent: generates every legal move, scores it by simulating the board, and decides when to pass.
package io.github.grechucia.gwentreimagined;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/** A candidate AI action with its evaluated value and the point gain it produces. */
final class AIMove {
    enum Kind { CARD, LEADER, FACTION }
    final Card card; final RowType row; final Player rowOwner; final Card target; final double value; final int gain; final Kind kind;
    AIMove(Card card, RowType row, Player rowOwner, Card target, double value, int gain, Kind kind) {
        this.card = card; this.row = row; this.rowOwner = rowOwner; this.target = target; this.value = value; this.gain = gain; this.kind = kind;
    }
}

/** Heuristic weights used when valuing moves (in points of score difference). */
final class AIWeights {
    /** Extra value for every muster copy that would follow the card. */
    static final double PER_MUSTER_COPY = 2.5;
    /** Extra value for reviving a unit with a medic. */
    static final double MEDIC = 3.0;
    /** Extra value for every berserker that a card would transform. */
    static final double PER_BERSERKER = 4.0;
    /** Extra value for every berserker on a row when playing Mardroeme. */
    static final double PER_MARDROEME_BERSERKER = 5.0;
    /** Card advantage from a spy (two extra cards). */
    static final double SPY = 9.0;
    /** Small cost of playing a weather card. */
    static final double WEATHER_PENALTY = -1.5;
    /** Abilities that bring extra cards or flexibility, each worth a small bonus. */
    static final List<String> UTILITY_ABILITIES = Arrays.asList("necrophage", "goetia", "sage", "zirael", "naglfar", "bait", "invoke", "summon_one_of", "trade",
        "rune_call", "omen", "clairvoyance", "witch_hunt", "doppler", "aerondight", "wish1", "wish2", "wish3", "cull");
    static final double UTILITY_ABILITY = 2.5;
    private AIWeights() {}
}

/** Collects the candidate moves of one evaluation and turns score changes into move values. */
final class MoveCollector {
    /** Score difference (AI minus opponent) before any move. */
    final int baseScore;
    final List<AIMove> moves = new ArrayList<>();
    MoveCollector(int baseScore) { this.baseScore = baseScore; }
    /** Adds a card move. Its value is the score gain plus a bonus, minus the cost of spending the card. */
    void add(Card card, RowType row, Player owner, Card target, int scoreAfter, double bonus) {
        double cost = card.basePower() * 0.35 + (card.hero() ? 2 : 0);
        int gain = scoreAfter - baseScore;
        moves.add(new AIMove(card, row, owner, target, gain + bonus - cost, gain, AIMove.Kind.CARD));
    }
    void add(Card card, int scoreAfter, double bonus) { add(card, null, null, null, scoreAfter, bonus); }
    /** Adds a leader or faction move with an already computed value. */
    void append(AIMove move) { moves.add(move); }
}

/** AI layer of the engine. */
abstract class GameAI extends GameFactions {
    GameAI(DeckData myDeck, DeckData opponentDeck) { super(myDeck, opponentDeck); }

    /** Snapshot of the board used to try a move and roll it back. */
    private static final class Snapshot {
        final List<List<Card>> rows = new ArrayList<>(), specials = new ArrayList<>();
        final List<List<Set<String>>> weather = new ArrayList<>();
        final List<Boolean> horns = new ArrayList<>();
    }
    private List<Row> allRows() { List<Row> r = new ArrayList<>(human.rowList()); r.addAll(computer.rowList()); return r; }
    /** Captures the current board state. */
    private Snapshot snap() {
        Snapshot s = new Snapshot();
        for (Row row : allRows()) { s.rows.add(new ArrayList<>(row.cards)); s.specials.add(new ArrayList<>(row.specials)); s.horns.add(row.leaderHorn); }
        for (Player p : players()) { List<Set<String>> w = new ArrayList<>(); for (Set<String> set : p.weather) w.add(new HashSet<>(set)); s.weather.add(w); }
        return s;
    }
    /** Restores a board state captured with snap(). */
    private void restore(Snapshot s) {
        List<Row> rows = allRows();
        for (int i = 0; i < rows.size(); i++) { rows.get(i).cards = s.rows.get(i); rows.get(i).specials = s.specials.get(i); rows.get(i).leaderHorn = s.horns.get(i); }
        List<Player> players = players();
        for (int p = 0; p < 2; p++) for (int i = 0; i < 3; i++) { players.get(p).weather.get(i).clear(); players.get(p).weather.get(i).addAll(s.weather.get(p).get(i)); }
    }
    /** Score difference for `player` after `apply` is executed; the board is restored afterwards. */
    int diffAfter(Player player, Runnable apply) {
        Snapshot snapshot = snap();
        apply.run(); recalc();
        int scoreAfterMove = player.total - player.opponent.total;
        restore(snapshot); recalc();
        return scoreAfterMove;
    }
    /** Simulates removing the strongest non-hero units from the given rows (scorch-like effects). */
    void killMax(List<Card> cards, List<Row> rows) {
        int highestPower = cards.stream().filter(c -> !c.hero()).mapToInt(c -> c.power).max().orElse(0);
        if (highestPower <= 0) return;
        for (Row row : rows) if (!row.shielded()) row.cards.removeIf(c -> !c.hero() && c.power == highestPower && c.immortalRounds == 0);
    }
    private List<Row> bothSides(Player a, Player b) { List<Row> r = new ArrayList<>(a.rowList()); r.addAll(b.rowList()); return r; }
    private List<Card> bothSideCards(Player a, Player b) { List<Card> r = new ArrayList<>(a.rowCards()); r.addAll(b.rowCards()); return r; }
    private void clearAllWeather() { for (Player side : players()) for (int i = 0; i < 3; i++) side.weather.get(i).clear(); }

    /** Lists every possible move for the AI player together with its estimated value. */
    List<AIMove> aiMoves(Player player) {
        recalc();
        MoveCollector collector = new MoveCollector(player.total - player.opponent.total);
        List<Card> playable = player.forcedCard != null ? filter(player.hand, c -> c == player.forcedCard) : new ArrayList<>(player.hand);
        for (Card card : playable) {
            if (card.isUnit()) evaluateUnit(card, player, collector);
            else if (card.data().isWeather()) evaluateWeather(card, player, collector);
            else evaluateSpecial(card, player, collector);
        }
        if (leaderAvailable(player) && player.forcedCard == null) evaluateLeader(player, collector);
        String faction = factionActive(player);
        if (faction != null && player.forcedCard == null) evaluateFaction(faction, player, collector);
        return collector.moves;
    }

    /** Unit card: tries every row it can go to and simulates its main abilities (muster, medic, scorch, berserker). */
    void evaluateUnit(Card card, Player player, MoveCollector collector) {
        Player enemy = player.opponent;
        List<RowType> rows = card.has("ambush") ? Arrays.asList(RowType.CLOSE) : card.allowedRows();
        boolean isSpy = card.has("spy") || card.has("emissary") || card.has("ofiri_envoy");
        Player side = isSpy ? enemy : player;
        for (RowType rowType : rows) {
            double[] bonus = {0};
            int scoreAfter = diffAfter(player, () -> {
                side.row(rowType).cards.add(card);
                if (card.has("muster")) {
                    List<Card> pool = new ArrayList<>(player.hand); pool.addAll(player.deck);
                    List<Card> copies = filter(pool, c -> c != card && c.groupKey().equals(card.groupKey()) && c.isUnit());
                    for (Card copy : copies) {
                        RowType fixed = RowType.from(copy.data().row);
                        player.row(card.data().row.startsWith("agile") ? rowType : (fixed != null ? fixed : rowType)).cards.add(copy);
                    }
                    bonus[0] += copies.size() * AIWeights.PER_MUSTER_COPY;
                }
                if (card.has("medic")) {
                    Card revived = filter(player.grave, c -> c.isUnit() && !c.hero()).stream().max(Comparator.comparingInt(this::aiCardValue)).orElse(null);
                    if (revived != null) { player.row(revived.firstRow()).cards.add(revived); bonus[0] += AIWeights.MEDIC; }
                }
                recalc();
                for (String ability : card.data().abilities) {
                    if (!ability.startsWith("scorch_")) continue;
                    Row targetRow = enemy.row(scorchRow(ability));
                    if (targetRow.total >= 10) killMax(targetRow.cards, Arrays.asList(targetRow));
                }
                if (card.has("scorch")) killMax(filter(bothSideCards(player, enemy), c -> c != card), bothSides(player, enemy));
                boolean triggersBerserkers = card.has("mardroeme") || (card.has("berserker") && side.row(rowType).specials.stream().anyMatch(s -> "mardroeme".equals(s.specialKind())));
                if (triggersBerserkers) bonus[0] += side.row(rowType).cards.stream().filter(c -> c.has("berserker")).count() * AIWeights.PER_BERSERKER;
            });
            if (isSpy) bonus[0] += AIWeights.SPY;
            for (String ability : AIWeights.UTILITY_ABILITIES) if (card.has(ability)) bonus[0] += AIWeights.UTILITY_ABILITY;
            collector.add(card, rowType, null, null, scoreAfter, bonus[0]);
        }
    }

    /** Weather card: simulates the weather on the rows it affects (storm can hit two different row pairs). */
    void evaluateWeather(Card card, Player player, MoveCollector collector) {
        String ability = card.data().abilities.isEmpty() ? "" : card.data().abilities.get(0);
        List<List<RowType>> variants = ability.equals("storm")
            ? Arrays.asList(Arrays.asList(RowType.CLOSE, RowType.RANGED), Arrays.asList(RowType.RANGED, RowType.SIEGE))
            : Arrays.asList(weatherRows(ability, card));
        int bestScore = Integer.MIN_VALUE;
        for (List<RowType> affectedRows : variants) {
            int scoreAfter = diffAfter(player, () -> {
                for (Player side : players()) {
                    if (ability.equals("clear")) for (int i = 0; i < 3; i++) side.weather.get(i).clear();
                    else for (RowType rowType : affectedRows) side.weather.get(rowType.index()).add(ability);
                }
            });
            bestScore = Math.max(bestScore, scoreAfter);
        }
        collector.add(card, bestScore, AIWeights.WEATHER_PENALTY);
    }

    /** Special (non-weather) card: simulates or estimates the effect of each special kind. */
    void evaluateSpecial(Card card, Player player, MoveCollector collector) {
        Player enemy = player.opponent;
        int base = collector.baseScore;
        String kind = card.specialKind() == null ? "" : card.specialKind();
        switch (kind) {
            case "horn": case "morale": case "toussaint_wine": case "mardroeme":
                for (RowType rowType : validRows(card, player)) {
                    int scoreAfter = diffAfter(player, () -> player.row(rowType).specials.add(card));
                    double berserkerBonus = kind.equals("mardroeme") ? player.row(rowType).cards.stream().filter(c -> c.has("berserker")).count() * AIWeights.PER_MARDROEME_BERSERKER : 0;
                    collector.add(card, rowType, player, null, scoreAfter, berserkerBonus - 2.5);
                }
                break;
            case "shield": case "shield_c": case "shield_r": case "shield_s":
                for (RowType rowType : validRows(card, player)) {
                    boolean threatened = enemy.hand.stream().anyMatch(c -> c.has("scorch") || "scorch".equals(c.specialKind())) || player.row(rowType).total >= 10;
                    collector.add(card, rowType, player, null, base, threatened ? player.row(rowType).total * 0.25 : -3);
                }
                break;
            case "lock": {
                List<RowType> rows = enemyRowTargets(card, player);
                if (!rows.isEmpty()) collector.add(card, rows.get(0), enemy, null, base, enemy.hand.size() > 3 ? 2 : -2);
                break;
            }
            case "curse": collector.add(card, RowType.CLOSE, enemy, null, base, enemy.hand.size() > 3 ? 2.5 : -2); break;
            case "knockback":
                for (RowType rowType : Arrays.asList(RowType.CLOSE, RowType.RANGED)) {
                    int scoreAfter = diffAfter(player, () -> {
                        RowType destination = rowType == RowType.CLOSE ? RowType.RANGED : RowType.SIEGE;
                        List<Card> pushed = filter(enemy.row(rowType).cards, c -> !c.hero());
                        enemy.row(rowType).cards.removeAll(pushed);
                        enemy.row(destination).cards.addAll(pushed);
                    });
                    collector.add(card, rowType, enemy, null, scoreAfter, -1);
                }
                break;
            case "seize": collector.add(card, diffAfter(player, () -> simulateSteal(enemy.row(RowType.CLOSE), player.row(RowType.CLOSE))), 0); break;
            case "stribog": collector.add(card, diffAfter(player, () -> simulateSteal(enemy.row(RowType.RANGED), player.row(RowType.RANGED))), 0); break;
            case "scorch": collector.add(card, diffAfter(player, () -> { recalc(); killMax(bothSideCards(player, enemy), bothSides(player, enemy)); }), -2); break;
            case "cull": {
                int scoreAfter = diffAfter(player, () -> {
                    recalc();
                    List<Card> units = filter(bothSideCards(player, enemy), c -> !c.hero());
                    if (units.isEmpty()) return;
                    int lowestPower = units.stream().mapToInt(c -> c.power).min().getAsInt();
                    for (Row row : bothSides(player, enemy)) if (!row.shielded()) row.cards.removeIf(c -> !c.hero() && c.power == lowestPower);
                });
                collector.add(card, scoreAfter, -1);
                break;
            }
            case "clear": collector.add(card, diffAfter(player, this::clearAllWeather), -1); break;
            case "decoy":
                for (Card target : decoyTargets(player)) {
                    int scoreAfter = diffAfter(player, () -> { RowType targetRow = player.rowOf(target); if (targetRow != null) player.row(targetRow).cards.remove(target); });
                    double bonus = target.has("spy") ? AIWeights.SPY : (target.has("medic") ? 4 : 0.5);
                    collector.add(card, null, null, target, scoreAfter, bonus);
                }
                break;
            case "bank": case "skellige_fleet": collector.add(card, base, 5); break;
            case "decoration": if (player.rowCards().stream().anyMatch(c -> !c.hero())) collector.add(card, base, 3); break;
            case "royal_decree": if (!PASSIVE_LEADERS.contains(player.leaderAbility())) collector.add(card, base, 3); break;
            case "door":
                if (player.deck.stream().anyMatch(Card::isUnit)) { List<RowType> rows = validRows(card, player); collector.add(card, rows.isEmpty() ? null : rows.get(0), player, null, base, 3); }
                break;
            case "chernobog": { Card strongest = strongestNonHero(player.row(RowType.CLOSE).cards); if (strongest != null) collector.add(card, base + strongest.power, -1); break; }
            case "perun": if (player.row(RowType.RANGED).cards.stream().anyMatch(c -> !c.hero())) collector.add(card, base + 5, -1); break;
            case "svarog": case "morana": {
                Card strongest = strongestNonHero(enemy.row(kind.equals("svarog") ? RowType.SIEGE : RowType.CLOSE).cards);
                if (strongest != null) collector.add(card, base + strongest.power - 1, -1);
                break;
            }
            case "triglav": if (enemy.rowCards().stream().anyMatch(Card::hero)) collector.add(card, base, 2); break;
            case "veles": { Card strongest = strongestNonHero(player.rowCards()); if (strongest != null) collector.add(card, base + strongest.power, -1); break; }
            case "devana": {
                int loss = enemy.row(RowType.RANGED).cards.stream().filter(c -> !c.hero()).mapToInt(c -> Math.max(0, c.power - 2)).sum();
                collector.add(card, base + loss, -1);
                break;
            }
            case "zoria": collector.add(card, diffAfter(player, () -> enemy.weather.get(0).add("frost")), -1); break;
            default: break;
        }
    }

    /** Leader ability: simulated when its effect is simple, otherwise valued higher in later rounds. */
    void evaluateLeader(Player player, MoveCollector collector) {
        Player enemy = player.opponent;
        String ability = player.leaderAbility();
        Integer scoreAfter;
        switch (ability) {
            case "foltest_siegemaster": scoreAfter = diffAfter(player, () -> player.row(RowType.SIEGE).leaderHorn = true); break;
            case "francesca_beautiful": scoreAfter = diffAfter(player, () -> player.row(RowType.RANGED).leaderHorn = true); break;
            case "foltest_lord": case "vilgefortz_sorcerer": scoreAfter = diffAfter(player, this::clearAllWeather); break;
            case "foltest_son": case "foltest_steelforged": case "francesca_queen": case "cosimo_malaspina": {
                RowType rowType = ability.equals("foltest_son") ? RowType.RANGED : (ability.equals("foltest_steelforged") ? RowType.SIEGE : RowType.CLOSE);
                Row targetRow = enemy.row(rowType);
                scoreAfter = targetRow.total >= 10 ? diffAfter(player, () -> killMax(targetRow.cards, Arrays.asList(targetRow))) : collector.baseScore - 5;
                break;
            }
            default: scoreAfter = null;
        }
        if (scoreAfter != null) {
            int gain = scoreAfter - collector.baseScore;
            collector.append(new AIMove(null, null, null, null, gain - 2, gain, AIMove.Kind.LEADER));
        } else {
            double value = 3.0 + round * 1.5 - player.hand.size() * 0.3;
            collector.append(new AIMove(null, null, null, null, value, 0, AIMove.Kind.LEADER));
        }
    }

    /** Faction ability that can be activated during the turn. */
    void evaluateFaction(String ability, Player player, MoveCollector collector) {
        switch (ability) {
            case "morale": {
                RowType fullest = RowType.CLOSE;
                for (RowType t : RowType.values()) if (player.row(t).cards.size() > player.row(fullest).cards.size()) fullest = t;
                final RowType fullestRow = fullest;
                int gain = diffAfter(player, () -> player.row(fullestRow).factionMorale += 1) - collector.baseScore;
                collector.append(new AIMove(null, null, null, null, gain - 1, gain, AIMove.Kind.FACTION));
                break;
            }
            case "weather": collector.append(new AIMove(null, null, null, null, 2, 0, AIMove.Kind.FACTION)); break;
            case "transform": collector.append(new AIMove(null, null, null, null, 4, 3, AIMove.Kind.FACTION)); break;
            default: break;
        }
    }

    /** Moves the weakest non-hero units of one row to another (seize-like effects), used in simulations. */
    void simulateSteal(Row source, Row destination) {
        List<Card> units = filter(source.cards, c -> !c.hero());
        if (units.isEmpty()) return;
        int lowestPower = units.stream().mapToInt(c -> c.power).min().getAsInt();
        for (Card unit : units) if (unit.power == lowestPower) { source.cards.remove(unit); destination.cards.add(unit); }
    }
    /** The strongest non-hero card of a list. */
    Card strongestNonHero(List<Card> cards) { return cards.stream().filter(c -> !c.hero()).max(Comparator.comparingInt(c -> c.power)).orElse(null); }

    /** Chooses the move to play, or null to pass, using round state and the configured difficulty. */
    AIMove aiDecide(Player requestedPlayer) {
        Player player = requestedPlayer != null ? requestedPlayer : computer, foe = player.opponent;
        recalc();
        // Nothing left to play: pass.
        if (player.hand.isEmpty() && !leaderAvailable(player)) return null;
        // Positive lead means the AI is ahead in the current round.
        int lead = player.total - foe.total;
        List<AIMove> moves = aiMoves(player);
        moves.sort((a, b) -> Double.compare(b.value, a.value));
        if (moves.isEmpty()) return null;
        AIMove best = moves.get(0);
        // A card that must be played this turn always wins.
        if (player.forcedCard != null) for (AIMove m : moves) if (m.card == player.forcedCard) return m;
        // Easy and normal opponents sometimes deviate from the best move.
        if (player == computer && aiLevel < 2) { AIMove weaker = weakenedChoice(moves, player, foe, lead); if (weaker != null) return weaker; }
        // With one life left the AI cannot afford to lose this round.
        boolean mustWin = player.gems == 1;
        // The opponent passed: play the cheapest card that takes the lead, or pass if already ahead.
        if (foe.passed) {
            if (lead > 0) return null;
            AIMove winning = moves.stream().filter(m -> lead + m.gain > 0).min(Comparator.comparingInt(m -> m.card != null ? m.card.basePower() : 0)).orElse(null);
            if (winning != null) return winning;
            int potential = moves.stream().mapToInt(m -> Math.max(0, m.gain)).sum();
            if (mustWin || lead + potential > 0) return best;
            return null;
        }
        // Comfortable lead: pass to save cards.
        if (!mustWin && lead >= 14 && player.hand.size() <= foe.hand.size()) return null;
        // Hopeless first round: pass and keep cards for later rounds.
        if (!mustWin && round == 1 && foe.gems == 2 && lead < -25 && player.hand.size() < foe.hand.size()) return null;
        // Every move would cost more than it gains while ahead: pass.
        if (best.value < -6 && !mustWin && lead > 0) return null;
        return best;
    }

    /** Easier opponents sometimes play a weaker move instead of the best one, and pass less cleverly. */
    AIMove weakenedChoice(List<AIMove> moves, Player player, Player foe, int lead) {
        double mistake = aiLevel == 0 ? 0.5 : 0.2;
        if (moves.size() <= 1 || RANDOM.nextDouble() >= mistake) return null;
        if (aiLevel == 0 && !foe.passed && lead > 0 && player.gems == 2 && RANDOM.nextDouble() < 0.3) return null;
        int poolSize = aiLevel == 0 ? Math.max(2, moves.size() / 2) : Math.min(3, moves.size());
        List<AIMove> pool = moves.subList(1, Math.min(poolSize, moves.size()));
        return pool.isEmpty() ? null : pool.get(RANDOM.nextInt(pool.size()));
    }

    /** Performs the AI player's turn. */
    void aiTurn(Player player) {
        if (phase != Phase.PLAY || current != player || busy) return;
        busy = true;
        try {
            aiPlayer = player;
            AIMove move = aiDecide(player);
            String faction = factionActive(player);
            if (faction != null && faction.startsWith("skip") && (move != null ? move.value : -10) < 0 && !player.opponent.passed) { useFaction(player); return; }
            if (move == null) { pass(player); return; }
            switch (move.kind) {
                case LEADER: useLeader(player); break;
                case FACTION: useFaction(player); break;
                case CARD: if (move.card != null) play(move.card, player, move.row, move.rowOwner, move.target); else pass(player); break;
            }
        } finally { busy = false; }
    }
}

/** The complete game: the core rules plus every ability layer and the AI. */
final class Game extends GameAI {
    Game(DeckData myDeck, DeckData opponentDeck) { super(myDeck, opponentDeck); setUp(); }
}

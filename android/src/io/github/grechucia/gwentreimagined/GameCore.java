// Game rules: two players, redraw, rounds, turns, placing units and asking players to choose.
package io.github.grechucia.gwentreimagined;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Random;
import java.util.Set;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.BlockingQueue;
import java.util.function.Function;
import java.util.function.Supplier;
import static io.github.grechucia.gwentreimagined.GameData.L;

/**
 * Core of the rules engine. Methods that wait (pause, choose) must run on a game task started with GameThread.launch;
 * the ability layers (scoring, unit/special/leader/faction abilities, AI) extend this class.
 */
abstract class GameCore {
    enum Phase { REDRAW, PLAY, ROUND_END, OVER }
    static final Random RANDOM = new Random();

    final Player human, computer;
    final List<Card> weatherCards = new ArrayList<>();
    Player current;
    int round = 1, turn;
    /** AI strength for the computer opponent: 0 = easy, 1 = normal, 2 = hard. */
    int aiLevel = 1;
    final List<RoundResult> history = new ArrayList<>();
    Phase phase = Phase.REDRAW;
    final List<GameEvent> events = new ArrayList<>();
    /** Choice the human currently has to make (shown by the UI). */
    Choice choice;
    private BlockingQueue<Object[]> choiceAnswer;
    boolean busy, autoHuman, showChoices, paused;
    int redrawsLeft = 2;
    Player lastRoundWinner, winner, aiPlayer;
    double spyMult = 1;
    int whorshipMult = 1, medicPicks = 1, maxDoors = 1;
    boolean navigatorShield;
    GameData gameData() { return GameData.shared; }

    // Layers implemented by subclasses.
    abstract void recalc();
    abstract void unitAbilities(Card card, Player player, Player side, RowType row);
    abstract void playWeather(Card card, Player player, RowType row);
    abstract void playSpecial(Card card, Player player, RowType row, Player rowOwner, Card target);
    abstract boolean leaderAvailable(Player player);
    abstract String factionActive(Player player);

    GameCore(DeckData myDeck, DeckData opponentDeck) {
        human = new Player(myDeck, false);
        computer = new Player(opponentDeck, true);
        human.opponent = computer; computer.opponent = human;
        current = human;
    }
    /** Second construction step (needs the subclasses to be ready). */
    void setUp() {
        for (Player player : players()) applyPassiveLeader(player);
        for (Player player : players()) {
            if (player.faction().equals("syndicate")) summonToBoard(player, "sy_sigi_reuven");
            if (player.leaderAbility().equals("ofir_aamad_crown")) summonToBoard(player, "ofir_ofieri_prince");
            int hand = 10 + (player.faction().equals("wild_hunt") ? 1 : 0) + (player.leaderAbility().equals("francesca_daisy") ? 3 : 0);
            draw(player, hand, true);
        }
        redrawsLeft = redrawCount(human);
        aiRedraw(computer);
        recalc();
    }
    List<Player> players() { return Arrays.asList(human, computer); }

    /** How many cards a player may redraw at the start. */
    int redrawCount(Player p) { return 2 + (p.faction().equals("toussaint") ? 1 : 0) + (p.faction().equals("novigrad") ? 1 : 0); }
    /** Applies leader abilities that work passively. */
    void applyPassiveLeader(Player player) {
        switch (player.leaderAbility()) {
            case "eredin_treacherous": spyMult *= 2; break;
            case "vilgefortz_magician_kovir": spyMult *= 0.5; break;
            case "zerrikanterment": whorshipMult = 2; break;
            case "meve_white_queen": medicPicks = 2; break;
            case "imlerith_general": navigatorShield = true; break;
            case "caranthir_navigator": maxDoors = 2; break;
            default: break;
        }
    }
    /** Puts a card with the given key directly on the board. */
    void summonToBoard(Player player, String key) {
        Card card = null;
        for (int i = 0; i < player.deck.size(); i++) if (player.deck.get(i).key().equals(key)) { card = player.deck.remove(i); break; }
        if (card == null) { CardData d = gameData().cards.get(key); if (d == null) return; card = new Card(d, player); }
        card.owner = player;
        player.row(card.firstRow()).cards.add(card);
    }

    // MARK: Choices

    /** Asks a player to choose; the AI answers automatically, the human through the UI. Returns null when cancelled. */
    int[] choose(Choice request) {
        if (autoHuman && showChoices && !request.player.isAI) {
            choice = request; pause(1.2); choice = null;
            return request.aiAnswer.get();
        }
        if (request.player.isAI || autoHuman) return request.aiAnswer.get();
        BlockingQueue<Object[]> answer = new ArrayBlockingQueue<>(1);
        choiceAnswer = answer;
        choice = request;
        int holds = GameThread.releaseAll();
        Object[] result;
        try { result = answer.take(); } catch (InterruptedException e) { result = new Object[]{null}; }
        GameThread.reacquire(holds);
        return (int[]) result[0];
    }
    /** Called by the UI with the human's answer to the pending choice. */
    void resolveChoice(int[] answer) {
        BlockingQueue<Object[]> queue = choiceAnswer;
        choice = null; choiceAnswer = null;
        if (queue != null) queue.offer(new Object[]{answer});
    }
    boolean waitingForChoice() { return choiceAnswer != null; }

    /** Asks a player to pick several cards. */
    List<Card> pickCards(Player player, String title, List<Card> cards, int min, int max, boolean cancel, Function<List<Card>, List<Card>> ai) {
        if (cards.isEmpty()) return new ArrayList<>();
        final List<Card> options = new ArrayList<>(cards);
        int[] selection = choose(new Choice(player, title, Choice.Kind.CARDS, cancel, options, min, Math.min(max, options.size()), null, null, () -> {
            List<Card> picked = ai.apply(options);
            return picked.stream().mapToInt(options::indexOf).filter(i -> i >= 0).toArray();
        }));
        List<Card> result = new ArrayList<>();
        if (selection != null) for (int i : selection) if (i >= 0 && i < options.size()) result.add(options.get(i));
        return result;
    }
    /** Asks a player to pick one card. */
    Card pickOne(Player player, String title, List<Card> cards, boolean cancel, Function<List<Card>, Card> ai) {
        List<Card> r = pickCards(player, title, cards, 1, 1, cancel, candidates -> { Card c = ai.apply(candidates); return c == null ? new ArrayList<>() : new ArrayList<>(Collections.singletonList(c)); });
        return r.isEmpty() ? null : r.get(0);
    }
    Card pickOne(Player player, String title, List<Card> cards, Function<List<Card>, Card> ai) { return pickOne(player, title, cards, false, ai); }
    /** Asks a player to pick a row. */
    SideRow pickRow(Player player, String title, List<SideRow> rows, Supplier<Integer> ai) {
        if (rows.isEmpty()) return null;
        if (rows.size() == 1) return rows.get(0);
        int[] r = choose(new Choice(player, title, Choice.Kind.ROWS, false, null, 0, 0, rows, null, () -> new int[]{ai.get()}));
        if (r == null || r.length == 0 || r[0] >= rows.size() || r[0] < 0) return rows.get(0);
        return rows.get(r[0]);
    }
    /** Asks a player to pick one of several options. */
    int pickOption(Player player, String title, List<String> options, Supplier<Integer> ai) {
        int[] r = choose(new Choice(player, title, Choice.Kind.OPTIONS, false, null, 0, 0, null, options, () -> new int[]{ai.get()}));
        return r == null || r.length == 0 ? 0 : r[0];
    }
    /** Shows cards to the player (e.g. the opponent's hand). */
    void reveal(Player player, String title, List<Card> cards) {
        if (cards.isEmpty()) return;
        choose(new Choice(player, title, Choice.Kind.REVEAL, true, new ArrayList<>(cards), 0, 0, null, null, () -> new int[0]));
    }

    /** Waits so the UI can show animations; also waits while the game is paused. */
    void pause(double seconds) {
        GameThread.sleep(autoHuman ? seconds * 0.3 : seconds);
        while (paused) GameThread.sleep(0.1);
    }

    static final Set<String> ANIM_ICONS = new HashSet<>(Arrays.asList("adaptive", "aerondight", "ambush", "bond", "chernobog", "clairvoyance", "clear", "comrade", "cull", "curse", "decoration",
        "doppler", "emissary", "goetia", "horn", "immortal", "invoke", "knockback", "lock", "mardroeme", "medic", "monster_toussaint", "morale", "morana",
        "muster", "necrophage", "ofiri_envoy", "omen", "perun", "resilience", "rune_call", "seize", "shield", "soothsayer", "spy", "stribog",
        "summon_one_of", "svarog", "trade", "triglav", "veles"));
    /** Animation name used for an ability. */
    static String animName(String ability) {
        if (ability.equals("toussaint_wine")) return "wine";
        if (ability.startsWith("wish")) return "wish";
        if (ability.equals("witch_hunt")) return "execute";
        if (ability.startsWith("shield")) return "shield";
        return ANIM_ICONS.contains(ability) ? ability : null;
    }
    /** Plays a card animation, optionally waiting for it. */
    void animate(Card card, String name, boolean wait) {
        String animation = animName(name);
        if (animation == null && name.equals("hero")) animation = "hero";
        if (animation == null) return;
        events.add(GameEvent.anim(card, animation));
        if (wait) pause(0.7);
    }
    void animate(Card card, String name) { animate(card, name, true); }
    /** Shows a notification banner. */
    void note(String text, String icon) { events.add(GameEvent.notify(text, icon)); }
    void note(String text) { note(text, null); }
    /** Plays a sound effect. */
    void sound(String name) { events.add(GameEvent.sound(name)); }

    // MARK: Drawing and redraw

    /** Draws cards from the deck into the hand. */
    void draw(Player player, int count, boolean silent) {
        for (int i = 0; i < count; i++) {
            if (player.deck.isEmpty()) return;
            player.hand.add(player.deck.remove(0));
            if (player.leaderAbility().equals("ofir_aamad") && phase == Phase.PLAY) player.aamadBonus += 1;
        }
        if (!silent) recalc();
    }
    void draw(Player player, int count) { draw(player, count, false); }
    /** Inserts a card at a random position of a deck. */
    static void insertRandomly(List<Card> deck, Card card) { deck.add(RANDOM.nextInt(deck.size() + 1), card); }
    /** Swaps a card in hand for the top card of the deck (redraw phase). */
    Card redraw(Card card) {
        int i = human.hand.indexOf(card);
        if (phase != Phase.REDRAW || redrawsLeft <= 0 || i < 0 || human.deck.isEmpty()) return null;
        Card drawn = human.deck.remove(0);
        human.hand.set(i, drawn);
        insertRandomly(human.deck, card);
        redrawsLeft -= 1;
        sound("redraw");
        return drawn;
    }
    /** AI decision for the redraw phase. */
    void aiRedraw(Player player) {
        if (player.leaderAbility().equals("francesca_daisy")) {
            for (int k = 0; k < 2; k++) {
                Card worst = player.hand.stream().min(Comparator.comparingInt(this::aiCardValue)).orElse(null);
                if (worst != null) { player.hand.remove(worst); insertRandomly(player.deck, worst); }
            }
        }
        for (int k = 0; k < redrawCount(player); k++) {
            Card worst = player.hand.stream().filter(c -> c.isUnit() && !c.hero() && !c.has("spy") && !c.has("medic") && !c.has("muster") && !c.has("bond"))
                .min(Comparator.comparingInt(Card::basePower)).orElse(null);
            if (worst == null || worst.basePower() > 3 || player.deck.isEmpty()) return;
            int i = player.hand.indexOf(worst);
            player.hand.set(i, player.deck.remove(0));
            insertRandomly(player.deck, worst);
        }
    }
    /** Handles the Daisy of the Valley ability after the redraw. */
    void daisyReturn() {
        if (!human.leaderAbility().equals("francesca_daisy")) return;
        List<Card> back = pickCards(human, L("Choose 2 cards to put back into your deck"), human.hand, 2, 2, false,
            candidates -> { List<Card> s = new ArrayList<>(candidates); s.sort(Comparator.comparingInt(this::aiCardValue)); return new ArrayList<>(s.subList(0, Math.min(2, s.size()))); });
        for (Card returned : back) { human.hand.remove(returned); insertRandomly(human.deck, returned); }
    }
    /** Ends the redraw phase, tosses the coin and starts the first round. */
    void finishRedraw() {
        if (phase != Phase.REDRAW || busy) return;
        busy = true;
        GameThread.launch(() -> {
            daisyReturn();
            phase = Phase.PLAY;
            current = RANDOM.nextBoolean() ? human : computer;
            sound("coin");
            events.add(GameEvent.coin(current == human));
            pause(1.6);
            note(current == human ? L("You will go first") : L("Your opponent will go first"), current == human ? "notif_me_coin" : "notif_op_coin");
            startRound();
            busy = false;
        });
    }

    // MARK: Rounds and turns

    /** Starts a round: faction bonuses, who goes first, turn loop. */
    void startRound() {
        turn += 1;
        // Reset per-round flags of both players.
        for (Player p : players()) { p.aamadBonus = 0; p.comradeUsedRound = false; p.factionUsedRound = false; p.fleetDrawsRound = 0; p.halfWeather = false; }
        // Announce the round.
        note(L("Round Start") + " · " + round, "notif_round_start");
        sound(round == 1 ? "round1_start" : "round_win");
        // Faction perks that trigger at the start of rounds 2 and 3 (Northern Realms, Zerrikania, Skellige).
        if (round > 1) {
            for (Player player : players()) {
                if (player.faction().equals("realms") && lastRoundWinner != player) {
                    draw(player, 1); note(L("Northern Realms faction ability triggered - North draws an additional card."), "notif_north");
                }
                if (player.faction().equals("zerrikania") && lastRoundWinner == player.opponent) {
                    List<Card> options = filter(player.grave, Card::isUnit);
                    Card card = pickOne(player, L("Which card to restore from your grave?"), options, true, this::mostValuable);
                    if (card != null) {
                        player.grave.remove(card);
                        placeUnit(card, player, card.firstRow(), null);
                        note(L("Zerrikania ability used - Unit restored from discard pile."), "notif_zerrikania");
                    }
                }
                if (player.faction().equals("skellige") && round == 3) {
                    List<Card> units = filter(player.grave, Card::isUnit);
                    Collections.shuffle(units);
                    List<Card> revived = new ArrayList<>(units.subList(0, Math.min(2, units.size())));
                    for (Card card : revived) { player.grave.remove(card); List<RowType> rows = card.allowedRows(); placeUnit(card, player, rows.get(RANDOM.nextInt(rows.size())), null); }
                    if (!revived.isEmpty()) note(player == human ? L("Skellige Ability Triggered!") : L("Opponent Skellige Ability Triggered!"), "notif_skellige");
                }
            }
        }
        // Wild Hunt picks which of its leaders to use this round.
        for (Player player : players()) {
            if (!player.faction().equals("wild_hunt")) continue;
            List<CardData> leaders = new ArrayList<>();
            for (CardData d : gameData().cards.values()) if (d.isLeader() && d.key.startsWith("wh_")) leaders.add(d);
            leaders.sort(Comparator.comparing(d -> d.key));
            List<Card> cards = new ArrayList<>();
            for (CardData d : leaders) cards.add(new Card(d, player));
            Card card = pickOne(player, L("Select the next leader to start the round with"), cards, candidates -> candidates.get(RANDOM.nextInt(candidates.size())));
            if (card != null) { player.leader = card; player.leaderUses = 1; applyPassiveLeader(player); }
        }
        for (Player player : players()) {
            // Leaders that offer a decision at the start of a round.
            if (player.leaderAbility().equals("king_bran") && player.leaderUses > 0) {
                int answer = pickOption(player, L("Bring the Skellige Storm?"), Arrays.asList(L("Bring the Storm [E]"), L("Maybe later [Q]")),
                    () -> (round > 1 || player.deck.stream().anyMatch(c -> c.has("storm"))) ? 0 : 1);
                if (answer == 0) {
                    player.leaderUses = 0; player.halfWeather = true;
                    Card storm = first(player.deck, c -> c.has("storm"));
                    if (storm != null) { player.deck.remove(storm); player.hand.add(storm); }
                }
            }
            if (player.leaderAbility().equals("madman_lugos") && player.leaderUses > 0 && player.opponent.hand.size() >= 2) {
                int answer = pickOption(player, L("Discard a card from the hand of the opponent?"), Arrays.asList(L("Discard a card [E]"), L("Maybe later [Q]")), () -> round >= 2 ? 0 : 1);
                if (answer == 0) {
                    player.leaderUses = 0;
                    List<Card> shuffled = new ArrayList<>(player.opponent.hand); Collections.shuffle(shuffled);
                    List<Card> twoCards = new ArrayList<>(shuffled.subList(0, Math.min(2, shuffled.size())));
                    Card card = pickOne(player, L("Which card to discard?"), twoCards, this::mostValuable);
                    if (card != null) { player.opponent.hand.remove(card); player.opponent.grave.add(card); }
                }
            }
        }
        // Scoia'tael decides who goes first.
        for (Player player : players()) {
            if (!player.faction().equals("scoiatael")) continue;
            int answer = pickOption(player, L("Who should go first?"), Arrays.asList(L("Go First [E]"), L("Let Opponent Start [Q]")), () -> 1);
            current = answer == 0 ? player : player.opponent;
            if (player == computer) note(L("Opponent used the Scoia'tael faction perk to go first."), "notif_scoiatael");
            break;
        }
        beginTurn();
    }

    /** Starts the current player's turn. */
    void beginTurn() {
        recalc();
        if (human.passed && computer.passed) { endRound(); return; }
        if (current.passed) current = current.opponent;
        if (current.hand.isEmpty() && !current.passed && !canActWithoutCards(current)) { pass(current); return; }
        if (current == human) { note(L("Your turn!"), "notif_me_turn"); sound("turn_me"); } else sound("turn_op");
    }
    /** Whether a player can still act without cards in hand. */
    boolean canActWithoutCards(Player p) { return leaderAvailable(p) || factionActive(p) != null; }

    /** The player passes for the rest of the round. */
    void pass(Player player) {
        if (phase != Phase.PLAY || player.passed) return;
        player.passed = true;
        sound("pass");
        note(player == human ? L("Round passed") : L("Your opponent has passed"), "notif_round_passed");
        if (player == current) current = player.opponent;
        beginTurn();
    }

    /** Ends a turn and gives control to the other player. */
    void endTurn(Player player) {
        recalc();
        List<RowType> doors = new ArrayList<>();
        for (RowType t : RowType.values()) if (player.row(t).door) doors.add(t);
        if (!doors.isEmpty() && !player.deck.isEmpty()) {
            Card top = player.deck.remove(0);
            RowType doorRow = null;
            if (top.isUnit()) for (RowType t : doors) if (top.allowedRows().contains(t)) { doorRow = t; break; }
            if (top.isUnit() && doorRow != null) placeUnit(top, player, doorRow, null);
            else if (!top.isUnit()) player.hand.add(top);
            else insertRandomly(player.deck, top);
        }
        for (Player side : Arrays.asList(player, player.opponent)) {
            if (!side.faction().equals("velen") || !side.lostUnitThisTurn) continue;
            side.lostUnitThisTurn = false;
            int extraDraws = 1 + (int) side.rowCards().stream().filter(c -> c.act("soothsayer")).count();
            if (side.leaderAbility().equals("lady_wood_brewess") && side.deck.size() >= 2) {
                List<Card> twoCards = new ArrayList<>(side.deck.subList(0, 2));
                Card card = pickOne(side, L("Choose a unit to play immediately"), twoCards, this::mostValuable);
                if (card != null) {
                    side.deck.remove(card);
                    if (card.isUnit()) placeUnit(card, side, card.firstRow(), null); else side.hand.add(card);
                    Collections.shuffle(side.deck);
                }
            } else draw(side, extraDraws);
            note(L("Velen ability triggered: Player will draw a card"), "notif_velen");
        }
        recalc();
        turn += 1;
        if (!player.opponent.passed) current = player.opponent;
        beginTurn();
    }

    /** Scores the round, removes a life from the loser and checks for the end of the match. */
    void endRound() {
        phase = Phase.ROUND_END;
        recalc();
        // Monsters may take one card back to hand before the round is scored.
        for (Player player : players()) {
            if (!player.faction().equals("monsters") || player.monstersUsed || player.rowCards().isEmpty()) continue;
            int answer = pickOption(player, L("Would you like to retake one of your cards?"), Arrays.asList(L("Retake a card [E]"), L("Not yet [Q]")), () -> round >= 2 ? 0 : 1);
            if (answer != 0) continue;
            Card card = pickOne(player, L("Which card to retake?"), player.rowCards(), this::mostValuable);
            if (card == null) continue;
            player.monstersUsed = true;
            RowType rowType = player.rowOf(card);
            if (rowType != null) player.row(rowType).cards.remove(card);
            resetCard(card); player.hand.add(card);
            note(L("Monsters faction ability triggered - monsters retake one card to their hand"), "notif_monsters");
        }
        recalc();
        // Decide the round winner; Nilfgaard wins draws against other factions.
        int humanScore = human.total, computerScore = computer.total;
        Player roundWinner = humanScore > computerScore ? human : (computerScore > humanScore ? computer : null);
        if (roundWinner == null) {
            boolean humanIsNilfgaard = human.faction().equals("nilfgaard"), computerIsNilfgaard = computer.faction().equals("nilfgaard");
            if (humanIsNilfgaard != computerIsNilfgaard) { roundWinner = humanIsNilfgaard ? human : computer; note(L("Nilfgaard wins draws"), "notif_nilfgaard"); }
        }
        // Record the result and take a life from the loser (both on a draw).
        history.add(new RoundResult(humanScore, computerScore, roundWinner));
        lastRoundWinner = roundWinner;
        if (roundWinner != null) roundWinner.opponent.gems -= 1; else { human.gems -= 1; computer.gems -= 1; }
        if (roundWinner == human) { note(L("You won the round!"), "notif_win_round"); sound("round_win"); }
        else if (roundWinner == computer) { note(L("Your opponent won the round"), "notif_lose_round"); sound("round_lose"); }
        else note(L("The round ended in a draw"), "notif_draw_round");
        // Clear the board, then end the match after the third round or when someone has no lives left.
        cleanupRound();
        if (human.gems <= 0 || computer.gems <= 0 || round >= 3) {
            phase = Phase.OVER;
            winner = human.gems > computer.gems ? human : (computer.gems > human.gems ? computer : null);
            sound(winner == human ? "game_win" : "game_lose");
            recalc();
            return;
        }
        // Otherwise prepare the next round; the round winner moves first.
        round += 1;
        human.passed = false; computer.passed = false;
        if (roundWinner != null) current = roundWinner;
        phase = Phase.PLAY;
        startRound();
    }

    /** Returns a card to its base state when it leaves the board. */
    void resetCard(Card card) {
        card.locked = false; card.setTo = null; card.tempStrength = null; card.multiplier = 1; card.bonus = 0; card.siegeMult = 1;
        card.baseOverride = null; card.heroOverride = null; card.keepNextRound = false;
    }
    /** Clears the board after a round, keeping cards that stay. */
    void cleanupRound() {
        List<Object[]> avengers = new ArrayList<>();
        for (Player player : players()) {
            for (Card unit : player.rowCards()) {
                if (!unit.act("resilience")) continue;
                List<String> a = unit.data().abilities; String key = a.isEmpty() ? "" : a.get(a.size() - 1);
                for (Card other : player.rowCards()) if (other != unit && other.data().abilities.contains(key)) { unit.keepNextRound = true; break; }
            }
        }
        for (Player player : players()) {
            for (RowType rowType : RowType.values()) {
                Row row = player.row(rowType);
                List<Card> stay = new ArrayList<>();
                for (Card card : row.cards) {
                    if (card.immortalRounds > 1) { card.immortalRounds -= 1; stay.add(card); continue; }
                    if (card.keepNextRound) { card.keepNextRound = false; stay.add(card); continue; }
                    boolean avenger = false; for (String a : card.data().abilities) if (a.startsWith("avenger")) avenger = true;
                    if (avenger && !card.locked) avengers.add(new Object[]{card, player, rowType});
                    resetCard(card); card.diedRound = round;
                    (card.owner != null ? card.owner : player).grave.add(card);
                }
                row.cards = stay;
                for (Card special : row.specials) (special.owner != null ? special.owner : player).grave.add(special);
                row.specials.clear(); row.lock = null; row.curse = null; row.ambush = null; row.door = false; row.leaderHorn = false; row.factionMorale = 0;
                player.weather.get(rowType.index()).clear();
            }
            for (Card card : player.hand) card.tempStrength = null;
            for (Card card : player.deck) card.tempStrength = null;
            player.forcedCard = null;
        }
        for (Card card : weatherCards) (card.owner != null ? card.owner : human).grave.add(card);
        weatherCards.clear();
        for (Player player : players()) if (player.fleetPending > 0) { draw(player, player.fleetPending); player.fleetPending = 0; }
        if (round < 3) {
            for (Object[] entry : avengers) {
                Card card = (Card) entry[0]; Player player = (Player) entry[1]; RowType r = (RowType) entry[2];
                for (String targetKey : card.data().targets) {
                    CardData cardData = gameData().cards.get(targetKey);
                    if (cardData == null || !cardData.isUnit()) continue;
                    RowType targetRow = RowType.from(cardData.row) != null ? RowType.from(cardData.row) : r;
                    Card summoned = first(player.deck, c -> c.key().equals(targetKey));
                    if (summoned != null) player.deck.remove(summoned); else summoned = new Card(cardData, player);
                    player.row(targetRow).cards.add(summoned); summoned.flash = 1;
                }
            }
        }
        recalc();
    }

    // MARK: Targets

    /** Rows where a card may be played. */
    List<RowType> validRows(Card card, Player player) {
        if (card.isUnit()) {
            if (card.act("ambush") || card.has("ambush")) return Arrays.asList(RowType.values());
            return card.allowedRows();
        }
        String kind = card.specialKind() == null ? "" : card.specialKind();
        List<RowType> rows = new ArrayList<>();
        switch (kind) {
            case "horn": case "mardroeme": case "morale":
                for (RowType t : RowType.values()) { boolean has = false; for (Card s : player.row(t).specials) if (kind.equals(s.specialKind())) has = true; if (!has) rows.add(t); }
                return rows;
            case "toussaint_wine":
                for (RowType t : Arrays.asList(RowType.CLOSE, RowType.RANGED)) { boolean has = false; for (Card s : player.row(t).specials) if ("toussaint_wine".equals(s.specialKind())) has = true; if (!has) rows.add(t); }
                return rows;
            case "shield": for (RowType t : RowType.values()) if (!player.row(t).shielded()) rows.add(t); return rows;
            case "shield_c": return Arrays.asList(RowType.CLOSE);
            case "shield_r": return Arrays.asList(RowType.RANGED);
            case "shield_s": return Arrays.asList(RowType.SIEGE);
            case "door": for (RowType t : RowType.values()) if (!player.row(t).door) rows.add(t); return rows;
            default: return rows;
        }
    }
    /** Enemy rows a card may target. */
    List<RowType> enemyRowTargets(Card card, Player player) {
        String kind = card.specialKind() == null ? "" : card.specialKind();
        List<RowType> rows = new ArrayList<>();
        if (kind.equals("lock")) { for (RowType t : RowType.values()) if (player.opponent.row(t).lock == null) rows.add(t); }
        else if (kind.equals("knockback")) { rows.add(RowType.CLOSE); rows.add(RowType.RANGED); }
        return rows;
    }
    /** Rows that can receive a curse. */
    List<SideRow> curseRows(Player player) {
        List<SideRow> rows = new ArrayList<>();
        for (Player side : Arrays.asList(player, player.opponent)) for (RowType t : RowType.values()) if (side.row(t).curse == null) rows.add(new SideRow(side, t));
        return rows;
    }
    /** Cards that a decoy can swap with. */
    List<Card> decoyTargets(Player player) { return filter(player.rowCards(), c -> !c.hero() && !c.key().equals("spe_decoy") && c.immortalRounds == 0); }

    // MARK: Playing cards

    /** The human plays a card. */
    void humanPlay(Card card, RowType row, Player rowOwner, Card target) {
        if (busy || phase != Phase.PLAY || current != human || !human.hand.contains(card)) return;
        busy = true;
        GameThread.launch(() -> { play(card, human, row, rowOwner, target); busy = false; });
    }
    /** The human passes. */
    void humanPass() {
        if (busy || phase != Phase.PLAY || current != human) return;
        busy = true;
        GameThread.launch(() -> { pass(human); busy = false; });
    }
    /** Plays a unit, special or weather card for a player. */
    void play(Card card, Player player, RowType row, Player rowOwner, Card target) {
        int handIndex = player.hand.indexOf(card);
        if (phase != Phase.PLAY || current != player || handIndex < 0) return;
        Card forced = player.forcedCard;
        if (forced != null && forced != card && player.hand.contains(forced)) return;
        player.forcedCard = null;
        player.hand.remove(handIndex);
        card.owner = player;
        card.flash = 1;
        if (card.data().isWeather()) playWeather(card, player, row);
        else if (card.data().isSpecial()) playSpecial(card, player, row, rowOwner, target);
        else placeUnit(card, player, row != null ? row : card.firstRow(), null);
        endTurn(player);
    }

    /** Places a unit on a row and triggers its abilities. */
    void placeUnit(Card card, Player player, RowType requestedRow, Player forcedSide) {
        RowType chosenRow = requestedRow;
        boolean isSpy = card.has("spy") || card.has("emissary") || card.has("ofiri_envoy");
        Player side = forcedSide != null ? forcedSide : (isSpy ? player.opponent : player);
        if (!card.isUnit()) { player.hand.add(card); return; }
        RowType fixed = RowType.from(card.data().row);
        if (!card.data().row.startsWith("agile") && !card.has("ambush") && fixed != null) chosenRow = fixed;
        card.owner = player;
        card.playedTurn = turn;
        Row row = side.row(chosenRow);
        if (row.curse != null && !card.hero()) {
            Card curse = row.curse;
            row.curse = null; (curse.owner != null ? curse.owner : player).grave.add(curse);
            side.grave.add(card); card.diedRound = round;
            note(gameData().abilityName("curse")); sound("curse");
            return;
        }
        row.cards.add(card);
        card.flash = 1;
        sound(card.hero() ? "hero" : "card");
        boolean hasAbilities = false; for (String a : card.data().abilities) if (!a.equals("hero")) hasAbilities = true;
        if (row.lock != null && !card.hero() && hasAbilities) {
            Card lockCard = row.lock;
            card.locked = true; row.lock = null; (lockCard.owner != null ? lockCard.owner : player).grave.add(lockCard); sound("lock"); events.add(GameEvent.anim(card, "lock"));
        }
        if (side == player) {
            final RowType ambushRow = chosenRow;
            Card ambusher = first(side.opponent.row(ambushRow).cards, c -> c.act("ambush") && c.owner == side.opponent);
            if (ambusher != null) {
                Player enemy = side.opponent;
                enemy.row(ambushRow).cards.remove(ambusher); enemy.grave.add(ambusher);
                draw(enemy, 2); sound("ambush");
            }
        }
        if (isSpy && side.leaderAbility().equals("novigrad_sigismund2")) draw(side, 1);
        recalc();
        pause(0.3);
        if (card.hero()) events.add(GameEvent.anim(card, "hero"));
        if (card.locked) { animate(card, "lock"); return; }
        if (card.act("bond")) {
            List<Card> group = filter(row.cards, c -> c.act("bond") && c.groupKey().equals(card.groupKey()));
            if (group.size() > 1) { for (Card member : group) animate(member, "bond", false); pause(0.7); }
        } else {
            String animatedAbility = null;
            List<String> abilities = card.data().abilities;
            for (int i = abilities.size() - 1; i >= 0; i--) if (animName(abilities.get(i)) != null) { animatedAbility = abilities.get(i); break; }
            if (animatedAbility != null) animate(card, animatedAbility);
            else if (card.hero()) pause(0.6);
        }
        unitAbilities(card, player, side, chosenRow);
        recalc();
    }

    static final Set<String> PASSIVE_LEADERS = new HashSet<>(Arrays.asList("eredin_treacherous", "vilgefortz_magician_kovir", "emhyr_whiteflame", "imlerith_general", "meve_white_queen",
        "novigrad_sigismund", "novigrad_sigismund2", "ofir_aamad", "zerrikanterment", "caranthir_navigator",
        "ofir_aamad_crown", "lady_wood_brewess", "francesca_daisy", "king_bran", "madman_lugos"));

    /** The human gives up the match. */
    void surrender() {
        if (phase == Phase.OVER) return;
        phase = Phase.OVER; human.gems = 0; winner = computer;
        sound("game_lose");
        if (waitingForChoice()) resolveChoice(null);
    }
    /** Ends a match that is being abandoned (e.g. exit to menu) so no task keeps waiting. */
    void abandon() {
        phase = Phase.OVER; paused = false;
        if (waitingForChoice()) resolveChoice(null);
    }
    /** Rough value of a card used by AI heuristics. */
    int aiCardValue(Card c) {
        return c.basePower() + (c.hero() ? 3 : 0) + (c.has("spy") ? 6 : 0) + (c.has("medic") ? 5 : 0) + (c.has("muster") ? 4 : 0)
            + (c.data().isSpecial() || c.data().isWeather() ? 4 : 0);
    }
    /** The card with the highest AI value. */
    Card mostValuable(List<Card> cards) { return cards.stream().max(Comparator.comparingInt(this::aiCardValue)).orElse(null); }

    // MARK: Small list helpers

    static <T> List<T> filter(List<T> list, java.util.function.Predicate<T> p) { List<T> r = new ArrayList<>(); for (T t : list) if (p.test(t)) r.add(t); return r; }
    static <T> T first(List<T> list, java.util.function.Predicate<T> p) { for (T t : list) if (p.test(t)) return t; return null; }
}

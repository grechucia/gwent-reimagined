// Game board: layout of rows and slots, the main board drawing, player panels and match flow overlays.
package io.github.grechucia.gwentreimagined;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Set;
import java.util.function.Consumer;
import static io.github.grechucia.gwentreimagined.GameData.L;

/** The match screen. */
abstract class SceneBoard extends SceneMenus {
    float watchdog;
    String lastSignature = "";

    SceneBoard(Renderer renderer, Audio audio) { super(renderer, audio); }

    abstract void startCareerFight(int fightIndex);

    /** Board background. */
    void drawModernBoard() {
        renderer.imageFillingScreen("img/board.jpg");
        renderer.gradient(box(0, Virtual.HEIGHT - 120, Virtual.WIDTH, 120), RGBA.BLACK.alpha(0), RGBA.BLACK.alpha(0.35f), 8);
    }
    boolean isHuman(Player player) { return game != null && player == game.human; }
    /** Screen rectangle of a player's row. */
    Box rowRect(Player player, RowType rowType) {
        float[] ys = isHuman(player) ? new float[]{422, 555, 688} : new float[]{271, 138, 5};
        return box(710, ys[rowType.index()], 803, 133);
    }
    /** Special card slot of a row. */
    Box specialRect(Player player, RowType rowType) { Box rowArea = rowRect(player, rowType); return box(579, rowArea.y + 9, CARD_WIDTH, CARD_HEIGHT); }
    /** Position of a player's deck. */
    Box deckRect(Player player) { return isHuman(player) ? box(1735, 836, CARD_WIDTH, 128) : box(1735, 80, CARD_WIDTH, 128); }
    /** Position of a player's graveyard. */
    Box graveRect(Player player) { return isHuman(player) ? box(1556, 836, CARD_WIDTH, CARD_HEIGHT) : box(1556, 80, CARD_WIDTH, CARD_HEIGHT); }
    /** Position of a player's leader card. */
    Box leaderRect(Player player) { return isHuman(player) ? BoardLayout.HUMAN_LEADER : BoardLayout.COMPUTER_LEADER; }

    /** Positions for `count` cards spread across an area. */
    List<Vec2> layout(int count, Box area, float width, float gap) {
        List<Vec2> positions = new ArrayList<>();
        if (count <= 0) return positions;
        float full = count * width + (count - 1) * gap;
        float step = width + gap;
        if (full > area.w) step = (area.w - width) / Math.max(1, count - 1);
        float used = step * (count - 1) + width;
        float x0 = area.x + (area.w - used) / 2;
        for (int i = 0; i < count; i++) positions.add(new Vec2(x0 + i * step, area.y));
        return positions;
    }
    List<Vec2> layout(int count, Box area) { return layout(count, area, CARD_WIDTH, 4); }

    /** Animates a card towards its target position. */
    void move(Card card, Vec2 point, Vec2 spawn, float dt) {
        if (!card.hasPos) { card.posX = spawn.x; card.posY = spawn.y; card.hasPos = true; }
        float k = Math.min(1, dt * 11);
        card.posX += (point.x - card.posX) * k; card.posY += (point.y - card.posY) * k;
        card.flash = Math.max(0, card.flash - dt * 1.6f);
    }

    /** Overlay image for the weather on a row. */
    String weatherOverlay(Set<String> weather) {
        if (weather.contains("frost") || weather.contains("white_frost")) return "overlay_frost";
        if (weather.contains("spider_web")) return "overlay_spider_web";
        if (weather.contains("fog")) return "overlay_fog";
        if (weather.contains("tse_tse")) return "overlay_tse_tse";
        if (weather.contains("sandstorm")) return "overlay_sandstorm";
        if (weather.contains("dragon_wrath")) return "overlay_dragon_wrath";
        if (weather.contains("rain") || weather.contains("storm")) return "overlay_rain";
        return null;
    }
    static final List<String> TARGETED_SPECIALS = Arrays.asList("horn", "mardroeme", "morale", "toussaint_wine", "shield", "shield_c", "shield_r", "shield_s", "door", "decoy", "lock", "knockback", "curse");
    /** Whether a special card needs no target. */
    boolean isFreeSpecial(Card card) {
        if (card.data().isWeather()) return true;
        if (!card.data().isSpecial()) return false;
        String kind = card.specialKind();
        return !TARGETED_SPECIALS.contains(kind == null ? "" : kind);
    }

    /** Rows and cards the human can target with the selected card, plus rows offered by a pending choice. */
    static final class PlayTargets { final List<SideRow> rows = new ArrayList<>(); List<Card> decoyCards = new ArrayList<>(); List<SideRow> choiceRows = new ArrayList<>(); }

    /** Game board: draws the whole match screen for one frame and drives the computer's turns. */
    @Override void drawGame(float dt) {
        Game match = game;
        if (match == null) return;
        processEvents(match);
        drawModernBoard();
        hover = null;
        boolean canAct = match.phase == GameCore.Phase.PLAY && match.current == match.human && !match.busy && match.choice == null;
        if (!canAct && match.choice == null) selected = null;
        drawActivePlayerHighlight(match);
        PlayTargets targets = playTargets(match, canAct);
        for (Player player : new Player[]{match.computer, match.human})
            for (RowType rowType : RowType.values()) drawRow(player, rowType, match, targets, dt);
        drawWeatherSlot(match, canAct, dt);
        for (Player player : new Player[]{match.computer, match.human}) drawStats(player, match, canAct);
        smallButton(BoardLayout.RULES_BUTTON, L("Rules"), true, this::openRules);
        parkHiddenCards(match);
        drawHand(match, canAct, dt);
        drawMatchButtons(match, canAct, dt);
        drawFX(dt);
        Card preview = hover != null ? hover : selected;
        if (preview != null) drawPreview(preview);
        if (match.phase == GameCore.Phase.REDRAW && match.choice == null) drawRedraw(match);
        if (match.choice != null) drawChoice(match.choice, match);
        drawNotes(dt);
        if (match.phase == GameCore.Phase.OVER && notes.isEmpty()) drawEnd(match);
        if (game == match) runComputerTurn(match, dt);
        if (autotest && game == match) autoTest(match, dt);
    }

    /** Works out where the currently selected card can be played. */
    PlayTargets playTargets(Game match, boolean canAct) {
        PlayTargets targets = new PlayTargets();
        if (match.choice != null && match.choice.kind == Choice.Kind.ROWS) targets.choiceRows = match.choice.rows;
        Card card = selected;
        if (!canAct || card == null) return targets;
        if (card.isUnit()) {
            boolean enemySide = card.has("spy") || card.has("emissary") || card.has("ofiri_envoy");
            for (RowType r : match.validRows(card, match.human)) targets.rows.add(new SideRow(enemySide ? match.computer : match.human, r));
            return targets;
        }
        String kind = card.specialKind() == null ? "" : card.specialKind();
        switch (kind) {
            case "decoy": targets.decoyCards = match.decoyTargets(match.human); break;
            case "lock": case "knockback": for (RowType r : match.enemyRowTargets(card, match.human)) targets.rows.add(new SideRow(match.computer, r)); break;
            case "curse": targets.rows.addAll(match.curseRows(match.human)); break;
            default: for (RowType r : match.validRows(card, match.human)) targets.rows.add(new SideRow(match.human, r)); break;
        }
        return targets;
    }

    /** Golden glow behind the panel of the player whose turn it is. */
    void drawActivePlayerHighlight(Game match) {
        if (match.phase != GameCore.Phase.PLAY) return;
        Player player = match.current;
        if (player == null) return;
        Box band = player == match.human ? BoardLayout.HUMAN_PANEL : BoardLayout.COMPUTER_PANEL;
        renderer.gradient(band, new RGBA(0.5f, 0.38f, 0.12f, 0), new RGBA(0.85f, 0.62f, 0.2f, 0.22f), 8);
        renderer.rect(box(band.x, player == match.human ? band.y : band.y + band.h - 3, band.w, 3), RGBA.GOLD.alpha(0.8f));
    }

    /** One board row: weather, target highlight, row effect icons, unit cards, special cards and the row score. */
    void drawRow(Player player, RowType rowType, Game match, PlayTargets targets, float dt) {
        Box rowArea = rowRect(player, rowType);
        Row row = player.row(rowType);
        Set<String> weather = player.weather.get(rowType.index());
        String overlay = weatherOverlay(weather);
        if (overlay != null) renderer.image("img/icons/" + overlay + ".png", box(BoardLayout.ROWS_LEFT, rowArea.y + 6, 950, 127), RGBA.WHITE.alpha(0.7f + 0.15f * sin(time * 1.3f + rowType.index())));
        drawWeatherFX(weather, rowArea);
        Box wholeRow = box(BoardLayout.ROWS_LEFT, rowArea.y + 2, BoardLayout.ROWS_WIDTH, rowArea.h - 4);
        boolean isTarget = false;
        for (SideRow s : targets.rows) if (s.player == player && s.row == rowType) isTarget = true;
        int choiceIndex = -1;
        for (int i = 0; i < targets.choiceRows.size(); i++) if (targets.choiceRows.get(i).player == player && targets.choiceRows.get(i).row == rowType) { choiceIndex = i; break; }
        if (isTarget || choiceIndex >= 0) {
            float pulse = 0.18f + 0.1f * sin(time * 5);
            renderer.rect(wholeRow, new RGBA(1, 0.8f, 0.3f, pulse)); renderer.frame(wholeRow, RGBA.GOLD, 2);
            Card card = selected;
            if (card != null && isTarget) button(wholeRow, () -> playSelected(card, rowType, player, null));
            int index = choiceIndex;
            if (index >= 0) button(wholeRow, () -> match.resolveChoice(new int[]{index}));
        }
        float iconX = 712;
        boolean[] active = {row.lock != null, row.curse != null, row.door, row.leaderHorn};
        String[] icons = {"power_lock", "power_curse", "power_door", "power_horn"};
        for (int i = 0; i < 4; i++) if (active[i]) { renderer.image("img/icons/" + icons[i] + ".png", box(iconX, rowArea.y + 92, 36, 36)); iconX += 38; }
        List<Vec2> positions = layout(row.cards.size(), box(rowArea.x + 4, rowArea.y + 5, rowArea.w - 8, CARD_HEIGHT));
        boolean[] flying = new boolean[1];
        for (int i = 0; i < row.cards.size(); i++) {
            Card card = row.cards.get(i);
            move(card, positions.get(i), player == match.human ? new Vec2(1000, 1000) : new Vec2(1000, -150), dt);
            Box cardRect = box(card.posX, card.posY, CARD_WIDTH, CARD_HEIGHT);
            boolean isDecoyTarget = targets.decoyCards.contains(card);
            Box flightFrame = flightRect(card, positions.get(i), flying);
            if (flying[0]) renderer.rect(box(flightFrame.x + 10, flightFrame.y + 16, flightFrame.w, flightFrame.h), RGBA.BLACK.alpha(0.35f));
            drawCard(card, flying[0] ? flightFrame : cardRect, isDecoyTarget, false);
            if (card.locked) renderer.image("img/icons/power_lock.png", box(cardRect.x + 50, cardRect.y + 4, 32, 32));
            if (cardRect.contains(mouse)) hover = card;
            Card decoy = selected;
            if (isDecoyTarget && decoy != null) button(cardRect, () -> playSelected(decoy, null, null, card));
        }
        Box specialSlot = specialRect(player, rowType);
        for (int i = 0; i < row.specials.size(); i++) {
            Card special = row.specials.get(i);
            move(special, new Vec2(specialSlot.x + i * 14, specialSlot.y), new Vec2(1000, 1000), dt);
            Box cardRect = box(special.posX, special.posY, CARD_WIDTH, CARD_HEIGHT);
            drawCard(special, cardRect);
            if (cardRect.contains(mouse)) hover = special;
        }
        drawRowScore(row.total, rowArea.y + 70);
    }

    /** Gold disc with the total power of a row. */
    void drawRowScore(int total, float centerY) {
        float x = BoardLayout.ROW_SCORE_X;
        Font outer = Font.ui(78), inner = Font.ui(70), digits = Font.ui(28, true);
        renderer.text("●", outer, x, centerY - renderer.measure("●", outer)[1] / 2, RGBA.GOLD_DARK.alpha(0.9f), 0, Align.CENTER, null, 0);
        renderer.text("●", inner, x, centerY - renderer.measure("●", inner)[1] / 2, Theme.PANEL_DARK, 0, Align.CENTER, null, 0);
        String text = String.valueOf(total);
        renderer.text(text, digits, x, centerY - renderer.measure(text, digits)[1] / 2, Theme.PALE_GOLD, 0, Align.CENTER, null, 0);
    }

    /** Weather cards in play and, for cards without a target, the area that plays them. */
    void drawWeatherSlot(Game match, boolean canAct, float dt) {
        Box slot = BoardLayout.WEATHER_SLOT;
        List<Vec2> positions = layout(match.weatherCards.size(), box(slot.x + 8, slot.y + 8, slot.w - 16, CARD_HEIGHT));
        for (int i = 0; i < match.weatherCards.size(); i++) {
            Card card = match.weatherCards.get(i);
            move(card, positions.get(i), new Vec2(1000, 1000), dt);
            Box cardRect = box(card.posX, card.posY, CARD_WIDTH, CARD_HEIGHT);
            drawCard(card, cardRect);
            if (cardRect.contains(mouse)) hover = card;
        }
        Card card = selected;
        if (canAct && card != null && isFreeSpecial(card)) {
            float pulse = 0.18f + 0.1f * sin(time * 5);
            renderer.rect(slot, new RGBA(1, 0.8f, 0.3f, pulse)); renderer.frame(slot, RGBA.GOLD, 2);
            button(slot, () -> playSelected(card, null, null, null));
            button(BoardLayout.ALL_ROWS, () -> playSelected(card, null, null, null));
        }
    }

    /** Keeps cards that are not visible (opponent's hand, both decks) at their off-screen or deck positions. */
    void parkHiddenCards(Game match) {
        for (Card card : match.computer.hand) { card.hasPos = true; card.posX = 1000; card.posY = -160; }
        for (Player player : new Player[]{match.human, match.computer}) {
            Box deck = deckRect(player);
            for (Card card : player.deck) { card.posX = deck.x; card.posY = deck.y; card.hasPos = true; }
        }
    }

    /** The human's hand: hover lift, selection and click handling. */
    void drawHand(Game match, boolean canAct, float dt) {
        Box hand = BoardLayout.HAND;
        List<Card> cards = match.human.hand;
        List<Vec2> positions = layout(cards.size(), box(hand.x + 8, hand.y + 6, hand.w - 16, CARD_HEIGHT), CARD_WIDTH, 3);
        Card hoveredCard = null;
        for (int i = cards.size() - 1; i >= 0 && hoveredCard == null; i--) {
            Card card = cards.get(i);
            Box area = box(positions.get(i).x, positions.get(i).y - card.lift, CARD_WIDTH, CARD_HEIGHT);
            if (area.contains(mouse) && match.phase == GameCore.Phase.PLAY && match.choice == null) hoveredCard = card;
        }
        Card forced = match.human.forcedCard;
        Box deck = deckRect(match.human);
        for (int i = 0; i < cards.size(); i++) {
            Card card = cards.get(i);
            float targetLift = selected == card ? 26 : (hoveredCard == card ? 14 : 0);
            card.lift += (targetLift - card.lift) * Math.min(1, dt * 14);
            move(card, positions.get(i), new Vec2(deck.x, deck.y), dt);
            Box cardRect = box(card.posX, card.posY - card.lift, CARD_WIDTH, CARD_HEIGHT);
            drawCard(card, cardRect, selected == card || forced == card, canAct && forced != null && forced != card);
            if (i == 0 && canAct) padPrimary = cardRect;
            if (hoveredCard == card) hover = card;
            if (canAct) button(cardRect, () -> clickHand(card));
        }
    }

    /** Music buttons, Exit to menu (with confirmation), Pass and Give up. */
    void drawMatchButtons(Game match, boolean canAct, float dt) {
        String[] symbols = {"♫", "⏭"};
        Runnable[] actions = {() -> audio.setMusicOn(!audio.musicOn()), audio::skipTrack};
        for (int i = 0; i < 2; i++) {
            Box area = box(BoardLayout.MUSIC_BUTTONS_X + i * 52, BoardLayout.BOTTOM_BUTTONS_Y, 46, 46);
            padNoAuto.add(area);
            boolean active = i == 1 || audio.musicOn();
            boolean hovered = area.contains(mouse);
            renderer.rect(area, Theme.PANEL_DARK.alpha(hovered ? 0.9f : 0.7f)); renderer.frame(area, RGBA.GOLD_DARK.alpha(hovered ? 0.9f : 0.45f), 1);
            renderer.text(symbols[i], Font.ui(24, true), area.mid().x, area.y + 8, hovered ? RGBA.WHITE : new RGBA(0.93f, 0.76f, 0.35f, active ? 1 : 0.35f), Align.CENTER);
            button(area, actions[i]);
        }
        exitConfirmTimer = Math.max(0, exitConfirmTimer - dt);
        padNoAuto.add(BoardLayout.EXIT_BUTTON);
        smallButton(BoardLayout.EXIT_BUTTON, exitConfirmTimer > 0 ? L("Are you sure?") : L("Exit to menu"), true, () -> {
            if (exitConfirmTimer > 0) { exitConfirmTimer = 0; leaveMatch(); setScreen(Screen.TITLE); } else exitConfirmTimer = 3;
        });
        smallButton(BoardLayout.PASS_BUTTON, L("Pass"), canAct, () -> { selected = null; if (game != null) game.humanPass(); });
        padNoAuto.add(BoardLayout.GIVE_UP_BUTTON);
        smallButton(BoardLayout.GIVE_UP_BUTTON, L("Give up"), match.phase != GameCore.Phase.OVER, () -> { if (game != null) game.surrender(); });
    }
    /** Drops the current match, releasing any game task that is waiting for a choice. */
    void leaveMatch() { if (game != null) game.abandon(); game = null; fxList.clear(); notes.clear(); }

    /** Lets the computer move after a short delay once nothing else is happening on screen. */
    void runComputerTurn(Game match, float dt) {
        boolean coinShown = false;
        for (FX fx : fxList) if (fx.kind == FX.Kind.COIN) coinShown = true;
        if (!(match.phase == GameCore.Phase.PLAY && !match.busy && match.choice == null && notes.isEmpty() && !coinShown && !rulesOpen)) { computerTurnTimer = 0; return; }
        computerTurnTimer += dt;
        if (computerTurnTimer <= (autotest ? 0.35f : 0.85f)) return;
        computerTurnTimer = 0;
        if (match.current == match.computer) {
            if (autotest) logAIMove(match, match.computer, "Player 2");
            GameThread.launch(() -> match.aiTurn(match.computer));
        } else if (autotest && match.current == match.human) {
            logAIMove(match, match.human, "Player 1");
            GameThread.launch(() -> match.aiTurn(match.human));
        }
    }
    /** Writes the move the AI is about to make to the test log. */
    void logAIMove(Game match, Player player, String label) {
        String score = "[" + match.human.total + ":" + match.computer.total + "]";
        AIMove move = match.aiDecide(player);
        if (move == null) { log("  " + label + ": pass  " + score); return; }
        String what = move.card != null ? move.card.key() : (move.kind == AIMove.Kind.LEADER ? "LEADER " + player.leaderAbility() : "FACTION");
        log("  " + label + ": " + what + (move.row != null ? " -> " + move.row : "") + "  " + score);
    }
    /** Automatic play used by tests. */
    void autoTest(Game match, float dt) {
        autotestTimer += dt;
        String signature = match.turn + "|" + match.round + "|" + match.human.hand.size() + "|" + match.computer.hand.size() + "|" + match.phase + "|" + match.human.total + "|" + match.computer.total;
        if (!signature.equals(lastSignature)) { lastSignature = signature; watchdog = 0; } else watchdog += dt;
        if (watchdog > 25) {
            log("HANG: phase " + match.phase + ", busy " + match.busy + ", choice: " + (match.choice != null ? match.choice.title : "none"));
            watchdog = 0; gamesPlayed++; startGame(); return;
        }
        if (match.phase == GameCore.Phase.REDRAW && autotestTimer > 1) { autotestTimer = 0; match.finishRedraw(); }
        if (match.phase == GameCore.Phase.OVER && notes.isEmpty() && autotestTimer > 2) {
            autotestTimer = 0; gamesPlayed++;
            StringBuilder rounds = new StringBuilder();
            for (RoundResult r : match.history) rounds.append(rounds.length() > 0 ? ", " : "").append(r.human).append(':').append(r.computer);
            log("END: rounds " + rounds + " winner: " + (match.winner == match.human ? "Player 1" : (match.winner == match.computer ? "Player 2" : "draw")));
            startGame();
        }
    }

    /** Player panel: name, faction, lives, card count and leader. */
    void drawStats(Player player, Game match, boolean canAct) {
        boolean mine = player == match.human;
        float panelY = mine ? 666 : 263;
        renderer.image("img/icons/profile.png", box(128, panelY + 13, 99, 108));
        renderer.image("img/icons/icon_player_border.png", box(118, panelY + 7, 116, 127));
        Box shield = box(106, mine ? 748 : 270, 50, 55);
        renderer.image("img/icons/deck_shield_" + player.faction() + ".png", shield);
        if (shield.contains(mouse)) hoverText = gameData().factionName(player.faction()) + "\n" + gameData().factionDesc(player.faction());
        float nameY = mine ? 728 : 271;
        renderer.text(mine ? playerName() : (careerFightName != null ? careerFightName : L("Player 2")), Font.gwent(24), 239, nameY, Theme.TEXT_GOLD);
        renderer.text(gameData().factionName(player.faction()), Font.ui(17), 239, nameY + 27, RGBA.gray(0.85f), 190);
        float handCountY = mine ? 680 : 356;
        renderer.image("img/icons/icon_card_count.png", box(240, handCountY + 4, 30, 32));
        renderer.text(String.valueOf(player.hand.size()), Font.ui(30, true), 274, handCountY, Theme.AMBER);
        float gemsY = mine ? 678 : 352;
        renderer.image("img/icons/icon_gem_" + (player.gems >= 1 ? "on" : "off") + ".png", box(319, gemsY, 41, 42));
        renderer.image("img/icons/icon_gem_" + (player.gems >= 2 ? "on" : "off") + ".png", box(360, gemsY, 41, 42));
        Box scoreBadge = box(427, mine ? 708 : 305, 54, 54);
        renderer.image("img/icons/score_total_" + (mine ? "me" : "op") + ".png", scoreBadge);
        if (player.total > player.opponent.total) renderer.image("img/icons/icon_high_score.png", box(scoreBadge.x - 14, scoreBadge.y - 12, 82, 78));
        String total = String.valueOf(player.total);
        float textHeight = renderer.measure(total, Font.ui(30, true))[1];
        renderer.text(total, Font.ui(30, true), scoreBadge.mid().x, scoreBadge.mid().y - textHeight / 2, RGBA.BLACK, 0, Align.CENTER, RGBA.WHITE.alpha(0.5f), 0);
        if (player.passed) renderer.text(L("Passed"), Font.ui(24, true), 330, mine ? 640 : 410, Theme.AMBER, Align.CENTER);
        Box leaderArea = leaderRect(player);
        player.leader.posX = leaderArea.x; player.leader.posY = leaderArea.y; player.leader.hasPos = true;
        boolean available = match.leaderAvailable(player);
        drawCard(player.leader, leaderArea, false, !available && !GameCore.PASSIVE_LEADERS.contains(player.leaderAbility()));
        renderer.image("img/icons/icon_leader_active.png", box(260, leaderArea.y + 51, 38, 38), RGBA.WHITE.alpha(available ? 1 : 0.25f));
        if (leaderArea.contains(mouse)) hover = player.leader;
        if (mine && canAct && available) {
            if (leaderArea.contains(mouse)) renderer.frame(leaderArea.inset(-3), RGBA.GOLD, 3);
            button(leaderArea, () -> { if (game != null) game.humanLeader(); });
            button(box(260, leaderArea.y + 51, 38, 38), () -> { if (game != null) game.humanLeader(); });
        }
        String factionAbility = mine ? match.factionActive(player) : null;
        if (factionAbility != null) {
            String title = factionAbility.equals("transform") ? L("Transform") : (factionAbility.startsWith("skip") ? L("Skip turn") : L("Faction ability"));
            smallButton(BoardLayout.FACTION_ABILITY_BUTTON, title, canAct, () -> { if (game != null) game.humanFaction(); });
        }
        Box deckArea = deckRect(player);
        int count = player.deck.size();
        for (int i = 0; i < Math.min(4, count); i++) renderer.image("img/icons/deck_back_" + player.faction() + ".jpg", box(deckArea.x - i, deckArea.y - i, deckArea.w, deckArea.h));
        if (count > 0) {
            renderer.rect(box(deckArea.mid().x - 22, deckArea.y + deckArea.h - 40, 44, 30), RGBA.BLACK.alpha(0.6f));
            renderer.text(String.valueOf(count), Font.ui(22, true), deckArea.mid().x, deckArea.y + deckArea.h - 38, RGBA.WHITE, Align.CENTER);
        }
        Box graveArea = graveRect(player);
        for (Card card : player.grave) move(card, new Vec2(graveArea.x, graveArea.y), new Vec2(graveArea.x, graveArea.y), 1 / 60f);
        if (!player.grave.isEmpty()) {
            Card top = player.grave.get(player.grave.size() - 1);
            Box topRect = box(top.posX, top.posY, CARD_WIDTH, CARD_HEIGHT);
            drawCard(top, topRect);
            if (topRect.contains(mouse)) hover = top;
        }
    }

    /** Selects or plays a card from the hand. */
    void clickHand(Card card) {
        Game match = game;
        if (match == null || match.phase != GameCore.Phase.PLAY || match.current != match.human || match.busy || match.choice != null) return;
        Card forced = match.human.forcedCard;
        if (forced != null && forced != card) { notes.add(new Note(L("You must play the marked card."), null)); return; }
        if (selected == card) {
            if (isFreeSpecial(card)) { playSelected(card, null, null, null); return; }
            List<RowType> rows = match.validRows(card, match.human);
            if (card.isUnit() && rows.size() == 1) { playSelected(card, rows.get(0), null, null); return; }
            String kind = card.specialKind();
            if (!card.isUnit() && !"lock".equals(kind) && !"knockback".equals(kind) && !"decoy".equals(kind) && !"curse".equals(kind) && rows.size() == 1) {
                playSelected(card, rows.get(0), match.human, null); return;
            }
            selected = null;
            return;
        }
        selected = card;
        audio.play("card", 0.5f);
    }
    /** Plays the selected card on a row or target. */
    void playSelected(Card card, RowType row, Player rowOwner, Card target) {
        if (game == null) return;
        selected = null;
        game.humanPlay(card, row, rowOwner, target);
    }

    /** Turns engine events into notifications, sounds and effects. */
    void processEvents(Game match) {
        for (GameEvent event : match.events) {
            switch (event.kind) {
                case NOTIFY: notes.add(new Note(event.text, event.icon)); while (notes.size() > 4) notes.remove(0); break;
                case SOUND: audio.play(event.text); break;
                case FLASH: event.card.flash = 1; break;
                default: addFX(event); break;
            }
        }
        match.events.clear();
    }

    /** Draws the tooltip and the current notification banner. */
    void drawNotes(float dt) {
        String tooltip = hoverText;
        if (tooltip != null && (game == null || game.choice == null)) {
            float w = 420;
            float h = renderer.measure(tooltip, Font.ui(17), w - 24)[1] + 20;
            Box area = box(Math.min(mouse.x + 18, Virtual.WIDTH - w - 10), Math.min(mouse.y + 18, Virtual.HEIGHT - h - 10), w, h);
            renderer.rect(area, Theme.PANEL_DARK.alpha(0.94f)); renderer.frame(area, RGBA.GOLD_DARK.alpha(0.7f), 1);
            renderer.text(tooltip, Font.ui(17), area.x + 12, area.y + 10, RGBA.gray(0.92f), w - 24);
        }
        hoverText = null;
        if (notes.isEmpty()) return;
        Note note = notes.get(0);
        noteTimer += dt;
        float duration = autotest ? 0.5f : 1.25f;
        float alpha = Math.max(0, Math.min(1, Math.min(noteTimer / 0.15f, (duration - noteTimer) / 0.2f)));
        float entry = Math.min(1, noteTimer / 0.18f), easing = 1 - (1 - entry) * (1 - entry);
        Font font = Font.gwent(34);
        float[] size = renderer.measure(note.text, font, 900);
        float textWidth = Math.min(900, size[0]), textHeight = size[1];
        float iconWidth = note.icon == null ? 0 : 96;
        float w = textWidth + iconWidth + 90, h = Math.max(110, textHeight + 50);
        Box card = box(960 - w / 2, 500 - h / 2 + (1 - easing) * 18, w, h);
        renderer.rect(renderer.visibleRect, RGBA.BLACK.alpha(0.25f * alpha));
        renderer.gradient(card, Theme.PANEL_DARK.alpha(0.93f * alpha), Theme.PANEL_DARK.alpha(0.95f * alpha), 8);
        renderer.rect(box(card.x, card.y, card.w, 2), RGBA.GOLD.alpha(0.9f * alpha));
        renderer.rect(box(card.x, card.y + card.h - 1, card.w, 1), RGBA.GOLD_DARK.alpha(0.6f * alpha));
        renderer.frame(card, RGBA.GOLD_DARK.alpha(0.35f * alpha), 1);
        float x = card.x + 45;
        if (note.icon != null) { renderer.image("img/icons/" + note.icon + ".png", box(x - 10, card.mid().y - 52, 104, 104), RGBA.WHITE.alpha(alpha)); x += iconWidth + 10; }
        renderer.text(note.text, font, note.icon == null ? card.mid().x : x, card.mid().y - textHeight / 2, Theme.PALE_GOLD.alpha(alpha), 900, note.icon == null ? Align.CENTER : Align.LEFT, null, 0);
        if (noteTimer >= duration) { notes.remove(0); noteTimer = 0; }
    }

    /** Full-screen overlay with a set of cards to choose from; returns the y just below the cards. */
    float overlayCards(List<Card> cards, String title, String info, List<Card> marked, Consumer<Card> onClick) {
        renderer.rect(renderer.visibleRect, RGBA.BLACK.alpha(0.74f));
        renderer.text(title, Font.serif(32, true), 960, 70, RGBA.GOLD, 1500, Align.CENTER);
        if (info != null) renderer.text(info, Font.ui(22), 960, 150, RGBA.gray(0.9f), Align.CENTER);
        int count = cards.size();
        int perRow = count > 14 ? 10 : (count > 6 ? (count + 1) / 2 : Math.max(1, count));
        int rows = (count + perRow - 1) / perRow;
        float w = rows > 2 ? 120 : (rows > 1 ? 168 : 190), h = w * 1.437f, gap = rows > 2 ? 12 : 22;
        float y0 = rows > 1 ? 195 : 330;
        for (int i = 0; i < count; i++) {
            Card card = cards.get(i);
            int rowI = i / perRow, colI = i % perRow;
            int inRow = Math.min(perRow, count - rowI * perRow);
            float x0 = 960 - (inRow * w + (inRow - 1) * gap) / 2;
            Box cardRect = box(x0 + colI * (w + gap), y0 + rowI * (h + gap), w, h);
            if (cardRect.y > 960) break;
            boolean hovered = cardRect.contains(mouse);
            drawCardLarge(card, cardRect);
            if (marked.contains(card)) renderer.frame(cardRect.inset(-5), new RGBA(0.3f, 0.85f, 0.3f, 1), 4);
            if (hovered) { renderer.frame(cardRect.inset(-4), RGBA.GOLD, 3); hover = card; }
            button(cardRect, () -> onClick.accept(card));
        }
        return Math.min(985, y0 + rows * (h + gap));
    }

    /** Redraw phase overlay. */
    void drawRedraw(Game match) {
        float end = overlayCards(match.human.hand, L("Click a card to redraw it"), L("Redraws left: ") + match.redrawsLeft, new ArrayList<>(), card -> {
            if (game == null || game.redrawsLeft <= 0 || game.busy) return;
            Card replacement = game.redraw(card);
            if (replacement != null) replacement.hasPos = false;
            if (game.redrawsLeft == 0) game.finishRedraw();
        });
        goldButton(box(960 - 150, Math.min(990, end + 10), 300, 60), L("Done"), Font.gwent(30), () -> { if (game != null) game.finishRedraw(); });
        if (hover != null) drawPreview(hover);
    }

    /** Overlay for a pending choice of the human player. */
    void drawChoice(Choice choice, Game match) {
        switch (choice.kind) {
            case CARDS: {
                List<Card> cards = choice.cards;
                int minCount = choice.min, maxCount = choice.max;
                boolean multi = maxCount > 1 || minCount != 1;
                float end = overlayCards(cards, choice.title, multi ? L("Selected: ") + multiSelection.size() + " / " + maxCount : null, multiSelection, c -> {
                    if (!multi) { match.resolveChoice(new int[]{cards.indexOf(c)}); return; }
                    if (multiSelection.contains(c)) multiSelection.remove(c);
                    else if (multiSelection.size() < maxCount) multiSelection.add(c);
                });
                float buttonX = 960 - 150;
                if (multi) {
                    boolean valid = multiSelection.size() >= minCount && multiSelection.size() <= maxCount;
                    goldButton(box(choice.canCancel ? 960 - 320 : buttonX, Math.min(990, end + 10), 300, 60), L("Done"), Font.gwent(30), valid, () -> {
                        int[] indices = new int[multiSelection.size()];
                        for (int i = 0; i < indices.length; i++) indices[i] = cards.indexOf(multiSelection.get(i));
                        multiSelection.clear(); match.resolveChoice(indices);
                    });
                    buttonX = 960 + 20;
                }
                if (choice.canCancel) goldButton(box(multi ? buttonX : 960 - 150, Math.min(990, end + 10), 300, 60), L("Skip"), Font.serif(24, true), () -> { multiSelection.clear(); match.resolveChoice(null); });
                if (hover != null) drawPreview(hover);
                break;
            }
            case REVEAL: {
                float end = overlayCards(choice.cards, choice.title, null, new ArrayList<>(), c -> match.resolveChoice(null));
                goldButton(box(960 - 150, Math.min(990, end + 10), 300, 60), L("Close"), Font.serif(24, true), () -> match.resolveChoice(null));
                if (hover != null) drawPreview(hover);
                break;
            }
            case OPTIONS: {
                List<String> options = choice.options;
                renderer.rect(renderer.visibleRect, RGBA.BLACK.alpha(0.55f));
                int cols = options.size() > 4 ? 5 : options.size();
                float buttonWidth = options.size() > 4 ? 120 : 340, buttonHeight = 64;
                int rows = (options.size() + cols - 1) / Math.max(1, cols);
                float boxH = 170 + rows * (buttonHeight + 16);
                Box panel = box(960 - 420, 540 - boxH / 2, 840, boxH);
                renderer.gradient(panel, new RGBA(0.12f, 0.09f, 0.05f, 0.97f), Theme.PANEL_DARK.alpha(0.97f), 10);
                renderer.frame(panel, RGBA.GOLD_DARK, 2);
                renderer.text(choice.title, Font.serif(26, true), 960, panel.y + 30, RGBA.GOLD, 760, Align.CENTER);
                for (int i = 0; i < options.size(); i++) {
                    int row = i / cols, col = i % cols;
                    int inRow = Math.min(cols, options.size() - row * cols);
                    float x0 = 960 - (inRow * buttonWidth + (inRow - 1) * 16) / 2;
                    int index = i;
                    goldButton(box(x0 + col * (buttonWidth + 16), panel.y + 120 + row * (buttonHeight + 16), buttonWidth, buttonHeight), options.get(i), Font.serif(22, true), () -> match.resolveChoice(new int[]{index}));
                }
                break;
            }
            case ROWS: {
                Box bar = BoardLayout.ROW_CHOICE_BAR;
                renderer.rect(bar, RGBA.BLACK.alpha(0.8f)); renderer.frame(bar, RGBA.GOLD_DARK.alpha(0.7f), 1);
                renderer.text(choice.title, Font.serif(22, true), bar.mid().x, bar.y + 10, RGBA.GOLD, 940, Align.CENTER);
                break;
            }
        }
    }

    /** End-of-match screen. */
    void drawEnd(Game match) {
        renderer.rect(renderer.visibleRect, RGBA.BLACK.alpha(0.8f));
        String image = match.winner == match.human ? "end_win" : (match.winner == match.computer ? "end_lose" : "end_draw");
        renderer.imageContain("img/icons/" + image + ".png", BoardLayout.END_OF_MATCH_BANNER);
        renderer.text(L("Round"), Font.serif(24, true), 760, 500, RGBA.gray(0.8f), Align.CENTER);
        renderer.text(playerName(), Font.serif(24, true), 960, 500, RGBA.GOLD, 190, Align.CENTER);
        renderer.text(careerFightName != null ? careerFightName : L("Player 2"), Font.serif(24, true), 1160, 500, RGBA.GOLD, 190, Align.CENTER);
        for (int i = 0; i < match.history.size(); i++) {
            RoundResult h = match.history.get(i);
            float y = 545 + i * 44;
            renderer.text(String.valueOf(i + 1), Font.ui(26, true), 760, y, RGBA.WHITE, Align.CENTER);
            renderer.text(String.valueOf(h.human), Font.ui(26, true), 960, y, h.winner == match.human ? RGBA.GOLD : RGBA.WHITE, Align.CENTER);
            renderer.text(String.valueOf(h.computer), Font.ui(26, true), 1160, y, h.winner == match.computer ? RGBA.GOLD : RGBA.WHITE, Align.CENTER);
        }
        Integer fightIndex = careerFight;
        if (fightIndex != null) {
            if (match.winner == match.human) {
                goldButton(box(960 - 160, 760, 320, 64), L("Claim reward"), Font.serif(26, true), () -> {
                    careerRewards = career().rewardOptions(fightIndex); careerNewLeader = career().win(fightIndex);
                    careerFight = null; leaveMatch(); careerChapter = null; setScreen(Screen.CAREER);
                });
            } else {
                goldButton(box(960 - 330, 760, 300, 64), L("Try again"), Font.serif(26, true), () -> startCareerFight(fightIndex));
                goldButton(box(960 + 30, 760, 300, 64), L("Career"), Font.serif(26, true), () -> { careerFight = null; leaveMatch(); setScreen(Screen.CAREER); });
            }
            return;
        }
        goldButton(box(960 - 330, 760, 300, 64), L("Replay"), Font.serif(26, true), this::startGame);
        goldButton(box(960 + 30, 760, 300, 64), L("Main menu"), Font.serif(26, true), () -> { leaveMatch(); setScreen(Screen.TITLE); });
    }
}

// Main UI scene state: immediate-mode buttons, navigation between screens, settings and input routing.
package io.github.grechucia.gwentreimagined;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Random;
import static io.github.grechucia.gwentreimagined.GameData.L;

/**
 * Base layer of the UI. The screens are split into layers like the Swift extensions:
 * SceneBase -> SceneMenus (title, cards, effects, gamepad focus) -> SceneBoard (match) -> SceneScreens (decks, builder, career) -> Scene (overlays).
 * Every method runs on the render thread with GameThread.LOCK held.
 */
abstract class SceneBase {
    static final float CARD_WIDTH = Virtual.CARD_WIDTH, CARD_HEIGHT = Virtual.CARD_HEIGHT;
    static final Random RANDOM = new Random();

    // MARK: Services
    final Renderer renderer;
    final Audio audio;
    GameHost host;
    GameData gameData() { return GameData.shared; }
    Career career() { return Career.shared; }
    String appVersion = "1.0.1";

    // MARK: Navigation
    /** Top-level screens. */
    enum Screen { TITLE, DECKS, GAME, BUILDER, CAREER }
    private Screen screen = Screen.TITLE;
    Screen screen() { return screen; }
    void setScreen(Screen next) {
        if (next != screen) { screen = next; audio.setMenuMode(next != Screen.GAME); if (padCursor) mouse = Vec2.NONE; }
    }
    boolean optionsOpen, rulesOpen, creditsOpen, savePromptOpen, langMenuOpen;
    /** Action to continue with after the save location has been chosen. */
    Runnable savePromptThen;

    // MARK: Time and input
    /** Seconds since the app started (drives animations). */
    float time;
    /** Duration of the current frame, zero while an overlay pauses the screen below. */
    float frameDelta = 1 / 60f;
    /** Pointer position in virtual coordinates; NONE when there is no pointer. */
    Vec2 mouse = Vec2.NONE;
    /** Pointer position normalised to -1...1, used for parallax. */
    Vec2 mouseNorm = new Vec2(0, 0);
    /** Accumulated scroll distance of the current frame. */
    float wheel;
    /** A clickable area registered while drawing. */
    static final class Hit { final Box rect; final Runnable action; Hit(Box rect, Runnable action) { this.rect = rect; this.action = action; } }
    /** Buttons registered while drawing this frame. */
    List<Hit> clicks = new ArrayList<>();
    /** Buttons of the previous frame; clicks are matched against these. */
    List<Hit> hits = new ArrayList<>();

    // MARK: Gamepad focus
    /** True while the game is controlled with a gamepad (the focused element is highlighted). */
    boolean padCursor;
    /** Elements that can never receive gamepad focus (e.g. web links). */
    final List<Box> padNoFocus = new ArrayList<>();
    /** Elements that are never focused automatically (e.g. Quit, Give up). */
    final List<Box> padNoAuto = new ArrayList<>();
    /** Element focused first on the current screen. */
    Box padPrimary;

    // MARK: Settings
    /** Performance mode: decorative animations (animated menu background, particles, weather effects) are skipped. */
    boolean lowDetail() { return host != null && host.performanceMode(); }
    /** Global AI difficulty for games outside the career (0 easy, 1 normal, 2 hard). */
    int aiLevel() { return host == null ? 1 : host.intSetting("aiLevel", 1); }
    void setAiLevel(int level) { if (host != null) host.setIntSetting("aiLevel", level); }
    String playerName() { String name = SaveStore.shared.getString("playerName"); return name == null || name.isEmpty() ? L("Player 1") : name; }
    /** Asks for the player's name and stores it in the save file. */
    void askPlayerName(Runnable then) {
        if (host == null) { if (then != null) then.run(); return; }
        String current = SaveStore.shared.getString("playerName");
        host.askText(L("What's your name?"), L("Your name is shown on the board. You can change it in Options."), L("Player 1"), current == null ? "" : current, text -> {
            if (text != null) { String name = text.trim(); SaveStore.shared.set("playerName", name.length() > 24 ? name.substring(0, 24) : name); }
            if (then != null) then.run();
        });
    }

    // MARK: Menu background
    /** Hover animation amount per card/tile key (0...1). */
    final Map<String, Float> cardHover = new HashMap<>();
    float hoverAmount(String key, boolean hovered, float speed) {
        float previous = cardHover.getOrDefault(key, 0f);
        float next = previous + ((hovered ? 1 : 0) - previous) * Math.min(1, speed);
        cardHover.put(key, next);
        return next;
    }

    // MARK: Deck selection
    List<DeckData> customDecks = DeckBuilder.loadCustom();
    List<DeckData> allDecks() { List<DeckData> all = new ArrayList<>(gameData().decks); all.addAll(customDecks); return all; }
    /** Deck used for quick play. */
    int myDeckIndex;
    /** Step of the deck selection flow: -1 start menu, 0 factions, 1 decks. */
    int deckStage = -1;
    String selectedFaction = "realms";
    /** Progress (0...1) of the transition animation between deck selection steps. */
    float deckTransition = 1;
    /** Deck shown in the read-only preview, if any. */
    Integer previewDeck;
    final float[] previewScroll = {0, 0};
    Integer favoriteDeckIndex() {
        String stored = SaveStore.shared.getString("favoriteDeck");
        if (stored == null || stored.length() < 2) return null;
        int deckIndex;
        try { deckIndex = Integer.parseInt(stored.substring(1)); } catch (NumberFormatException e) { return null; }
        int i = stored.startsWith("c") ? gameData().decks.size() + deckIndex : deckIndex;
        return i >= 0 && i < allDecks().size() ? i : null;
    }
    void setFavoriteDeckIndex(Integer i) {
        if (i == null) { SaveStore.shared.set("favoriteDeck", null); return; }
        int premade = gameData().decks.size();
        SaveStore.shared.set("favoriteDeck", i >= premade ? "c" + (i - premade) : "p" + i);
    }

    // MARK: Deck builder
    DeckBuilder builder = new DeckBuilder();
    /** Card under the pointer in menus and the builder (shown in the large preview). */
    Card builderHover;
    /** Time left for the "Deck saved" message. */
    float builderSavedTimer;
    /** Card type filter of the collection (0 = all). */
    int builderFilter;
    boolean leaderPickerOpen;
    /** A card flying between the collection and the deck after a click. */
    static final class FlyCard { final CardData cardData; final Box from, to; float progress; FlyCard(CardData d, Box from, Box to) { cardData = d; this.from = from; this.to = to; } }
    final List<FlyCard> flyCards = new ArrayList<>();
    final float[] collectionScroll = {0, 0}, deckScroll = {0, 0};

    // MARK: Career
    /** Index of the career fight being played, if any. */
    Integer careerFight;
    /** Reward cards offered after a won fight. */
    List<String> careerRewards;
    /** Leader unlocked by beating a boss. */
    String careerNewLeader;
    /** Chapter selected in the career ladder. */
    Integer careerChapter;
    boolean careerConfirmReset;
    /** Difficulty selected on the new-career screen. */
    int careerDifficultyChoice = 1;
    /** Opponent name shown on the board during a career fight. */
    String careerFightName;

    // MARK: Match
    Game game;
    /** Card selected in the hand. */
    Card selected;
    /** Card under the pointer on the board. */
    Card hover;
    /** Cards chosen so far in a multi-card choice. */
    final List<Card> multiSelection = new ArrayList<>();
    /** Tooltip text shown next to the pointer. */
    String hoverText;
    /** Queued notification banner. */
    static final class Note { final String text, icon; Note(String text, String icon) { this.text = text; this.icon = icon; } }
    final List<Note> notes = new ArrayList<>();
    float noteTimer;
    /** Delay before the computer makes its move. */
    float computerTurnTimer;
    /** Time left to confirm "Exit to menu". */
    float exitConfirmTimer;
    float rulesScroll;

    // MARK: Automated tests
    boolean autotest;
    float autotestTimer;
    int gamesPlayed;
    void log(String line) { android.util.Log.i("GwentTest", line); }

    SceneBase(Renderer renderer, Audio audio) {
        this.renderer = renderer; this.audio = audio;
        for (int i = 0; i < gameData().decks.size(); i++) if (gameData().decks.get(i).faction.equals("realms")) { myDeckIndex = i; break; }
        audio.preload(Audio.PRELOAD.toArray(new String[0]));
    }

    /** Updates the pointer position (virtual coordinates). */
    void mouseMoved(Vec2 point) { mouse = point; mouseNorm = new Vec2((point.x / Virtual.WIDTH - 0.5f) * 2, (point.y / Virtual.HEIGHT - 0.5f) * 2); }
    /** Runs the topmost button under the point. */
    void click(Vec2 point) {
        mouse = point;
        for (int i = hits.size() - 1; i >= 0; i--) if (hits.get(i).rect.contains(point)) { hits.get(i).action.run(); return; }
    }
    /** Long press: cancels the selection. */
    void rightClick() { selected = null; }
    /** Scroll wheel or drag. */
    void scroll(float delta) { wheel += delta; }
    /** Back key (the Esc key of the desktop version): closes overlays and cancels choices. Returns false when there was nothing to close. */
    boolean back() {
        if (rulesOpen) { closeRules(); return true; }
        if (creditsOpen) { creditsOpen = false; if (game != null) game.paused = false; return true; }
        if (langMenuOpen) { langMenuOpen = false; return true; }
        if (leaderPickerOpen) { leaderPickerOpen = false; return true; }
        if (savePromptOpen && SaveStore.shared.chosen()) { savePromptOpen = false; savePromptThen = null; return true; }
        if (optionsOpen) { optionsOpen = false; if (game != null) game.paused = false; return true; }
        if (screen == Screen.DECKS && previewDeck != null) { previewDeck = null; deckTransition = 0; return true; }
        if (screen == Screen.DECKS && deckStage >= 0) { deckStage -= 1; deckTransition = 0; return true; }
        if (screen == Screen.DECKS) { setScreen(Screen.TITLE); return true; }
        if (screen == Screen.BUILDER) { setScreen(builder.careerMode() ? Screen.CAREER : Screen.DECKS); return true; }
        if (screen == Screen.CAREER) { deckStage = -1; deckTransition = 0; setScreen(Screen.DECKS); return true; }
        if (game != null && game.choice != null && game.choice.canCancel) { multiSelection.clear(); selected = null; game.resolveChoice(null); return true; }
        if (selected != null) { selected = null; return true; }
        if (screen == Screen.GAME) { optionsOpen = true; if (game != null) game.paused = true; return true; }
        return false;
    }

    /** Draws one frame of the current screen and overlays. */
    void frame(float dt) {
        time += dt;
        hits = clicks; clicks = new ArrayList<>();
        padNoFocus.clear(); padNoAuto.clear(); padPrimary = null;
        boolean overlay = rulesOpen || creditsOpen || optionsOpen || savePromptOpen;
        frameDelta = overlay ? 0 : dt;
        switch (screen) {
            case TITLE: drawTitle(frameDelta); break;
            case DECKS: drawDeckSelect(frameDelta); break;
            case GAME: drawGame(frameDelta); break;
            case BUILDER: drawBuilder(builder, frameDelta); break;
            case CAREER: drawCareer(frameDelta); break;
        }
        if (rulesOpen) { clicks.clear(); drawRules(); }
        else if (creditsOpen) { clicks.clear(); drawCredits(); }
        else if (savePromptOpen) { clicks.clear(); drawSavePrompt(); }
        else if (optionsOpen) { clicks.clear(); drawOptions(); }
        drawPadCursor();
        wheel = 0;
    }
    /** Registers a clickable area for this frame (immediate-mode UI). */
    void button(Box rect, Runnable action) { clicks.add(new Hit(rect, action)); }

    // Screens implemented by the later layers.
    abstract void drawTitle(float dt);
    abstract void drawDeckSelect(float dt);
    abstract void drawGame(float dt);
    abstract void drawBuilder(DeckBuilder builder, float dt);
    abstract void drawCareer(float dt);
    abstract void drawRules();
    abstract void drawCredits();
    abstract void drawSavePrompt();
    abstract void drawOptions();
    abstract void drawPadCursor();
    abstract void openRules();
    abstract void closeRules();
    abstract void askSaveLocation(Runnable then);
    abstract void languageToggle(float y);

    static Box box(float x, float y, float w, float h) { return new Box(x, y, w, h); }
    /** Smoothstep easing used for UI animations. */
    static float ease(float value) { float x = Math.max(0, Math.min(1, value)); return x * x * (3 - 2 * x); }
    static float fract(float x) { return x - (float) Math.floor(x); }
    static float sin(float x) { return (float) Math.sin(x); }
    static float cos(float x) { return (float) Math.cos(x); }
    static float rand(float lo, float hi) { return lo + RANDOM.nextFloat() * (hi - lo); }

    /** Main gold-framed button. */
    void goldButton(Box area, String title, Font font, boolean enabled, Runnable action) {
        boolean hovered = area.contains(mouse) && enabled;
        renderer.gradient(area, Theme.INK.alpha(0.95f), Theme.PANEL_DARK.alpha(0.96f), 12);
        if (hovered) renderer.rect(area.inset(-6), Theme.GLOW.alpha(0.10f));
        renderer.frame(area, RGBA.GOLD_DARK.alpha(enabled ? 1 : 0.4f), 2);
        renderer.frame(area.inset(5), RGBA.GOLD_DARK.alpha(hovered ? 0.95f : 0.55f), 1);
        float textHeight = renderer.measure(title, font)[1];
        renderer.text(title, font, area.mid().x, area.mid().y - textHeight / 2 + 1, enabled ? (hovered ? Theme.CREAM : Theme.TEXT_GOLD) : RGBA.gray(0.5f), Align.CENTER);
        if (enabled) button(area, action);
    }
    void goldButton(Box area, String title, Font font, Runnable action) { goldButton(area, title, font, true, action); }
    void goldButton(Box area, String title, Runnable action) { goldButton(area, title, Font.serif(26, true), true, action); }

    /** Smaller gold button that shrinks its font to fit. */
    void smallButton(Box area, String title, boolean enabled, Runnable action) {
        Font fitted = Font.serif(21, true);
        while (renderer.measure(title, fitted)[0] > area.w - 18 && fitted.size > 11) fitted = Font.serif(fitted.size - 1, true);
        goldButton(area, title, fitted, enabled, action);
    }

    /** Starts a match with the given decks (random opponent deck if none). */
    void startGame(DeckData deck, DeckData against, Integer careerFightIndex) {
        List<DeckData> decks = gameData().decks;
        if (autotest) myDeckIndex = RANDOM.nextInt(decks.size());
        List<DeckData> all = allDecks();
        DeckData mine = deck != null ? deck : all.get(Math.min(myDeckIndex, all.size() - 1));
        List<Integer> others = new ArrayList<>();
        for (int i = 0; i < decks.size(); i++) if (i != myDeckIndex) others.add(i);
        DeckData theirs = against != null ? against : decks.get(others.isEmpty() ? 0 : others.get(RANDOM.nextInt(others.size())));
        if (game != null) game.abandon();
        careerFight = careerFightIndex;
        if (careerFightIndex == null) careerFightName = null;
        game = new Game(mine, theirs);
        game.aiLevel = careerFightIndex != null ? Math.max(0, career().difficulty - 1) : aiLevel();
        game.autoHuman = autotest;
        log("GAME " + (gamesPlayed + 1) + ": " + mine.faction + " vs " + theirs.faction + ", AI level " + game.aiLevel);
        selected = null; notes.clear(); noteTimer = 0; computerTurnTimer = 0;
        setScreen(Screen.GAME);
        audio.play("game_start");
    }
    void startGame() { startGame(null, null, null); }
    void startGame(DeckData deck) { startGame(deck, null, null); }
}

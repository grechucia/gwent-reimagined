// Overlays drawn above every screen: Options, rules, licenses and the save-location prompt.
package io.github.grechucia.gwentreimagined;

import java.util.List;
import java.util.function.IntConsumer;
import static io.github.grechucia.gwentreimagined.GameData.L;

/** The complete UI scene. */
final class Scene extends SceneScreens {
    Scene(Renderer renderer, Audio audio) { super(renderer, audio); }

    // MARK: Options

    static final int[] RESOLUTIONS = {0, 720, 1080};
    private float optionsY;

    /** Draws a row label in Options. */
    private void optionLabel(Box panel, String text) { renderer.text(text, Font.serif(22, true), panel.x + 60, optionsY + 10, RGBA.WHITE, 340); }
    /** Draws a row of toggle buttons in Options; the selected one is highlighted. */
    private void optionChoice(Box panel, String[] titles, boolean[] selected, float width, IntConsumer act) {
        float bx = panel.x + 420;
        for (int i = 0; i < titles.length; i++) {
            Box area = box(bx + i * (width + 10), optionsY, width, 46);
            int index = i;
            goldButton(area, (selected[i] ? "✓ " : "") + titles[i], Font.serif(17, true), true, () -> act.accept(index));
            if (selected[i]) { renderer.rect(area, Theme.GLOW.alpha(0.22f)); renderer.frame(area.inset(-3), Theme.HIGHLIGHT_GOLD, 3); }
        }
    }

    /** Options overlay: player name, audio, graphics, difficulty, save location and language. */
    @Override void drawOptions() {
        renderer.rect(renderer.visibleRect, RGBA.BLACK.alpha(0.82f));
        Box panel = ScreenLayout.OPTIONS_PANEL;
        glassPanel(panel, 0.96f);
        renderer.text(L("Options"), Font.gwent(52), 960, panel.y + 24, RGBA.GOLD, Align.CENTER);
        goldButton(ScreenLayout.BACK_BUTTON, "‹  " + L("Back"), Font.serif(22, true), () -> { optionsOpen = false; if (game != null) game.paused = false; });
        goldButton(box(panel.x + panel.w - 250, panel.y + 30, 210, 46), L("Licenses"), Font.serif(18, true), () -> creditsOpen = true);
        optionsY = panel.y + 110;
        float bx = panel.x + 420;
        optionLabel(panel, L("Player name"));
        renderer.text(playerName(), Font.serif(22, true), bx, optionsY + 10, RGBA.GOLD, 380);
        goldButton(box(bx + 400, optionsY, 200, 46), L("Change…"), Font.serif(17, true), () -> askPlayerName(null));
        optionsY += 76;
        optionLabel(panel, L("Music"));
        optionChoice(panel, new String[]{L("On"), L("Off")}, new boolean[]{audio.musicOn() && !audio.muted, !audio.musicOn() || audio.muted}, 140, i -> {
            if (i == 0) { audio.muted = false; audio.setMusicOn(true); } else audio.setMusicOn(false);
        });
        optionsY += 76;
        optionLabel(panel, L("Sound effects"));
        optionChoice(panel, new String[]{L("On"), L("Off")}, new boolean[]{!audio.muted, audio.muted}, 140, i -> {
            audio.muted = i == 1; if (i == 1) audio.setMusicOn(false);
        });
        optionsY += 76;
        GameHost h = host;
        if (h != null) {
            optionLabel(panel, L("Performance mode"));
            boolean performance = h.performanceMode();
            optionChoice(panel, new String[]{L("On"), L("Off")}, new boolean[]{performance, !performance}, 140, i -> h.setPerformanceMode(i == 0));
            renderer.text(L("For older devices: no background animations, resolution adjusts to keep the frame rate."), Font.ui(15), bx + 310, optionsY + 2, RGBA.gray(0.75f), 420);
            optionsY += 76;
            optionLabel(panel, L("Render resolution"));
            if (performance) {
                renderer.text(L("Automatic") + ": " + h.automaticRenderHeight() + "p", Font.serif(20, true), bx, optionsY + 10, RGBA.GOLD);
                optionsY += 76;
            } else {
            String[] titles = new String[RESOLUTIONS.length]; boolean[] chosen = new boolean[RESOLUTIONS.length];
            for (int i = 0; i < RESOLUTIONS.length; i++) { titles[i] = RESOLUTIONS[i] == 0 ? L("Native") : RESOLUTIONS[i] + "p"; chosen[i] = RESOLUTIONS[i] == h.renderRes(); }
            optionChoice(panel, titles, chosen, 128, i -> h.setRenderRes(RESOLUTIONS[i]));
            optionsY += 76;
            }
            optionLabel(panel, L("Frame limit"));
            List<Integer> rates = h.availableFrameLimits();
            String[] rateTitles = new String[rates.size()]; boolean[] rateChosen = new boolean[rates.size()];
            for (int i = 0; i < rates.size(); i++) { rateTitles[i] = rates.get(i) + " FPS"; rateChosen[i] = rates.get(i) == h.effectiveFrameLimit(); }
            optionChoice(panel, rateTitles, rateChosen, 128, i -> h.setFrameLimit(rates.get(i)));
            optionsY += 76;
        }
        optionLabel(panel, L("Save location"));
        renderer.text(SaveStore.shared.chosen() ? SaveStore.shared.displayPath() : L("not chosen yet"), Font.ui(15), bx, optionsY + 4, RGBA.gray(0.8f), 680);
        goldButton(box(bx, optionsY + 50, 200, 44), L("Change…"), Font.serif(17, true), () -> askSaveLocation(null));
        optionsY += 126;
        if (h != null) {
            optionLabel(panel, L("Scaling"));
            optionChoice(panel, new String[]{L("Fill screen"), "16:9"}, new boolean[]{h.fillScreen(), !h.fillScreen()}, 180, i -> h.setFillScreen(i == 0));
            optionsY += 76;
        }
        optionLabel(panel, L("Difficulty (outside career)"));
        int level = aiLevel();
        optionChoice(panel, new String[]{L("Easy"), L("Normal"), L("Hard")}, new boolean[]{level == 0, level == 1, level == 2}, 180, this::setAiLevel);
        optionsY += 76;
        optionLabel(panel, L("Language"));
        languageToggle(optionsY + 6);
    }

    // MARK: Rules

    /** Opens the rules screen. */
    @Override void openRules() { rulesOpen = true; rulesScroll = 0; if (game != null) game.paused = true; }
    /** Closes the rules screen. */
    @Override void closeRules() { rulesOpen = false; if (game != null) game.paused = false; }

    /** Rules screen. */
    @Override void drawRules() {
        renderer.rect(renderer.visibleRect, RGBA.BLACK.alpha(0.82f));
        Box panel = ScreenLayout.RULES_PANEL;
        renderer.gradient(panel, new RGBA(0.13f, 0.1f, 0.06f, 0.98f), Theme.PANEL_DARK.alpha(0.98f), 12);
        renderer.frame(panel, RGBA.GOLD_DARK, 2);
        renderer.frame(panel.inset(6), RGBA.GOLD_DARK.alpha(0.4f), 1);
        renderer.text(L("Rules of Gwent"), Font.gwent(48), 960, 22, RGBA.GOLD, Align.CENTER);
        goldButton(ScreenLayout.BACK_BUTTON, "‹  " + L("Back"), Font.serif(22, true), this::closeRules);
        Box content = box(panel.x + 50, panel.y + 30, panel.w - 100, panel.h - 60);
        List<RulesBlock> blocks = gameData().rules();
        float[] heights = new float[blocks.size()];
        float total = 0;
        for (int i = 0; i < blocks.size(); i++) {
            RulesBlock block = blocks.get(i);
            heights[i] = block.heading ? renderer.measure(block.text, Font.gwent(30), content.w)[1] + 18 : renderer.measure(block.text, Font.serif(21), content.w)[1] + 16;
            total += heights[i];
        }
        float maxScroll = Math.max(0, total - content.h);
        rulesScroll = Math.max(0, Math.min(maxScroll, rulesScroll - wheel));
        renderer.clip(content);
        float y = content.y - rulesScroll;
        for (int i = 0; i < blocks.size(); i++) {
            RulesBlock block = blocks.get(i);
            float h = heights[i];
            if (y + h >= content.y && y <= content.y + content.h) {
                if (block.heading) {
                    renderer.text(block.text, Font.gwent(30), content.x, y + 10, RGBA.GOLD, content.w);
                    renderer.rect(box(content.x, y + h - 6, Math.min(content.w, 520), 1.5f), RGBA.GOLD_DARK.alpha(0.6f));
                } else renderer.text(block.text, Font.serif(21), content.x, y, Theme.PARCHMENT, content.w);
            }
            y += h;
        }
        renderer.clip(null);
        if (maxScroll > 0) {
            float thumb = content.h * content.h / total;
            renderer.rect(box(panel.x + panel.w - 14, content.y + (content.h - thumb) * rulesScroll / maxScroll, 5, thumb), RGBA.GOLD.alpha(0.6f));
        }
    }

    // MARK: Licenses

    private float creditsY;
    /** Draws the licenses and credits. */
    @Override void drawCredits() {
        renderer.rect(renderer.visibleRect, RGBA.BLACK.alpha(0.85f));
        Box panel = ScreenLayout.LICENSES_PANEL;
        glassPanel(panel, 0.95f);
        renderer.text(L("Licenses"), Font.gwent(52), 960, 24, RGBA.GOLD, Align.CENTER);
        goldButton(ScreenLayout.BACK_BUTTON, "‹  " + L("Back"), Font.serif(22, true), () -> { creditsOpen = false; if (game != null) game.paused = false; });
        float x = panel.x + 60, w = panel.w - 120;
        creditsY = panel.y + 40;
        creditsHead(x, w, L("Rights holder: CD PROJEKT RED"));
        creditsPara(x, w, L("All characters, the Witcher universe, Gwent, names, card art, music, sounds and trademarks are the property of CD PROJEKT S.A. / CD PROJEKT RED. The Witcher 3: Wild Hunt © CD PROJEKT S.A."), Theme.PARCHMENT);
        creditsPara(x, w, "This is an unofficial fan work and is not approved/endorsed by CD PROJEKT RED.", new RGBA(1, 0.9f, 0.6f, 1));
        creditsPara(x, w, L("The project is non-commercial and free. CD PROJEKT RED Fan Content Guidelines:"), RGBA.gray(0.7f));
        creditsLink(x, w, "cdprojektred.com/en/fan-content", "https://www.cdprojektred.com/en/fan-content");
        creditsY += 10;
        creditsHead(x, w, L("Fork of Gwent Classic v5.0"));
        creditsPara(x, w, L("This app is a fork of the open-source Gwent Classic v5.0 project from GitHub (authors: Arun Sundaram, Reynolds Costa, Sylver, Iván Mtz; version 5.0: ia2904)."), Theme.PARCHMENT);
        creditsLink(x, w, L("Original: Gwent Classic (Arun Sundaram)"), "https://github.com/asundr/gwent-classic");
        creditsLink(x, w, "github.com/ia2904/gwent-classic-v5.0", "https://github.com/ia2904/gwent-classic-v5.0");
        creditsLink(x, w, L("License (MIT + Commons Clause)"), "https://github.com/ia2904/gwent-classic-v5.0?tab=License-1-ov-file");
        creditsPara(x, w, "“Commons Clause” License Condition v1.0 — " + L("the license does not grant the right to sell the Software. Software: Gwent Classic · License: MIT · Licensor: Arun Sundaram."), RGBA.gray(0.75f));
        creditsY += 10;
        creditsHead(x, w, L("Port"));
        creditsPara(x, w, "Reimagined / ported by grechucia. " + L("Port code under the same license (MIT + Commons Clause)."), Theme.PARCHMENT);
        creditsLink(x, w, "github.com/grechucia/gwent-reimagined", "https://github.com/grechucia/gwent-reimagined");
    }
    /** Section heading of the licenses screen. */
    private void creditsHead(float x, float w, String text) {
        creditsY += renderer.text(text, Font.gwent(30), x, creditsY, RGBA.GOLD, w)[1] + 4;
        goldDivider(x, creditsY, Math.min(w, 600));
        creditsY += 14;
    }
    /** Paragraph of the licenses screen. */
    private void creditsPara(float x, float w, String text, RGBA color) { creditsY += renderer.text(text, Font.serif(19), x, creditsY, color, w)[1] + 10; }
    /** Clickable link of the licenses screen. */
    private void creditsLink(float x, float w, String text, String url) {
        float[] size = renderer.measure(text, Font.serif(19, true), w);
        Box area = box(x, creditsY, size[0], size[1]);
        boolean hovered = area.contains(mouse);
        renderer.text(text, Font.serif(19, true), x, creditsY, hovered ? RGBA.WHITE : Theme.LINK_BLUE, w);
        renderer.rect(box(x, creditsY + size[1] - 2, size[0], 1), Theme.LINK_BLUE.alpha(hovered ? 1 : 0.6f));
        padNoFocus.add(area);
        button(area, () -> { if (host != null) host.openURL(url); });
        creditsY += size[1] + 12;
    }

    // MARK: Save location

    /** Opens the save-location prompt, then runs `then`. */
    @Override void askSaveLocation(Runnable then) { savePromptOpen = true; savePromptThen = then; }

    /** Save-location prompt: this device or a folder chosen with the system picker. */
    @Override void drawSavePrompt() {
        renderer.rect(renderer.visibleRect, RGBA.BLACK.alpha(0.82f));
        Box area = ScreenLayout.SAVE_PROMPT_PANEL;
        glassPanel(area, 0.96f);
        renderer.text(L("Where should your progress be saved?"), Font.gwent(44), 960, area.y + 30, RGBA.GOLD, Align.CENTER);
        renderer.text(L("Your decks and career are kept in one file. Choose a location – you can change it later in Options."),
            Font.serif(19, false, true), 960, area.y + 96, RGBA.gray(0.88f), area.w - 120, Align.CENTER);
        String[] titles = {L("On this device"), L("Choose a folder…")};
        String[] descriptions = {L("Local save in the app's storage. The simplest choice if you only play on this device."),
            L("E.g. a network drive, Dropbox or Google Drive – useful if you also want to sync with Android.")};
        Runnable[] actions = {() -> { SaveStore.shared.chooseLocal(); finishSaveChoice(); }, () -> {
            if (host != null) host.pickFolder(chosen -> { if (chosen) finishSaveChoice(); });
        }};
        for (int i = 0; i < titles.length; i++) {
            Box option = box(area.x + 80, area.y + 180 + i * 170, area.w - 160, 140);
            boolean hovered = option.contains(mouse);
            renderer.rect(option, RGBA.BLACK.alpha(hovered ? 0.5f : 0.32f)); renderer.frame(option, RGBA.GOLD.alpha(hovered ? 1 : 0.5f), hovered ? 2.5f : 1.5f);
            renderer.text(titles[i], Font.serif(28, true), option.x + 30, option.y + 22, hovered ? RGBA.WHITE : RGBA.GOLD);
            renderer.text(descriptions[i], Font.ui(18), option.x + 30, option.y + 72, RGBA.gray(0.88f), option.w - 60);
            button(option, actions[i]);
        }
        if (SaveStore.shared.chosen()) {
            renderer.text(L("Currently") + ": " + SaveStore.shared.displayPath(), Font.ui(15), 960, area.y + area.h - 70, RGBA.gray(0.7f), area.w - 100, Align.CENTER);
            smallLink(box(960 - 120, area.y + area.h - 44, 240, 32), L("Cancel"), () -> { savePromptOpen = false; savePromptThen = null; });
        }
    }

    /** Reloads saved data from the chosen location and continues. */
    void finishSaveChoice() {
        Career.shared.load(); customDecks = DeckBuilder.loadCustom();
        savePromptOpen = false;
        Runnable pending = savePromptThen; savePromptThen = null;
        if (pending != null) pending.run();
    }
}

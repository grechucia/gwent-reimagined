// Deck selection (start menu, factions, decks, preview), the deck builder with its leader picker, and the career screens.
package io.github.grechucia.gwentreimagined;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.function.Predicate;
import static io.github.grechucia.gwentreimagined.GameData.L;

/** Menu screens between the title screen and a match. */
abstract class SceneScreens extends SceneBoard {
    SceneScreens(Renderer renderer, Audio audio) { super(renderer, audio); }

    // MARK: Deck selection

    /** Deck selection flow: start step, faction step and deck step. */
    @Override void drawDeckSelect(float dt) {
        drawMenuBackground(dt, 0.66f);
        deckTransition = Math.min(1, deckTransition + dt / 0.5f);
        if (previewDeck != null && previewDeck < allDecks().size()) drawDeckPreview(previewDeck, dt);
        else if (deckStage < 0) drawStartStep();
        else if (deckStage == 0) drawFactionStep(dt);
        else drawDeckStep(dt);
        if (previewDeck == null) languageToggle(1018);
        if (builderHover != null) drawPreviewRight(builderHover, previewDeck != null ? 110 : 1580);
        builderHover = null;
    }
    /** Header shown above each deck selection step. */
    void stepHeader(int step, String title, String hint) {
        renderer.text(L("Step") + " " + step + " / 2", Font.ui(16, true), 960, 22, RGBA.GOLD.alpha(0.8f), Align.CENTER);
        renderer.text(title, Font.gwent(52), 960, 44, RGBA.GOLD, Align.CENTER);
        renderer.text(hint, Font.serif(19, false, true), 960, 112, RGBA.gray(0.85f), Align.CENTER);
    }
    /** Highlighted big panel used on the start step. */
    void startPanel(Box panel, float progress, String title) {
        boolean hovered = panel.contains(mouse);
        if (hovered) renderer.quad(renderer.glow, box(panel.x - 50, panel.y - 50, panel.w + 100, panel.h + 100), Theme.GLOW.alpha(0.25f));
        glassPanel(panel, 0.75f * progress);
        renderer.frame(panel, RGBA.GOLD.alpha(hovered ? 0.9f : 0.4f), 1.5f);
        renderer.text(title, Font.gwent(40), panel.mid().x, panel.y + 26, RGBA.GOLD.alpha(progress), Align.CENTER);
    }

    /** First step: My deck, Career or Choose a faction. */
    void drawStartStep() {
        renderer.text(L("How do you want to play?"), Font.gwent(52), 960, 44, RGBA.GOLD, Align.CENTER);
        renderer.text(L("Play your own deck with one click, or choose a faction."), Font.serif(19, false, true), 960, 112, RGBA.gray(0.85f), Align.CENTER);
        goldButton(ScreenLayout.BACK_BUTTON, "‹  " + L("Back"), Font.serif(22, true), () -> setScreen(Screen.TITLE));
        float progress = ease(deckTransition * 1.4f);
        Box myDeckPanel = box(110, 170 + (1 - progress) * 24, 540, 780);
        startPanel(myDeckPanel, progress, "★ " + L("My deck"));
        Integer favorite = favoriteDeckIndex();
        if (favorite != null) {
            int i = favorite;
            DeckData deck = allDecks().get(i);
            CardData leaderData = gameData().cards.get(deck.leader);
            if (leaderData != null) {
                Box cardRect = box(myDeckPanel.mid().x - 135, myDeckPanel.y + 90, 270, 270 / 0.697f);
                drawCardLarge(new Card(leaderData, null), cardRect);
                if (cardRect.contains(mouse)) builderHover = new Card(leaderData, null);
            }
            String subtitle = i >= gameData().decks.size() ? gameData().ui(deck.title) : gameData().factionName(deck.faction);
            renderer.text(subtitle, Font.serif(20, true), myDeckPanel.mid().x, myDeckPanel.y + 90 + 270 / 0.697f + 14, RGBA.WHITE.alpha(progress), myDeckPanel.w - 60, Align.CENTER);
            goldButton(box(myDeckPanel.x + 70, myDeckPanel.y + myDeckPanel.h - 130, myDeckPanel.w - 140, 64), L("Play my deck"), Font.serif(26, true), () -> { myDeckIndex = i; startGame(deck); });
            smallLink(box(myDeckPanel.x + 70, myDeckPanel.y + myDeckPanel.h - 56, (myDeckPanel.w - 140) / 2, 32), L("View cards"), () -> {
                selectedFaction = deck.faction; deckStage = 1; previewDeck = i; previewScroll[0] = 0; previewScroll[1] = 0; deckTransition = 0; });
            smallLink(box(myDeckPanel.mid().x, myDeckPanel.y + myDeckPanel.h - 56, (myDeckPanel.w - 140) / 2, 32), L("Change deck"), () -> { deckStage = 0; deckTransition = 0; });
        } else {
            renderer.text("☆", Font.gwent(140), myDeckPanel.mid().x, myDeckPanel.y + 150, RGBA.GOLD.alpha(0.5f * progress), Align.CENTER);
            renderer.text(L("You haven't picked your deck yet."), Font.serif(24, true), myDeckPanel.mid().x, myDeckPanel.y + 360, RGBA.WHITE.alpha(progress), myDeckPanel.w - 80, Align.CENTER);
            renderer.text(L("Choose a faction, then click “☆ Set as my deck” under the deck you like. From then on you can play it with one click."),
                Font.ui(18), myDeckPanel.mid().x, myDeckPanel.y + 410, RGBA.gray(0.85f, progress), myDeckPanel.w - 100, Align.CENTER);
            goldButton(box(myDeckPanel.x + 70, myDeckPanel.y + myDeckPanel.h - 130, myDeckPanel.w - 140, 64), L("Pick your deck"), Font.serif(24, true), () -> { deckStage = 0; deckTransition = 0; });
        }
        Box careerPanel = box(690, 170 + (1 - ease(deckTransition * 1.4f - 0.1f)) * 24, 540, 780);
        startPanel(careerPanel, progress, "⚔ " + L("Career"));
        Career career = career();
        if (career.active()) {
            renderer.image("img/icons/deck_shield_" + career.faction + ".png", box(careerPanel.mid().x - 60, careerPanel.y + 110, 120, 134), RGBA.WHITE.alpha(progress));
            renderer.text(gameData().factionName(career.faction), Font.gwent(30), careerPanel.mid().x, careerPanel.y + 262, RGBA.GOLD.alpha(progress), Align.CENTER);
            CareerChapter chapter = career.chapter(career.currentChapter());
            renderer.text(L("Chapter") + " " + (career.currentChapter() + 1) + "/" + career.chapterCount() + ": " + chapter.title, Font.serif(22, true), careerPanel.mid().x, careerPanel.y + 320, RGBA.WHITE.alpha(progress), careerPanel.w - 60, Align.CENTER);
            renderer.text(L("Opponents defeated") + ": " + career.beaten.size() + "/" + career.totalFights(), Font.ui(18), careerPanel.mid().x, careerPanel.y + 362, RGBA.gray(0.85f, progress), Align.CENTER);
            Box bar = box(careerPanel.x + 70, careerPanel.y + 400, careerPanel.w - 140, 8);
            renderer.rect(bar, RGBA.WHITE.alpha(0.12f));
            renderer.rect(box(bar.x, bar.y, bar.w * Math.min(1, (float) career.beaten.size() / career.totalFights()), bar.h), RGBA.GOLD);
        } else {
            renderer.text("⚔", Font.gwent(130), careerPanel.mid().x, careerPanel.y + 130, RGBA.GOLD.alpha(0.5f * progress), Align.CENTER);
            renderer.text(L("Start with weak cards, win new ones and defeat boss after boss. Every career is generated anew."),
                Font.ui(18), careerPanel.mid().x, careerPanel.y + 340, RGBA.gray(0.85f, progress), careerPanel.w - 90, Align.CENTER);
        }
        goldButton(box(careerPanel.x + 70, careerPanel.y + careerPanel.h - 130, careerPanel.w - 140, 64), career.active() ? L("Continue career") : L("Start career"),
            Font.serif(24, true), () -> { careerChapter = null; deckTransition = 0; setScreen(Screen.CAREER); });
        Box factionPanel = box(1270, 170 + (1 - ease(deckTransition * 1.4f - 0.2f)) * 24, 540, 780);
        boolean hoveredFactions = factionPanel.contains(mouse);
        startPanel(factionPanel, progress, L("Choose a faction"));
        List<String> factions = DeckBuilder.FACTIONS_ORDER;
        for (int index = 0; index < factions.size(); index++) {
            int col = index % 5, row = index / 5;
            Box area = box(factionPanel.x + 34 + col * 96, factionPanel.y + 110 + row * 116, 78, 87);
            renderer.image("img/icons/deck_shield_" + factions.get(index) + ".png", area, RGBA.WHITE.alpha(progress * (hoveredFactions ? 1 : 0.85f)));
        }
        renderer.text(L("Pick one of 15 factions and one of its decks, or build your own."),
            Font.ui(18), factionPanel.mid().x, factionPanel.y + 520, RGBA.gray(0.85f, progress), factionPanel.w - 100, Align.CENTER);
        goldButton(box(factionPanel.x + 70, factionPanel.y + factionPanel.h - 130, factionPanel.w - 140, 64), L("Choose a faction"), Font.serif(26, true), () -> { deckStage = 0; deckTransition = 0; });
    }

    /** Faction grid. */
    void drawFactionStep(float dt) {
        stepHeader(1, L("Choose a faction"), L("Click the faction you want to play."));
        goldButton(ScreenLayout.BACK_BUTTON, "‹  " + L("Back"), Font.serif(22, true), () -> { deckStage = -1; deckTransition = 0; });
        List<String> factions = DeckBuilder.FACTIONS_ORDER;
        int cols = 5; float tw = 340, th = 250, gx = 22, gy = 22;
        float x0 = 960 - (cols * tw + (cols - 1) * gx) / 2, y0 = 160;
        List<DeckData> all = allDecks();
        for (int i = 0; i < factions.size(); i++) {
            String faction = factions.get(i);
            int col = i % cols, row = i / cols;
            float progress = ease(deckTransition * 1.6f - i * 0.04f);
            Box base = box(x0 + col * (tw + gx), y0 + row * (th + gy) + (1 - progress) * 24, tw, th);
            float amount = hoverAmount("fac2_" + faction, base.contains(mouse), dt * 10);
            Box area = box(base.x, base.y - 6 * amount, base.w, base.h);
            if (amount > 0.02f) renderer.quad(renderer.glow, box(area.x - 40, area.y - 40, area.w + 80, area.h + 80), Theme.GLOW.alpha(0.32f * amount));
            glassPanel(area, 0.72f * progress);
            renderer.frame(area, RGBA.GOLD.alpha(0.25f + 0.6f * amount), 1.5f + amount);
            renderer.image("img/icons/deck_shield_" + faction + ".png", box(area.x + 22, area.y + 22, 74, 82), RGBA.WHITE.alpha(progress));
            float nameHeight = renderer.text(gameData().factionName(faction), Font.gwent(30), area.x + 112, area.y + 30, RGBA.GOLD.alpha(progress), area.w - 126)[1];
            int deckCount = 0;
            for (DeckData d : all) if (d.faction.equals(faction)) deckCount++;
            renderer.text(deckCount == 1 ? L("1 deck") : deckCount + " " + L("decks"), Font.ui(15), area.x + 112, area.y + 34 + nameHeight, RGBA.gray(0.7f, progress));
            renderer.text(gameData().factionDesc(faction), Font.ui(16), area.x + 22, area.y + 122, Theme.PARCHMENT_TEXT.alpha(progress), area.w - 44);
            button(area, () -> { selectedFaction = faction; deckStage = 1; deckTransition = 0; audio.play("card", 0.5f); });
        }
    }

    /** Premade and custom decks of the chosen faction. */
    void drawDeckStep(float dt) {
        String faction = selectedFaction;
        stepHeader(2, L("Choose a deck"), gameData().factionName(faction) + " — " + L("click “Play this deck” under the deck you want."));
        goldButton(ScreenLayout.WIDE_BACK_BUTTON, "‹  " + L("Factions"), Font.serif(22, true), () -> { deckStage = 0; deckTransition = 0; });
        List<DeckData> all = allDecks();
        List<Integer> indices = new ArrayList<>();
        for (int i = 0; i < all.size(); i++) if (all.get(i).faction.equals(faction)) indices.add(i);
        int tileCount = indices.size() + 1;
        float gap = 26;
        float tileWidth = Math.min(300, (1780 - gap * (tileCount - 1)) / tileCount);
        float tileHeight = tileWidth / 0.697f;
        float x0 = 960 - (tileCount * tileWidth + (tileCount - 1) * gap) / 2, y0 = 170;
        Integer favorite = favoriteDeckIndex();
        for (int position = 0; position < indices.size(); position++) {
            int i = indices.get(position);
            DeckData deck = all.get(i);
            boolean custom = i >= gameData().decks.size();
            float progress = ease(deckTransition * 1.5f - position * 0.08f);
            float x = x0 + position * (tileWidth + gap);
            Box cardR = box(x, y0 + (1 - progress) * 30, tileWidth, tileHeight);
            Box tile = box(x - 10, cardR.y - 10, tileWidth + 20, tileHeight + 250);
            float amount = hoverAmount("deck_" + i, tile.contains(mouse), dt * 10);
            if (amount > 0.02f) renderer.quad(renderer.glow, box(tile.x - 50, tile.y - 50, tile.w + 100, tile.h + 100), Theme.GLOW.alpha(0.3f * amount));
            glassPanel(tile, 0.6f * progress);
            CardData leaderData = gameData().cards.get(deck.leader);
            if (leaderData != null) {
                Box lift = box(cardR.x, cardR.y - 8 * amount, cardR.w, cardR.h);
                drawCardLarge(new Card(leaderData, null), lift);
                renderer.rect(lift, RGBA.BLACK.alpha(1 - progress));
                if (lift.contains(mouse)) builderHover = new Card(leaderData, null);
            }
            float textY = cardR.y + tileHeight + 14;
            String title = gameData().ui(deck.title);
            if (custom || !title.equals(gameData().factionName(faction)))
                textY += renderer.text((custom ? "★ " : "") + title, Font.serif(20, true), x, textY, RGBA.WHITE.alpha(progress), tileWidth)[1] + 4;
            String desc;
            if (deck.description.isEmpty()) {
                List<String> abilities = leaderData != null ? leaderData.abilities : new ArrayList<>();
                desc = gameData().abilityDesc(abilities.isEmpty() ? "" : abilities.get(abilities.size() - 1));
            } else desc = gameData().ui(deck.description);
            renderer.clip(box(x, textY, tileWidth, 100));
            renderer.text(desc, Font.ui(16), x, textY, Theme.PARCHMENT_TEXT.alpha(progress), tileWidth);
            renderer.clip(null);
            int units = 0, total = 0;
            for (DeckEntry e : deck.cards) { total += e.count; CardData d = gameData().cards.get(e.key); if (d != null && d.isUnit()) units += e.count; }
            renderer.text(total + " " + L("cards") + " · " + units + " " + L("units"), Font.ui(14), x, tile.y + tile.h - 92, RGBA.GOLD.alpha(0.75f * progress));
            goldButton(box(x, tile.y + tile.h - 66, tileWidth, 52), L("Play this deck"), Font.serif(tileWidth < 260 ? 18 : 21, true), () -> { myDeckIndex = i; startGame(deck); });
            float buttonWidth = (tileWidth - 8) / 2, buttonY = tile.y + tile.h + 10, buttonFont = tileWidth < 260 ? 15 : 17;
            goldButton(box(x, buttonY, buttonWidth, 42), L("View cards"), Font.serif(buttonFont, true), () -> {
                previewDeck = i; previewScroll[0] = 0; previewScroll[1] = 0; deckTransition = 0; audio.play("card", 0.5f); });
            goldButton(box(x + buttonWidth + 8, buttonY, buttonWidth, 42), L("Edit deck"), Font.serif(buttonFont, true), () -> {
                builder = new DeckBuilder(); builder.load(deck, custom ? i - gameData().decks.size() : null); setScreen(Screen.BUILDER); });
            boolean isFavorite = favorite != null && favorite == i;
            Box favoriteRect = box(x, buttonY + 50, custom ? buttonWidth : tileWidth, 42);
            if (isFavorite) renderer.rect(favoriteRect, Theme.WOOD_BROWN.alpha(0.55f));
            goldButton(favoriteRect, isFavorite ? "★ " + L("My deck") : "☆ " + L("Set as mine"), Font.serif(buttonFont, true), () -> {
                setFavoriteDeckIndex(isFavorite ? null : i); audio.play("card", 0.5f); });
            if (custom) {
                goldButton(box(x + buttonWidth + 8, buttonY + 50, buttonWidth, 42), L("Delete deck"), Font.serif(buttonFont, true), () -> {
                    List<DeckData> decks = DeckBuilder.loadCustom(); int customIndex = i - gameData().decks.size();
                    if (customIndex >= 0 && customIndex < decks.size()) { decks.remove(customIndex); DeckBuilder.saveCustom(decks); }
                    customDecks = decks;
                });
            }
        }
        float x = x0 + indices.size() * (tileWidth + gap);
        float progress = ease(deckTransition * 1.5f - indices.size() * 0.08f);
        Box tile = box(x - 10, y0 - 10 + (1 - progress) * 30, tileWidth + 20, tileHeight + 250);
        boolean hovered = tile.contains(mouse);
        glassPanel(tile, 0.45f * progress);
        renderer.frame(tile.inset(14), RGBA.GOLD.alpha((hovered ? 0.9f : 0.35f) * progress), 1.5f);
        renderer.text("+", Font.gwent(120), tile.mid().x, tile.y + tileHeight * 0.28f, RGBA.GOLD.alpha((hovered ? 1 : 0.7f) * progress), Align.CENTER);
        renderer.text(L("Custom deck"), Font.serif(22, true), tile.mid().x, tile.y + tileHeight * 0.62f, RGBA.WHITE.alpha(progress), tileWidth - 20, Align.CENTER);
        renderer.text(L("Build a deck from this faction's cards in the deck builder."), Font.ui(15), tile.mid().x, tile.y + tileHeight * 0.62f + 34, RGBA.gray(0.75f, progress), tileWidth - 30, Align.CENTER);
        button(tile, () -> { builder = new DeckBuilder(); builder.newDeck(faction); setScreen(Screen.BUILDER); });
    }

    /** Read-only list of a deck's cards. */
    void drawDeckPreview(int i, float dt) {
        DeckData deck = allDecks().get(i);
        float progress = ease(deckTransition * 1.4f);
        renderer.text(L("Deck cards"), Font.gwent(52), 960, 34, RGBA.GOLD.alpha(progress), Align.CENTER);
        String title = gameData().ui(deck.title), factionName = gameData().factionName(deck.faction);
        renderer.text(factionName + (!title.equals(factionName) || i >= gameData().decks.size() ? " — " + title : ""), Font.serif(20, false, true), 960, 102, RGBA.gray(0.85f, progress), Align.CENTER);
        goldButton(ScreenLayout.DECK_BACK_BUTTON, "‹  " + L("Decks"), Font.serif(22, true), () -> { previewDeck = null; deckTransition = 0; });
        Box left = DeckPreviewLayout.INFO_PANEL;
        glassPanel(left, 0.7f * progress);
        CardData leaderData = gameData().cards.get(deck.leader);
        if (leaderData != null) {
            Box cardRect = box(left.x + 60, left.y + 30 + (1 - progress) * 20, 280, 280 / 0.697f);
            drawCardLarge(new Card(leaderData, null), cardRect);
            if (cardRect.contains(mouse)) builderHover = new Card(leaderData, null);
        }
        List<CardData> list = new ArrayList<>(); Map<String, Integer> counts = new HashMap<>();
        int units = 0, total = 0, specials = 0, heroes = 0, power = 0;
        for (DeckEntry e : deck.cards) {
            CardData d = gameData().cards.get(e.key);
            if (d == null) continue;
            if (!counts.containsKey(e.key)) list.add(d);
            counts.put(e.key, counts.getOrDefault(e.key, 0) + e.count); total += e.count;
            if (d.isUnit()) { units += e.count; power += d.strength * e.count; if (d.abilities.contains("hero")) heroes += e.count; } else specials += e.count;
        }
        list.sort((a, b) -> {
            int ka = a.isWeather() ? 1 : (a.isSpecial() ? 0 : 2), kb = b.isWeather() ? 1 : (b.isSpecial() ? 0 : 2);
            if (ka != kb) return Integer.compare(ka, kb);
            if (a.strength != b.strength) return Integer.compare(b.strength, a.strength);
            return a.name.compareTo(b.name);
        });
        float y = left.y + 30 + 280 / 0.697f + 24;
        String[] labels = {L("Total cards"), L("Units"), L("Special cards"), L("Heroes"), L("Total unit strength")};
        int[] values = {total, units, specials, heroes, power};
        for (int k = 0; k < labels.length; k++) {
            renderer.text(labels[k], Font.ui(17), left.x + 30, y, RGBA.gray(0.8f, progress));
            renderer.text(String.valueOf(values[k]), Font.ui(17, true), left.x + left.w - 30, y, RGBA.GOLD.alpha(progress), Align.RIGHT);
            y += 30;
        }
        Integer favorite = favoriteDeckIndex();
        boolean isFavorite = favorite != null && favorite == i;
        smallLink(box(left.x + 30, left.y + left.h - 122, left.w - 60, 32), isFavorite ? "★ " + L("My deck") : "☆ " + L("Set as my deck"), () -> {
            setFavoriteDeckIndex(isFavorite ? null : i); audio.play("card", 0.5f); });
        goldButton(box(left.x + 30, left.y + left.h - 76, left.w - 60, 56), L("Play this deck"), () -> { previewDeck = null; myDeckIndex = i; startGame(deck); });
        Box area = DeckPreviewLayout.CARDS_AREA;
        glassPanel(area, 0.55f * progress);
        builderGrid(list, area.inset(6), previewScroll, dt, 150, d -> counts.getOrDefault(d.key, 0), (d, from) -> {});
        renderer.text(L("Hover a card to see its description. Scroll with the mouse wheel."), Font.serif(17, false, true), area.mid().x, area.y + area.h + 14, RGBA.gray(0.7f, progress), Align.CENTER);
    }

    // MARK: Deck builder

    /** Deck builder screen: collection on the left, deck on the right, statistics in the middle. */
    @Override void drawBuilder(DeckBuilder builder, float dt) {
        drawMenuBackground(dt, 0.72f);
        if (leaderPickerOpen) { drawLeaderPicker(builder); return; }
        renderer.text(L("Deck builder"), Font.gwent(46), 960, 14, RGBA.GOLD, Align.CENTER);
        int factionIndex = Math.max(0, DeckBuilder.FACTIONS_ORDER.indexOf(builder.faction));
        renderer.quad(renderer.glow, box(960 - 240, 60, 100, 100), Theme.GLOW.alpha(0.3f));
        renderer.image("img/icons/deck_shield_" + builder.faction + ".png", box(960 - 212, 78, 44, 48));
        renderer.text(gameData().factionName(builder.faction), Font.serif(28, true), 960 - 155, 84, RGBA.WHITE);
        if (!builder.careerMode()) {
            int[] arrows = {-1, 1}; float[] xs = {960 - 280, 960 + 240};
            for (int k = 0; k < 2; k++) {
                int step = arrows[k];
                Box area = box(xs[k], 74, 40, 56);
                renderer.text(step < 0 ? "‹" : "›", Font.serif(60), area.mid().x, area.y - 18, area.contains(mouse) ? RGBA.WHITE : RGBA.GOLD, Align.CENTER);
                button(area, () -> {
                    int count = DeckBuilder.FACTIONS_ORDER.size();
                    builder.newDeck(DeckBuilder.FACTIONS_ORDER.get((factionIndex + step + count) % count));
                    collectionScroll[1] = 0; deckScroll[1] = 0;
                });
            }
        }
        renderer.text(gameData().factionDesc(builder.faction), Font.ui(16), 960, 134, RGBA.gray(0.78f), 900, Align.CENTER);
        Box colL = BuilderLayout.COLLECTION_COLUMN, colR = BuilderLayout.DECK_COLUMN;
        glassPanel(colL, 0.55f); glassPanel(colR, 0.55f);
        renderer.text(L("Card Collection"), Font.serif(22, true), colL.x + 14, 168, RGBA.GOLD);
        renderer.text(L("Cards in Deck"), Font.serif(22, true), colR.x + 14, 168, RGBA.GOLD);
        String[] filterNames = {L("All"), L("Melee"), L("Ranged"), L("Siege"), L("Hero"), L("Special")};
        List<Predicate<CardData>> filters = new ArrayList<>();
        filters.add(d -> true);
        filters.add(d -> d.isUnit() && d.row.contains("c") && (d.row.equals("close") || d.row.startsWith("agile")));
        filters.add(d -> d.isUnit() && (d.row.equals("ranged") || (d.row.startsWith("agile") && d.row.contains("r"))));
        filters.add(d -> d.isUnit() && (d.row.equals("siege") || d.row.endsWith("s")));
        filters.add(CardData::isHero);
        filters.add(d -> d.isSpecial() || d.isWeather());
        float filterX = colL.x + 240;
        for (int i = 0; i < filterNames.length; i++) {
            String name = filterNames[i];
            float w = renderer.measure(name, Font.ui(15, true))[0] + 22;
            Box area = box(filterX, 192, w, 26);
            boolean isActive = builderFilter == i;
            if (isActive) renderer.gradient(area, new RGBA(0.95f, 0.82f, 0.49f, 1), Theme.BRONZE, 6);
            else if (area.contains(mouse)) renderer.rect(area, RGBA.GOLD.alpha(0.15f));
            renderer.text(name, Font.ui(15, true), area.mid().x, area.y + 4, isActive ? Theme.PANEL_DARK : RGBA.gray(0.85f), 0, Align.CENTER, null, 0);
            int index = i;
            button(area, () -> { builderFilter = index; collectionScroll[1] = 0; });
            filterX += w + 6;
        }
        Predicate<CardData> predicate = filters.get(Math.min(builderFilter, filters.size() - 1));
        List<CardData> collection = new ArrayList<>();
        for (CardData d : builder.collection()) if (predicate.test(d) && d.count - builder.counts.getOrDefault(d.key, 0) > 0) collection.add(d);
        builderGrid(collection, colL, collectionScroll, dt, 100, d -> builder.cap(d) - builder.counts.getOrDefault(d.key, 0), (d, from) -> {
            int before = builder.counts.getOrDefault(d.key, 0);
            builder.add(d);
            if (builder.counts.getOrDefault(d.key, 0) > before) { audio.play("card", 0.4f); flyCards.add(new FlyCard(d, from, box(colR.mid().x - 50, colR.y + 40, 100, 143))); }
        });
        builderGrid(builder.deckCards(), colR, deckScroll, dt, 100, d -> builder.counts.getOrDefault(d.key, 0), (d, from) -> {
            builder.remove(d); audio.play("discard", 0.4f);
            flyCards.add(new FlyCard(d, from, box(colL.mid().x - 50, colL.y + 40, 100, 143)));
        });
        List<CardData> leaderCards = builder.leaders();
        int leaderIndex = -1;
        for (int i = 0; i < leaderCards.size(); i++) if (leaderCards.get(i).key.equals(builder.leaderKey)) leaderIndex = i;
        if (leaderIndex < 0 && !leaderCards.isEmpty()) leaderIndex = 0;
        if (leaderIndex >= 0) {
            if (builder.leaderKey.isEmpty()) builder.leaderKey = leaderCards.get(leaderIndex).key;
            Card leaderCard = new Card(leaderCards.get(leaderIndex), null);
            Box leaderArea = BuilderLayout.LEADER_CARD;
            renderer.quad(renderer.glow, box(leaderArea.x - 40, leaderArea.y - 40, leaderArea.w + 80, leaderArea.h + 80), Theme.GLOW.alpha(0.22f + 0.06f * sin(time * 2)));
            drawCard(leaderCard, leaderArea);
            renderer.frame(leaderArea.inset(-2), RGBA.GOLD.alpha(0.6f), 2);
            if (leaderArea.contains(mouse)) builderHover = leaderCard;
            Box changeButton = BuilderLayout.CHANGE_LEADER_BUTTON;
            renderer.text(L("Change leader") + " ▾", Font.serif(17, true), 960, 388, changeButton.contains(mouse) ? RGBA.WHITE : RGBA.GOLD, Align.CENTER);
            renderer.rect(box(changeButton.x + 14, changeButton.y + 25, changeButton.w - 28, 1), RGBA.GOLD.alpha(changeButton.contains(mouse) ? 1 : 0.5f));
            button(changeButton, () -> leaderPickerOpen = true);
            button(leaderArea, () -> leaderPickerOpen = true);
            int[] arrows = {-1, 1}; float[] xs = {856, 1030};
            int current = leaderIndex;
            for (int k = 0; k < 2; k++) {
                int step = arrows[k];
                Box area = box(xs[k], 256, 34, 60);
                renderer.text(step < 0 ? "‹" : "›", Font.serif(54), area.mid().x, area.y - 12, area.contains(mouse) ? RGBA.WHITE : RGBA.GOLD, Align.CENTER);
                button(area, () -> builder.leaderKey = leaderCards.get((current + step + leaderCards.size()) % leaderCards.size()).key);
            }
        }
        int[] stats = builder.stats();
        int totalCards = stats[0], units = stats[1], specials = stats[2], strength = stats[3], heroes = stats[4];
        String[] names = {L("Total cards in deck"), L("Number of Unit Cards"), L("Special Cards"), L("Total Unit Card Strength"), L("Hero Cards")};
        String[] values = {String.valueOf(totalCards), String.valueOf(units), specials + "/10", String.valueOf(strength), String.valueOf(heroes)};
        boolean[] ok = {true, units >= 22, specials <= 10, true, true};
        float y = 424;
        for (int k = 0; k < names.length; k++) {
            renderer.text(names[k], Font.ui(14), 960, y, RGBA.gray(0.72f), 220, Align.CENTER); y += 19;
            renderer.text(values[k], Font.gwent(28), 960, y, ok[k] ? RGBA.WHITE : new RGBA(1, 0.4f, 0.35f, 1), Align.CENTER); y += 40;
        }
        Box bar = box(870, y + 2, 180, 6);
        renderer.rect(bar, RGBA.WHITE.alpha(0.12f));
        renderer.rect(box(bar.x, bar.y, bar.w * Math.min(1, units / 22f), bar.h), units >= 22 ? new RGBA(0.45f, 0.85f, 0.4f, 1) : RGBA.GOLD);
        y += 18;
        if (units < 22) renderer.text(L("Your deck must have at least 22 unit cards."), Font.ui(13), 960, y, Theme.NEGATIVE, 200, Align.CENTER);
        goldButton(BuilderLayout.SAVE_BUTTON, L("Save"), Font.serif(22, true), builder.valid(), () -> { builder.save(); audio.play("game_buy"); builderSavedTimer = 1.5f; });
        if (!builder.careerMode())
            goldButton(BuilderLayout.START_BUTTON, L("Start game"), Font.serif(20, true), builder.valid(), () -> { builder.save(); customDecks = DeckBuilder.loadCustom(); startGame(builder.asDeck()); });
        goldButton(ScreenLayout.BACK_BUTTON, "‹  " + L("Back"), Font.serif(22, true), () -> {
            if (builder.careerMode()) { builder.save(); setScreen(Screen.CAREER); return; }
            customDecks = DeckBuilder.loadCustom(); selectedFaction = builder.faction; deckStage = 1; deckTransition = 0; setScreen(Screen.DECKS);
        });
        if (builderSavedTimer > 0) { renderer.text(L("Deck Saved!"), Font.serif(22, true), 960, 760, new RGBA(0.5f, 1, 0.5f, Math.min(1, builderSavedTimer)), Align.CENTER); builderSavedTimer -= dt; }
        for (int i = flyCards.size() - 1; i >= 0; i--) {
            FlyCard flight = flyCards.get(i);
            flight.progress += dt / 0.35f;
            if (flight.progress >= 1) { flyCards.remove(i); continue; }
            float progress = ease(flight.progress);
            float arc = sin(progress * (float) Math.PI) * -60;
            Box cardRect = box(flight.from.x + (flight.to.x - flight.from.x) * progress, flight.from.y + (flight.to.y - flight.from.y) * progress + arc, flight.from.w, flight.from.h);
            renderer.rect(box(cardRect.x + 10, cardRect.y + 14, cardRect.w, cardRect.h), RGBA.BLACK.alpha(0.35f * (1 - progress)));
            drawCard(new Card(flight.cardData, null), cardRect);
            renderer.rect(cardRect, RGBA.BLACK.alpha(progress * 0.6f));
        }
        if (builderHover != null) drawPreview(builderHover);
        builderHover = null;
        languageToggle(1040);
    }

    /** Overlay for choosing the deck's leader. */
    void drawLeaderPicker(DeckBuilder builder) {
        renderer.text(L("Choose a leader"), Font.gwent(52), 960, 40, RGBA.GOLD, Align.CENTER);
        renderer.text(gameData().factionName(builder.faction) + " — " + L("click the leader you want to play with."), Font.serif(19, false, true), 960, 108, RGBA.gray(0.85f), Align.CENTER);
        goldButton(ScreenLayout.BACK_BUTTON, "‹  " + L("Back"), Font.serif(22, true), () -> leaderPickerOpen = false);
        List<CardData> leaderCards = builder.leaders();
        if (leaderCards.isEmpty()) return;
        int count = leaderCards.size(); float gap = 24;
        float cardW = Math.min(240, (1800 - gap * (count - 1)) / count), cardH = cardW / 0.697f;
        float x0 = 960 - (count * cardW + (count - 1) * gap) / 2;
        Card hovered = null;
        for (int i = 0; i < count; i++) {
            CardData entry = leaderCards.get(i);
            Box base = box(x0 + i * (cardW + gap), 180, cardW, cardH);
            boolean isHovered = base.contains(mouse), isSelected = entry.key.equals(builder.leaderKey);
            Box cardRect = isHovered ? box(base.x, base.y - 8, base.w, base.h) : base;
            if (isHovered || isSelected) renderer.quad(renderer.glow, box(cardRect.x - 40, cardRect.y - 40, cardRect.w + 80, cardRect.h + 80), Theme.GLOW.alpha(isSelected ? 0.45f : 0.3f));
            Card card = new Card(entry, null);
            drawCardLarge(card, cardRect);
            renderer.frame(cardRect.inset(-3), isSelected ? RGBA.GOLD : RGBA.GOLD.alpha(isHovered ? 0.7f : 0.25f), isSelected ? 3 : 1.5f);
            if (isSelected) renderer.text("★ " + L("Selected"), Font.serif(18, true), cardRect.mid().x, cardRect.y + cardRect.h + 10, RGBA.GOLD, Align.CENTER);
            if (isHovered) hovered = card;
            button(base, () -> { builder.leaderKey = entry.key; leaderPickerOpen = false; audio.play("card", 0.5f); });
        }
        CardData show = hovered != null ? hovered.data() : null;
        if (show == null) for (CardData d : leaderCards) if (d.key.equals(builder.leaderKey)) show = d;
        if (show == null) show = leaderCards.get(0);
        Box panel = box(460, 180 + cardH + 60, 1000, 150);
        glassPanel(panel, 0.8f);
        renderer.text(gameData().cardName(show), Font.serif(24, true), panel.mid().x, panel.y + 18, RGBA.GOLD, panel.w - 60, Align.CENTER);
        List<String> abilities = show.abilities;
        renderer.text(gameData().abilityDesc(abilities.isEmpty() ? "" : abilities.get(abilities.size() - 1)), Font.ui(18), panel.mid().x, panel.y + 60, RGBA.gray(0.9f), panel.w - 80, Align.CENTER);
    }

    // MARK: Career

    /** Career entry point: start screen, chapter ladder or reward screen. */
    @Override void drawCareer(float dt) {
        drawMenuBackground(dt, 0.7f);
        deckTransition = Math.min(1, deckTransition + dt / 0.5f);
        renderer.text(L("Career"), Font.gwent(52), 960, 30, RGBA.GOLD, Align.CENTER);
        goldButton(ScreenLayout.BACK_BUTTON, "‹  " + L("Back"), Font.serif(22, true), () -> { deckStage = -1; deckTransition = 0; setScreen(Screen.DECKS); });
        if (!career().active()) { drawCareerStart(); return; }
        drawCareerLadder();
        if (careerRewards != null) drawCareerReward();
        if (builderHover != null) drawPreviewRight(builderHover, 110);
        builderHover = null;
    }

    /** Difficulty and faction selection for a new career. */
    void drawCareerStart() {
        renderer.text(L("You start with weak cards of the chosen faction. Every career is generated anew: different places, opponents and bosses. Win, earn cards and reach the top."),
            Font.serif(20, false, true), 960, 96, RGBA.gray(0.88f), 1300, Align.CENTER);
        renderer.text(L("Difficulty") + ":", Font.serif(22, true), 960 - 470, 160, RGBA.GOLD);
        String[] options = {L("easy · 6 chapters"), L("normal · 8 chapters"), L("hard · 10 chapters")};
        for (int i = 0; i < options.length; i++) {
            Box area = box(960 - 230 + i * 250, 150, 240, 46);
            int index = i;
            goldButton(area, (careerDifficultyChoice == i ? "✓ " : "") + options[i], Font.serif(17, true), () -> careerDifficultyChoice = index);
            if (careerDifficultyChoice == i) { renderer.rect(area, Theme.GLOW.alpha(0.22f)); renderer.frame(area.inset(-3), Theme.HIGHLIGHT_GOLD, 3); }
        }
        renderer.text(L("Choose the faction to start your career with:"), Font.serif(22, true), 960, 214, RGBA.GOLD, Align.CENTER);
        List<String> factions = DeckBuilder.FACTIONS_ORDER;
        float tileWidth = 300, tileHeight = 214, gapX = 24, gapY = 18;
        float x0 = 960 - (5 * tileWidth + 4 * gapX) / 2;
        for (int i = 0; i < factions.size(); i++) {
            String faction = factions.get(i);
            float progress = ease(deckTransition * 1.6f - i * 0.04f);
            Box area = box(x0 + (i % 5) * (tileWidth + gapX), 256 + (i / 5) * (tileHeight + gapY) + (1 - progress) * 20, tileWidth, tileHeight);
            boolean hovered = area.contains(mouse);
            if (hovered) renderer.quad(renderer.glow, box(area.x - 40, area.y - 40, area.w + 80, area.h + 80), Theme.GLOW.alpha(0.3f));
            glassPanel(area, 0.75f * progress);
            renderer.frame(area, RGBA.GOLD.alpha(hovered ? 0.9f : 0.3f), 1.5f);
            renderer.image("img/icons/deck_shield_" + faction + ".png", box(area.mid().x - 34, area.y + 18, 68, 76), RGBA.WHITE.alpha(progress));
            renderer.text(gameData().factionName(faction), Font.gwent(26), area.mid().x, area.y + 104, RGBA.GOLD.alpha(progress), area.w - 20, Align.CENTER);
            renderer.text(gameData().factionDesc(faction), Font.ui(14), area.mid().x, area.y + 140, RGBA.gray(0.85f, progress), area.w - 30, Align.CENTER);
            button(area, () -> { career().start(faction, careerDifficultyChoice); careerChapter = 0; deckTransition = 0; audio.play("game_buy"); });
        }
    }

    /** Chapter list, fights of the selected chapter and the player's deck panel. */
    void drawCareerLadder() {
        Career career = career();
        int chapterCount = career.chapterCount();
        int selectedChapter = Math.min(careerChapter != null ? careerChapter : career.currentChapter(), chapterCount - 1);
        String difficultyName = Career.DIFFICULTY_NAMES[career.difficulty];
        renderer.text(gameData().factionName(career.faction) + " · " + L(difficultyName) + " · " + L("opponents defeated") + ": " + career.beaten.size() + "/" + career.totalFights(),
            Font.serif(20, false, true), 960, 98, RGBA.gray(0.85f), Align.CENTER);
        Box colL = CareerLayout.CHAPTERS_COLUMN;
        glassPanel(colL, 0.7f);
        renderer.text(L("Chapters"), Font.gwent(30), colL.mid().x, colL.y + 14, RGBA.GOLD, Align.CENTER);
        int first = Math.max(0, Math.min(career.currentChapter() - 2, chapterCount - 5));
        for (int chapter = first; chapter < Math.min(chapterCount, first + 5); chapter++) {
            CareerChapter info = career.chapter(chapter);
            Box area = box(colL.x + 16, colL.y + 70 + (chapter - first) * 112, colL.w - 32, 100);
            boolean open = career.unlocked(chapter, 0), done = career.beaten.contains(career.index(chapter, 3));
            boolean isSelected = chapter == selectedChapter, hovered = area.contains(mouse) && open;
            renderer.rect(area, isSelected ? Theme.WOOD_BROWN.alpha(0.55f) : RGBA.BLACK.alpha(hovered ? 0.45f : 0.3f));
            renderer.frame(area, RGBA.GOLD.alpha(isSelected ? 0.95f : (open ? 0.45f : 0.15f)), isSelected ? 2 : 1);
            renderer.text((chapter + 1) + ". " + info.title, Font.serif(20, true), area.x + 14, area.y + 14, open ? RGBA.WHITE : RGBA.gray(0.45f), area.w - 28);
            String status = done ? "✓ " + L("Completed") : (open ? "▶ " + L("In progress") : "🔒 " + L("Locked"));
            int won = 0;
            for (int s = 0; s < 4; s++) if (career.beaten.contains(career.index(chapter, s))) won++;
            renderer.text(status + "  ·  " + won + "/4", Font.ui(15), area.x + 14, area.y + 62, done ? Theme.POSITIVE : (open ? RGBA.GOLD : RGBA.gray(0.45f)));
            int chosen = chapter;
            if (open) button(area, () -> careerChapter = chosen);
        }
        List<CareerFight> fights = career.chapter(selectedChapter).fights;
        float cardW = 230, cardH = cardW / 0.697f, gap = 24;
        float x0 = 460 + (1040 - (4 * cardW + 3 * gap)) / 2;
        renderer.text(L("Chapter") + " " + (selectedChapter + 1) + "/" + chapterCount + ": " + career.chapter(selectedChapter).title, Font.gwent(34), 980, 150, RGBA.GOLD, Align.CENTER);
        for (int slot = 0; slot < fights.size(); slot++) {
            CareerFight fight = fights.get(slot);
            int fightIndex = career.index(selectedChapter, slot);
            float progress = ease(deckTransition * 1.5f - slot * 0.08f);
            float x = x0 + slot * (cardW + gap);
            Box tile = box(x - 10, 200 + (1 - progress) * 24, cardW + 20, cardH + 210);
            boolean open = career.unlocked(selectedChapter, slot), won = career.beaten.contains(fightIndex);
            boolean hovered = tile.contains(mouse) && open;
            if (hovered) renderer.quad(renderer.glow, box(tile.x - 40, tile.y - 40, tile.w + 80, tile.h + 80), Theme.GLOW.alpha(0.28f));
            glassPanel(tile, 0.65f * progress);
            renderer.frame(tile, fight.boss ? new RGBA(0.95f, 0.35f, 0.25f, 0.8f * progress) : RGBA.GOLD.alpha(0.35f * progress), fight.boss ? 2.5f : 1.5f);
            DeckData opponentDeck = career.opponentDeck(fightIndex, fight);
            Box cardRect = box(x, tile.y + 10, cardW, cardH);
            CardData portrait = gameData().cards.get(fight.portrait);
            if (portrait == null) portrait = gameData().cards.get(opponentDeck.leader);
            if (portrait != null) {
                drawCardLarge(new Card(portrait, null), cardRect);
                if (cardRect.contains(mouse)) builderHover = new Card(portrait, null);
            }
            if (!open) { renderer.rect(cardRect, RGBA.BLACK.alpha(0.6f)); renderer.text("🔒", Font.ui(54), cardRect.mid().x, cardRect.mid().y - 34, RGBA.WHITE, Align.CENTER); }
            float textY = cardRect.y + cardH + 10;
            textY += renderer.text((fight.boss ? "☠ " : "") + fight.name, Font.serif(20, true), x, textY, fight.boss ? Theme.NEGATIVE.alpha(progress) : RGBA.WHITE.alpha(progress), cardW)[1] + 2;
            textY += renderer.text(gameData().factionName(fight.faction), Font.ui(15), x, textY, RGBA.gray(0.8f, progress), cardW)[1] + 2;
            String difficulty = fight.cap >= 99 ? L("Full strength") : L("Card strength up to") + " " + fight.cap;
            renderer.text(difficulty + (fight.heroes > 0 ? " · " + L("heroes") + ": " + fight.heroes : ""), Font.ui(14), x, textY, RGBA.GOLD.alpha(0.8f * progress), cardW);
            Box area = box(x, tile.y + tile.h - 56, cardW, 46);
            if (won) {
                renderer.text("✓ " + L("Defeated"), Font.serif(18, true), area.mid().x, area.y - 26, Theme.POSITIVE.alpha(progress), Align.CENTER);
                goldButton(area, L("Play again"), Font.serif(18, true), () -> startCareerFight(fightIndex));
            } else if (open) {
                goldButton(area, fight.boss ? L("Fight the boss") : L("Fight"), Font.serif(20, true), () -> startCareerFight(fightIndex));
            } else {
                renderer.text(fight.boss ? L("Defeat the three opponents") : L("Defeat the previous boss"), Font.ui(14), area.mid().x, area.y + 4, RGBA.gray(0.55f), cardW, Align.CENTER);
            }
        }
        if (career.finished()) renderer.text("★ " + L("Career complete! You are a Gwent master.") + " ★", Font.serif(26, true), 980, 900, RGBA.GOLD, Align.CENTER);
        Box colR = CareerLayout.DECK_COLUMN;
        glassPanel(colR, 0.7f);
        renderer.text(L("Your deck"), Font.gwent(30), colR.mid().x, colR.y + 14, RGBA.GOLD, Align.CENTER);
        CardData leaderData = gameData().cards.get(career.leader);
        if (leaderData != null) {
            Box leaderArea = box(colR.mid().x - 90, colR.y + 64, 180, 180 / 0.697f);
            drawCardLarge(new Card(leaderData, null), leaderArea);
            if (leaderArea.contains(mouse)) builderHover = new Card(leaderData, null);
        }
        int owned = 0;
        for (int v : career.collection.values()) owned += v;
        float y = colR.y + 64 + 180 / 0.697f + 14;
        String[] labels = {L("Cards in collection"), L("Units in deck"), L("Leaders")};
        String[] values = {String.valueOf(owned), String.valueOf(career.deckUnits()), String.valueOf(career.leaders.size())};
        for (int k = 0; k < 3; k++) {
            renderer.text(labels[k], Font.ui(16), colR.x + 24, y, RGBA.gray(0.8f));
            renderer.text(values[k], Font.ui(16, true), colR.x + colR.w - 24, y, RGBA.GOLD, Align.RIGHT); y += 28;
        }
        goldButton(box(colR.x + 24, colR.y + colR.h - 128, colR.w - 48, 50), L("Edit career deck"), Font.serif(19, true), () -> {
            builder = new DeckBuilder(); builder.loadCareer(); leaderPickerOpen = false; setScreen(Screen.BUILDER); });
        Box resetArea = box(colR.x + 24, colR.y + colR.h - 66, colR.w - 48, 44);
        goldButton(resetArea, careerConfirmReset ? L("Sure? Click again") : L("New career"), Font.serif(17, true), () -> {
            if (careerConfirmReset) { career().reset(); careerConfirmReset = false; careerChapter = null; } else careerConfirmReset = true;
        });
    }

    /** Starts a career fight. */
    @Override void startCareerFight(int fightIndex) {
        CareerFight fight = career().chapter(fightIndex / 4).fights.get(fightIndex % 4);
        careerConfirmReset = false;
        startGame(career().playerDeck(), career().opponentDeck(fightIndex, fight), fightIndex);
        careerFightName = fight.name;
    }

    /** Lets the player pick one of the reward cards after a win. */
    void drawCareerReward() {
        List<String> options = careerRewards;
        if (options == null) return;
        clicks.clear();
        renderer.rect(renderer.visibleRect, RGBA.BLACK.alpha(0.8f));
        renderer.text(L("Victory!"), Font.gwent(64), 960, 60, RGBA.GOLD, Align.CENTER);
        renderer.text(options.isEmpty() ? L("You already own every card of this faction.") : L("Choose a card to add to your collection:"),
            Font.serif(24, false, true), 960, 150, RGBA.WHITE, Align.CENTER);
        CardData newLeader = careerNewLeader != null ? gameData().cards.get(careerNewLeader) : null;
        if (newLeader != null) renderer.text("★ " + L("New leader") + ": " + gameData().cardName(newLeader), Font.serif(22, true), 960, 196, RGBA.GOLD, Align.CENTER);
        float cardW = 300, cardH = cardW / 0.697f, gap = 60;
        float x0 = 960 - (options.size() * cardW + Math.max(0, options.size() - 1) * gap) / 2;
        for (int i = 0; i < options.size(); i++) {
            String key = options.get(i);
            CardData cardData = gameData().cards.get(key);
            if (cardData == null) continue;
            Box base = box(x0 + i * (cardW + gap), 260, cardW, cardH);
            boolean hovered = base.contains(mouse);
            Box cardRect = hovered ? box(base.x - 6, base.y - 10, base.w + 12, base.h + 12) : base;
            if (hovered) renderer.quad(renderer.glow, box(cardRect.x - 50, cardRect.y - 50, cardRect.w + 100, cardRect.h + 100), Theme.GLOW.alpha(0.45f));
            drawCardLarge(new Card(cardData, null), cardRect);
            if (hovered) builderHover = new Card(cardData, null);
            button(base, () -> { career().take(key); careerRewards = null; careerNewLeader = null; audio.play("game_buy"); });
        }
        if (options.isEmpty()) goldButton(box(960 - 150, 700, 300, 60), L("Continue"), Font.serif(24, true), () -> { careerRewards = null; careerNewLeader = null; });
    }
}

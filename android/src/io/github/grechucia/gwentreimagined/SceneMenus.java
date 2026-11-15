// Title screen, menu background and particles, card rendering, visual effects and gamepad focus navigation.
package io.github.grechucia.gwentreimagined;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.BiConsumer;
import java.util.function.ToIntFunction;
import static io.github.grechucia.gwentreimagined.GameData.L;

/** Title screen, shared menu widgets, card drawing, effects and gamepad focus. */
abstract class SceneMenus extends SceneBase {
    /** A floating ember or dust particle of the menu background. */
    static final class Particle { float x, y, vx, vy, life, lifetime, size, alpha, depth; boolean ember; }
    final List<Particle> particles = new ArrayList<>();
    Vec2 smoothMouse = new Vec2(0, 0);

    static final List<BgRegion> REGIONS = new ArrayList<>();
    static {
        float[][] values = {
            {120, 560, 110, 140, 0, 1.0f, 4.6f, 0.0f}, {240, 380, 70, 90, 0, 0.8f, 5.2f, 1.3f}, {380, 550, 115, 120, 0, 1.0f, 4.1f, 2.1f},
            {590, 420, 80, 90, 0, 0.9f, 4.8f, 0.7f}, {900, 560, 160, 170, 0, 1.1f, 5.4f, 1.8f}, {1100, 590, 125, 140, 0, 1.0f, 4.3f, 3.0f},
            {1300, 440, 95, 100, 0, 0.9f, 5.0f, 2.6f}, {1500, 600, 115, 140, 0, 1.0f, 4.5f, 0.4f}, {1680, 440, 80, 90, 0, 0.8f, 5.6f, 1.1f},
            {1760, 600, 115, 140, 0, 1.0f, 3.9f, 2.4f}, {480, 930, 200, 130, 0, 1.2f, 5.3f, 0.9f}, {1640, 960, 130, 110, 0, 1.0f, 3.8f, 3.4f},
            {115, 320, 70, 90, 1, 1.0f, 7.1f, 0.3f}, {235, 260, 55, 70, 1, 0.9f, 8.3f, 2.2f}, {390, 370, 75, 90, 1, 1.1f, 6.4f, 1.0f},
            {575, 270, 55, 70, 1, 1.0f, 7.7f, 2.9f}, {850, 310, 80, 100, 1, 0.9f, 8.9f, 0.6f}, {1080, 190, 85, 130, 1, 1.4f, 6.1f, 1.7f},
            {1100, 380, 75, 95, 1, 1.0f, 7.4f, 2.5f}, {1290, 260, 60, 75, 1, 0.9f, 8.1f, 0.2f}, {1500, 390, 70, 90, 1, 1.0f, 6.8f, 1.4f},
            {1680, 300, 55, 70, 1, 0.9f, 9.2f, 3.1f}, {1750, 390, 70, 85, 1, 1.0f, 7.0f, 0.8f}, {470, 720, 95, 105, 1, 1.1f, 7.9f, 2.0f},
            {1660, 760, 80, 95, 1, 1.2f, 6.6f, 1.2f}};
        for (float[] v : values) REGIONS.add(new BgRegion(new float[]{v[0] / 1920, v[1] / 1080, v[2] / 1920, v[3] / 1080}, new float[]{v[4], v[5], v[6], v[7]}));
    }
    static final List<Vec2> GLINTS = Arrays.asList(new Vec2(605 / 1920f, 318 / 1080f), new Vec2(1250 / 1920f, 382 / 1080f));
    static final List<Vec2> CANDLES = Arrays.asList(new Vec2(1405 / 1920f, 290 / 1080f), new Vec2(1850 / 1920f, 330 / 1080f), new Vec2(1245 / 1920f, 1062 / 1080f));

    SceneMenus(Renderer renderer, Audio audio) {
        super(renderer, audio);
        for (int i = 0; i < 90; i++) particles.add(spawn(false, true));
        for (int i = 0; i < 26; i++) particles.add(spawn(true, true));
    }

    // MARK: Title screen

    /** Title screen with the animated background. */
    @Override void drawTitle(float dt) {
        if (autotest) { autotestTimer += dt; if (autotestTimer > 2.5f) { autotestTimer = 0; myDeckIndex = RANDOM.nextInt(gameData().decks.size()); startGame(); return; } }
        smoothMouse = smoothMouse.plus(mouseNorm.minus(smoothMouse).times(Math.min(1, dt * 2.5f)));
        renderer.titleBackground("img/start_bg.jpg", time, smoothMouse, REGIONS, GLINTS, CANDLES);
        drawParticles(dt);
        String middle = gameData().language.equals("pl") ? "WIN" : "WEN";
        Font bigFont = Font.gwent(146), smallFont = Font.gwent(104);
        float total = renderer.measure("G", bigFont)[0] + renderer.measure(middle, smallFont)[0] + renderer.measure("T", bigFont)[0] - 24;
        float x = 960 - total / 2, y = 34;
        String witcherLabel = L("The Witcher 3").toUpperCase();
        renderer.text(witcherLabel, Font.gwent(26), 962, 16, RGBA.BLACK.alpha(0.7f), 0, Align.CENTER, null, 0);
        renderer.text(witcherLabel, Font.gwent(26), 960, 14, Theme.TEXT_GOLD.alpha(0.7f), 0, Align.CENTER, null, 0);
        String[] letters = {"G", middle, "T"};
        Font[] fonts = {bigFont, smallFont, bigFont};
        float[] offsets = {0, 30, 0};
        for (int i = 0; i < 3; i++) {
            renderer.text(letters[i], fonts[i], x + 3, y + offsets[i] + 5, RGBA.BLACK.alpha(0.85f), 0, Align.LEFT, null, 0);
            renderer.text(letters[i], fonts[i], x, y + offsets[i], Theme.GLOW, 0, Align.LEFT, null, 0);
            renderer.text(letters[i], fonts[i], x, y + offsets[i] - 2, Theme.PALE_GOLD.alpha(0.35f), 0, Align.LEFT, null, 0);
            x += renderer.measure(letters[i], fonts[i])[0] - 12;
        }
        float ornamentY = 206;
        renderer.gradient(box(960 - 230, ornamentY, 210, 2), RGBA.GOLD_DARK.alpha(0), RGBA.GOLD);
        renderer.rect(box(960 - 230, ornamentY, 210, 2), RGBA.GOLD_DARK.alpha(0.6f));
        renderer.rect(box(960 + 20, ornamentY, 210, 2), RGBA.GOLD_DARK.alpha(0.6f));
        renderer.quad(renderer.white, box(953, ornamentY - 6, 14, 14), new Box(0, 0, 1, 1), RGBA.GOLD, 0, (float) Math.PI / 4);
        renderer.quad(renderer.white, box(956, ornamentY - 3, 8, 8), new Box(0, 0, 1, 1), Theme.INK, 0, (float) Math.PI / 4);
        Box area = box(960 - 170, 905, 340, 70);
        padPrimary = area;
        goldButton(area, gameData().ui("LET'S PLAY"), Font.gwent(38), () -> {
            audio.play("menu_opening");
            Runnable openDecks = () -> { deckStage = -1; deckTransition = 0; setScreen(Screen.DECKS); };
            Runnable named = () -> { if (SaveStore.shared.get("playerName") == null) askPlayerName(openDecks); else openDecks.run(); };
            if (SaveStore.shared.chosen()) named.run(); else askSaveLocation(named);
        });
        goldButton(box(960 + 200, 917, 220, 46), L("How to play"), Font.serif(20, true), this::openRules);
        goldButton(box(960 - 420, 917, 220, 46), L("Options"), Font.serif(20, true), () -> optionsOpen = true);
        renderer.text("v" + appVersion, Font.serif(17), 1880, 1044, Theme.PARCHMENT_TEXT.alpha(0.6f), Align.RIGHT);
        languageToggle(995);
    }

    /** Language dropdown. */
    @Override void languageToggle(float y) {
        float w = 260, h = 40;
        Box area = box(960 - w / 2, y, w, h);
        String currentName = GameData.languageName(gameData().language);
        renderer.rect(area.inset(-4), Theme.PANEL_DARK.alpha(0.78f));
        renderer.frame(area.inset(-4), RGBA.GOLD_DARK.alpha(langMenuOpen || area.contains(mouse) ? 0.95f : 0.55f), 1.5f);
        float textHeight = renderer.measure(currentName, Font.serif(20, true))[1];
        renderer.text(currentName, Font.serif(20, true), area.x + 18, area.mid().y - textHeight / 2, RGBA.GOLD);
        renderer.text(langMenuOpen ? "▴" : "▾", Font.ui(20, true), area.x + area.w - 18, area.mid().y - textHeight / 2, RGBA.GOLD, Align.RIGHT);
        if (!langMenuOpen) { button(area, () -> langMenuOpen = true); return; }
        button(renderer.visibleRect, () -> langMenuOpen = false);
        float itemHeight = 36;
        String[][] list = GameData.LANGUAGES;
        Box menu = box(area.x - 4, area.y - 8 - list.length * itemHeight, area.w + 8, list.length * itemHeight + 4);
        renderer.rect(menu, Theme.PANEL_DARK.alpha(0.97f)); renderer.frame(menu, RGBA.GOLD_DARK, 1.5f);
        for (int i = 0; i < list.length; i++) {
            String code = list[i][0], name = list[i][1];
            Box item = box(menu.x + 2, menu.y + 2 + i * itemHeight, menu.w - 4, itemHeight);
            boolean isCurrent = code.equals(gameData().language), hovered = item.contains(mouse);
            if (isCurrent) renderer.gradient(item, new RGBA(0.95f, 0.82f, 0.49f, 1), Theme.BRONZE, 6);
            else if (hovered) renderer.rect(item, RGBA.GOLD.alpha(0.18f));
            float textY = item.mid().y - renderer.measure(name, Font.serif(19, true))[1] / 2;
            renderer.text(name, Font.serif(19, true), item.x + 16, textY, isCurrent ? Theme.PANEL_DARK : (hovered ? RGBA.WHITE : RGBA.gray(0.85f)), 0, Align.LEFT, isCurrent ? null : RGBA.BLACK.alpha(0.8f), 0);
            if (!gameData().hasTranslation(code)) renderer.text("EN", Font.ui(12, true), item.x + item.w - 14, item.mid().y - 8, isCurrent ? Theme.INK : RGBA.gray(0.5f), 0, Align.RIGHT, null, 0);
            button(item, () -> { setLanguage(code); langMenuOpen = false; });
        }
    }

    /** Changes the game language. */
    void setLanguage(String code) { gameData().language = code; if (host != null) host.setLanguage(code); }

    /** Creates a background particle. */
    Particle spawn(boolean ember, boolean initial) {
        Particle p = new Particle();
        p.ember = ember;
        if (!ember) {
            p.x = rand(0, 1920); p.y = rand(0, 970); p.vx = rand(-4, 4); p.vy = rand(-4.5f, 2);
            p.lifetime = rand(8, 18); p.size = rand(2, 7); p.alpha = rand(0.12f, 0.37f); p.depth = rand(0.3f, 1.3f);
        } else {
            float[][] origins = RANDOM.nextBoolean() ? new float[][]{{1405, 290}, {1850, 330}, {1245, 1062}} : new float[][]{{605, 318}, {1250, 382}};
            float[] origin = origins[RANDOM.nextInt(origins.length)];
            p.x = origin[0] + rand(-28, 28); p.y = origin[1] + rand(-20, 0); p.vx = rand(-10, 10); p.vy = rand(-55, -20);
            p.lifetime = rand(1.8f, 4); p.size = rand(1.5f, 4); p.alpha = rand(0.5f, 1); p.depth = 1.2f;
        }
        if (initial) p.life = rand(0, p.lifetime);
        return p;
    }

    /** Updates and draws the background particles. */
    void drawParticles(float dt) {
        for (int i = 0; i < particles.size(); i++) {
            Particle p = particles.get(i);
            p.life += dt;
            if (p.life > p.lifetime) { p = spawn(p.ember, false); particles.set(i, p); }
            if (p.ember) p.vx += sin(time * 2 + i) * 0.6f;
            p.x += (p.vx + sin(time * 0.3f + i) * 1.5f) * dt;
            p.y += p.vy * dt;
            float fade = sin((float) Math.PI * Math.min(1, p.life / p.lifetime));
            float alpha = p.alpha * fade * (p.ember ? (0.7f + 0.3f * sin(time * 17 + i * 3)) : 1);
            float size = p.size * 2.4f * (p.ember ? 1 : p.depth);
            float sx = p.x - smoothMouse.x * p.depth * 8, sy = p.y - smoothMouse.y * p.depth * 6;
            RGBA tint = p.ember ? new RGBA(1, 0.6f, 0.25f, alpha) : Theme.CREAM.alpha(alpha);
            renderer.quad(renderer.glow, box(sx - size / 2, sy - size / 2, size, size), tint);
        }
    }

    /** Dimmed menu background used by secondary screens. */
    void drawMenuBackground(float dt, float dimming) {
        smoothMouse = smoothMouse.plus(mouseNorm.minus(smoothMouse).times(Math.min(1, dt * 2.5f)));
        renderer.titleBackground("img/start_bg.jpg", time, smoothMouse.times(0.5f), REGIONS, GLINTS, CANDLES);
        renderer.rect(renderer.visibleRect, Theme.PANEL_DARK.alpha(dimming));
        drawParticles(dt);
    }

    // MARK: Shared widgets

    /** Dark translucent panel with a gold frame. */
    void glassPanel(Box area, float alpha) {
        renderer.gradient(area, Theme.PANEL_DARK.alpha(alpha), Theme.PANEL_DARK.alpha(alpha + 0.08f), 10);
        renderer.gradient(box(area.x, area.y, area.w, Math.min(60, area.h * 0.25f)), Theme.PALE_GOLD.alpha(0.06f), Theme.PALE_GOLD.alpha(0), 6);
        renderer.frame(area, RGBA.GOLD_DARK.alpha(0.55f), 1.5f);
    }
    void glassPanel(Box area) { glassPanel(area, 0.78f); }
    /** Decorative gold divider line. */
    void goldDivider(float x, float y, float width) {
        renderer.gradient(box(x, y, width / 2, 1.5f), RGBA.GOLD_DARK.alpha(0), RGBA.GOLD.alpha(0.8f));
        renderer.quad(renderer.white, box(x + width / 2 - 4, y - 3.5f, 8, 8), new Box(0, 0, 1, 1), RGBA.GOLD, 0, (float) Math.PI / 4);
        renderer.rect(box(x + width / 2 + 6, y, width / 2 - 6, 1.5f), RGBA.GOLD_DARK.alpha(0.45f));
    }
    /** Text button drawn as an underlined link. */
    void smallLink(Box area, String title, Runnable action) {
        float amount = hoverAmount("link_" + title, area.contains(mouse), 0.25f);
        Font font = Font.serif(21, true);
        float[] size = renderer.measure(title, font);
        renderer.text(title, font, area.mid().x, area.mid().y - size[1] / 2, new RGBA(0.95f, 0.82f + 0.18f * amount, 0.5f + 0.5f * amount, 1), Align.CENTER);
        float w = size[0] * amount;
        renderer.rect(box(area.mid().x - w / 2, area.mid().y + size[1] / 2 + 2, w, 1.5f), RGBA.GOLD);
        button(area, action);
    }

    // MARK: Card rendering

    /** Icon file for an ability. */
    String abilityIcon(String ability) {
        String iconName = ability;
        if (iconName.equals("cerys")) iconName = "muster";
        if (iconName.startsWith("avenger")) iconName = "avenger";
        if (Arrays.asList("scorch_c", "scorch_r", "scorch_s").contains(iconName)) iconName = "scorch_combat";
        if (Arrays.asList("shield_c", "shield_r", "shield_s").contains(iconName)) iconName = "shield";
        return "img/icons/card_ability_" + iconName + ".png";
    }
    /** Power badge image of a card. */
    String powerBadge(Card card) {
        if (card.hero()) return "img/icons/power_hero.png";
        if (card.data().isSpecial() || card.data().isWeather()) {
            String badge = card.data().abilities.isEmpty() ? "normal" : card.data().abilities.get(0);
            if (Arrays.asList("shield_c", "shield_r", "shield_s").contains(badge)) badge = "shield";
            return "img/icons/power_" + badge + ".png";
        }
        return "img/icons/power_normal.png";
    }
    /** Last shown power of each card and its "pop" animation amount. */
    final Map<Integer, float[]> powerSeen = new HashMap<>();

    /** Draws a small card with power, row and ability icons. */
    void drawCard(Card card, Box r, boolean highlight, boolean dimmed) {
        float scale = r.w / CARD_WIDTH;
        renderer.imageCover(card.data().image(), r, dimmed ? RGBA.gray(0.45f) : RGBA.WHITE);
        if (card.flash > 0) renderer.rect(r, new RGBA(1, 0.9f, 0.6f, card.flash * 0.35f));
        if (card.data().isLeader()) { if (highlight) renderer.frame(r.inset(-3), RGBA.GOLD, 3); return; }
        renderer.image(powerBadge(card), box(r.x - 3 * scale, r.y - 5 * scale, 60 * scale, 61 * scale));
        if (card.data().isUnit()) {
            int power = card.power;
            RGBA color = card.hero() ? RGBA.WHITE : (power > card.basePower() ? new RGBA(0.1f, 0.55f, 0.1f, 1) : (power < card.basePower() ? new RGBA(0.75f, 0.1f, 0.1f, 1) : RGBA.BLACK));
            float badgeX = 16.3f, badgeY = 14.6f;
            float pop = 0;
            float[] seen = powerSeen.get(card.id);
            if (seen != null) pop = seen[0] != power ? 0.45f : Math.max(0, seen[1] - frameDelta);
            powerSeen.put(card.id, new float[]{power, pop});
            Font font = Font.ui((card.hero() ? 21 : 19) * scale * (1 + pop * 1.1f), true);
            String text = String.valueOf(power);
            float textHeight = renderer.measure(text, font)[1];
            if (pop > 0) renderer.quad(renderer.glow, box(r.x + badgeX * scale - 22 * scale, r.y + badgeY * scale - 22 * scale, 44 * scale, 44 * scale), new RGBA(1, 0.9f, 0.5f, pop * 1.6f));
            renderer.text(text, font, r.x + badgeX * scale, r.y + badgeY * scale - textHeight / 2, color, 0, Align.CENTER, null, 0);
            renderer.image("img/icons/card_row_" + card.data().row + ".png", box(r.x + 56 * scale, r.y + 91 * scale, 28 * scale, 27 * scale));
            List<String> abilities = new ArrayList<>();
            for (String a : card.data().abilities) if (!a.equals("hero")) abilities.add(a);
            if (!abilities.isEmpty()) renderer.image(abilityIcon(abilities.get(abilities.size() - 1)), box(r.x + 28 * scale, r.y + 91 * scale, 28 * scale, 27 * scale));
            else if (card.data().row.startsWith("agile")) renderer.image("img/icons/card_ability_agile.png", box(r.x + 28 * scale, r.y + 91 * scale, 28 * scale, 27 * scale));
            if (abilities.size() > 1) renderer.image(abilityIcon(abilities.get(abilities.size() - 2)), box(r.x, r.y + 91 * scale, 28 * scale, 27 * scale));
        }
        if (highlight) renderer.frame(r.inset(-3), RGBA.GOLD, 3);
    }
    void drawCard(Card card, Box r) { drawCard(card, r, false, false); }

    /** Draws a large card with its name and quote. */
    void drawCardLarge(Card card, Box r) {
        renderer.imageCover(card.data().image(), r);
        float bandHeight = r.h * 0.26f;
        Box band = box(r.x, r.y + r.h - bandHeight, r.w, bandHeight);
        renderer.gradient(band, Theme.PARCHMENT, Theme.PARCHMENT_SHADE, 10);
        renderer.rect(box(band.x, band.y, band.w, Math.max(1.5f, r.w * 0.008f)), new RGBA(0.55f, 0.42f, 0.2f, 1));
        // Android's serif font is wider than Georgia, so long quotes are kept inside the parchment band.
        renderer.clip(band);
        Font nameFont = Font.serif(Math.max(10, r.w * 0.078f), true);
        float nameHeight = renderer.text(gameData().cardName(card.data()), nameFont, band.mid().x, band.y + bandHeight * 0.08f, Theme.INK, band.w - r.w * 0.08f, Align.CENTER, null, 0)[1];
        String quote = gameData().cardQuote(card.data());
        if (!quote.isEmpty() && r.w >= 150)
            renderer.text(quote, Font.serif(Math.max(9, r.w * 0.053f), false, true), band.mid().x, band.y + bandHeight * 0.06f + nameHeight, new RGBA(0.13f, 0.09f, 0.04f, 1), band.w - r.w * 0.1f, Align.CENTER, null, 0);
        renderer.clip(null);
        if (card.data().isLeader()) return;
        float scale = r.w / CARD_WIDTH * 0.5f;
        renderer.image(powerBadge(card), box(r.x - 3 * scale, r.y - 5 * scale, 60 * scale, 61 * scale));
        if (card.data().isUnit()) {
            Font font = Font.ui((card.hero() ? 21 : 19) * scale, true);
            String text = String.valueOf(card.basePower());
            float textHeight = renderer.measure(text, font)[1];
            renderer.text(text, font, r.x + 16.3f * scale, r.y + 14.6f * scale - textHeight / 2, card.hero() ? RGBA.WHITE : RGBA.BLACK, 0, Align.CENTER, null, 0);
            renderer.image("img/icons/card_row_" + card.data().row + ".png", box(r.x + 3 * scale, r.y + 58 * scale, 44 * scale, 42 * scale));
            String last = null;
            for (String a : card.data().abilities) if (!a.equals("hero")) last = a;
            if (last != null) renderer.image(abilityIcon(last), box(r.x + 3 * scale, r.y + 102 * scale, 44 * scale, 42 * scale));
        }
    }

    /** Title and description lines of a card's abilities. */
    List<String[]> abilityLines(Card card, boolean includeAgile) {
        List<String[]> lines = new ArrayList<>();
        List<String> abilities = card.data().abilities;
        if (card.data().isLeader()) {
            if (!abilities.isEmpty()) lines.add(new String[]{L("Leader Ability"), gameData().abilityDesc(abilities.get(abilities.size() - 1))});
        } else {
            if (includeAgile && card.data().row.startsWith("agile")) lines.add(new String[]{gameData().abilityName("agile"), gameData().abilityDesc("agile")});
            for (String a : abilities) if (!a.equals("hero")) lines.add(new String[]{gameData().abilityName(a), gameData().abilityDesc(a)});
            if (card.hero()) lines.add(new String[]{L("Hero"), gameData().abilityDesc("hero")});
        }
        return lines;
    }

    /** Card preview with the ability description (larger on phones, using the extra screen width). */
    void drawPreview(Card card) {
        boolean large = host != null && host.isPhone();
        Box visible = renderer.visibleRect;
        float columnWidth = large ? 560 : 350;
        float edgeMargin = 130;
        float columnX = large ? visible.x + visible.w - columnWidth - edgeMargin : ScreenLayout.CARD_PREVIEW_TEXT.x;
        Box cardRect = large ? box(columnX + (columnWidth - 300) / 2, 40, 300, 431) : ScreenLayout.CARD_PREVIEW_CARD;
        renderer.rect(cardRect.inset(-6), RGBA.BLACK.alpha(0.55f));
        drawCardLarge(card, cardRect);
        List<String[]> lines = abilityLines(card, true);
        if (lines.isEmpty()) return;
        Font titleFont = Font.serif(large ? 26 : 19, true), bodyFont = Font.ui(large ? 22 : 16);
        float textWidth = columnWidth - 24;
        Box area = box(columnX, cardRect.y + cardRect.h + 12, columnWidth, Virtual.HEIGHT - (cardRect.y + cardRect.h + 12) - 8);
        float contentHeight = 12;
        for (String[] line : lines) contentHeight += renderer.measure(line[0], titleFont, textWidth)[1] + renderer.measure(line[1], bodyFont, textWidth)[1] + 10;
        Box panel = box(area.x, area.y, area.w, Math.min(area.h, contentHeight));
        renderer.rect(panel, Theme.PANEL_DARK.alpha(0.94f));
        renderer.frame(panel, RGBA.GOLD_DARK.alpha(0.6f), 1);
        float y = area.y + 6;
        for (String[] line : lines) {
            if (y > area.y + area.h - 20) break;
            y += renderer.text(line[0], titleFont, area.x + 12, y, RGBA.GOLD, textWidth)[1];
            y += renderer.text(line[1], bodyFont, area.x + 12, y, RGBA.gray(0.95f), textWidth)[1] + 10;
        }
    }

    /** Large card preview with its description, shown at the given x. */
    void drawPreviewRight(Card card, float x) {
        Box cardRect = box(x, 250, 300, 431);
        renderer.rect(cardRect.inset(-6), RGBA.BLACK.alpha(0.6f));
        drawCardLarge(card, cardRect);
        List<String[]> lines = abilityLines(card, false);
        float y = cardRect.y + cardRect.h + 14;
        for (int i = 0; i < Math.min(3, lines.size()); i++) {
            String title = lines.get(i)[0], description = lines.get(i)[1];
            Box label = box(cardRect.x - 6, y, cardRect.w + 12, renderer.measure(title, Font.serif(17, true), cardRect.w - 8)[1] + renderer.measure(description, Font.ui(15), cardRect.w - 8)[1] + 14);
            renderer.rect(label, Theme.PANEL_DARK.alpha(0.94f)); renderer.frame(label, RGBA.GOLD_DARK.alpha(0.6f), 1);
            float titleHeight = renderer.text(title, Font.serif(17, true), cardRect.x + 2, y + 6, RGBA.GOLD, cardRect.w - 8)[1];
            renderer.text(description, Font.ui(15), cardRect.x + 2, y + 6 + titleHeight, RGBA.gray(0.9f), cardRect.w - 8);
            y += label.h + 6;
        }
    }

    /** Scrollable grid of cards (deck builder and deck preview); scroll holds {position, target}. */
    void builderGrid(List<CardData> cards, Box area, float[] scroll, float dt, float cardW, ToIntFunction<CardData> count, BiConsumer<CardData, Box> onClick) {
        float gridW = cardW, gridH = cardW * 1.43f, gap = 10;
        int perRow = Math.max(1, (int) ((area.w - 20 + gap) / (gridW + gap)));
        int rows = (cards.size() + perRow - 1) / perRow;
        float contentH = rows * (gridH + gap) + 10;
        float maxScroll = Math.max(0, contentH - area.h);
        if (area.contains(mouse)) scroll[1] -= wheel * 1.4f;
        scroll[1] = Math.max(0, Math.min(maxScroll, scroll[1]));
        scroll[0] += (scroll[1] - scroll[0]) * Math.min(1, dt * 12);
        scroll[0] = Math.max(0, Math.min(maxScroll, scroll[0]));
        renderer.clip(area);
        for (int i = 0; i < cards.size(); i++) {
            CardData cardData = cards.get(i);
            int row = i / perRow, col = i % perRow;
            float y = area.y + 10 + row * (gridH + gap) - scroll[0];
            if (y + gridH < area.y || y > area.y + area.h) continue;
            float x = area.x + 10 + col * (gridW + gap);
            Box base = box(x, y, gridW, gridH);
            boolean inside = base.mid().y > area.y && base.mid().y < area.y + area.h;
            boolean hovered = inside && base.contains(mouse);
            float amount = hoverAmount(area.x + "_" + cardData.key, hovered, dt * 14);
            float zoom = 1 + 0.07f * amount;
            Box cardRect = box(base.mid().x - gridW * zoom / 2, base.mid().y - gridH * zoom / 2 - 4 * amount, gridW * zoom, gridH * zoom);
            if (amount > 0.02f) renderer.quad(renderer.glow, box(cardRect.x - 20, cardRect.y - 20, cardRect.w + 40, cardRect.h + 40), Theme.GLOW.alpha(0.35f * amount));
            Card newCard = new Card(cardData, null);
            drawCard(newCard, cardRect);
            int copies = count.applyAsInt(cardData);
            if (copies > 1 || cardData.count > 1) {
                renderer.rect(box(cardRect.x + cardRect.w - 30, cardRect.y + cardRect.h - 26, 28, 22), RGBA.BLACK.alpha(0.75f));
                renderer.text("×" + copies, Font.ui(15, true), cardRect.x + cardRect.w - 16, cardRect.y + cardRect.h - 25, RGBA.WHITE, 0, Align.CENTER, null, 0);
            }
            if (hovered) { renderer.frame(cardRect.inset(-2), RGBA.GOLD, 2); builderHover = newCard; }
            if (inside) button(base, () -> onClick.accept(cardData, base));
        }
        renderer.clip(null);
        if (maxScroll > 0) {
            float thumb = area.h * area.h / contentH;
            renderer.rect(box(area.x + area.w - 6, area.y + (area.h - thumb) * scroll[0] / maxScroll, 4, thumb), RGBA.GOLD.alpha(0.6f));
        }
    }

    // MARK: Effects

    /** A running visual effect. */
    static final class FX {
        enum Kind { ICON, BURN, HERO, COIN }
        final Kind kind; final String icon; final boolean mine; final Card card; Box rect; float elapsed; final float duration;
        FX(Kind kind, String icon, boolean mine, Card card, Box rect, float duration) { this.kind = kind; this.icon = icon; this.mine = mine; this.card = card; this.rect = rect; this.duration = duration; }
    }
    final List<FX> fxList = new ArrayList<>();

    /** Creates effects for an engine event. */
    void addFX(GameEvent event) {
        switch (event.kind) {
            case ANIM: {
                Card c = event.card; boolean hero = "hero".equals(event.text);
                fxList.add(new FX(hero ? FX.Kind.HERO : FX.Kind.ICON, event.text, false, c, box(c.posX, c.posY, CARD_WIDTH, CARD_HEIGHT), hero ? 1.1f : 1.6f));
                break;
            }
            case BURN: fxList.add(new FX(FX.Kind.BURN, null, false, event.card, box(event.card.posX, event.card.posY, CARD_WIDTH, CARD_HEIGHT), 1.0f)); break;
            case COIN: fxList.add(new FX(FX.Kind.COIN, null, event.flag, null, box(960 - 170, 290, 340, 340), 1.7f)); break;
            default: break;
        }
    }
    /** Updates and draws the running effects. */
    void drawFX(float dt) {
        for (int i = fxList.size() - 1; i >= 0; i--) {
            FX effect = fxList.get(i);
            effect.elapsed += dt;
            if (effect.elapsed >= effect.duration) { fxList.remove(i); continue; }
            if (effect.card != null && effect.card.hasPos && effect.kind != FX.Kind.BURN) effect.rect = box(effect.card.posX, effect.card.posY, CARD_WIDTH, CARD_HEIGHT);
            float elapsed = effect.elapsed; Box cr = effect.rect;
            switch (effect.kind) {
                case ICON: {
                    float size, a;
                    if (elapsed < 0.3f) { float phase = elapsed / 0.3f; size = 0.5f + 0.6f * phase; a = phase; }
                    else if (elapsed < 1.3f) { float phase = (elapsed - 0.3f) / 1.0f; size = 1.1f - 0.2f * phase; a = 1; }
                    else { float phase = (elapsed - 1.3f) / 0.3f; size = 0.9f - 0.4f * phase; a = 1 - phase; }
                    float w = cr.w * size * 1.15f;
                    renderer.image("img/icons/anim_" + effect.icon + ".png", box(cr.mid().x - w / 2, cr.mid().y - w / 2, w, w), RGBA.WHITE.alpha(a));
                    break;
                }
                case BURN: {
                    float phase = elapsed / effect.duration;
                    float alpha = phase < 0.15f ? phase / 0.15f : (phase > 0.75f ? (1 - phase) / 0.25f : 1);
                    float flick = 0.85f + 0.15f * sin(time * 40 + cr.x);
                    renderer.quad(renderer.glow, box(cr.x - 30, cr.y - 30, cr.w + 60, cr.h + 60), Theme.FIRE.alpha(0.55f * alpha * flick));
                    renderer.image("img/icons/anim_scorch.png", box(cr.x - cr.w * 0.1f, cr.y - cr.h * 0.15f, cr.w * 1.2f, cr.h * 1.25f), RGBA.WHITE.alpha(alpha * flick));
                    break;
                }
                case HERO: {
                    float phase = elapsed / effect.duration;
                    renderer.clip(cr);
                    float x = cr.x - 60 + (cr.w + 120) * phase;
                    renderer.quad(renderer.white, box(x - 14, cr.y - 40, 28, cr.h + 80), new Box(0, 0, 1, 1), new RGBA(1, 0.92f, 0.6f, 0.55f * (1 - Math.abs(phase - 0.5f) * 2) + 0.15f), 0, 0.35f);
                    renderer.clip(null);
                    renderer.frame(cr.inset(-3), new RGBA(1, 0.84f, 0.35f, 0.9f * (1 - phase)), 3);
                    renderer.quad(renderer.glow, box(cr.x - 25, cr.y - 25, cr.w + 50, cr.h + 50), new RGBA(1, 0.8f, 0.3f, 0.35f * (1 - phase)));
                    break;
                }
                case COIN: {
                    float progress = elapsed / effect.duration;
                    float spin = Math.abs(cos(Math.min(progress / 0.7f, 1) * (float) Math.PI * 5));
                    float alpha = progress > 0.85f ? (1 - progress) / 0.15f : 1;
                    renderer.rect(renderer.visibleRect, RGBA.BLACK.alpha(0.35f * alpha));
                    boolean face = progress < 0.7f ? ((int) (progress / 0.7f * 10) % 2 == 0) : effect.mine;
                    float w = cr.w * Math.max(0.06f, progress < 0.7f ? spin : 1);
                    renderer.image("img/icons/notif_" + (face ? "me" : "op") + "_coin.png", box(cr.mid().x - w / 2, cr.y, w, cr.h), RGBA.WHITE.alpha(alpha));
                    break;
                }
            }
        }
    }
    /** Rectangle of a card flying towards a target, and whether it is still flying. */
    Box flightRect(Card card, Vec2 target, boolean[] flying) {
        float distance = new Vec2(target.x - card.posX, target.y - card.posY).length();
        float scale = 1 + Math.min(0.22f, distance / 900);
        float w = CARD_WIDTH * scale, h = CARD_HEIGHT * scale;
        flying[0] = distance > 6;
        return box(card.posX + CARD_WIDTH / 2 - w / 2, card.posY + CARD_HEIGHT / 2 - h / 2 - Math.min(18, distance / 25), w, h);
    }
    /** Animated weather on a row (rain, frost, fog...). */
    void drawWeatherFX(Set<String> weather, Box rowArea) {
        if (weather.isEmpty()) return;
        Box area = box(567, rowArea.y + 4, 946, rowArea.h - 6);
        renderer.clip(area);
        if (weather.contains("rain") || weather.contains("storm") || weather.contains("dragon_wrath")) {
            for (int i = 0; i < 46; i++) {
                float x = area.x + fract(i * 0.6180339f + 0.13f) * area.w + fract(time * 0.9f + i * 0.37f) * 30;
                float y = area.y - 20 + fract(time * 1.7f + i * 0.0731f) * (area.h + 40);
                renderer.quad(renderer.white, box(x, y, 1.6f, 16), new Box(0, 0, 1, 1), new RGBA(0.75f, 0.85f, 1, 0.35f), 0, 0.22f);
            }
        }
        if (weather.contains("fog") || weather.contains("tse_tse")) {
            for (int layer = 0; layer < 2; layer++) {
                float offset = sin(time * 0.25f + layer * 2) * 40;
                renderer.image("img/icons/overlay_" + (weather.contains("fog") ? "fog" : "tse_tse") + ".png", box(area.x + offset - 20, area.y, area.w + 40, area.h), RGBA.WHITE.alpha(0.25f + 0.12f * sin(time * 0.7f + layer)));
            }
        }
        if (weather.contains("frost") || weather.contains("white_frost") || weather.contains("spider_web")) {
            for (int i = 0; i < 26; i++) {
                float x = area.x + fract(i * 0.754877f) * area.w, y = area.y + fract(i * 0.569840f) * area.h;
                float twinkle = Math.max(0, sin(time * 2.4f + i * 1.7f));
                float flake = 6 + 10 * twinkle;
                renderer.quad(renderer.glow, box(x - flake / 2, y - flake / 2, flake, flake), Theme.FROST_BLUE.alpha(0.7f * twinkle));
            }
        }
        if (weather.contains("sandstorm")) {
            for (int i = 0; i < 40; i++) {
                float x = area.x - 40 + fract(time * 0.8f + i * 0.6180339f) * (area.w + 80);
                float y = area.y + fract(i * 0.4142f) * area.h + sin(time * 3 + i) * 4;
                renderer.quad(renderer.white, box(x, y, 24, 1.5f), new RGBA(0.9f, 0.75f, 0.45f, 0.35f));
            }
        }
        renderer.clip(null);
    }

    // MARK: Gamepad focus

    /** First gamepad input only activates focus mode; returns true if the input was consumed. */
    boolean padWake() {
        if (padCursor) return false;
        padCursor = true; mouse = Vec2.NONE;
        return true;
    }
    List<Box> focusTargets() {
        List<Box> targets = new ArrayList<>();
        for (Hit h : clicks) if (h.rect.w < Virtual.WIDTH * 0.9f && h.rect.h < Virtual.HEIGHT * 0.9f && !padNoFocus.contains(h.rect)) targets.add(h.rect);
        return targets;
    }
    /** Element focused automatically: the screen's primary element, otherwise the one nearest the centre. */
    Box autoTarget(List<Box> targets) {
        if (padPrimary != null && targets.contains(padPrimary)) return padPrimary;
        List<Box> pool = new ArrayList<>();
        for (Box t : targets) if (!padNoAuto.contains(t)) pool.add(t);
        if (pool.isEmpty()) pool = targets;
        Box best = null; float bestDistance = Float.MAX_VALUE;
        for (Box t : pool) { float d = t.mid().minus(new Vec2(Virtual.WIDTH / 2, Virtual.HEIGHT / 2)).length(); if (d < bestDistance) { bestDistance = d; best = t; } }
        return best;
    }
    /** Moves focus to the nearest interactive element in the given direction. */
    void padFocus(Vec2 direction) {
        List<Box> targets = focusTargets();
        if (targets.isEmpty()) return;
        Box current = focusedRect(targets);
        if (current == null) { Box fallback = autoTarget(targets); if (fallback != null) mouseMoved(fallback.mid()); return; }
        Vec2 origin = current.mid();
        Box best = null; float bestScore = 0;
        for (Box target : targets) {
            if (target.mid().equals(origin)) continue;
            Vec2 offset = target.mid().minus(origin);
            float along = offset.x * direction.x + offset.y * direction.y;
            if (along <= 4) continue;
            float score = along + Math.abs(offset.x * direction.y - offset.y * direction.x) * 2.5f;
            if (best == null || score < bestScore) { best = target; bestScore = score; }
        }
        if (best != null) mouseMoved(best.mid());
    }
    /** The interactive element under the focus point. */
    Box focusedRect(List<Box> targets) {
        if (mouse.x < 0) return null;
        Box best = null;
        for (Box t : targets) if (t.contains(mouse) && (best == null || t.w * t.h < best.w * best.h)) best = t;
        return best;
    }
    /** Draws the highlight around the focused element. */
    @Override void drawPadCursor() {
        if (!padCursor) return;
        List<Box> targets = focusTargets();
        if (targets.isEmpty()) return;
        Box focused = focusedRect(targets);
        if (focused == null) { Box target = autoTarget(targets); if (target != null) mouseMoved(target.mid()); return; }
        float pulse = 0.75f + 0.25f * sin(time * 5);
        renderer.rect(focused.inset(-4), new RGBA(1, 0.8f, 0.35f, 0.10f * pulse));
        renderer.frame(focused.inset(-4), Theme.HIGHLIGHT_GOLD.alpha(pulse), 3);
        renderer.frame(focused.inset(-9), Theme.GLOW.alpha(0.35f * pulse), 2);
    }
}

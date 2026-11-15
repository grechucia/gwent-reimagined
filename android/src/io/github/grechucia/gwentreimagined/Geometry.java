// Basic value types shared by the whole game: points, rectangles, colours, the colour palette and fixed UI positions.
package io.github.grechucia.gwentreimagined;

/** Size of the virtual coordinate space and of a small board card. */
final class Virtual {
    static final float WIDTH = 1920, HEIGHT = 1080;
    static final float CARD_WIDTH = 85, CARD_HEIGHT = 122;
    private Virtual() {}
}

/** Immutable 2D point or vector. */
final class Vec2 {
    final float x, y;
    Vec2(float x, float y) { this.x = x; this.y = y; }
    static final Vec2 NONE = new Vec2(-1, -1);
    Vec2 plus(Vec2 o) { return new Vec2(x + o.x, y + o.y); }
    Vec2 minus(Vec2 o) { return new Vec2(x - o.x, y - o.y); }
    Vec2 times(float s) { return new Vec2(x * s, y * s); }
    float length() { return (float) Math.sqrt(x * x + y * y); }
    @Override public boolean equals(Object o) { return o instanceof Vec2 && ((Vec2) o).x == x && ((Vec2) o).y == y; }
    @Override public int hashCode() { return Float.hashCode(x) * 31 + Float.hashCode(y); }
}

/** Rectangle in virtual coordinates. */
final class Box {
    final float x, y, w, h;
    Box(float x, float y, float w, float h) { this.x = x; this.y = y; this.w = w; this.h = h; }
    /** Whether a point lies inside the rectangle. */
    boolean contains(Vec2 p) { return p.x >= x && p.x <= x + w && p.y >= y && p.y <= y + h; }
    /** Rectangle shrunk (positive) or grown (negative) on every side. */
    Box inset(float a) { return new Box(x + a, y + a, w - 2 * a, h - 2 * a); }
    Vec2 mid() { return new Vec2(x + w / 2, y + h / 2); }
    @Override public boolean equals(Object o) {
        if (!(o instanceof Box)) return false;
        Box b = (Box) o; return b.x == x && b.y == y && b.w == w && b.h == h;
    }
    @Override public int hashCode() { return Float.hashCode(x) * 31 + Float.hashCode(y) * 17 + Float.hashCode(w) * 7 + Float.hashCode(h); }
}

/** RGBA colour. */
final class RGBA {
    final float r, g, b, a;
    RGBA(float r, float g, float b, float a) { this.r = r; this.g = g; this.b = b; this.a = a; }
    static final RGBA WHITE = new RGBA(1, 1, 1, 1), BLACK = new RGBA(0, 0, 0, 1);
    static final RGBA GOLD = new RGBA(0.95f, 0.80f, 0.45f, 1), GOLD_DARK = new RGBA(0.79f, 0.63f, 0.29f, 1);
    /** Grey colour. */
    static RGBA gray(float value) { return new RGBA(value, value, value, 1); }
    static RGBA gray(float value, float alpha) { return new RGBA(value, value, value, alpha); }
    /** Same colour with alpha multiplied. */
    RGBA alpha(float factor) { return new RGBA(r, g, b, a * factor); }
}

/** Colour palette shared by every screen (same values as the iOS/macOS version). */
final class Theme {
    static final RGBA GLOW = new RGBA(1, 0.75f, 0.3f, 1);
    static final RGBA HIGHLIGHT_GOLD = new RGBA(1, 0.85f, 0.4f, 1);
    static final RGBA PALE_GOLD = new RGBA(1, 0.9f, 0.65f, 1);
    static final RGBA CREAM = new RGBA(1, 0.95f, 0.85f, 1);
    static final RGBA TEXT_GOLD = new RGBA(0.96f, 0.85f, 0.56f, 1);
    static final RGBA AMBER = new RGBA(0.93f, 0.72f, 0.2f, 1);
    static final RGBA BRONZE = new RGBA(0.79f, 0.59f, 0.18f, 1);
    static final RGBA PARCHMENT_TEXT = new RGBA(0.92f, 0.87f, 0.76f, 1);
    static final RGBA PARCHMENT = new RGBA(0.95f, 0.91f, 0.82f, 1);
    static final RGBA PARCHMENT_SHADE = new RGBA(0.84f, 0.77f, 0.63f, 1);
    static final RGBA INK = new RGBA(0.22f, 0.15f, 0.06f, 1);
    static final RGBA PANEL_DARK = new RGBA(0.06f, 0.05f, 0.03f, 1);
    static final RGBA WOOD_BROWN = new RGBA(0.55f, 0.4f, 0.12f, 1);
    static final RGBA LINK_BLUE = new RGBA(0.55f, 0.78f, 1, 1);
    static final RGBA FROST_BLUE = new RGBA(0.8f, 0.92f, 1, 1);
    static final RGBA POSITIVE = new RGBA(0.5f, 0.9f, 0.5f, 1);
    static final RGBA NEGATIVE = new RGBA(1, 0.55f, 0.45f, 1);
    static final RGBA FIRE = new RGBA(1, 0.45f, 0.1f, 1);
    private Theme() {}
}

/** Elements shared by many screens. */
final class ScreenLayout {
    static final Box BACK_BUTTON = new Box(40, 24, 190, 50);
    static final Box WIDE_BACK_BUTTON = new Box(40, 24, 220, 50);
    static final Box DECK_BACK_BUTTON = new Box(40, 24, 200, 50);
    static final Box QUIT_BUTTON = new Box(1690, 24, 190, 46);
    static final Box OPTIONS_PANEL = new Box(360, 40, 1200, 1000);
    static final Box LICENSES_PANEL = new Box(360, 110, 1200, 860);
    static final Box RULES_PANEL = new Box(260, 90, 1400, 940);
    static final Box SAVE_PROMPT_PANEL = new Box(360, 120, 1200, 840);
    static final Box CARD_PREVIEW_CARD = new Box(1538, 232, 330, 474);
    static final Box CARD_PREVIEW_TEXT = new Box(1528, 714, 350, 360);
    private ScreenLayout() {}
}

/** Deck builder screen. */
final class BuilderLayout {
    static final Box COLLECTION_COLUMN = new Box(40, 222, 800, 818);
    static final Box DECK_COLUMN = new Box(1080, 222, 800, 818);
    static final Box LEADER_CARD = new Box(895, 196, 130, 187);
    static final Box CHANGE_LEADER_BUTTON = new Box(875, 386, 170, 28);
    static final Box SAVE_BUTTON = new Box(865, 800, 190, 52);
    static final Box START_BUTTON = new Box(865, 862, 190, 52);
    private BuilderLayout() {}
}

/** Career ladder screen. */
final class CareerLayout {
    static final Box CHAPTERS_COLUMN = new Box(40, 150, 380, 640);
    static final Box DECK_COLUMN = new Box(1520, 150, 360, 640);
    private CareerLayout() {}
}

/** Read-only deck preview. */
final class DeckPreviewLayout {
    static final Box INFO_PANEL = new Box(60, 150, 400, 830);
    static final Box CARDS_AREA = new Box(490, 150, 1370, 830);
    private DeckPreviewLayout() {}
}

/** Fixed positions of board elements (they match the board image). */
final class BoardLayout {
    static final float ROWS_LEFT = 567, ROWS_WIDTH = 946, ROW_SCORE_X = 534;
    static final Box ALL_ROWS = new Box(567, 5, 946, 816);
    static final Box HUMAN_PANEL = new Box(0, 666, 450, 135);
    static final Box COMPUTER_PANEL = new Box(0, 263, 450, 135);
    static final Box RULES_BUTTON = new Box(1540, 16, 190, 46);
    static final Box PASS_BUTTON = new Box(292, 848, 150, 50);
    static final Box GIVE_UP_BUTTON = new Box(292, 944, 150, 50);
    static final Box EXIT_BUTTON = new Box(1680, 1018, 180, 46);
    static final float MUSIC_BUTTONS_X = 1570, BOTTOM_BUTTONS_Y = 1018;
    static final Box HAND = new Box(580, 843, 932, 128);
    static final Box WEATHER_SLOT = new Box(141, 448, 279, 138);
    static final Box HUMAN_LEADER = new Box(142, 835, 96, 132);
    static final Box COMPUTER_LEADER = new Box(142, 83, 96, 132);
    static final Box FACTION_ABILITY_BUTTON = new Box(160, 612, 150, 34);
    static final Box ROW_CHOICE_BAR = new Box(560, 820, 960, 46);
    static final Box END_OF_MATCH_BANNER = new Box(660, 90, 600, 360);
    private BoardLayout() {}
}

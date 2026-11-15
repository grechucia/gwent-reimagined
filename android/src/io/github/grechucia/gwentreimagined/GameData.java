// Static game data loaded from JSON (cards, decks, factions, abilities) and localisation helpers.
package io.github.grechucia.gwentreimagined;

import android.content.res.AssetManager;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

/** Static definition of a card loaded from cards.json. */
final class CardData {
    final String key, name, deck, row, filename, quote, target;
    final int strength, count;
    final List<String> abilities, targets;
    CardData(String key, String name, String deck, String row, int strength, List<String> abilities, String filename,
             int count, String quote, String target, List<String> targets) {
        this.key = key; this.name = name; this.deck = deck; this.row = row; this.strength = strength; this.abilities = abilities;
        this.filename = filename; this.count = count; this.quote = quote; this.target = target; this.targets = targets;
    }
    String faction() { int space = deck.indexOf(' '); return space < 0 ? deck : deck.substring(0, space); }
    boolean isSpecial() { return faction().equals("special"); }
    boolean isWeather() { return faction().equals("weather"); }
    boolean isLeader() { return row.equals("leader"); }
    boolean isHero() { return abilities.contains("hero"); }
    boolean isUnit() { return !isSpecial() && !isWeather() && !isLeader(); }
    String image() { return "img/sm/" + faction() + "_" + filename + ".jpg"; }
}

/** One card entry of a deck: card key and number of copies. */
final class DeckEntry {
    final String key; final int count;
    DeckEntry(String key, int count) { this.key = key; this.count = count; }
}

/** A deck: title, description, leader, faction and card counts. */
final class DeckData {
    final String title, description, leader, faction;
    final List<DeckEntry> cards;
    DeckData(String title, String description, String leader, String faction, List<DeckEntry> cards) {
        this.title = title; this.description = description; this.leader = leader; this.faction = faction; this.cards = cards;
    }
}

/** A paragraph of the rules text. */
final class RulesBlock {
    final String text; final boolean heading;
    RulesBlock(String text, boolean heading) { this.text = text; this.heading = heading; }
}

/** All static game data and the active translation. */
final class GameData {
    static GameData shared;
    final Map<String, CardData> cards = new HashMap<>();
    final List<DeckData> decks = new ArrayList<>();
    final Map<String, Map<String, String>> factions = new HashMap<>();
    final Map<String, Map<String, String>> abilities = new HashMap<>();
    /** Language code -> section name ("cards", "ui"...) -> parsed JSON object. */
    final Map<String, JSONObject> lang = new HashMap<>();
    String language = "en";
    static final String[][] LANGUAGES = {
        {"de", "Deutsch"}, {"en", "English"}, {"es", "Español"}, {"fr", "Français"}, {"it", "Italiano"}, {"pl", "Polski"},
        {"pt", "Português"}, {"ru", "Русский"}, {"zh", "中文"}, {"ja", "日本語"}, {"ko", "한국어"}};

    /** Whether a translation exists for a language code. */
    boolean hasTranslation(String code) { return code.equals("en") || lang.containsKey(code); }
    /** Native name of a language. */
    static String languageName(String code) { for (String[] l : LANGUAGES) if (l[0].equals(code)) return l[1]; return code; }

    GameData(AssetManager assets) {
        try {
            JSONObject cardsJSON = new JSONObject(read(assets, "data/cards.json"));
            for (Iterator<String> it = cardsJSON.keys(); it.hasNext();) {
                String k = it.next(); JSONObject v = cardsJSON.getJSONObject(k);
                String ability = str(v.opt("ability"));
                List<String> abilityList = ability.isEmpty() ? new ArrayList<>() : new ArrayList<>(Arrays.asList(ability.trim().split("\\s+")));
                List<String> targets = new ArrayList<>();
                Object target = v.opt("target");
                if (target instanceof JSONArray) { JSONArray a = (JSONArray) target; for (int i = 0; i < a.length(); i++) targets.add(a.optString(i)); }
                else if (!str(target).isEmpty()) targets.add(str(target));
                cards.put(k, new CardData(k, str(v.opt("name")), str(v.opt("deck")), str(v.opt("row")), integer(v.opt("strength")), abilityList,
                        str(v.opt("filename")), Math.max(1, integer(v.opt("count"))), str(v.opt("quote")), target instanceof JSONArray ? "" : str(target), targets));
            }
            JSONArray decksJSON = new JSONArray(read(assets, "data/decks.json"));
            for (int i = 0; i < decksJSON.length(); i++) {
                JSONObject entry = decksJSON.getJSONObject(i);
                List<DeckEntry> list = new ArrayList<>();
                JSONArray cardList = entry.optJSONArray("cards");
                if (cardList != null) for (int j = 0; j < cardList.length(); j++) {
                    JSONArray pair = cardList.optJSONArray(j);
                    if (pair == null || pair.length() < 2) continue;
                    list.add(new DeckEntry(pair.optString(0), pair.optInt(1, 1)));
                }
                DeckData deck = new DeckData(str(entry.opt("title")), str(entry.opt("description")), str(entry.opt("leader")), str(entry.opt("faction")), list);
                if (cards.containsKey(deck.leader)) decks.add(deck);
            }
            readNested(read(assets, "data/factions.json"), factions);
            readNested(read(assets, "data/abilities.json"), abilities);
            for (String[] l : LANGUAGES) {
                String text = read(assets, "data/lang_" + l[0] + ".json");
                if (text == null) continue;
                JSONObject languageFile = new JSONObject(text);
                String extra = read(assets, "data/ui_" + l[0] + ".json");
                if (extra != null) {
                    JSONObject ui = languageFile.optJSONObject("ui");
                    if (ui == null) { ui = new JSONObject(); languageFile.put("ui", ui); }
                    JSONObject extraJSON = new JSONObject(extra);
                    for (Iterator<String> it = extraJSON.keys(); it.hasNext();) { String k = it.next(); ui.put(k, extraJSON.get(k)); }
                }
                lang.put(l[0], languageFile);
            }
        } catch (Exception e) { throw new RuntimeException("Game data", e); }
    }

    private static void readNested(String text, Map<String, Map<String, String>> into) throws Exception {
        if (text == null) return;
        JSONObject o = new JSONObject(text);
        for (Iterator<String> it = o.keys(); it.hasNext();) {
            String k = it.next(); JSONObject inner = o.optJSONObject(k); if (inner == null) continue;
            Map<String, String> m = new HashMap<>();
            for (Iterator<String> j = inner.keys(); j.hasNext();) { String f = j.next(); m.put(f, str(inner.opt(f))); }
            into.put(k, m);
        }
    }
    /** Reads a text asset, or null if it does not exist. */
    static String read(AssetManager assets, String path) {
        try (InputStream in = assets.open(path)) {
            ByteArrayOutputStream out = new ByteArrayOutputStream(); byte[] buf = new byte[65536]; int n;
            while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
            return new String(out.toByteArray(), StandardCharsets.UTF_8);
        } catch (Exception e) { return null; }
    }
    /** Reads a JSON value as a string. */
    static String str(Object value) {
        if (value == null || value == JSONObject.NULL) return "";
        if (value instanceof Number) { Number n = (Number) value; return n.doubleValue() == Math.rint(n.doubleValue()) ? String.valueOf(n.longValue()) : n.toString(); }
        return value.toString();
    }
    /** Reads a JSON value as an integer. */
    static int integer(Object value) {
        if (value instanceof Number) return ((Number) value).intValue();
        try { return Integer.parseInt(str(value).trim()); } catch (Exception e) { return 0; }
    }

    /** Section of the active translation file. */
    JSONObject section(String name) {
        JSONObject file = lang.get(language);
        JSONObject s = file == null ? null : file.optJSONObject(name);
        return s == null ? new JSONObject() : s;
    }
    private String localized(String sectionName, String key, String field) {
        JSONObject entry = section(sectionName).optJSONObject(key);
        String value = entry == null ? null : entry.optString(field, null);
        return value == null || value.isEmpty() ? null : value;
    }
    /** Localised card name. */
    String cardName(CardData c) { String v = localized("cards", c.key, "name"); return v != null ? v : c.name; }
    /** Localised card quote. */
    String cardQuote(CardData c) { String v = localized("cards", c.key, "quote"); return v != null ? v : c.quote; }
    /** Localised ability name. */
    String abilityName(String key) {
        String v = localized("abilities", key, "name"); if (v != null) return v;
        Map<String, String> a = abilities.get(key); return a != null && a.get("name") != null ? a.get("name") : key;
    }
    /** Localised ability description. */
    String abilityDesc(String key) {
        String v = localized("abilities", key, "description"); if (v != null) return v;
        Map<String, String> a = abilities.get(key); return a != null && a.get("description") != null ? a.get("description") : "";
    }
    /** Localised faction name. */
    String factionName(String key) {
        String v = localized("factions", key, "name"); if (v != null) return v;
        Map<String, String> a = factions.get(key); return a != null && a.get("name") != null ? a.get("name") : key;
    }
    /** Localised faction description. */
    String factionDesc(String key) {
        String v = localized("factions", key, "description"); if (v != null) return v;
        Map<String, String> a = factions.get(key); return a != null && a.get("description") != null ? a.get("description") : "";
    }
    /** Localised rules text, split into headings and paragraphs. */
    List<RulesBlock> rules() {
        JSONObject file = lang.get(language);
        JSONObject blocks = file == null ? null : file.optJSONObject("blocks");
        if (blocks == null && lang.get("en") != null) blocks = lang.get("en").optJSONObject("blocks");
        List<RulesBlock> paragraphs = new ArrayList<>();
        if (blocks == null) return paragraphs;
        for (int i = 1; i <= 138; i++) {
            String h = blocks.optString("b" + i, null);
            if (h == null) continue;
            h = h.replace("<br>", "\n").replace("<br/>", "\n");
            String plain = h.replaceAll("<[^>]+>", "");
            String[][] entities = {{"&amp;", "&"}, {"&quot;", "\""}, {"&#39;", "'"}, {"&lt;", "<"}, {"&gt;", ">"}, {"&nbsp;", " "}};
            for (String[] e : entities) plain = plain.replace(e[0], e[1]);
            plain = plain.trim();
            if (plain.isEmpty()) continue;
            boolean heading = plain.codePointCount(0, plain.length()) <= 48 && !plain.endsWith(".") && !plain.endsWith(":") && !plain.contains("\n");
            paragraphs.add(new RulesBlock(plain, heading));
        }
        return paragraphs;
    }
    /** Translates an English UI string into the active language. */
    String ui(String english) {
        if (language.equals("en")) return english;
        String v = section("ui").optString(english, null);
        return v != null ? v : english;
    }
    /** Translates an English UI string (shorthand used across the UI). */
    static String L(String english) { return shared.ui(english); }
}

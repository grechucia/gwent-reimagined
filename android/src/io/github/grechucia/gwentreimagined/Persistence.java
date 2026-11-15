// Save file (shared format with iOS/macOS), career mode generation and the deck-building model.
package io.github.grechucia.gwentreimagined;

import android.content.ContentResolver;
import android.content.Context;
import android.content.SharedPreferences;
import android.net.Uri;
import android.provider.DocumentsContract;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import static io.github.grechucia.gwentreimagined.GameData.L;

/** Single JSON save file holding the career, custom decks, favourite deck and player name. */
final class SaveStore {
    static SaveStore shared;
    static final String FILE_NAME = "GwentReimagined-save.json";
    private final Context context;
    private final SharedPreferences prefs;
    JSONObject data = new JSONObject();

    SaveStore(Context context) {
        this.context = context;
        prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE);
        load();
    }
    /** Folder chosen with the system picker (a document tree), or null for the app's own storage. */
    private Uri treeUri() { String s = prefs.getString("saveTree", null); return s == null ? null : Uri.parse(s); }
    /** Whether the player has already chosen where to save. */
    boolean chosen() { return prefs.getBoolean("saveChosen", false); }
    /** Human-readable save location shown in Options. */
    String displayPath() {
        Uri tree = treeUri();
        if (tree == null) return L("On this device");
        String id = DocumentsContract.getTreeDocumentId(tree);
        return id.contains(":") ? id.substring(id.indexOf(':') + 1) : id;
    }
    private File localFile() { return new File(context.getFilesDir(), FILE_NAME); }

    /** Reads the save file from the current location. */
    void load() {
        try {
            String text;
            Uri tree = treeUri();
            if (tree == null) {
                File f = localFile(); if (!f.exists()) return;
                byte[] bytes = java.nio.file.Files.readAllBytes(f.toPath()); text = new String(bytes, StandardCharsets.UTF_8);
            } else {
                Uri doc = findDocument(tree); if (doc == null) return;
                try (InputStream in = context.getContentResolver().openInputStream(doc)) { text = readAll(in); }
            }
            data = new JSONObject(text);
        } catch (Exception ignored) {}
    }
    /** Writes the save file to the current location. */
    void save() {
        try {
            byte[] bytes = data.toString(1).getBytes(StandardCharsets.UTF_8);
            Uri tree = treeUri();
            if (tree == null) { try (FileOutputStream out = new FileOutputStream(localFile())) { out.write(bytes); } return; }
            Uri doc = findDocument(tree);
            ContentResolver resolver = context.getContentResolver();
            if (doc == null) doc = DocumentsContract.createDocument(resolver, DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree)), "application/json", FILE_NAME);
            if (doc == null) return;
            try (OutputStream out = resolver.openOutputStream(doc, "wt")) { out.write(bytes); }
        } catch (Exception ignored) {}
    }
    /** The save file inside a chosen folder, if it exists. */
    private Uri findDocument(Uri tree) {
        ContentResolver resolver = context.getContentResolver();
        Uri children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree));
        try (android.database.Cursor c = resolver.query(children, new String[]{DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME}, null, null, null)) {
            while (c != null && c.moveToNext()) if (FILE_NAME.equals(c.getString(1))) return DocumentsContract.buildDocumentUriUsingTree(tree, c.getString(0));
        } catch (Exception ignored) {}
        return null;
    }
    private static String readAll(InputStream in) throws Exception {
        java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream(); byte[] buf = new byte[65536]; int n;
        while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
        return new String(out.toByteArray(), StandardCharsets.UTF_8);
    }

    Object get(String key) { return data.opt(key); }
    /** Stores a value (null removes it) and saves immediately. */
    void set(String key, Object value) {
        try { if (value == null) data.remove(key); else data.put(key, value); } catch (Exception ignored) {}
        save();
    }
    String getString(String key) { Object v = data.opt(key); return v instanceof String ? (String) v : null; }

    /** Uses the app's own storage. */
    void chooseLocal() { switchTo(null); }
    /** Uses a folder chosen with the system folder picker. */
    void chooseFolder(Uri tree) { switchTo(tree); }
    private void switchTo(Uri tree) {
        JSONObject current = data;
        prefs.edit().putBoolean("saveChosen", true).putString("saveTree", tree == null ? null : tree.toString()).apply();
        data = new JSONObject();
        load();
        if (data.length() == 0) { data = current; save(); }
    }
}

/** Deterministic xorshift random generator, so a career seed always produces the same chapters (same algorithm as Swift). */
final class SeededRNG {
    private long state;
    SeededRNG(long seed) { state = seed * 0x9E3779B97F4A7C15L | 1; }
    long next() { state ^= state << 13; state ^= state >>> 7; state ^= state << 17; return state; }
    /** Uniform integer in 0..<upperBound using Lemire's method, matching Swift's `Int.random(in:using:)`. */
    int nextInt(int upperBound) {
        long bound = upperBound;
        long random = next();
        long low = random * bound, high = unsignedMultiplyHigh(random, bound);
        if (Long.compareUnsigned(low, bound) < 0) {
            long threshold = Long.remainderUnsigned(-bound, bound);
            while (Long.compareUnsigned(low, threshold) < 0) { random = next(); low = random * bound; high = unsignedMultiplyHigh(random, bound); }
        }
        return (int) high;
    }
    private static long unsignedMultiplyHigh(long a, long b) {
        long aLow = a & 0xFFFFFFFFL, aHigh = a >>> 32, bLow = b & 0xFFFFFFFFL, bHigh = b >>> 32;
        long lowLow = aLow * bLow, highLow = aHigh * bLow, lowHigh = aLow * bHigh, highHigh = aHigh * bHigh;
        long cross = (lowLow >>> 32) + (highLow & 0xFFFFFFFFL) + lowHigh;
        return highHigh + (highLow >>> 32) + (cross >>> 32);
    }
    /** Shuffles a list in place with Swift's algorithm. */
    <T> void shuffle(List<T> list) {
        int amount = list.size(), current = 0;
        while (amount > 1) { int random = nextInt(amount); amount -= 1; Collections.swap(list, current, current + random); current++; }
    }
    <T> T randomElement(List<T> list) { return list.isEmpty() ? null : list.get(nextInt(list.size())); }
}

/** One career opponent: display name, portrait card, faction, card strength cap, hero count and boss flag. */
final class CareerFight {
    final String name, portrait, faction; final int cap, heroes; final boolean boss;
    CareerFight(String name, String portrait, String faction, int cap, int heroes, boolean boss) {
        this.name = name; this.portrait = portrait; this.faction = faction; this.cap = cap; this.heroes = heroes; this.boss = boss;
    }
}

/** A generated career chapter. */
final class CareerChapter {
    final String title; final List<CareerFight> fights;
    CareerChapter(String title, List<CareerFight> fights) { this.title = title; this.fights = fights; }
}

/** Career mode state and generation. */
final class Career {
    static Career shared;
    GameData gameData() { return GameData.shared; }
    String faction = "";
    int difficulty = 1;
    List<String> leaders = new ArrayList<>();
    String leader = "";
    Map<String, Integer> collection = new TreeMap<>(), deck = new TreeMap<>();
    Set<Integer> beaten = new HashSet<>();
    long seed;
    boolean active() { return !faction.isEmpty(); }

    static final String[] DIFFICULTY_NAMES = {"Easy", "Normal", "Hard"};
    int chapterCount() { return new int[]{6, 8, 10}[difficulty]; }
    static final String[] PLACES = {"White Orchard", "Velen", "Novigrad", "Oxenfurt", "Vizima", "Kaer Morhen", "Skellige", "Toussaint", "Beauclair", "Cintra", "Mahakam",
        "Brokilon", "Kovir", "Vengerberg", "Zerrikania", "Ofir", "Crow's Perch", "Gors Velen", "Lyria", "Rivia", "Nilfgaard"};

    long rngBase() { return seed * 31 + difficulty; }
    private final Map<Integer, CareerChapter> cache = new HashMap<>();
    private String cacheKey = "";
    /** Returns the title and the four fights of a chapter (cached per seed, difficulty and language). */
    CareerChapter chapter(int chapter) {
        String key = seed + "|" + difficulty + "|" + gameData().language;
        if (!key.equals(cacheKey)) { cache.clear(); cacheKey = key; }
        CareerChapter cached = cache.get(chapter);
        if (cached != null) return cached;
        CareerChapter generated = makeChapter(chapter); cache.put(chapter, generated); return generated;
    }
    /** Generates a chapter: three regular opponents and a boss whose strength grows with progress. */
    CareerChapter makeChapter(int chapter) {
        SeededRNG rng = new SeededRNG(rngBase() + chapter * 1_000_003L);
        SeededRNG orderRng = new SeededRNG(rngBase());
        List<Integer> order = new ArrayList<>(); for (int i = 0; i < PLACES.length; i++) order.add(i);
        orderRng.shuffle(order);
        String place = PLACES[order.get(chapter % order.size())];
        boolean last = chapter == chapterCount() - 1;
        int difficultyOffset = difficulty - 1;
        float progress = (float) chapter / Math.max(1, chapterCount() - 1);
        int base = Math.round(progress * 6) + (difficultyOffset < 0 ? -1 : difficultyOffset);
        int heroesBase = Math.max(0, Math.round(progress * 3) + difficultyOffset - 1);
        List<CareerFight> fights = new ArrayList<>();
        for (int slot = 0; slot < 4; slot++) {
            boolean boss = slot == 3;
            String opponentFaction = rng.randomElement(DeckBuilder.FACTIONS_ORDER);
            int cap = boss ? base + 2 : base + (slot == 2 ? 1 : 0);
            if (cap >= 11 || (boss && last)) cap = 99;
            int heroes = boss ? Math.min(7, heroesBase + 1 + (last ? 2 : 0)) : Math.max(0, heroesBase - 1 + (slot == 2 ? 1 : 0));
            CareerFight draft = new CareerFight("", "", opponentFaction, Math.max(2, cap), heroes, boss);
            DeckData generatedDeck = opponentDeck(index(chapter, slot), draft);
            String portraitKey = generatedDeck.leader;
            if (!boss) {
                CardData strongest = null;
                for (DeckEntry e : generatedDeck.cards) { CardData d = gameData().cards.get(e.key); if (d != null && d.isUnit() && (strongest == null || d.strength > strongest.strength)) strongest = d; }
                if (strongest != null) portraitKey = strongest.key;
            }
            CardData portrait = gameData().cards.get(portraitKey);
            String displayName = portrait != null ? gameData().cardName(portrait) : opponentFaction;
            fights.add(new CareerFight(displayName, portraitKey, opponentFaction, draft.cap, heroes, boss));
        }
        return new CareerChapter(L(place), fights);
    }
    /** Global index of a fight. */
    int index(int chapter, int slot) { return chapter * 4 + slot; }
    /** Whether a fight can be played. */
    boolean unlocked(int chapter, int slot) {
        if (chapter > 0 && !beaten.contains(index(chapter - 1, 3))) return false;
        if (slot < 3) return true;
        for (int s = 0; s < 3; s++) if (!beaten.contains(index(chapter, s))) return false;
        return true;
    }
    int currentChapter() { for (int c = 0; c < chapterCount(); c++) if (!beaten.contains(index(c, 3))) return c; return chapterCount() - 1; }
    boolean finished() { return beaten.contains(index(chapterCount() - 1, 3)); }
    int totalFights() { return chapterCount() * 4; }

    Career() { load(); }
    /** Loads the career from the save file. */
    void load() {
        faction = ""; leaders = new ArrayList<>(); leader = ""; collection = new TreeMap<>(); deck = new TreeMap<>(); beaten = new HashSet<>();
        Object savedObject = SaveStore.shared.get("career");
        if (!(savedObject instanceof JSONObject)) return;
        JSONObject saved = (JSONObject) savedObject;
        faction = saved.optString("faction", "");
        JSONArray l = saved.optJSONArray("leaders"); if (l != null) for (int i = 0; i < l.length(); i++) leaders.add(l.optString(i));
        leader = saved.optString("leader", leaders.isEmpty() ? "" : leaders.get(0));
        readCounts(saved.optJSONObject("collection"), collection);
        readCounts(saved.optJSONObject("deck"), deck);
        JSONArray b = saved.optJSONArray("beaten"); if (b != null) for (int i = 0; i < b.length(); i++) beaten.add(b.optInt(i));
        seed = saved.optLong("seed", 0);
        difficulty = saved.optInt("difficulty", 1);
    }
    private static void readCounts(JSONObject o, Map<String, Integer> into) {
        if (o == null) return;
        for (Iterator<String> it = o.keys(); it.hasNext();) { String k = it.next(); into.put(k, o.optInt(k)); }
    }
    /** Stores the career in the save file. */
    void save() {
        if (!active()) { SaveStore.shared.set("career", null); return; }
        try {
            JSONObject o = new JSONObject();
            o.put("faction", faction); o.put("leaders", new JSONArray(leaders)); o.put("leader", leader);
            o.put("collection", new JSONObject(collection)); o.put("deck", new JSONObject(deck));
            List<Integer> sorted = new ArrayList<>(beaten); Collections.sort(sorted); o.put("beaten", new JSONArray(sorted));
            o.put("seed", seed); o.put("difficulty", difficulty);
            SaveStore.shared.set("career", o);
        } catch (Exception ignored) {}
    }
    /** Abandons the current career. */
    void reset() { faction = ""; leaders = new ArrayList<>(); leader = ""; collection = new TreeMap<>(); deck = new TreeMap<>(); beaten = new HashSet<>(); save(); }

    /** All cards of a faction that can appear in decks. */
    List<CardData> pool(String faction) { DeckBuilder builder = new DeckBuilder(); builder.faction = faction; return builder.collection(); }
    private List<CardData> leadersOf(String faction) {
        List<CardData> r = new ArrayList<>();
        for (CardData d : gameData().cards.values()) if (d.isLeader() && d.faction().equals(faction)) r.add(d);
        r.sort(Comparator.comparing(d -> d.key));
        return r;
    }

    /** Starts a new career: random seed, first leader and a starter deck of weak units. */
    void start(String chosenFaction, int level) {
        faction = chosenFaction; difficulty = level; beaten = new HashSet<>(); seed = 1 + new java.util.Random().nextInt(999_999);
        List<CardData> factionPool = pool(chosenFaction);
        List<CardData> leaderCards = leadersOf(chosenFaction);
        leaders = new ArrayList<>(); if (!leaderCards.isEmpty()) leaders.add(leaderCards.get(0).key);
        leader = leaders.isEmpty() ? "" : leaders.get(0);
        int cap = 6 - (difficulty - 1);
        List<CardData> units;
        while (true) {
            final int c = cap;
            units = new ArrayList<>();
            int copies = 0;
            for (CardData d : factionPool) if (d.isUnit() && !d.isHero() && d.strength <= c && !d.abilities.contains("spy")) { units.add(d); copies += d.count; }
            if (copies >= 24 || cap > 12) break;
            cap++;
        }
        collection = new TreeMap<>();
        units.sort((a, b) -> b.strength - a.strength);
        int cardCount = 0;
        for (CardData unit : units) { if (cardCount >= 22) break; int copies = Math.min(unit.count, 22 - cardCount); collection.put(unit.key, copies); cardCount += copies; }
        int weather = 0;
        for (CardData d : factionPool) if (d.isWeather() && weather < 2) { collection.put(d.key, 1); weather++; }
        for (String specialKey : new String[]{"spe_horn", "spe_decoy"}) if (gameData().cards.containsKey(specialKey)) collection.put(specialKey, 1);
        deck = new TreeMap<>(collection);
        save();
    }
    DeckData playerDeck() {
        List<DeckEntry> cards = new ArrayList<>();
        for (Map.Entry<String, Integer> e : deck.entrySet()) cards.add(new DeckEntry(e.getKey(), e.getValue()));
        return new DeckData(L("Career deck"), "", leader, faction, cards);
    }
    int deckUnits() { int n = 0; for (Map.Entry<String, Integer> e : deck.entrySet()) { CardData d = gameData().cards.get(e.getKey()); if (d != null && d.isUnit()) n += e.getValue(); } return n; }

    /** Builds the opponent's deck for a fight (premade deck for the final boss). */
    DeckData opponentDeck(int fightIndex, CareerFight fight) {
        if (fight.boss && fight.cap >= 99) {
            SeededRNG bossRng = new SeededRNG(rngBase() + fightIndex);
            List<DeckData> premade = new ArrayList<>();
            for (DeckData d : gameData().decks) if (d.faction.equals(fight.faction)) premade.add(d);
            DeckData chosen = bossRng.randomElement(premade);
            if (chosen != null) return chosen;
        }
        SeededRNG rng = new SeededRNG(rngBase() + fightIndex * 7919L);
        List<CardData> factionPool = pool(fight.faction);
        int cap = fight.cap;
        while (cap < 15) {
            int copies = 0; for (CardData d : factionPool) if (d.isUnit() && !d.isHero() && d.strength <= cap) copies += d.count;
            if (copies >= 18) break;
            cap++;
        }
        final int finalCap = cap;
        List<CardData> unitPool = new ArrayList<>();
        for (CardData d : factionPool) if (d.isUnit() && !d.isHero() && d.strength <= finalCap && (fight.boss || !d.abilities.contains("spy"))) unitPool.add(d);
        rng.shuffle(unitPool);
        List<CardData> units = new ArrayList<>(unitPool);
        if (!fight.boss) units.sort(Comparator.comparingInt(d -> d.strength));
        List<CardData> heroPool = new ArrayList<>(); for (CardData d : factionPool) if (d.isUnit() && d.isHero()) heroPool.add(d);
        rng.shuffle(heroPool);
        List<CardData> specialPool = new ArrayList<>(); for (CardData d : factionPool) if (!d.isUnit()) specialPool.add(d);
        rng.shuffle(specialPool);
        List<DeckEntry> cards = new ArrayList<>();
        for (int i = 0; i < Math.min(fight.heroes, heroPool.size()); i++) cards.add(new DeckEntry(heroPool.get(i).key, 1));
        int count = cards.size();
        for (CardData unit : units) { if (count >= 20) break; int copies = Math.min(unit.count, 20 - count); cards.add(new DeckEntry(unit.key, copies)); count += copies; }
        for (int i = 0; i < Math.min(Math.min(4, fight.heroes), specialPool.size()); i++) cards.add(new DeckEntry(specialPool.get(i).key, 1));
        List<CardData> leaderCards = leadersOf(fight.faction);
        CardData lead = leaderCards.isEmpty() ? null : (fight.boss ? leaderCards.get(leaderCards.size() - 1) : leaderCards.get(0));
        return new DeckData(fight.name, "", lead != null ? lead.key : "", fight.faction, cards);
    }

    /** Three cards offered as a reward after winning a fight. */
    List<String> rewardOptions(int fightIndex) {
        int chapter = fightIndex / 4; boolean boss = fightIndex % 4 == 3;
        float progress = (float) chapter / Math.max(1, chapterCount() - 1);
        int cap = progress > 0.8f ? 99 : 5 + (int) (progress * 7);
        SeededRNG rng = new SeededRNG(seed + fightIndex * 104_729L + beaten.size());
        List<CardData> available = new ArrayList<>();
        for (CardData d : pool(faction)) if (collection.getOrDefault(d.key, 0) < d.count) available.add(d);
        List<CardData> candidates = new ArrayList<>();
        for (CardData d : available) if (boss ? (d.isUnit() && d.isHero()) : (!d.isHero() && (!d.isUnit() || d.strength <= cap))) candidates.add(d);
        if (candidates.size() < 3) candidates = new ArrayList<>(available);
        candidates.sort((a, b) -> (b.isUnit() ? b.strength : 3) - (a.isUnit() ? a.strength : 3));
        List<CardData> top = new ArrayList<>(candidates.subList(0, Math.min(Math.max(6, candidates.size() / 2), candidates.size())));
        rng.shuffle(top);
        List<String> keys = new ArrayList<>();
        for (int i = 0; i < Math.min(3, top.size()); i++) keys.add(top.get(i).key);
        return keys;
    }
    /** Marks a fight as won; bosses also unlock a new leader, whose key is returned. */
    String win(int fightIndex) {
        beaten.add(fightIndex);
        String newLeader = null;
        if (fightIndex % 4 == 3) for (CardData d : leadersOf(faction)) if (!leaders.contains(d.key)) { leaders.add(d.key); newLeader = d.key; break; }
        save();
        return newLeader;
    }
    /** Adds a reward card to the collection and, if possible, to the deck. */
    void take(String key) {
        collection.merge(key, 1, Integer::sum);
        int specials = 0;
        for (Map.Entry<String, Integer> e : deck.entrySet()) { CardData d = gameData().cards.get(e.getKey()); if (d != null && !d.isUnit()) specials += e.getValue(); }
        CardData d = gameData().cards.get(key);
        if ((d != null && d.isUnit()) || specials < 10) deck.merge(key, 1, Integer::sum);
        save();
    }
}

/** Editable deck: faction, leader and card counts, with optional career card limits. */
final class DeckBuilder {
    String faction = "realms", leaderKey = "", title = "";
    Map<String, Integer> counts = new TreeMap<>();
    Integer editingIndex;
    float scrollL, scrollR;
    Map<String, Integer> limit;
    List<String> ownedLeaders;
    boolean careerMode() { return limit != null; }
    GameData gameData() { return GameData.shared; }
    static final List<String> FACTIONS_ORDER = Arrays.asList("realms", "nilfgaard", "monsters", "scoiatael", "skellige", "witcher_universe", "toussaint", "lyria_rivia",
        "syndicate", "zerrikania", "redania", "velen", "wild_hunt", "novigrad", "ofir");

    /** Maximum copies of a card allowed in the deck. */
    int cap(CardData d) { return Math.min(d.count, limit != null && limit.containsKey(d.key) ? limit.get(d.key) : d.count); }
    /** Loads the career deck and the owned cards as limits. */
    void loadCareer() {
        Career career = Career.shared;
        faction = career.faction; leaderKey = career.leader; counts = new TreeMap<>(career.deck); title = ""; editingIndex = null;
        limit = new TreeMap<>(career.collection); ownedLeaders = new ArrayList<>(career.leaders); scrollL = 0; scrollR = 0;
    }
    /** Leaders available for the current faction. */
    List<CardData> leaders() {
        List<CardData> r = new ArrayList<>();
        for (CardData d : gameData().cards.values()) if (d.isLeader() && d.faction().equals(faction) && (ownedLeaders == null || ownedLeaders.contains(d.key))) r.add(d);
        r.sort(Comparator.comparing(d -> d.key));
        return r;
    }
    private static int rank(CardData d) { return d.isLeader() ? 0 : (d.isWeather() ? 1 : (d.isSpecial() ? 2 : 3)); }
    /** Cards that can be added for the current faction, sorted for display. */
    List<CardData> collection() {
        List<CardData> r = new ArrayList<>();
        for (CardData d : gameData().cards.values()) {
            if (d.isLeader()) continue;
            if (limit != null) { if (limit.getOrDefault(d.key, 0) > 0) r.add(d); continue; }
            String[] parts = d.deck.split(" ");
            if (parts[0].equals("neutral")) { r.add(d); continue; }
            if (d.isSpecial() || d.isWeather()) { if (parts.length == 1 || parts[1].equals(faction)) r.add(d); continue; }
            if (parts[0].equals(faction)) r.add(d);
        }
        r.sort((a, b) -> {
            if (rank(a) != rank(b)) return rank(a) - rank(b);
            if (a.strength != b.strength) return b.strength - a.strength;
            int byName = a.name.compareTo(b.name);
            return byName != 0 ? byName : a.key.compareTo(b.key);
        });
        return r;
    }
    /** Loads an existing deck for editing. */
    void load(DeckData deck, Integer customIndex) {
        faction = deck.faction; leaderKey = deck.leader; title = deck.title; editingIndex = customIndex; limit = null; ownedLeaders = null;
        counts = new TreeMap<>();
        for (DeckEntry e : deck.cards) counts.merge(e.key, e.count, Integer::sum);
        scrollL = 0; scrollR = 0;
    }
    /** Starts an empty deck for a faction. */
    void newDeck(String chosenFaction) {
        limit = null; ownedLeaders = null;
        faction = chosenFaction; List<CardData> l = leaders(); leaderKey = l.isEmpty() ? "" : l.get(0).key; counts = new TreeMap<>(); title = ""; editingIndex = null; scrollL = 0; scrollR = 0;
    }
    List<CardData> deckCards() { List<CardData> r = new ArrayList<>(); for (CardData d : collection()) if (counts.getOrDefault(d.key, 0) > 0) r.add(d); return r; }
    /** Deck statistics: total cards, units, specials, unit strength and heroes. */
    int[] stats() {
        int total = 0, units = 0, specials = 0, strength = 0, heroes = 0;
        for (Map.Entry<String, Integer> e : counts.entrySet()) {
            CardData d = gameData().cards.get(e.getKey()); if (d == null) continue;
            int copies = e.getValue(); total += copies;
            if (d.isUnit()) { units += copies; strength += d.strength * copies; if (d.isHero()) heroes += copies; } else specials += copies;
        }
        return new int[]{total, units, specials, strength, heroes};
    }
    boolean valid() { int[] s = stats(); return s[1] >= 22 && s[2] <= 10 && !leaderKey.isEmpty(); }
    /** Adds one copy of a card. */
    void add(CardData d) {
        int current = counts.getOrDefault(d.key, 0);
        if (current >= cap(d)) return;
        if ((d.isSpecial() || d.isWeather()) && stats()[2] >= 10) return;
        counts.put(d.key, current + 1);
    }
    /** Removes one copy of a card. */
    void remove(CardData d) { int remaining = counts.getOrDefault(d.key, 0) - 1; if (remaining > 0) counts.put(d.key, remaining); else counts.remove(d.key); }
    /** Converts the builder state into a playable deck. */
    DeckData asDeck() {
        List<DeckEntry> cards = new ArrayList<>();
        for (Map.Entry<String, Integer> e : counts.entrySet()) cards.add(new DeckEntry(e.getKey(), e.getValue()));
        return new DeckData(title.isEmpty() ? L("My deck") + " — " + gameData().factionName(faction) : title, "", leaderKey, faction, cards);
    }
    /** Reads the player's custom decks from the save file. */
    static List<DeckData> loadCustom() {
        List<DeckData> decks = new ArrayList<>();
        Object saved = SaveStore.shared.get("customDecks");
        if (!(saved instanceof JSONArray)) return decks;
        JSONArray array = (JSONArray) saved;
        for (int i = 0; i < array.length(); i++) {
            JSONObject entry = array.optJSONObject(i); if (entry == null) continue;
            String savedFaction = entry.optString("faction", null), savedLeader = entry.optString("leader", null);
            JSONArray cardList = entry.optJSONArray("cards");
            if (savedFaction == null || savedLeader == null || cardList == null) continue;
            List<DeckEntry> cards = new ArrayList<>();
            for (int j = 0; j < cardList.length(); j++) { JSONArray pair = cardList.optJSONArray(j); if (pair != null && pair.length() > 0) cards.add(new DeckEntry(pair.optString(0), pair.length() > 1 ? pair.optInt(pair.length() - 1, 1) : 1)); }
            decks.add(new DeckData(entry.optString("title", ""), "", savedLeader, savedFaction, cards));
        }
        return decks;
    }
    /** Writes the player's custom decks to the save file. */
    static void saveCustom(List<DeckData> decks) {
        JSONArray array = new JSONArray();
        try {
            for (DeckData d : decks) {
                JSONObject o = new JSONObject(); o.put("title", d.title); o.put("faction", d.faction); o.put("leader", d.leader);
                JSONArray cards = new JSONArray(); for (DeckEntry e : d.cards) cards.put(new JSONArray().put(e.key).put(e.count));
                o.put("cards", cards); array.put(o);
            }
        } catch (Exception ignored) {}
        SaveStore.shared.set("customDecks", array);
    }
    /** Saves the edited deck (custom deck or career deck). */
    void save() {
        if (careerMode()) { Career career = Career.shared; career.deck = new TreeMap<>(counts); career.leader = leaderKey; career.save(); return; }
        List<DeckData> all = loadCustom();
        DeckData deck = asDeck();
        if (editingIndex != null && editingIndex < all.size()) all.set(editingIndex, deck); else { all.add(deck); editingIndex = all.size() - 1; }
        saveCustom(all);
    }
}

// Music and sound effects: menu theme, random in-game tracks and low-latency sound effects.
package io.github.grechucia.gwentreimagined;

import android.content.res.AssetFileDescriptor;
import android.content.res.AssetManager;
import android.media.AudioAttributes;
import android.media.MediaPlayer;
import android.media.SoundPool;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Random;

/** Plays the music (MediaPlayer) and sound effects (SoundPool). */
final class Audio {
    private final AssetManager assets;
    private final SoundPool pool;
    private final Map<String, Integer> sounds = new HashMap<>();
    private final java.util.Set<Integer> loaded = java.util.Collections.synchronizedSet(new java.util.HashSet<>());
    private MediaPlayer music;
    private final List<String> tracks = new ArrayList<>();
    private int lastTrack = -1;
    private final Random random = new Random();
    boolean muted;
    private boolean musicOn = true;
    private boolean menuMode = true;
    private boolean suspended;

    Audio(AssetManager assets) {
        this.assets = assets;
        pool = new SoundPool.Builder().setMaxStreams(10)
            .setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()).build();
        pool.setOnLoadCompleteListener((soundPool, id, status) -> { if (status == 0) loaded.add(id); });
        try {
            String[] files = assets.list("game/audio");
            if (files != null) for (String f : files) if (f.toLowerCase().endsWith(".mp3")) tracks.add(f);
        } catch (Exception ignored) {}
        Collections.sort(tracks);
    }

    boolean musicOn() { return musicOn; }
    void setMusicOn(boolean on) { musicOn = on; if (on) playMusic(); else stopMusic(); }

    /** Loads (and caches) a sound effect. */
    private synchronized Integer sound(String name) {
        Integer id = sounds.get(name);
        if (id != null) return id;
        try (AssetFileDescriptor fd = assets.openFd("game/sfx/" + name + ".mp3")) {
            id = pool.load(fd, 1);
        } catch (Exception e) { id = -1; }
        sounds.put(name, id);
        return id;
    }
    /** Loads the given sound effects in advance. */
    void preload(String... names) { if (!muted) for (String n : names) sound(n); }

    /** Plays a sound effect by name. */
    void play(String name) { play(name, 0.9f); }
    void play(String name, float volume) {
        if (muted || suspended) return;
        Integer id = sound(name);
        if (id == null || id < 0) return;
        if (loaded.contains(id)) pool.play(id, volume, volume, 1, 0, 1);
    }

    /** Switches between the menu theme (true) and random in-game music (false). */
    void setMenuMode(boolean menu) {
        if (menu == menuMode) return;
        menuMode = menu; stopMusic(); playMusic();
    }
    private void stopMusic() {
        if (music != null) { try { music.stop(); } catch (Exception ignored) {} music.release(); music = null; }
    }
    /** Starts the music for the current mode. */
    void playMusic() {
        if (!musicOn || muted || suspended || tracks.isEmpty()) return;
        if (menuMode) {
            if (music != null && music.isPlaying()) return;
            String menuTrack = tracks.contains("track11.mp3") ? "track11.mp3" : tracks.get(0);
            start(menuTrack, true);
            return;
        }
        int i = random.nextInt(tracks.size());
        if (tracks.size() > 1) while (i == lastTrack) i = random.nextInt(tracks.size());
        lastTrack = i;
        start(tracks.get(i), false);
    }
    private void start(String track, boolean loop) {
        stopMusic();
        try (AssetFileDescriptor fd = assets.openFd("game/audio/" + track)) {
            MediaPlayer player = new MediaPlayer();
            player.setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build());
            player.setDataSource(fd.getFileDescriptor(), fd.getStartOffset(), fd.getLength());
            player.setLooping(loop);
            player.setVolume(0.35f, 0.35f);
            if (!loop) player.setOnCompletionListener(p -> { if (!menuMode) playMusic(); });
            player.prepare();
            player.start();
            music = player;
        } catch (Exception ignored) {}
    }
    /** Skips to another music track. */
    void skipTrack() { if (!menuMode) { stopMusic(); playMusic(); } }

    /** Pauses everything while the app is in the background. */
    void suspend() { suspended = true; if (music != null && music.isPlaying()) music.pause(); pool.autoPause(); }
    void resume() {
        suspended = false; pool.autoResume();
        if (music != null) { if (musicOn && !muted) music.start(); } else playMusic();
    }
    static final List<String> PRELOAD = Arrays.asList("card", "redraw", "coin", "turn_me", "turn_op", "pass", "round1_start", "round_win", "round_lose", "hero",
        "horn", "moral", "med", "spy", "scorch", "cold", "fog", "rain", "clear", "game_win", "game_lose", "ally", "decoy", "menu_opening");
}

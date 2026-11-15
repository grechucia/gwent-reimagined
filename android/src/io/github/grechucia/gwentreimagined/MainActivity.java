// Android entry point: OpenGL ES view, frame loop, touch, keyboard and gamepad input, dialogs and the folder picker.
package io.github.grechucia.gwentreimagined;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.opengl.GLSurfaceView;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.InputType;
import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.widget.EditText;
import android.widget.FrameLayout;
import java.util.ArrayList;
import java.util.List;
import java.util.function.Consumer;
import javax.microedition.khronos.egl.EGLConfig;
import javax.microedition.khronos.opengles.GL10;

/** The only activity: owns the GL view, the scene and the platform services the scene needs. */
public final class MainActivity extends Activity implements GameHost, GLSurfaceView.Renderer {
    private static final int PICK_FOLDER = 1;
    private static final int[] FRAME_LIMITS = {30, 60, 90, 120};

    private GLSurfaceView view;
    private Renderer renderer;
    private Audio audio;
    private Scene scene;
    private SharedPreferences prefs;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private long lastFrame = System.nanoTime();
    private int surfaceWidth = 1, surfaceHeight = 1, viewWidth = 1, viewHeight = 1;
    private Consumer<Boolean> folderDone;
    /** Weak device (little memory or few cores): renders at 720p by default and shades the menu background at lower resolution. */
    private boolean lowEnd;
    private int perfFrames; private float perfTime, perfWorst;

    // Touch state: tap = click, long press = cancel selection, drag = scroll.
    private float startX, startY, lastX, lastY;
    private boolean dragging, longFired;
    private final Runnable longPress = () -> { if (!dragging) { longFired = true; onGame(() -> scene.rightClick()); } };

    // Gamepad state: left stick/hat directions repeat after 0.4 s, then every 0.12 s.
    private final float[] stick = new float[4];
    private final float[] repeatTimers = new float[4];
    private final boolean[] held = new boolean[4];
    private float rightStickY;

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        prefs = getSharedPreferences("settings", Context.MODE_PRIVATE);
        android.app.ActivityManager activityManager = (android.app.ActivityManager) getSystemService(Context.ACTIVITY_SERVICE);
        android.app.ActivityManager.MemoryInfo memory = new android.app.ActivityManager.MemoryInfo();
        activityManager.getMemoryInfo(memory);
        lowEnd = activityManager.isLowRamDevice() || memory.totalMem < 4500L * 1024 * 1024 || Runtime.getRuntime().availableProcessors() <= 4;
        GameData.shared = new GameData(getAssets());
        GameData.shared.language = prefs.getString("lang", "en");
        SaveStore.shared = new SaveStore(this);
        Career.shared = new Career();
        audio = new Audio(getAssets());
        renderer = new Renderer(getAssets());
        renderer.fillScreen = fillScreen();
        renderer.backgroundScale = lowEnd ? 0.35f : 0.5f;
        Intent intent = getIntent();
        boolean mute = intent.getBooleanExtra("mute", false), autotest = intent.getBooleanExtra("autotest", false);
        if (mute || autotest) { audio.muted = true; audio.setMusicOn(false); }
        scene = new Scene(renderer, audio);
        scene.host = this;
        try { scene.appVersion = getPackageManager().getPackageInfo(getPackageName(), 0).versionName; } catch (Exception ignored) {}

        if (!audio.muted) audio.playMusic();
        scene.autotest = autotest;
        String show = intent.getStringExtra("show");
        if ("options".equals(show)) scene.optionsOpen = true;
        else if ("start".equals(show)) scene.setScreen(SceneBase.Screen.DECKS);
        else if ("career".equals(show)) scene.setScreen(SceneBase.Screen.CAREER);
        else if ("game".equals(show)) scene.startGame();

        view = new GLSurfaceView(this);
        view.setEGLContextClientVersion(3);
        view.setEGLConfigChooser(8, 8, 8, 8, 0, 0);
        view.setPreserveEGLContextOnPause(true);
        view.setRenderer(this);
        view.setFocusable(true);
        view.setFocusableInTouchMode(true);
        view.setDefaultFocusHighlightEnabled(false);
        view.setOnTouchListener((v, event) -> { handleTouch(event); return true; });
        view.addOnLayoutChangeListener((v, l, t, r, b, ol, ot, or, ob) -> { viewWidth = Math.max(1, r - l); viewHeight = Math.max(1, b - t); applyRenderRes(); });
        FrameLayout root = new FrameLayout(this);
        root.addView(view);
        setContentView(root);
        if (Build.VERSION.SDK_INT >= 28) getWindow().getAttributes().layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        if (Build.VERSION.SDK_INT >= 33)
            getOnBackInvokedDispatcher().registerOnBackInvokedCallback(android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT, this::handleBack);
        hideSystemBars();
    }

    /** Hides the status and navigation bars (they reappear temporarily with a swipe). */
    @SuppressWarnings("deprecation")
    private void hideSystemBars() {
        if (Build.VERSION.SDK_INT >= 30) {
            getWindow().setDecorFitsSystemWindows(false);
            WindowInsetsController controller = getWindow().getInsetsController();
            if (controller != null) {
                controller.hide(WindowInsets.Type.systemBars());
                controller.setSystemBarsBehavior(WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
            }
        } else {
            getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY | View.SYSTEM_UI_FLAG_FULLSCREEN | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_LAYOUT_STABLE);
        }
    }
    @Override public void onWindowFocusChanged(boolean hasFocus) { super.onWindowFocusChanged(hasFocus); if (hasFocus) hideSystemBars(); }
    @Override protected void onPause() { super.onPause(); view.onPause(); audio.suspend(); }
    @Override protected void onResume() { super.onResume(); view.onResume(); audio.resume(); hideSystemBars(); }

    /** Runs scene code on the GL thread with the game lock held. */
    private void onGame(Runnable action) {
        view.queueEvent(() -> {
            GameThread.LOCK.lock();
            try { action.run(); } finally { GameThread.LOCK.unlock(); }
        });
    }

    // MARK: Frame loop (GL thread)

    @Override public void onSurfaceCreated(GL10 unused, EGLConfig config) {
        GameThread.LOCK.lock();
        try { renderer.init(); renderer.preload("img/start_bg.jpg", "img/board.jpg"); } finally { GameThread.LOCK.unlock(); }
    }
    @Override public void onSurfaceChanged(GL10 unused, int width, int height) { surfaceWidth = width; surfaceHeight = height; }
    @Override public void onDrawFrame(GL10 unused) {
        long now = System.nanoTime();
        int limit = effectiveFrameLimit();
        long minimum = 1_000_000_000L / limit - 2_000_000L;
        if (limit < displayRate() && now - lastFrame < minimum) {
            try { Thread.sleep((minimum - (now - lastFrame)) / 1_000_000L); } catch (InterruptedException ignored) {}
            now = System.nanoTime();
        }
        float dt = Math.min(0.1f, (now - lastFrame) / 1e9f);
        lastFrame = now;
        GameThread.LOCK.lock();
        try {
            updateGamepad(dt);
            renderer.begin(surfaceWidth, surfaceHeight);
            scene.frame(dt);
            renderer.end();
        } finally { GameThread.LOCK.unlock(); }
        // Average and worst frame time, logged every 5 seconds (tag GwentPerf) for performance checks.
        float work = (System.nanoTime() - now) / 1e6f;
        perfFrames++; perfTime += dt; perfWorst = Math.max(perfWorst, work);
        if (perfTime >= 5) {
            android.util.Log.i("GwentPerf", String.format(java.util.Locale.ROOT, "%.1f fps, worst frame work %.1f ms, %dx%d", perfFrames / perfTime, perfWorst, surfaceWidth, surfaceHeight));
            perfFrames = 0; perfTime = 0; perfWorst = 0;
        }
    }

    // MARK: Touch

    /** Converts a touch position in view pixels to the virtual coordinate space. */
    private Vec2 virtualPoint(float x, float y) {
        return renderer.virtualPoint(x / viewWidth * surfaceWidth, y / viewHeight * surfaceHeight);
    }
    private void handleTouch(MotionEvent event) {
        float x = event.getX(), y = event.getY();
        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN: {
                startX = lastX = x; startY = lastY = y; dragging = false; longFired = false;
                Vec2 point = virtualPoint(x, y);
                onGame(() -> { scene.padCursor = false; scene.mouseMoved(point); });
                handler.removeCallbacks(longPress);
                handler.postDelayed(longPress, 500);
                break;
            }
            case MotionEvent.ACTION_MOVE: {
                float density = getResources().getDisplayMetrics().density;
                if (!dragging && Math.hypot(x - startX, y - startY) > 12 * density) { dragging = true; handler.removeCallbacks(longPress); }
                Vec2 previous = virtualPoint(lastX, lastY), point = virtualPoint(x, y);
                boolean scrolling = dragging;
                onGame(() -> { if (scrolling) scene.scroll((point.y - previous.y) * 1.2f); scene.mouseMoved(point); });
                lastX = x; lastY = y;
                break;
            }
            case MotionEvent.ACTION_UP: {
                handler.removeCallbacks(longPress);
                Vec2 point = virtualPoint(x, y);
                boolean tap = !dragging && !longFired;
                onGame(() -> { if (tap) scene.click(point); scene.mouse = Vec2.NONE; });
                break;
            }
            case MotionEvent.ACTION_CANCEL:
                handler.removeCallbacks(longPress);
                onGame(() -> scene.mouse = Vec2.NONE);
                break;
            default: break;
        }
    }

    // MARK: Keys and gamepad

    private void handleBack() { onGame(() -> { if (!scene.back()) handler.post(() -> moveTaskToBack(true)); }); }

    private static boolean isGamepad(InputDevice device) {
        if (device == null) return false;
        int sources = device.getSources();
        return (sources & InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD || (sources & InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK;
    }
    /** Runs a gamepad action; the first gamepad input only switches to focus mode. */
    private void padAction(Runnable action) { onGame(() -> { if (!scene.padWake()) action.run(); }); }

    @Override public boolean onKeyDown(int keyCode, KeyEvent event) {
        switch (keyCode) {
            case KeyEvent.KEYCODE_BACK: case KeyEvent.KEYCODE_ESCAPE:
                if (event.getRepeatCount() == 0) handleBack();
                return true;
            case KeyEvent.KEYCODE_BUTTON_B:
                if (event.getRepeatCount() == 0) padAction(() -> { if (!scene.back()) handler.post(() -> moveTaskToBack(true)); });
                return true;
            case KeyEvent.KEYCODE_BUTTON_A: case KeyEvent.KEYCODE_DPAD_CENTER: case KeyEvent.KEYCODE_ENTER:
                if (event.getRepeatCount() == 0) padAction(() -> scene.click(scene.mouse));
                return true;
            case KeyEvent.KEYCODE_BUTTON_X:
                if (event.getRepeatCount() == 0) padAction(() -> scene.rightClick());
                return true;
            case KeyEvent.KEYCODE_BUTTON_START: case KeyEvent.KEYCODE_MENU:
                if (event.getRepeatCount() == 0) onGame(() -> { scene.optionsOpen = !scene.optionsOpen; if (scene.game != null) scene.game.paused = scene.optionsOpen; });
                return true;
            case KeyEvent.KEYCODE_DPAD_UP: padAction(() -> scene.padFocus(new Vec2(0, -1))); return true;
            case KeyEvent.KEYCODE_DPAD_DOWN: padAction(() -> scene.padFocus(new Vec2(0, 1))); return true;
            case KeyEvent.KEYCODE_DPAD_LEFT: padAction(() -> scene.padFocus(new Vec2(-1, 0))); return true;
            case KeyEvent.KEYCODE_DPAD_RIGHT: padAction(() -> scene.padFocus(new Vec2(1, 0))); return true;
            default: return super.onKeyDown(keyCode, event);
        }
    }

    @Override public boolean onGenericMotionEvent(MotionEvent event) {
        if (isGamepad(event.getDevice()) && event.getActionMasked() == MotionEvent.ACTION_MOVE) {
            float x = event.getAxisValue(MotionEvent.AXIS_X), y = event.getAxisValue(MotionEvent.AXIS_Y);
            float hatX = event.getAxisValue(MotionEvent.AXIS_HAT_X), hatY = event.getAxisValue(MotionEvent.AXIS_HAT_Y);
            float rz = event.getAxisValue(MotionEvent.AXIS_RZ);
            synchronized (stick) {
                stick[0] = (y < -0.6f || hatY < -0.5f) ? 1 : 0;
                stick[1] = (y > 0.6f || hatY > 0.5f) ? 1 : 0;
                stick[2] = (x < -0.6f || hatX < -0.5f) ? 1 : 0;
                stick[3] = (x > 0.6f || hatX > 0.5f) ? 1 : 0;
                rightStickY = Math.abs(rz) > 0.2f ? rz : 0;
            }
            return true;
        }
        if ((event.getSource() & InputDevice.SOURCE_CLASS_POINTER) != 0 && event.getActionMasked() == MotionEvent.ACTION_SCROLL) {
            float delta = event.getAxisValue(MotionEvent.AXIS_VSCROLL) * 60;
            onGame(() -> scene.scroll(delta));
            return true;
        }
        return super.onGenericMotionEvent(event);
    }

    /** Applies held stick directions (with key repeat) and right-stick scrolling; runs on the GL thread with the lock held. */
    private void updateGamepad(float dt) {
        Vec2[] directions = {new Vec2(0, -1), new Vec2(0, 1), new Vec2(-1, 0), new Vec2(1, 0)};
        float scroll;
        boolean[] on = new boolean[4];
        synchronized (stick) { for (int i = 0; i < 4; i++) on[i] = stick[i] > 0; scroll = rightStickY; }
        for (int i = 0; i < 4; i++) {
            boolean fire = false;
            if (on[i] && !held[i]) { fire = true; repeatTimers[i] = 0.4f; }
            else if (on[i]) { repeatTimers[i] -= dt; if (repeatTimers[i] <= 0) { fire = true; repeatTimers[i] = 0.12f; } }
            held[i] = on[i];
            if (fire && !scene.padWake()) scene.padFocus(directions[i]);
        }
        if (scroll != 0 && !scene.padWake()) scene.scroll(-scroll * 1100 * dt);
    }

    // MARK: GameHost

    @Override public int renderRes() { return prefs.getInt("renderRes", lowEnd ? 720 : 0); }
    @Override public void setRenderRes(int height) { prefs.edit().putInt("renderRes", height).apply(); handler.post(this::applyRenderRes); }
    /** Renders at a lower resolution than the screen when chosen in Options (the system scales the image up). */
    private void applyRenderRes() {
        int height = renderRes();
        if (height <= 0 || height >= viewHeight) view.getHolder().setSizeFromLayout();
        else view.getHolder().setFixedSize(Math.round(viewWidth * (float) height / viewHeight), height);
    }
    private int displayRate() {
        float rate = Build.VERSION.SDK_INT >= 30 && getDisplay() != null ? getDisplay().getRefreshRate() : getWindowManager().getDefaultDisplay().getRefreshRate();
        return Math.max(30, Math.round(rate));
    }
    @Override public List<Integer> availableFrameLimits() {
        int rate = displayRate();
        List<Integer> limits = new ArrayList<>();
        for (int limit : FRAME_LIMITS) if (limit <= rate && rate % limit == 0) limits.add(limit);
        if (limits.isEmpty()) limits.add(rate);
        return limits;
    }
    @Override public int effectiveFrameLimit() {
        int stored = prefs.getInt("frameLimit", 60);
        List<Integer> available = availableFrameLimits();
        if (available.contains(stored)) return stored;
        int best = available.get(available.size() - 1);
        for (int limit : available) if (limit <= stored) best = limit;
        return best;
    }
    @Override public void setFrameLimit(int limit) { prefs.edit().putInt("frameLimit", limit).apply(); }
    @Override public boolean fillScreen() { return prefs.getBoolean("fillScreen", true); }
    @Override public void setFillScreen(boolean on) { prefs.edit().putBoolean("fillScreen", on).apply(); renderer.fillScreen = on; }
    @Override public boolean isPhone() { return getResources().getConfiguration().smallestScreenWidthDp < 600; }
    @Override public void openURL(String url) {
        handler.post(() -> { try { startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url))); } catch (Exception ignored) {} });
    }
    @Override public void askText(String title, String message, String placeholder, String current, Consumer<String> done) {
        handler.post(() -> {
            EditText input = new EditText(this);
            input.setText(current); input.setHint(placeholder); input.setSingleLine(true);
            input.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_CAP_WORDS);
            input.setSelection(input.getText().length());
            input.setImeOptions(android.view.inputmethod.EditorInfo.IME_FLAG_NO_EXTRACT_UI | android.view.inputmethod.EditorInfo.IME_FLAG_NO_FULLSCREEN | android.view.inputmethod.EditorInfo.IME_ACTION_DONE);
            FrameLayout container = new FrameLayout(this);
            int padding = Math.round(20 * getResources().getDisplayMetrics().density);
            container.setPadding(padding, 0, padding, 0);
            container.addView(input);
            boolean[] answered = {false};
            AlertDialog dialog = new AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
                .setTitle(title).setMessage(message).setView(container)
                .setPositiveButton("OK", (d, w) -> { answered[0] = true; String text = input.getText().toString(); onGame(() -> done.accept(text)); })
                .setNegativeButton(GameData.L("Cancel"), (d, w) -> { answered[0] = true; onGame(() -> done.accept(null)); })
                .setOnDismissListener(d -> { if (!answered[0]) onGame(() -> done.accept(null)); hideSystemBars(); })
                .create();
            dialog.show();
        });
    }
    @Override public void pickFolder(Consumer<Boolean> done) {
        handler.post(() -> {
            folderDone = done;
            Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
            try { startActivityForResult(intent, PICK_FOLDER); } catch (Exception e) { folderDone = null; onGame(() -> done.accept(false)); }
        });
    }
    @Override protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != PICK_FOLDER || folderDone == null) return;
        Consumer<Boolean> done = folderDone; folderDone = null;
        Uri tree = resultCode == RESULT_OK && data != null ? data.getData() : null;
        if (tree == null) { onGame(() -> done.accept(false)); return; }
        try { getContentResolver().takePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION); } catch (Exception ignored) {}
        onGame(() -> { SaveStore.shared.chooseFolder(tree); done.accept(true); });
    }
    @Override public int intSetting(String key, int fallback) { return prefs.getInt(key, fallback); }
    @Override public void setIntSetting(String key, int value) { prefs.edit().putInt(key, value).apply(); }
    @Override public void setLanguage(String code) { prefs.edit().putString("lang", code).apply(); }
}

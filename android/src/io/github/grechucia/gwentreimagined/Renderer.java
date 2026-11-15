// OpenGL ES 3 2D renderer: batched textured quads in a virtual 1920x1080 space, Android text rendering and the title-screen shader.
package io.github.grechucia.gwentreimagined;

import android.content.res.AssetManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Typeface;
import android.opengl.GLES30;
import android.text.Layout;
import android.text.StaticLayout;
import android.text.TextPaint;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

/** GPU texture with its size in pixels. */
final class Texture {
    final int id, width, height;
    Texture(int id, int width, int height) { this.id = id; this.width = width; this.height = height; }
}

/** Rendered text texture with its size in virtual units. */
final class TextTex {
    final Texture texture; final float w, h; int lastUsed;
    TextTex(Texture texture, float w, float h) { this.texture = texture; this.w = w; this.h = h; }
}

/** Font description: family, size and style. */
final class Font {
    final String name; final float size; final boolean bold, italic;
    Font(String name, float size, boolean bold, boolean italic) { this.name = name; this.size = size; this.bold = bold; this.italic = italic; }
    /** System sans-serif font. */
    static Font ui(float size) { return new Font("sans", size, false, false); }
    static Font ui(float size, boolean bold) { return new Font("sans", size, bold, false); }
    /** Serif font. */
    static Font serif(float size) { return new Font("serif", size, false, false); }
    static Font serif(float size, boolean bold) { return new Font("serif", size, bold, false); }
    static Font serif(float size, boolean bold, boolean italic) { return new Font("serif", size, bold, italic); }
    /** The Gwent logo font. */
    static Font gwent(float size) { return new Font("gwent", size, false, false); }
}

/** Text alignment. */
enum Align { LEFT, CENTER, RIGHT }

/** An animated region of the title background (position/size and motion). */
final class BgRegion {
    final float[] bounds, motion;
    BgRegion(float[] bounds, float[] motion) { this.bounds = bounds; this.motion = motion; }
}

/** Batches textured quads into OpenGL draw calls; letterboxes to 16:9 or extends the virtual area to fill the screen. */
final class Renderer {
    private static final int FLOATS_PER_VERTEX = 9, MAX_VERTS = 60000;
    private final AssetManager assets;
    private int program, bgProgram, vbo;
    private int uProjection, uTexture, bgTexture, bgTime, bgMouse, bgTexel, bgCover, bgRegions, bgGlints, bgCandles;
    private final FloatBuffer verts = ByteBuffer.allocateDirect(MAX_VERTS * FLOATS_PER_VERTEX * 4).order(ByteOrder.nativeOrder()).asFloatBuffer();
    private int vcount, flushedFrom;
    private Texture curTex;
    private final float[] projection = new float[16];
    Texture white, glow;
    float pxScale = 1;
    Box viewportPx = new Box(0, 0, 1, 1);
    int drawableWidth = 1, drawableHeight = 1;
    /** When true the whole screen is used: the virtual area grows beyond 1920x1080 instead of showing black bars. */
    boolean fillScreen = true;
    /** Part of the virtual space that is visible on screen. */
    Box visibleRect = new Box(0, 0, Virtual.WIDTH, Virtual.HEIGHT);
    private final Map<String, Texture> texCache = new HashMap<>();
    private final Map<String, TextTex> textCache = new HashMap<>();
    int frameNo;
    private Typeface gwentTypeface;

    Renderer(AssetManager assets) { this.assets = assets; }

    /** Creates GPU resources; called when the GL context is (re)created. */
    void init() {
        texCache.clear(); textCache.clear();
        program = link(VERTEX_SHADER, FRAGMENT_SHADER);
        uProjection = GLES30.glGetUniformLocation(program, "projection");
        uTexture = GLES30.glGetUniformLocation(program, "tex");
        bgProgram = link(BG_VERTEX_SHADER, BG_FRAGMENT_SHADER);
        bgTexture = GLES30.glGetUniformLocation(bgProgram, "tex");
        bgTime = GLES30.glGetUniformLocation(bgProgram, "time");
        bgMouse = GLES30.glGetUniformLocation(bgProgram, "mouse");
        bgTexel = GLES30.glGetUniformLocation(bgProgram, "texel");
        bgCover = GLES30.glGetUniformLocation(bgProgram, "cover");
        bgRegions = GLES30.glGetUniformLocation(bgProgram, "regions");
        bgGlints = GLES30.glGetUniformLocation(bgProgram, "glints");
        bgCandles = GLES30.glGetUniformLocation(bgProgram, "candles");
        int[] ids = new int[1];
        GLES30.glGenBuffers(1, ids, 0); vbo = ids[0];
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, vbo);
        GLES30.glBufferData(GLES30.GL_ARRAY_BUFFER, MAX_VERTS * FLOATS_PER_VERTEX * 4, null, GLES30.GL_DYNAMIC_DRAW);
        ByteBuffer px = ByteBuffer.allocateDirect(4).order(ByteOrder.nativeOrder());
        px.put(new byte[]{(byte) 255, (byte) 255, (byte) 255, (byte) 255}).position(0);
        white = upload(px, 1, 1, GLES30.GL_RGBA8, GLES30.GL_RGBA, false);
        glow = makeGlow();
        try { gwentTypeface = Typeface.createFromAsset(assets, "game/fonts/gwent.ttf"); } catch (Exception e) { gwentTypeface = Typeface.DEFAULT_BOLD; }
        GLES30.glEnable(GLES30.GL_BLEND);
        GLES30.glBlendFuncSeparate(GLES30.GL_SRC_ALPHA, GLES30.GL_ONE_MINUS_SRC_ALPHA, GLES30.GL_ONE, GLES30.GL_ONE_MINUS_SRC_ALPHA);
    }

    /** Soft round white texture used for glows and particles (alpha 1 at the centre, 0.45 at 35% of the radius, 0 at the edge). */
    private static Texture makeGlow() {
        int size = 64;
        ByteBuffer pixels = ByteBuffer.allocateDirect(size * size * 4).order(ByteOrder.nativeOrder());
        for (int y = 0; y < size; y++) for (int x = 0; x < size; x++) {
            float dx = x + 0.5f - size / 2f, dy = y + 0.5f - size / 2f;
            float d = (float) Math.sqrt(dx * dx + dy * dy) / (size / 2f);
            float alpha = d < 0.35f ? 1 - (1 - 0.45f) * d / 0.35f : (d < 1 ? 0.45f * (1 - (d - 0.35f) / 0.65f) : 0);
            pixels.put((byte) 255).put((byte) 255).put((byte) 255).put((byte) Math.round(alpha * 255));
        }
        pixels.position(0);
        return upload(pixels, size, size, GLES30.GL_RGBA8, GLES30.GL_RGBA, false);
    }

    private static int compile(int type, String source) {
        int shader = GLES30.glCreateShader(type);
        GLES30.glShaderSource(shader, source); GLES30.glCompileShader(shader);
        int[] ok = new int[1]; GLES30.glGetShaderiv(shader, GLES30.GL_COMPILE_STATUS, ok, 0);
        if (ok[0] == 0) throw new RuntimeException("Shader: " + GLES30.glGetShaderInfoLog(shader));
        return shader;
    }
    private static int link(String vertex, String fragment) {
        int p = GLES30.glCreateProgram();
        GLES30.glAttachShader(p, compile(GLES30.GL_VERTEX_SHADER, vertex));
        GLES30.glAttachShader(p, compile(GLES30.GL_FRAGMENT_SHADER, fragment));
        GLES30.glBindAttribLocation(p, 0, "pos"); GLES30.glBindAttribLocation(p, 1, "uv");
        GLES30.glBindAttribLocation(p, 2, "color"); GLES30.glBindAttribLocation(p, 3, "mode");
        GLES30.glLinkProgram(p);
        int[] ok = new int[1]; GLES30.glGetProgramiv(p, GLES30.GL_LINK_STATUS, ok, 0);
        if (ok[0] == 0) throw new RuntimeException("Program: " + GLES30.glGetProgramInfoLog(p));
        return p;
    }

    /** Uploads pixel data as a texture. */
    private static Texture upload(ByteBuffer pixels, int w, int h, int internalFormat, int format, boolean mipmaps) {
        int[] ids = new int[1];
        GLES30.glGenTextures(1, ids, 0);
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, ids[0]);
        GLES30.glPixelStorei(GLES30.GL_UNPACK_ALIGNMENT, 1);
        GLES30.glTexImage2D(GLES30.GL_TEXTURE_2D, 0, internalFormat, w, h, 0, format, GLES30.GL_UNSIGNED_BYTE, pixels);
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MIN_FILTER, mipmaps ? GLES30.GL_LINEAR_MIPMAP_LINEAR : GLES30.GL_LINEAR);
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MAG_FILTER, GLES30.GL_LINEAR);
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_S, GLES30.GL_CLAMP_TO_EDGE);
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_T, GLES30.GL_CLAMP_TO_EDGE);
        if (mipmaps) GLES30.glGenerateMipmap(GLES30.GL_TEXTURE_2D);
        return new Texture(ids[0], w, h);
    }

    /** Loads (and caches) an image from the game assets as a texture (colours not premultiplied, like the Metal version). */
    Texture texture(String path) {
        Texture cached = texCache.get(path);
        if (cached != null) return cached;
        Bitmap bitmap;
        try (InputStream in = assets.open("game/" + path)) {
            BitmapFactory.Options options = new BitmapFactory.Options();
            options.inPremultiplied = false;
            options.inPreferredConfig = Bitmap.Config.ARGB_8888;
            bitmap = BitmapFactory.decodeStream(in, null, options);
        } catch (Exception e) { return null; }
        if (bitmap == null) return null;
        ByteBuffer pixels = ByteBuffer.allocateDirect(bitmap.getWidth() * bitmap.getHeight() * 4).order(ByteOrder.nativeOrder());
        bitmap.copyPixelsToBuffer(pixels); pixels.position(0);
        Texture t = upload(pixels, bitmap.getWidth(), bitmap.getHeight(), GLES30.GL_RGBA8, GLES30.GL_RGBA, true);
        bitmap.recycle();
        texCache.put(path, t);
        return t;
    }
    void preload(String... paths) { for (String p : paths) texture(p); }

    /** Starts a frame: computes the viewport (letterboxed or filling the screen). */
    void begin(int width, int height) {
        drawableWidth = width; drawableHeight = height;
        float dw = width, dh = height;
        if (fillScreen) {
            viewportPx = new Box(0, 0, dw, dh);
            float aspect = dw / dh;
            if (aspect >= Virtual.WIDTH / Virtual.HEIGHT) { float vw = Virtual.HEIGHT * aspect; visibleRect = new Box(-(vw - Virtual.WIDTH) / 2, 0, vw, Virtual.HEIGHT); }
            else { float vh = Virtual.WIDTH / aspect; visibleRect = new Box(0, -(vh - Virtual.HEIGHT) / 2, Virtual.WIDTH, vh); }
        } else {
            float w = dw, h = dw * Virtual.HEIGHT / Virtual.WIDTH;
            if (h > dh) { h = dh; w = dh * Virtual.WIDTH / Virtual.HEIGHT; }
            viewportPx = new Box(Math.round((dw - w) / 2), Math.round((dh - h) / 2), Math.round(w), Math.round(h));
            visibleRect = new Box(0, 0, Virtual.WIDTH, Virtual.HEIGHT);
        }
        pxScale = viewportPx.w / visibleRect.w;
        GLES30.glViewport(0, 0, width, height);
        GLES30.glDisable(GLES30.GL_SCISSOR_TEST);
        GLES30.glClearColor(0, 0, 0, 1);
        GLES30.glClear(GLES30.GL_COLOR_BUFFER_BIT);
        GLES30.glViewport((int) viewportPx.x, (int) (height - viewportPx.y - viewportPx.h), (int) viewportPx.w, (int) viewportPx.h);
        Box v = visibleRect;
        // Column-major orthographic projection from the visible virtual area to clip space (y down).
        java.util.Arrays.fill(projection, 0);
        projection[0] = 2 / v.w; projection[12] = -1 - 2 * v.x / v.w;
        projection[5] = -2 / v.h; projection[13] = 1 + 2 * v.y / v.h;
        projection[10] = 1; projection[15] = 1;
        verts.clear(); vcount = 0; flushedFrom = 0; curTex = null;
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, vbo);
        GLES30.glBufferData(GLES30.GL_ARRAY_BUFFER, MAX_VERTS * FLOATS_PER_VERTEX * 4, null, GLES30.GL_DYNAMIC_DRAW);
        useQuadProgram();
        frameNo++;
    }
    private void useQuadProgram() {
        GLES30.glUseProgram(program);
        GLES30.glUniformMatrix4fv(uProjection, 1, false, projection, 0);
        GLES30.glUniform1i(uTexture, 0);
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, vbo);
        int stride = FLOATS_PER_VERTEX * 4;
        GLES30.glEnableVertexAttribArray(0); GLES30.glVertexAttribPointer(0, 2, GLES30.GL_FLOAT, false, stride, 0);
        GLES30.glEnableVertexAttribArray(1); GLES30.glVertexAttribPointer(1, 2, GLES30.GL_FLOAT, false, stride, 8);
        GLES30.glEnableVertexAttribArray(2); GLES30.glVertexAttribPointer(2, 4, GLES30.GL_FLOAT, false, stride, 16);
        GLES30.glEnableVertexAttribArray(3); GLES30.glVertexAttribPointer(3, 1, GLES30.GL_FLOAT, false, stride, 32);
    }
    /** Finishes the frame. */
    void end() {
        flush();
        if (frameNo % 600 == 0) trimTextCache();
    }
    /** Sends the queued quads to the GPU. */
    private void flush() {
        if (vcount <= flushedFrom || curTex == null) return;
        int count = vcount - flushedFrom;
        verts.position(flushedFrom * FLOATS_PER_VERTEX);
        GLES30.glBufferSubData(GLES30.GL_ARRAY_BUFFER, flushedFrom * FLOATS_PER_VERTEX * 4, count * FLOATS_PER_VERTEX * 4, verts);
        GLES30.glActiveTexture(GLES30.GL_TEXTURE0);
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, curTex.id);
        GLES30.glDrawArrays(GLES30.GL_TRIANGLES, flushedFrom, count);
        flushedFrom = vcount;
    }

    /** Queues a textured quad. mode 1 draws a greyscale text mask in the given colour. */
    void quad(Texture texture, Box rect, Box uv, RGBA tint, float mode, float rotation) {
        if (texture == null || vcount + 6 > MAX_VERTS) return;
        if (texture != curTex) { flush(); curTex = texture; }
        float[] xs = {rect.x, rect.x + rect.w, rect.x, rect.x + rect.w}, ys = {rect.y, rect.y, rect.y + rect.h, rect.y + rect.h};
        if (rotation != 0) {
            float cx = rect.x + rect.w / 2, cy = rect.y + rect.h / 2, cs = (float) Math.cos(rotation), sn = (float) Math.sin(rotation);
            for (int i = 0; i < 4; i++) { float ox = xs[i] - cx, oy = ys[i] - cy; xs[i] = cx + ox * cs - oy * sn; ys[i] = cy + ox * sn + oy * cs; }
        }
        float[] us = {uv.x, uv.x + uv.w, uv.x, uv.x + uv.w}, vs = {uv.y, uv.y, uv.y + uv.h, uv.y + uv.h};
        verts.position(vcount * FLOATS_PER_VERTEX);
        for (int i : new int[]{0, 1, 2, 1, 3, 2}) {
            verts.put(xs[i]).put(ys[i]).put(us[i]).put(vs[i]).put(tint.r).put(tint.g).put(tint.b).put(tint.a).put(mode);
            vcount++;
        }
    }
    private static final Box FULL_UV = new Box(0, 0, 1, 1);
    void quad(Texture texture, Box rect, RGBA tint) { quad(texture, rect, FULL_UV, tint, 0, 0); }
    void quad(Texture texture, Box rect) { quad(texture, rect, FULL_UV, RGBA.WHITE, 0, 0); }
    void quad(Texture texture, Box rect, Box uv) { quad(texture, rect, uv, RGBA.WHITE, 0, 0); }

    /** Draws an image stretched into a rectangle. */
    void image(String path, Box rect) { image(path, rect, RGBA.WHITE, 0); }
    void image(String path, Box rect, RGBA color) { image(path, rect, color, 0); }
    void image(String path, Box rect, RGBA color, float rotation) { Texture t = texture(path); if (t != null) quad(t, rect, FULL_UV, color, 0, rotation); }
    /** Draws an image filling a rectangle, cropping to keep its aspect ratio. */
    void imageCover(String path, Box rect) { imageCover(path, rect, RGBA.WHITE); }
    void imageCover(String path, Box rect, RGBA color) {
        Texture t = texture(path); if (t == null) return;
        float textureAspect = (float) t.width / t.height, ra = rect.w / rect.h;
        Box uv;
        if (textureAspect > ra) { float w = ra / textureAspect; uv = new Box((1 - w) / 2, 0, w, 1); }
        else { float h = textureAspect / ra; uv = new Box(0, (1 - h) / 2, 1, h); }
        quad(t, rect, uv, color, 0, 0);
    }
    /** Draws an image fitted inside a rectangle. */
    void imageContain(String path, Box rect) { imageContain(path, rect, RGBA.WHITE, false); }
    void imageContain(String path, Box rect, RGBA color, boolean alignTop) {
        Texture t = texture(path); if (t == null) return;
        float textureAspect = (float) t.width / t.height, ra = rect.w / rect.h;
        Box destination;
        if (textureAspect > ra) { float h = rect.w / textureAspect; destination = new Box(rect.x, alignTop ? rect.y : rect.y + (rect.h - h) / 2, rect.w, h); }
        else { float w = rect.h * textureAspect; destination = new Box(rect.x + (rect.w - w) / 2, rect.y, w, rect.h); }
        quad(t, destination, FULL_UV, color, 0, 0);
    }
    /** Converts a position in drawable pixels to the virtual coordinate space. */
    Vec2 virtualPoint(float pixelX, float pixelY) {
        Box viewport = viewportPx, visible = visibleRect;
        return new Vec2(visible.x + (pixelX - viewport.x) / viewport.w * visible.w, visible.y + (pixelY - viewport.y) / viewport.h * visible.h);
    }
    /** Draws an image over the 1920x1080 area and stretches its outermost pixels over the extra screen area in fill mode. */
    void imageFillingScreen(String path) {
        Texture t = texture(path); if (t == null) return;
        Box visible = visibleRect; float edge = 0.004f;
        quad(t, new Box(0, 0, Virtual.WIDTH, Virtual.HEIGHT));
        if (visible.x < 0) {
            quad(t, new Box(visible.x, 0, -visible.x, Virtual.HEIGHT), new Box(0, 0, edge, 1));
            quad(t, new Box(Virtual.WIDTH, 0, -visible.x, Virtual.HEIGHT), new Box(1 - edge, 0, edge, 1));
        }
        if (visible.y < 0) {
            quad(t, new Box(0, visible.y, Virtual.WIDTH, -visible.y), new Box(0, 0, 1, edge));
            quad(t, new Box(0, Virtual.HEIGHT, Virtual.WIDTH, -visible.y), new Box(0, 1 - edge, 1, edge));
        }
    }
    /** Restricts drawing to a rectangle (null removes the clip). */
    void clip(Box rect) {
        flush();
        if (rect == null) { GLES30.glDisable(GLES30.GL_SCISSOR_TEST); return; }
        Box viewport = viewportPx;
        int x = Math.max(0, (int) (viewport.x + (rect.x - visibleRect.x) * pxScale));
        int y = Math.max(0, (int) (viewport.y + (rect.y - visibleRect.y) * pxScale));
        int w = Math.max(1, (int) (rect.w * pxScale)), h = Math.max(1, (int) (rect.h * pxScale));
        GLES30.glEnable(GLES30.GL_SCISSOR_TEST);
        GLES30.glScissor(x, drawableHeight - y - h, w, h);
    }
    /** Draws a filled rectangle. */
    void rect(Box rect, RGBA color) { quad(white, rect, color); }
    /** Draws a rectangle outline. */
    void frame(Box area, RGBA color, float thickness) {
        float t = thickness;
        rect(new Box(area.x, area.y, area.w, t), color); rect(new Box(area.x, area.y + area.h - t, area.w, t), color);
        rect(new Box(area.x, area.y + t, t, area.h - 2 * t), color); rect(new Box(area.x + area.w - t, area.y + t, t, area.h - 2 * t), color);
    }
    void frame(Box area, RGBA color) { frame(area, color, 2); }
    /** Draws a vertical gradient. */
    void gradient(Box area, RGBA top, RGBA bottom, int steps) {
        int stepCount = Math.max(1, steps);
        for (int i = 0; i < stepCount; i++) {
            float start = (float) i / stepCount, end = (float) (i + 1) / stepCount, mid = (start + end) / 2;
            RGBA c = new RGBA(top.r + (bottom.r - top.r) * mid, top.g + (bottom.g - top.g) * mid, top.b + (bottom.b - top.b) * mid, top.a + (bottom.a - top.a) * mid);
            rect(new Box(area.x, area.y + area.h * start, area.w, area.h * (end - start) + 0.5f), c);
        }
    }
    void gradient(Box area, RGBA top, RGBA bottom) { gradient(area, top, bottom, 24); }

    // MARK: Text

    private Typeface typeface(Font font) {
        Typeface base = font.name.equals("gwent") ? gwentTypeface : (font.name.equals("serif") ? Typeface.SERIF : Typeface.SANS_SERIF);
        int style = (font.bold ? Typeface.BOLD : 0) | (font.italic ? Typeface.ITALIC : 0);
        return style == 0 ? base : Typeface.create(base, style);
    }
    /** Renders text into a cached greyscale texture. */
    TextTex textTex(String text, Font font, float maxWidth, Align align, float lineSpacing) {
        if (text == null || text.isEmpty()) return null;
        float scale = Math.max(0.5f, pxScale);
        String key = text + "|" + font.name + "|" + font.size + "|" + font.bold + "|" + font.italic + "|" + maxWidth + "|" + align + "|" + lineSpacing + "|" + scale;
        TextTex cached = textCache.get(key);
        if (cached != null) { cached.lastUsed = frameNo; return cached; }
        TextPaint paint = new TextPaint(TextPaint.ANTI_ALIAS_FLAG);
        paint.setTypeface(typeface(font));
        paint.setTextSize(font.size * scale);
        paint.setColor(0xFFFFFFFF);
        Layout.Alignment alignment = align == Align.CENTER ? Layout.Alignment.ALIGN_CENTER : (align == Align.RIGHT ? Layout.Alignment.ALIGN_OPPOSITE : Layout.Alignment.ALIGN_NORMAL);
        int constraint = maxWidth > 0 ? (int) Math.ceil(maxWidth * scale) : (int) Math.ceil(Layout.getDesiredWidth(text, paint)) + 1;
        StaticLayout layout = StaticLayout.Builder.obtain(text, 0, text.length(), paint, Math.max(1, constraint))
            .setAlignment(alignment).setLineSpacing(lineSpacing * scale, 1).setIncludePad(false).build();
        float width = 0;
        for (int i = 0; i < layout.getLineCount(); i++) width = Math.max(width, layout.getLineWidth(i));
        if (maxWidth > 0 && align != Align.LEFT) width = constraint;
        int padding = 2;
        int pixelWidth = (int) Math.ceil(width + padding * 2), pixelHeight = layout.getHeight() + padding * 2;
        if (pixelWidth <= 0 || pixelHeight <= 0 || pixelWidth >= 16384 || pixelHeight >= 16384) return null;
        int rowWidth = (pixelWidth + 3) & ~3;
        Bitmap bitmap = Bitmap.createBitmap(rowWidth, pixelHeight, Bitmap.Config.ALPHA_8);
        Canvas canvas = new Canvas(bitmap);
        canvas.translate(padding + (maxWidth > 0 && align != Align.LEFT ? 0 : 0), padding);
        if (maxWidth <= 0 && align != Align.LEFT) canvas.translate(-(constraint - width) * (align == Align.CENTER ? 0.5f : 1f), 0);
        layout.draw(canvas);
        ByteBuffer pixels = ByteBuffer.allocateDirect(bitmap.getRowBytes() * pixelHeight).order(ByteOrder.nativeOrder());
        bitmap.copyPixelsToBuffer(pixels); pixels.position(0);
        Texture t;
        if (bitmap.getRowBytes() == rowWidth) t = upload(pixels, rowWidth, pixelHeight, GLES30.GL_R8, GLES30.GL_RED, false);
        else {
            ByteBuffer tight = ByteBuffer.allocateDirect(rowWidth * pixelHeight).order(ByteOrder.nativeOrder());
            for (int y = 0; y < pixelHeight; y++) for (int x = 0; x < rowWidth; x++) tight.put(pixels.get(y * bitmap.getRowBytes() + x));
            tight.position(0);
            t = upload(tight, rowWidth, pixelHeight, GLES30.GL_R8, GLES30.GL_RED, false);
        }
        bitmap.recycle();
        TextTex textTexture = new TextTex(t, rowWidth / scale, pixelHeight / scale);
        textTexture.lastUsed = frameNo;
        textCache.put(key, textTexture);
        return textTexture;
    }
    /** Drops text textures that were not used recently. */
    private void trimTextCache() {
        for (Iterator<Map.Entry<String, TextTex>> it = textCache.entrySet().iterator(); it.hasNext();) {
            TextTex t = it.next().getValue();
            if (frameNo - t.lastUsed >= 600) { GLES30.glDeleteTextures(1, new int[]{t.texture.id}, 0); it.remove(); }
        }
    }
    static final RGBA DEFAULT_SHADOW = new RGBA(0, 0, 0, 0.85f);
    /** Draws text and returns its size (width, height) in virtual units. */
    float[] text(String string, Font font, float x, float y, RGBA color, float maxWidth, Align align, RGBA shadow, float lineSpacing) {
        TextTex t = textTex(string, font, maxWidth, align, lineSpacing);
        if (t == null) return new float[]{0, 0};
        float x0 = x;
        if (align == Align.CENTER) x0 = x - t.w / 2; else if (align == Align.RIGHT) x0 = x - t.w;
        if (shadow != null) {
            float offset = Math.max(1, font.size * 0.06f);
            quad(t.texture, new Box(x0 + offset, y + offset, t.w, t.h), FULL_UV, shadow, 1, 0);
        }
        quad(t.texture, new Box(x0, y, t.w, t.h), FULL_UV, color, 1, 0);
        return new float[]{t.w, t.h};
    }
    float[] text(String s, Font f, float x, float y, RGBA color) { return text(s, f, x, y, color, 0, Align.LEFT, DEFAULT_SHADOW, 0); }
    float[] text(String s, Font f, float x, float y, RGBA color, float maxWidth) { return text(s, f, x, y, color, maxWidth, Align.LEFT, DEFAULT_SHADOW, 0); }
    float[] text(String s, Font f, float x, float y, RGBA color, float maxWidth, Align align) { return text(s, f, x, y, color, maxWidth, align, DEFAULT_SHADOW, 0); }
    float[] text(String s, Font f, float x, float y, RGBA color, Align align) { return text(s, f, x, y, color, 0, align, DEFAULT_SHADOW, 0); }
    /** Measures text without drawing it. */
    float[] measure(String text, Font font, float maxWidth) { TextTex t = textTex(text, font, maxWidth, Align.LEFT, 0); return t == null ? new float[]{0, 0} : new float[]{t.w, t.h}; }
    float[] measure(String text, Font font) { return measure(text, font, 0); }

    // MARK: Title background

    /** Draws the animated title background with the dedicated shader. */
    void titleBackground(String path, float time, Vec2 mouse, List<BgRegion> regions, List<Vec2> glints, List<Vec2> candles) {
        Texture t = texture(path); if (t == null) return;
        flush();
        GLES30.glUseProgram(bgProgram);
        GLES30.glDisableVertexAttribArray(0); GLES30.glDisableVertexAttribArray(1); GLES30.glDisableVertexAttribArray(2); GLES30.glDisableVertexAttribArray(3);
        GLES30.glUniform1f(bgTime, time);
        GLES30.glUniform2f(bgMouse, mouse.x, mouse.y);
        GLES30.glUniform2f(bgTexel, 1f / t.width, 1f / t.height);
        GLES30.glUniform1f(bgCover, (Virtual.WIDTH / Virtual.HEIGHT) / (visibleRect.w / visibleRect.h));
        float[] regionData = new float[48 * 8];
        for (int i = 0; i < Math.min(48, regions.size()); i++) {
            System.arraycopy(regions.get(i).bounds, 0, regionData, i * 8, 4);
            System.arraycopy(regions.get(i).motion, 0, regionData, i * 8 + 4, 4);
        }
        GLES30.glUniform4fv(bgRegions, 96, regionData, 0);
        float[] glintData = new float[4];
        for (int i = 0; i < Math.min(2, glints.size()); i++) { glintData[i * 2] = glints.get(i).x; glintData[i * 2 + 1] = glints.get(i).y; }
        GLES30.glUniform2fv(bgGlints, 2, glintData, 0);
        float[] candleData = {-1, -1, -1, -1, -1, -1};
        for (int i = 0; i < Math.min(3, candles.size()); i++) { candleData[i * 2] = candles.get(i).x; candleData[i * 2 + 1] = candles.get(i).y; }
        GLES30.glUniform2fv(bgCandles, 3, candleData, 0);
        GLES30.glActiveTexture(GLES30.GL_TEXTURE0);
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, t.id);
        GLES30.glUniform1i(bgTexture, 0);
        GLES30.glDrawArrays(GLES30.GL_TRIANGLE_STRIP, 0, 4);
        useQuadProgram();
        curTex = null;
    }

    private static final String VERTEX_SHADER =
        "#version 300 es\n" +
        "in vec2 pos; in vec2 uv; in vec4 color; in float mode;\n" +
        "uniform mat4 projection;\n" +
        "out vec2 vUV; out vec4 vColor; out float vMode;\n" +
        "void main() { gl_Position = projection * vec4(pos, 0.0, 1.0); vUV = uv; vColor = color; vMode = mode; }\n";
    private static final String FRAGMENT_SHADER =
        "#version 300 es\nprecision mediump float;\n" +
        "in vec2 vUV; in vec4 vColor; in float vMode;\n" +
        "uniform sampler2D tex;\nout vec4 fragColor;\n" +
        "void main() { vec4 c = texture(tex, vUV);\n" +
        "  if (vMode > 0.5) fragColor = vec4(vColor.rgb, vColor.a * c.r); else fragColor = c * vColor; }\n";
    private static final String BG_VERTEX_SHADER =
        "#version 300 es\nout vec2 vUV;\n" +
        "void main() { int id = gl_VertexID; vec2 p = vec2((id & 1) != 0 ? 1.0 : -1.0, (id & 2) != 0 ? -1.0 : 1.0);\n" +
        "  gl_Position = vec4(p, 0.0, 1.0); vUV = vec2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5); }\n";
    private static final String BG_FRAGMENT_SHADER =
        "#version 300 es\nprecision highp float;\n" +
        "in vec2 vUV; out vec4 fragColor;\n" +
        "uniform sampler2D tex; uniform float time; uniform vec2 mouse; uniform vec2 texel; uniform float cover;\n" +
        "uniform vec4 regions[96]; uniform vec2 glints[2]; uniform vec2 candles[3];\n" +
        "float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }\n" +
        "float flick(float t) { return 0.5*sin(t*7.3) + 0.3*sin(t*13.1+1.7) + 0.2*sin(t*23.7+4.1); }\n" +
        "float gauss(vec2 uv, vec4 r) { vec2 d = (uv - r.xy) / r.zw; return exp(-dot(d, d) * 2.2); }\n" +
        "void main() {\n" +
        "  float t = time; vec2 uv = vUV;\n" +
        "  if (cover < 1.0) uv.y = 0.5 + (uv.y - 0.5) * cover; else if (cover > 1.0) uv.x = 0.5 + (uv.x - 0.5) / cover;\n" +
        "  float z = 1.03 + 0.012 * sin(t * 0.045);\n" +
        "  uv = (uv - 0.5) / z + 0.5 + vec2(sin(t * 0.031), cos(t * 0.027)) * 0.003;\n" +
        "  float depth = 0.25 + 0.45 * smoothstep(0.12, 0.35, uv.y) + 0.6 * gauss(uv, vec4(0.25, 0.86, 0.13, 0.17)) + 0.6 * gauss(uv, vec4(0.855, 0.89, 0.09, 0.15));\n" +
        "  uv -= mouse * depth * vec2(1.8 / 1920.0, 1.8 / 1080.0);\n" +
        "  vec2 disp = vec2(0.0);\n" +
        "  for (int i = 0; i < 48; i++) {\n" +
        "    vec4 R = regions[i * 2]; vec4 M = regions[i * 2 + 1];\n" +
        "    if (R.z <= 0.0) continue;\n" +
        "    float w = gauss(uv, R);\n" +
        "    if (w < 0.002) continue;\n" +
        "    float sn = sin(t * 6.2831853 / M.z + M.w);\n" +
        "    if (M.x < 0.5) { float b = 0.5 + 0.5 * sn; b = b * b * (3.0 - 2.0 * b);\n" +
        "      disp -= (uv - R.xy) * (M.y * 0.014 * b) * w; disp.y += M.y * (2.4 / 1080.0) * b * w; }\n" +
        "    else { float s2 = sin(t * 6.2831853 / (M.z * 1.37) + M.w * 1.7); disp += vec2(sn * M.y * 1.5 / 1920.0, s2 * M.y * 0.9 / 1080.0) * w; }\n" +
        "  }\n" +
        "  uv += disp;\n" +
        "  uv = clamp(uv, texel, 1.0 - texel);\n" +
        "  vec3 c = texture(tex, uv).rgb;\n" +
        "  float f = flick(t);\n" +
        "  float warm = gauss(uv, vec4(0.47, 0.62, 0.45, 0.5)) * 0.55;\n" +
        "  for (int k = 0; k < 3; k++) if (candles[k].x >= 0.0) warm += gauss(uv, vec4(candles[k], 0.08, 0.1)) * 0.8;\n" +
        "  for (int g = 0; g < 2; g++) warm += gauss(uv, vec4(glints[g], 0.04, 0.06)) * 0.7;\n" +
        "  c *= 1.0 + warm * (0.05 + 0.045 * f) * vec3(1.0, 0.86, 0.62);\n" +
        "  for (int k = 0; k < 3; k++) if (candles[k].x >= 0.0) { float fk = flick(t * 1.07 + float(k) * 3.1);\n" +
        "    c += vec3(1.0, 0.58, 0.22) * gauss(uv, vec4(candles[k], 0.035, 0.06)) * (0.07 + 0.04 * fk); }\n" +
        "  for (int g = 0; g < 2; g++) { vec2 d = (uv - glints[g]) * vec2(1920.0, 1080.0);\n" +
        "    float tw = pow(max(0.0, sin(t * (0.9 + 0.4 * float(g)) + float(g) * 2.3)), 24.0);\n" +
        "    float star = exp(-dot(d, d) / 60.0) + 0.35 * exp(-abs(d.x) * 0.6) * exp(-d.y * d.y / 3.0) + 0.35 * exp(-abs(d.y) * 0.6) * exp(-d.x * d.x / 3.0);\n" +
        "    c += vec3(1.0, 0.9, 0.7) * star * tw * 0.55; }\n" +
        "  float rx = uv.x * 0.85 + uv.y * 0.45;\n" +
        "  float ray = pow(0.5 + 0.5 * sin(rx * 26.0 + sin(t * 0.11) * 2.0), 6.0) * 0.6 + pow(0.5 + 0.5 * sin(rx * 11.0 - t * 0.07), 8.0) * 0.4;\n" +
        "  c += vec3(1.0, 0.82, 0.55) * ray * smoothstep(0.85, 0.0, uv.y) * 0.045;\n" +
        "  vec2 q = vUV;\n" +
        "  c *= 1.0 - 0.42 * smoothstep(0.30, 0.0, q.y) - 0.5 * smoothstep(0.74, 1.0, q.y);\n" +
        "  c *= mix(0.5, 1.0, smoothstep(1.15, 0.35, length((q - 0.5) * vec2(1.25, 1.0))));\n" +
        "  c += (hash2(q * vec2(1920.0, 1080.0) + fract(t * 0.73) * 91.0) - 0.5) * 0.016;\n" +
        "  fragColor = vec4(c, 1.0);\n" +
        "}\n";
}

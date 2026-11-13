import MetalKit
import CoreText

let resolutions: [(px: Int, title: String)] = [(0, "Natywna (rozmiar okna)"), (720, "720p (1280×720)"), (1080, "1080p (1920×1080)"),
                                               (1440, "1440p (2560×1440)"), (2160, "2160p (3840×2160)")]
let frameLimits: [Int] = [30, 40, 60, 120]

#if os(macOS)
import Cocoa


@MainActor
final class GameView: MTKView {
    weak var app: AppDelegate?
    var renderHeight = 0 { didSet { updateDrawableSize() } }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    override func makeTouchBar() -> NSTouchBar? { nil }
    override func setFrameSize(_ s: NSSize) { super.setFrameSize(s); updateDrawableSize() }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); updateDrawableSize() }
    func updateDrawableSize() {
        let b = bounds.size
        guard b.width > 0, b.height > 0 else { return }
        autoResizeDrawable = false
        if renderHeight > 0 {
            let aspect = b.width / b.height
            let h16 = CGFloat(renderHeight)
            let h = aspect >= 16.0 / 9.0 ? h16 : h16 * (16.0 / 9.0) / aspect
            drawableSize = CGSize(width: (h * aspect).rounded(), height: h.rounded())
        } else {
            let s = window?.backingScaleFactor ?? 2
            drawableSize = CGSize(width: b.width * s, height: b.height * s)
        }
    }
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        if let t = tracking { removeTrackingArea(t) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(tracking!)
        super.updateTrackingAreas()
    }
    func virtualPoint(_ e: NSEvent) -> SIMD2<Float> {
        let p = convert(e.locationInWindow, from: nil)
        guard let r = app?.renderer else { return .zero }
        let px = Float(p.x / bounds.width) * Float(drawableSize.width)
        let py = Float((bounds.height - p.y) / bounds.height) * Float(drawableSize.height)
        let vp = r.viewportPx
        return SIMD2((px - vp.x) / vp.w * VW, (py - vp.y) / vp.h * VH)
    }
    override func mouseMoved(with e: NSEvent) { app?.scene?.padCursor = false; app?.scene?.mouseMoved(virtualPoint(e)) }
    override func mouseDragged(with e: NSEvent) { app?.scene?.mouseMoved(virtualPoint(e)) }
    override func mouseDown(with e: NSEvent) { window?.makeFirstResponder(self); app?.scene?.padCursor = false; app?.scene?.click(virtualPoint(e)) }
    override func rightMouseDown(with e: NSEvent) { app?.scene?.rightClick() }
    override func keyDown(with e: NSEvent) { app?.scene?.keyDown(e.keyCode) }
    override func scrollWheel(with e: NSEvent) { app?.scene?.scroll(Float(e.scrollingDeltaY) * (e.hasPreciseScrollingDeltas ? 1 : 12)) }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, MTKViewDelegate, NSMenuDelegate, NSMenuItemValidation, GameHost {
    let supportsWindowModes = true
    var window: NSWindow!
    var view: GameView!
    var renderer: Renderer!
    var scene: Scene?
    var audio: Audio!
    let gamepad = Gamepad()
    private var last = CACurrentMediaTime()
    let env = ProcessInfo.processInfo.environment
    lazy var autotest = env["GWENT_AUTOTEST"] == "1"
    lazy var logURL = URL(fileURLWithPath: env["GWENT_LOG"] ?? (NSHomeDirectory() + "/Library/Logs/GwentReimagined.log"))
    private var fpsFrames = 0, fpsT: Double = 0, worst: Double = 0
    func log(_ s: String) {
        guard autotest else { return }
        let line = s + "\n"
        if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
        else { try? line.write(to: logURL, atomically: true, encoding: .utf8) }
    }
    let resMenu = NSMenu(title: "Rozdzielczość renderowania"), fpsMenu = NSMenu(title: "Limit klatek"), langMenu = NSMenu(title: "Język")
    let soundMenu = NSMenu(title: "Dźwięk")
    let res = Bundle.main.resourceURL!

    var renderRes: Int { get { UserDefaults.standard.integer(forKey: "renderRes") } set { UserDefaults.standard.set(newValue, forKey: "renderRes") } }
    var frameLimit: Int {
        get { let v = UserDefaults.standard.integer(forKey: "frameLimit"); return v == 0 ? 60 : v }
        set { UserDefaults.standard.set(newValue, forKey: "frameLimit") }
    }
    var screenFPS: Int { max(30, (window?.screen ?? NSScreen.main)?.maximumFramesPerSecond ?? 60) }
    var lang: String {
        get { UserDefaults.standard.string(forKey: "lang") ?? "en" }
        set { UserDefaults.standard.set(newValue, forKey: "lang") }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        let ud = UserDefaults.standard
        if !ud.bool(forKey: "migratedLegacyDefaults"), let old = UserDefaults(suiteName: "pl.retronative.gwint.native") {
            for k in ["customDecks", "favoriteDeck", "frameLimit", "lang", "renderRes", "saveDir"] where ud.object(forKey: k) == nil {
                if let v = old.object(forKey: k) { ud.set(v, forKey: k) }
            }
            ud.set(true, forKey: "migratedLegacyDefaults")
        }
        let me = NSRunningApplication.current
        if let other = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .first(where: { $0.processIdentifier != me.processIdentifier && !$0.isTerminated }) {
            other.activate(); NSApp.terminate(nil); return
        }
        if let icon = Bundle.main.image(forResource: "AppIcon") { NSApp.applicationIconImage = icon }
        CTFontManagerRegisterFontsForURL(res.appendingPathComponent("game/fonts/gwent.ttf") as CFURL, .process, nil)

        GameData.shared = GameData(dir: res.appendingPathComponent("data"))
        GameData.shared.language = lang

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 810),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "GwentReimagined"
        window.backgroundColor = .black
        window.contentMinSize = NSSize(width: 800, height: 450)
        window.collectionBehavior = [.fullScreenPrimary]
        window.setFrameAutosaveName("GwentReimaginedMain")
        if window.frame.origin == .zero { window.center() }
        if autotest || env["GWENT_SCREEN"] == "builtin", let s = NSScreen.screens.first(where: { scr in
            let id = (scr.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            return CGDisplayIsBuiltin(id) != 0 }) { window.setFrame(s.visibleFrame, display: false) }
        if env["GWENT_SHOT"] == "1" { window.styleMask = [.borderless]; window.setFrame(NSRect(x: 0, y: 0, width: 1280, height: 720), display: false) }
        view = GameView(frame: window.contentView!.bounds)
        view.app = self
        view.autoresizingMask = [.width, .height]
        renderer = Renderer(view: view, gameDir: res.appendingPathComponent("game"))
        view.delegate = self
        window.contentView = view
        applyFrameRate()
        view.renderHeight = renderRes
        audio = Audio(gameDir: res.appendingPathComponent("game"))
        scene = Scene(renderer: renderer, audio: audio)
        scene?.onLanguageChange = { [weak self] code in self?.lang = code; self?.refreshMenus() }
        scene?.host = self
        gamepad.scene = scene
        if autotest { audio.muted = true; audio.musicOn = false; scene?.autotest = true; scene?.log = { [weak self] s in self?.log(s) } }
        if env["GWENT_MUTE"] == "1" { audio.muted = true; audio.musicOn = false }
        switch env["GWENT_SHOW"] ?? "" {
        case "builder": scene?.builder.load(GameData.shared.decks[0], customIndex: nil); scene?.screen = .builder; scene?.leaderPickerOpen = env["GWENT_LEADERS"] == "1"
        case "decks": scene?.screen = .decks; if let f = env["GWENT_FACTION"] { scene?.selFaction = f; scene?.deckStage = 1; if let pv = env["GWENT_PREVIEW"], let n = Int(pv) { scene?.previewDeck = n } }
        case "rules": scene?.openRules()
        case "options": scene?.optionsOpen = true
        case "saveprompt": scene?.askSaveLocation(then: nil)
        case "career":
            if let f = env["GWENT_CAREER"], !Career.shared.active { Career.shared.start(f); for i in 0..<Int(env["GWENT_BEATEN"] ?? "0")! { _ = Career.shared.win(i) } }
            scene?.screen = .career
            if let fs = env["GWENT_FIGHT"], let fi = Int(fs) { scene?.startCareerFight(fi); scene?.game?.autoHuman = true }
            if env["GWENT_REWARD"] == "1" { scene?.careerRewards = Career.shared.rewardOptions(3); scene?.careerNewLeader = Career.shared.leaders.last }
        case "start": scene?.screen = .decks
        case "licenses": scene?.creditsOpen = true
        default: break
        }
        renderer.preload(["img/start_bg.jpg", "img/board.jpg"])
        if !audio.muted { audio.playMusic() }
        buildMenu()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeScreenNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let s = self else { return }
                s.applyFrameRate(); s.refreshMenus()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }

    func mtkView(_ v: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in v: MTKView) {
        let now = CACurrentMediaTime()
        let dt = Float(min(0.1, now - last)); last = now
        if autotest {
            fpsFrames += 1; fpsT += Double(dt); worst = max(worst, Double(dt))
            if fpsT >= 5 { log(String(format: "FPS %.1f, najdłuższa klatka %.0f ms, bufor %dx%d", Double(fpsFrames) / fpsT, worst * 1000, Int(v.drawableSize.width), Int(v.drawableSize.height))); fpsFrames = 0; fpsT = 0; worst = 0 }
        }
        guard let cb = renderer.begin(view: v) else { return }
        gamepad.update(dt)
        scene?.frame(dt: dt)
        renderer.end(cb, view: v)
    }

    func buildMenu() {
        let main = NSMenu()
        func sub(_ title: String, _ items: [NSMenuItem], menu: NSMenu? = nil) {
            let it = NSMenuItem(); let m = menu ?? NSMenu(title: title); m.title = title
            items.forEach { m.addItem($0) }; it.submenu = m; main.addItem(it)
        }
        func item(_ t: String, _ a: Selector?, _ k: String = "", _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: t, action: a, keyEquivalent: k); i.keyEquivalentModifierMask = mods; return i
        }
        func submenuItem(_ t: String, _ m: NSMenu) -> NSMenuItem { let i = NSMenuItem(title: t, action: nil, keyEquivalent: ""); i.submenu = m; return i }
        sub("GwentReimagined", [item("O programie GwentReimagined", #selector(showAbout)), item("Licencje…", #selector(showCredits)), .separator(),
                      item("Ukryj GwentReimagined", #selector(NSApplication.hide(_:)), "h"),
                      item("Zakończ GwentReimagined", #selector(NSApplication.terminate(_:)), "q")])
        for r in resolutions { let it = item(r.title, #selector(pickResolution(_:)), "", []); it.tag = r.px; resMenu.addItem(it) }
        for f in frameLimits { let it = item("\(f) FPS", #selector(pickFrameLimit(_:)), "", []); it.tag = f; fpsMenu.addItem(it) }
        sub("Okno", [item("Pełny ekran", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
                     item("Minimalizuj", #selector(NSWindow.performMiniaturize(_:)), "m"), item("Zamknij", #selector(NSWindow.performClose(_:)), "w")])
        NSApp.mainMenu = main
        refreshMenus()
    }
    func menuNeedsUpdate(_ m: NSMenu) { refreshMenus() }
    func refreshMenus() {
        for it in resMenu.items { it.state = it.tag == renderRes ? .on : .off }
        let hz = screenFPS
        for it in fpsMenu.items { it.state = it.tag == frameLimit ? .on : .off; it.title = it.tag > hz ? "\(it.tag) FPS (ekran: \(hz) Hz)" : "\(it.tag) FPS" }
        for it in langMenu.items { it.state = (it.representedObject as? String) == lang ? .on : .off }
        for it in soundMenu.items where it.tag == 1 { it.state = audio?.musicOn == true ? .on : .off }
    }
    func validateMenuItem(_ m: NSMenuItem) -> Bool { m.menu === fpsMenu ? m.tag <= screenFPS : true }
    func setRenderRes(_ px: Int) { renderRes = px; view.renderHeight = px; refreshMenus() }
    func setFrameLimit(_ f: Int) { frameLimit = f; applyFrameRate(); refreshMenus() }
    var availableFrameLimits: [Int] { let hz = screenFPS; let l = frameLimits.filter { $0 <= hz && hz % $0 == 0 }; return l.isEmpty ? [hz] : l }
    var effectiveFrameLimit: Int { let a = availableFrameLimits; return a.contains(frameLimit) ? frameLimit : (a.last { $0 <= frameLimit } ?? a.last!) }
    private var link: CADisplayLink?
    func applyFrameRate() {
        let f = Float(effectiveFrameLimit)
        view.isPaused = true; view.enableSetNeedsDisplay = false
        link?.invalidate()
        let l = view.displayLink(target: self, selector: #selector(tick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: f, maximum: f, preferred: f)
        l.add(to: .main, forMode: .common); link = l
    }
    @objc func tick(_ l: CADisplayLink) { draw(in: view) }
    var isFullScreen: Bool { window.styleMask.contains(.fullScreen) }
    func setFullScreen(_ on: Bool) { if on != isFullScreen { window.toggleFullScreen(nil) } }
    @objc func pickResolution(_ s: NSMenuItem) { renderRes = s.tag; view.renderHeight = s.tag; refreshMenus() }
    @objc func pickFrameLimit(_ s: NSMenuItem) { setFrameLimit(s.tag) }
    @objc func pickLang(_ s: NSMenuItem) { if let c = s.representedObject as? String { scene?.setLanguage(c) } }
    @objc func toggleMusic(_ s: NSMenuItem) { audio.musicOn.toggle(); refreshMenus() }
    @objc func nextTrack() { audio.skipTrack() }
    @objc func toggleMute(_ s: NSMenuItem) { audio.muted.toggle(); s.state = audio.muted ? .on : .off; if audio.muted { audio.musicOn = false } }
    @objc func showRules() { scene?.openRules() }
    @objc func showCredits() { scene?.creditsOpen = true; scene?.game?.paused = true }
    @objc func goTitle() { scene?.game = nil; scene?.screen = .title }
    @objc func newGame() { scene?.screen = .decks }
    @objc func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "GwentReimagined", .applicationVersion: "1.0", .version: "",
                                                     .credits: NSAttributedString(string: "All characters, the Witcher universe and Gwent © CD PROJEKT S.A. / CD PROJEKT RED.\nUnofficial fan project — a fork of Gwent Classic v5.0 (github.com/ia2904/gwent-classic-v5.0), MIT + Commons Clause.\nReimagined / ported by grechucia — github.com/grechucia/gwent-reimagined")])
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
#else
import UIKit
UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(IOSAppDelegate.self))
#endif

// macOS entry point: window, Metal view, mouse/keyboard input, frame pacing and the menu bar.
import MetalKit
import CoreText

let resolutions: [(px: Int, title: String)] = [(0, "Native (window size)"), (720, "720p (1280×720)"), (1080, "1080p (1920×1080)"),
                                               (1440, "1440p (2560×1440)"), (2160, "2160p (3840×2160)")]
let frameLimits: [Int] = [30, 40, 60]

#if os(macOS)
import Cocoa


/// Metal view for macOS: drawable size, mouse/keyboard input.
@MainActor
final class GameView: MTKView {
    weak var app: AppDelegate?
    var renderHeight = 0 { didSet { updateDrawableSize() } }
    override var acceptsFirstResponder: Bool { true }
    /// Accepts the first click even when the window is not focused.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// No Touch Bar.
    override func makeTouchBar() -> NSTouchBar? { nil }
    /// Updates the drawable size when the window is resized.
    override func setFrameSize(_ size: NSSize) { super.setFrameSize(size); updateDrawableSize() }
    /// Updates the drawable size when the window changes screen scale.
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); updateDrawableSize() }
    /// Sets the drawable size from the view size and the render resolution option.
    func updateDrawableSize() {
        let boundsSize = bounds.size
        guard boundsSize.width > 0, boundsSize.height > 0 else { return }
        autoResizeDrawable = false
        if renderHeight > 0 {
            let aspect = boundsSize.width / boundsSize.height
            let targetHeight = CGFloat(renderHeight)
            let h = aspect >= 16.0 / 9.0 ? targetHeight : targetHeight * (16.0 / 9.0) / aspect
            drawableSize = CGSize(width: (h * aspect).rounded(), height: h.rounded())
        } else {
            let s = window?.backingScaleFactor ?? 2
            drawableSize = CGSize(width: boundsSize.width * s, height: boundsSize.height * s)
        }
        layer?.contentsScale = drawableSize.width / boundsSize.width
    }
    var tracking: NSTrackingArea?
    /// Tracks mouse movement inside the view.
    override func updateTrackingAreas() {
        if let trackingArea = tracking { removeTrackingArea(trackingArea) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(tracking!)
        super.updateTrackingAreas()
    }
    /// Converts a mouse event to the virtual 1920x1080 space.
    func virtualPoint(_ event: NSEvent) -> SIMD2<Float> {
        let location = convert(event.locationInWindow, from: nil)
        guard let renderer = app?.renderer else { return .zero }
        let pixelX = Float(location.x / bounds.width) * Float(drawableSize.width)
        let pixelY = Float((bounds.height - location.y) / bounds.height) * Float(drawableSize.height)
        return renderer.virtualPoint(pixelX: pixelX, pixelY: pixelY)
    }
    override func mouseMoved(with event: NSEvent) { app?.scene?.padCursor = false; app?.scene?.mouseMoved(virtualPoint(event)) }
    override func mouseDragged(with event: NSEvent) { app?.scene?.mouseMoved(virtualPoint(event)) }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); app?.scene?.padCursor = false; app?.scene?.click(virtualPoint(event)) }
    override func rightMouseDown(with event: NSEvent) { app?.scene?.rightClick() }
    override func keyDown(with event: NSEvent) { app?.scene?.keyDown(event.keyCode) }
    override func scrollWheel(with event: NSEvent) { app?.scene?.scroll(Float(event.scrollingDeltaY) * (event.hasPreciseScrollingDeltas ? 1 : 12)) }
}

/// macOS application delegate: window, renderer, audio, scene, menus and settings.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, MTKViewDelegate, NSMenuDelegate, NSMenuItemValidation, GameHost {
    let supportsWindowModes = true
    var window: NSWindow!
    var view: GameView!
    var renderer: Renderer!
    var scene: Scene?
    var audio: Audio!
    let gamepad = Gamepad()
    var last = CACurrentMediaTime()
    let env = ProcessInfo.processInfo.environment
    lazy var autotest = env["GWENT_AUTOTEST"] == "1"
    lazy var logURL = URL(fileURLWithPath: env["GWENT_LOG"] ?? (NSHomeDirectory() + "/Library/Logs/GwentReimagined.log"))
    var fpsFrames = 0, fpsT: Double = 0, worst: Double = 0
    /// Appends a line to the test log.
    func log(_ text: String) {
        guard autotest else { return }
        let line = text + "\n"
        if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
        else { try? line.write(to: logURL, atomically: true, encoding: .utf8) }
    }
    let resMenu = NSMenu(title: "Render resolution"), fpsMenu = NSMenu(title: "Frame limit"), langMenu = NSMenu(title: "Language")
    let soundMenu = NSMenu(title: "Sound")
    let resources = Bundle.main.resourceURL!

    var renderRes: Int { get { UserDefaults.standard.integer(forKey: "renderRes") } set { UserDefaults.standard.set(newValue, forKey: "renderRes") } }
    var frameLimit: Int {
        get { let stored = UserDefaults.standard.integer(forKey: "frameLimit"); return stored == 0 ? 60 : stored }
        set { UserDefaults.standard.set(newValue, forKey: "frameLimit") }
    }
    var screenFPS: Int { max(30, (window?.screen ?? NSScreen.main)?.maximumFramesPerSecond ?? 60) }
    var lang: String {
        get { UserDefaults.standard.string(forKey: "lang") ?? "en" }
        set { UserDefaults.standard.set(newValue, forKey: "lang") }
    }

    /// Sets up the window, the renderer and the scene; handles the GWENT_* test options.
    func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "migratedLegacyDefaults"), let legacyDefaults = UserDefaults(suiteName: "pl.retronative.gwint.native") {
            for key in ["customDecks", "favoriteDeck", "frameLimit", "lang", "renderRes", "saveDir"] where defaults.object(forKey: key) == nil {
                if let value = legacyDefaults.object(forKey: key) { defaults.set(value, forKey: key) }
            }
            defaults.set(true, forKey: "migratedLegacyDefaults")
        }
        let currentApp = NSRunningApplication.current
        if let other = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .first(where: { $0.processIdentifier != currentApp.processIdentifier && !$0.isTerminated }) {
            other.activate(); NSApp.terminate(nil); return
        }
        if let icon = Bundle.main.image(forResource: "AppIcon") { NSApp.applicationIconImage = icon }
        CTFontManagerRegisterFontsForURL(resources.appendingPathComponent("game/fonts/gwent.ttf") as CFURL, .process, nil)

        GameData.shared = GameData(directory: resources.appendingPathComponent("data"))
        GameData.shared.language = lang

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 810),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "GwentReimagined"
        window.backgroundColor = .black
        window.contentMinSize = NSSize(width: 800, height: 450)
        window.collectionBehavior = [.fullScreenPrimary]
        window.setFrameAutosaveName("GwentReimaginedMain")
        if window.frame.origin == .zero { window.center() }
        if autotest || env["GWENT_SCREEN"] == "builtin", let builtInScreen = NSScreen.screens.first(where: { screen in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            return CGDisplayIsBuiltin(id) != 0 }) { window.setFrame(builtInScreen.visibleFrame, display: false) }
        if env["GWENT_SHOT"] == "1" { window.styleMask = [.borderless]; window.setFrame(NSRect(x: 0, y: 0, width: 1280, height: 720), display: false) }
        view = GameView(frame: window.contentView!.bounds)
        view.app = self
        view.autoresizingMask = [.width, .height]
        renderer = Renderer(view: view, gameDir: resources.appendingPathComponent("game"))
        view.delegate = self
        renderer.fillScreen = fillScreen
        window.contentView = view
        applyFrameRate()
        view.renderHeight = renderRes
        audio = Audio(gameDir: resources.appendingPathComponent("game"))
        scene = Scene(renderer: renderer, audio: audio)
        scene?.onLanguageChange = { [weak self] code in self?.lang = code; self?.refreshMenus() }
        scene?.host = self
        gamepad.scene = scene
        if autotest { audio.muted = true; audio.musicOn = false; scene?.autotest = true; scene?.log = { [weak self] message in self?.log(message) } }
        if env["GWENT_MUTE"] == "1" { audio.muted = true; audio.musicOn = false }
        switch env["GWENT_SHOW"] ?? "" {
        case "builder": scene?.builder.load(GameData.shared.decks[0], customIndex: nil); scene?.screen = .builder; scene?.leaderPickerOpen = env["GWENT_LEADERS"] == "1"
        case "decks": scene?.screen = .decks; if let faction = env["GWENT_FACTION"] { scene?.selFaction = faction; scene?.deckStage = 1; if let preview = env["GWENT_PREVIEW"], let notification = Int(preview) { scene?.previewDeck = notification } }
        case "rules": scene?.openRules()
        case "options": scene?.optionsOpen = true
        case "saveprompt": scene?.askSaveLocation(then: nil)
        case "career":
            if let faction = env["GWENT_CAREER"], !Career.shared.active { Career.shared.start(faction); for i in 0..<Int(env["GWENT_BEATEN"] ?? "0")! { _ = Career.shared.win(i) } }
            scene?.screen = .career
            if let fight = env["GWENT_FIGHT"], let fightIndex = Int(fight) { scene?.startCareerFight(fightIndex); scene?.game?.autoHuman = true }
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
                guard let strongSelf = self else { return }
                strongSelf.applyFrameRate(); strongSelf.refreshMenus()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    /// Quits when the window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ application: NSApplication) -> Bool { true }

    /// Not used: the drawable size is managed manually.
    func mtkView(_ metalView: MTKView, drawableSizeWillChange size: CGSize) {}
    /// Renders one frame.
    func draw(in metalView: MTKView) {
        let now = CACurrentMediaTime()
        let dt = Float(min(0.1, now - last)); last = now
        if autotest {
            fpsT += Double(dt); worst = max(worst, Double(dt))
            if fpsT >= 5 { log(String(format: "FPS %.1f, longest frame %.0f ms, buffer %dx%d", Double(fpsFrames) / fpsT, worst * 1000, Int(metalView.drawableSize.width), Int(metalView.drawableSize.height))); fpsFrames = 0; fpsT = 0; worst = 0 }
        }
        guard let commandBuffer = renderer.begin(view: metalView) else { return }
        fpsFrames += 1
        gamepad.update(dt)
        scene?.frame(dt: dt)
        renderer.end(commandBuffer, view: metalView)
    }

    /// Builds the minimal menu bar (app and window menus).
    func buildMenu() {
        let main = NSMenu()
        func sub(_ title: String, _ items: [NSMenuItem], menu: NSMenu? = nil) {
            let menuItem = NSMenuItem(); let submenu = menu ?? NSMenu(title: title); submenu.title = title
            items.forEach { submenu.addItem($0) }; menuItem.submenu = submenu; main.addItem(menuItem)
        }
        func item(_ text: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: text, action: action, keyEquivalent: key); i.keyEquivalentModifierMask = mods; return i
        }
        func submenuItem(_ text: String, _ menu: NSMenu) -> NSMenuItem { let i = NSMenuItem(title: text, action: nil, keyEquivalent: ""); i.submenu = menu; return i }
        sub("GwentReimagined", [item(L("About") + " GwentReimagined", #selector(showAbout)), item(L("Licenses") + "…", #selector(showCredits)), .separator(),
                      item(L("Hide") + " GwentReimagined", #selector(NSApplication.hide(_:)), "h"),
                      item(L("Quit") + " GwentReimagined", #selector(NSApplication.terminate(_:)), "q")])
        for resolution in resolutions { let menuItem = item(resolution.title, #selector(pickResolution(_:)), "", []); menuItem.tag = resolution.px; resMenu.addItem(menuItem) }
        for limit in frameLimits { let menuItem = item("\(limit) FPS", #selector(pickFrameLimit(_:)), "", []); menuItem.tag = limit; fpsMenu.addItem(menuItem) }
        sub(L("Window"), [item(L("Full screen"), #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
                     item(L("Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m"), item(L("Close"), #selector(NSWindow.performClose(_:)), "w")])
        NSApp.mainMenu = main
        refreshMenus()
    }
    /// Refreshes menu state before it opens.
    func menuNeedsUpdate(_ menu: NSMenu) { refreshMenus() }
    /// Updates check marks in the menus.
    func refreshMenus() {
        for menuItem in resMenu.items { menuItem.state = menuItem.tag == renderRes ? .on : .off }
        let refreshRate = screenFPS
        for menuItem in fpsMenu.items { menuItem.state = menuItem.tag == frameLimit ? .on : .off; menuItem.title = menuItem.tag > refreshRate ? "\(menuItem.tag) FPS (display: \(refreshRate) Hz)" : "\(menuItem.tag) FPS" }
        for menuItem in langMenu.items { menuItem.state = (menuItem.representedObject as? String) == lang ? .on : .off }
        for menuItem in soundMenu.items where menuItem.tag == 1 { menuItem.state = audio?.musicOn == true ? .on : .off }
    }
    /// Disables frame limits the screen cannot show.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { menuItem.menu === fpsMenu ? menuItem.tag <= screenFPS : true }
    /// Changes the render resolution.
    /// Scaling mode stored in UserDefaults; the default fills the screen on iOS and keeps 16:9 on macOS.
    var fillScreen: Bool { (UserDefaults.standard.object(forKey: "fillScreen") as? Bool) ?? false }
    func setFillScreen(_ on: Bool) { UserDefaults.standard.set(on, forKey: "fillScreen"); renderer.fillScreen = on }
    func setRenderRes(_ height: Int) { renderRes = height; view.renderHeight = height; refreshMenus() }
    /// Changes the frame limit.
    func setFrameLimit(_ limit: Int) { frameLimit = limit; applyFrameRate(); refreshMenus() }
    var availableFrameLimits: [Int] { let refreshRate = screenFPS; let limits = frameLimits.filter { $0 <= refreshRate && refreshRate % $0 == 0 }; return limits.isEmpty ? [refreshRate] : limits }
    var effectiveFrameLimit: Int { let available = availableFrameLimits; return available.contains(frameLimit) ? frameLimit : (available.last { $0 <= frameLimit } ?? available.last!) }
    var link: CADisplayLink?
    /// Creates the display link that drives rendering at the chosen frame rate.
    func applyFrameRate() {
        let rate = Float(effectiveFrameLimit)
        view.isPaused = true; view.enableSetNeedsDisplay = false
        link?.invalidate()
        let displayLink = view.displayLink(target: self, selector: #selector(tick(_:)))
        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
        displayLink.add(to: .main, forMode: .common); link = displayLink
    }
    /// Called by the display link: renders a frame.
    @objc func tick(_ link: CADisplayLink) { view.draw() }
    var isFullScreen: Bool { window.styleMask.contains(.fullScreen) }
    /// Enters or leaves full screen.
    func setFullScreen(_ on: Bool) { if on != isFullScreen { window.toggleFullScreen(nil) } }
    @objc func pickResolution(_ sender: NSMenuItem) { renderRes = sender.tag; view.renderHeight = sender.tag; refreshMenus() }
    @objc func pickFrameLimit(_ sender: NSMenuItem) { setFrameLimit(sender.tag) }
    @objc func pickLang(_ sender: NSMenuItem) { if let code = sender.representedObject as? String { scene?.setLanguage(code) } }
    @objc func toggleMusic(_ sender: NSMenuItem) { audio.musicOn.toggle(); refreshMenus() }
    @objc func nextTrack() { audio.skipTrack() }
    @objc func toggleMute(_ sender: NSMenuItem) { audio.muted.toggle(); sender.state = audio.muted ? .on : .off; if audio.muted { audio.musicOn = false } }
    @objc func showRules() { scene?.openRules() }
    @objc func showCredits() { scene?.creditsOpen = true; scene?.game?.paused = true }
    @objc func goTitle() { scene?.game = nil; scene?.screen = .title }
    @objc func newGame() { scene?.screen = .decks }
    /// Shows the About panel.
    @objc func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "GwentReimagined", .applicationVersion: "1.0.1", .version: "",
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

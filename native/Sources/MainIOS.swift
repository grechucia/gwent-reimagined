// iOS / iPadOS entry point: app and scene delegates, the Metal view and touch input.
#if os(iOS)
import UIKit
import MetalKit
import CoreText
import AVFoundation

/// Metal view for iOS that converts touches into scene input.
@MainActor
final class IOSGameView: MTKView {
    weak var app: IOSAppDelegate?
    var renderHeight = 0 { didSet { updateDrawableSize() } }
    var start = CGPoint.zero
    var last = CGPoint.zero
    var dragging = false
    var longFired = false
    var longTimer: Timer?

    /// Keeps the drawable size in sync with the view size.
    override func layoutSubviews() { super.layoutSubviews(); updateDrawableSize() }
    /// Sets the drawable size from the view size and the render resolution option.
    func updateDrawableSize() {
        let b = bounds.size
        guard b.width > 0, b.height > 0 else { return }
        autoResizeDrawable = false
        let aspect = b.width / b.height
        if renderHeight > 0 {
            let h16 = CGFloat(renderHeight)
            let h = aspect >= 16.0 / 9.0 ? h16 : h16 * (16.0 / 9.0) / aspect
            drawableSize = CGSize(width: (h * aspect).rounded(), height: h.rounded())
        } else {
            let s = window?.screen.nativeScale ?? UIScreen.main.nativeScale
            drawableSize = CGSize(width: b.width * s, height: b.height * s)
        }
    }
    /// Converts a touch position to the virtual 1920x1080 space.
    func virtualPoint(_ p: CGPoint) -> SIMD2<Float> {
        guard let r = app?.renderer, bounds.width > 0 else { return .zero }
        let px = Float(p.x / bounds.width) * Float(drawableSize.width)
        let py = Float(p.y / bounds.height) * Float(drawableSize.height)
        let vp = r.viewportPx
        return SIMD2((px - vp.x) / vp.w * virtualWidth, (py - vp.y) / vp.h * virtualHeight)
    }

    /// Touch down: moves focus and starts the long-press timer (long press = card details).
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, let s = app?.scene else { return }
        start = t.location(in: self); last = start; dragging = false; longFired = false
        s.padCursor = false
        s.mouseMoved(virtualPoint(start))
        longTimer?.invalidate()
        longTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let v = self, !v.dragging else { return }
                v.longFired = true
                v.app?.scene?.rightClick()
            }
        }
    }
    /// Dragging scrolls lists.
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, let s = app?.scene else { return }
        let p = t.location(in: self)
        if !dragging && hypot(p.x - start.x, p.y - start.y) > 12 { dragging = true; longTimer?.invalidate() }
        if dragging {
            let a = virtualPoint(last), b = virtualPoint(p)
            s.scroll((b.y - a.y) * 1.2)
        }
        last = p
        s.mouseMoved(virtualPoint(p))
    }
    /// Tap = click, unless the touch was a drag or a long press.
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        longTimer?.invalidate()
        guard let t = touches.first, let s = app?.scene else { return }
        let p = virtualPoint(t.location(in: self))
        if !dragging && !longFired { s.click(p) }
        s.mouse = SIMD2(-1, -1)
    }
    /// Cancels the current touch.
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        longTimer?.invalidate()
        app?.scene?.mouse = SIMD2(-1, -1)
    }
}

/// Root view controller: full screen, landscape only.
@MainActor
final class GameViewController: UIViewController {
    weak var app: IOSAppDelegate?
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    /// Uses the shared Metal view as its view.
    override func loadView() { view = app?.view }
}

/// iOS application delegate: sets up data, renderer, audio and the scene.
@MainActor
final class IOSAppDelegate: UIResponder, UIApplicationDelegate, MTKViewDelegate, GameHost {
    var window: UIWindow?
    var view: IOSGameView!
    var renderer: Renderer!
    var scene: Scene?
    var audio: Audio!
    let gamepad = Gamepad()
    var last = CACurrentMediaTime()
    let res = Bundle.main.resourceURL!

    var renderRes: Int { get { UserDefaults.standard.integer(forKey: "renderRes") } set { UserDefaults.standard.set(newValue, forKey: "renderRes") } }
    var frameLimit: Int {
        get { let v = UserDefaults.standard.integer(forKey: "frameLimit"); return v == 0 ? 60 : v }
        set { UserDefaults.standard.set(newValue, forKey: "frameLimit") }
    }
    var lang: String {
        get { UserDefaults.standard.string(forKey: "lang") ?? "en" }
        set { UserDefaults.standard.set(newValue, forKey: "lang") }
    }
    let supportsWindowModes = false
    var isFullScreen: Bool { true }
    /// Not applicable on iOS.
    func setFullScreen(_ on: Bool) {}
    /// Not applicable on iOS.
    func refreshMenus() {}
    var screenFPS: Int { max(30, UIScreen.main.maximumFramesPerSecond) }
    var availableFrameLimits: [Int] { let hz = screenFPS; let l = frameLimits.filter { $0 <= hz && hz % $0 == 0 }; return l.isEmpty ? [hz] : l }
    var effectiveFrameLimit: Int { let a = availableFrameLimits; return a.contains(frameLimit) ? frameLimit : (a.last { $0 <= frameLimit } ?? a.last!) }
    /// Changes the render resolution.
    func setRenderRes(_ height: Int) { renderRes = height; view.renderHeight = height }
    /// Changes the frame limit.
    func setFrameLimit(_ limit: Int) { frameLimit = limit; view.preferredFramesPerSecond = effectiveFrameLimit }

    /// Initialises the game when the app launches.
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        try? AVAudioSession.sharedInstance().setActive(true)
        Platform.restoreBookmarkedFolder()
        CTFontManagerRegisterFontsForURL(res.appendingPathComponent("game/fonts/gwent.ttf") as CFURL, .process, nil)
        GameData.shared = GameData(dir: res.appendingPathComponent("data"))
        GameData.shared.language = lang

        view = IOSGameView(frame: CGRect(x: 0, y: 0, width: 1280, height: 720))
        view.app = self
        view.isMultipleTouchEnabled = false
        renderer = Renderer(view: view, gameDir: res.appendingPathComponent("game"))
        view.delegate = self
        view.preferredFramesPerSecond = effectiveFrameLimit
        view.renderHeight = renderRes
        audio = Audio(gameDir: res.appendingPathComponent("game"))
        scene = Scene(renderer: renderer, audio: audio)
        scene?.onLanguageChange = { [weak self] code in self?.lang = code }
        scene?.host = self
        gamepad.scene = scene
        renderer.preload(["img/start_bg.jpg", "img/board.jpg"])
        let env = ProcessInfo.processInfo.environment
        if env["GWENT_MUTE"] == "1" { audio.muted = true; audio.musicOn = false } else { audio.playMusic() }
        if env["GWENT_AUTOTEST"] == "1" { audio.muted = true; audio.musicOn = false; scene?.autotest = true }
        switch env["GWENT_SHOW"] ?? "" {
        case "options": scene?.optionsOpen = true
        case "start": scene?.screen = .decks
        case "career": scene?.screen = .career
        default: break
        }

        return true
    }

    /// Uses IOSSceneDelegate for the app's window scene.
    func application(_ a: UIApplication, configurationForConnecting s: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let c = UISceneConfiguration(name: nil, sessionRole: s.role)
        c.delegateClass = IOSSceneDelegate.self
        return c
    }

    /// Not used: the drawable size is managed manually.
    func mtkView(_ metalView: MTKView, drawableSizeWillChange size: CGSize) {}
    /// Renders one frame.
    func draw(in metalView: MTKView) {
        let now = CACurrentMediaTime()
        let dt = Float(min(0.1, now - last)); last = now
        guard let cb = renderer.begin(view: metalView) else { return }
        gamepad.update(dt)
        scene?.frame(dt: dt)
        renderer.end(cb, view: metalView)
    }
}

/// Creates the window and the root view controller.
@MainActor
final class IOSSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    /// Attaches the game window to the scene.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let ws = scene as? UIWindowScene, let app = UIApplication.shared.delegate as? IOSAppDelegate else { return }
        let vc = GameViewController()
        vc.app = app
        let w = UIWindow(windowScene: ws)
        w.rootViewController = vc
        w.backgroundColor = .black
        w.makeKeyAndVisible()
        window = w
        Platform.iosRoot = vc
    }
}
#endif

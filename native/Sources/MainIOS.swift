#if os(iOS)
import UIKit
import MetalKit
import CoreText
import AVFoundation

@MainActor
final class IOSGameView: MTKView {
    weak var app: IOSAppDelegate?
    var renderHeight = 0 { didSet { updateDrawableSize() } }
    private var start = CGPoint.zero
    private var last = CGPoint.zero
    private var dragging = false
    private var longFired = false
    private var longTimer: Timer?

    override func layoutSubviews() { super.layoutSubviews(); updateDrawableSize() }
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
    private func virtualPoint(_ p: CGPoint) -> SIMD2<Float> {
        guard let r = app?.renderer, bounds.width > 0 else { return .zero }
        let px = Float(p.x / bounds.width) * Float(drawableSize.width)
        let py = Float(p.y / bounds.height) * Float(drawableSize.height)
        let vp = r.viewportPx
        return SIMD2((px - vp.x) / vp.w * VW, (py - vp.y) / vp.h * VH)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with e: UIEvent?) {
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
    override func touchesMoved(_ touches: Set<UITouch>, with e: UIEvent?) {
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
    override func touchesEnded(_ touches: Set<UITouch>, with e: UIEvent?) {
        longTimer?.invalidate()
        guard let t = touches.first, let s = app?.scene else { return }
        let p = virtualPoint(t.location(in: self))
        if !dragging && !longFired { s.click(p) }
        s.mouse = SIMD2(-1, -1)
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with e: UIEvent?) {
        longTimer?.invalidate()
        app?.scene?.mouse = SIMD2(-1, -1)
    }
}

@MainActor
final class GameViewController: UIViewController {
    weak var app: IOSAppDelegate?
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override func loadView() { view = app?.view }
}

@MainActor
final class IOSAppDelegate: UIResponder, UIApplicationDelegate, MTKViewDelegate, GameHost {
    var window: UIWindow?
    var view: IOSGameView!
    var renderer: Renderer!
    var scene: Scene?
    var audio: Audio!
    let gamepad = Gamepad()
    private var last = CACurrentMediaTime()
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
    func setFullScreen(_ on: Bool) {}
    func refreshMenus() {}
    var screenFPS: Int { max(30, UIScreen.main.maximumFramesPerSecond) }
    var availableFrameLimits: [Int] { let hz = screenFPS; let l = frameLimits.filter { $0 <= hz && hz % $0 == 0 }; return l.isEmpty ? [hz] : l }
    var effectiveFrameLimit: Int { let a = availableFrameLimits; return a.contains(frameLimit) ? frameLimit : (a.last { $0 <= frameLimit } ?? a.last!) }
    func setRenderRes(_ px: Int) { renderRes = px; view.renderHeight = px }
    func setFrameLimit(_ f: Int) { frameLimit = f; view.preferredFramesPerSecond = effectiveFrameLimit }

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

    func application(_ a: UIApplication, configurationForConnecting s: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let c = UISceneConfiguration(name: nil, sessionRole: s.role)
        c.delegateClass = IOSSceneDelegate.self
        return c
    }

    func mtkView(_ v: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in v: MTKView) {
        let now = CACurrentMediaTime()
        let dt = Float(min(0.1, now - last)); last = now
        guard let cb = renderer.begin(view: v) else { return }
        gamepad.update(dt)
        scene?.frame(dt: dt)
        renderer.end(cb, view: v)
    }
}

@MainActor
final class IOSSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
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

// Main UI scene: immediate-mode buttons, title screen, game board drawing, card rendering and input routing.
import CoreGraphics
import Foundation
import Metal

private let cardWidth: Float = 85, cardHeight: Float = 122

/// The whole UI: screens, overlays, input handling and drawing of the game.
@MainActor
final class Scene {
    let renderer: Renderer
    let audio: Audio
    var gameData: GameData { GameData.shared }
    /// Top-level screens.
    enum Screen { case title, decks, game, builder, career }
    var screen: Screen = .title { didSet { if screen != oldValue { audio.setMenuMode(screen != .game); if padCursor { mouse = SIMD2(-1, -1) } } } }
    var time: Float = 0
    var mouse = SIMD2<Float>(-1, -1)
    var mouseNorm = SIMD2<Float>(0, 0)
    var clicks: [(R, () -> Void)] = []
    private var hits: [(R, () -> Void)] = []
    var clickTargets: [R] { hits.map { $0.0 } }
    var padCursor = false
    var exitConfirmT: Float = 0
    /// Global AI difficulty for games outside the career (0 easy, 1 normal, 2 hard), stored in UserDefaults.
    var aiLevel: Int {
        get { UserDefaults.standard.object(forKey: "aiLevel") as? Int ?? 1 }
        set { UserDefaults.standard.set(newValue, forKey: "aiLevel") }
    }
    var padNoFocus: [R] = []
    var padNoAuto: [R] = []
    var padPrimary: R?
    var appVersion: String { (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0" }
    var onLanguageChange: ((String) -> Void)?
    var autotest = false
    var log: (String) -> Void = { _ in }
    private var autoT: Float = 0
    var gamesPlayed = 0

    var game: Game?
    var selected: Card?
    var hover: Card?
    private var notes: [(text: String, icon: String?)] = []
    private var noteT: Float = 0
    private var aiT: Float = 0
    var builder = DeckBuilder()
    var builderHover: Card?
    var builderSaved: Float = 0
    var customDecks: [DeckData] = DeckBuilder.loadCustom()
    var wheel: Float = 0
    var allDecks: [DeckData] { gameData.decks + customDecks }
    private var multiSel: [Card] = []
    private var hoverText: String?
    var myDeckIndex = 0
    private var particles: [Particle] = []
    private var glow: MTLTexture!
    var glowTex: MTLTexture { glow }
    var fxList: [FX] = []
    var rulesOpen = false
    var rulesScroll: Float = 0
    var powerSeen: [Int: (Int, Float)] = [:]
    var frameDT: Float = 1 / 60
    var langMenuOpen = false
    var creditsOpen = false
    var deckFrom = -1
    var careerFight: Int?
    var careerRewards: [String]?
    var careerNewLeader: String?
    var careerChapter: Int?
    var careerConfirmReset = false
    var careerDiffPick = 1
    var careerFightName: String?
    var playerName: String { (SaveStore.shared["playerName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? L("Player 1") }
    /// Asks for the player's name and stores it in the save file.
    func askPlayerName(then: (() -> Void)? = nil) {
        Platform.askText(title: L("What's your name?"),
                         message: L("Your name is shown on the board. You can change it in Options."),
                         placeholder: L("Player 1"), current: (SaveStore.shared["playerName"] as? String) ?? "") { text in
            if let n = text?.trimmingCharacters(in: .whitespacesAndNewlines) { SaveStore.shared["playerName"] = String(n.prefix(24)) }
            then?()
        }
    }
    var savePromptOpen = false
    var savePromptThen: (() -> Void)?
    var optionsOpen = false
    weak var host: GameHost?
    var leaderPickerOpen = false
    var deckStage = -1
    var favoriteDeckIndex: Int? {
        get {
            guard let s = SaveStore.shared["favoriteDeck"] as? String, let n = Int(s.dropFirst()) else { return nil }
            let i = s.hasPrefix("c") ? gameData.decks.count + n : n
            return i >= 0 && i < allDecks.count ? i : nil
        }
        set {
            guard let i = newValue else { SaveStore.shared["favoriteDeck"] = nil; return }
            SaveStore.shared["favoriteDeck"] = i >= gameData.decks.count ? "c\(i - gameData.decks.count)" : "p\(i)"
        }
    }
    var previewDeck: Int? = nil
    var previewScroll: Float = 0, previewTarget: Float = 0
    var selFaction = "realms"
    var hoverTextTitle: String?
    var deckSwitchT: Float = 1
    var deckDir: Float = 1
    var builderFilter = 0
    var cardHover: [String: Float] = [:]
    var flyCards: [(d: CardData, from: R, to: R, t: Float)] = []
    var scrollTargetL: Float = 0, scrollTargetR: Float = 0

    /// A floating ember or dust particle of the menu background.
    struct Particle { var p: SIMD2<Float>; var v: SIMD2<Float>; var life: Float; var max: Float; var size: Float; var a: Float; var ember: Bool; var depth: Float }

    init(renderer: Renderer, audio: Audio) {
        self.renderer = renderer; self.audio = audio
        glow = makeGlow()
        for _ in 0..<90 { particles.append(spawn(false, initial: true)) }
        for _ in 0..<26 { particles.append(spawn(true, initial: true)) }
        myDeckIndex = max(0, gameData.decks.firstIndex { $0.faction == "realms" } ?? 0)
        audio.preload(["card", "redraw", "coin", "turn_me", "turn_op", "pass", "round1_start", "round_win", "round_lose", "hero", "horn", "moral", "med", "spy", "scorch", "cold", "fog", "rain", "clear", "game_win", "game_lose", "ally", "decoy", "menu_opening"])
    }

    /// Updates the pointer position (virtual coordinates).
    func mouseMoved(_ p: SIMD2<Float>) { mouse = p; mouseNorm = SIMD2((p.x / virtualWidth - 0.5) * 2, (p.y / virtualHeight - 0.5) * 2) }
    /// Runs the topmost button under the point.
    func click(_ p: SIMD2<Float>) {
        mouse = p
        for (rect, action) in hits.reversed() where rect.contains(p) { action(); return }
    }
    /// Right click / long press: card details or cancel.
    func rightClick() { selected = nil }
    /// Scroll wheel or drag.
    func scroll(_ dy: Float) { wheel += dy }
    /// Keyboard input (Esc closes overlays and cancels choices).
    func keyDown(_ code: UInt16) {
        if code == 53 && rulesOpen { closeRules(); return }
        if code == 53 && creditsOpen { creditsOpen = false; game?.paused = false; return }
        if code == 53 && langMenuOpen { langMenuOpen = false; return }
        if code == 53 && leaderPickerOpen { leaderPickerOpen = false; return }
        if code == 53 && savePromptOpen && SaveStore.shared.chosen { savePromptOpen = false; savePromptThen = nil; return }
        if code == 53 && optionsOpen { optionsOpen = false; game?.paused = false; return }
        if screen == .decks && (code == 51 || code == 53) && previewDeck != nil { previewDeck = nil; deckSwitchT = 0; return }
        if screen == .decks && code == 51 && deckStage >= 0 { deckStage -= 1; deckSwitchT = 0; return }
        if code == 53 { selected = nil; if let g = game, let ch = g.choice, ch.canCancel { multiSel = []; g.resolveChoice(nil) } }
    }

    /// Draws one frame of the current screen and overlays.
    func frame(dt: Float) {
        time += dt
        hits = clicks; clicks = []
        padNoFocus = []; padNoAuto = []; padPrimary = nil
        let overlay = rulesOpen || creditsOpen || optionsOpen || savePromptOpen
        frameDT = overlay ? 0 : dt
        let d = overlay ? 0 : dt
        switch screen {
        case .title: drawTitle(d)
        case .decks: drawDeckSelect(d)
        case .game: drawGame(d)
        case .builder: drawBuilder(builder, d)
        case .career: drawCareer(d)
        }
        if rulesOpen { clicks.removeAll(); drawRules() }
        else if creditsOpen { clicks.removeAll(); drawCredits() }
        else if savePromptOpen { clicks.removeAll(); drawSavePrompt() }
        else if optionsOpen { clicks.removeAll(); drawOptions() }
        drawPadCursor()
        wheel = 0
    }
    /// Registers a clickable area for this frame (immediate-mode UI).
    func button(_ rect: R, _ action: @escaping () -> Void) { clicks.append((rect, action)) }

    private static let regions: [Renderer.BgRegion] = {
        let d: [[Float]] = [
            [120, 560, 110, 140, 0, 1.0, 4.6, 0.0], [240, 380, 70, 90, 0, 0.8, 5.2, 1.3], [380, 550, 115, 120, 0, 1.0, 4.1, 2.1],
            [590, 420, 80, 90, 0, 0.9, 4.8, 0.7], [900, 560, 160, 170, 0, 1.1, 5.4, 1.8], [1100, 590, 125, 140, 0, 1.0, 4.3, 3.0],
            [1300, 440, 95, 100, 0, 0.9, 5.0, 2.6], [1500, 600, 115, 140, 0, 1.0, 4.5, 0.4], [1680, 440, 80, 90, 0, 0.8, 5.6, 1.1],
            [1760, 600, 115, 140, 0, 1.0, 3.9, 2.4], [480, 930, 200, 130, 0, 1.2, 5.3, 0.9], [1640, 960, 130, 110, 0, 1.0, 3.8, 3.4],
            [115, 320, 70, 90, 1, 1.0, 7.1, 0.3], [235, 260, 55, 70, 1, 0.9, 8.3, 2.2], [390, 370, 75, 90, 1, 1.1, 6.4, 1.0],
            [575, 270, 55, 70, 1, 1.0, 7.7, 2.9], [850, 310, 80, 100, 1, 0.9, 8.9, 0.6], [1080, 190, 85, 130, 1, 1.4, 6.1, 1.7],
            [1100, 380, 75, 95, 1, 1.0, 7.4, 2.5], [1290, 260, 60, 75, 1, 0.9, 8.1, 0.2], [1500, 390, 70, 90, 1, 1.0, 6.8, 1.4],
            [1680, 300, 55, 70, 1, 0.9, 9.2, 3.1], [1750, 390, 70, 85, 1, 1.0, 7.0, 0.8], [470, 720, 95, 105, 1, 1.1, 7.9, 2.0],
            [1660, 760, 80, 95, 1, 1.2, 6.6, 1.2]]
        return d.map { Renderer.BgRegion(reg: SIMD4($0[0] / 1920, $0[1] / 1080, $0[2] / 1920, $0[3] / 1080), mot: SIMD4($0[4], $0[5], $0[6], $0[7])) }
    }()
    private let glints: [SIMD2<Float>] = [SIMD2(605 / 1920, 318 / 1080), SIMD2(1250 / 1920, 382 / 1080)]
    private let candles: [SIMD2<Float>] = [SIMD2(1405 / 1920, 290 / 1080), SIMD2(1850 / 1920, 330 / 1080), SIMD2(1245 / 1920, 1062 / 1080)]
    private var smoothMouse = SIMD2<Float>(0, 0)

    /// Title screen with the animated background.
    private func drawTitle(_ dt: Float) {
        if autotest { autoT += dt; if autoT > 2.5 { autoT = 0; myDeckIndex = Int.random(in: 0..<gameData.decks.count); startGame() } }
        smoothMouse += (mouseNorm - smoothMouse) * min(1, dt * 2.5)
        renderer.titleBackground("img/start_bg.jpg", time: time, mouse: smoothMouse, regions: Scene.regions, glints: glints, candles: candles)
        drawParticles(dt)
        let mid = gameData.language == "pl" ? "WIN" : "WEN"
        let big = Renderer.Font.gwent(146), small = Renderer.Font.gwent(104)
        let wG = renderer.measure("G", big).w, wM = renderer.measure(mid, small).w, wT = renderer.measure("T", big).w
        let total = wG + wM + wT - 24
        var x = 960 - total / 2
        let y: Float = 34
        let w3 = L("The Witcher 3").uppercased()
        renderer.text(w3, .gwent(26), x: 962, y: 16, color: RGBA(r: 0, g: 0, b: 0, a: 0.7), align: .center, shadow: nil)
        renderer.text(w3, .gwent(26), x: 960, y: 14, color: RGBA(r: 0.96, g: 0.85, b: 0.6, a: 0.7), align: .center, shadow: nil)
        for (s, f, dy) in [("G", big, Float(0)), (mid, small, Float(30)), ("T", big, Float(0))] {
            renderer.text(s, f, x: x + 3, y: y + dy + 5, color: RGBA(r: 0, g: 0, b: 0, a: 0.85), shadow: nil)
            renderer.text(s, f, x: x, y: y + dy, color: RGBA(r: 0.96, g: 0.79, b: 0.33, a: 1), shadow: nil)
            renderer.text(s, f, x: x, y: y + dy - 2, color: RGBA(r: 1, g: 0.93, b: 0.68, a: 0.35), shadow: nil)
            x += renderer.measure(s, f).w - 12
        }
        let oy: Float = 206
        renderer.gradient(R(960 - 230, oy, 210, 2), RGBA.goldDark.alpha(0), RGBA.gold)
        renderer.rect(R(960 - 230, oy, 210, 2), RGBA.goldDark.alpha(0.6))
        renderer.rect(R(960 + 20, oy, 210, 2), RGBA.goldDark.alpha(0.6))
        renderer.quad(renderer.white, R(953, oy - 6, 14, 14), color: RGBA.gold, rotation: .pi / 4)
        renderer.quad(renderer.white, R(956, oy - 3, 8, 8), color: RGBA(r: 0.25, g: 0.17, b: 0.05, a: 1), rotation: .pi / 4)
        let b = R(960 - 170, 905, 340, 70)
        padPrimary = b
        goldButton(b, gameData.ui("LET'S PLAY"), font: .gwent(38)) { [weak self] in
            guard let s = self else { return }
            s.audio.play("menu_opening")
            let go: () -> Void = { [weak s] in s?.deckStage = -1; s?.deckSwitchT = 0; s?.screen = .decks }
            let named: () -> Void = { [weak s] in if SaveStore.shared["playerName"] == nil { s?.askPlayerName(then: go) } else { go() } }
            if SaveStore.shared.chosen { named() } else { s.askSaveLocation(then: named) }
        }
        goldButton(R(960 + 200, 917, 220, 46), L("How to play"), font: .serif(20, bold: true)) { [weak self] in self?.openRules() }
        goldButton(R(960 - 420, 917, 220, 46), L("Options"), font: .serif(20, bold: true)) { [weak self] in self?.optionsOpen = true }
        if Platform.isDesktop {
            padNoAuto.append(R(1690, 24, 190, 46))
            goldButton(R(1690, 24, 190, 46), L("Quit game"), font: .serif(19, bold: true)) { Platform.quit() }
        }
        renderer.text("v" + appVersion, .serif(17), x: 1880, y: 1044, color: RGBA(r: 0.91, g: 0.86, b: 0.74, a: 0.6), align: .right)
        languageToggle(y: 995)
    }

    /// A credit line with a clickable name.
    func creditLine(_ plain: String, _ linkText: String, _ url: String, y: Float) {
        let f = Renderer.Font.serif(18), fb = Renderer.Font.serif(18, bold: true)
        let lw = renderer.measure(linkText, fb).w, pw = renderer.measure(plain, f).w
        let x1 = 1880 - lw
        renderer.text(plain, f, x: x1 - pw, y: y, color: RGBA(r: 0.91, g: 0.86, b: 0.74, a: 0.9))
        let b = R(x1, y, lw, 26)
        let hov = b.contains(mouse)
        renderer.text(linkText, fb, x: x1, y: y, color: hov ? .white : RGBA.gold)
        renderer.rect(R(x1, y + 23, lw, 1), RGBA.gold.alpha(hov ? 1 : 0.5))
        padNoFocus.append(b)
        button(b) { if let u = URL(string: url) { Platform.openURL(u) } }
    }
    /// Main gold-framed button.
    func goldButton(_ b: R, _ title: String, font: Renderer.Font = .serif(26, bold: true), enabled: Bool = true, _ action: @escaping () -> Void) {
        let hov = b.contains(mouse) && enabled
        renderer.gradient(b, RGBA(r: 0.19, g: 0.13, b: 0.05, a: 0.95), RGBA(r: 0.05, g: 0.04, b: 0.02, a: 0.96), steps: 12)
        if hov { renderer.rect(b.inset(-6), RGBA(r: 1, g: 0.75, b: 0.3, a: 0.10)) }
        renderer.frame(b, RGBA.goldDark.alpha(enabled ? 1 : 0.4), 2)
        renderer.frame(b.inset(5), RGBA.goldDark.alpha(hov ? 0.95 : 0.55), 1)
        let th = renderer.measure(title, font).h
        renderer.text(title, font, x: b.mid.x, y: b.mid.y - th / 2 + 1, color: enabled ? (hov ? RGBA(r: 1, g: 0.96, b: 0.8, a: 1) : RGBA(r: 0.96, g: 0.86, b: 0.56, a: 1)) : .gray(0.5), align: .center)
        if enabled { button(b, action) }
    }
    /// Language dropdown on the title screen.
    func languageToggle(y: Float) {
        let w: Float = 260, h: Float = 40
        let box = R(960 - w / 2, y, w, h)
        let cur = GameData.languageName(gameData.language)
        renderer.rect(box.inset(-4), RGBA(r: 0.04, g: 0.03, b: 0.01, a: 0.78))
        renderer.frame(box.inset(-4), RGBA.goldDark.alpha(langMenuOpen || box.contains(mouse) ? 0.95 : 0.55), 1.5)
        let th = renderer.measure(cur, .serif(20, bold: true)).h
        renderer.text(cur, .serif(20, bold: true), x: box.x + 18, y: box.mid.y - th / 2, color: RGBA.gold)
        renderer.text(langMenuOpen ? "▴" : "▾", .ui(20, bold: true), x: box.x + box.w - 18, y: box.mid.y - th / 2, color: RGBA.gold, align: .right)
        if !langMenuOpen { button(box) { [weak self] in self?.langMenuOpen = true }; return }
        button(R(0, 0, virtualWidth, virtualHeight)) { [weak self] in self?.langMenuOpen = false }
        let ih: Float = 36
        let list = GameData.languages
        let lb = R(box.x - 4, box.y - 8 - Float(list.count) * ih, box.w + 8, Float(list.count) * ih + 4)
        renderer.rect(lb, RGBA(r: 0.05, g: 0.04, b: 0.02, a: 0.97)); renderer.frame(lb, RGBA.goldDark, 1.5)
        for (i, l) in list.enumerated() {
            let ir = R(lb.x + 2, lb.y + 2 + Float(i) * ih, lb.w - 4, ih)
            let on = l.code == gameData.language, hov = ir.contains(mouse)
            if on { renderer.gradient(ir, RGBA(r: 0.95, g: 0.82, b: 0.49, a: 1), RGBA(r: 0.79, g: 0.59, b: 0.18, a: 1), steps: 6) }
            else if hov { renderer.rect(ir, RGBA.gold.alpha(0.18)) }
            let ty = ir.mid.y - renderer.measure(l.name, .serif(19, bold: true)).h / 2
            renderer.text(l.name, .serif(19, bold: true), x: ir.x + 16, y: ty, color: on ? RGBA(r: 0.1, g: 0.07, b: 0.02, a: 1) : (hov ? .white : .gray(0.85)), shadow: on ? nil : RGBA.black.alpha(0.8))
            if !gameData.hasTranslation(l.code) { renderer.text("EN", .ui(12, bold: true), x: ir.x + ir.w - 14, y: ir.mid.y - 8, color: on ? RGBA(r: 0.2, g: 0.14, b: 0.04, a: 1) : .gray(0.5), align: .right, shadow: nil) }
            button(ir) { [weak self] in self?.setLanguage(l.code); self?.langMenuOpen = false }
        }
    }
    /// Changes the game language.
    func setLanguage(_ code: String) { gameData.language = code; onLanguageChange?(code) }

    /// Creates the soft glow texture used by effects.
    private func makeGlow() -> MTLTexture {
        let n = 64
        let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 1), CGColor(red: 1, green: 1, blue: 1, alpha: 0.45), CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray, locations: [0, 0.35, 1])!
        ctx.drawRadialGradient(grad, startCenter: CGPoint(x: n / 2, y: n / 2), startRadius: 0, endCenter: CGPoint(x: n / 2, y: n / 2), endRadius: CGFloat(n / 2), options: [])
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: n, height: n, mipmapped: false)
        let t = renderer.device.makeTexture(descriptor: td)!
        let src = ctx.data!.bindMemory(to: UInt8.self, capacity: n * n * 4)
        var px = [UInt8](repeating: 255, count: n * n * 4)
        for i in 0..<(n * n) { px[i * 4 + 3] = src[i * 4 + 3] }
        t.replace(region: MTLRegionMake2D(0, 0, n, n), mipmapLevel: 0, withBytes: px, bytesPerRow: n * 4)
        return t
    }
    /// Creates a background particle.
    private func spawn(_ ember: Bool, initial: Bool) -> Particle {
        var p: Particle
        if !ember {
            p = Particle(p: SIMD2(Float.random(in: 0...1920), Float.random(in: 0...970)), v: SIMD2(Float.random(in: -4...4), Float.random(in: -4.5...2)),
                         life: 0, max: Float.random(in: 8...18), size: Float.random(in: 2...7), a: Float.random(in: 0.12...0.37), ember: false, depth: Float.random(in: 0.3...1.3))
        } else {
            let o = Bool.random() ? [SIMD2<Float>(1405, 290), SIMD2(1850, 330), SIMD2(1245, 1062)].randomElement()! : [SIMD2<Float>(605, 318), SIMD2(1250, 382)].randomElement()!
            p = Particle(p: o + SIMD2(Float.random(in: -28...28), Float.random(in: -20...0)), v: SIMD2(Float.random(in: -10...10), Float.random(in: -55...(-20))),
                         life: 0, max: Float.random(in: 1.8...4), size: Float.random(in: 1.5...4), a: Float.random(in: 0.5...1), ember: true, depth: 1.2)
        }
        if initial { p.life = Float.random(in: 0...p.max) }
        return p
    }
    /// Updates and draws the background particles.
    private func drawParticles(_ dt: Float) {
        for i in particles.indices {
            var p = particles[i]
            p.life += dt
            if p.life > p.max { p = spawn(p.ember, initial: false) }
            if p.ember { p.v.x += sin(time * 2 + Float(i)) * 0.6 }
            p.p += (p.v + SIMD2(sin(time * 0.3 + Float(i)) * 1.5, 0)) * dt
            particles[i] = p
            let fade = sin(Float.pi * min(1, p.life / p.max))
            let a = p.a * fade * (p.ember ? (0.7 + 0.3 * sin(time * 17 + Float(i) * 3)) : 1)
            let s = p.size * 2.4 * (p.ember ? 1 : p.depth)
            let pos = p.p - smoothMouse * p.depth * SIMD2(8, 6)
            let col = p.ember ? RGBA(r: 1, g: 0.6, b: 0.25, a: a) : RGBA(r: 1, g: 0.93, b: 0.8, a: a)
            renderer.quad(glow, R(pos.x - s / 2, pos.y - s / 2, s, s), color: col)
        }
    }

    /// Dimmed menu background used by secondary screens.
    func drawMenuBackground(_ dt: Float, dim: Float) {
        smoothMouse += (mouseNorm - smoothMouse) * min(1, dt * 2.5)
        renderer.titleBackground("img/start_bg.jpg", time: time, mouse: smoothMouse * 0.5, regions: Scene.regions, glints: glints, candles: candles)
        renderer.rect(R(0, 0, virtualWidth, virtualHeight), RGBA(r: 0.02, g: 0.015, b: 0.01, a: dim))
        drawParticles(dt)
    }

    /// Starts a match with the given decks (random opponent deck if none).
    func startGame(with deck: DeckData? = nil, against: DeckData? = nil, careerFight cf: Int? = nil) {
        let decks = gameData.decks
        if autotest { myDeckIndex = Int.random(in: 0..<decks.count) }
        let all = allDecks
        let mine = deck ?? all[min(myDeckIndex, all.count - 1)]
        let others = decks.indices.filter { $0 != myDeckIndex }
        let theirs = against ?? decks[others.randomElement() ?? 0]
        careerFight = cf
        if cf == nil { careerFightName = nil }
        game = Game(myDeck: mine, opDeck: theirs)
        game?.aiLevel = cf != nil ? max(0, Career.shared.difficulty - 1) : aiLevel
        game?.autoHuman = autotest
        game?.showChoices = ProcessInfo.processInfo.environment["GWENT_SHOWCHOICES"] == "1"
        /// Total unit strength and card count of a deck (used in test logs).
        func power(_ d: DeckData) -> (Int, Int) { d.cards.reduce((0, 0)) { acc, e in let c = gameData.cards[e.0]; return (acc.0 + (c?.strength ?? 0) * e.1, acc.1 + e.1) } }
        let pm = power(mine), po = power(theirs)
        log("GAME \(gamesPlayed + 1): \(mine.faction) power \(pm.0) / \(pm.1) cards vs \(theirs.faction) power \(po.0) / \(po.1) cards, AI level \(game?.aiLevel ?? -1)")
        selected = nil; notes = []; noteT = 0; aiT = 0
        screen = .game
        audio.play("game_start")
    }

    /// Board background.
    private func drawModernBoard(_ g: Game) {
        renderer.image("img/board.jpg", R(0, 0, virtualWidth, virtualHeight))
        renderer.gradient(R(0, virtualHeight - 120, virtualWidth, 120), RGBA.black.alpha(0), RGBA.black.alpha(0.35), steps: 8)
    }

    /// Screen rectangle of a player's row.
    private func rowRect(_ p: Player, _ t: RowType) -> R {
        let mine = p === game?.human
        let y: Float = mine ? [422, 555, 688][t.rawValue] : [271, 138, 5][t.rawValue]
        return R(710, y, 803, 133)
    }
    /// Special card slot of a row.
    private func specialRect(_ p: Player, _ t: RowType) -> R { let rr = rowRect(p, t); return R(579, rr.y + 9, cardWidth, cardHeight) }
    private let handRect = R(580, 843, 932, 128)
    private let weatherRect = R(141, 448, 279, 138)
    /// Position of a player's deck.
    private func deckRect(_ p: Player) -> R { p === game?.human ? R(1735, 836, cardWidth, 128) : R(1735, 80, cardWidth, 128) }
    /// Position of a player's graveyard.
    private func graveRect(_ p: Player) -> R { p === game?.human ? R(1556, 836, cardWidth, cardHeight) : R(1556, 80, cardWidth, cardHeight) }
    /// Position of a player's leader card.
    private func leaderRect(_ p: Player) -> R { p === game?.human ? R(142, 835, 96, 132) : R(142, 83, 96, 132) }

    /// Positions for `n` cards spread across an area.
    private func layout(_ n: Int, in area: R, w: Float = cardWidth, gap: Float = 4) -> [SIMD2<Float>] {
        guard n > 0 else { return [] }
        let full = Float(n) * w + Float(n - 1) * gap
        var step = w + gap
        if full > area.w { step = (area.w - w) / Float(max(1, n - 1)) }
        let used = step * Float(n - 1) + w
        let x0 = area.x + (area.w - used) / 2
        return (0..<n).map { SIMD2(x0 + Float($0) * step, area.y) }
    }
    /// Animates a card towards its target position.
    private func move(_ c: Card, to p: SIMD2<Float>, from spawn: SIMD2<Float>, dt: Float) {
        if !c.hasPos { c.pos = spawn; c.hasPos = true }
        c.pos += (p - c.pos) * min(1, dt * 11)
        c.flash = max(0, c.flash - dt * 1.6)
    }

    /// Overlay image for the weather on a row.
    private func weatherOverlay(_ w: Set<String>) -> String? {
        if w.contains("frost") || w.contains("white_frost") { return "overlay_frost" }
        if w.contains("spider_web") { return "overlay_spider_web" }
        if w.contains("fog") { return "overlay_fog" }
        if w.contains("tse_tse") { return "overlay_tse_tse" }
        if w.contains("sandstorm") { return "overlay_sandstorm" }
        if w.contains("dragon_wrath") { return "overlay_dragon_wrath" }
        if w.contains("rain") || w.contains("storm") { return "overlay_rain" }
        return nil
    }
    /// Whether a special card needs no target.
    private func isFreeSpecial(_ c: Card) -> Bool {
        if c.data.isWeather { return true }
        guard c.data.isSpecial else { return false }
        return !["horn", "mardroeme", "morale", "toussaint_wine", "shield", "shield_c", "shield_r", "shield_s", "door", "decoy", "lock", "knockback", "curse"].contains(c.specialKind ?? "")
    }
    /// Game board: rows, hand, player panels, buttons and choices.
    private func drawGame(_ dt: Float) {
        guard let g = game else { return }
        processEvents(g, dt)
        drawModernBoard(g)
        hover = nil
        let canAct = g.phase == .play && g.current === g.human && !g.busy && g.choice == nil
        if !canAct && g.choice == nil { selected = nil }
        for p in [g.computer, g.human] {
            let band = p === g.human ? R(0, 666, 450, 135) : R(0, 263, 450, 135)
            if g.current === p && g.phase == .play {
                renderer.gradient(band, RGBA(r: 0.5, g: 0.38, b: 0.12, a: 0.0), RGBA(r: 0.85, g: 0.62, b: 0.2, a: 0.22), steps: 8)
                renderer.rect(R(band.x, p === g.human ? band.y : band.y + band.h - 3, band.w, 3), RGBA.gold.alpha(0.8))
            }
        }
        var targetRows: [(Player, RowType)] = []
        var decoyTargets: [Card] = []
        var rowChoice: [(Player, RowType)] = []
        if let ch = g.choice, case .rows(let rs) = ch.kind { rowChoice = rs }
        if canAct, let s = selected {
            if s.isUnit { targetRows = g.validRows(for: s, by: g.human).map { ((s.has("spy") || s.has("emissary") || s.has("ofiri_envoy")) ? g.computer : g.human, $0) } }
            else {
                switch s.specialKind ?? "" {
                case "decoy": decoyTargets = g.decoyTargets(for: g.human)
                case "lock", "knockback": targetRows = g.enemyRowTargets(for: s, by: g.human).map { (g.computer, $0) }
                case "curse": targetRows = g.curseRows(by: g.human)
                default: targetRows = g.validRows(for: s, by: g.human).map { (g.human, $0) }
                }
            }
        }
        for p in [g.computer, g.human] {
            for t in RowType.allCases {
                let rr = rowRect(p, t)
                let row = p.row(t)
                if let ov = weatherOverlay(p.weather[t.rawValue]) { renderer.image("img/icons/\(ov).png", R(567, rr.y + 6, 950, 127), color: .white.alpha(0.7 + 0.15 * sin(time * 1.3 + Float(t.rawValue)))) }
                drawWeatherFX(p.weather[t.rawValue], rr)
                let full = R(567, rr.y + 2, 946, rr.h - 4)
                let isTarget = targetRows.contains { $0.0 === p && $0.1 == t }
                let isChoice = rowChoice.firstIndex { $0.0 === p && $0.1 == t }
                if isTarget || isChoice != nil {
                    let pulse = 0.18 + 0.1 * sin(time * 5)
                    renderer.rect(full, RGBA(r: 1, g: 0.8, b: 0.3, a: pulse)); renderer.frame(full, RGBA.gold, 2)
                    if let s = selected, isTarget { button(full) { [weak self] in self?.playSelected(s, row: t, rowOwner: p) } }
                    if let i = isChoice { button(full) { g.resolveChoice([i]) } }
                }
                var mx: Float = 712
                for (flag, icon) in [(row.lock != nil, "power_lock"), (row.curse != nil, "power_curse"), (row.door, "power_door"), (row.leaderHorn, "power_horn")] where flag {
                    renderer.image("img/icons/\(icon).png", R(mx, rr.y + 92, 36, 36)); mx += 38
                }
                let ps = layout(row.cards.count, in: R(rr.x + 4, rr.y + 5, rr.w - 8, cardHeight))
                for (i, c) in row.cards.enumerated() {
                    move(c, to: ps[i], from: p === g.human ? SIMD2(1000, 1000) : SIMD2(1000, -150), dt: dt)
                    let cr = R(c.pos.x, c.pos.y, cardWidth, cardHeight)
                    let isDecoy = decoyTargets.contains { $0 === c }
                    let (fr, flying) = flightRect(c, target: ps[i])
                    if flying { renderer.rect(R(fr.x + 10, fr.y + 16, fr.w, fr.h), RGBA.black.alpha(0.35)) }
                    drawCard(c, flying ? fr : cr, highlight: isDecoy)
                    if c.locked { renderer.image("img/icons/power_lock.png", R(cr.x + 50, cr.y + 4, 32, 32)) }
                    if cr.contains(mouse) { hover = c }
                    if isDecoy, let s = selected { button(cr) { [weak self] in self?.playSelected(s, target: c) } }
                }
                let sp = specialRect(p, t)
                for (i, s) in row.specials.enumerated() {
                    move(s, to: SIMD2(sp.x + Float(i) * 14, sp.y), from: SIMD2(1000, 1000), dt: dt)
                    let cr = R(s.pos.x, s.pos.y, cardWidth, cardHeight)
                    drawCard(s, cr)
                    if cr.contains(mouse) { hover = s }
                }
                let sc = "\(row.total)"
                let disc = Renderer.Font.ui(78)
                let dh = renderer.measure("●", disc).h
                renderer.text("●", disc, x: 534, y: rr.y + 70 - dh / 2, color: RGBA.goldDark.alpha(0.9), align: .center, shadow: nil)
                renderer.text("●", .ui(70), x: 534, y: rr.y + 70 - renderer.measure("●", .ui(70)).h / 2, color: RGBA(r: 0.06, g: 0.05, b: 0.04, a: 1), align: .center, shadow: nil)
                let th = renderer.measure(sc, .ui(28, bold: true)).h
                renderer.text(sc, .ui(28, bold: true), x: 534, y: rr.y + 70 - th / 2, color: RGBA(r: 1, g: 0.9, b: 0.65, a: 1), align: .center, shadow: nil)
            }
        }
        let wps = layout(g.weatherCards.count, in: R(weatherRect.x + 8, weatherRect.y + 8, weatherRect.w - 16, cardHeight))
        for (i, c) in g.weatherCards.enumerated() {
            move(c, to: wps[i], from: SIMD2(1000, 1000), dt: dt)
            let cr = R(c.pos.x, c.pos.y, cardWidth, cardHeight)
            drawCard(c, cr)
            if cr.contains(mouse) { hover = c }
        }
        if canAct, let s = selected, isFreeSpecial(s) {
            let pulse = 0.18 + 0.1 * sin(time * 5)
            renderer.rect(weatherRect, RGBA(r: 1, g: 0.8, b: 0.3, a: pulse)); renderer.frame(weatherRect, RGBA.gold, 2)
            button(weatherRect) { [weak self] in self?.playSelected(s) }
            button(R(567, 5, 946, 816)) { [weak self] in self?.playSelected(s) }
        }
        for p in [g.computer, g.human] { drawStats(p, g, canAct: canAct) }
        smallButton(R(1540, 16, 190, 46), L("Rules"), enabled: true) { [weak self] in self?.openRules() }
        for c in g.computer.hand { c.hasPos = true; c.pos = SIMD2(1000, -160) }
        for p in [g.human, g.computer] { let d = deckRect(p); for c in p.deck { c.pos = SIMD2(d.x, d.y); c.hasPos = true } }
        let hp = layout(g.human.hand.count, in: R(handRect.x + 8, handRect.y + 6, handRect.w - 16, cardHeight), gap: 3)
        var hoveredHand: Card?
        for (i, c) in g.human.hand.enumerated().reversed() where hoveredHand == nil {
            if R(hp[i].x, hp[i].y - c.lift, cardWidth, cardHeight).contains(mouse) && g.phase == .play && g.choice == nil { hoveredHand = c }
        }
        let forced = g.human.forcedCard
        for (i, c) in g.human.hand.enumerated() {
            let want: Float = (selected === c ? 26 : (hoveredHand === c ? 14 : 0))
            c.lift += (want - c.lift) * min(1, dt * 14)
            move(c, to: hp[i], from: SIMD2(deckRect(g.human).x, deckRect(g.human).y), dt: dt)
            let cr = R(c.pos.x, c.pos.y - c.lift, cardWidth, cardHeight)
            drawCard(c, cr, highlight: selected === c || forced === c, dim: canAct && forced != nil && forced !== c)
            if i == 0 && canAct { padPrimary = cr }
            if hoveredHand === c { hover = c }
            if canAct { button(cr) { [weak self] in self?.clickHand(c) } }
        }
        for (i, (sym, act)) in [("♫", { [weak self] in self?.audio.musicOn.toggle() } as () -> Void), ("⏭", { [weak self] in self?.audio.skipTrack() })].enumerated() {
            let b = R(1570 + Float(i) * 52, 1018, 46, 46)
            padNoAuto.append(b)
            let on = i == 1 || audio.musicOn
            let hov = b.contains(mouse)
            renderer.rect(b, RGBA(r: 0.03, g: 0.03, b: 0.04, a: hov ? 0.9 : 0.7)); renderer.frame(b, RGBA.goldDark.alpha(hov ? 0.9 : 0.45), 1)
            renderer.text(sym, .ui(24, bold: true), x: b.mid.x, y: b.y + 8, color: hov ? .white : RGBA(r: 0.93, g: 0.76, b: 0.35, a: on ? 1 : 0.35), align: .center)
            button(b, act)
        }
        exitConfirmT = max(0, exitConfirmT - dt)
        padNoAuto.append(R(1680, 1018, 180, 46))
        smallButton(R(1680, 1018, 180, 46), exitConfirmT > 0 ? L("Are you sure?") : L("Exit to menu"), enabled: true) { [weak self] in
            guard let s = self else { return }
            if s.exitConfirmT > 0 { s.exitConfirmT = 0; s.game = nil; s.screen = .title } else { s.exitConfirmT = 3 }
        }
        smallButton(R(292, 848, 150, 50), L("Pass"), enabled: canAct) { [weak self] in self?.selected = nil; self?.game?.humanPass() }
        padNoAuto.append(R(292, 944, 150, 50))
        smallButton(R(292, 944, 150, 50), L("Give up"), enabled: g.phase != .over) { [weak self] in self?.game?.surrender() }
        drawFX(dt)
        if let h = hover ?? selected { drawPreview(h) }
        if g.phase == .redraw && g.choice == nil { drawRedraw(g) }
        if let ch = g.choice { drawChoice(ch, g) }
        drawNotes(dt)
        if g.phase == .over && notes.isEmpty { drawEnd(g) }
        let coinShown = fxList.contains { if case .coin = $0.kind { return true }; return false }
        if g.phase == .play && !g.busy && g.choice == nil && notes.isEmpty && !coinShown && !rulesOpen {
            aiT += dt
            let delay: Float = autotest ? 0.35 : 0.85
            if aiT > delay {
                aiT = 0
                if g.current === g.computer {
                    if autotest { if let m = g.aiDecide(for: g.computer) { log("  Player 2: \(m.card?.key ?? (m.kind == .leader ? "LEADER \(g.computer.leaderAbility)" : "FACTION"))\(m.row.map { " -> \($0)" } ?? "")  [\(g.human.total):\(g.computer.total)]") } else { log("  Player 2: pass  [\(g.human.total):\(g.computer.total)]") } }
                    Task { @MainActor in await g.aiTurn(g.computer) }
                }
                else if autotest && g.current === g.human {
                    if let m = g.aiDecide(for: g.human) { log("  Player 1: \(m.card?.key ?? (m.kind == .leader ? "LEADER \(g.human.leaderAbility)" : "FACTION"))\(m.row.map { " -> \($0)" } ?? "")  [\(g.human.total):\(g.computer.total)]") }
                    else { log("  Player 1: pass  [\(g.human.total):\(g.computer.total)]") }
                    Task { @MainActor in await g.aiTurn(g.human) }
                }
            }
        } else { aiT = 0 }
        if autotest { autoTest(g, dt) }
    }

    private var watchdog: Float = 0
    private var lastSig = ""
    /// Automatic play used by tests (GWENT_AUTOTEST).
    private func autoTest(_ g: Game, _ dt: Float) {
        autoT += dt
        let sig = "\(g.turn)|\(g.round)|\(g.human.hand.count)|\(g.computer.hand.count)|\(g.phase)|\(g.human.total)|\(g.computer.total)"
        if sig != lastSig { lastSig = sig; watchdog = 0 } else { watchdog += dt }
        if watchdog > 25 {
            log("HANG: phase \(g.phase), turn \(g.current === g.human ? "Player 1" : "Player 2"), busy \(g.busy), choice: \(g.choice?.title ?? "none"), leaders \(g.human.leaderAbility)/\(g.computer.leaderAbility)")
            watchdog = 0; gamesPlayed += 1; startGame(); return
        }
        if g.phase == .redraw && autoT > 1 { autoT = 0; g.finishRedraw() }
        if g.phase == .over && notes.isEmpty && autoT > 2 {
            autoT = 0; gamesPlayed += 1
            log("END: rounds \(g.history.map { "\($0.human):\($0.computer)" }.joined(separator: ", ")) winner: \(g.winner === g.human ? "Player 1" : (g.winner === g.computer ? "Player 2" : "draw"))")
            startGame()
        }
    }

    /// Smaller gold button that shrinks its font to fit.
    func smallButton(_ b: R, _ title: String, enabled: Bool, _ action: @escaping () -> Void) {
        var f = Renderer.Font.serif(21, bold: true)
        while renderer.measure(title, f).w > b.w - 18 && f.size > 11 { f = .serif(f.size - 1, bold: true) }
        goldButton(b, title, font: f, enabled: enabled, action)
    }

    /// Player panel: name, faction, lives, card count and leader.
    private func drawStats(_ p: Player, _ g: Game, canAct: Bool) {
        let mine = p === g.human
        let oy: Float = mine ? 666 : 263
        renderer.image("img/icons/profile.png", R(128, oy + 13, 99, 108))
        renderer.image("img/icons/icon_player_border.png", R(118, oy + 7, 116, 127))
        let shield = R(106, mine ? 748 : 270, 50, 55)
        renderer.image("img/icons/deck_shield_\(p.faction).png", shield)
        if shield.contains(mouse) { hoverText = gameData.factionName(p.faction) + "\n" + gameData.factionDesc(p.faction) }
        let nameY: Float = mine ? 728 : 271
        renderer.text(mine ? playerName : (careerFightName ?? L("Player 2")), .gwent(24), x: 239, y: nameY, color: RGBA(r: 0.96, g: 0.85, b: 0.56, a: 1))
        renderer.text(gameData.factionName(p.faction), .ui(17), x: 239, y: nameY + 27, color: .gray(0.85), maxWidth: 190)
        let hcY: Float = mine ? 680 : 356
        renderer.image("img/icons/icon_card_count.png", R(240, hcY + 4, 30, 32))
        renderer.text("\(p.hand.count)", .ui(30, bold: true), x: 274, y: hcY, color: RGBA(r: 0.93, g: 0.72, b: 0.2, a: 1))
        let gy: Float = mine ? 678 : 352
        renderer.image("img/icons/icon_gem_\(p.gems >= 1 ? "on" : "off").png", R(319, gy, 41, 42))
        renderer.image("img/icons/icon_gem_\(p.gems >= 2 ? "on" : "off").png", R(360, gy, 41, 42))
        let st = R(427, mine ? 708 : 305, 54, 54)
        renderer.image("img/icons/score_total_\(mine ? "me" : "op").png", st)
        if p.total > p.opponent.total { renderer.image("img/icons/icon_high_score.png", R(st.x - 14, st.y - 12, 82, 78)) }
        let th = renderer.measure("\(p.total)", .ui(30, bold: true)).h
        renderer.text("\(p.total)", .ui(30, bold: true), x: st.mid.x, y: st.mid.y - th / 2, color: .black, align: .center, shadow: RGBA.white.alpha(0.5))
        if p.passed { renderer.text(L("Passed"), .ui(24, bold: true), x: 330, y: mine ? 640 : 410, color: RGBA(r: 0.93, g: 0.72, b: 0.2, a: 1), align: .center) }
        let lr = leaderRect(p)
        p.leader.pos = SIMD2(lr.x, lr.y); p.leader.hasPos = true
        let avail = g.leaderAvailable(p)
        drawCard(p.leader, lr, dim: !avail && !Game.passiveLeaders.contains(p.leaderAbility))
        renderer.image("img/icons/icon_leader_active.png", R(260, lr.y + 51, 38, 38), color: .white.alpha(avail ? 1 : 0.25))
        if lr.contains(mouse) { hover = p.leader }
        if mine && canAct && avail {
            if lr.contains(mouse) { renderer.frame(lr.inset(-3), RGBA.gold, 3) }
            button(lr) { [weak self] in self?.game?.humanLeader() }
            button(R(260, lr.y + 51, 38, 38)) { [weak self] in self?.game?.humanLeader() }
        }
        if mine, let f = g.factionActive(p) {
            let b = R(160, 612, 150, 34)
            let title = f == "transform" ? L("Transform") : (f.hasPrefix("skip") ? L("Skip turn") : L("Faction ability"))
            smallButton(b, title, enabled: canAct) { [weak self] in self?.game?.humanFaction() }
        }
        let dr = deckRect(p)
        let n = p.deck.count
        for i in 0..<min(4, n) { renderer.image("img/icons/deck_back_\(p.faction).jpg", R(dr.x - Float(i), dr.y - Float(i), dr.w, dr.h)) }
        if n > 0 {
            renderer.rect(R(dr.mid.x - 22, dr.y + dr.h - 40, 44, 30), RGBA.black.alpha(0.6))
            renderer.text("\(n)", .ui(22, bold: true), x: dr.mid.x, y: dr.y + dr.h - 38, color: .white, align: .center)
        }
        let gr = graveRect(p)
        for c in p.grave { move(c, to: SIMD2(gr.x, gr.y), from: SIMD2(gr.x, gr.y), dt: 1 / 60) }
        if let top = p.grave.last {
            drawCard(top, R(top.pos.x, top.pos.y, cardWidth, cardHeight))
            if R(top.pos.x, top.pos.y, cardWidth, cardHeight).contains(mouse) { hover = top }
        }
    }

    /// Icon file for an ability.
    private func abilityIcon(_ a: String) -> String {
        var s = a
        if s == "cerys" { s = "muster" }
        if s.hasPrefix("avenger") { s = "avenger" }
        if ["scorch_c", "scorch_r", "scorch_s"].contains(s) { s = "scorch_combat" }
        if ["shield_c", "shield_r", "shield_s"].contains(s) { s = "shield" }
        return "img/icons/card_ability_\(s).png"
    }
    /// Power badge image of a card.
    private func powerBadge(_ c: Card) -> String {
        if c.hero { return "img/icons/power_hero.png" }
        if c.data.isSpecial || c.data.isWeather {
            var s = c.data.abilities.first ?? "normal"
            if ["shield_c", "shield_r", "shield_s"].contains(s) { s = "shield" }
            return "img/icons/power_\(s).png"
        }
        return "img/icons/power_normal.png"
    }
    /// Draws a small card with power, row and ability icons.
    func drawCard(_ c: Card, _ cr: R, highlight: Bool = false, dim: Bool = false) {
        let s = cr.w / cardWidth
        renderer.imageCover(c.data.image, cr, color: dim ? .gray(0.45) : .white)
        if c.flash > 0 { renderer.rect(cr, RGBA(r: 1, g: 0.9, b: 0.6, a: c.flash * 0.35)) }
        if c.data.isLeader { if highlight { renderer.frame(cr.inset(-3), RGBA.gold, 3) }; return }
        renderer.image(powerBadge(c), R(cr.x - 3 * s, cr.y - 5 * s, 60 * s, 61 * s))
        if c.data.isUnit {
            let v = c.power
            let col: RGBA = c.hero ? .white : (v > c.basePower ? RGBA(r: 0.1, g: 0.55, b: 0.1, a: 1) : (v < c.basePower ? RGBA(r: 0.75, g: 0.1, b: 0.1, a: 1) : .black))
            let cx: Float = 16.3, cy: Float = 14.6
            var pop: Float = 0
            if let seen = powerSeen[c.id] { pop = seen.0 != v ? 0.45 : max(0, seen.1 - frameDT) }
            powerSeen[c.id] = (v, pop)
            let f = Renderer.Font.ui((c.hero ? 21 : 19) * s * (1 + pop * 1.1), bold: true)
            let th = renderer.measure("\(v)", f).h
            if pop > 0 { renderer.quad(glowTex, R(cr.x + cx * s - 22 * s, cr.y + cy * s - 22 * s, 44 * s, 44 * s), color: RGBA(r: 1, g: 0.9, b: 0.5, a: pop * 1.6)) }
            renderer.text("\(v)", f, x: cr.x + cx * s, y: cr.y + cy * s - th / 2, color: col, align: .center, shadow: nil)
            let rowName = c.data.row.hasPrefix("agile") ? c.data.row : c.data.row
            renderer.image("img/icons/card_row_\(rowName).png", R(cr.x + 56 * s, cr.y + 91 * s, 28 * s, 27 * s))
            let abis = c.data.abilities.filter { $0 != "hero" }
            if let a = abis.last { renderer.image(abilityIcon(a), R(cr.x + 28 * s, cr.y + 91 * s, 28 * s, 27 * s)) }
            else if c.data.row.hasPrefix("agile") { renderer.image("img/icons/card_ability_agile.png", R(cr.x + 28 * s, cr.y + 91 * s, 28 * s, 27 * s)) }
            if abis.count > 1 { renderer.image(abilityIcon(abis[abis.count - 2]), R(cr.x + 0 * s, cr.y + 91 * s, 28 * s, 27 * s)) }
        }
        if highlight { renderer.frame(cr.inset(-3), RGBA.gold, 3) }
    }
    private var largeCache: [String: Card] = [:]
    /// Draws a large card with its name and quote.
    func drawCardLarge(_ c: Card, _ cr: R, cache: String = "") {
        renderer.imageCover(c.data.image, cr)
        let bh = cr.h * 0.26
        let br = R(cr.x, cr.y + cr.h - bh, cr.w, bh)
        renderer.gradient(br, RGBA(r: 0.95, g: 0.91, b: 0.82, a: 1), RGBA(r: 0.84, g: 0.77, b: 0.63, a: 1), steps: 10)
        renderer.rect(R(br.x, br.y, br.w, max(1.5, cr.w * 0.008)), RGBA(r: 0.55, g: 0.42, b: 0.2, a: 1))
        let nf = Renderer.Font.serif(max(10, cr.w * 0.078), bold: true)
        let nh = renderer.text(gameData.cardName(c.data), nf, x: br.mid.x, y: br.y + bh * 0.08, color: RGBA(r: 0.22, g: 0.15, b: 0.06, a: 1), maxWidth: br.w - cr.w * 0.08, align: .center, shadow: nil).h
        let q = gameData.cardQuote(c.data)
        if !q.isEmpty && cr.w >= 150 {
            renderer.text(q, .serif(max(9, cr.w * 0.053), italic: true), x: br.mid.x, y: br.y + bh * 0.06 + nh, color: RGBA(r: 0.13, g: 0.09, b: 0.04, a: 1), maxWidth: br.w - cr.w * 0.1, align: .center, shadow: nil)
        }
        if c.data.isLeader { return }
        let s = cr.w / cardWidth * 0.5
        renderer.image(powerBadge(c), R(cr.x - 3 * s, cr.y - 5 * s, 60 * s, 61 * s))
        if c.data.isUnit {
            let cx: Float = 16.3, cy: Float = 14.6
            let f = Renderer.Font.ui((c.hero ? 21 : 19) * s, bold: true)
            let th = renderer.measure("\(c.basePower)", f).h
            renderer.text("\(c.basePower)", f, x: cr.x + cx * s, y: cr.y + cy * s - th / 2, color: c.hero ? .white : .black, align: .center, shadow: nil)
            renderer.image("img/icons/card_row_\(c.data.row).png", R(cr.x - 3 * s + 6 * s, cr.y + 58 * s, 44 * s, 42 * s))
            if let a = c.data.abilities.filter({ $0 != "hero" }).last { renderer.image(abilityIcon(a), R(cr.x + 3 * s, cr.y + 102 * s, 44 * s, 42 * s)) }
        }
    }
    /// Card preview with the ability description.
    func drawPreview(_ c: Card) {
        let cr = R(1538, 232, 330, 474)
        renderer.rect(cr.inset(-6), RGBA.black.alpha(0.55))
        drawCardLarge(c, cr)
        var lines: [(String, String)] = []
        if c.data.isLeader { if let a = c.data.abilities.last { lines.append((L("Leader Ability"), gameData.abilityDesc(a))) } }
        else {
            if c.data.row.hasPrefix("agile") { lines.append((gameData.abilityName("agile"), gameData.abilityDesc("agile"))) }
            for a in c.data.abilities where a != "hero" { lines.append((gameData.abilityName(a), gameData.abilityDesc(a))) }
            if c.hero { lines.append((L("Hero"), gameData.abilityDesc("hero"))) }
        }
        guard !lines.isEmpty else { return }
        var y: Float = 720
        let box = R(1528, 714, 350, 360)
        var h: Float = 12
        for (n, d) in lines { h += renderer.measure(n, .serif(19, bold: true), maxWidth: 326).h + renderer.measure(d, .ui(16), maxWidth: 326).h + 10 }
        renderer.rect(R(box.x, box.y, box.w, min(box.h, h)), RGBA(r: 0.06, g: 0.05, b: 0.03, a: 0.92))
        renderer.frame(R(box.x, box.y, box.w, min(box.h, h)), RGBA.goldDark.alpha(0.6), 1)
        for (n, d) in lines {
            if y > 1050 { break }
            y += renderer.text(n, .serif(19, bold: true), x: box.x + 12, y: y, color: RGBA.gold, maxWidth: 326).h
            y += renderer.text(d, .ui(16), x: box.x + 12, y: y, color: .gray(0.92), maxWidth: 326).h + 10
        }
    }

    /// Selects or plays a card from the hand.
    private func clickHand(_ c: Card) {
        guard let g = game, g.phase == .play, g.current === g.human, !g.busy, g.choice == nil else { return }
        if let f = g.human.forcedCard, f !== c { notes.append((L("You must play the marked card."), nil)); return }
        if selected === c {
            if isFreeSpecial(c) { playSelected(c); return }
            if c.isUnit, g.validRows(for: c, by: g.human).count == 1 { playSelected(c, row: g.validRows(for: c, by: g.human)[0]); return }
            if !c.isUnit, ["lock", "knockback"].contains(c.specialKind ?? "") == false, c.specialKind != "decoy", c.specialKind != "curse", g.validRows(for: c, by: g.human).count == 1 {
                playSelected(c, row: g.validRows(for: c, by: g.human)[0], rowOwner: g.human); return
            }
            selected = nil
            return
        }
        selected = c
        audio.play("card", volume: 0.5)
    }
    /// Plays the selected card on a row or target.
    private func playSelected(_ c: Card, row: RowType? = nil, rowOwner: Player? = nil, target: Card? = nil) {
        guard let g = game else { return }
        selected = nil
        g.humanPlay(c, row: row, rowOwner: rowOwner, target: target)
    }

    /// Turns engine events into notifications, sounds and effects.
    private func processEvents(_ g: Game, _ dt: Float) {
        for e in g.events {
            switch e {
            case .notify(let t, let icon): notes.append((t, icon)); if notes.count > 4 { notes.removeFirst(notes.count - 4) }
            case .sound(let s): audio.play(s)
            case .flash(let c): c.flash = 1
            case .anim, .burn, .coin: addFX(e)
            }
        }
        g.events.removeAll()
    }
    /// Draws the current notification banner.
    private func drawNotes(_ dt: Float) {
        if let t = hoverText, game?.choice == nil {
            let w: Float = 420
            let h = renderer.measure(t, .ui(17), maxWidth: w - 24).h + 20
            let b = R(min(mouse.x + 18, virtualWidth - w - 10), min(mouse.y + 18, virtualHeight - h - 10), w, h)
            renderer.rect(b, RGBA(r: 0.06, g: 0.05, b: 0.03, a: 0.94)); renderer.frame(b, RGBA.goldDark.alpha(0.7), 1)
            renderer.text(t, .ui(17), x: b.x + 12, y: b.y + 10, color: .gray(0.92), maxWidth: w - 24)
        }
        hoverText = nil
        guard let n = notes.first else { return }
        noteT += dt
        let dur: Float = autotest ? 0.5 : 1.25
        let a = max(0, min(1, min(noteT / 0.15, (dur - noteT) / 0.2)))
        let e = min(1, noteT / 0.18), ease = 1 - (1 - e) * (1 - e)
        let f = Renderer.Font.gwent(34)
        let tw = min(900, renderer.measure(n.text, f, maxWidth: 900).w)
        let th = renderer.measure(n.text, f, maxWidth: 900).h
        let iw: Float = n.icon == nil ? 0 : 96
        let w = tw + iw + 90, h = max(110, th + 50)
        let card = R(960 - w / 2, 500 - h / 2 + (1 - ease) * 18, w, h)
        renderer.rect(R(0, 0, virtualWidth, virtualHeight), RGBA.black.alpha(0.25 * a))
        renderer.gradient(card, RGBA(r: 0.08, g: 0.07, b: 0.06, a: 0.93 * a), RGBA(r: 0.02, g: 0.02, b: 0.03, a: 0.95 * a), steps: 8)
        renderer.rect(R(card.x, card.y, card.w, 2), RGBA.gold.alpha(0.9 * a))
        renderer.rect(R(card.x, card.y + card.h - 1, card.w, 1), RGBA.goldDark.alpha(0.6 * a))
        renderer.frame(card, RGBA.goldDark.alpha(0.35 * a), 1)
        var x = card.x + 45
        if let icon = n.icon { renderer.image("img/icons/\(icon).png", R(x - 10, card.mid.y - 52, 104, 104), color: .white.alpha(a)); x += iw + 10 }
        renderer.text(n.text, f, x: n.icon == nil ? card.mid.x : x, y: card.mid.y - th / 2, color: RGBA(r: 0.97, g: 0.88, b: 0.62, a: a), maxWidth: 900, align: n.icon == nil ? .center : .left, shadow: nil)
        if noteT >= dur { notes.removeFirst(); noteT = 0 }
    }

    /// Full-screen overlay with a set of cards to choose from.
    private func overlayCards(_ cards: [Card], title: String, info: String?, marked: [Card] = [], _ onClick: @escaping (Card) -> Void) -> R {
        renderer.rect(R(0, 0, virtualWidth, virtualHeight), RGBA.black.alpha(0.74))
        renderer.text(title, .serif(32, bold: true), x: 960, y: 70, color: RGBA.gold, maxWidth: 1500, align: .center)
        if let info = info { renderer.text(info, .ui(22), x: 960, y: 150, color: .gray(0.9), align: .center) }
        let n = cards.count
        let perRow = n > 14 ? 10 : (n > 6 ? Int((Double(n) / 2).rounded(.up)) : max(1, n))
        let rows = Int((Double(n) / Double(perRow)).rounded(.up))
        let w: Float = rows > 2 ? 120 : (rows > 1 ? 168 : 190), h = w * 1.437, gap: Float = rows > 2 ? 12 : 22
        let y0: Float = rows > 1 ? 195 : 330
        for (i, c) in cards.enumerated() {
            let rowI = i / perRow, colI = i % perRow
            let inRow = min(perRow, n - rowI * perRow)
            let x0 = 960 - (Float(inRow) * w + Float(inRow - 1) * gap) / 2
            let cr = R(x0 + Float(colI) * (w + gap), y0 + Float(rowI) * (h + gap), w, h)
            if cr.y > 960 { break }
            let hov = cr.contains(mouse)
            drawCardLarge(c, cr)
            if marked.contains(where: { $0 === c }) { renderer.frame(cr.inset(-5), RGBA(r: 0.3, g: 0.85, b: 0.3, a: 1), 4) }
            if hov { renderer.frame(cr.inset(-4), RGBA.gold, 3); hover = c }
            button(cr) { onClick(c) }
        }
        return R(0, min(985, y0 + Float(rows) * (h + gap)), virtualWidth, 0)
    }
    /// Redraw phase overlay.
    private func drawRedraw(_ g: Game) {
        let end = overlayCards(g.human.hand, title: L("Click a card to redraw it"),
                               info: L("Redraws left: ") + "\(g.redrawsLeft)") { [weak self] c in
            guard let g = self?.game, g.redrawsLeft > 0, !g.busy else { return }
            if let n = g.redraw(c) { n.hasPos = false }
            if g.redrawsLeft == 0 { g.finishRedraw() }
        }
        goldButton(R(960 - 150, min(990, end.y + 10), 300, 60), L("Done"), font: .gwent(30)) { [weak self] in self?.game?.finishRedraw() }
        if let h = hover { drawPreview(h) }
    }
    /// Overlay for a pending choice of the human player.
    private func drawChoice(_ ch: Choice, _ g: Game) {
        switch ch.kind {
        case .cards(let cards, let mn, let mx):
            let multi = mx > 1 || mn != 1
            let end = overlayCards(cards, title: ch.title, info: multi ? L("Selected: ") + "\(multiSel.count) / \(mx)" : nil, marked: multiSel) { [weak self] c in
                guard let s = self else { return }
                if !multi { g.resolveChoice([cards.firstIndex { $0 === c }!]); return }
                if let i = s.multiSel.firstIndex(where: { $0 === c }) { s.multiSel.remove(at: i) }
                else if s.multiSel.count < mx { s.multiSel.append(c) }
            }
            var bx: Float = 960 - 150
            if multi {
                let ok = multiSel.count >= mn && multiSel.count <= mx
                goldButton(R(ch.canCancel ? 960 - 320 : bx, min(990, end.y + 10), 300, 60), L("Done"), font: .gwent(30), enabled: ok) { [weak self] in
                    guard let s = self else { return }
                    let idx = s.multiSel.compactMap { m in cards.firstIndex { $0 === m } }
                    s.multiSel = []; g.resolveChoice(idx)
                }
                bx = 960 + 20
            }
            if ch.canCancel { goldButton(R(multi ? bx : 960 - 150, min(990, end.y + 10), 300, 60), L("Skip"), font: .serif(24, bold: true)) { [weak self] in self?.multiSel = []; g.resolveChoice(nil) } }
            if let h = hover { drawPreview(h) }
        case .reveal(let cards):
            let end = overlayCards(cards, title: ch.title, info: nil) { _ in g.resolveChoice(nil) }
            goldButton(R(960 - 150, min(990, end.y + 10), 300, 60), L("Close"), font: .serif(24, bold: true)) { g.resolveChoice(nil) }
            if let h = hover { drawPreview(h) }
        case .options(let opts):
            renderer.rect(R(0, 0, virtualWidth, virtualHeight), RGBA.black.alpha(0.55))
            let cols = opts.count > 4 ? 5 : opts.count
            let bw: Float = opts.count > 4 ? 120 : 340, bh: Float = 64
            let rowsN = Int((Double(opts.count) / Double(cols)).rounded(.up))
            let boxH: Float = 170 + Float(rowsN) * (bh + 16)
            let box = R(960 - 420, 540 - boxH / 2, 840, boxH)
            renderer.gradient(box, RGBA(r: 0.12, g: 0.09, b: 0.05, a: 0.97), RGBA(r: 0.05, g: 0.04, b: 0.02, a: 0.97), steps: 10)
            renderer.frame(box, RGBA.goldDark, 2)
            renderer.text(ch.title, .serif(26, bold: true), x: 960, y: box.y + 30, color: RGBA.gold, maxWidth: 760, align: .center)
            for (i, o) in opts.enumerated() {
                let row = i / cols, col = i % cols
                let inRow = min(cols, opts.count - row * cols)
                let x0 = 960 - (Float(inRow) * bw + Float(inRow - 1) * 16) / 2
                goldButton(R(x0 + Float(col) * (bw + 16), box.y + 120 + Float(row) * (bh + 16), bw, bh), o, font: .serif(22, bold: true)) { g.resolveChoice([i]) }
            }
        case .rows:
            let b = R(560, 820, 960, 46)
            renderer.rect(b, RGBA.black.alpha(0.8)); renderer.frame(b, RGBA.goldDark.alpha(0.7), 1)
            renderer.text(ch.title, .serif(22, bold: true), x: b.mid.x, y: b.y + 10, color: RGBA.gold, maxWidth: 940, align: .center)
        }
    }

    /// End-of-match screen.
    private func drawEnd(_ g: Game) {
        renderer.rect(R(0, 0, virtualWidth, virtualHeight), RGBA.black.alpha(0.8))
        let img = g.winner === g.human ? "end_win" : (g.winner === g.computer ? "end_lose" : "end_draw")
        renderer.imageContain("img/icons/\(img).png", R(660, 90, 600, 360))
        renderer.text(L("Round"), .serif(24, bold: true), x: 760, y: 500, color: .gray(0.8), align: .center)
        renderer.text(playerName, .serif(24, bold: true), x: 960, y: 500, color: RGBA.gold, maxWidth: 190, align: .center)
        renderer.text(careerFightName ?? L("Player 2"), .serif(24, bold: true), x: 1160, y: 500, color: RGBA.gold, maxWidth: 190, align: .center)
        for (i, h) in g.history.enumerated() {
            let y = 545 + Float(i) * 44
            renderer.text("\(i + 1)", .ui(26, bold: true), x: 760, y: y, color: .white, align: .center)
            renderer.text("\(h.human)", .ui(26, bold: true), x: 960, y: y, color: h.winner === g.human ? RGBA.gold : .white, align: .center)
            renderer.text("\(h.computer)", .ui(26, bold: true), x: 1160, y: y, color: h.winner === g.computer ? RGBA.gold : .white, align: .center)
        }
        if let fi = careerFight {
            if g.winner === g.human {
                goldButton(R(960 - 160, 760, 320, 64), L("Claim reward"), font: .serif(26, bold: true)) { [weak self] in
                    guard let s = self else { return }
                    s.careerRewards = s.career.rewardOptions(fi); s.careerNewLeader = s.career.win(fi)
                    s.careerFight = nil; s.game = nil; s.careerChapter = nil; s.screen = .career
                }
            } else {
                goldButton(R(960 - 330, 760, 300, 64), L("Try again"), font: .serif(26, bold: true)) { [weak self] in self?.startCareerFight(fi) }
                goldButton(R(960 + 30, 760, 300, 64), L("Career"), font: .serif(26, bold: true)) { [weak self] in self?.careerFight = nil; self?.game = nil; self?.screen = .career }
            }
            return
        }
        goldButton(R(960 - 330, 760, 300, 64), L("Replay"), font: .serif(26, bold: true)) { [weak self] in self?.startGame() }
        goldButton(R(960 + 30, 760, 300, 64), L("Main menu"), font: .serif(26, bold: true)) { [weak self] in self?.game = nil; self?.screen = .title }
    }
}

// Main UI scene: immediate-mode buttons, title screen, game board drawing, card rendering and input routing.
import CoreGraphics
import Foundation
import Metal


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
    var hits: [(R, () -> Void)] = []
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
    var appVersion: String { (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.1" }
    var onLanguageChange: ((String) -> Void)?
    var autotest = false
    var log: (String) -> Void = { _ in }
    var autoT: Float = 0
    var gamesPlayed = 0

    var game: Game?
    var selected: Card?
    var hover: Card?
    var notes: [(text: String, icon: String?)] = []
    var noteT: Float = 0
    var aiT: Float = 0
    var builder = DeckBuilder()
    var builderHover: Card?
    var builderSaved: Float = 0
    var customDecks: [DeckData] = DeckBuilder.loadCustom()
    var wheel: Float = 0
    var allDecks: [DeckData] { gameData.decks + customDecks }
    var multiSel: [Card] = []
    var hoverText: String?
    var myDeckIndex = 0
    var particles: [Particle] = []
    var glow: MTLTexture!
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
    func mouseMoved(_ point: SIMD2<Float>) { mouse = point; mouseNorm = SIMD2((point.x / virtualWidth - 0.5) * 2, (point.y / virtualHeight - 0.5) * 2) }
    /// Runs the topmost button under the point.
    func click(_ point: SIMD2<Float>) {
        mouse = point
        for (rect, action) in hits.reversed() where rect.contains(point) { action(); return }
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
        if code == 53 { selected = nil; if let match = game, let ch = match.choice, ch.canCancel { multiSel = []; match.resolveChoice(nil) } }
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

    static let regions: [Renderer.BgRegion] = {
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
    let glints: [SIMD2<Float>] = [SIMD2(605 / 1920, 318 / 1080), SIMD2(1250 / 1920, 382 / 1080)]
    let candles: [SIMD2<Float>] = [SIMD2(1405 / 1920, 290 / 1080), SIMD2(1850 / 1920, 330 / 1080), SIMD2(1245 / 1920, 1062 / 1080)]
    var smoothMouse = SIMD2<Float>(0, 0)

    /// Main gold-framed button.
    func goldButton(_ box: R, _ title: String, font: Renderer.Font = .serif(26, bold: true), enabled: Bool = true, _ action: @escaping () -> Void) {
        let hovered = box.contains(mouse) && enabled
        renderer.gradient(box, RGBA(r: 0.19, g: 0.13, b: 0.05, a: 0.95), RGBA(r: 0.05, g: 0.04, b: 0.02, a: 0.96), steps: 12)
        if hovered { renderer.rect(box.inset(-6), RGBA(r: 1, g: 0.75, b: 0.3, a: 0.10)) }
        renderer.frame(box, RGBA.goldDark.alpha(enabled ? 1 : 0.4), 2)
        renderer.frame(box.inset(5), RGBA.goldDark.alpha(hovered ? 0.95 : 0.55), 1)
        let textHeight = renderer.measure(title, font).h
        renderer.text(title, font, x: box.mid.x, y: box.mid.y - textHeight / 2 + 1, color: enabled ? (hovered ? RGBA(r: 1, g: 0.96, b: 0.8, a: 1) : RGBA(r: 0.96, g: 0.86, b: 0.56, a: 1)) : .gray(0.5), align: .center)
        if enabled { button(box, action) }
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
        func power(_ deck: DeckData) -> (Int, Int) { deck.cards.reduce((0, 0)) { acc, e in let c = gameData.cards[e.0]; return (acc.0 + (c?.strength ?? 0) * e.1, acc.1 + e.1) } }
        let pm = power(mine), po = power(theirs)
        log("GAME \(gamesPlayed + 1): \(mine.faction) power \(pm.0) / \(pm.1) cards vs \(theirs.faction) power \(po.0) / \(po.1) cards, AI level \(game?.aiLevel ?? -1)")
        selected = nil; notes = []; noteT = 0; aiT = 0
        screen = .game
        audio.play("game_start")
    }

    let handRect = R(580, 843, 932, 128)
    let weatherRect = R(141, 448, 279, 138)

    var watchdog: Float = 0
    var lastSig = ""

    /// Smaller gold button that shrinks its font to fit.
    func smallButton(_ box: R, _ title: String, enabled: Bool, _ action: @escaping () -> Void) {
        var f = Renderer.Font.serif(21, bold: true)
        while renderer.measure(title, f).w > box.w - 18 && f.size > 11 { f = .serif(f.size - 1, bold: true) }
        goldButton(box, title, font: f, enabled: enabled, action)
    }

    var largeCache: [String: Card] = [:]

}

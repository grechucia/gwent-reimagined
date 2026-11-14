// In-app Options overlay.
import Foundation
import Metal
import CoreGraphics
import simd

extension Scene {
    /// Options overlay: player name, audio, graphics, difficulty, save location and language.
    func drawOptions() {
        renderer.rect(R(0, 0, virtualWidth, virtualHeight), RGBA.black.alpha(0.82))
        let panel = ScreenLayout.optionsPanel
        glassPanel(panel, alpha: 0.96)
        renderer.text(L("Options"), .gwent(52), x: 960, y: panel.y + 24, color: RGBA.gold, align: .center)
        goldButton(ScreenLayout.backButton, "‹  " + L("Back"), font: .serif(22, bold: true)) { [weak self] in self?.optionsOpen = false; self?.game?.paused = false }
        goldButton(R(panel.x + panel.w - 250, panel.y + 30, 210, 46), L("Licenses"), font: .serif(18, bold: true)) { [weak self] in self?.creditsOpen = true }
        var y = panel.y + 110
        let labelX = panel.x + 60, bx = panel.x + 420
        /// Draws a row label.
        func label(_ text: String) { renderer.text(text, .serif(22, bold: true), x: labelX, y: y + 10, color: .white, maxWidth: 340) }
        /// Draws a row of toggle buttons; the selected one is highlighted.
        func choice(_ items: [(String, Bool, Bool)], w width: Float = 140, _ act: @escaping (Int) -> Void) {
            for (i, item) in items.enumerated() {
                let box = R(bx + Float(i) * (width + 10), y, width, 46)
                goldButton(box, (item.1 ? "✓ " : "") + item.0, font: .serif(17, bold: true), enabled: item.2) { act(i) }
                if item.1 { renderer.rect(box, RGBA(r: 1, g: 0.78, b: 0.3, a: 0.22)); renderer.frame(box.inset(-3), RGBA(r: 1, g: 0.85, b: 0.4, a: 1), 3) }
            }
        }
        label(L("Player name"))
        renderer.text(playerName, .serif(22, bold: true), x: bx, y: y + 10, color: RGBA.gold, maxWidth: 380)
        goldButton(R(bx + 400, y, 200, 46), L("Change…"), font: .serif(17, bold: true)) { [weak self] in self?.askPlayerName() }
        y += 76
        label(L("Music"))
        choice([(L("On"), audio.musicOn && !audio.muted, true), (L("Off"), !audio.musicOn || audio.muted, true)]) { [weak self] i in
            guard let strongSelf = self else { return }
            if i == 0 { strongSelf.audio.muted = false; strongSelf.audio.musicOn = true } else { strongSelf.audio.musicOn = false }
            strongSelf.host?.refreshMenus()
        }
        y += 76
        label(L("Sound effects"))
        choice([(L("On"), !audio.muted, true), (L("Off"), audio.muted, true)]) { [weak self] i in
            guard let strongSelf = self else { return }
            strongSelf.audio.muted = i == 1; if i == 1 { strongSelf.audio.musicOn = false }
            strongSelf.host?.refreshMenus()
        }
        y += 76
        if let h = host {
            label(L("Render resolution"))
            let options = resolutions
            choice(options.map { ($0.px == 0 ? L("Native") : "\($0.px)p", $0.px == h.renderRes, true) }, w: 128) { i in h.setRenderRes(options[i].px) }
            y += 76
            label(L("Frame limit"))
            let fl = h.availableFrameLimits
            choice(fl.map { ("\($0) FPS", $0 == h.effectiveFrameLimit, true) }, w: 128) { i in h.setFrameLimit(fl[i]) }
            y += 76
            if h.supportsWindowModes {
                label(L("Display mode"))
                choice([(L("Window"), !h.isFullScreen, true), (L("Full screen"), h.isFullScreen, true)], w: 180) { i in h.setFullScreen(i == 1) }
                y += 76
            }
        }
        label(L("Save location"))
        renderer.text(SaveStore.shared.chosen ? SaveStore.shared.displayPath : L("not chosen yet"), .ui(15), x: bx, y: y + 4, color: .gray(0.8), maxWidth: 680)
        goldButton(R(bx, y + 50, 200, 44), L("Change…"), font: .serif(17, bold: true)) { [weak self] in self?.askSaveLocation(then: nil) }
        y += 126
        label(L("Difficulty (outside career)"))
        choice([(L("Easy"), aiLevel == 0, true), (L("Normal"), aiLevel == 1, true), (L("Hard"), aiLevel == 2, true)], w: 180) { [weak self] i in self?.aiLevel = i }
        y += 76
        label(L("Language"))
        languageToggle(y: y + 6)
    }
}

// Licenses and credits overlay.
import Foundation
import Metal
import CoreGraphics
import simd

extension Scene {
    /// Draws the licenses and credits.
    func drawCredits() {
        renderer.rect(renderer.visibleRect, RGBA.black.alpha(0.85))
        let panel = ScreenLayout.licensesPanel
        glassPanel(panel, alpha: 0.95)
        renderer.text(L("Licenses"), .gwent(52), x: 960, y: 24, color: RGBA.gold, align: .center)
        goldButton(ScreenLayout.backButton, "‹  " + L("Back"), font: .serif(22, bold: true)) { [weak self] in self?.creditsOpen = false; self?.game?.paused = false }
        let x = panel.x + 60, w = panel.w - 120
        var y = panel.y + 40
        /// Section heading.
        func head(_ text: String) { y += renderer.text(text, .gwent(30), x: x, y: y, color: RGBA.gold, maxWidth: w).h + 4; goldDivider(x, y, min(w, 600)); y += 14 }
        /// Paragraph.
        func para(_ text: String, _ color: RGBA = RGBA(r: 0.92, g: 0.88, b: 0.8, a: 1)) { y += renderer.text(text, .serif(19), x: x, y: y, color: color, maxWidth: w).h + 10 }
        /// Clickable link.
        func link(_ text: String, _ url: String) {
            let textSize = renderer.measure(text, .serif(19, bold: true), maxWidth: w)
            let area = R(x, y, textSize.w, textSize.h)
            let hovered = area.contains(mouse)
            renderer.text(text, .serif(19, bold: true), x: x, y: y, color: hovered ? .white : RGBA(r: 0.55, g: 0.78, b: 1, a: 1), maxWidth: w)
            renderer.rect(R(x, y + textSize.h - 2, textSize.w, 1), RGBA(r: 0.55, g: 0.78, b: 1, a: hovered ? 1 : 0.6))
            button(area) { if let link = URL(string: url) { Platform.openURL(link) } }
            y += textSize.h + 12
        }
        head(L("Rights holder: CD PROJEKT RED"))
        para(L("All characters, the Witcher universe, Gwent, names, card art, music, sounds and trademarks are the property of CD PROJEKT S.A. / CD PROJEKT RED. The Witcher 3: Wild Hunt © CD PROJEKT S.A."))
        para("This is an unofficial fan work and is not approved/endorsed by CD PROJEKT RED.", RGBA(r: 1, g: 0.9, b: 0.6, a: 1))
        para(L("The project is non-commercial and free. CD PROJEKT RED Fan Content Guidelines:"), .gray(0.7))
        link("cdprojektred.com/en/fan-content", "https://www.cdprojektred.com/en/fan-content")
        y += 10
        head(L("Fork of Gwent Classic v5.0"))
        para(L("This app is a fork of the open-source Gwent Classic v5.0 project from GitHub (authors: Arun Sundaram, Reynolds Costa, Sylver, Iván Mtz; version 5.0: ia2904)."))
        link(L("Original: Gwent Classic (Arun Sundaram)"), "https://github.com/asundr/gwent-classic")
        link("github.com/ia2904/gwent-classic-v5.0", "https://github.com/ia2904/gwent-classic-v5.0")
        link(L("License (MIT + Commons Clause)"), "https://github.com/ia2904/gwent-classic-v5.0?tab=License-1-ov-file")
        para("“Commons Clause” License Condition v1.0 — " + L("the license does not grant the right to sell the Software. Software: Gwent Classic · License: MIT · Licensor: Arun Sundaram."), .gray(0.75))
        y += 10
        head(L("Port"))
        para("Reimagined / ported by grechucia. " + L("Port code under the same license (MIT + Commons Clause)."))
        link("github.com/grechucia/gwent-reimagined", "https://github.com/grechucia/gwent-reimagined")
    }
}

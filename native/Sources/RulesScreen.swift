// Rules screen overlay.
import Foundation
import Metal
import CoreGraphics
import simd

extension Scene {
    /// Opens the rules screen.
    func openRules() { rulesOpen = true; rulesScroll = 0; game?.paused = true }

    /// Closes the rules screen.
    func closeRules() { rulesOpen = false; game?.paused = false }

    /// Rules screen.
    func drawRules() {
        renderer.rect(renderer.visibleRect, RGBA.black.alpha(0.82))
        let panel = ScreenLayout.rulesPanel
        renderer.gradient(panel, RGBA(r: 0.13, g: 0.1, b: 0.06, a: 0.98), RGBA(r: 0.07, g: 0.05, b: 0.03, a: 0.98), steps: 12)
        renderer.frame(panel, RGBA.goldDark, 2)
        renderer.frame(panel.inset(6), RGBA.goldDark.alpha(0.4), 1)
        renderer.text(L("Rules of Gwent"), .gwent(48), x: 960, y: 22, color: RGBA.gold, align: .center)
        let back = ScreenLayout.backButton
        goldButton(back, "‹  " + L("Back"), font: .serif(22, bold: true)) { [weak self] in self?.closeRules() }
        let content = R(panel.x + 50, panel.y + 30, panel.w - 100, panel.h - 60)
        let blocks = gameData.rules()
        var heights: [Float] = []
        var total: Float = 0
        for block in blocks {
            let h = block.heading ? renderer.measure(block.text, .gwent(30), maxWidth: content.w).h + 18 : renderer.measure(block.text, .serif(21), maxWidth: content.w).h + 16
            heights.append(h); total += h
        }
        let maxScroll = max(0, total - content.h)
        rulesScroll = max(0, min(maxScroll, rulesScroll - wheel))
        renderer.clip(content)
        var y = content.y - rulesScroll
        for (i, block) in blocks.enumerated() {
            let h = heights[i]
            if y + h >= content.y && y <= content.y + content.h {
                if block.heading {
                    renderer.text(block.text, .gwent(30), x: content.x, y: y + 10, color: RGBA.gold, maxWidth: content.w)
                    renderer.rect(R(content.x, y + h - 6, min(content.w, 520), 1.5), RGBA.goldDark.alpha(0.6))
                } else {
                    renderer.text(block.text, .serif(21), x: content.x, y: y, color: RGBA(r: 0.92, g: 0.88, b: 0.8, a: 1), maxWidth: content.w)
                }
            }
            y += h
        }
        renderer.clip(nil)
        if maxScroll > 0 {
            let scrollThumbHeight = content.h * content.h / total
            renderer.rect(R(panel.x + panel.w - 14, content.y + (content.h - scrollThumbHeight) * rulesScroll / maxScroll, 5, scrollThumbHeight), RGBA.gold.alpha(0.6))
        }
        renderer.text(L("Scroll with the mouse wheel · Esc — back"), .ui(16), x: 960, y: 1040, color: .gray(0.6), align: .center)
    }
}

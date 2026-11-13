import CoreGraphics
import Foundation
import Metal
import simd

private let CW: Float = 85, CH: Float = 122

struct FX {
    enum Kind { case icon(String), burn, hero, coin(Bool) }
    let kind: Kind
    weak var card: Card?
    var rect: R
    var t: Float = 0
    let dur: Float
}

extension Scene {
    func addFX(_ e: GameEvent) {
        switch e {
        case .anim(let c, let n):
            let rr = R(c.pos.x, c.pos.y, CW, CH)
            fxList.append(FX(kind: n == "hero" ? .hero : .icon(n), card: c, rect: rr, dur: n == "hero" ? 1.1 : 1.6))
        case .burn(let c):
            fxList.append(FX(kind: .burn, card: c, rect: R(c.pos.x, c.pos.y, CW, CH), dur: 1.0))
        case .coin(let mine):
            fxList.append(FX(kind: .coin(mine), card: nil, rect: R(960 - 170, 290, 340, 340), dur: 1.7))
        default: break
        }
    }
    func drawFX(_ dt: Float) {
        for i in fxList.indices.reversed() {
            fxList[i].t += dt
            var f = fxList[i]
            if f.t >= f.dur { fxList.remove(at: i); continue }
            if let c = f.card, c.hasPos, !isBurn(f) { f.rect = R(c.pos.x, c.pos.y, CW, CH); fxList[i].rect = f.rect }
            let t = f.t, cr = f.rect
            switch f.kind {
            case .icon(let n):
                let s: Float, a: Float
                if t < 0.3 { let k = t / 0.3; s = 0.5 + 0.6 * k; a = k }
                else if t < 1.3 { let k = (t - 0.3) / 1.0; s = 1.1 - 0.2 * k; a = 1 }
                else { let k = (t - 1.3) / 0.3; s = 0.9 - 0.4 * k; a = 1 - k }
                let w = cr.w * s * 1.15
                r.image("img/icons/anim_\(n).png", R(cr.mid.x - w / 2, cr.mid.y - w / 2, w, w), color: .white.alpha(a))
            case .burn:
                let k = t / f.dur
                let a = k < 0.15 ? k / 0.15 : (k > 0.75 ? (1 - k) / 0.25 : 1)
                let flick = 0.85 + 0.15 * sin(time * 40 + cr.x)
                r.quad(glowTex, R(cr.x - 30, cr.y - 30, cr.w + 60, cr.h + 60), color: RGBA(r: 1, g: 0.45, b: 0.1, a: 0.55 * a * flick))
                r.image("img/icons/anim_scorch.png", R(cr.x - cr.w * 0.1, cr.y - cr.h * 0.15, cr.w * 1.2, cr.h * 1.25), color: .white.alpha(a * flick))
            case .hero:
                let k = t / f.dur
                r.clip(cr)
                let x = cr.x - 60 + (cr.w + 120) * k
                r.quad(r.white, R(x - 14, cr.y - 40, 28, cr.h + 80), color: RGBA(r: 1, g: 0.92, b: 0.6, a: 0.55 * (1 - abs(k - 0.5) * 2) + 0.15), rotation: 0.35)
                r.clip(nil)
                r.frame(cr.inset(-3), RGBA(r: 1, g: 0.84, b: 0.35, a: 0.9 * (1 - k)), 3)
                r.quad(glowTex, R(cr.x - 25, cr.y - 25, cr.w + 50, cr.h + 50), color: RGBA(r: 1, g: 0.8, b: 0.3, a: 0.35 * (1 - k)))
            case .coin(let mine):
                let k = t / f.dur
                let spin = abs(cos(min(k / 0.7, 1) * Float.pi * 5))
                let a: Float = k > 0.85 ? (1 - k) / 0.15 : 1
                r.rect(R(0, 0, VW, VH), RGBA.black.alpha(0.35 * a))
                let face = k < 0.7 ? (Int(k / 0.7 * 10) % 2 == 0) : mine
                let w = cr.w * max(0.06, k < 0.7 ? spin : 1)
                r.image("img/icons/notif_\(face ? "me" : "op")_coin.png", R(cr.mid.x - w / 2, cr.y, w, cr.h), color: .white.alpha(a))
            }
        }
    }
    private func isBurn(_ f: FX) -> Bool { if case .burn = f.kind { return true }; return false }

    func flightRect(_ c: Card, target: SIMD2<Float>) -> (R, Bool) {
        let d = simd_length(target - c.pos)
        let s = 1 + min(0.22, d / 900)
        let w = CW * s, h = CH * s
        return (R(c.pos.x + CW / 2 - w / 2, c.pos.y + CH / 2 - h / 2 - min(18, d / 25), w, h), d > 6)
    }

    func drawWeatherFX(_ w: Set<String>, _ rr: R) {
        guard !w.isEmpty else { return }
        let area = R(567, rr.y + 4, 946, rr.h - 6)
        r.clip(area)
        defer { r.clip(nil) }
        if w.contains("rain") || w.contains("storm") || w.contains("dragon_wrath") {
            for i in 0..<46 {
                let fi = Float(i)
                let x = area.x + fract(fi * 0.6180339 + 0.13) * area.w + fract(time * 0.9 + fi * 0.37) * 30
                let y = area.y - 20 + fract(time * 1.7 + fi * 0.0731) * (area.h + 40)
                r.quad(r.white, R(x, y, 1.6, 16), color: RGBA(r: 0.75, g: 0.85, b: 1, a: 0.35), rotation: 0.22)
            }
        }
        if w.contains("fog") || w.contains("tse_tse") {
            for k in 0..<2 {
                let off = sin(time * 0.25 + Float(k) * 2) * 40
                r.image("img/icons/overlay_\(w.contains("fog") ? "fog" : "tse_tse").png", R(area.x + off - 20, area.y, area.w + 40, area.h), color: .white.alpha(0.25 + 0.12 * sin(time * 0.7 + Float(k))))
            }
        }
        if w.contains("frost") || w.contains("white_frost") || w.contains("spider_web") {
            for i in 0..<26 {
                let fi = Float(i)
                let x = area.x + fract(fi * 0.754877) * area.w, y = area.y + fract(fi * 0.569840) * area.h
                let tw = max(0, sin(time * 2.4 + fi * 1.7))
                let s: Float = 6 + 10 * tw
                r.quad(glowTex, R(x - s / 2, y - s / 2, s, s), color: RGBA(r: 0.8, g: 0.92, b: 1, a: 0.7 * tw))
            }
        }
        if w.contains("sandstorm") {
            for i in 0..<40 {
                let fi = Float(i)
                let x = area.x - 40 + fract(time * 0.8 + fi * 0.6180339) * (area.w + 80)
                let y = area.y + fract(fi * 0.4142) * area.h + sin(time * 3 + fi) * 4
                r.quad(r.white, R(x, y, 24, 1.5), color: RGBA(r: 0.9, g: 0.75, b: 0.45, a: 0.35))
            }
        }
    }

    func openRules() { rulesOpen = true; rulesScroll = 0; game?.paused = true }
    func closeRules() { rulesOpen = false; game?.paused = false }
    func drawRules() {
        r.rect(R(0, 0, VW, VH), RGBA.black.alpha(0.82))
        let panel = R(260, 90, 1400, 940)
        r.gradient(panel, RGBA(r: 0.13, g: 0.1, b: 0.06, a: 0.98), RGBA(r: 0.07, g: 0.05, b: 0.03, a: 0.98), steps: 12)
        r.frame(panel, RGBA.goldDark, 2)
        r.frame(panel.inset(6), RGBA.goldDark.alpha(0.4), 1)
        r.text(L("Rules of Gwent"), .gwent(48), x: 960, y: 22, color: RGBA.gold, align: .center)
        let back = R(40, 24, 190, 50)
        goldButton(back, "‹  " + L2("Wróć", "Back"), font: .serif(22, bold: true)) { [weak self] in self?.closeRules() }
        let content = R(panel.x + 50, panel.y + 30, panel.w - 100, panel.h - 60)
        let blocks = gd.rules()
        var heights: [Float] = []
        var total: Float = 0
        for b in blocks {
            let h = b.heading ? r.measure(b.text, .gwent(30), maxWidth: content.w).h + 18 : r.measure(b.text, .serif(21), maxWidth: content.w).h + 16
            heights.append(h); total += h
        }
        let maxScroll = max(0, total - content.h)
        rulesScroll = max(0, min(maxScroll, rulesScroll - wheel))
        r.clip(content)
        var y = content.y - rulesScroll
        for (i, b) in blocks.enumerated() {
            let h = heights[i]
            if y + h >= content.y && y <= content.y + content.h {
                if b.heading {
                    r.text(b.text, .gwent(30), x: content.x, y: y + 10, color: RGBA.gold, maxWidth: content.w)
                    r.rect(R(content.x, y + h - 6, min(content.w, 520), 1.5), RGBA.goldDark.alpha(0.6))
                } else {
                    r.text(b.text, .serif(21), x: content.x, y: y, color: RGBA(r: 0.92, g: 0.88, b: 0.8, a: 1), maxWidth: content.w)
                }
            }
            y += h
        }
        r.clip(nil)
        if maxScroll > 0 {
            let th = content.h * content.h / total
            r.rect(R(panel.x + panel.w - 14, content.y + (content.h - th) * rulesScroll / maxScroll, 5, th), RGBA.gold.alpha(0.6))
        }
        r.text(L2("Przewijaj kółkiem myszy · Esc — powrót", "Scroll with the mouse wheel · Esc — back"), .ui(16), x: 960, y: 1040, color: .gray(0.6), align: .center)
    }
}

@inline(__always) func fract(_ x: Float) -> Float { x - floor(x) }

extension Scene {
    func drawCredits() {
        r.rect(R(0, 0, VW, VH), RGBA.black.alpha(0.85))
        let panel = R(360, 110, 1200, 860)
        glassPanel(panel, alpha: 0.95)
        r.text(L2("Licencje", "Licenses"), .gwent(52), x: 960, y: 24, color: RGBA.gold, align: .center)
        goldButton(R(40, 24, 190, 50), "‹  " + L2("Wróć", "Back"), font: .serif(22, bold: true)) { [weak self] in self?.creditsOpen = false; self?.game?.paused = false }
        let x = panel.x + 60, w = panel.w - 120
        var y = panel.y + 40
        func head(_ t: String) { y += r.text(t, .gwent(30), x: x, y: y, color: RGBA.gold, maxWidth: w).h + 4; goldDivider(x, y, min(w, 600)); y += 14 }
        func para(_ t: String, _ c: RGBA = RGBA(r: 0.92, g: 0.88, b: 0.8, a: 1)) { y += r.text(t, .serif(19), x: x, y: y, color: c, maxWidth: w).h + 10 }
        func link(_ t: String, _ url: String) {
            let sz = r.measure(t, .serif(19, bold: true), maxWidth: w)
            let b = R(x, y, sz.w, sz.h)
            let hov = b.contains(mouse)
            r.text(t, .serif(19, bold: true), x: x, y: y, color: hov ? .white : RGBA(r: 0.55, g: 0.78, b: 1, a: 1), maxWidth: w)
            r.rect(R(x, y + sz.h - 2, sz.w, 1), RGBA(r: 0.55, g: 0.78, b: 1, a: hov ? 1 : 0.6))
            button(b) { if let u = URL(string: url) { Platform.openURL(u) } }
            y += sz.h + 12
        }
        head(L2("Właściciel praw: CD PROJEKT RED", "Rights holder: CD PROJEKT RED"))
        para(L2("Wszystkie postacie, uniwersum Wiedźmina, gwint, nazwy, ilustracje kart, muzyka, dźwięki i znaki towarowe są własnością CD PROJEKT S.A. / CD PROJEKT RED. Wiedźmin 3: Dziki Gon © CD PROJEKT S.A.",
                "All characters, the Witcher universe, Gwent, names, card art, music, sounds and trademarks are the property of CD PROJEKT S.A. / CD PROJEKT RED. The Witcher 3: Wild Hunt © CD PROJEKT S.A."))
        para("This is an unofficial fan work and is not approved/endorsed by CD PROJEKT RED.", RGBA(r: 1, g: 0.9, b: 0.6, a: 1))
        para(L2("Projekt jest niekomercyjny i darmowy. Zasady twórczości fanowskiej CD PROJEKT RED (Fan Content Guidelines):",
                "The project is non-commercial and free. CD PROJEKT RED Fan Content Guidelines:"), .gray(0.7))
        link("cdprojektred.com/en/fan-content", "https://www.cdprojektred.com/en/fan-content")
        y += 10
        head(L2("Fork projektu Gwent Classic v5.0", "Fork of Gwent Classic v5.0"))
        para(L2("Ta aplikacja jest forkiem projektu open source Gwent Classic v5.0 z GitHuba (autorzy: Arun Sundaram, Reynolds Costa, Sylver, Iván Mtz; wersja 5.0: ia2904).",
                "This app is a fork of the open-source Gwent Classic v5.0 project from GitHub (authors: Arun Sundaram, Reynolds Costa, Sylver, Iván Mtz; version 5.0: ia2904)."))
        link(L2("Oryginał: Gwent Classic (Arun Sundaram)", "Original: Gwent Classic (Arun Sundaram)"), "https://github.com/asundr/gwent-classic")
        link("github.com/ia2904/gwent-classic-v5.0", "https://github.com/ia2904/gwent-classic-v5.0")
        link(L2("Licencja (MIT + Commons Clause)", "License (MIT + Commons Clause)"), "https://github.com/ia2904/gwent-classic-v5.0?tab=License-1-ov-file")
        para("“Commons Clause” License Condition v1.0 — " + L2("licencja nie daje prawa do sprzedaży oprogramowania. Software: Gwent Classic · License: MIT · Licensor: Arun Sundaram.",
                "the license does not grant the right to sell the Software. Software: Gwent Classic · License: MIT · Licensor: Arun Sundaram."), .gray(0.75))
        y += 10
        head(L2("Port", "Port"))
        para("Reimagined / ported by grechucia. " + L2("Kod portu na tej samej licencji (MIT + Commons Clause).", "Port code under the same license (MIT + Commons Clause)."))
        link("github.com/grechucia/gwent-reimagined", "https://github.com/grechucia/gwent-reimagined")
    }
}

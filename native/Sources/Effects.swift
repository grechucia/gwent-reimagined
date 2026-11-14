// Visual effects: card flights, burns, flashes and animated weather on rows.
import CoreGraphics
import Foundation
import Metal
import simd


/// A running visual effect.
struct FX {
    /// Effect type.
    enum Kind { case icon(String), burn, hero, coin(Bool) }
    let kind: Kind
    weak var card: Card?
    var rect: R
    var t: Float = 0
    let dur: Float
}

/// Visual effects.
extension Scene {
    /// Creates effects for an engine event.
    func addFX(_ event: GameEvent) {
        switch event {
        case .anim(let c, let n):
            let rowArea = R(c.pos.x, c.pos.y, cardWidth, cardHeight)
            fxList.append(FX(kind: n == "hero" ? .hero : .icon(n), card: c, rect: rowArea, dur: n == "hero" ? 1.1 : 1.6))
        case .burn(let c):
            fxList.append(FX(kind: .burn, card: c, rect: R(c.pos.x, c.pos.y, cardWidth, cardHeight), dur: 1.0))
        case .coin(let mine):
            fxList.append(FX(kind: .coin(mine), card: nil, rect: R(960 - 170, 290, 340, 340), dur: 1.7))
        default: break
        }
    }
    /// Updates and draws the running effects.
    func drawFX(_ dt: Float) {
        for i in fxList.indices.reversed() {
            fxList[i].t += dt
            var f = fxList[i]
            if f.t >= f.dur { fxList.remove(at: i); continue }
            if let c = f.card, c.hasPos, !isBurn(f) { f.rect = R(c.pos.x, c.pos.y, cardWidth, cardHeight); fxList[i].rect = f.rect }
            let t = f.t, cr = f.rect
            switch f.kind {
            case .icon(let n):
                let s: Float, a: Float
                if t < 0.3 { let k = t / 0.3; s = 0.5 + 0.6 * k; a = k }
                else if t < 1.3 { let k = (t - 0.3) / 1.0; s = 1.1 - 0.2 * k; a = 1 }
                else { let k = (t - 1.3) / 0.3; s = 0.9 - 0.4 * k; a = 1 - k }
                let w = cr.w * s * 1.15
                renderer.image("img/icons/anim_\(n).png", R(cr.mid.x - w / 2, cr.mid.y - w / 2, w, w), color: .white.alpha(a))
            case .burn:
                let k = t / f.dur
                let a = k < 0.15 ? k / 0.15 : (k > 0.75 ? (1 - k) / 0.25 : 1)
                let flick = 0.85 + 0.15 * sin(time * 40 + cr.x)
                renderer.quad(glowTex, R(cr.x - 30, cr.y - 30, cr.w + 60, cr.h + 60), color: RGBA(r: 1, g: 0.45, b: 0.1, a: 0.55 * a * flick))
                renderer.image("img/icons/anim_scorch.png", R(cr.x - cr.w * 0.1, cr.y - cr.h * 0.15, cr.w * 1.2, cr.h * 1.25), color: .white.alpha(a * flick))
            case .hero:
                let k = t / f.dur
                renderer.clip(cr)
                let x = cr.x - 60 + (cr.w + 120) * k
                renderer.quad(renderer.white, R(x - 14, cr.y - 40, 28, cr.h + 80), color: RGBA(r: 1, g: 0.92, b: 0.6, a: 0.55 * (1 - abs(k - 0.5) * 2) + 0.15), rotation: 0.35)
                renderer.clip(nil)
                renderer.frame(cr.inset(-3), RGBA(r: 1, g: 0.84, b: 0.35, a: 0.9 * (1 - k)), 3)
                renderer.quad(glowTex, R(cr.x - 25, cr.y - 25, cr.w + 50, cr.h + 50), color: RGBA(r: 1, g: 0.8, b: 0.3, a: 0.35 * (1 - k)))
            case .coin(let mine):
                let k = t / f.dur
                let spin = abs(cos(min(k / 0.7, 1) * Float.pi * 5))
                let a: Float = k > 0.85 ? (1 - k) / 0.15 : 1
                renderer.rect(R(0, 0, virtualWidth, virtualHeight), RGBA.black.alpha(0.35 * a))
                let face = k < 0.7 ? (Int(k / 0.7 * 10) % 2 == 0) : mine
                let w = cr.w * max(0.06, k < 0.7 ? spin : 1)
                renderer.image("img/icons/notif_\(face ? "me" : "op")_coin.png", R(cr.mid.x - w / 2, cr.y, w, cr.h), color: .white.alpha(a))
            }
        }
    }
    /// Whether an effect is a burn (scorch) effect.
    func isBurn(_ f: FX) -> Bool { if case .burn = f.kind { return true }; return false }

    /// Rectangle of a card flying towards a target.
    func flightRect(_ card: Card, target: SIMD2<Float>) -> (R, Bool) {
        let d = simd_length(target - card.pos)
        let s = 1 + min(0.22, d / 900)
        let w = cardWidth * s, h = cardHeight * s
        return (R(card.pos.x + cardWidth / 2 - w / 2, card.pos.y + cardHeight / 2 - h / 2 - min(18, d / 25), w, h), d > 6)
    }

    /// Animated weather on a row (rain, frost, fog...).
    func drawWeatherFX(_ weather: Set<String>, _ rowArea: R) {
        guard !weather.isEmpty else { return }
        let area = R(567, rowArea.y + 4, 946, rowArea.h - 6)
        renderer.clip(area)
        defer { renderer.clip(nil) }
        if weather.contains("rain") || weather.contains("storm") || weather.contains("dragon_wrath") {
            for i in 0..<46 {
                let fi = Float(i)
                let x = area.x + fract(fi * 0.6180339 + 0.13) * area.w + fract(time * 0.9 + fi * 0.37) * 30
                let y = area.y - 20 + fract(time * 1.7 + fi * 0.0731) * (area.h + 40)
                renderer.quad(renderer.white, R(x, y, 1.6, 16), color: RGBA(r: 0.75, g: 0.85, b: 1, a: 0.35), rotation: 0.22)
            }
        }
        if weather.contains("fog") || weather.contains("tse_tse") {
            for k in 0..<2 {
                let off = sin(time * 0.25 + Float(k) * 2) * 40
                renderer.image("img/icons/overlay_\(weather.contains("fog") ? "fog" : "tse_tse").png", R(area.x + off - 20, area.y, area.w + 40, area.h), color: .white.alpha(0.25 + 0.12 * sin(time * 0.7 + Float(k))))
            }
        }
        if weather.contains("frost") || weather.contains("white_frost") || weather.contains("spider_web") {
            for i in 0..<26 {
                let fi = Float(i)
                let x = area.x + fract(fi * 0.754877) * area.w, y = area.y + fract(fi * 0.569840) * area.h
                let twinkle = max(0, sin(time * 2.4 + fi * 1.7))
                let s: Float = 6 + 10 * twinkle
                renderer.quad(glowTex, R(x - s / 2, y - s / 2, s, s), color: RGBA(r: 0.8, g: 0.92, b: 1, a: 0.7 * twinkle))
            }
        }
        if weather.contains("sandstorm") {
            for i in 0..<40 {
                let fi = Float(i)
                let x = area.x - 40 + fract(time * 0.8 + fi * 0.6180339) * (area.w + 80)
                let y = area.y + fract(fi * 0.4142) * area.h + sin(time * 3 + fi) * 4
                renderer.quad(renderer.white, R(x, y, 24, 1.5), color: RGBA(r: 0.9, g: 0.75, b: 0.45, a: 0.35))
            }
        }
    }

}

@inline(__always) func fract(_ x: Float) -> Float { x - floor(x) }

/// Licenses screen.
extension Scene {
}

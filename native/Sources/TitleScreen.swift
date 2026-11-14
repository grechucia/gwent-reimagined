// Title screen: animated background, logo, main buttons, language selector and particles.
import Foundation
import Metal
import CoreGraphics
import simd

extension Scene {
    /// Title screen with the animated background.
    func drawTitle(_ dt: Float) {
        if autotest { autoT += dt; if autoT > 2.5 { autoT = 0; myDeckIndex = Int.random(in: 0..<gameData.decks.count); startGame() } }
        smoothMouse += (mouseNorm - smoothMouse) * min(1, dt * 2.5)
        renderer.titleBackground("img/start_bg.jpg", time: time, mouse: smoothMouse, regions: Scene.regions, glints: glints, candles: candles)
        drawParticles(dt)
        let mid = gameData.language == "pl" ? "WIN" : "WEN"
        let big = Renderer.Font.gwent(146), small = Renderer.Font.gwent(104)
        let widthG = renderer.measure("G", big).w, wM = renderer.measure(mid, small).w, wT = renderer.measure("T", big).w
        let total = widthG + wM + wT - 24
        var x = 960 - total / 2
        let y: Float = 34
        let witcherLabel = L("The Witcher 3").uppercased()
        renderer.text(witcherLabel, .gwent(26), x: 962, y: 16, color: RGBA(r: 0, g: 0, b: 0, a: 0.7), align: .center, shadow: nil)
        renderer.text(witcherLabel, .gwent(26), x: 960, y: 14, color: RGBA(r: 0.96, g: 0.85, b: 0.6, a: 0.7), align: .center, shadow: nil)
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
        let area = R(960 - 170, 905, 340, 70)
        padPrimary = area
        goldButton(area, gameData.ui("LET'S PLAY"), font: .gwent(38)) { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.audio.play("menu_opening")
            let go: () -> Void = { [weak strongSelf] in strongSelf?.deckStage = -1; strongSelf?.deckSwitchT = 0; strongSelf?.screen = .decks }
            let named: () -> Void = { [weak strongSelf] in if SaveStore.shared["playerName"] == nil { strongSelf?.askPlayerName(then: go) } else { go() } }
            if SaveStore.shared.chosen { named() } else { strongSelf.askSaveLocation(then: named) }
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
        let font = Renderer.Font.serif(18), fb = Renderer.Font.serif(18, bold: true)
        let lw = renderer.measure(linkText, fb).w, pw = renderer.measure(plain, font).w
        let x1 = 1880 - lw
        renderer.text(plain, font, x: x1 - pw, y: y, color: RGBA(r: 0.91, g: 0.86, b: 0.74, a: 0.9))
        let area = R(x1, y, lw, 26)
        let hovered = area.contains(mouse)
        renderer.text(linkText, fb, x: x1, y: y, color: hovered ? .white : RGBA.gold)
        renderer.rect(R(x1, y + 23, lw, 1), RGBA.gold.alpha(hovered ? 1 : 0.5))
        padNoFocus.append(area)
        button(area) { if let link = URL(string: url) { Platform.openURL(link) } }
    }

    /// Language dropdown on the title screen.
    func languageToggle(y: Float) {
        let w: Float = 260, h: Float = 40
        let box = R(960 - w / 2, y, w, h)
        let currentName = GameData.languageName(gameData.language)
        renderer.rect(box.inset(-4), RGBA(r: 0.04, g: 0.03, b: 0.01, a: 0.78))
        renderer.frame(box.inset(-4), RGBA.goldDark.alpha(langMenuOpen || box.contains(mouse) ? 0.95 : 0.55), 1.5)
        let textHeight = renderer.measure(currentName, .serif(20, bold: true)).h
        renderer.text(currentName, .serif(20, bold: true), x: box.x + 18, y: box.mid.y - textHeight / 2, color: RGBA.gold)
        renderer.text(langMenuOpen ? "▴" : "▾", .ui(20, bold: true), x: box.x + box.w - 18, y: box.mid.y - textHeight / 2, color: RGBA.gold, align: .right)
        if !langMenuOpen { button(box) { [weak self] in self?.langMenuOpen = true }; return }
        button(R(0, 0, virtualWidth, virtualHeight)) { [weak self] in self?.langMenuOpen = false }
        let ih: Float = 36
        let list = GameData.languages
        let area = R(box.x - 4, box.y - 8 - Float(list.count) * ih, box.w + 8, Float(list.count) * ih + 4)
        renderer.rect(area, RGBA(r: 0.05, g: 0.04, b: 0.02, a: 0.97)); renderer.frame(area, RGBA.goldDark, 1.5)
        for (i, language) in list.enumerated() {
            let ir = R(area.x + 2, area.y + 2 + Float(i) * ih, area.w - 4, ih)
            let isCurrent = language.code == gameData.language, hov = ir.contains(mouse)
            if isCurrent { renderer.gradient(ir, RGBA(r: 0.95, g: 0.82, b: 0.49, a: 1), RGBA(r: 0.79, g: 0.59, b: 0.18, a: 1), steps: 6) }
            else if hov { renderer.rect(ir, RGBA.gold.alpha(0.18)) }
            let textY = ir.mid.y - renderer.measure(language.name, .serif(19, bold: true)).h / 2
            renderer.text(language.name, .serif(19, bold: true), x: ir.x + 16, y: textY, color: isCurrent ? RGBA(r: 0.1, g: 0.07, b: 0.02, a: 1) : (hov ? .white : .gray(0.85)), shadow: isCurrent ? nil : RGBA.black.alpha(0.8))
            if !gameData.hasTranslation(language.code) { renderer.text("EN", .ui(12, bold: true), x: ir.x + ir.w - 14, y: ir.mid.y - 8, color: isCurrent ? RGBA(r: 0.2, g: 0.14, b: 0.04, a: 1) : .gray(0.5), align: .right, shadow: nil) }
            button(ir) { [weak self] in self?.setLanguage(language.code); self?.langMenuOpen = false }
        }
    }

    /// Changes the game language.
    func setLanguage(_ code: String) { gameData.language = code; onLanguageChange?(code) }

    /// Creates the soft glow texture used by effects.
    func makeGlow() -> MTLTexture {
        let size = 64
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 1), CGColor(red: 1, green: 1, blue: 1, alpha: 0.45), CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray, locations: [0, 0.35, 1])!
        context.drawRadialGradient(grad, startCenter: CGPoint(x: size / 2, y: size / 2), startRadius: 0, endCenter: CGPoint(x: size / 2, y: size / 2), endRadius: CGFloat(size / 2), options: [])
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: size, height: size, mipmapped: false)
        let texture = renderer.device.makeTexture(descriptor: td)!
        let source = context.data!.bindMemory(to: UInt8.self, capacity: size * size * 4)
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        for i in 0..<(size * size) { pixels[i * 4 + 3] = source[i * 4 + 3] }
        texture.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0, withBytes: pixels, bytesPerRow: size * 4)
        return texture
    }

    /// Creates a background particle.
    func spawn(_ ember: Bool, initial: Bool) -> Particle {
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
    func drawParticles(_ dt: Float) {
        for i in particles.indices {
            var particle = particles[i]
            particle.life += dt
            if particle.life > particle.max { particle = spawn(particle.ember, initial: false) }
            if particle.ember { particle.v.x += sin(time * 2 + Float(i)) * 0.6 }
            particle.p += (particle.v + SIMD2(sin(time * 0.3 + Float(i)) * 1.5, 0)) * dt
            particles[i] = particle
            let fade = sin(Float.pi * min(1, particle.life / particle.max))
            let alpha = particle.a * fade * (particle.ember ? (0.7 + 0.3 * sin(time * 17 + Float(i) * 3)) : 1)
            let size = particle.size * 2.4 * (particle.ember ? 1 : particle.depth)
            let pos = particle.p - smoothMouse * particle.depth * SIMD2(8, 6)
            let col = particle.ember ? RGBA(r: 1, g: 0.6, b: 0.25, a: alpha) : RGBA(r: 1, g: 0.93, b: 0.8, a: alpha)
            renderer.quad(glow, R(pos.x - size / 2, pos.y - size / 2, size, size), color: col)
        }
    }

    /// Dimmed menu background used by secondary screens.
    func drawMenuBackground(_ dt: Float, dim: Float) {
        smoothMouse += (mouseNorm - smoothMouse) * min(1, dt * 2.5)
        renderer.titleBackground("img/start_bg.jpg", time: time, mouse: smoothMouse * 0.5, regions: Scene.regions, glints: glints, candles: candles)
        renderer.rect(R(0, 0, virtualWidth, virtualHeight), RGBA(r: 0.02, g: 0.015, b: 0.01, a: dim))
        drawParticles(dt)
    }
}

// Start menu, faction and deck selection, and the read-only deck preview.
import Foundation


/// Smoothstep easing used for UI animations.
func ease(_ t: Float) -> Float { let x = max(0, min(1, t)); return x * x * (3 - 2 * x) }

/// Menu and deck screens.
extension Scene {
    /// Dark translucent panel with a gold frame.
    func glassPanel(_ box: R, alpha: Float = 0.78) {
        renderer.gradient(box, RGBA(r: 0.10, g: 0.075, b: 0.045, a: alpha), RGBA(r: 0.04, g: 0.03, b: 0.02, a: alpha + 0.08), steps: 10)
        renderer.gradient(R(box.x, box.y, box.w, min(60, box.h * 0.25)), RGBA(r: 1, g: 0.9, b: 0.7, a: 0.06), RGBA(r: 1, g: 0.9, b: 0.7, a: 0), steps: 6)
        renderer.frame(box, RGBA.goldDark.alpha(0.55), 1.5)
    }
    /// Decorative gold divider line.
    func goldDivider(_ x: Float, _ y: Float, _ width: Float) {
        renderer.gradient(R(x, y, width / 2, 1.5), RGBA.goldDark.alpha(0), RGBA.gold.alpha(0.8))
        renderer.rect(R(x, y, width / 2, 1.5), RGBA.goldDark.alpha(0.0))
        renderer.quad(renderer.white, R(x + width / 2 - 4, y - 3.5, 8, 8), color: RGBA.gold, rotation: .pi / 4)
        renderer.rect(R(x + width / 2 + 6, y, width / 2 - 6, 1.5), RGBA.goldDark.alpha(0.45))
    }
    /// Card drawn with a hover glow, used in menus.
    func drawLiveCard(_ card: Card, _ baseRect: R, glow: Float = 1) {
        let bob = sin(time * 1.3) * 6
        let cardRect = R(baseRect.x, baseRect.y + bob, baseRect.w, baseRect.h)
        renderer.quad(glowTex, R(cardRect.x - 70, cardRect.y - 60, cardRect.w + 140, cardRect.h + 120), color: RGBA(r: 1, g: 0.72, b: 0.3, a: 0.28 * glow * (0.85 + 0.15 * sin(time * 2))))
        renderer.rect(R(cardRect.x + 14, cardRect.y + 22, cardRect.w, cardRect.h), RGBA.black.alpha(0.45))
        drawCardLarge(card, cardRect)
        renderer.clip(cardRect)
        let mx = (mouse.x - cardRect.x) / cardRect.w
        let x = cardRect.x + cardRect.w * (0.2 + 0.6 * max(0, min(1, mx))) + sin(time * 0.6) * 20
        renderer.quad(renderer.white, R(x - 30, cardRect.y - 60, 60, cardRect.h + 120), color: RGBA(r: 1, g: 0.95, b: 0.85, a: 0.07), rotation: 0.4)
        renderer.clip(nil)
        renderer.frame(cardRect.inset(-2), RGBA.gold.alpha(0.55 + 0.25 * sin(time * 2)), 2)
    }

    /// Deck selection flow: start step, faction step and deck step.
    func drawDeckSelect(_ dt: Float) {
        drawMenuBackground(dt, dim: 0.66)
        deckSwitchT = min(1, deckSwitchT + dt / 0.5)
        if let p = previewDeck, p < allDecks.count { drawDeckPreview(p, dt) }
        else if deckStage < 0 { drawStartStep(dt) } else if deckStage == 0 { drawFactionStep(dt) } else { drawDeckStep(dt) }
        if previewDeck == nil { languageToggle(y: 1018) }
        if let h = builderHover { drawPreviewRight(h, x: previewDeck != nil ? 110 : 1580)  }
        builderHover = nil
    }
    /// Header shown above each deck selection step.
    func stepHeader(_ step: Int, _ title: String, _ hint: String) {
        renderer.text(L("Step") + " \(step) / 2", .ui(16, bold: true), x: 960, y: 22, color: RGBA.gold.alpha(0.8), align: .center)
        renderer.text(title, .gwent(52), x: 960, y: 44, color: RGBA.gold, align: .center)
        renderer.text(hint, .serif(19, italic: true), x: 960, y: 112, color: .gray(0.85), align: .center)
    }

    /// First step: My deck, Career or Choose a faction.
    func drawStartStep(_ dt: Float) {
        renderer.text(L("How do you want to play?"), .gwent(52), x: 960, y: 44, color: RGBA.gold, align: .center)
        renderer.text(L("Play your own deck with one click, or choose a faction."), .serif(19, italic: true), x: 960, y: 112, color: .gray(0.85), align: .center)
        goldButton(R(40, 24, 190, 50), "‹  " + L("Back"), font: .serif(22, bold: true)) { [weak self] in self?.screen = .title }
        let a = ease(deckSwitchT * 1.4)
        let myDeckPanel = R(110, 170 + (1 - a) * 24, 540, 780)
        let hovered = myDeckPanel.contains(mouse)
        if hovered { renderer.quad(glowTex, R(myDeckPanel.x - 50, myDeckPanel.y - 50, myDeckPanel.w + 100, myDeckPanel.h + 100), color: RGBA(r: 1, g: 0.72, b: 0.3, a: 0.25)) }
        glassPanel(myDeckPanel, alpha: 0.75 * a)
        renderer.frame(myDeckPanel, RGBA.gold.alpha(hovered ? 0.9 : 0.4), 1.5)
        renderer.text("★ " + L("My deck"), .gwent(40), x: myDeckPanel.mid.x, y: myDeckPanel.y + 26, color: RGBA.gold.alpha(a), align: .center)
        if let i = favoriteDeckIndex {
            let d = allDecks[i]
            if let lc = gameData.cards[d.leader] {
                let cardRect = R(myDeckPanel.mid.x - 135, myDeckPanel.y + 90, 270, 270 / 0.697)
                drawCardLarge(Card(lc, owner: nil), cardRect)
                if cardRect.contains(mouse) { builderHover = Card(lc, owner: nil) }
            }
            let sub = i >= gameData.decks.count ? gameData.ui(d.title) : gameData.factionName(d.faction)
            renderer.text(sub, .serif(20, bold: true), x: myDeckPanel.mid.x, y: myDeckPanel.y + 90 + 270 / 0.697 + 14, color: RGBA.white.alpha(a), maxWidth: myDeckPanel.w - 60, align: .center)
            goldButton(R(myDeckPanel.x + 70, myDeckPanel.y + myDeckPanel.h - 130, myDeckPanel.w - 140, 64), L("Play my deck"), font: .serif(26, bold: true)) { [weak self] in
                self?.myDeckIndex = i; self?.startGame(with: d)
            }
            smallLink(R(myDeckPanel.x + 70, myDeckPanel.y + myDeckPanel.h - 56, (myDeckPanel.w - 140) / 2, 32), L("View cards")) { [weak self] in
                self?.selFaction = d.faction; self?.deckStage = 1; self?.previewDeck = i; self?.previewScroll = 0; self?.previewTarget = 0; self?.deckSwitchT = 0 }
            smallLink(R(myDeckPanel.mid.x, myDeckPanel.y + myDeckPanel.h - 56, (myDeckPanel.w - 140) / 2, 32), L("Change deck")) { [weak self] in self?.deckStage = 0; self?.deckSwitchT = 0 }
        } else {
            renderer.text("☆", .gwent(140), x: myDeckPanel.mid.x, y: myDeckPanel.y + 150, color: RGBA.gold.alpha(0.5 * a), align: .center)
            renderer.text(L("You haven't picked your deck yet."), .serif(24, bold: true), x: myDeckPanel.mid.x, y: myDeckPanel.y + 360, color: RGBA.white.alpha(a), maxWidth: myDeckPanel.w - 80, align: .center)
            renderer.text(L("Choose a faction, then click “☆ Set as my deck” under the deck you like. From then on you can play it with one click."),
                   .ui(18), x: myDeckPanel.mid.x, y: myDeckPanel.y + 410, color: RGBA.gray(0.85, a), maxWidth: myDeckPanel.w - 100, align: .center)
            goldButton(R(myDeckPanel.x + 70, myDeckPanel.y + myDeckPanel.h - 130, myDeckPanel.w - 140, 64), L("Pick your deck"), font: .serif(24, bold: true)) { [weak self] in self?.deckStage = 0; self?.deckSwitchT = 0 }
        }
        let M = R(690, 170 + (1 - ease(deckSwitchT * 1.4 - 0.1)) * 24, 540, 780)
        let hovM = M.contains(mouse)
        if hovM { renderer.quad(glowTex, R(M.x - 50, M.y - 50, M.w + 100, M.h + 100), color: RGBA(r: 1, g: 0.72, b: 0.3, a: 0.25)) }
        glassPanel(M, alpha: 0.75 * a)
        renderer.frame(M, RGBA.gold.alpha(hovM ? 0.9 : 0.4), 1.5)
        renderer.text("⚔ " + L("Career"), .gwent(40), x: M.mid.x, y: M.y + 26, color: RGBA.gold.alpha(a), align: .center)
        let car = Career.shared
        if car.active {
            renderer.image("img/icons/deck_shield_\(car.faction).png", R(M.mid.x - 60, M.y + 110, 120, 134), color: .white.alpha(a))
            renderer.text(gameData.factionName(car.faction), .gwent(30), x: M.mid.x, y: M.y + 262, color: RGBA.gold.alpha(a), align: .center)
            let cc = car.chapter(car.currentChapter)
            renderer.text(L("Chapter") + " \(car.currentChapter + 1)/\(car.chapterCount): " + cc.title, .serif(22, bold: true), x: M.mid.x, y: M.y + 320, color: RGBA.white.alpha(a), maxWidth: M.w - 60, align: .center)
            renderer.text(L("Opponents defeated") + ": \(car.beaten.count)/\(car.totalFights)", .ui(18), x: M.mid.x, y: M.y + 362, color: RGBA.gray(0.85, a), align: .center)
            let pr = R(M.x + 70, M.y + 400, M.w - 140, 8)
            renderer.rect(pr, RGBA.white.alpha(0.12)); renderer.rect(R(pr.x, pr.y, pr.w * min(1, Float(car.beaten.count) / Float(car.totalFights)), pr.h), RGBA.gold)
        } else {
            renderer.text("⚔", .gwent(130), x: M.mid.x, y: M.y + 130, color: RGBA.gold.alpha(0.5 * a), align: .center)
            renderer.text(L("Start with weak cards, win new ones and defeat boss after boss. Every career is generated anew."),
                   .ui(18), x: M.mid.x, y: M.y + 340, color: RGBA.gray(0.85, a), maxWidth: M.w - 90, align: .center)
        }
        goldButton(R(M.x + 70, M.y + M.h - 130, M.w - 140, 64), car.active ? L("Continue career") : L("Start career"),
                   font: .serif(24, bold: true)) { [weak self] in self?.careerChapter = nil; self?.deckSwitchT = 0; self?.screen = .career }
        let Rr = R(1270, 170 + (1 - ease(deckSwitchT * 1.4 - 0.2)) * 24, 540, 780)
        let hovR = Rr.contains(mouse)
        if hovR { renderer.quad(glowTex, R(Rr.x - 50, Rr.y - 50, Rr.w + 100, Rr.h + 100), color: RGBA(r: 1, g: 0.72, b: 0.3, a: 0.25)) }
        glassPanel(Rr, alpha: 0.75 * a)
        renderer.frame(Rr, RGBA.gold.alpha(hovR ? 0.9 : 0.4), 1.5)
        renderer.text(L("Choose a faction"), .gwent(40), x: Rr.mid.x, y: Rr.y + 26, color: RGBA.gold.alpha(a), align: .center)
        let facs = DeckBuilder.factionsOrder
        for (k, f) in facs.enumerated() {
            let col = k % 5, row = k / 5
            let s = R(Rr.x + 34 + Float(col) * 96, Rr.y + 110 + Float(row) * 116, 78, 87)
            renderer.image("img/icons/deck_shield_\(f).png", s, color: .white.alpha(a * (hovR ? 1 : 0.85)))
        }
        renderer.text(L("Pick one of 15 factions and one of its decks, or build your own."),
               .ui(18), x: Rr.mid.x, y: Rr.y + 520, color: RGBA.gray(0.85, a), maxWidth: Rr.w - 100, align: .center)
        goldButton(R(Rr.x + 70, Rr.y + Rr.h - 130, Rr.w - 140, 64), L("Choose a faction"), font: .serif(26, bold: true)) { [weak self] in self?.deckStage = 0; self?.deckSwitchT = 0 }
    }
    /// Faction grid.
    func drawFactionStep(_ dt: Float) {
        stepHeader(1, L("Choose a faction"), L("Click the faction you want to play."))
        goldButton(R(40, 24, 190, 50), "‹  " + L("Back"), font: .serif(22, bold: true)) { [weak self] in self?.deckStage = -1; self?.deckSwitchT = 0 }
        let facs = DeckBuilder.factionsOrder
        let cols = 5, tw: Float = 340, th: Float = 250, gx: Float = 22, gy: Float = 22
        let x0 = 960 - (Float(cols) * tw + Float(cols - 1) * gx) / 2, y0: Float = 160
        for (i, f) in facs.enumerated() {
            let col = i % cols, row = i / cols
            let k = ease((deckSwitchT * 1.6) - Float(i) * 0.04)
            let base = R(x0 + Float(col) * (tw + gx), y0 + Float(row) * (th + gy) + (1 - k) * 24, tw, th)
            let hovered = base.contains(mouse)
            let hk = cardHover["fac2_" + f, default: 0]
            cardHover["fac2_" + f] = hk + ((hovered ? 1 : 0) - hk) * min(1, dt * 10)
            let h = cardHover["fac2_" + f, default: 0]
            let t = R(base.x, base.y - 6 * h, base.w, base.h)
            if h > 0.02 { renderer.quad(glowTex, R(t.x - 40, t.y - 40, t.w + 80, t.h + 80), color: RGBA(r: 1, g: 0.72, b: 0.3, a: 0.32 * h)) }
            glassPanel(t, alpha: 0.72 * k)
            renderer.frame(t, RGBA.gold.alpha(0.25 + 0.6 * h), 1.5 + h)
            renderer.image("img/icons/deck_shield_\(f).png", R(t.x + 22, t.y + 22, 74, 82), color: .white.alpha(k))
            let nameHeight = renderer.text(gameData.factionName(f), .gwent(30), x: t.x + 112, y: t.y + 30, color: RGBA.gold.alpha(k), maxWidth: t.w - 126).h
            let n = allDecks.filter { $0.faction == f }.count
            renderer.text(n == 1 ? L("1 deck") : "\(n) " + L("decks"), .ui(15), x: t.x + 112, y: t.y + 34 + nameHeight, color: RGBA.gray(0.7, k))
            renderer.text(gameData.factionDesc(f), .ui(16), x: t.x + 22, y: t.y + 122, color: RGBA(r: 0.92, g: 0.86, b: 0.72, a: k), maxWidth: t.w - 44)
            button(t) { [weak self] in
                guard let s = self else { return }
                s.selFaction = f; s.deckStage = 1; s.deckSwitchT = 0; s.audio.play("card", volume: 0.5)
            }
        }
    }
    /// Premade and custom decks of the chosen faction.
    func drawDeckStep(_ dt: Float) {
        let f = selFaction
        stepHeader(2, L("Choose a deck"), gameData.factionName(f) + " — " + L("click “Play this deck” under the deck you want."))
        goldButton(R(40, 24, 220, 50), "‹  " + L("Factions"), font: .serif(22, bold: true)) { [weak self] in self?.deckStage = 0; self?.deckSwitchT = 0 }
        let all = allDecks
        let idx = all.indices.filter { all[$0].faction == f }
        let n = idx.count + 1
        let gap: Float = 26
        let textWidth = min(300, (1780 - gap * Float(n - 1)) / Float(n))
        let ch = textWidth / 0.697
        let x0 = 960 - (Float(n) * textWidth + Float(n - 1) * gap) / 2, y0: Float = 170
        for (k, i) in idx.enumerated() {
            let d = all[i]
            let custom = i >= gameData.decks.count
            let a = ease((deckSwitchT * 1.5) - Float(k) * 0.08)
            let x = x0 + Float(k) * (textWidth + gap)
            let cardR = R(x, y0 + (1 - a) * 30, textWidth, ch)
            let tile = R(x - 10, cardR.y - 10, textWidth + 20, ch + 250)
            let hovered = tile.contains(mouse)
            let key = "deck_\(i)"
            let hk = cardHover[key, default: 0]
            cardHover[key] = hk + ((hovered ? 1 : 0) - hk) * min(1, dt * 10)
            let h = cardHover[key, default: 0]
            if h > 0.02 { renderer.quad(glowTex, R(tile.x - 50, tile.y - 50, tile.w + 100, tile.h + 100), color: RGBA(r: 1, g: 0.72, b: 0.3, a: 0.3 * h)) }
            glassPanel(tile, alpha: 0.6 * a)
            if let lc = gameData.cards[d.leader] {
                let lift = R(cardR.x, cardR.y - 8 * h, cardR.w, cardR.h)
                drawCardLarge(Card(lc, owner: nil), lift)
                renderer.rect(lift, RGBA.black.alpha(1 - a))
                if lift.contains(mouse) { builderHover = Card(lc, owner: nil) }
            }
            var ty = cardR.y + ch + 14
            let title = gameData.ui(d.title)
            if custom || title != gameData.factionName(f) {
                ty += renderer.text((custom ? "★ " : "") + title, .serif(20, bold: true), x: x, y: ty, color: RGBA.white.alpha(a), maxWidth: textWidth).h + 4
            }
            let desc = d.description.isEmpty ? gameData.abilityDesc(gameData.cards[d.leader]?.abilities.last ?? "") : gameData.ui(d.description)
            renderer.clip(R(x, ty, textWidth, 100))
            renderer.text(desc, .ui(16), x: x, y: ty, color: RGBA(r: 0.92, g: 0.86, b: 0.72, a: a), maxWidth: textWidth)
            renderer.clip(nil)
            var units = 0, total = 0
            for (ck, cn) in d.cards { total += cn; if gameData.cards[ck]?.isUnit == true { units += cn } }
            renderer.text("\(total) " + L("cards") + " · \(units) " + L("units"), .ui(14), x: x, y: tile.y + tile.h - 92, color: RGBA.gold.alpha(0.75 * a))
            goldButton(R(x, tile.y + tile.h - 66, textWidth, 52), L("Play this deck"), font: .serif(textWidth < 260 ? 18 : 21, bold: true)) { [weak self] in
                self?.myDeckIndex = i; self?.startGame(with: d)
            }
            let bw = (textWidth - 8) / 2, by = tile.y + tile.h + 10, fs: Float = textWidth < 260 ? 15 : 17
            goldButton(R(x, by, bw, 42), L("View cards"), font: .serif(fs, bold: true)) { [weak self] in
                self?.previewDeck = i; self?.previewScroll = 0; self?.previewTarget = 0; self?.deckSwitchT = 0; self?.audio.play("card", volume: 0.5) }
            goldButton(R(x + bw + 8, by, bw, 42), L("Edit deck"), font: .serif(fs, bold: true)) { [weak self] in
                guard let s = self else { return }; s.builder.load(d, customIndex: custom ? i - s.gameData.decks.count : nil); s.screen = .builder }
            let fav = favoriteDeckIndex == i
            let favW = custom ? bw : textWidth
            let favR = R(x, by + 50, favW, 42)
            if fav { renderer.rect(favR, RGBA(r: 0.55, g: 0.4, b: 0.1, a: 0.55)) }
            goldButton(favR, fav ? "★ " + L("My deck") : "☆ " + L("Set as mine"), font: .serif(fs, bold: true)) { [weak self] in
                guard let s = self else { return }; s.favoriteDeckIndex = fav ? nil : i; s.audio.play("card", volume: 0.5) }
            if custom {
                goldButton(R(x + bw + 8, by + 50, bw, 42), L("Delete deck"), font: .serif(fs, bold: true)) { [weak self] in
                    guard let s = self else { return }
                    var cd = DeckBuilder.loadCustom(); let ci = i - s.gameData.decks.count
                    if ci >= 0 && ci < cd.count { cd.remove(at: ci); DeckBuilder.saveCustom(cd) }
                    s.customDecks = cd
                }
            }
        }
        let x = x0 + Float(idx.count) * (textWidth + gap)
        let a = ease((deckSwitchT * 1.5) - Float(idx.count) * 0.08)
        let tile = R(x - 10, y0 - 10 + (1 - a) * 30, textWidth + 20, ch + 250)
        let hovered = tile.contains(mouse)
        glassPanel(tile, alpha: 0.45 * a)
        renderer.frame(tile.inset(14), RGBA.gold.alpha((hovered ? 0.9 : 0.35) * a), 1.5)
        renderer.text("+", .gwent(120), x: tile.mid.x, y: tile.y + ch * 0.28, color: RGBA.gold.alpha((hovered ? 1 : 0.7) * a), align: .center)
        renderer.text(L("Custom deck"), .serif(22, bold: true), x: tile.mid.x, y: tile.y + ch * 0.62, color: RGBA.white.alpha(a), maxWidth: textWidth - 20, align: .center)
        renderer.text(L("Build a deck from this faction's cards in the deck builder."), .ui(15), x: tile.mid.x, y: tile.y + ch * 0.62 + 34, color: RGBA.gray(0.75, a), maxWidth: textWidth - 30, align: .center)
        button(tile) { [weak self] in guard let s = self else { return }; s.builder.newDeck(f); s.screen = .builder }
    }
    /// Text button drawn as an underlined link.
    func smallLink(_ box: R, _ title: String, _ action: @escaping () -> Void) {
        let key = "link_" + title
        let hovered = box.contains(mouse)
        let k = cardHover[key, default: 0]
        cardHover[key] = k + ((hovered ? 1 : 0) - k) * 0.25
        let kk = cardHover[key, default: 0]
        let textHeight = renderer.measure(title, .serif(21, bold: true)).h
        renderer.text(title, .serif(21, bold: true), x: box.mid.x, y: box.mid.y - textHeight / 2, color: RGBA(r: 0.95, g: 0.82 + 0.18 * kk, b: 0.5 + 0.5 * kk, a: 1), align: .center)
        let w = renderer.measure(title, .serif(21, bold: true)).w * kk
        renderer.rect(R(box.mid.x - w / 2, box.mid.y + textHeight / 2 + 2, w, 1.5), RGBA.gold)
        button(box, action)
    }
    /// Large card preview with its description, shown on the right.
    func drawPreviewRight(_ card: Card, x: Float = 1580) {
        let cardRect = R(x, 250, 300, 431)
        renderer.rect(cardRect.inset(-6), RGBA.black.alpha(0.6))
        drawCardLarge(card, cardRect)
        var lines: [(String, String)] = []
        if card.data.isLeader { if let a = card.data.abilities.last { lines.append((L("Leader Ability"), gameData.abilityDesc(a))) } }
        else {
            for a in card.data.abilities where a != "hero" { lines.append((gameData.abilityName(a), gameData.abilityDesc(a))) }
            if card.hero { lines.append((L("Hero"), gameData.abilityDesc("hero"))) }
        }
        var y = cardRect.y + cardRect.h + 14
        for (n, d) in lines.prefix(3) {
            let b = R(cardRect.x - 6, y, cardRect.w + 12, renderer.measure(n, .serif(17, bold: true), maxWidth: cardRect.w - 8).h + renderer.measure(d, .ui(15), maxWidth: cardRect.w - 8).h + 14)
            renderer.rect(b, RGBA(r: 0.06, g: 0.05, b: 0.03, a: 0.94)); renderer.frame(b, RGBA.goldDark.alpha(0.6), 1)
            let h1 = renderer.text(n, .serif(17, bold: true), x: cardRect.x + 2, y: y + 6, color: RGBA.gold, maxWidth: cardRect.w - 8).h
            renderer.text(d, .ui(15), x: cardRect.x + 2, y: y + 6 + h1, color: .gray(0.9), maxWidth: cardRect.w - 8)
            y += b.h + 6
        }
    }



    /// Read-only list of a deck's cards.
    func drawDeckPreview(_ i: Int, _ dt: Float) {
        let d = allDecks[i]
        let a = ease(deckSwitchT * 1.4)
        renderer.text(L("Deck cards"), .gwent(52), x: 960, y: 34, color: RGBA.gold.alpha(a), align: .center)
        renderer.text(gameData.factionName(d.faction) + (gameData.ui(d.title) != gameData.factionName(d.faction) || i >= gameData.decks.count ? " — " + gameData.ui(d.title) : ""),
               .serif(20, italic: true), x: 960, y: 102, color: RGBA.gray(0.85, a), align: .center)
        goldButton(R(40, 24, 200, 50), "‹  " + L("Decks"), font: .serif(22, bold: true)) { [weak self] in self?.previewDeck = nil; self?.deckSwitchT = 0 }
        let left = R(60, 150, 400, 830)
        glassPanel(left, alpha: 0.7 * a)
        if let lc = gameData.cards[d.leader] {
            let cardRect = R(left.x + 60, left.y + 30 + (1 - a) * 20, 280, 280 / 0.697)
            drawCardLarge(Card(lc, owner: nil), cardRect)
            if cardRect.contains(mouse) { builderHover = Card(lc, owner: nil) }
        }
        var list: [CardData] = []; var cnt: [String: Int] = [:]
        var units = 0, total = 0, specials = 0, heroes = 0, power = 0
        for (k, n) in d.cards {
            guard let c = gameData.cards[k] else { continue }
            if cnt[k] == nil { list.append(c) }
            cnt[k, default: 0] += n; total += n
            if c.isUnit { units += n; power += c.strength * n; if c.abilities.contains("hero") { heroes += n } } else { specials += n }
        }
        /// Grouping order for the preview list.
        func kind(_ cardData: CardData) -> Int { cardData.isWeather ? 1 : cardData.isSpecial ? 0 : 2 }
        list.sort { kind($0) != kind($1) ? kind($0) < kind($1) : ($0.strength != $1.strength ? $0.strength > $1.strength : $0.name < $1.name) }
        var y = left.y + 30 + 280 / 0.697 + 24
        for (t, v) in [(L("Total cards"), total), (L("Units"), units), (L("Special cards"), specials),
                       (L("Heroes"), heroes), (L("Total unit strength"), power)] {
            renderer.text(t, .ui(17), x: left.x + 30, y: y, color: RGBA.gray(0.8, a))
            renderer.text("\(v)", .ui(17, bold: true), x: left.x + left.w - 30, y: y, color: RGBA.gold.alpha(a), align: .right)
            y += 30
        }
        let fav = favoriteDeckIndex == i
        smallLink(R(left.x + 30, left.y + left.h - 122, left.w - 60, 32), fav ? "★ " + L("My deck") : "☆ " + L("Set as my deck")) { [weak self] in
            guard let s = self else { return }; s.favoriteDeckIndex = fav ? nil : i; s.audio.play("card", volume: 0.5) }
        goldButton(R(left.x + 30, left.y + left.h - 76, left.w - 60, 56), L("Play this deck")) { [weak self] in
            self?.previewDeck = nil; self?.myDeckIndex = i; self?.startGame(with: d)
        }
        let area = R(490, 150, 1370, 830)
        glassPanel(area, alpha: 0.55 * a)
        builderGrid(list, in: area.inset(6), scroll: &previewScroll, target: &previewTarget, dt: dt, cardW: 150, count: { cnt[$0.key] ?? 0 }) { _, _ in }
        renderer.text(L("Hover a card to see its description. Scroll with the mouse wheel."),
               .serif(17, italic: true), x: area.mid.x, y: area.y + area.h + 14, color: RGBA.gray(0.7, a), align: .center)
    }


}

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
        let relativeX = (mouse.x - cardRect.x) / cardRect.w
        let x = cardRect.x + cardRect.w * (0.2 + 0.6 * max(0, min(1, relativeX))) + sin(time * 0.6) * 20
        renderer.quad(renderer.white, R(x - 30, cardRect.y - 60, 60, cardRect.h + 120), color: RGBA(r: 1, g: 0.95, b: 0.85, a: 0.07), rotation: 0.4)
        renderer.clip(nil)
        renderer.frame(cardRect.inset(-2), RGBA.gold.alpha(0.55 + 0.25 * sin(time * 2)), 2)
    }

    /// Deck selection flow: start step, faction step and deck step.
    func drawDeckSelect(_ dt: Float) {
        drawMenuBackground(dt, dim: 0.66)
        deckSwitchT = min(1, deckSwitchT + dt / 0.5)
        if let previewIndex = previewDeck, previewIndex < allDecks.count { drawDeckPreview(previewIndex, dt) }
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
        let progress = ease(deckSwitchT * 1.4)
        let myDeckPanel = R(110, 170 + (1 - progress) * 24, 540, 780)
        let hovered = myDeckPanel.contains(mouse)
        if hovered { renderer.quad(glowTex, R(myDeckPanel.x - 50, myDeckPanel.y - 50, myDeckPanel.w + 100, myDeckPanel.h + 100), color: RGBA(r: 1, g: 0.72, b: 0.3, a: 0.25)) }
        glassPanel(myDeckPanel, alpha: 0.75 * progress)
        renderer.frame(myDeckPanel, RGBA.gold.alpha(hovered ? 0.9 : 0.4), 1.5)
        renderer.text("★ " + L("My deck"), .gwent(40), x: myDeckPanel.mid.x, y: myDeckPanel.y + 26, color: RGBA.gold.alpha(progress), align: .center)
        if let i = favoriteDeckIndex {
            let deck = allDecks[i]
            if let cardData = gameData.cards[deck.leader] {
                let cardRect = R(myDeckPanel.mid.x - 135, myDeckPanel.y + 90, 270, 270 / 0.697)
                drawCardLarge(Card(cardData, owner: nil), cardRect)
                if cardRect.contains(mouse) { builderHover = Card(cardData, owner: nil) }
            }
            let subtitle = i >= gameData.decks.count ? gameData.ui(deck.title) : gameData.factionName(deck.faction)
            renderer.text(subtitle, .serif(20, bold: true), x: myDeckPanel.mid.x, y: myDeckPanel.y + 90 + 270 / 0.697 + 14, color: RGBA.white.alpha(progress), maxWidth: myDeckPanel.w - 60, align: .center)
            goldButton(R(myDeckPanel.x + 70, myDeckPanel.y + myDeckPanel.h - 130, myDeckPanel.w - 140, 64), L("Play my deck"), font: .serif(26, bold: true)) { [weak self] in
                self?.myDeckIndex = i; self?.startGame(with: deck)
            }
            smallLink(R(myDeckPanel.x + 70, myDeckPanel.y + myDeckPanel.h - 56, (myDeckPanel.w - 140) / 2, 32), L("View cards")) { [weak self] in
                self?.selFaction = deck.faction; self?.deckStage = 1; self?.previewDeck = i; self?.previewScroll = 0; self?.previewTarget = 0; self?.deckSwitchT = 0 }
            smallLink(R(myDeckPanel.mid.x, myDeckPanel.y + myDeckPanel.h - 56, (myDeckPanel.w - 140) / 2, 32), L("Change deck")) { [weak self] in self?.deckStage = 0; self?.deckSwitchT = 0 }
        } else {
            renderer.text("☆", .gwent(140), x: myDeckPanel.mid.x, y: myDeckPanel.y + 150, color: RGBA.gold.alpha(0.5 * progress), align: .center)
            renderer.text(L("You haven't picked your deck yet."), .serif(24, bold: true), x: myDeckPanel.mid.x, y: myDeckPanel.y + 360, color: RGBA.white.alpha(progress), maxWidth: myDeckPanel.w - 80, align: .center)
            renderer.text(L("Choose a faction, then click “☆ Set as my deck” under the deck you like. From then on you can play it with one click."),
                   .ui(18), x: myDeckPanel.mid.x, y: myDeckPanel.y + 410, color: RGBA.gray(0.85, progress), maxWidth: myDeckPanel.w - 100, align: .center)
            goldButton(R(myDeckPanel.x + 70, myDeckPanel.y + myDeckPanel.h - 130, myDeckPanel.w - 140, 64), L("Pick your deck"), font: .serif(24, bold: true)) { [weak self] in self?.deckStage = 0; self?.deckSwitchT = 0 }
        }
        let M = R(690, 170 + (1 - ease(deckSwitchT * 1.4 - 0.1)) * 24, 540, 780)
        let hovM = M.contains(mouse)
        if hovM { renderer.quad(glowTex, R(M.x - 50, M.y - 50, M.w + 100, M.h + 100), color: RGBA(r: 1, g: 0.72, b: 0.3, a: 0.25)) }
        glassPanel(M, alpha: 0.75 * progress)
        renderer.frame(M, RGBA.gold.alpha(hovM ? 0.9 : 0.4), 1.5)
        renderer.text("⚔ " + L("Career"), .gwent(40), x: M.mid.x, y: M.y + 26, color: RGBA.gold.alpha(progress), align: .center)
        let career = Career.shared
        if career.active {
            renderer.image("img/icons/deck_shield_\(career.faction).png", R(M.mid.x - 60, M.y + 110, 120, 134), color: .white.alpha(progress))
            renderer.text(gameData.factionName(career.faction), .gwent(30), x: M.mid.x, y: M.y + 262, color: RGBA.gold.alpha(progress), align: .center)
            let chapterInfo = career.chapter(career.currentChapter)
            renderer.text(L("Chapter") + " \(career.currentChapter + 1)/\(career.chapterCount): " + chapterInfo.title, .serif(22, bold: true), x: M.mid.x, y: M.y + 320, color: RGBA.white.alpha(progress), maxWidth: M.w - 60, align: .center)
            renderer.text(L("Opponents defeated") + ": \(career.beaten.count)/\(career.totalFights)", .ui(18), x: M.mid.x, y: M.y + 362, color: RGBA.gray(0.85, progress), align: .center)
            let area = R(M.x + 70, M.y + 400, M.w - 140, 8)
            renderer.rect(area, RGBA.white.alpha(0.12)); renderer.rect(R(area.x, area.y, area.w * min(1, Float(career.beaten.count) / Float(career.totalFights)), area.h), RGBA.gold)
        } else {
            renderer.text("⚔", .gwent(130), x: M.mid.x, y: M.y + 130, color: RGBA.gold.alpha(0.5 * progress), align: .center)
            renderer.text(L("Start with weak cards, win new ones and defeat boss after boss. Every career is generated anew."),
                   .ui(18), x: M.mid.x, y: M.y + 340, color: RGBA.gray(0.85, progress), maxWidth: M.w - 90, align: .center)
        }
        goldButton(R(M.x + 70, M.y + M.h - 130, M.w - 140, 64), career.active ? L("Continue career") : L("Start career"),
                   font: .serif(24, bold: true)) { [weak self] in self?.careerChapter = nil; self?.deckSwitchT = 0; self?.screen = .career }
        let Rr = R(1270, 170 + (1 - ease(deckSwitchT * 1.4 - 0.2)) * 24, 540, 780)
        let hovR = Rr.contains(mouse)
        if hovR { renderer.quad(glowTex, R(Rr.x - 50, Rr.y - 50, Rr.w + 100, Rr.h + 100), color: RGBA(r: 1, g: 0.72, b: 0.3, a: 0.25)) }
        glassPanel(Rr, alpha: 0.75 * progress)
        renderer.frame(Rr, RGBA.gold.alpha(hovR ? 0.9 : 0.4), 1.5)
        renderer.text(L("Choose a faction"), .gwent(40), x: Rr.mid.x, y: Rr.y + 26, color: RGBA.gold.alpha(progress), align: .center)
        let facs = DeckBuilder.factionsOrder
        for (index, faction) in facs.enumerated() {
            let col = index % 5, row = index / 5
            let area = R(Rr.x + 34 + Float(col) * 96, Rr.y + 110 + Float(row) * 116, 78, 87)
            renderer.image("img/icons/deck_shield_\(faction).png", area, color: .white.alpha(progress * (hovR ? 1 : 0.85)))
        }
        renderer.text(L("Pick one of 15 factions and one of its decks, or build your own."),
               .ui(18), x: Rr.mid.x, y: Rr.y + 520, color: RGBA.gray(0.85, progress), maxWidth: Rr.w - 100, align: .center)
        goldButton(R(Rr.x + 70, Rr.y + Rr.h - 130, Rr.w - 140, 64), L("Choose a faction"), font: .serif(26, bold: true)) { [weak self] in self?.deckStage = 0; self?.deckSwitchT = 0 }
    }
    /// Faction grid.
    func drawFactionStep(_ dt: Float) {
        stepHeader(1, L("Choose a faction"), L("Click the faction you want to play."))
        goldButton(R(40, 24, 190, 50), "‹  " + L("Back"), font: .serif(22, bold: true)) { [weak self] in self?.deckStage = -1; self?.deckSwitchT = 0 }
        let facs = DeckBuilder.factionsOrder
        let cols = 5, tw: Float = 340, th: Float = 250, gx: Float = 22, gy: Float = 22
        let x0 = 960 - (Float(cols) * tw + Float(cols - 1) * gx) / 2, y0: Float = 160
        for (i, faction) in facs.enumerated() {
            let col = i % cols, row = i / cols
            let progress = ease((deckSwitchT * 1.6) - Float(i) * 0.04)
            let base = R(x0 + Float(col) * (tw + gx), y0 + Float(row) * (th + gy) + (1 - progress) * 24, tw, th)
            let hovered = base.contains(mouse)
            let previousHover = cardHover["fac2_" + faction, default: 0]
            cardHover["fac2_" + faction] = previousHover + ((hovered ? 1 : 0) - previousHover) * min(1, dt * 10)
            let hoverAmount = cardHover["fac2_" + faction, default: 0]
            let area = R(base.x, base.y - 6 * hoverAmount, base.w, base.h)
            if hoverAmount > 0.02 { renderer.quad(glowTex, R(area.x - 40, area.y - 40, area.w + 80, area.h + 80), color: RGBA(r: 1, g: 0.72, b: 0.3, a: 0.32 * hoverAmount)) }
            glassPanel(area, alpha: 0.72 * progress)
            renderer.frame(area, RGBA.gold.alpha(0.25 + 0.6 * hoverAmount), 1.5 + hoverAmount)
            renderer.image("img/icons/deck_shield_\(faction).png", R(area.x + 22, area.y + 22, 74, 82), color: .white.alpha(progress))
            let nameHeight = renderer.text(gameData.factionName(faction), .gwent(30), x: area.x + 112, y: area.y + 30, color: RGBA.gold.alpha(progress), maxWidth: area.w - 126).h
            let deckCount = allDecks.filter { $0.faction == faction }.count
            renderer.text(deckCount == 1 ? L("1 deck") : "\(deckCount) " + L("decks"), .ui(15), x: area.x + 112, y: area.y + 34 + nameHeight, color: RGBA.gray(0.7, progress))
            renderer.text(gameData.factionDesc(faction), .ui(16), x: area.x + 22, y: area.y + 122, color: RGBA(r: 0.92, g: 0.86, b: 0.72, a: progress), maxWidth: area.w - 44)
            button(area) { [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.selFaction = faction; strongSelf.deckStage = 1; strongSelf.deckSwitchT = 0; strongSelf.audio.play("card", volume: 0.5)
            }
        }
    }
    /// Premade and custom decks of the chosen faction.
    func drawDeckStep(_ dt: Float) {
        let faction = selFaction
        stepHeader(2, L("Choose a deck"), gameData.factionName(faction) + " — " + L("click “Play this deck” under the deck you want."))
        goldButton(R(40, 24, 220, 50), "‹  " + L("Factions"), font: .serif(22, bold: true)) { [weak self] in self?.deckStage = 0; self?.deckSwitchT = 0 }
        let all = allDecks
        let idx = all.indices.filter { all[$0].faction == faction }
        let tileCount = idx.count + 1
        let gap: Float = 26
        let tileWidth = min(300, (1780 - gap * Float(tileCount - 1)) / Float(tileCount))
        let tileHeight = tileWidth / 0.697
        let x0 = 960 - (Float(tileCount) * tileWidth + Float(tileCount - 1) * gap) / 2, y0: Float = 170
        for (position, i) in idx.enumerated() {
            let deck = all[i]
            let custom = i >= gameData.decks.count
            let progress = ease((deckSwitchT * 1.5) - Float(position) * 0.08)
            let x = x0 + Float(position) * (tileWidth + gap)
            let cardR = R(x, y0 + (1 - progress) * 30, tileWidth, tileHeight)
            let tile = R(x - 10, cardR.y - 10, tileWidth + 20, tileHeight + 250)
            let hovered = tile.contains(mouse)
            let key = "deck_\(i)"
            let previousHover = cardHover[key, default: 0]
            cardHover[key] = previousHover + ((hovered ? 1 : 0) - previousHover) * min(1, dt * 10)
            let hoverAmount = cardHover[key, default: 0]
            if hoverAmount > 0.02 { renderer.quad(glowTex, R(tile.x - 50, tile.y - 50, tile.w + 100, tile.h + 100), color: RGBA(r: 1, g: 0.72, b: 0.3, a: 0.3 * hoverAmount)) }
            glassPanel(tile, alpha: 0.6 * progress)
            if let cardData = gameData.cards[deck.leader] {
                let lift = R(cardR.x, cardR.y - 8 * hoverAmount, cardR.w, cardR.h)
                drawCardLarge(Card(cardData, owner: nil), lift)
                renderer.rect(lift, RGBA.black.alpha(1 - progress))
                if lift.contains(mouse) { builderHover = Card(cardData, owner: nil) }
            }
            var textY = cardR.y + tileHeight + 14
            let title = gameData.ui(deck.title)
            if custom || title != gameData.factionName(faction) {
                textY += renderer.text((custom ? "★ " : "") + title, .serif(20, bold: true), x: x, y: textY, color: RGBA.white.alpha(progress), maxWidth: tileWidth).h + 4
            }
            let desc = deck.description.isEmpty ? gameData.abilityDesc(gameData.cards[deck.leader]?.abilities.last ?? "") : gameData.ui(deck.description)
            renderer.clip(R(x, textY, tileWidth, 100))
            renderer.text(desc, .ui(16), x: x, y: textY, color: RGBA(r: 0.92, g: 0.86, b: 0.72, a: progress), maxWidth: tileWidth)
            renderer.clip(nil)
            var units = 0, total = 0
            for (ck, cn) in deck.cards { total += cn; if gameData.cards[ck]?.isUnit == true { units += cn } }
            renderer.text("\(total) " + L("cards") + " · \(units) " + L("units"), .ui(14), x: x, y: tile.y + tile.h - 92, color: RGBA.gold.alpha(0.75 * progress))
            goldButton(R(x, tile.y + tile.h - 66, tileWidth, 52), L("Play this deck"), font: .serif(tileWidth < 260 ? 18 : 21, bold: true)) { [weak self] in
                self?.myDeckIndex = i; self?.startGame(with: deck)
            }
            let bw = (tileWidth - 8) / 2, by = tile.y + tile.h + 10, fs: Float = tileWidth < 260 ? 15 : 17
            goldButton(R(x, by, bw, 42), L("View cards"), font: .serif(fs, bold: true)) { [weak self] in
                self?.previewDeck = i; self?.previewScroll = 0; self?.previewTarget = 0; self?.deckSwitchT = 0; self?.audio.play("card", volume: 0.5) }
            goldButton(R(x + bw + 8, by, bw, 42), L("Edit deck"), font: .serif(fs, bold: true)) { [weak self] in
                guard let strongSelf = self else { return }; strongSelf.builder.load(deck, customIndex: custom ? i - strongSelf.gameData.decks.count : nil); strongSelf.screen = .builder }
            let isFavorite = favoriteDeckIndex == i
            let favW = custom ? bw : tileWidth
            let favR = R(x, by + 50, favW, 42)
            if isFavorite { renderer.rect(favR, RGBA(r: 0.55, g: 0.4, b: 0.1, a: 0.55)) }
            goldButton(favR, isFavorite ? "★ " + L("My deck") : "☆ " + L("Set as mine"), font: .serif(fs, bold: true)) { [weak self] in
                guard let strongSelf = self else { return }; strongSelf.favoriteDeckIndex = isFavorite ? nil : i; strongSelf.audio.play("card", volume: 0.5) }
            if custom {
                goldButton(R(x + bw + 8, by + 50, bw, 42), L("Delete deck"), font: .serif(fs, bold: true)) { [weak self] in
                    guard let strongSelf = self else { return }
                    var customDecks = DeckBuilder.loadCustom(); let ci = i - strongSelf.gameData.decks.count
                    if ci >= 0 && ci < customDecks.count { customDecks.remove(at: ci); DeckBuilder.saveCustom(customDecks) }
                    strongSelf.customDecks = customDecks
                }
            }
        }
        let x = x0 + Float(idx.count) * (tileWidth + gap)
        let progress = ease((deckSwitchT * 1.5) - Float(idx.count) * 0.08)
        let tile = R(x - 10, y0 - 10 + (1 - progress) * 30, tileWidth + 20, tileHeight + 250)
        let hovered = tile.contains(mouse)
        glassPanel(tile, alpha: 0.45 * progress)
        renderer.frame(tile.inset(14), RGBA.gold.alpha((hovered ? 0.9 : 0.35) * progress), 1.5)
        renderer.text("+", .gwent(120), x: tile.mid.x, y: tile.y + tileHeight * 0.28, color: RGBA.gold.alpha((hovered ? 1 : 0.7) * progress), align: .center)
        renderer.text(L("Custom deck"), .serif(22, bold: true), x: tile.mid.x, y: tile.y + tileHeight * 0.62, color: RGBA.white.alpha(progress), maxWidth: tileWidth - 20, align: .center)
        renderer.text(L("Build a deck from this faction's cards in the deck builder."), .ui(15), x: tile.mid.x, y: tile.y + tileHeight * 0.62 + 34, color: RGBA.gray(0.75, progress), maxWidth: tileWidth - 30, align: .center)
        button(tile) { [weak self] in guard let strongSelf = self else { return }; strongSelf.builder.newDeck(faction); strongSelf.screen = .builder }
    }
    /// Text button drawn as an underlined link.
    func smallLink(_ box: R, _ title: String, _ action: @escaping () -> Void) {
        let key = "link_" + title
        let hovered = box.contains(mouse)
        let previousHover = cardHover[key, default: 0]
        cardHover[key] = previousHover + ((hovered ? 1 : 0) - previousHover) * 0.25
        let hoverAmount = cardHover[key, default: 0]
        let textHeight = renderer.measure(title, .serif(21, bold: true)).h
        renderer.text(title, .serif(21, bold: true), x: box.mid.x, y: box.mid.y - textHeight / 2, color: RGBA(r: 0.95, g: 0.82 + 0.18 * hoverAmount, b: 0.5 + 0.5 * hoverAmount, a: 1), align: .center)
        let w = renderer.measure(title, .serif(21, bold: true)).w * hoverAmount
        renderer.rect(R(box.mid.x - w / 2, box.mid.y + textHeight / 2 + 2, w, 1.5), RGBA.gold)
        button(box, action)
    }
    /// Large card preview with its description, shown on the right.
    func drawPreviewRight(_ card: Card, x: Float = 1580) {
        let cardRect = R(x, 250, 300, 431)
        renderer.rect(cardRect.inset(-6), RGBA.black.alpha(0.6))
        drawCardLarge(card, cardRect)
        var lines: [(String, String)] = []
        if card.data.isLeader { if let lastAbility = card.data.abilities.last { lines.append((L("Leader Ability"), gameData.abilityDesc(lastAbility))) } }
        else {
            for lastAbility in card.data.abilities where lastAbility != "hero" { lines.append((gameData.abilityName(lastAbility), gameData.abilityDesc(lastAbility))) }
            if card.hero { lines.append((L("Hero"), gameData.abilityDesc("hero"))) }
        }
        var y = cardRect.y + cardRect.h + 14
        for (title, description) in lines.prefix(3) {
            let labelBox = R(cardRect.x - 6, y, cardRect.w + 12, renderer.measure(title, .serif(17, bold: true), maxWidth: cardRect.w - 8).h + renderer.measure(description, .ui(15), maxWidth: cardRect.w - 8).h + 14)
            renderer.rect(labelBox, RGBA(r: 0.06, g: 0.05, b: 0.03, a: 0.94)); renderer.frame(labelBox, RGBA.goldDark.alpha(0.6), 1)
            let h1 = renderer.text(title, .serif(17, bold: true), x: cardRect.x + 2, y: y + 6, color: RGBA.gold, maxWidth: cardRect.w - 8).h
            renderer.text(description, .ui(15), x: cardRect.x + 2, y: y + 6 + h1, color: .gray(0.9), maxWidth: cardRect.w - 8)
            y += labelBox.h + 6
        }
    }



    /// Read-only list of a deck's cards.
    func drawDeckPreview(_ i: Int, _ dt: Float) {
        let deck = allDecks[i]
        let progress = ease(deckSwitchT * 1.4)
        renderer.text(L("Deck cards"), .gwent(52), x: 960, y: 34, color: RGBA.gold.alpha(progress), align: .center)
        renderer.text(gameData.factionName(deck.faction) + (gameData.ui(deck.title) != gameData.factionName(deck.faction) || i >= gameData.decks.count ? " — " + gameData.ui(deck.title) : ""),
               .serif(20, italic: true), x: 960, y: 102, color: RGBA.gray(0.85, progress), align: .center)
        goldButton(R(40, 24, 200, 50), "‹  " + L("Decks"), font: .serif(22, bold: true)) { [weak self] in self?.previewDeck = nil; self?.deckSwitchT = 0 }
        let left = R(60, 150, 400, 830)
        glassPanel(left, alpha: 0.7 * progress)
        if let leaderData = gameData.cards[deck.leader] {
            let cardRect = R(left.x + 60, left.y + 30 + (1 - progress) * 20, 280, 280 / 0.697)
            drawCardLarge(Card(leaderData, owner: nil), cardRect)
            if cardRect.contains(mouse) { builderHover = Card(leaderData, owner: nil) }
        }
        var list: [CardData] = []; var cnt: [String: Int] = [:]
        var units = 0, total = 0, specials = 0, heroes = 0, power = 0
        for (key, copies) in deck.cards {
            guard let cardData = gameData.cards[key] else { continue }
            if cnt[key] == nil { list.append(cardData) }
            cnt[key, default: 0] += copies; total += copies
            if cardData.isUnit { units += copies; power += cardData.strength * copies; if cardData.abilities.contains("hero") { heroes += copies } } else { specials += copies }
        }
        /// Grouping order for the preview list.
        func kind(_ cardData: CardData) -> Int { cardData.isWeather ? 1 : cardData.isSpecial ? 0 : 2 }
        list.sort { kind($0) != kind($1) ? kind($0) < kind($1) : ($0.strength != $1.strength ? $0.strength > $1.strength : $0.name < $1.name) }
        var y = left.y + 30 + 280 / 0.697 + 24
        for (label, value) in [(L("Total cards"), total), (L("Units"), units), (L("Special cards"), specials),
                       (L("Heroes"), heroes), (L("Total unit strength"), power)] {
            renderer.text(label, .ui(17), x: left.x + 30, y: y, color: RGBA.gray(0.8, progress))
            renderer.text("\(value)", .ui(17, bold: true), x: left.x + left.w - 30, y: y, color: RGBA.gold.alpha(progress), align: .right)
            y += 30
        }
        let isFavorite = favoriteDeckIndex == i
        smallLink(R(left.x + 30, left.y + left.h - 122, left.w - 60, 32), isFavorite ? "★ " + L("My deck") : "☆ " + L("Set as my deck")) { [weak self] in
            guard let strongSelf = self else { return }; strongSelf.favoriteDeckIndex = isFavorite ? nil : i; strongSelf.audio.play("card", volume: 0.5) }
        goldButton(R(left.x + 30, left.y + left.h - 76, left.w - 60, 56), L("Play this deck")) { [weak self] in
            self?.previewDeck = nil; self?.myDeckIndex = i; self?.startGame(with: deck)
        }
        let area = R(490, 150, 1370, 830)
        glassPanel(area, alpha: 0.55 * progress)
        builderGrid(list, in: area.inset(6), scroll: &previewScroll, target: &previewTarget, dt: dt, cardW: 150, count: { cnt[$0.key] ?? 0 }) { _, _ in }
        renderer.text(L("Hover a card to see its description. Scroll with the mouse wheel."),
               .serif(17, italic: true), x: area.mid.x, y: area.y + area.h + 14, color: RGBA.gray(0.7, progress), align: .center)
    }


}

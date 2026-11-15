// Deck builder screen: card collection, current deck, statistics and the leader picker.
import Foundation
import Metal
import CoreGraphics
import simd

extension Scene {
    /// Deck builder screen: collection on the left, deck on the right, statistics in the middle.
    func drawBuilder(_ builder: DeckBuilder, _ dt: Float) {
        drawMenuBackground(dt, dim: 0.72)
        if leaderPickerOpen { drawLeaderPicker(builder); return }
        renderer.text(L("Deck builder"), .gwent(46), x: 960, y: 14, color: RGBA.gold, align: .center)
        let factionIndex = DeckBuilder.factionsOrder.firstIndex(of: builder.faction) ?? 0
        renderer.quad(glowTex, R(960 - 240, 60, 100, 100), color: RGBA(r: 1, g: 0.75, b: 0.3, a: 0.3))
        renderer.image("img/icons/deck_shield_\(builder.faction).png", R(960 - 212, 78, 44, 48))
        renderer.text(gameData.factionName(builder.faction), .serif(28, bold: true), x: 960 - 155, y: 84, color: .white)
        for (arrows, x) in [(-1, Float(960 - 280)), (1, Float(960 + 240))] where !builder.careerMode {
            let area = R(x, 74, 40, 56)
            renderer.text(arrows < 0 ? "‹" : "›", .serif(60), x: area.mid.x, y: area.y - 18, color: area.contains(mouse) ? .white : RGBA.gold, align: .center)
            button(area) { [weak self] in
                let count = DeckBuilder.factionsOrder.count
                builder.newDeck(DeckBuilder.factionsOrder[(factionIndex + arrows + count) % count]); self?.scrollTargetL = 0; self?.scrollTargetR = 0
            }
        }
        renderer.text(gameData.factionDesc(builder.faction), .ui(16), x: 960, y: 134, color: .gray(0.78), maxWidth: 900, align: .center)
        let colL = BuilderLayout.collectionColumn, colR = BuilderLayout.deckColumn
        glassPanel(colL, alpha: 0.55); glassPanel(colR, alpha: 0.55)
        renderer.text(L("Card Collection"), .serif(22, bold: true), x: colL.x + 14, y: 168, color: RGBA.gold)
        renderer.text(L("Cards in Deck"), .serif(22, bold: true), x: colR.x + 14, y: 168, color: RGBA.gold)
        let filters: [(String, (CardData) -> Bool)] = [
            (L("All"), { _ in true }),
            (L("Melee"), { $0.isUnit && $0.row.contains("c") && ($0.row == "close" || $0.row.hasPrefix("agile")) }),
            (L("Ranged"), { $0.isUnit && ($0.row == "ranged" || ($0.row.hasPrefix("agile") && $0.row.contains("r"))) }),
            (L("Siege"), { $0.isUnit && ($0.row == "siege" || $0.row.hasSuffix("s")) }),
            (L("Hero"), { $0.isHero }),
            (L("Special"), { $0.isSpecial || $0.isWeather })]
        var filterX: Float = colL.x + 240
        for (i, (n, _)) in filters.enumerated() {
            let w = renderer.measure(n, .ui(15, bold: true)).w + 22
            let area = R(filterX, 192, w, 26)
            let isActive = builderFilter == i
            if isActive { renderer.gradient(area, RGBA(r: 0.95, g: 0.82, b: 0.49, a: 1), RGBA(r: 0.79, g: 0.59, b: 0.18, a: 1), steps: 6) }
            else if area.contains(mouse) { renderer.rect(area, RGBA.gold.alpha(0.15)) }
            renderer.text(n, .ui(15, bold: true), x: area.mid.x, y: area.y + 4, color: isActive ? RGBA(r: 0.1, g: 0.07, b: 0.02, a: 1) : .gray(0.85), align: .center, shadow: nil)
            button(area) { [weak self] in self?.builderFilter = i; self?.scrollTargetL = 0 }
            filterX += w + 6
        }
        let pred = filters[min(builderFilter, filters.count - 1)].1
        let coll = builder.collection().filter { pred($0) && ($0.count - (builder.counts[$0.key] ?? 0)) > 0 }
        builderGrid(coll, in: colL, scroll: &builder.scrollL, target: &scrollTargetL, dt: dt, count: { cardData in builder.cap(cardData) - (builder.counts[cardData.key] ?? 0) }) { [weak self] d, from in
            let before = builder.counts[d.key] ?? 0
            builder.add(d)
            if (builder.counts[d.key] ?? 0) > before { self?.audio.play("card", volume: 0.4); self?.flyCards.append((d, from, R(colR.mid.x - 50, colR.y + 40, 100, 143), 0)) }
        }
        builderGrid(builder.deckCards, in: colR, scroll: &builder.scrollR, target: &scrollTargetR, dt: dt, count: { cardData in builder.counts[cardData.key] ?? 0 }) { [weak self] d, from in
            builder.remove(d); self?.audio.play("discard", volume: 0.4)
            self?.flyCards.append((d, from, R(colL.mid.x - 50, colL.y + 40, 100, 143), 0))
        }
        let leaderCards = builder.leaders()
        if let leaderIndex = leaderCards.firstIndex(where: { $0.key == builder.leaderKey }) ?? (leaderCards.isEmpty ? nil : 0) {
            if builder.leaderKey.isEmpty { builder.leaderKey = leaderCards[leaderIndex].key }
            let lc = Card(leaderCards[leaderIndex], owner: nil)
            let leaderArea = BuilderLayout.leaderCard
            renderer.quad(glowTex, R(leaderArea.x - 40, leaderArea.y - 40, leaderArea.w + 80, leaderArea.h + 80), color: RGBA(r: 1, g: 0.72, b: 0.3, a: 0.22 + 0.06 * sin(time * 2)))
            drawCard(lc, leaderArea)
            renderer.frame(leaderArea.inset(-2), RGBA.gold.alpha(0.6), 2)
            if leaderArea.contains(mouse) { builderHover = lc }
            let lb = BuilderLayout.changeLeaderButton
            renderer.text(L("Change leader") + " ▾", .serif(17, bold: true), x: 960, y: 388, color: lb.contains(mouse) ? .white : RGBA.gold, align: .center)
            renderer.rect(R(lb.x + 14, lb.y + 25, lb.w - 28, 1), RGBA.gold.alpha(lb.contains(mouse) ? 1 : 0.5))
            button(lb) { [weak self] in self?.leaderPickerOpen = true }
            button(leaderArea) { [weak self] in self?.leaderPickerOpen = true }
            for (arrows, x) in [(-1, Float(856)), (1, Float(1030))] {
                let area = R(x, 256, 34, 60)
                renderer.text(arrows < 0 ? "‹" : "›", .serif(54), x: area.mid.x, y: area.y - 12, color: area.contains(mouse) ? .white : RGBA.gold, align: .center)
                button(area) { builder.leaderKey = leaderCards[(leaderIndex + arrows + leaderCards.count) % leaderCards.count].key }
            }
        }
        let stats = builder.stats
        let rows: [(String, String, Bool)] = [
            (L("Total cards in deck"), "\(stats.total)", true), (L("Number of Unit Cards"), "\(stats.units)", stats.units >= 22),
            (L("Special Cards"), "\(stats.specials)/10", stats.specials <= 10), (L("Total Unit Card Strength"), "\(stats.strength)", true), (L("Hero Cards"), "\(stats.heroes)", true)]
        var y: Float = 424
        for (n, v, ok) in rows {
            renderer.text(n, .ui(14), x: 960, y: y, color: .gray(0.72), maxWidth: 220, align: .center); y += 19
            renderer.text(v, .gwent(28), x: 960, y: y, color: ok ? .white : RGBA(r: 1, g: 0.4, b: 0.35, a: 1), align: .center); y += 40
        }
        let area = R(870, y + 2, 180, 6)
        renderer.rect(area, RGBA.white.alpha(0.12))
        renderer.rect(R(area.x, area.y, area.w * min(1, Float(stats.units) / 22), area.h), stats.units >= 22 ? RGBA(r: 0.45, g: 0.85, b: 0.4, a: 1) : RGBA.gold)
        y += 18
        if stats.units < 22 { renderer.text(L("Your deck must have at least 22 unit cards."), .ui(13), x: 960, y: y, color: RGBA(r: 1, g: 0.55, b: 0.45, a: 1), maxWidth: 200, align: .center) }
        goldButton(BuilderLayout.saveButton, L("Save"), font: .serif(22, bold: true), enabled: builder.valid) { [weak self] in builder.save(); self?.audio.play("game_buy"); self?.builderSaved = 1.5 }
        if !builder.careerMode {
        goldButton(BuilderLayout.startButton, L("Start game"), font: .serif(20, bold: true), enabled: builder.valid) { [weak self] in
            guard let self = self else { return }
            builder.save(); self.customDecks = DeckBuilder.loadCustom(); self.startGame(with: builder.asDeck())
        }
        }
        goldButton(ScreenLayout.backButton, "‹  " + L("Back"), font: .serif(22, bold: true)) { [weak self] in
            if builder.careerMode { builder.save(); self?.screen = .career; return }
            self?.customDecks = DeckBuilder.loadCustom(); self?.selFaction = builder.faction; self?.deckStage = 1; self?.deckSwitchT = 0; self?.screen = .decks }
        if builderSaved > 0 { renderer.text(L("Deck Saved!"), .serif(22, bold: true), x: 960, y: 760, color: RGBA(r: 0.5, g: 1, b: 0.5, a: min(1, builderSaved)), align: .center); builderSaved -= dt }
        for i in flyCards.indices.reversed() {
            flyCards[i].t += dt / 0.35
            let flight = flyCards[i]
            if flight.t >= 1 { flyCards.remove(at: i); continue }
            let progress = ease(flight.t)
            let arcOffset = sin(progress * .pi) * -60
            let cardRect = R(flight.from.x + (flight.to.x - flight.from.x) * progress, flight.from.y + (flight.to.y - flight.from.y) * progress + arcOffset, flight.from.w, flight.from.h)
            renderer.rect(R(cardRect.x + 10, cardRect.y + 14, cardRect.w, cardRect.h), RGBA.black.alpha(0.35 * (1 - progress)))
            drawCard(Card(flight.d, owner: nil), cardRect)
            renderer.rect(cardRect, RGBA.black.alpha(progress * 0.6))
        }
        if let h = builderHover { drawPreview(h) }
        builderHover = nil
        languageToggle(y: 1040)
    }

    /// Overlay for choosing the deck's leader.
    func drawLeaderPicker(_ builder: DeckBuilder) {
        renderer.text(L("Choose a leader"), .gwent(52), x: 960, y: 40, color: RGBA.gold, align: .center)
        renderer.text(gameData.factionName(builder.faction) + " — " + L("click the leader you want to play with."), .serif(19, italic: true), x: 960, y: 108, color: .gray(0.85), align: .center)
        goldButton(ScreenLayout.backButton, "‹  " + L("Back"), font: .serif(22, bold: true)) { [weak self] in self?.leaderPickerOpen = false }
        let leaderCards = builder.leaders()
        guard !leaderCards.isEmpty else { return }
        let leaderCount = leaderCards.count, gap: Float = 24
        let leaderCardWidth = min(240, (1800 - gap * Float(leaderCount - 1)) / Float(leaderCount)), ch = leaderCardWidth / 0.697
        let x0 = 960 - (Float(leaderCount) * leaderCardWidth + Float(leaderCount - 1) * gap) / 2
        var hovered: Card?
        for (i, leaderEntry) in leaderCards.enumerated() {
            let base = R(x0 + Float(i) * (leaderCardWidth + gap), 180, leaderCardWidth, ch)
            let isHovered = base.contains(mouse)
            let isSelected = leaderEntry.key == builder.leaderKey
            let cardRect = isHovered ? R(base.x, base.y - 8, base.w, base.h) : base
            if isHovered || isSelected { renderer.quad(glowTex, R(cardRect.x - 40, cardRect.y - 40, cardRect.w + 80, cardRect.h + 80), color: RGBA(r: 1, g: 0.72, b: 0.3, a: isSelected ? 0.45 : 0.3)) }
            let newCard = Card(leaderEntry, owner: nil)
            drawCardLarge(newCard, cardRect)
            renderer.frame(cardRect.inset(-3), isSelected ? RGBA.gold : RGBA.gold.alpha(isHovered ? 0.7 : 0.25), isSelected ? 3 : 1.5)
            if isSelected { renderer.text("★ " + L("Selected"), .serif(18, bold: true), x: cardRect.mid.x, y: cardRect.y + cardRect.h + 10, color: RGBA.gold, align: .center) }
            if isHovered { hovered = newCard }
            button(base) { [weak self] in builder.leaderKey = leaderEntry.key; self?.leaderPickerOpen = false; self?.audio.play("card", volume: 0.5) }
        }
        let show = hovered?.data ?? leaderCards.first(where: { $0.key == builder.leaderKey }) ?? leaderCards[0]
        let panel = R(460, 180 + ch + 60, 1000, 150)
        glassPanel(panel, alpha: 0.8)
        renderer.text(gameData.cardName(show), .serif(24, bold: true), x: panel.mid.x, y: panel.y + 18, color: RGBA.gold, maxWidth: panel.w - 60, align: .center)
        renderer.text(gameData.abilityDesc(show.abilities.last ?? ""), .ui(18), x: panel.mid.x, y: panel.y + 60, color: .gray(0.9), maxWidth: panel.w - 80, align: .center)
    }

    /// Scrollable grid of cards used by the deck builder.
    func builderGrid(_ cards: [CardData], in area: R, scroll: inout Float, target: inout Float, dt: Float, cardW: Float = 100, count: (CardData) -> Int,
                             _ onClick: @escaping (CardData, R) -> Void) {
        let gridCardWidth: Float = cardW, gridCardHeight: Float = cardW * 1.43, gap: Float = 10
        let perRow = Int((area.w - 20 + gap) / (gridCardWidth + gap))
        let rowsN = (cards.count + perRow - 1) / perRow
        let contentH = Float(rowsN) * (gridCardHeight + gap) + 10
        let maxScroll = max(0, contentH - area.h)
        if area.contains(mouse) { target -= wheel * 1.4 }
        target = max(0, min(maxScroll, target))
        scroll += (target - scroll) * min(1, dt * 12)
        scroll = max(0, min(maxScroll, scroll))
        renderer.clip(area)
        defer { renderer.clip(nil) }
        for (i, cardData) in cards.enumerated() {
            let row = i / perRow, col = i % perRow
            let y = area.y + 10 + Float(row) * (gridCardHeight + gap) - scroll
            if y + gridCardHeight < area.y || y > area.y + area.h { continue }
            let x = area.x + 10 + Float(col) * (gridCardWidth + gap)
            let base = R(x, y, gridCardWidth, gridCardHeight)
            let inside = base.mid.y > area.y && base.mid.y < area.y + area.h
            let hovered = inside && base.contains(mouse)
            let key = "\(area.x)_" + cardData.key
            let previousHover = cardHover[key, default: 0]
            cardHover[key] = previousHover + ((hovered ? 1 : 0) - previousHover) * min(1, dt * 14)
            let hoverAmount = cardHover[key, default: 0]
            let zoom = 1 + 0.07 * hoverAmount
            let cardRect = R(base.mid.x - gridCardWidth * zoom / 2, base.mid.y - gridCardHeight * zoom / 2 - 4 * hoverAmount, gridCardWidth * zoom, gridCardHeight * zoom)
            if hoverAmount > 0.02 { renderer.quad(glowTex, R(cardRect.x - 20, cardRect.y - 20, cardRect.w + 40, cardRect.h + 40), color: RGBA(r: 1, g: 0.75, b: 0.3, a: 0.35 * hoverAmount)) }
            let newCard = Card(cardData, owner: nil)
            drawCard(newCard, cardRect)
            let copies = count(cardData)
            if copies > 1 || cardData.count > 1 {
                renderer.rect(R(cardRect.x + cardRect.w - 30, cardRect.y + cardRect.h - 26, 28, 22), RGBA.black.alpha(0.75))
                renderer.text("×\(copies)", .ui(15, bold: true), x: cardRect.x + cardRect.w - 16, y: cardRect.y + cardRect.h - 25, color: .white, align: .center, shadow: nil)
            }
            if hovered { renderer.frame(cardRect.inset(-2), RGBA.gold, 2); builderHover = newCard }
            if inside { button(base) { onClick(cardData, base) } }
        }
        if maxScroll > 0 {
            let scrollThumbHeight = area.h * area.h / contentH
            renderer.rect(R(area.x + area.w - 6, area.y + (area.h - scrollThumbHeight) * scroll / maxScroll, 4, scrollThumbHeight), RGBA.gold.alpha(0.6))
        }
    }
}

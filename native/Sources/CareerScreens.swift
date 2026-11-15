// Career screens, the save-location prompt and the in-app Options overlay.
import CoreGraphics
import Foundation

/// Career, save-location and options screens.
extension Scene {
    var career: Career { Career.shared }

    /// Career entry point: start screen, chapter ladder or reward screen.
    func drawCareer(_ dt: Float) {
        drawMenuBackground(dt, dim: 0.7)
        deckTransition = min(1, deckTransition + dt / 0.5)
        renderer.text(L("Career"), .gwent(52), x: 960, y: 30, color: RGBA.gold, align: .center)
        goldButton(ScreenLayout.backButton, "‹  " + L("Back"), font: .serif(22, bold: true)) { [weak self] in
            self?.deckStage = -1; self?.deckTransition = 0; self?.screen = .decks }
        if !career.active { drawCareerStart(); return }
        drawCareerLadder()
        if careerRewards != nil { drawCareerReward() }
        if let h = builderHover { drawPreviewRight(h, x: 110) }
        builderHover = nil
    }

    /// Difficulty and faction selection for a new career.
    func drawCareerStart() {
        renderer.text(L("You start with weak cards of the chosen faction. Every career is generated anew: different places, opponents and bosses. Win, earn cards and reach the top."),
               .serif(20, italic: true), x: 960, y: 96, color: .gray(0.88), maxWidth: 1300, align: .center)
        renderer.text(L("Difficulty") + ":", .serif(22, bold: true), x: 960 - 470, y: 160, color: RGBA.gold)
        let difficultyOptions: [(String, String)] = [(L("easy · 6 chapters"), ""), (L("normal · 8 chapters"), ""), (L("hard · 10 chapters"), "")]
        for (i, tile) in difficultyOptions.enumerated() {
            let area = R(960 - 230 + Float(i) * 250, 150, 240, 46)
            goldButton(area, (careerDifficultyChoice == i ? "✓ " : "") + tile.0, font: .serif(17, bold: true)) { [weak self] in self?.careerDifficultyChoice = i }
            if careerDifficultyChoice == i { renderer.rect(area, Theme.glow.alpha(0.22)); renderer.frame(area.inset(-3), Theme.highlightGold, 3) }
        }
        renderer.text(L("Choose the faction to start your career with:"), .serif(22, bold: true), x: 960, y: 214, color: RGBA.gold, align: .center)
        let facs = DeckBuilder.factionsOrder
        let tileWidth: Float = 300, tileHeight: Float = 214, gapX: Float = 24, gapY: Float = 18
        let x0 = 960 - (5 * tileWidth + 4 * gapX) / 2
        for (i, faction) in facs.enumerated() {
            let progress = ease(deckTransition * 1.6 - Float(i) * 0.04)
            let area = R(x0 + Float(i % 5) * (tileWidth + gapX), 256 + Float(i / 5) * (tileHeight + gapY) + (1 - progress) * 20, tileWidth, tileHeight)
            let hovered = area.contains(mouse)
            if hovered { renderer.quad(glowTex, R(area.x - 40, area.y - 40, area.w + 80, area.h + 80), color: Theme.glow.alpha(0.3)) }
            glassPanel(area, alpha: 0.75 * progress)
            renderer.frame(area, RGBA.gold.alpha(hovered ? 0.9 : 0.3), 1.5)
            renderer.image("img/icons/deck_shield_\(faction).png", R(area.mid.x - 34, area.y + 18, 68, 76), color: .white.alpha(progress))
            renderer.text(gameData.factionName(faction), .gwent(26), x: area.mid.x, y: area.y + 104, color: RGBA.gold.alpha(progress), maxWidth: area.w - 20, align: .center)
            renderer.text(gameData.factionDesc(faction), .ui(14), x: area.mid.x, y: area.y + 140, color: RGBA.gray(0.85, progress), maxWidth: area.w - 30, align: .center)
            button(area) { [weak self] in self?.career.start(faction, difficulty: self?.careerDifficultyChoice ?? 1); self?.careerChapter = 0; self?.deckTransition = 0; self?.audio.play("game_buy") }
        }
    }

    /// Chapter list, fights of the selected chapter and the player's deck panel.
    func drawCareerLadder() {
        let chapterCount = career.chapterCount
        let selectedChapter = min(careerChapter ?? career.currentChapter, chapterCount - 1)
        let difficultyName = Career.difficultyNames[career.difficulty]
        renderer.text(gameData.factionName(career.faction) + " · " + L(difficultyName) + " · " + L("opponents defeated") + ": \(career.beaten.count)/\(career.totalFights)",
               .serif(20, italic: true), x: 960, y: 98, color: .gray(0.85), align: .center)
        let colL = CareerLayout.chaptersColumn
        glassPanel(colL, alpha: 0.7)
        renderer.text(L("Chapters"), .gwent(30), x: colL.mid.x, y: colL.y + 14, color: RGBA.gold, align: .center)
        let first = max(0, min(career.currentChapter - 2, chapterCount - 5))
        for chapter in first..<min(chapterCount, first + 5) {
            let chap = career.chapter(chapter)
            let area = R(colL.x + 16, colL.y + 70 + Float(chapter - first) * 112, colL.w - 32, 100)
            let open = career.unlocked(chapter, 0), done = career.beaten.contains(career.index(chapter, 3))
            let isSelected = chapter == selectedChapter, hov = area.contains(mouse) && open
            renderer.rect(area, isSelected ? Theme.woodBrown.alpha(0.55) : RGBA.black.alpha(hov ? 0.45 : 0.3))
            renderer.frame(area, RGBA.gold.alpha(isSelected ? 0.95 : (open ? 0.45 : 0.15)), isSelected ? 2 : 1)
            renderer.text("\(chapter + 1). " + chap.title, .serif(20, bold: true), x: area.x + 14, y: area.y + 14, color: open ? .white : .gray(0.45), maxWidth: area.w - 28)
            let status = done ? "✓ " + L("Completed") : (open ? "▶ " + L("In progress") : "🔒 " + L("Locked"))
            let wonFights = (0..<4).filter { career.beaten.contains(career.index(chapter, $0)) }.count
            renderer.text(status + "  ·  \(wonFights)/4", .ui(15), x: area.x + 14, y: area.y + 62, color: done ? Theme.positive : (open ? RGBA.gold : .gray(0.45)))
            if open { button(area) { [weak self] in self?.careerChapter = chapter } }
        }
        let fights = career.chapter(selectedChapter).fights
        let cardWidthLarge: Float = 230, cardHeightLarge = cardWidthLarge / 0.697, gap: Float = 24
        let x0: Float = 460 + (1040 - (4 * cardWidthLarge + 3 * gap)) / 2
        renderer.text(L("Chapter") + " \(selectedChapter + 1)/\(chapterCount): " + career.chapter(selectedChapter).title, .gwent(34), x: 980, y: 150, color: RGBA.gold, align: .center)
        for (slot, fight) in fights.enumerated() {
            let fightIndex = career.index(selectedChapter, slot)
            let progress = ease(deckTransition * 1.5 - Float(slot) * 0.08)
            let x = x0 + Float(slot) * (cardWidthLarge + gap)
            let tile = R(x - 10, 200 + (1 - progress) * 24, cardWidthLarge + 20, cardHeightLarge + 210)
            let open = career.unlocked(selectedChapter, slot), won = career.beaten.contains(fightIndex)
            let hovered = tile.contains(mouse) && open
            if hovered { renderer.quad(glowTex, R(tile.x - 40, tile.y - 40, tile.w + 80, tile.h + 80), color: Theme.glow.alpha(0.28)) }
            glassPanel(tile, alpha: 0.65 * progress)
            renderer.frame(tile, fight.boss ? RGBA(r: 0.95, g: 0.35, b: 0.25, a: 0.8 * progress) : RGBA.gold.alpha(0.35 * progress), fight.boss ? 2.5 : 1.5)
            let opponentDeck = career.opponentDeck(fightIndex, fight)
            let cardRect = R(x, tile.y + 10, cardWidthLarge, cardHeightLarge)
            if let cardData = gameData.cards[fight.portrait] ?? gameData.cards[opponentDeck.leader] {
                drawCardLarge(Card(cardData, owner: nil), cardRect)
                if cardRect.contains(mouse) { builderHover = Card(cardData, owner: nil) }
            }
            if !open { renderer.rect(cardRect, RGBA.black.alpha(0.6)); renderer.text("🔒", .ui(54), x: cardRect.mid.x, y: cardRect.mid.y - 34, color: .white, align: .center) }
            var textY = cardRect.y + cardHeightLarge + 10
            textY += renderer.text((fight.boss ? "☠ " : "") + fight.name, .serif(20, bold: true), x: x, y: textY, color: fight.boss ? Theme.negative.alpha(progress) : RGBA.white.alpha(progress), maxWidth: cardWidthLarge).h + 2
            textY += renderer.text(gameData.factionName(fight.faction), .ui(15), x: x, y: textY, color: RGBA.gray(0.8, progress), maxWidth: cardWidthLarge).h + 2
            let diff = fight.cap >= 99 ? L("Full strength") : L("Card strength up to") + " \(fight.cap)"
            renderer.text(diff + (fight.heroes > 0 ? " · " + L("heroes") + ": \(fight.heroes)" : ""), .ui(14), x: x, y: textY, color: RGBA.gold.alpha(0.8 * progress), maxWidth: cardWidthLarge)
            let area = R(x, tile.y + tile.h - 56, cardWidthLarge, 46)
            if won {
                renderer.text("✓ " + L("Defeated"), .serif(18, bold: true), x: area.mid.x, y: area.y - 26, color: Theme.positive.alpha(progress), align: .center)
                goldButton(area, L("Play again"), font: .serif(18, bold: true)) { [weak self] in self?.startCareerFight(fightIndex) }
            } else if open {
                goldButton(area, fight.boss ? L("Fight the boss") : L("Fight"), font: .serif(20, bold: true)) { [weak self] in self?.startCareerFight(fightIndex) }
            } else {
                renderer.text(fight.boss ? L("Defeat the three opponents") : L("Defeat the previous boss"),
                       .ui(14), x: area.mid.x, y: area.y + 4, color: .gray(0.55), maxWidth: cardWidthLarge, align: .center)
            }
        }
        if career.finished {
            renderer.text("★ " + L("Career complete! You are a Gwent master.") + " ★",
                   .serif(26, bold: true), x: 980, y: 900, color: RGBA.gold, align: .center)
        }
        let colR = CareerLayout.deckColumn
        glassPanel(colR, alpha: 0.7)
        renderer.text(L("Your deck"), .gwent(30), x: colR.mid.x, y: colR.y + 14, color: RGBA.gold, align: .center)
        if let cardData = gameData.cards[career.leader] {
            let leaderArea = R(colR.mid.x - 90, colR.y + 64, 180, 180 / 0.697)
            drawCardLarge(Card(cardData, owner: nil), leaderArea)
            if leaderArea.contains(mouse) { builderHover = Card(cardData, owner: nil) }
        }
        let owned = career.collection.values.reduce(0, +)
        var y = colR.y + 64 + 180 / 0.697 + 14
        for (label, value) in [(L("Cards in collection"), "\(owned)"), (L("Units in deck"), "\(career.deckUnits)"),
                       (L("Leaders"), "\(career.leaders.count)")] {
            renderer.text(label, .ui(16), x: colR.x + 24, y: y, color: .gray(0.8)); renderer.text(value, .ui(16, bold: true), x: colR.x + colR.w - 24, y: y, color: RGBA.gold, align: .right); y += 28
        }
        goldButton(R(colR.x + 24, colR.y + colR.h - 128, colR.w - 48, 50), L("Edit career deck"), font: .serif(19, bold: true)) { [weak self] in
            guard let strongSelf = self else { return }; strongSelf.builder.loadCareer(); strongSelf.leaderPickerOpen = false; strongSelf.screen = .builder }
        let area = R(colR.x + 24, colR.y + colR.h - 66, colR.w - 48, 44)
        goldButton(area, careerConfirmReset ? L("Sure? Click again") : L("New career"), font: .serif(17, bold: true)) { [weak self] in
            guard let strongSelf = self else { return }
            if strongSelf.careerConfirmReset { strongSelf.career.reset(); strongSelf.careerConfirmReset = false; strongSelf.careerChapter = nil } else { strongSelf.careerConfirmReset = true }
        }
    }

    /// Starts a career fight against opponent `fi`.
    func startCareerFight(_ fightIndex: Int) {
        let chapter = fightIndex / 4, slot = fightIndex % 4
        let fight = career.chapter(chapter).fights[slot]
        careerConfirmReset = false
        defer { careerFightName = fight.name }
        startGame(with: career.playerDeck, against: career.opponentDeck(fightIndex, fight), careerFight: fightIndex)
    }

    /// Lets the player pick one of the reward cards after a win.
    func drawCareerReward() {
        guard let options = careerRewards else { return }
        clicks.removeAll()
        renderer.rect(renderer.visibleRect, RGBA.black.alpha(0.8))
        renderer.text(L("Victory!"), .gwent(64), x: 960, y: 60, color: RGBA.gold, align: .center)
        renderer.text(options.isEmpty ? L("You already own every card of this faction.")
                            : L("Choose a card to add to your collection:"),
               .serif(24, italic: true), x: 960, y: 150, color: .white, align: .center)
        if let newLeaderKey = careerNewLeader, let leaderData = gameData.cards[newLeaderKey] {
            renderer.text("★ " + L("New leader") + ": " + gameData.cardName(leaderData), .serif(22, bold: true), x: 960, y: 196, color: RGBA.gold, align: .center)
        }
        let cardWidthLarge: Float = 300, cardHeightLarge = cardWidthLarge / 0.697, gap: Float = 60
        let x0 = 960 - (Float(options.count) * cardWidthLarge + Float(max(0, options.count - 1)) * gap) / 2
        for (i, slot) in options.enumerated() {
            guard let cardData = gameData.cards[slot] else { continue }
            let base = R(x0 + Float(i) * (cardWidthLarge + gap), 260, cardWidthLarge, cardHeightLarge)
            let hovered = base.contains(mouse)
            let cardRect = hovered ? R(base.x - 6, base.y - 10, base.w + 12, base.h + 12) : base
            if hovered { renderer.quad(glowTex, R(cardRect.x - 50, cardRect.y - 50, cardRect.w + 100, cardRect.h + 100), color: Theme.glow.alpha(0.45)) }
            drawCardLarge(Card(cardData, owner: nil), cardRect)
            if hovered { builderHover = Card(cardData, owner: nil) }
            button(base) { [weak self] in self?.career.take(slot); self?.careerRewards = nil; self?.careerNewLeader = nil; self?.audio.play("game_buy") }
        }
        if options.isEmpty {
            goldButton(R(960 - 150, 700, 300, 60), L("Continue"), font: .serif(24, bold: true)) { [weak self] in self?.careerRewards = nil; self?.careerNewLeader = nil }
        }
    }

}

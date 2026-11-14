// Career screens, the save-location prompt and the in-app Options overlay.
import CoreGraphics
import Foundation

/// Career, save-location and options screens.
extension Scene {
    var career: Career { Career.shared }

    /// Career entry point: start screen, chapter ladder or reward screen.
    func drawCareer(_ dt: Float) {
        drawMenuBackground(dt, dim: 0.7)
        deckSwitchT = min(1, deckSwitchT + dt / 0.5)
        renderer.text(L("Career"), .gwent(52), x: 960, y: 30, color: RGBA.gold, align: .center)
        goldButton(R(40, 24, 190, 50), "‹  " + L("Back"), font: .serif(22, bold: true)) { [weak self] in
            self?.deckStage = -1; self?.deckSwitchT = 0; self?.screen = .decks }
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
        let dd: [(String, String)] = [(L("easy · 6 chapters"), ""), (L("normal · 8 chapters"), ""), (L("hard · 10 chapters"), "")]
        for (i, t) in dd.enumerated() {
            let b = R(960 - 230 + Float(i) * 250, 150, 240, 46)
            goldButton(b, (careerDiffPick == i ? "✓ " : "") + t.0, font: .serif(17, bold: true)) { [weak self] in self?.careerDiffPick = i }
            if careerDiffPick == i { renderer.rect(b, RGBA(r: 1, g: 0.78, b: 0.3, a: 0.22)); renderer.frame(b.inset(-3), RGBA(r: 1, g: 0.85, b: 0.4, a: 1), 3) }
        }
        renderer.text(L("Choose the faction to start your career with:"), .serif(22, bold: true), x: 960, y: 214, color: RGBA.gold, align: .center)
        let facs = DeckBuilder.factionsOrder
        let tw: Float = 300, th: Float = 214, gx: Float = 24, gy: Float = 18
        let x0 = 960 - (5 * tw + 4 * gx) / 2
        for (i, f) in facs.enumerated() {
            let a = ease(deckSwitchT * 1.6 - Float(i) * 0.04)
            let t = R(x0 + Float(i % 5) * (tw + gx), 256 + Float(i / 5) * (th + gy) + (1 - a) * 20, tw, th)
            let hovered = t.contains(mouse)
            if hovered { renderer.quad(glowTex, R(t.x - 40, t.y - 40, t.w + 80, t.h + 80), color: RGBA(r: 1, g: 0.72, b: 0.3, a: 0.3)) }
            glassPanel(t, alpha: 0.75 * a)
            renderer.frame(t, RGBA.gold.alpha(hovered ? 0.9 : 0.3), 1.5)
            renderer.image("img/icons/deck_shield_\(f).png", R(t.mid.x - 34, t.y + 18, 68, 76), color: .white.alpha(a))
            renderer.text(gameData.factionName(f), .gwent(26), x: t.mid.x, y: t.y + 104, color: RGBA.gold.alpha(a), maxWidth: t.w - 20, align: .center)
            renderer.text(gameData.factionDesc(f), .ui(14), x: t.mid.x, y: t.y + 140, color: RGBA.gray(0.85, a), maxWidth: t.w - 30, align: .center)
            button(t) { [weak self] in self?.career.start(f, difficulty: self?.careerDiffPick ?? 1); self?.careerChapter = 0; self?.deckSwitchT = 0; self?.audio.play("game_buy") }
        }
    }

    /// Chapter list, fights of the selected chapter and the player's deck panel.
    func drawCareerLadder() {
        let n = career.chapterCount
        let cc = min(careerChapter ?? career.currentChapter, n - 1)
        let dn = Career.difficultyNames[career.difficulty]
        renderer.text(gameData.factionName(career.faction) + " · " + L(dn) + " · " + L("opponents defeated") + ": \(career.beaten.count)/\(career.totalFights)",
               .serif(20, italic: true), x: 960, y: 98, color: .gray(0.85), align: .center)
        let colL = R(40, 150, 380, 640)
        glassPanel(colL, alpha: 0.7)
        renderer.text(L("Chapters"), .gwent(30), x: colL.mid.x, y: colL.y + 14, color: RGBA.gold, align: .center)
        let first = max(0, min(career.currentChapter - 2, n - 5))
        for c in first..<min(n, first + 5) {
            let chap = career.chapter(c)
            let b = R(colL.x + 16, colL.y + 70 + Float(c - first) * 112, colL.w - 32, 100)
            let open = career.unlocked(c, 0), done = career.beaten.contains(career.index(c, 3))
            let sel = c == cc, hov = b.contains(mouse) && open
            renderer.rect(b, sel ? RGBA(r: 0.55, g: 0.4, b: 0.12, a: 0.55) : RGBA.black.alpha(hov ? 0.45 : 0.3))
            renderer.frame(b, RGBA.gold.alpha(sel ? 0.95 : (open ? 0.45 : 0.15)), sel ? 2 : 1)
            renderer.text("\(c + 1). " + chap.title, .serif(20, bold: true), x: b.x + 14, y: b.y + 14, color: open ? .white : .gray(0.45), maxWidth: b.w - 28)
            let st = done ? "✓ " + L("Completed") : (open ? "▶ " + L("In progress") : "🔒 " + L("Locked"))
            let won = (0..<4).filter { career.beaten.contains(career.index(c, $0)) }.count
            renderer.text(st + "  ·  \(won)/4", .ui(15), x: b.x + 14, y: b.y + 62, color: done ? RGBA(r: 0.5, g: 0.9, b: 0.5, a: 1) : (open ? RGBA.gold : .gray(0.45)))
            if open { button(b) { [weak self] in self?.careerChapter = c } }
        }
        let fights = career.chapter(cc).fights
        let cw: Float = 230, chh = cw / 0.697, gap: Float = 24
        let x0: Float = 460 + (1040 - (4 * cw + 3 * gap)) / 2
        renderer.text(L("Chapter") + " \(cc + 1)/\(n): " + career.chapter(cc).title, .gwent(34), x: 980, y: 150, color: RGBA.gold, align: .center)
        for (k, f) in fights.enumerated() {
            let fi = career.index(cc, k)
            let a = ease(deckSwitchT * 1.5 - Float(k) * 0.08)
            let x = x0 + Float(k) * (cw + gap)
            let tile = R(x - 10, 200 + (1 - a) * 24, cw + 20, chh + 210)
            let open = career.unlocked(cc, k), won = career.beaten.contains(fi)
            let hovered = tile.contains(mouse) && open
            if hovered { renderer.quad(glowTex, R(tile.x - 40, tile.y - 40, tile.w + 80, tile.h + 80), color: RGBA(r: 1, g: 0.72, b: 0.3, a: 0.28)) }
            glassPanel(tile, alpha: 0.65 * a)
            renderer.frame(tile, f.boss ? RGBA(r: 0.95, g: 0.35, b: 0.25, a: 0.8 * a) : RGBA.gold.alpha(0.35 * a), f.boss ? 2.5 : 1.5)
            let od = career.opponentDeck(fi, f)
            let cardRect = R(x, tile.y + 10, cw, chh)
            if let lc = gameData.cards[f.portrait] ?? gameData.cards[od.leader] {
                drawCardLarge(Card(lc, owner: nil), cardRect)
                if cardRect.contains(mouse) { builderHover = Card(lc, owner: nil) }
            }
            if !open { renderer.rect(cardRect, RGBA.black.alpha(0.6)); renderer.text("🔒", .ui(54), x: cardRect.mid.x, y: cardRect.mid.y - 34, color: .white, align: .center) }
            var ty = cardRect.y + chh + 10
            ty += renderer.text((f.boss ? "☠ " : "") + f.name, .serif(20, bold: true), x: x, y: ty, color: f.boss ? RGBA(r: 1, g: 0.6, b: 0.5, a: a) : RGBA.white.alpha(a), maxWidth: cw).h + 2
            ty += renderer.text(gameData.factionName(f.faction), .ui(15), x: x, y: ty, color: RGBA.gray(0.8, a), maxWidth: cw).h + 2
            let diff = f.cap >= 99 ? L("Full strength") : L("Card strength up to") + " \(f.cap)"
            renderer.text(diff + (f.heroes > 0 ? " · " + L("heroes") + ": \(f.heroes)" : ""), .ui(14), x: x, y: ty, color: RGBA.gold.alpha(0.8 * a), maxWidth: cw)
            let bb = R(x, tile.y + tile.h - 56, cw, 46)
            if won {
                renderer.text("✓ " + L("Defeated"), .serif(18, bold: true), x: bb.mid.x, y: bb.y - 26, color: RGBA(r: 0.5, g: 0.9, b: 0.5, a: a), align: .center)
                goldButton(bb, L("Play again"), font: .serif(18, bold: true)) { [weak self] in self?.startCareerFight(fi) }
            } else if open {
                goldButton(bb, f.boss ? L("Fight the boss") : L("Fight"), font: .serif(20, bold: true)) { [weak self] in self?.startCareerFight(fi) }
            } else {
                renderer.text(f.boss ? L("Defeat the three opponents") : L("Defeat the previous boss"),
                       .ui(14), x: bb.mid.x, y: bb.y + 4, color: .gray(0.55), maxWidth: cw, align: .center)
            }
        }
        if career.finished {
            renderer.text("★ " + L("Career complete! You are a Gwent master.") + " ★",
                   .serif(26, bold: true), x: 980, y: 900, color: RGBA.gold, align: .center)
        }
        let colR = R(1520, 150, 360, 640)
        glassPanel(colR, alpha: 0.7)
        renderer.text(L("Your deck"), .gwent(30), x: colR.mid.x, y: colR.y + 14, color: RGBA.gold, align: .center)
        if let lc = gameData.cards[career.leader] {
            let leaderArea = R(colR.mid.x - 90, colR.y + 64, 180, 180 / 0.697)
            drawCardLarge(Card(lc, owner: nil), leaderArea)
            if leaderArea.contains(mouse) { builderHover = Card(lc, owner: nil) }
        }
        let owned = career.collection.values.reduce(0, +)
        var y = colR.y + 64 + 180 / 0.697 + 14
        for (t, v) in [(L("Cards in collection"), "\(owned)"), (L("Units in deck"), "\(career.deckUnits)"),
                       (L("Leaders"), "\(career.leaders.count)")] {
            renderer.text(t, .ui(16), x: colR.x + 24, y: y, color: .gray(0.8)); renderer.text(v, .ui(16, bold: true), x: colR.x + colR.w - 24, y: y, color: RGBA.gold, align: .right); y += 28
        }
        goldButton(R(colR.x + 24, colR.y + colR.h - 128, colR.w - 48, 50), L("Edit career deck"), font: .serif(19, bold: true)) { [weak self] in
            guard let s = self else { return }; s.builder.loadCareer(); s.leaderPickerOpen = false; s.screen = .builder }
        let rb = R(colR.x + 24, colR.y + colR.h - 66, colR.w - 48, 44)
        goldButton(rb, careerConfirmReset ? L("Sure? Click again") : L("New career"), font: .serif(17, bold: true)) { [weak self] in
            guard let s = self else { return }
            if s.careerConfirmReset { s.career.reset(); s.careerConfirmReset = false; s.careerChapter = nil } else { s.careerConfirmReset = true }
        }
    }

    /// Starts a career fight against opponent `fi`.
    func startCareerFight(_ fightIndex: Int) {
        let c = fightIndex / 4, k = fightIndex % 4
        let f = career.chapter(c).fights[k]
        careerConfirmReset = false
        defer { careerFightName = f.name }
        startGame(with: career.playerDeck, against: career.opponentDeck(fightIndex, f), careerFight: fightIndex)
    }

    /// Lets the player pick one of the reward cards after a win.
    func drawCareerReward() {
        guard let opts = careerRewards else { return }
        clicks.removeAll()
        renderer.rect(R(0, 0, virtualWidth, virtualHeight), RGBA.black.alpha(0.8))
        renderer.text(L("Victory!"), .gwent(64), x: 960, y: 60, color: RGBA.gold, align: .center)
        renderer.text(opts.isEmpty ? L("You already own every card of this faction.")
                            : L("Choose a card to add to your collection:"),
               .serif(24, italic: true), x: 960, y: 150, color: .white, align: .center)
        if let nl = careerNewLeader, let lc = gameData.cards[nl] {
            renderer.text("★ " + L("New leader") + ": " + gameData.cardName(lc), .serif(22, bold: true), x: 960, y: 196, color: RGBA.gold, align: .center)
        }
        let cw: Float = 300, chh = cw / 0.697, gap: Float = 60
        let x0 = 960 - (Float(opts.count) * cw + Float(max(0, opts.count - 1)) * gap) / 2
        for (i, k) in opts.enumerated() {
            guard let d = gameData.cards[k] else { continue }
            let base = R(x0 + Float(i) * (cw + gap), 260, cw, chh)
            let hovered = base.contains(mouse)
            let cardRect = hovered ? R(base.x - 6, base.y - 10, base.w + 12, base.h + 12) : base
            if hovered { renderer.quad(glowTex, R(cardRect.x - 50, cardRect.y - 50, cardRect.w + 100, cardRect.h + 100), color: RGBA(r: 1, g: 0.75, b: 0.3, a: 0.45)) }
            drawCardLarge(Card(d, owner: nil), cardRect)
            if hovered { builderHover = Card(d, owner: nil) }
            button(base) { [weak self] in self?.career.take(k); self?.careerRewards = nil; self?.careerNewLeader = nil; self?.audio.play("game_buy") }
        }
        if opts.isEmpty {
            goldButton(R(960 - 150, 700, 300, 60), L("Continue"), font: .serif(24, bold: true)) { [weak self] in self?.careerRewards = nil; self?.careerNewLeader = nil }
        }
    }

}

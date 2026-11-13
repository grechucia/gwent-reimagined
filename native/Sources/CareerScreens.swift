import CoreGraphics
import Foundation

extension Scene {
    var career: Career { Career.shared }

    func drawCareer(_ dt: Float) {
        drawMenuBackground(dt, dim: 0.7)
        deckSwitchT = min(1, deckSwitchT + dt / 0.5)
        r.text(L2("Kariera", "Career"), .gwent(52), x: 960, y: 30, color: RGBA.gold, align: .center)
        goldButton(R(40, 24, 190, 50), "‹  " + L2("Wróć", "Back"), font: .serif(22, bold: true)) { [weak self] in
            self?.deckStage = -1; self?.deckSwitchT = 0; self?.screen = .decks }
        if !career.active { drawCareerStart(); return }
        drawCareerLadder()
        if careerRewards != nil { drawCareerReward() }
        if let h = builderHover { drawPreviewRight(h, x: 110) }
        builderHover = nil
    }

    private func drawCareerStart() {
        r.text(L2("Zaczynasz od słabych kart wybranej frakcji. Każda kariera jest losowana od nowa: inne miejsca, przeciwnicy i bossowie. Wygrywaj, zdobywaj karty i dojdź na szczyt.",
                  "You start with weak cards of the chosen faction. Every career is generated anew: different places, opponents and bosses. Win, earn cards and reach the top."),
               .serif(20, italic: true), x: 960, y: 96, color: .gray(0.88), maxWidth: 1300, align: .center)
        r.text(L2("Poziom trudności", "Difficulty") + ":", .serif(22, bold: true), x: 960 - 470, y: 160, color: RGBA.gold)
        let dd: [(String, String)] = [(L2("łatwy · 6 rozdziałów", "easy · 6 chapters"), ""), (L2("normalny · 8 rozdziałów", "normal · 8 chapters"), ""), (L2("trudny · 10 rozdziałów", "hard · 10 chapters"), "")]
        for (i, t) in dd.enumerated() {
            let b = R(960 - 230 + Float(i) * 250, 150, 240, 46)
            goldButton(b, (careerDiffPick == i ? "✓ " : "") + t.0, font: .serif(17, bold: true)) { [weak self] in self?.careerDiffPick = i }
            if careerDiffPick == i { r.rect(b, RGBA(r: 1, g: 0.78, b: 0.3, a: 0.22)); r.frame(b.inset(-3), RGBA(r: 1, g: 0.85, b: 0.4, a: 1), 3) }
        }
        r.text(L2("Wybierz frakcję, którą rozpoczniesz karierę:", "Choose the faction to start your career with:"), .serif(22, bold: true), x: 960, y: 214, color: RGBA.gold, align: .center)
        let facs = DeckBuilder.factionsOrder
        let tw: Float = 300, th: Float = 214, gx: Float = 24, gy: Float = 18
        let x0 = 960 - (5 * tw + 4 * gx) / 2
        for (i, f) in facs.enumerated() {
            let a = ease(deckSwitchT * 1.6 - Float(i) * 0.04)
            let t = R(x0 + Float(i % 5) * (tw + gx), 256 + Float(i / 5) * (th + gy) + (1 - a) * 20, tw, th)
            let hov = t.contains(mouse)
            if hov { r.quad(glowTex, R(t.x - 40, t.y - 40, t.w + 80, t.h + 80), color: RGBA(r: 1, g: 0.72, b: 0.3, a: 0.3)) }
            glassPanel(t, alpha: 0.75 * a)
            r.frame(t, RGBA.gold.alpha(hov ? 0.9 : 0.3), 1.5)
            r.image("img/icons/deck_shield_\(f).png", R(t.mid.x - 34, t.y + 18, 68, 76), color: .white.alpha(a))
            r.text(gd.factionName(f), .gwent(26), x: t.mid.x, y: t.y + 104, color: RGBA.gold.alpha(a), maxWidth: t.w - 20, align: .center)
            r.text(gd.factionDesc(f), .ui(14), x: t.mid.x, y: t.y + 140, color: RGBA.gray(0.85, a), maxWidth: t.w - 30, align: .center)
            button(t) { [weak self] in self?.career.start(f, difficulty: self?.careerDiffPick ?? 1); self?.careerChapter = 0; self?.deckSwitchT = 0; self?.audio.play("game_buy") }
        }
    }

    private func drawCareerLadder() {
        let n = career.chapterCount
        let cc = min(careerChapter ?? career.currentChapter, n - 1)
        let dn = Career.difficultyNames[career.difficulty]
        r.text(gd.factionName(career.faction) + " · " + L2(dn.0, dn.1) + " · " + L2("pokonani przeciwnicy", "opponents defeated") + ": \(career.beaten.count)/\(career.totalFights)",
               .serif(20, italic: true), x: 960, y: 98, color: .gray(0.85), align: .center)
        let colL = R(40, 150, 380, 640)
        glassPanel(colL, alpha: 0.7)
        r.text(L2("Rozdziały", "Chapters"), .gwent(30), x: colL.mid.x, y: colL.y + 14, color: RGBA.gold, align: .center)
        let first = max(0, min(career.currentChapter - 2, n - 5))
        for c in first..<min(n, first + 5) {
            let chap = career.chapter(c)
            let b = R(colL.x + 16, colL.y + 70 + Float(c - first) * 112, colL.w - 32, 100)
            let open = career.unlocked(c, 0), done = career.beaten.contains(career.index(c, 3))
            let sel = c == cc, hov = b.contains(mouse) && open
            r.rect(b, sel ? RGBA(r: 0.55, g: 0.4, b: 0.12, a: 0.55) : RGBA.black.alpha(hov ? 0.45 : 0.3))
            r.frame(b, RGBA.gold.alpha(sel ? 0.95 : (open ? 0.45 : 0.15)), sel ? 2 : 1)
            r.text("\(c + 1). " + chap.title, .serif(20, bold: true), x: b.x + 14, y: b.y + 14, color: open ? .white : .gray(0.45), maxWidth: b.w - 28)
            let st = done ? "✓ " + L2("Ukończony", "Completed") : (open ? "▶ " + L2("W toku", "In progress") : "🔒 " + L2("Zablokowany", "Locked"))
            let won = (0..<4).filter { career.beaten.contains(career.index(c, $0)) }.count
            r.text(st + "  ·  \(won)/4", .ui(15), x: b.x + 14, y: b.y + 62, color: done ? RGBA(r: 0.5, g: 0.9, b: 0.5, a: 1) : (open ? RGBA.gold : .gray(0.45)))
            if open { button(b) { [weak self] in self?.careerChapter = c } }
        }
        let fights = career.chapter(cc).fights
        let cw: Float = 230, chh = cw / 0.697, gap: Float = 24
        let x0: Float = 460 + (1040 - (4 * cw + 3 * gap)) / 2
        r.text(L2("Rozdział", "Chapter") + " \(cc + 1)/\(n): " + career.chapter(cc).title, .gwent(34), x: 980, y: 150, color: RGBA.gold, align: .center)
        for (k, f) in fights.enumerated() {
            let fi = career.index(cc, k)
            let a = ease(deckSwitchT * 1.5 - Float(k) * 0.08)
            let x = x0 + Float(k) * (cw + gap)
            let tile = R(x - 10, 200 + (1 - a) * 24, cw + 20, chh + 210)
            let open = career.unlocked(cc, k), won = career.beaten.contains(fi)
            let hov = tile.contains(mouse) && open
            if hov { r.quad(glowTex, R(tile.x - 40, tile.y - 40, tile.w + 80, tile.h + 80), color: RGBA(r: 1, g: 0.72, b: 0.3, a: 0.28)) }
            glassPanel(tile, alpha: 0.65 * a)
            r.frame(tile, f.boss ? RGBA(r: 0.95, g: 0.35, b: 0.25, a: 0.8 * a) : RGBA.gold.alpha(0.35 * a), f.boss ? 2.5 : 1.5)
            let od = career.opponentDeck(fi, f)
            let cr = R(x, tile.y + 10, cw, chh)
            if let lc = gd.cards[f.portrait] ?? gd.cards[od.leader] {
                drawCardLarge(Card(lc, owner: nil), cr)
                if cr.contains(mouse) { builderHover = Card(lc, owner: nil) }
            }
            if !open { r.rect(cr, RGBA.black.alpha(0.6)); r.text("🔒", .ui(54), x: cr.mid.x, y: cr.mid.y - 34, color: .white, align: .center) }
            var ty = cr.y + chh + 10
            ty += r.text((f.boss ? "☠ " : "") + f.name, .serif(20, bold: true), x: x, y: ty, color: f.boss ? RGBA(r: 1, g: 0.6, b: 0.5, a: a) : RGBA.white.alpha(a), maxWidth: cw).h + 2
            ty += r.text(gd.factionName(f.faction), .ui(15), x: x, y: ty, color: RGBA.gray(0.8, a), maxWidth: cw).h + 2
            let diff = f.cap >= 99 ? L2("Pełna siła", "Full strength") : L2("Siła kart do", "Card strength up to") + " \(f.cap)"
            r.text(diff + (f.heroes > 0 ? " · " + L2("bohaterowie", "heroes") + ": \(f.heroes)" : ""), .ui(14), x: x, y: ty, color: RGBA.gold.alpha(0.8 * a), maxWidth: cw)
            let bb = R(x, tile.y + tile.h - 56, cw, 46)
            if won {
                r.text("✓ " + L2("Pokonany", "Defeated"), .serif(18, bold: true), x: bb.mid.x, y: bb.y - 26, color: RGBA(r: 0.5, g: 0.9, b: 0.5, a: a), align: .center)
                goldButton(bb, L2("Zagraj ponownie", "Play again"), font: .serif(18, bold: true)) { [weak self] in self?.startCareerFight(fi) }
            } else if open {
                goldButton(bb, f.boss ? L2("Walcz z bossem", "Fight the boss") : L2("Walcz", "Fight"), font: .serif(20, bold: true)) { [weak self] in self?.startCareerFight(fi) }
            } else {
                r.text(f.boss ? L2("Pokonaj trzech przeciwników", "Defeat the three opponents") : L2("Pokonaj bossa poprzedniego rozdziału", "Defeat the previous boss"),
                       .ui(14), x: bb.mid.x, y: bb.y + 4, color: .gray(0.55), maxWidth: cw, align: .center)
            }
        }
        if career.finished {
            r.text("★ " + L2("Kariera ukończona! Jesteś mistrzem gwinta.", "Career complete! You are a Gwent master.") + " ★",
                   .serif(26, bold: true), x: 980, y: 900, color: RGBA.gold, align: .center)
        }
        let colR = R(1520, 150, 360, 640)
        glassPanel(colR, alpha: 0.7)
        r.text(L2("Twoja talia", "Your deck"), .gwent(30), x: colR.mid.x, y: colR.y + 14, color: RGBA.gold, align: .center)
        if let lc = gd.cards[career.leader] {
            let lr = R(colR.mid.x - 90, colR.y + 64, 180, 180 / 0.697)
            drawCardLarge(Card(lc, owner: nil), lr)
            if lr.contains(mouse) { builderHover = Card(lc, owner: nil) }
        }
        let owned = career.collection.values.reduce(0, +)
        var y = colR.y + 64 + 180 / 0.697 + 14
        for (t, v) in [(L2("Karty w kolekcji", "Cards in collection"), "\(owned)"), (L2("Jednostki w talii", "Units in deck"), "\(career.deckUnits)"),
                       (L2("Dowódcy", "Leaders"), "\(career.leaders.count)")] {
            r.text(t, .ui(16), x: colR.x + 24, y: y, color: .gray(0.8)); r.text(v, .ui(16, bold: true), x: colR.x + colR.w - 24, y: y, color: RGBA.gold, align: .right); y += 28
        }
        goldButton(R(colR.x + 24, colR.y + colR.h - 128, colR.w - 48, 50), L2("Edytuj talię kariery", "Edit career deck"), font: .serif(19, bold: true)) { [weak self] in
            guard let s = self else { return }; s.builder.loadCareer(); s.leaderPickerOpen = false; s.screen = .builder }
        let rb = R(colR.x + 24, colR.y + colR.h - 66, colR.w - 48, 44)
        goldButton(rb, careerConfirmReset ? L2("Na pewno? Kliknij ponownie", "Sure? Click again") : L2("Nowa kariera", "New career"), font: .serif(17, bold: true)) { [weak self] in
            guard let s = self else { return }
            if s.careerConfirmReset { s.career.reset(); s.careerConfirmReset = false; s.careerChapter = nil } else { s.careerConfirmReset = true }
        }
    }

    func startCareerFight(_ fi: Int) {
        let c = fi / 4, k = fi % 4
        let f = career.chapter(c).fights[k]
        careerConfirmReset = false
        defer { careerFightName = f.name }
        startGame(with: career.playerDeck, against: career.opponentDeck(fi, f), careerFight: fi)
    }

    private func drawCareerReward() {
        guard let opts = careerRewards else { return }
        clicks.removeAll()
        r.rect(R(0, 0, VW, VH), RGBA.black.alpha(0.8))
        r.text(L2("Zwycięstwo!", "Victory!"), .gwent(64), x: 960, y: 60, color: RGBA.gold, align: .center)
        r.text(opts.isEmpty ? L2("Masz już wszystkie karty tej frakcji.", "You already own every card of this faction.")
                            : L2("Wybierz kartę, którą dodasz do swojej kolekcji:", "Choose a card to add to your collection:"),
               .serif(24, italic: true), x: 960, y: 150, color: .white, align: .center)
        if let nl = careerNewLeader, let lc = gd.cards[nl] {
            r.text("★ " + L2("Nowy dowódca", "New leader") + ": " + gd.cardName(lc), .serif(22, bold: true), x: 960, y: 196, color: RGBA.gold, align: .center)
        }
        let cw: Float = 300, chh = cw / 0.697, gap: Float = 60
        let x0 = 960 - (Float(opts.count) * cw + Float(max(0, opts.count - 1)) * gap) / 2
        for (i, k) in opts.enumerated() {
            guard let d = gd.cards[k] else { continue }
            let base = R(x0 + Float(i) * (cw + gap), 260, cw, chh)
            let hov = base.contains(mouse)
            let cr = hov ? R(base.x - 6, base.y - 10, base.w + 12, base.h + 12) : base
            if hov { r.quad(glowTex, R(cr.x - 50, cr.y - 50, cr.w + 100, cr.h + 100), color: RGBA(r: 1, g: 0.75, b: 0.3, a: 0.45)) }
            drawCardLarge(Card(d, owner: nil), cr)
            if hov { builderHover = Card(d, owner: nil) }
            button(base) { [weak self] in self?.career.take(k); self?.careerRewards = nil; self?.careerNewLeader = nil; self?.audio.play("game_buy") }
        }
        if opts.isEmpty {
            goldButton(R(960 - 150, 700, 300, 60), L2("Dalej", "Continue"), font: .serif(24, bold: true)) { [weak self] in self?.careerRewards = nil; self?.careerNewLeader = nil }
        }
    }

    func askSaveLocation(then: (() -> Void)?) { savePromptOpen = true; savePromptThen = then }

    func drawSavePrompt() {
        r.rect(R(0, 0, VW, VH), RGBA.black.alpha(0.82))
        let p = R(360, 120, 1200, 840)
        glassPanel(p, alpha: 0.96)
        r.text(L2("Gdzie zapisywać postęp gry?", "Where should your progress be saved?"), .gwent(44), x: 960, y: p.y + 30, color: RGBA.gold, align: .center)
        r.text(L2("Twoje talie i kariera zapisują się w jednym pliku. Wybierz miejsce – możesz je później zmienić w Opcjach.",
                  "Your decks and career are kept in one file. Choose a location – you can change it later in Options."),
               .serif(19, italic: true), x: 960, y: p.y + 96, color: .gray(0.88), maxWidth: p.w - 120, align: .center)
        let ic = SaveStore.iCloudDir
        let opts: [(String, String, Bool, () -> Void)] = [
            (Platform.isDesktop ? L2("Na tym Macu", "On this Mac") : L2("Na tym urządzeniu", "On this device"),
             Platform.isDesktop ? L2("Zapis lokalny. Najprostszy wybór, jeśli grasz tylko na tym komputerze.", "Local save. The simplest choice if you only play on this computer.")
                                : L2("Zapis lokalny, widoczny w aplikacji Pliki. Najprostszy wybór, jeśli grasz tylko na tym urządzeniu.", "Local save, visible in the Files app. The simplest choice if you only play on this device."), true,
             { [weak self] in self?.finishSaveChoice(SaveStore.localDir) }),
            (L2("iCloud Drive", "iCloud Drive"), ic == nil
                ? (Platform.isDesktop ? L2("iCloud Drive jest wyłączony na tym Macu (Ustawienia systemowe → Apple ID → iCloud).", "iCloud Drive is off on this Mac (System Settings → Apple ID → iCloud).")
                                      : L2("Wybierz folder w iCloud Drive przez „Wybierz folder…”.", "Choose a folder in iCloud Drive with “Choose a folder…”."))
                : L2("Synchronizacja między urządzeniami Apple: Mac, iPhone i iPad zobaczą ten sam postęp.", "Syncs between Apple devices: your Mac, iPhone and iPad share the same progress."),
             ic != nil, { [weak self] in if let u = ic { self?.finishSaveChoice(u) } }),
            (L2("Wybierz folder…", "Choose a folder…"), L2("Np. dysk sieciowy, Dropbox albo Dysk Google – przyda się, jeśli chcesz synchronizować postęp także z Androidem.",
                                                             "E.g. a network drive, Dropbox or Google Drive – useful if you also want to sync with Android."), true,
             { [weak self] in self?.pickSaveFolder() })]
        for (i, o) in opts.enumerated() {
            let b = R(p.x + 80, p.y + 180 + Float(i) * 170, p.w - 160, 140)
            let hov = o.2 && b.contains(mouse)
            r.rect(b, RGBA.black.alpha(hov ? 0.5 : 0.32)); r.frame(b, RGBA.gold.alpha(o.2 ? (hov ? 1 : 0.5) : 0.2), hov ? 2.5 : 1.5)
            r.text(o.0, .serif(28, bold: true), x: b.x + 30, y: b.y + 22, color: o.2 ? (hov ? .white : RGBA.gold) : .gray(0.45))
            r.text(o.1, .ui(18), x: b.x + 30, y: b.y + 72, color: o.2 ? .gray(0.88) : .gray(0.5), maxWidth: b.w - 60)
            if o.2 { button(b, o.3) }
        }
        if SaveStore.shared.chosen {
            r.text(L2("Obecnie", "Currently") + ": " + SaveStore.shared.displayPath, .ui(15), x: 960, y: p.y + p.h - 70, color: .gray(0.7), maxWidth: p.w - 100, align: .center)
            smallLink(R(960 - 120, p.y + p.h - 44, 240, 32), L2("Anuluj", "Cancel")) { [weak self] in self?.savePromptOpen = false; self?.savePromptThen = nil }
        }
    }
    private func finishSaveChoice(_ u: URL) {
        SaveStore.shared.choose(u)
        Career.shared.load(); customDecks = DeckBuilder.loadCustom()
        savePromptOpen = false
        let t = savePromptThen; savePromptThen = nil; t?()
    }
    private func pickSaveFolder() {
        Platform.pickFolder(message: L2("Folder na zapis gry GwentReimagined", "Folder for GwentReimagined saves")) { [weak self] u in
            if let u = u { self?.finishSaveChoice(u) }
        }
    }

    func drawOptions() {
        r.rect(R(0, 0, VW, VH), RGBA.black.alpha(0.82))
        let p = R(360, 40, 1200, 1000)
        glassPanel(p, alpha: 0.96)
        r.text(L2("Opcje", "Options"), .gwent(52), x: 960, y: p.y + 24, color: RGBA.gold, align: .center)
        goldButton(R(40, 24, 190, 50), "‹  " + L2("Wróć", "Back"), font: .serif(22, bold: true)) { [weak self] in self?.optionsOpen = false; self?.game?.paused = false }
        goldButton(R(p.x + p.w - 250, p.y + 30, 210, 46), L2("Licencje", "Licenses"), font: .serif(18, bold: true)) { [weak self] in self?.creditsOpen = true }
        var y = p.y + 110
        let lx = p.x + 60, bx = p.x + 420
        func label(_ t: String) { r.text(t, .serif(22, bold: true), x: lx, y: y + 10, color: .white, maxWidth: 340) }
        func choice(_ items: [(String, Bool, Bool)], w: Float = 140, _ act: @escaping (Int) -> Void) {
            for (i, it) in items.enumerated() {
                let b = R(bx + Float(i) * (w + 10), y, w, 46)
                goldButton(b, (it.1 ? "✓ " : "") + it.0, font: .serif(17, bold: true), enabled: it.2) { act(i) }
                if it.1 { r.rect(b, RGBA(r: 1, g: 0.78, b: 0.3, a: 0.22)); r.frame(b.inset(-3), RGBA(r: 1, g: 0.85, b: 0.4, a: 1), 3) }
            }
        }
        label(L2("Nazwa gracza", "Player name"))
        r.text(playerName, .serif(22, bold: true), x: bx, y: y + 10, color: RGBA.gold, maxWidth: 380)
        goldButton(R(bx + 400, y, 200, 46), L2("Zmień…", "Change…"), font: .serif(17, bold: true)) { [weak self] in self?.askPlayerName() }
        y += 76
        label(L2("Muzyka", "Music"))
        choice([(L2("Włączona", "On"), audio.musicOn && !audio.muted, true), (L2("Wyłączona", "Off"), !audio.musicOn || audio.muted, true)]) { [weak self] i in
            guard let s = self else { return }
            if i == 0 { s.audio.muted = false; s.audio.musicOn = true } else { s.audio.musicOn = false }
            s.host?.refreshMenus()
        }
        y += 76
        label(L2("Efekty dźwiękowe", "Sound effects"))
        choice([(L2("Włączone", "On"), !audio.muted, true), (L2("Wyłączone", "Off"), audio.muted, true)]) { [weak self] i in
            guard let s = self else { return }
            s.audio.muted = i == 1; if i == 1 { s.audio.musicOn = false }
            s.host?.refreshMenus()
        }
        y += 76
        if let h = host {
            label(L2("Rozdzielczość renderowania", "Render resolution"))
            let rs = resolutions
            choice(rs.map { ($0.px == 0 ? L2("Natywna", "Native") : "\($0.px)p", $0.px == h.renderRes, true) }, w: 128) { i in h.setRenderRes(rs[i].px) }
            y += 76
            label(L2("Limit klatek", "Frame limit"))
            let fl = h.availableFrameLimits
            choice(fl.map { ("\($0) FPS", $0 == h.effectiveFrameLimit, true) }, w: 128) { i in h.setFrameLimit(fl[i]) }
            y += 76
            if h.supportsWindowModes {
                label(L2("Tryb wyświetlania", "Display mode"))
                choice([(L2("Okno", "Window"), !h.isFullScreen, true), (L2("Pełny ekran", "Full screen"), h.isFullScreen, true)], w: 180) { i in h.setFullScreen(i == 1) }
                y += 76
            }
        }
        label(L2("Miejsce zapisu", "Save location"))
        r.text(SaveStore.shared.chosen ? SaveStore.shared.displayPath : L2("jeszcze nie wybrano", "not chosen yet"), .ui(15), x: bx, y: y + 4, color: .gray(0.8), maxWidth: 680)
        goldButton(R(bx, y + 50, 200, 44), L2("Zmień…", "Change…"), font: .serif(17, bold: true)) { [weak self] in self?.askSaveLocation(then: nil) }
        y += 126
        label(L2("Język", "Language"))
        languageToggle(y: y + 6)
    }
}

// Game board: layout of rows and slots, the main board drawing, player panels and match flow overlays.
import Foundation
import Metal
import CoreGraphics
import simd

extension Scene {
    /// Board background.
    func drawModernBoard(_ match: Game) {
        renderer.imageFillingScreen("img/board.jpg")
        renderer.gradient(R(0, virtualHeight - 120, virtualWidth, 120), RGBA.black.alpha(0), RGBA.black.alpha(0.35), steps: 8)
    }

    /// Screen rectangle of a player's row.
    func rowRect(_ player: Player, _ rowType: RowType) -> R {
        let mine = player === game?.human
        let y: Float = mine ? [422, 555, 688][rowType.rawValue] : [271, 138, 5][rowType.rawValue]
        return R(710, y, 803, 133)
    }

    /// Special card slot of a row.
    func specialRect(_ player: Player, _ rowType: RowType) -> R { let rowArea = rowRect(player, rowType); return R(579, rowArea.y + 9, cardWidth, cardHeight) }

    /// Position of a player's deck.
    func deckRect(_ player: Player) -> R { player === game?.human ? R(1735, 836, cardWidth, 128) : R(1735, 80, cardWidth, 128) }

    /// Position of a player's graveyard.
    func graveRect(_ player: Player) -> R { player === game?.human ? R(1556, 836, cardWidth, cardHeight) : R(1556, 80, cardWidth, cardHeight) }

    /// Position of a player's leader card.
    func leaderRect(_ player: Player) -> R { player === game?.human ? BoardLayout.humanLeader : BoardLayout.computerLeader }

    /// Positions for `n` cards spread across an area.
    func layout(_ count: Int, in area: R, w width: Float = cardWidth, gap: Float = 4) -> [SIMD2<Float>] {
        guard count > 0 else { return [] }
        let full = Float(count) * width + Float(count - 1) * gap
        var step = width + gap
        if full > area.w { step = (area.w - width) / Float(max(1, count - 1)) }
        let used = step * Float(count - 1) + width
        let x0 = area.x + (area.w - used) / 2
        return (0..<count).map { SIMD2(x0 + Float($0) * step, area.y) }
    }

    /// Animates a card towards its target position.
    func move(_ card: Card, to point: SIMD2<Float>, from spawn: SIMD2<Float>, dt: Float) {
        if !card.hasPos { card.pos = spawn; card.hasPos = true }
        card.pos += (point - card.pos) * min(1, dt * 11)
        card.flash = max(0, card.flash - dt * 1.6)
    }

    /// Overlay image for the weather on a row.
    func weatherOverlay(_ weather: Set<String>) -> String? {
        if weather.contains("frost") || weather.contains("white_frost") { return "overlay_frost" }
        if weather.contains("spider_web") { return "overlay_spider_web" }
        if weather.contains("fog") { return "overlay_fog" }
        if weather.contains("tse_tse") { return "overlay_tse_tse" }
        if weather.contains("sandstorm") { return "overlay_sandstorm" }
        if weather.contains("dragon_wrath") { return "overlay_dragon_wrath" }
        if weather.contains("rain") || weather.contains("storm") { return "overlay_rain" }
        return nil
    }

    /// Whether a special card needs no target.
    func isFreeSpecial(_ card: Card) -> Bool {
        if card.data.isWeather { return true }
        guard card.data.isSpecial else { return false }
        return !["horn", "mardroeme", "morale", "toussaint_wine", "shield", "shield_c", "shield_r", "shield_s", "door", "decoy", "lock", "knockback", "curse"].contains(card.specialKind ?? "")
    }

    /// Game board: draws the whole match screen for one frame and drives the computer's turns.
    func drawGame(_ dt: Float) {
        guard let match = game else { return }
        processEvents(match, dt)
        drawModernBoard(match)
        hover = nil
        let canAct = match.phase == .play && match.current === match.human && !match.busy && match.choice == nil
        if !canAct && match.choice == nil { selected = nil }
        drawActivePlayerHighlight(match)
        let targets = playTargets(match, canAct: canAct)
        for player in [match.computer, match.human] {
            for rowType in RowType.allCases { drawRow(player, rowType, match: match, targets: targets, dt: dt) }
        }
        drawWeatherSlot(match, canAct: canAct, dt: dt)
        for player in [match.computer, match.human] { drawStats(player, match, canAct: canAct) }
        smallButton(BoardLayout.rulesButton, L("Rules"), enabled: true) { [weak self] in self?.openRules() }
        parkHiddenCards(match)
        drawHand(match, canAct: canAct, dt: dt)
        drawMatchButtons(match, canAct: canAct, dt: dt)
        drawFX(dt)
        if let h = hover ?? selected { drawPreview(h) }
        if match.phase == .redraw && match.choice == nil { drawRedraw(match) }
        if let choice = match.choice { drawChoice(choice, match) }
        drawNotes(dt)
        if match.phase == .over && notes.isEmpty { drawEnd(match) }
        runComputerTurn(match, dt: dt)
        if autotest { autoTest(match, dt) }
    }

    /// Rows and cards the human can target with the selected card, plus rows offered by a pending choice.
    struct PlayTargets {
        var rows: [(Player, RowType)] = []
        var decoyCards: [Card] = []
        var choiceRows: [(Player, RowType)] = []
    }

    /// Works out where the currently selected card can be played.
    func playTargets(_ match: Game, canAct: Bool) -> PlayTargets {
        var targets = PlayTargets()
        if let choice = match.choice, case .rows(let rows) = choice.kind { targets.choiceRows = rows }
        guard canAct, let card = selected else { return targets }
        if card.isUnit {
            let playsOnEnemySide = card.has("spy") || card.has("emissary") || card.has("ofiri_envoy")
            targets.rows = match.validRows(for: card, by: match.human).map { (playsOnEnemySide ? match.computer : match.human, $0) }
            return targets
        }
        switch card.specialKind ?? "" {
        case "decoy": targets.decoyCards = match.decoyTargets(for: match.human)
        case "lock", "knockback": targets.rows = match.enemyRowTargets(for: card, by: match.human).map { (match.computer, $0) }
        case "curse": targets.rows = match.curseRows(by: match.human)
        default: targets.rows = match.validRows(for: card, by: match.human).map { (match.human, $0) }
        }
        return targets
    }

    /// Golden glow behind the panel of the player whose turn it is.
    func drawActivePlayerHighlight(_ match: Game) {
        for player in [match.computer, match.human] where match.current === player && match.phase == .play {
            let band = player === match.human ? BoardLayout.humanPanel : BoardLayout.computerPanel
            renderer.gradient(band, RGBA(r: 0.5, g: 0.38, b: 0.12, a: 0.0), RGBA(r: 0.85, g: 0.62, b: 0.2, a: 0.22), steps: 8)
            renderer.rect(R(band.x, player === match.human ? band.y : band.y + band.h - 3, band.w, 3), RGBA.gold.alpha(0.8))
        }
    }

    /// One board row: weather, target highlight, row effect icons, unit cards, special cards and the row score.
    func drawRow(_ player: Player, _ rowType: RowType, match: Game, targets: PlayTargets, dt: Float) {
        let rowArea = rowRect(player, rowType)
        let row = player.row(rowType)
        if let overlay = weatherOverlay(player.weather[rowType.rawValue]) {
            renderer.image("img/icons/\(overlay).png", R(BoardLayout.rowsLeft, rowArea.y + 6, 950, 127), color: .white.alpha(0.7 + 0.15 * sin(time * 1.3 + Float(rowType.rawValue))))
        }
        drawWeatherFX(player.weather[rowType.rawValue], rowArea)
        let wholeRow = R(BoardLayout.rowsLeft, rowArea.y + 2, BoardLayout.rowsWidth, rowArea.h - 4)
        let isTarget = targets.rows.contains { $0.0 === player && $0.1 == rowType }
        let choiceIndex = targets.choiceRows.firstIndex { $0.0 === player && $0.1 == rowType }
        if isTarget || choiceIndex != nil {
            let pulse = 0.18 + 0.1 * sin(time * 5)
            renderer.rect(wholeRow, RGBA(r: 1, g: 0.8, b: 0.3, a: pulse)); renderer.frame(wholeRow, RGBA.gold, 2)
            if let card = selected, isTarget { button(wholeRow) { [weak self] in self?.playSelected(card, row: rowType, rowOwner: player) } }
            if let index = choiceIndex { button(wholeRow) { match.resolveChoice([index]) } }
        }
        var iconX: Float = 712
        for (active, icon) in [(row.lock != nil, "power_lock"), (row.curse != nil, "power_curse"), (row.door, "power_door"), (row.leaderHorn, "power_horn")] where active {
            renderer.image("img/icons/\(icon).png", R(iconX, rowArea.y + 92, 36, 36)); iconX += 38
        }
        let positions = layout(row.cards.count, in: R(rowArea.x + 4, rowArea.y + 5, rowArea.w - 8, cardHeight))
        for (i, card) in row.cards.enumerated() {
            move(card, to: positions[i], from: player === match.human ? SIMD2(1000, 1000) : SIMD2(1000, -150), dt: dt)
            let cardRect = R(card.pos.x, card.pos.y, cardWidth, cardHeight)
            let isDecoyTarget = targets.decoyCards.contains { $0 === card }
            let (flightFrame, flying) = flightRect(card, target: positions[i])
            if flying { renderer.rect(R(flightFrame.x + 10, flightFrame.y + 16, flightFrame.w, flightFrame.h), RGBA.black.alpha(0.35)) }
            drawCard(card, flying ? flightFrame : cardRect, highlight: isDecoyTarget)
            if card.locked { renderer.image("img/icons/power_lock.png", R(cardRect.x + 50, cardRect.y + 4, 32, 32)) }
            if cardRect.contains(mouse) { hover = card }
            if isDecoyTarget, let decoy = selected { button(cardRect) { [weak self] in self?.playSelected(decoy, target: card) } }
        }
        let specialSlot = specialRect(player, rowType)
        for (i, special) in row.specials.enumerated() {
            move(special, to: SIMD2(specialSlot.x + Float(i) * 14, specialSlot.y), from: SIMD2(1000, 1000), dt: dt)
            let cardRect = R(special.pos.x, special.pos.y, cardWidth, cardHeight)
            drawCard(special, cardRect)
            if cardRect.contains(mouse) { hover = special }
        }
        drawRowScore(row.total, centerY: rowArea.y + 70)
    }

    /// Gold disc with the total power of a row.
    func drawRowScore(_ total: Int, centerY: Float) {
        let x = BoardLayout.rowScoreX
        let outer = Renderer.Font.ui(78), inner = Renderer.Font.ui(70), digits = Renderer.Font.ui(28, bold: true)
        renderer.text("●", outer, x: x, y: centerY - renderer.measure("●", outer).h / 2, color: RGBA.goldDark.alpha(0.9), align: .center, shadow: nil)
        renderer.text("●", inner, x: x, y: centerY - renderer.measure("●", inner).h / 2, color: RGBA(r: 0.06, g: 0.05, b: 0.04, a: 1), align: .center, shadow: nil)
        let text = "\(total)"
        renderer.text(text, digits, x: x, y: centerY - renderer.measure(text, digits).h / 2, color: RGBA(r: 1, g: 0.9, b: 0.65, a: 1), align: .center, shadow: nil)
    }

    /// Weather cards in play and, for cards without a target, the area that plays them.
    func drawWeatherSlot(_ match: Game, canAct: Bool, dt: Float) {
        let positions = layout(match.weatherCards.count, in: R(weatherRect.x + 8, weatherRect.y + 8, weatherRect.w - 16, cardHeight))
        for (i, card) in match.weatherCards.enumerated() {
            move(card, to: positions[i], from: SIMD2(1000, 1000), dt: dt)
            let cardRect = R(card.pos.x, card.pos.y, cardWidth, cardHeight)
            drawCard(card, cardRect)
            if cardRect.contains(mouse) { hover = card }
        }
        if canAct, let card = selected, isFreeSpecial(card) {
            let pulse = 0.18 + 0.1 * sin(time * 5)
            renderer.rect(weatherRect, RGBA(r: 1, g: 0.8, b: 0.3, a: pulse)); renderer.frame(weatherRect, RGBA.gold, 2)
            button(weatherRect) { [weak self] in self?.playSelected(card) }
            button(BoardLayout.allRows) { [weak self] in self?.playSelected(card) }
        }
    }

    /// Keeps cards that are not visible (opponent's hand, both decks) at their off-screen or deck positions.
    func parkHiddenCards(_ match: Game) {
        for card in match.computer.hand { card.hasPos = true; card.pos = SIMD2(1000, -160) }
        for player in [match.human, match.computer] {
            let deck = deckRect(player)
            for card in player.deck { card.pos = SIMD2(deck.x, deck.y); card.hasPos = true }
        }
    }

    /// The human's hand: hover lift, selection and click handling.
    func drawHand(_ match: Game, canAct: Bool, dt: Float) {
        let positions = layout(match.human.hand.count, in: R(handRect.x + 8, handRect.y + 6, handRect.w - 16, cardHeight), gap: 3)
        var hoveredCard: Card?
        for (i, card) in match.human.hand.enumerated().reversed() where hoveredCard == nil {
            let area = R(positions[i].x, positions[i].y - card.lift, cardWidth, cardHeight)
            if area.contains(mouse) && match.phase == .play && match.choice == nil { hoveredCard = card }
        }
        let forced = match.human.forcedCard
        for (i, card) in match.human.hand.enumerated() {
            let targetLift: Float = selected === card ? 26 : (hoveredCard === card ? 14 : 0)
            card.lift += (targetLift - card.lift) * min(1, dt * 14)
            move(card, to: positions[i], from: SIMD2(deckRect(match.human).x, deckRect(match.human).y), dt: dt)
            let cardRect = R(card.pos.x, card.pos.y - card.lift, cardWidth, cardHeight)
            drawCard(card, cardRect, highlight: selected === card || forced === card, dim: canAct && forced != nil && forced !== card)
            if i == 0 && canAct { padPrimary = cardRect }
            if hoveredCard === card { hover = card }
            if canAct { button(cardRect) { [weak self] in self?.clickHand(card) } }
        }
    }

    /// Music buttons, Exit to menu (with confirmation), Pass and Give up.
    func drawMatchButtons(_ match: Game, canAct: Bool, dt: Float) {
        let musicButtons: [(String, () -> Void)] = [("♫", { [weak self] in self?.audio.musicOn.toggle() }), ("⏭", { [weak self] in self?.audio.skipTrack() })]
        for (i, (symbol, action)) in musicButtons.enumerated() {
            let box = R(BoardLayout.musicButtonsX + Float(i) * 52, BoardLayout.bottomButtonsY, 46, 46)
            padNoAuto.append(box)
            let active = i == 1 || audio.musicOn
            let hovered = box.contains(mouse)
            renderer.rect(box, RGBA(r: 0.03, g: 0.03, b: 0.04, a: hovered ? 0.9 : 0.7)); renderer.frame(box, RGBA.goldDark.alpha(hovered ? 0.9 : 0.45), 1)
            renderer.text(symbol, .ui(24, bold: true), x: box.mid.x, y: box.y + 8, color: hovered ? .white : RGBA(r: 0.93, g: 0.76, b: 0.35, a: active ? 1 : 0.35), align: .center)
            button(box, action)
        }
        exitConfirmT = max(0, exitConfirmT - dt)
        padNoAuto.append(BoardLayout.exitButton)
        smallButton(BoardLayout.exitButton, exitConfirmT > 0 ? L("Are you sure?") : L("Exit to menu"), enabled: true) { [weak self] in
            guard let scene = self else { return }
            if scene.exitConfirmT > 0 { scene.exitConfirmT = 0; scene.game = nil; scene.screen = .title } else { scene.exitConfirmT = 3 }
        }
        smallButton(BoardLayout.passButton, L("Pass"), enabled: canAct) { [weak self] in self?.selected = nil; self?.game?.humanPass() }
        padNoAuto.append(BoardLayout.giveUpButton)
        smallButton(BoardLayout.giveUpButton, L("Give up"), enabled: match.phase != .over) { [weak self] in self?.game?.surrender() }
    }

    /// Lets the computer move after a short delay once nothing else is happening on screen.
    func runComputerTurn(_ match: Game, dt: Float) {
        let coinShown = fxList.contains { if case .coin = $0.kind { return true }; return false }
        guard match.phase == .play && !match.busy && match.choice == nil && notes.isEmpty && !coinShown && !rulesOpen else { computerTurnTimer = 0; return }
        computerTurnTimer += dt
        guard computerTurnTimer > (autotest ? 0.35 : 0.85) else { return }
        computerTurnTimer = 0
        if match.current === match.computer {
            if autotest { logAIMove(match, match.computer, label: "Player 2") }
            Task { @MainActor in await match.aiTurn(match.computer) }
        } else if autotest && match.current === match.human {
            logAIMove(match, match.human, label: "Player 1")
            Task { @MainActor in await match.aiTurn(match.human) }
        }
    }

    /// Writes the move the AI is about to make to the test log.
    func logAIMove(_ match: Game, _ player: Player, label: String) {
        let score = "[\(match.human.total):\(match.computer.total)]"
        guard let move = match.aiDecide(for: player) else { log("  \(label): pass  \(score)"); return }
        let what = move.card?.key ?? (move.kind == .leader ? "LEADER \(player.leaderAbility)" : "FACTION")
        log("  \(label): \(what)\(move.row.map { " -> \($0)" } ?? "")  \(score)")
    }

    /// Automatic play used by tests (GWENT_AUTOTEST).
    func autoTest(_ match: Game, _ dt: Float) {
        autoT += dt
        let progressSignature = "\(match.turn)|\(match.round)|\(match.human.hand.count)|\(match.computer.hand.count)|\(match.phase)|\(match.human.total)|\(match.computer.total)"
        if progressSignature != lastSig { lastSig = progressSignature; watchdog = 0 } else { watchdog += dt }
        if watchdog > 25 {
            log("HANG: phase \(match.phase), turn \(match.current === match.human ? "Player 1" : "Player 2"), busy \(match.busy), choice: \(match.choice?.title ?? "none"), leaders \(match.human.leaderAbility)/\(match.computer.leaderAbility)")
            watchdog = 0; gamesPlayed += 1; startGame(); return
        }
        if match.phase == .redraw && autoT > 1 { autoT = 0; match.finishRedraw() }
        if match.phase == .over && notes.isEmpty && autoT > 2 {
            autoT = 0; gamesPlayed += 1
            log("END: rounds \(match.history.map { "\($0.human):\($0.computer)" }.joined(separator: ", ")) winner: \(match.winner === match.human ? "Player 1" : (match.winner === match.computer ? "Player 2" : "draw"))")
            startGame()
        }
    }

    /// Player panel: name, faction, lives, card count and leader.
    func drawStats(_ player: Player, _ match: Game, canAct: Bool) {
        let mine = player === match.human
        let panelY: Float = mine ? 666 : 263
        renderer.image("img/icons/profile.png", R(128, panelY + 13, 99, 108))
        renderer.image("img/icons/icon_player_border.png", R(118, panelY + 7, 116, 127))
        let shield = R(106, mine ? 748 : 270, 50, 55)
        renderer.image("img/icons/deck_shield_\(player.faction).png", shield)
        if shield.contains(mouse) { hoverText = gameData.factionName(player.faction) + "\n" + gameData.factionDesc(player.faction) }
        let nameY: Float = mine ? 728 : 271
        renderer.text(mine ? playerName : (careerFightName ?? L("Player 2")), .gwent(24), x: 239, y: nameY, color: RGBA(r: 0.96, g: 0.85, b: 0.56, a: 1))
        renderer.text(gameData.factionName(player.faction), .ui(17), x: 239, y: nameY + 27, color: .gray(0.85), maxWidth: 190)
        let handCountY: Float = mine ? 680 : 356
        renderer.image("img/icons/icon_card_count.png", R(240, handCountY + 4, 30, 32))
        renderer.text("\(player.hand.count)", .ui(30, bold: true), x: 274, y: handCountY, color: RGBA(r: 0.93, g: 0.72, b: 0.2, a: 1))
        let gemsY: Float = mine ? 678 : 352
        renderer.image("img/icons/icon_gem_\(player.gems >= 1 ? "on" : "off").png", R(319, gemsY, 41, 42))
        renderer.image("img/icons/icon_gem_\(player.gems >= 2 ? "on" : "off").png", R(360, gemsY, 41, 42))
        let scoreBadge = R(427, mine ? 708 : 305, 54, 54)
        renderer.image("img/icons/score_total_\(mine ? "me" : "op").png", scoreBadge)
        if player.total > player.opponent.total { renderer.image("img/icons/icon_high_score.png", R(scoreBadge.x - 14, scoreBadge.y - 12, 82, 78)) }
        let textHeight = renderer.measure("\(player.total)", .ui(30, bold: true)).h
        renderer.text("\(player.total)", .ui(30, bold: true), x: scoreBadge.mid.x, y: scoreBadge.mid.y - textHeight / 2, color: .black, align: .center, shadow: RGBA.white.alpha(0.5))
        if player.passed { renderer.text(L("Passed"), .ui(24, bold: true), x: 330, y: mine ? 640 : 410, color: RGBA(r: 0.93, g: 0.72, b: 0.2, a: 1), align: .center) }
        let leaderArea = leaderRect(player)
        player.leader.pos = SIMD2(leaderArea.x, leaderArea.y); player.leader.hasPos = true
        let avail = match.leaderAvailable(player)
        drawCard(player.leader, leaderArea, dim: !avail && !Game.passiveLeaders.contains(player.leaderAbility))
        renderer.image("img/icons/icon_leader_active.png", R(260, leaderArea.y + 51, 38, 38), color: .white.alpha(avail ? 1 : 0.25))
        if leaderArea.contains(mouse) { hover = player.leader }
        if mine && canAct && avail {
            if leaderArea.contains(mouse) { renderer.frame(leaderArea.inset(-3), RGBA.gold, 3) }
            button(leaderArea) { [weak self] in self?.game?.humanLeader() }
            button(R(260, leaderArea.y + 51, 38, 38)) { [weak self] in self?.game?.humanLeader() }
        }
        if mine, let factionAbility = match.factionActive(player) {
            let box = BoardLayout.factionAbilityButton
            let title = factionAbility == "transform" ? L("Transform") : (factionAbility.hasPrefix("skip") ? L("Skip turn") : L("Faction ability"))
            smallButton(box, title, enabled: canAct) { [weak self] in self?.game?.humanFaction() }
        }
        let deckArea = deckRect(player)
        let count = player.deck.count
        for i in 0..<min(4, count) { renderer.image("img/icons/deck_back_\(player.faction).jpg", R(deckArea.x - Float(i), deckArea.y - Float(i), deckArea.w, deckArea.h)) }
        if count > 0 {
            renderer.rect(R(deckArea.mid.x - 22, deckArea.y + deckArea.h - 40, 44, 30), RGBA.black.alpha(0.6))
            renderer.text("\(count)", .ui(22, bold: true), x: deckArea.mid.x, y: deckArea.y + deckArea.h - 38, color: .white, align: .center)
        }
        let graveArea = graveRect(player)
        for card in player.grave { move(card, to: SIMD2(graveArea.x, graveArea.y), from: SIMD2(graveArea.x, graveArea.y), dt: 1 / 60) }
        if let top = player.grave.last {
            drawCard(top, R(top.pos.x, top.pos.y, cardWidth, cardHeight))
            if R(top.pos.x, top.pos.y, cardWidth, cardHeight).contains(mouse) { hover = top }
        }
    }

    /// Selects or plays a card from the hand.
    func clickHand(_ card: Card) {
        guard let match = game, match.phase == .play, match.current === match.human, !match.busy, match.choice == nil else { return }
        if let forced = match.human.forcedCard, forced !== card { notes.append((L("You must play the marked card."), nil)); return }
        if selected === card {
            if isFreeSpecial(card) { playSelected(card); return }
            if card.isUnit, match.validRows(for: card, by: match.human).count == 1 { playSelected(card, row: match.validRows(for: card, by: match.human)[0]); return }
            if !card.isUnit, ["lock", "knockback"].contains(card.specialKind ?? "") == false, card.specialKind != "decoy", card.specialKind != "curse", match.validRows(for: card, by: match.human).count == 1 {
                playSelected(card, row: match.validRows(for: card, by: match.human)[0], rowOwner: match.human); return
            }
            selected = nil
            return
        }
        selected = card
        audio.play("card", volume: 0.5)
    }

    /// Plays the selected card on a row or target.
    func playSelected(_ card: Card, row: RowType? = nil, rowOwner: Player? = nil, target: Card? = nil) {
        guard let match = game else { return }
        selected = nil
        match.humanPlay(card, row: row, rowOwner: rowOwner, target: target)
    }

    /// Turns engine events into notifications, sounds and effects.
    func processEvents(_ match: Game, _ dt: Float) {
        for event in match.events {
            switch event {
            case .notify(let text, let icon): notes.append((text, icon)); if notes.count > 4 { notes.removeFirst(notes.count - 4) }
            case .sound(let soundName): audio.play(soundName)
            case .flash(let flashedCard): flashedCard.flash = 1
            case .anim, .burn, .coin: addFX(event)
            }
        }
        match.events.removeAll()
    }

    /// Draws the current notification banner.
    func drawNotes(_ dt: Float) {
        if let tooltip = hoverText, game?.choice == nil {
            let w: Float = 420
            let h = renderer.measure(tooltip, .ui(17), maxWidth: w - 24).h + 20
            let box = R(min(mouse.x + 18, virtualWidth - w - 10), min(mouse.y + 18, virtualHeight - h - 10), w, h)
            renderer.rect(box, RGBA(r: 0.06, g: 0.05, b: 0.03, a: 0.94)); renderer.frame(box, RGBA.goldDark.alpha(0.7), 1)
            renderer.text(tooltip, .ui(17), x: box.x + 12, y: box.y + 10, color: .gray(0.92), maxWidth: w - 24)
        }
        hoverText = nil
        guard let note = notes.first else { return }
        noteT += dt
        let duration: Float = autotest ? 0.5 : 1.25
        let alpha = max(0, min(1, min(noteT / 0.15, (duration - noteT) / 0.2)))
        let entry = min(1, noteT / 0.18), ease = 1 - (1 - entry) * (1 - entry)
        let font = Renderer.Font.gwent(34)
        let textWidth = min(900, renderer.measure(note.text, font, maxWidth: 900).w)
        let textHeight = renderer.measure(note.text, font, maxWidth: 900).h
        let iconWidth: Float = note.icon == nil ? 0 : 96
        let w = textWidth + iconWidth + 90, h = max(110, textHeight + 50)
        let card = R(960 - w / 2, 500 - h / 2 + (1 - ease) * 18, w, h)
        renderer.rect(renderer.visibleRect, RGBA.black.alpha(0.25 * alpha))
        renderer.gradient(card, RGBA(r: 0.08, g: 0.07, b: 0.06, a: 0.93 * alpha), RGBA(r: 0.02, g: 0.02, b: 0.03, a: 0.95 * alpha), steps: 8)
        renderer.rect(R(card.x, card.y, card.w, 2), RGBA.gold.alpha(0.9 * alpha))
        renderer.rect(R(card.x, card.y + card.h - 1, card.w, 1), RGBA.goldDark.alpha(0.6 * alpha))
        renderer.frame(card, RGBA.goldDark.alpha(0.35 * alpha), 1)
        var x = card.x + 45
        if let icon = note.icon { renderer.image("img/icons/\(icon).png", R(x - 10, card.mid.y - 52, 104, 104), color: .white.alpha(alpha)); x += iconWidth + 10 }
        renderer.text(note.text, font, x: note.icon == nil ? card.mid.x : x, y: card.mid.y - textHeight / 2, color: RGBA(r: 0.97, g: 0.88, b: 0.62, a: alpha), maxWidth: 900, align: note.icon == nil ? .center : .left, shadow: nil)
        if noteT >= duration { notes.removeFirst(); noteT = 0 }
    }

    /// Full-screen overlay with a set of cards to choose from.
    func overlayCards(_ cards: [Card], title: String, info: String?, marked: [Card] = [], _ onClick: @escaping (Card) -> Void) -> R {
        renderer.rect(renderer.visibleRect, RGBA.black.alpha(0.74))
        renderer.text(title, .serif(32, bold: true), x: 960, y: 70, color: RGBA.gold, maxWidth: 1500, align: .center)
        if let info = info { renderer.text(info, .ui(22), x: 960, y: 150, color: .gray(0.9), align: .center) }
        let count = cards.count
        let perRow = count > 14 ? 10 : (count > 6 ? Int((Double(count) / 2).rounded(.up)) : max(1, count))
        let rows = Int((Double(count) / Double(perRow)).rounded(.up))
        let w: Float = rows > 2 ? 120 : (rows > 1 ? 168 : 190), h = w * 1.437, gap: Float = rows > 2 ? 12 : 22
        let y0: Float = rows > 1 ? 195 : 330
        for (i, card) in cards.enumerated() {
            let rowI = i / perRow, colI = i % perRow
            let inRow = min(perRow, count - rowI * perRow)
            let x0 = 960 - (Float(inRow) * w + Float(inRow - 1) * gap) / 2
            let cardRect = R(x0 + Float(colI) * (w + gap), y0 + Float(rowI) * (h + gap), w, h)
            if cardRect.y > 960 { break }
            let hovered = cardRect.contains(mouse)
            drawCardLarge(card, cardRect)
            if marked.contains(where: { $0 === card }) { renderer.frame(cardRect.inset(-5), RGBA(r: 0.3, g: 0.85, b: 0.3, a: 1), 4) }
            if hovered { renderer.frame(cardRect.inset(-4), RGBA.gold, 3); hover = card }
            button(cardRect) { onClick(card) }
        }
        return R(0, min(985, y0 + Float(rows) * (h + gap)), virtualWidth, 0)
    }

    /// Redraw phase overlay.
    func drawRedraw(_ match: Game) {
        let end = overlayCards(match.human.hand, title: L("Click a card to redraw it"),
                               info: L("Redraws left: ") + "\(match.redrawsLeft)") { [weak self] card in
            guard let match = self?.game, match.redrawsLeft > 0, !match.busy else { return }
            if let replacement = match.redraw(card) { replacement.hasPos = false }
            if match.redrawsLeft == 0 { match.finishRedraw() }
        }
        goldButton(R(960 - 150, min(990, end.y + 10), 300, 60), L("Done"), font: .gwent(30)) { [weak self] in self?.game?.finishRedraw() }
        if let h = hover { drawPreview(h) }
    }

    /// Overlay for a pending choice of the human player.
    func drawChoice(_ choice: Choice, _ match: Game) {
        switch choice.kind {
        case .cards(let cards, let minCount, let maxCount):
            let multi = maxCount > 1 || minCount != 1
            let end = overlayCards(cards, title: choice.title, info: multi ? L("Selected: ") + "\(multiSel.count) / \(maxCount)" : nil, marked: multiSel) { [weak self] c in
                guard let strongSelf = self else { return }
                if !multi { match.resolveChoice([cards.firstIndex { $0 === c }!]); return }
                if let i = strongSelf.multiSel.firstIndex(where: { $0 === c }) { strongSelf.multiSel.remove(at: i) }
                else if strongSelf.multiSel.count < maxCount { strongSelf.multiSel.append(c) }
            }
            var buttonX: Float = 960 - 150
            if multi {
                let selectionValid = multiSel.count >= minCount && multiSel.count <= maxCount
                goldButton(R(choice.canCancel ? 960 - 320 : buttonX, min(990, end.y + 10), 300, 60), L("Done"), font: .gwent(30), enabled: selectionValid) { [weak self] in
                    guard let strongSelf = self else { return }
                    let idx = strongSelf.multiSel.compactMap { card in cards.firstIndex { $0 === card } }
                    strongSelf.multiSel = []; match.resolveChoice(idx)
                }
                buttonX = 960 + 20
            }
            if choice.canCancel { goldButton(R(multi ? buttonX : 960 - 150, min(990, end.y + 10), 300, 60), L("Skip"), font: .serif(24, bold: true)) { [weak self] in self?.multiSel = []; match.resolveChoice(nil) } }
            if let h = hover { drawPreview(h) }
        case .reveal(let cards):
            let end = overlayCards(cards, title: choice.title, info: nil) { _ in match.resolveChoice(nil) }
            goldButton(R(960 - 150, min(990, end.y + 10), 300, 60), L("Close"), font: .serif(24, bold: true)) { match.resolveChoice(nil) }
            if let h = hover { drawPreview(h) }
        case .options(let opts):
            renderer.rect(renderer.visibleRect, RGBA.black.alpha(0.55))
            let cols = opts.count > 4 ? 5 : opts.count
            let buttonWidth: Float = opts.count > 4 ? 120 : 340, buttonHeight: Float = 64
            let rowsN = Int((Double(opts.count) / Double(cols)).rounded(.up))
            let boxH: Float = 170 + Float(rowsN) * (buttonHeight + 16)
            let box = R(960 - 420, 540 - boxH / 2, 840, boxH)
            renderer.gradient(box, RGBA(r: 0.12, g: 0.09, b: 0.05, a: 0.97), RGBA(r: 0.05, g: 0.04, b: 0.02, a: 0.97), steps: 10)
            renderer.frame(box, RGBA.goldDark, 2)
            renderer.text(choice.title, .serif(26, bold: true), x: 960, y: box.y + 30, color: RGBA.gold, maxWidth: 760, align: .center)
            for (i, option) in opts.enumerated() {
                let row = i / cols, col = i % cols
                let inRow = min(cols, opts.count - row * cols)
                let x0 = 960 - (Float(inRow) * buttonWidth + Float(inRow - 1) * 16) / 2
                goldButton(R(x0 + Float(col) * (buttonWidth + 16), box.y + 120 + Float(row) * (buttonHeight + 16), buttonWidth, buttonHeight), option, font: .serif(22, bold: true)) { match.resolveChoice([i]) }
            }
        case .rows:
            let box = BoardLayout.rowChoiceBar
            renderer.rect(box, RGBA.black.alpha(0.8)); renderer.frame(box, RGBA.goldDark.alpha(0.7), 1)
            renderer.text(choice.title, .serif(22, bold: true), x: box.mid.x, y: box.y + 10, color: RGBA.gold, maxWidth: 940, align: .center)
        }
    }

    /// End-of-match screen.
    func drawEnd(_ match: Game) {
        renderer.rect(renderer.visibleRect, RGBA.black.alpha(0.8))
        let image = match.winner === match.human ? "end_win" : (match.winner === match.computer ? "end_lose" : "end_draw")
        renderer.imageContain("img/icons/\(image).png", BoardLayout.endOfMatchBanner)
        renderer.text(L("Round"), .serif(24, bold: true), x: 760, y: 500, color: .gray(0.8), align: .center)
        renderer.text(playerName, .serif(24, bold: true), x: 960, y: 500, color: RGBA.gold, maxWidth: 190, align: .center)
        renderer.text(careerFightName ?? L("Player 2"), .serif(24, bold: true), x: 1160, y: 500, color: RGBA.gold, maxWidth: 190, align: .center)
        for (i, h) in match.history.enumerated() {
            let y = 545 + Float(i) * 44
            renderer.text("\(i + 1)", .ui(26, bold: true), x: 760, y: y, color: .white, align: .center)
            renderer.text("\(h.human)", .ui(26, bold: true), x: 960, y: y, color: h.winner === match.human ? RGBA.gold : .white, align: .center)
            renderer.text("\(h.computer)", .ui(26, bold: true), x: 1160, y: y, color: h.winner === match.computer ? RGBA.gold : .white, align: .center)
        }
        if let fightIndex = careerFight {
            if match.winner === match.human {
                goldButton(R(960 - 160, 760, 320, 64), L("Claim reward"), font: .serif(26, bold: true)) { [weak self] in
                    guard let strongSelf = self else { return }
                    strongSelf.careerRewards = strongSelf.career.rewardOptions(fightIndex); strongSelf.careerNewLeader = strongSelf.career.win(fightIndex)
                    strongSelf.careerFight = nil; strongSelf.game = nil; strongSelf.careerChapter = nil; strongSelf.screen = .career
                }
            } else {
                goldButton(R(960 - 330, 760, 300, 64), L("Try again"), font: .serif(26, bold: true)) { [weak self] in self?.startCareerFight(fightIndex) }
                goldButton(R(960 + 30, 760, 300, 64), L("Career"), font: .serif(26, bold: true)) { [weak self] in self?.careerFight = nil; self?.game = nil; self?.screen = .career }
            }
            return
        }
        goldButton(R(960 - 330, 760, 300, 64), L("Replay"), font: .serif(26, bold: true)) { [weak self] in self?.startGame() }
        goldButton(R(960 + 30, 760, 300, 64), L("Main menu"), font: .serif(26, bold: true)) { [weak self] in self?.game = nil; self?.screen = .title }
    }
}

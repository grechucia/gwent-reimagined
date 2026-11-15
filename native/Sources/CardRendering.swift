// Card rendering: small board cards, large cards with quotes and the card preview.
import Foundation
import Metal
import CoreGraphics
import simd

extension Scene {
    /// Icon file for an ability.
    func abilityIcon(_ ability: String) -> String {
        var iconName = ability
        if iconName == "cerys" { iconName = "muster" }
        if iconName.hasPrefix("avenger") { iconName = "avenger" }
        if ["scorch_c", "scorch_r", "scorch_s"].contains(iconName) { iconName = "scorch_combat" }
        if ["shield_c", "shield_r", "shield_s"].contains(iconName) { iconName = "shield" }
        return "img/icons/card_ability_\(iconName).png"
    }

    /// Power badge image of a card.
    func powerBadge(_ card: Card) -> String {
        if card.hero { return "img/icons/power_hero.png" }
        if card.data.isSpecial || card.data.isWeather {
            var badgeName = card.data.abilities.first ?? "normal"
            if ["shield_c", "shield_r", "shield_s"].contains(badgeName) { badgeName = "shield" }
            return "img/icons/power_\(badgeName).png"
        }
        return "img/icons/power_normal.png"
    }

    /// Draws a small card with power, row and ability icons.
    func drawCard(_ card: Card, _ cardRect: R, highlight: Bool = false, dim dimmed: Bool = false) {
        let scale = cardRect.w / cardWidth
        renderer.imageCover(card.data.image, cardRect, color: dimmed ? .gray(0.45) : .white)
        if card.flash > 0 { renderer.rect(cardRect, RGBA(r: 1, g: 0.9, b: 0.6, a: card.flash * 0.35)) }
        if card.data.isLeader { if highlight { renderer.frame(cardRect.inset(-3), RGBA.gold, 3) }; return }
        renderer.image(powerBadge(card), R(cardRect.x - 3 * scale, cardRect.y - 5 * scale, 60 * scale, 61 * scale))
        if card.data.isUnit {
            let power = card.power
            let col: RGBA = card.hero ? .white : (power > card.basePower ? RGBA(r: 0.1, g: 0.55, b: 0.1, a: 1) : (power < card.basePower ? RGBA(r: 0.75, g: 0.1, b: 0.1, a: 1) : .black))
            let badgeCenterX: Float = 16.3, badgeCenterY: Float = 14.6
            var popAmount: Float = 0
            if let seen = powerSeen[card.id] { popAmount = seen.0 != power ? 0.45 : max(0, seen.1 - frameDT) }
            powerSeen[card.id] = (power, popAmount)
            let font = Renderer.Font.ui((card.hero ? 21 : 19) * scale * (1 + popAmount * 1.1), bold: true)
            let textHeight = renderer.measure("\(power)", font).h
            if popAmount > 0 { renderer.quad(glowTex, R(cardRect.x + badgeCenterX * scale - 22 * scale, cardRect.y + badgeCenterY * scale - 22 * scale, 44 * scale, 44 * scale), color: RGBA(r: 1, g: 0.9, b: 0.5, a: popAmount * 1.6)) }
            renderer.text("\(power)", font, x: cardRect.x + badgeCenterX * scale, y: cardRect.y + badgeCenterY * scale - textHeight / 2, color: col, align: .center, shadow: nil)
            let rowName = card.data.row.hasPrefix("agile") ? card.data.row : card.data.row
            renderer.image("img/icons/card_row_\(rowName).png", R(cardRect.x + 56 * scale, cardRect.y + 91 * scale, 28 * scale, 27 * scale))
            let abis = card.data.abilities.filter { $0 != "hero" }
            if let lastAbility = abis.last { renderer.image(abilityIcon(lastAbility), R(cardRect.x + 28 * scale, cardRect.y + 91 * scale, 28 * scale, 27 * scale)) }
            else if card.data.row.hasPrefix("agile") { renderer.image("img/icons/card_ability_agile.png", R(cardRect.x + 28 * scale, cardRect.y + 91 * scale, 28 * scale, 27 * scale)) }
            if abis.count > 1 { renderer.image(abilityIcon(abis[abis.count - 2]), R(cardRect.x + 0 * scale, cardRect.y + 91 * scale, 28 * scale, 27 * scale)) }
        }
        if highlight { renderer.frame(cardRect.inset(-3), RGBA.gold, 3) }
    }

    /// Draws a large card with its name and quote.
    func drawCardLarge(_ card: Card, _ cardRect: R, cache: String = "") {
        renderer.imageCover(card.data.image, cardRect)
        let bandHeight = cardRect.h * 0.26
        let band = R(cardRect.x, cardRect.y + cardRect.h - bandHeight, cardRect.w, bandHeight)
        renderer.gradient(band, RGBA(r: 0.95, g: 0.91, b: 0.82, a: 1), RGBA(r: 0.84, g: 0.77, b: 0.63, a: 1), steps: 10)
        renderer.rect(R(band.x, band.y, band.w, max(1.5, cardRect.w * 0.008)), RGBA(r: 0.55, g: 0.42, b: 0.2, a: 1))
        let nameFont = Renderer.Font.serif(max(10, cardRect.w * 0.078), bold: true)
        let nameHeight = renderer.text(gameData.cardName(card.data), nameFont, x: band.mid.x, y: band.y + bandHeight * 0.08, color: RGBA(r: 0.22, g: 0.15, b: 0.06, a: 1), maxWidth: band.w - cardRect.w * 0.08, align: .center, shadow: nil).h
        let quote = gameData.cardQuote(card.data)
        if !quote.isEmpty && cardRect.w >= 150 {
            renderer.text(quote, .serif(max(9, cardRect.w * 0.053), italic: true), x: band.mid.x, y: band.y + bandHeight * 0.06 + nameHeight, color: RGBA(r: 0.13, g: 0.09, b: 0.04, a: 1), maxWidth: band.w - cardRect.w * 0.1, align: .center, shadow: nil)
        }
        if card.data.isLeader { return }
        let scale = cardRect.w / cardWidth * 0.5
        renderer.image(powerBadge(card), R(cardRect.x - 3 * scale, cardRect.y - 5 * scale, 60 * scale, 61 * scale))
        if card.data.isUnit {
            let badgeCenterX: Float = 16.3, badgeCenterY: Float = 14.6
            let font = Renderer.Font.ui((card.hero ? 21 : 19) * scale, bold: true)
            let textHeight = renderer.measure("\(card.basePower)", font).h
            renderer.text("\(card.basePower)", font, x: cardRect.x + badgeCenterX * scale, y: cardRect.y + badgeCenterY * scale - textHeight / 2, color: card.hero ? .white : .black, align: .center, shadow: nil)
            renderer.image("img/icons/card_row_\(card.data.row).png", R(cardRect.x - 3 * scale + 6 * scale, cardRect.y + 58 * scale, 44 * scale, 42 * scale))
            if let lastAbility = card.data.abilities.filter({ $0 != "hero" }).last { renderer.image(abilityIcon(lastAbility), R(cardRect.x + 3 * scale, cardRect.y + 102 * scale, 44 * scale, 42 * scale)) }
        }
    }

    /// Card preview with the ability description.
    func drawPreview(_ card: Card) {
        // On phones the preview is larger and uses the extra screen width available in fill mode.
        let large = Platform.isPhone
        let visible = renderer.visibleRect
        let columnWidth: Float = large ? 560 : 350
        // Keep clear of the rounded corners and the camera housing at the screen edges.
        let edgeMargin: Float = 130
        let columnX = large ? visible.x + visible.w - columnWidth - edgeMargin : ScreenLayout.cardPreviewText.x
        let cardRect = large ? R(columnX + (columnWidth - 300) / 2, 40, 300, 431) : ScreenLayout.cardPreviewCard
        renderer.rect(cardRect.inset(-6), RGBA.black.alpha(0.55))
        drawCardLarge(card, cardRect)
        var lines: [(String, String)] = []
        if card.data.isLeader {
            if let leaderAbility = card.data.abilities.last { lines.append((L("Leader Ability"), gameData.abilityDesc(leaderAbility))) }
        } else {
            if card.data.row.hasPrefix("agile") { lines.append((gameData.abilityName("agile"), gameData.abilityDesc("agile"))) }
            for ability in card.data.abilities where ability != "hero" { lines.append((gameData.abilityName(ability), gameData.abilityDesc(ability))) }
            if card.hero { lines.append((L("Hero"), gameData.abilityDesc("hero"))) }
        }
        guard !lines.isEmpty else { return }
        let titleFont = Renderer.Font.serif(large ? 26 : 19, bold: true), bodyFont = Renderer.Font.ui(large ? 22 : 16)
        let textWidth = columnWidth - 24
        let box = R(columnX, cardRect.y + cardRect.h + 12, columnWidth, virtualHeight - (cardRect.y + cardRect.h + 12) - 8)
        var contentHeight: Float = 12
        for (title, description) in lines {
            contentHeight += renderer.measure(title, titleFont, maxWidth: textWidth).h + renderer.measure(description, bodyFont, maxWidth: textWidth).h + 10
        }
        let panel = R(box.x, box.y, box.w, min(box.h, contentHeight))
        renderer.rect(panel, RGBA(r: 0.06, g: 0.05, b: 0.03, a: 0.94))
        renderer.frame(panel, RGBA.goldDark.alpha(0.6), 1)
        var y = box.y + 6
        for (title, description) in lines {
            if y > box.y + box.h - 20 { break }
            y += renderer.text(title, titleFont, x: box.x + 12, y: y, color: RGBA.gold, maxWidth: textWidth).h
            y += renderer.text(description, bodyFont, x: box.x + 12, y: y, color: .gray(0.95), maxWidth: textWidth).h + 10
        }
    }
}

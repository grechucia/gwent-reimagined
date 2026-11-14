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
    func drawCard(_ card: Card, _ cardRect: R, highlight: Bool = false, dim: Bool = false) {
        let scale = cardRect.w / cardWidth
        renderer.imageCover(card.data.image, cardRect, color: dim ? .gray(0.45) : .white)
        if card.flash > 0 { renderer.rect(cardRect, RGBA(r: 1, g: 0.9, b: 0.6, a: card.flash * 0.35)) }
        if card.data.isLeader { if highlight { renderer.frame(cardRect.inset(-3), RGBA.gold, 3) }; return }
        renderer.image(powerBadge(card), R(cardRect.x - 3 * scale, cardRect.y - 5 * scale, 60 * scale, 61 * scale))
        if card.data.isUnit {
            let power = card.power
            let col: RGBA = card.hero ? .white : (power > card.basePower ? RGBA(r: 0.1, g: 0.55, b: 0.1, a: 1) : (power < card.basePower ? RGBA(r: 0.75, g: 0.1, b: 0.1, a: 1) : .black))
            let cx: Float = 16.3, cy: Float = 14.6
            var pop: Float = 0
            if let seen = powerSeen[card.id] { pop = seen.0 != power ? 0.45 : max(0, seen.1 - frameDT) }
            powerSeen[card.id] = (power, pop)
            let font = Renderer.Font.ui((card.hero ? 21 : 19) * scale * (1 + pop * 1.1), bold: true)
            let textHeight = renderer.measure("\(power)", font).h
            if pop > 0 { renderer.quad(glowTex, R(cardRect.x + cx * scale - 22 * scale, cardRect.y + cy * scale - 22 * scale, 44 * scale, 44 * scale), color: RGBA(r: 1, g: 0.9, b: 0.5, a: pop * 1.6)) }
            renderer.text("\(power)", font, x: cardRect.x + cx * scale, y: cardRect.y + cy * scale - textHeight / 2, color: col, align: .center, shadow: nil)
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
            let cx: Float = 16.3, cy: Float = 14.6
            let font = Renderer.Font.ui((card.hero ? 21 : 19) * scale, bold: true)
            let textHeight = renderer.measure("\(card.basePower)", font).h
            renderer.text("\(card.basePower)", font, x: cardRect.x + cx * scale, y: cardRect.y + cy * scale - textHeight / 2, color: card.hero ? .white : .black, align: .center, shadow: nil)
            renderer.image("img/icons/card_row_\(card.data.row).png", R(cardRect.x - 3 * scale + 6 * scale, cardRect.y + 58 * scale, 44 * scale, 42 * scale))
            if let lastAbility = card.data.abilities.filter({ $0 != "hero" }).last { renderer.image(abilityIcon(lastAbility), R(cardRect.x + 3 * scale, cardRect.y + 102 * scale, 44 * scale, 42 * scale)) }
        }
    }

    /// Card preview with the ability description.
    func drawPreview(_ card: Card) {
        let cardRect = ScreenLayout.cardPreviewCard
        renderer.rect(cardRect.inset(-6), RGBA.black.alpha(0.55))
        drawCardLarge(card, cardRect)
        var lines: [(String, String)] = []
        if card.data.isLeader { if let lastAbility = card.data.abilities.last { lines.append((L("Leader Ability"), gameData.abilityDesc(lastAbility))) } }
        else {
            if card.data.row.hasPrefix("agile") { lines.append((gameData.abilityName("agile"), gameData.abilityDesc("agile"))) }
            for lastAbility in card.data.abilities where lastAbility != "hero" { lines.append((gameData.abilityName(lastAbility), gameData.abilityDesc(lastAbility))) }
            if card.hero { lines.append((L("Hero"), gameData.abilityDesc("hero"))) }
        }
        guard !lines.isEmpty else { return }
        var y: Float = 720
        let box = ScreenLayout.cardPreviewText
        var h: Float = 12
        for (title, description) in lines { h += renderer.measure(title, .serif(19, bold: true), maxWidth: 326).h + renderer.measure(description, .ui(16), maxWidth: 326).h + 10 }
        renderer.rect(R(box.x, box.y, box.w, min(box.h, h)), RGBA(r: 0.06, g: 0.05, b: 0.03, a: 0.92))
        renderer.frame(R(box.x, box.y, box.w, min(box.h, h)), RGBA.goldDark.alpha(0.6), 1)
        for (title, description) in lines {
            if y > 1050 { break }
            y += renderer.text(title, .serif(19, bold: true), x: box.x + 12, y: y, color: RGBA.gold, maxWidth: 326).h
            y += renderer.text(description, .ui(16), x: box.x + 12, y: y, color: .gray(0.92), maxWidth: 326).h + 10
        }
    }
}

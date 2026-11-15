// Board scoring: recalculates every card's power (weather, horns, bonds, morale).
import Foundation

extension Game {
    /// Strongest card of a list.
    func best1(_ cards: [Card]) -> Card? { cards.max { aiCardValue($0) < aiCardValue($1) } }

    /// Recalculates the power of every card on the board.
    func recalc() {
        for player in [human, computer] {
            let side = player.rowCards
            let inspires = side.filter { $0.act("inspire") }
            let maxInspire = inspires.map { $0.basePower }.max() ?? 0
            let whorshippers = side.filter { $0.act("whorshipper") }.count
            var schools: [String: Int] = [:]
            for card in side where !card.locked { if let school = card.school { schools[school, default: 0] += 1 } }
            for rowType in RowType.allCases {
                let row = player.row(rowType)
                let bondCounts = Dictionary(grouping: row.cards.filter { $0.act("bond") }, by: { $0.groupKey }).mapValues { $0.count }
                let morale = row.cards.filter { $0.act("morale") }.count + row.specials.filter { $0.specialKind == "morale" }.count + row.factionMorale
                let wine = row.specials.filter { $0.specialKind == "toussaint_wine" }.count + row.cards.filter { $0.act("toussaint_wine") }.count
                let horns = row.hornCount
                let w = player.weather[rowType.rawValue]
                var total = 0
                for card in row.cards {
                    card.power = cardScore(card, rowType, player, bondCounts: bondCounts, morale: morale, wine: wine, horns: horns, weather: w,
                                        inspire: inspires.count > 1 ? maxInspire : nil, whorshippers: whorshippers, schools: schools)
                    total += card.power
                }
                row.total = total
            }
            player.total = player.rows.reduce(0) { $0 + $1.total } + player.aamadBonus
        }
    }

    /// Power of a single card on a row after weather, horns, bonds and morale.
    func cardScore(_ card: Card, _ rowType: RowType, _ player: Player, bondCounts: [String: Int], morale: Int, wine: Int, horns: Int, weather w: Set<String>,
                   inspire: Int?, whorshippers: Int, schools: [String: Int]) -> Int {
        if card.key == "spe_decoy" { return 0 }
        var basePower = card.tempStrength ?? card.basePower
        if card.hero { return basePower * card.multiplier + card.bonus }
        if card.has("spy") || card.has("emissary") || card.has("ofiri_envoy") { basePower = Int(floor(spyMult * Double(basePower))) }
        if let inspired = inspire, card.act("inspire") { basePower = inspired }
        if let fixed = card.setTo { basePower = fixed }
        if !w.isEmpty {
            let immune = w.allSatisfy { ($0 == "fog" && card.has("fog_summoning")) || ($0 == "sandstorm" && card.has("sandstorm_immunity")) }
            if !immune {
                let limit = card.has("adaptive") ? 2 : 1
                basePower = player.halfWeather ? max(min(limit, basePower), basePower / 2) : min(limit, basePower)
            }
        }
        if card.act("bond"), let bondSize = bondCounts[card.groupKey], bondSize > 1 { basePower *= bondSize }
        basePower += max(0, morale - (card.act("morale") ? 1 : 0))
        basePower += 2 * max(0, wine - (card.act("toussaint_wine") ? 1 : 0))
        if let school = card.school, !card.locked, let schoolCount = schools[school], schoolCount > 1 { basePower += (schoolCount - 1) * 2 }
        if card.act("whorshipped") && whorshippers > 0 { basePower += whorshippers * whorshipMult }
        if horns - (card.act("horn") ? 1 : 0) > 0 { basePower *= 2 }
        basePower = basePower * card.multiplier + card.bonus
        if rowType == .siege { basePower *= card.siegeMult }
        return basePower
    }
}

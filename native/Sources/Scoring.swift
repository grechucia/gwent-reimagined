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
    func cardScore(_ c: Card, _ r: RowType, _ p: Player, bondCounts: [String: Int], morale: Int, wine: Int, horns: Int, weather w: Set<String>,
                   inspire: Int?, whorshippers: Int, schools: [String: Int]) -> Int {
        if c.key == "spe_decoy" { return 0 }
        var basePower = c.tempStrength ?? c.basePower
        if c.hero { return basePower * c.multiplier + c.bonus }
        if c.has("spy") || c.has("emissary") || c.has("ofiri_envoy") { basePower = Int(floor(spyMult * Double(basePower))) }
        if let ins = inspire, c.act("inspire") { basePower = ins }
        if let fixed = c.setTo { basePower = fixed }
        if !w.isEmpty {
            let immune = w.allSatisfy { ($0 == "fog" && c.has("fog_summoning")) || ($0 == "sandstorm" && c.has("sandstorm_immunity")) }
            if !immune {
                let limit = c.has("adaptive") ? 2 : 1
                basePower = p.halfWeather ? max(min(limit, basePower), basePower / 2) : min(limit, basePower)
            }
        }
        if c.act("bond"), let bondSize = bondCounts[c.groupKey], bondSize > 1 { basePower *= bondSize }
        basePower += max(0, morale - (c.act("morale") ? 1 : 0))
        basePower += 2 * max(0, wine - (c.act("toussaint_wine") ? 1 : 0))
        if let school = c.school, !c.locked, let n = schools[school], n > 1 { basePower += (n - 1) * 2 }
        if c.act("whorshipped") && whorshippers > 0 { basePower += whorshippers * whorshipMult }
        if horns - (c.act("horn") ? 1 : 0) > 0 { basePower *= 2 }
        basePower = basePower * c.multiplier + c.bonus
        if r == .siege { basePower *= c.siegeMult }
        return basePower
    }
}

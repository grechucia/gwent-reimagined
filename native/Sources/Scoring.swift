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
            for c in side where !c.locked { if let s = c.school { schools[s, default: 0] += 1 } }
            for r in RowType.allCases {
                let row = player.row(r)
                let bondCounts = Dictionary(grouping: row.cards.filter { $0.act("bond") }, by: { $0.groupKey }).mapValues { $0.count }
                let morale = row.cards.filter { $0.act("morale") }.count + row.specials.filter { $0.specialKind == "morale" }.count + row.factionMorale
                let wine = row.specials.filter { $0.specialKind == "toussaint_wine" }.count + row.cards.filter { $0.act("toussaint_wine") }.count
                let horns = row.hornCount
                let w = player.weather[r.rawValue]
                var sum = 0
                for card in row.cards {
                    card.power = cardScore(card, r, player, bondCounts: bondCounts, morale: morale, wine: wine, horns: horns, weather: w,
                                        inspire: inspires.count > 1 ? maxInspire : nil, whorshippers: whorshippers, schools: schools)
                    sum += card.power
                }
                row.total = sum
            }
            player.total = player.rows.reduce(0) { $0 + $1.total } + player.aamadBonus
        }
    }

    /// Power of a single card on a row after weather, horns, bonds and morale.
    func cardScore(_ c: Card, _ r: RowType, _ p: Player, bondCounts: [String: Int], morale: Int, wine: Int, horns: Int, weather w: Set<String>,
                   inspire: Int?, whorshippers: Int, schools: [String: Int]) -> Int {
        if c.key == "spe_decoy" { return 0 }
        var t = c.tempStrength ?? c.basePower
        if c.hero { return t * c.multiplier + c.bonus }
        if c.has("spy") || c.has("emissary") || c.has("ofiri_envoy") { t = Int(floor(spyMult * Double(t))) }
        if let ins = inspire, c.act("inspire") { t = ins }
        if let s = c.setTo { t = s }
        if !w.isEmpty {
            let immune = w.allSatisfy { ($0 == "fog" && c.has("fog_summoning")) || ($0 == "sandstorm" && c.has("sandstorm_immunity")) }
            if !immune {
                let limit = c.has("adaptive") ? 2 : 1
                t = p.halfWeather ? max(min(limit, t), t / 2) : min(limit, t)
            }
        }
        if c.act("bond"), let b = bondCounts[c.groupKey], b > 1 { t *= b }
        t += max(0, morale - (c.act("morale") ? 1 : 0))
        t += 2 * max(0, wine - (c.act("toussaint_wine") ? 1 : 0))
        if let s = c.school, !c.locked, let n = schools[s], n > 1 { t += (n - 1) * 2 }
        if c.act("whorshipped") && whorshippers > 0 { t += whorshippers * whorshipMult }
        if horns - (c.act("horn") ? 1 : 0) > 0 { t *= 2 }
        t = t * c.multiplier + c.bonus
        if r == .siege { t *= c.siegeMult }
        return t
    }
}

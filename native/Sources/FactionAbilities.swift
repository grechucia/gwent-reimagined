// Faction abilities that the player can activate during a match.
import Foundation

extension Game {
    /// The faction ability that can be activated now, if any.
    func factionActive(_ player: Player) -> String? {
        switch player.faction {
        case "witcher_universe": return player.factionUsedRound ? nil : "skip_round"
        case "redania": return player.factionUsedGame ? nil : "skip_game"
        case "lyria_rivia": return player.factionUsedGame ? nil : "morale"
        case "ofir": return player.factionUsedGame || !player.deck.contains(where: { $0.data.isWeather }) ? nil : "weather"
        case "toussaint": return player.rowCards.contains(where: { $0.act("monster_toussaint") && $0.playedTurn < turn - 1 }) ? "transform" : nil
        default: return nil
        }
    }

    /// The human uses the faction ability.
    func humanFaction() {
        guard !busy, phase == .play, current === human, factionActive(human) != nil else { return }
        busy = true
        Task { @MainActor in await self.useFaction(self.human); self.busy = false }
    }

    /// Uses a player's active faction ability.
    func useFaction(_ player: Player) async {
        guard let f = factionActive(player), current === player else { return }
        switch f {
        case "skip_round":
            player.factionUsedRound = true
            note(L("Witcher Universe used its faction ability and skipped a turn"), "notif_witcher_universe")
        case "skip_game":
            player.factionUsedGame = true
            note(L("Redania used its faction ability and skipped a turn"), "notif_redania")
        // Morale Boost: Adds +1 to all units in the row (excluding itself).
        case "morale":
            if let (_, r) = await pickRow(player, gameData.factionDesc("lyria_rivia"), RowType.allCases.map { (player, $0) }, ai: { RowType.allCases.map { player.row($0).cards.count }.enumerated().max { $0.1 < $1.1 }!.0 }) {
                player.row(r).factionMorale += 1; player.factionUsedGame = true
                note(L("Lyria & Rivia ability used - Morale Boost effect applied to a row."), "notif_lyria_rivia"); sound("moral")
            }
        case "weather":
            let options = player.deck.filter { $0.data.isWeather }
            if let t = await pickOne(player, L("Choose a weather card to play"), options, ai: { $0.first }) {
                player.factionUsedGame = true; player.deck.removeAll { $0 === t }; t.owner = player
                await playWeather(t, by: player, row: nil)
                note(L("Ofir faction ability used - Weather card played from deck."), "notif_ofir")
            }
        case "transform":
            let options = player.rowCards.filter { $0.act("monster_toussaint") && $0.playedTurn < turn - 1 }
            if let chosen = await pickOne(player, L("Choose which monster to transform."), options, ai: best1), let k = chosen.data.targets.first, let d = gameData.cards[k] {
                chosen.revertTo = chosen.key
                chosen.transform(into: d); chosen.playedTurn = turn
                sound("monster_toussaint")
                await unitAbilities(chosen, by: player, side: player, row: player.rowOf(chosen) ?? .close)
            }
        default: break
        }
        recalc()
        await endTurn(player)
    }
}

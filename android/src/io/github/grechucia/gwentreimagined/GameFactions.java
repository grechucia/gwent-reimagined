// Faction abilities that the player can activate during a match.
package io.github.grechucia.gwentreimagined;

import java.util.Arrays;
import java.util.List;
import static io.github.grechucia.gwentreimagined.GameData.L;

/** Faction ability layer of the engine. */
abstract class GameFactions extends GameLeaders {
    GameFactions(DeckData myDeck, DeckData opponentDeck) { super(myDeck, opponentDeck); }

    /** The faction ability that can be activated now, if any. */
    @Override String factionActive(Player player) {
        switch (player.faction()) {
            case "witcher_universe": return player.factionUsedRound ? null : "skip_round";
            case "redania": return player.factionUsedGame ? null : "skip_game";
            case "lyria_rivia": return player.factionUsedGame ? null : "morale";
            case "ofir": return player.factionUsedGame || player.deck.stream().noneMatch(c -> c.data().isWeather()) ? null : "weather";
            case "toussaint": return player.rowCards().stream().anyMatch(c -> c.act("monster_toussaint") && c.playedTurn < turn - 1) ? "transform" : null;
            default: return null;
        }
    }
    /** The human uses the faction ability. */
    void humanFaction() {
        if (busy || phase != Phase.PLAY || current != human || factionActive(human) == null) return;
        busy = true;
        GameThread.launch(() -> { useFaction(human); busy = false; });
    }
    /** Uses a player's active faction ability and ends the turn. */
    void useFaction(Player player) {
        String ability = factionActive(player);
        if (ability == null || current != player) return;
        switch (ability) {
            case "skip_round":
                player.factionUsedRound = true;
                note(L("Witcher Universe used its faction ability and skipped a turn"), "notif_witcher_universe");
                break;
            case "skip_game":
                player.factionUsedGame = true;
                note(L("Redania used its faction ability and skipped a turn"), "notif_redania");
                break;
            // Morale Boost: adds +1 to all units in the chosen row.
            case "morale": {
                SideRow destination = pickRow(player, gameData().factionDesc("lyria_rivia"), sideRows(player, Arrays.asList(RowType.values())), () -> {
                    int best = 0; for (RowType t : RowType.values()) if (player.row(t).cards.size() > player.row(RowType.values()[best]).cards.size()) best = t.index(); return best;
                });
                if (destination != null) {
                    player.row(destination.row).factionMorale += 1; player.factionUsedGame = true;
                    note(L("Lyria & Rivia ability used - Morale Boost effect applied to a row."), "notif_lyria_rivia"); sound("moral");
                }
                break;
            }
            case "weather": {
                Card chosen = pickOne(player, L("Choose a weather card to play"), filter(player.deck, c -> c.data().isWeather()), GameLeaders::firstOf);
                if (chosen != null) {
                    player.factionUsedGame = true; player.deck.remove(chosen); chosen.owner = player;
                    playWeather(chosen, player, null);
                    note(L("Ofir faction ability used - Weather card played from deck."), "notif_ofir");
                }
                break;
            }
            case "transform": {
                List<Card> options = filter(player.rowCards(), c -> c.act("monster_toussaint") && c.playedTurn < turn - 1);
                Card chosen = pickOne(player, L("Choose which monster to transform."), options, this::mostValuable);
                if (chosen != null && !chosen.data().targets.isEmpty()) {
                    CardData transformData = gameData().cards.get(chosen.data().targets.get(0));
                    if (transformData != null) {
                        chosen.revertTo = chosen.key();
                        chosen.transform(transformData); chosen.playedTurn = turn;
                        sound("monster_toussaint");
                        RowType row = player.rowOf(chosen);
                        unitAbilities(chosen, player, player, row != null ? row : RowType.CLOSE);
                    }
                }
                break;
            }
            default: break;
        }
        recalc();
        endTurn(player);
    }
}

// Board scoring: recalculates every card's power (weather, horns, bonds, morale, schools).
package io.github.grechucia.gwentreimagined;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/** Scoring layer of the engine. */
abstract class GameScoring extends GameCore {
    GameScoring(DeckData myDeck, DeckData opponentDeck) { super(myDeck, opponentDeck); }

    /** Recalculates the power of every card on the board. */
    @Override void recalc() {
        for (Player player : players()) {
            List<Card> side = player.rowCards();
            int inspireCount = 0, maxInspire = 0, whorshippers = 0;
            Map<String, Integer> schools = new HashMap<>();
            for (Card c : side) {
                if (c.act("inspire")) { inspireCount++; maxInspire = Math.max(maxInspire, c.basePower()); }
                if (c.act("whorshipper")) whorshippers++;
                if (!c.locked && c.school() != null) schools.merge(c.school(), 1, Integer::sum);
            }
            Integer inspire = inspireCount > 1 ? maxInspire : null;
            int playerTotal = 0;
            for (RowType rowType : RowType.values()) {
                Row row = player.row(rowType);
                Map<String, Integer> bondCounts = new HashMap<>();
                for (Card c : row.cards) if (c.act("bond")) bondCounts.merge(c.groupKey(), 1, Integer::sum);
                int morale = row.factionMorale, wine = 0;
                for (Card c : row.cards) { if (c.act("morale")) morale++; if (c.act("toussaint_wine")) wine++; }
                for (Card s : row.specials) { if ("morale".equals(s.specialKind())) morale++; if ("toussaint_wine".equals(s.specialKind())) wine++; }
                int horns = row.hornCount();
                Set<String> weather = player.weather.get(rowType.index());
                int total = 0;
                for (Card card : row.cards) {
                    card.power = cardScore(card, rowType, player, bondCounts, morale, wine, horns, weather, inspire, whorshippers, schools);
                    total += card.power;
                }
                row.total = total;
                playerTotal += total;
            }
            player.total = playerTotal + player.aamadBonus;
        }
    }

    /** Power of a single card on a row after weather, horns, bonds and morale. */
    int cardScore(Card card, RowType rowType, Player player, Map<String, Integer> bondCounts, int morale, int wine, int horns, Set<String> weather,
                  Integer inspire, int whorshippers, Map<String, Integer> schools) {
        if (card.key().equals("spe_decoy")) return 0;
        int basePower = card.tempStrength != null ? card.tempStrength : card.basePower();
        if (card.hero()) return basePower * card.multiplier + card.bonus;
        if (card.has("spy") || card.has("emissary") || card.has("ofiri_envoy")) basePower = (int) Math.floor(spyMult * basePower);
        if (inspire != null && card.act("inspire")) basePower = inspire;
        if (card.setTo != null) basePower = card.setTo;
        if (!weather.isEmpty()) {
            boolean immune = true;
            for (String w : weather) if (!((w.equals("fog") && card.has("fog_summoning")) || (w.equals("sandstorm") && card.has("sandstorm_immunity")))) immune = false;
            if (!immune) {
                int limit = card.has("adaptive") ? 2 : 1;
                basePower = player.halfWeather ? Math.max(Math.min(limit, basePower), basePower / 2) : Math.min(limit, basePower);
            }
        }
        if (card.act("bond")) { Integer bondSize = bondCounts.get(card.groupKey()); if (bondSize != null && bondSize > 1) basePower *= bondSize; }
        basePower += Math.max(0, morale - (card.act("morale") ? 1 : 0));
        basePower += 2 * Math.max(0, wine - (card.act("toussaint_wine") ? 1 : 0));
        String school = card.school();
        if (school != null && !card.locked) { Integer count = schools.get(school); if (count != null && count > 1) basePower += (count - 1) * 2; }
        if (card.act("whorshipped") && whorshippers > 0) basePower += whorshippers * whorshipMult;
        if (horns - (card.act("horn") ? 1 : 0) > 0) basePower *= 2;
        basePower = basePower * card.multiplier + card.bonus;
        if (rowType == RowType.SIEGE) basePower *= card.siegeMult;
        return basePower;
    }
}

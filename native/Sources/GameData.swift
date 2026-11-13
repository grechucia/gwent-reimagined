import Foundation

struct CardData {
    let key: String
    let name: String
    let deck: String
    let row: String
    let strength: Int
    let abilities: [String]
    let filename: String
    let count: Int
    let quote: String
    let target: String
    let targets: [String]
    var faction: String { String(deck.split(separator: " ").first ?? "") }
    var isSpecial: Bool { faction == "special" }
    var isWeather: Bool { faction == "weather" }
    var isLeader: Bool { row == "leader" }
    var isHero: Bool { abilities.contains("hero") }
    var isUnit: Bool { !isSpecial && !isWeather && !isLeader }
    var image: String { "img/sm/\(faction)_\(filename).jpg" }
}

struct DeckData { let title: String; let description: String; let leader: String; let faction: String; let cards: [(String, Int)] }

final class GameData {
    static var shared: GameData!
    var cards: [String: CardData] = [:]
    var decks: [DeckData] = []
    var factions: [String: [String: String]] = [:]
    var abilities: [String: [String: String]] = [:]
    private var lang: [String: [String: Any]] = [:]
    var language = "en"
    static let languages: [(code: String, name: String)] = [("de", "Deutsch"), ("en", "English"), ("es", "Español"), ("fr", "Français"),
        ("it", "Italiano"), ("pl", "Polski"), ("pt", "Português"), ("ru", "Русский"), ("zh", "中文"), ("ja", "日本語"), ("ko", "한국어")]
    func hasTranslation(_ code: String) -> Bool { code == "en" || lang[code] != nil }
    static func languageName(_ code: String) -> String { languages.first { $0.code == code }?.name ?? code }

    init(dir: URL) {
        func json(_ n: String) -> Any? {
            guard let d = try? Data(contentsOf: dir.appendingPathComponent(n)) else { return nil }
            return try? JSONSerialization.jsonObject(with: d)
        }
        func str(_ v: Any?) -> String { if let s = v as? String { return s }; if let n = v as? NSNumber { return n.stringValue }; return "" }
        func int(_ v: Any?) -> Int { if let n = v as? NSNumber { return n.intValue }; return Int(str(v)) ?? 0 }
        if let c = json("cards.json") as? [String: [String: Any]] {
            for (k, v) in c {
                cards[k] = CardData(key: k, name: str(v["name"]), deck: str(v["deck"]), row: str(v["row"]), strength: int(v["strength"]),
                                    abilities: str(v["ability"]).split(separator: " ").map(String.init), filename: str(v["filename"]),
                                    count: max(1, int(v["count"])), quote: str(v["quote"]), target: str(v["target"]),
                                    targets: (v["target"] as? [String]) ?? (str(v["target"]).isEmpty ? [] : [str(v["target"])]))
            }
        }
        if let d = json("decks.json") as? [[String: Any]] {
            decks = d.map { e in
                let cs = (e["cards"] as? [[Any]] ?? []).compactMap { p -> (String, Int)? in
                    guard p.count >= 2, let k = p[0] as? String else { return nil }
                    return (k, (p[1] as? NSNumber)?.intValue ?? 1)
                }
                return DeckData(title: str(e["title"]), description: str(e["description"]), leader: str(e["leader"]), faction: str(e["faction"]), cards: cs)
            }.filter { cards[$0.leader] != nil }
        }
        factions = (json("factions.json") as? [String: [String: String]]) ?? [:]
        abilities = (json("abilities.json") as? [String: [String: String]]) ?? [:]
        for (code, _) in GameData.languages { if let l = json("lang_\(code).json") as? [String: Any] { lang[code] = l } }
    }

    private func section(_ s: String) -> [String: Any] { (lang[language]?[s] as? [String: Any]) ?? [:] }

    func cardName(_ c: CardData) -> String { ((section("cards")[c.key] as? [String: String])?["name"]).flatMap { $0.isEmpty ? nil : $0 } ?? c.name }
    func cardQuote(_ c: CardData) -> String { ((section("cards")[c.key] as? [String: String])?["quote"]).flatMap { $0.isEmpty ? nil : $0 } ?? c.quote }
    func abilityName(_ k: String) -> String { ((section("abilities")[k] as? [String: String])?["name"]) ?? abilities[k]?["name"] ?? k }
    func abilityDesc(_ k: String) -> String { ((section("abilities")[k] as? [String: String])?["description"]) ?? abilities[k]?["description"] ?? "" }
    func factionName(_ k: String) -> String { ((section("factions")[k] as? [String: String])?["name"]) ?? factions[k]?["name"] ?? k }
    func factionDesc(_ k: String) -> String { ((section("factions")[k] as? [String: String])?["description"]) ?? factions[k]?["description"] ?? "" }
    func rules() -> [(text: String, heading: Bool)] {
        guard let blocks = (lang[language]?["blocks"] ?? lang["en"]?["blocks"]) as? [String: String] else { return [] }
        var out: [(String, Bool)] = []
        for i in 1...138 {
            guard var h = blocks["b\(i)"] else { continue }
            h = h.replacingOccurrences(of: "<br>", with: "\n").replacingOccurrences(of: "<br/>", with: "\n")
            var s = h.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            for (e, r) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] { s = s.replacingOccurrences(of: e, with: r) }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.isEmpty { continue }
            let heading = s.count <= 48 && !s.hasSuffix(".") && !s.hasSuffix(":") && !s.contains("\n")
            out.append((s, heading))
        }
        return out
    }
    func ui(_ en: String) -> String {
        if language == "en" { return en }
        return (section("ui")[en] as? String) ?? en
    }
}

func L(_ en: String) -> String { GameData.shared.ui(en) }
func L2(_ pl: String, _ en: String) -> String { GameData.shared.language == "pl" ? pl : GameData.shared.ui(en) }

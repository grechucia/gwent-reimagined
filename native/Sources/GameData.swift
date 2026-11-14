// Static game data loaded from JSON (cards, decks, factions, abilities) and localisation helpers.
import Foundation

/// Static definition of a card loaded from cards.json.
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

/// A deck: title, description, leader, faction and card counts.
struct DeckData { let title: String; let description: String; let leader: String; let faction: String; let cards: [(String, Int)] }

/// All static game data and the active translation.
final class GameData {
    static var shared: GameData!
    var cards: [String: CardData] = [:]
    var decks: [DeckData] = []
    var factions: [String: [String: String]] = [:]
    var abilities: [String: [String: String]] = [:]
    var lang: [String: [String: Any]] = [:]
    var language = "en"
    static let languages: [(code: String, name: String)] = [("de", "Deutsch"), ("en", "English"), ("es", "Español"), ("fr", "Français"),
        ("it", "Italiano"), ("pl", "Polski"), ("pt", "Português"), ("ru", "Русский"), ("zh", "中文"), ("ja", "日本語"), ("ko", "한국어")]
    /// Whether a translation exists for a language code.
    func hasTranslation(_ code: String) -> Bool { code == "en" || lang[code] != nil }
    /// Native name of a language.
    static func languageName(_ code: String) -> String { languages.first { $0.code == code }?.name ?? code }

    init(dir: URL) {
        /// Loads a JSON file from the data folder.
        func json(_ n: String) -> Any? {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(n)) else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        }
        /// Reads a JSON value as a string.
        func str(_ v: Any?) -> String { if let string = v as? String { return string }; if let number = v as? NSNumber { return number.stringValue }; return "" }
        /// Reads a JSON value as an integer.
        func int(_ v: Any?) -> Int { if let number = v as? NSNumber { return number.intValue }; return Int(str(v)) ?? 0 }
        if let cardsJSON = json("cards.json") as? [String: [String: Any]] {
            for (k, value) in cardsJSON {
                cards[k] = CardData(key: k, name: str(value["name"]), deck: str(value["deck"]), row: str(value["row"]), strength: int(value["strength"]),
                                    abilities: str(value["ability"]).split(separator: " ").map(String.init), filename: str(value["filename"]),
                                    count: max(1, int(value["count"])), quote: str(value["quote"]), target: str(value["target"]),
                                    targets: (value["target"] as? [String]) ?? (str(value["target"]).isEmpty ? [] : [str(value["target"])]))
            }
        }
        if let decksJSON = json("decks.json") as? [[String: Any]] {
            decks = decksJSON.map { e in
                let cardList = (e["cards"] as? [[Any]] ?? []).compactMap { p -> (String, Int)? in
                    guard p.count >= 2, let key = p[0] as? String else { return nil }
                    return (key, (p[1] as? NSNumber)?.intValue ?? 1)
                }
                return DeckData(title: str(e["title"]), description: str(e["description"]), leader: str(e["leader"]), faction: str(e["faction"]), cards: cardList)
            }.filter { cards[$0.leader] != nil }
        }
        factions = (json("factions.json") as? [String: [String: String]]) ?? [:]
        abilities = (json("abilities.json") as? [String: [String: String]]) ?? [:]
        for (code, _) in GameData.languages {
            guard var languageFile = json("lang_\(code).json") as? [String: Any] else { continue }
            if let extra = json("ui_\(code).json") as? [String: String] {
                var uiStrings = (languageFile["ui"] as? [String: Any]) ?? [:]
                for (key, value) in extra { uiStrings[key] = value }
                languageFile["ui"] = uiStrings
            }
            lang[code] = languageFile
        }
    }

    /// Section of the active translation file.
    func section(_ text: String) -> [String: Any] { (lang[language]?[text] as? [String: Any]) ?? [:] }

    /// Localised card name.
    func cardName(_ cardData: CardData) -> String { ((section("cards")[cardData.key] as? [String: String])?["name"]).flatMap { $0.isEmpty ? nil : $0 } ?? cardData.name }
    /// Localised card quote.
    func cardQuote(_ cardData: CardData) -> String { ((section("cards")[cardData.key] as? [String: String])?["quote"]).flatMap { $0.isEmpty ? nil : $0 } ?? cardData.quote }
    /// Localised ability name.
    func abilityName(_ key: String) -> String { ((section("abilities")[key] as? [String: String])?["name"]) ?? abilities[key]?["name"] ?? key }
    /// Localised ability description.
    func abilityDesc(_ key: String) -> String { ((section("abilities")[key] as? [String: String])?["description"]) ?? abilities[key]?["description"] ?? "" }
    /// Localised faction name.
    func factionName(_ key: String) -> String { ((section("factions")[key] as? [String: String])?["name"]) ?? factions[key]?["name"] ?? key }
    /// Localised faction description.
    func factionDesc(_ key: String) -> String { ((section("factions")[key] as? [String: String])?["description"]) ?? factions[key]?["description"] ?? "" }
    /// Localised rules text, split into headings and paragraphs.
    func rules() -> [(text: String, heading: Bool)] {
        guard let blocks = (lang[language]?["blocks"] ?? lang["en"]?["blocks"]) as? [String: String] else { return [] }
        var out: [(String, Bool)] = []
        for i in 1...138 {
            guard var h = blocks["b\(i)"] else { continue }
            h = h.replacingOccurrences(of: "<br>", with: "\n").replacingOccurrences(of: "<br/>", with: "\n")
            var plain = h.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            for (entity, replacement) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] { plain = plain.replacingOccurrences(of: entity, with: replacement) }
            plain = plain.trimmingCharacters(in: .whitespacesAndNewlines)
            if plain.isEmpty { continue }
            let heading = plain.count <= 48 && !plain.hasSuffix(".") && !plain.hasSuffix(":") && !plain.contains("\n")
            out.append((plain, heading))
        }
        return out
    }
    /// Translates an English UI string into the active language.
    func ui(_ en: String) -> String {
        if language == "en" { return en }
        return (section("ui")[en] as? String) ?? en
    }
}

/// Translates an English UI string (shorthand used across the UI).
func L(_ en: String) -> String { GameData.shared.ui(en) }

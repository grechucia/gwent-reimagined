import Foundation
import Translation

func readJSON(_ p: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: p)))) as? [String: Any] ?? [:]
}
func stripHTML(_ s: String) -> String {
    var t = s.replacingOccurrences(of: "<br>", with: "\n").replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    for (e, r) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] { t = t.replacingOccurrences(of: e, with: r) }
    return t.trimmingCharacters(in: .whitespacesAndNewlines)
}

@main struct Translate {
    static let targets: [String: String] = ["fr": "fr", "it": "it", "de": "de", "es": "es", "zh": "zh-Hans", "ja": "ja", "ko": "ko", "pt": "pt-BR", "ru": "ru"]

    static func main() async {
        let args = CommandLine.arguments
        guard args.count >= 3 else { print("użycie: translate <katalog data> <kod> [kod...]"); exit(1) }
        let dir = args[1]
        let en = readJSON(dir + "/lang_en.json")
        let extra = (try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: dir + "/ui_extra_en.json")))) as? [String] ?? []
        var texts = Set<String>()
        let cards = en["cards"] as? [String: [String: String]] ?? [:]
        let abilities = en["abilities"] as? [String: [String: String]] ?? [:]
        let factions = en["factions"] as? [String: [String: String]] ?? [:]
        let ui = en["ui"] as? [String: String] ?? [:]
        let blocks = en["blocks"] as? [String: String] ?? [:]
        for v in cards.values { if let n = v["name"], !n.isEmpty { texts.insert(n) }; if let q = v["quote"], !q.isEmpty { texts.insert(q) } }
        for v in abilities.values { for s in v.values where !s.isEmpty { texts.insert(s) } }
        for v in factions.values { for s in v.values where !s.isEmpty { texts.insert(s) } }
        for k in ui.keys where !k.isEmpty { texts.insert(k) }
        for s in extra where !s.isEmpty { texts.insert(s) }
        var plainBlocks: [String: String] = [:]
        for (k, h) in blocks { let p = stripHTML(h); if !p.isEmpty { plainBlocks[k] = p; texts.insert(p) } }
        let list = Array(texts).sorted()
        print("» tekstów do tłumaczenia: \(list.count)")

        for code in args.dropFirst(2) {
            guard let target = targets[code] else { print("! nieznany kod \(code)"); continue }
            let session = TranslationSession(installedSource: Locale.Language(identifier: "en"), target: Locale.Language(identifier: target))
            var map: [String: String] = [:]
            var i = 0
            let batch = 60
            do {
                while i < list.count {
                    let part = Array(list[i..<min(i + batch, list.count)])
                    let reqs = part.enumerated().map { TranslationSession.Request(sourceText: $0.element, clientIdentifier: "\($0.offset)") }
                    let res = try await session.translations(from: reqs)
                    for r in res { if let id = r.clientIdentifier, let n = Int(id) { map[part[n]] = r.targetText } }
                    i += batch
                    print("  \(code): \(min(i, list.count))/\(list.count)", terminator: "\r"); fflush(stdout)
                }
            } catch {
                print("\n! \(code): \(error) — pobierz pakiet językowy w Ustawieniach systemowych (Język i region → Języki tłumaczenia)")
                continue
            }
            func t(_ s: String) -> String { map[s] ?? s }
            var out: [String: Any] = ["name": code]
            out["cards"] = cards.mapValues { v in v.mapValues { t($0) } }
            out["abilities"] = abilities.mapValues { v in v.mapValues { t($0) } }
            out["factions"] = factions.mapValues { v in v.mapValues { t($0) } }
            var uiOut: [String: String] = [:]
            for k in ui.keys { uiOut[k] = t(k) }
            for s in extra { uiOut[s] = t(s) }
            out["ui"] = uiOut
            out["blocks"] = plainBlocks.mapValues { t($0) }
            let data = try! JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
            try! data.write(to: URL(fileURLWithPath: dir + "/lang_\(code).json"))
            print("\n✓ lang_\(code).json")
        }
    }
}

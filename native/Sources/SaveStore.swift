// Persistent save file shared by the career, custom decks, favourite deck and player name.
import Foundation

/// Single JSON save file holding the career, custom decks, favourite deck and player name.
@MainActor final class SaveStore {
    static let shared = SaveStore()
    private(set) var data: [String: Any] = [:]
    static let fileName = "GwentReimagined-save.json"

    static let testDir = ProcessInfo.processInfo.environment["GWENT_SAVEDIR"]
    var dirPath: String? { SaveStore.testDir ?? UserDefaults.standard.string(forKey: "saveDir") }
    var chosen: Bool { dirPath != nil }
    var displayPath: String {
        if ProcessInfo.processInfo.environment["GWENT_SHOT"] == "1" { return "~/Library/Application Support/GwentReimagined" }
        #if os(iOS)
        if dir.path == SaveStore.localDir.path { return L("Files → On My iPhone → GwentReimagined") }
        return dir.lastPathComponent
        #else
        return (dir.path as NSString).abbreviatingWithTildeInPath
        #endif
    }
    var dir: URL { URL(fileURLWithPath: dirPath ?? SaveStore.localDir.path) }
    var fileURL: URL { dir.appendingPathComponent(SaveStore.fileName) }

    static var localDir: URL {
        #if os(macOS)
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("GwentReimagined")
        #else
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #endif
    }
    static var iCloudDir: URL? {
        #if os(iOS)
        return nil
        #endif
        let docs = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        return FileManager.default.fileExists(atPath: docs.path) ? docs.appendingPathComponent("GwentReimagined") : nil
    }

    init() {
        load()
        if data["customDecks"] == nil, let a = UserDefaults.standard.array(forKey: "customDecks") { data["customDecks"] = a }
        if data["favoriteDeck"] == nil, let f = UserDefaults.standard.string(forKey: "favoriteDeck") { data["favoriteDeck"] = f }
    }
    /// Reads the save file from the current location.
    func load() {
        if let d = try? Data(contentsOf: fileURL), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { data = o }
    }
    /// Writes the save file to the current location.
    func save() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let d = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: fileURL, options: .atomic) }
    }
    subscript(_ key: String) -> Any? {
        get { data[key] }
        set { data[key] = newValue; save() }
    }
    /// Switches to a new save folder: loads an existing save there, otherwise moves the current one.
    func choose(_ url: URL) {
        let current = data
        if SaveStore.testDir != nil { return }
        UserDefaults.standard.set(url.path, forKey: "saveDir")
        if FileManager.default.fileExists(atPath: fileURL.path) { load() } else { data = current; save() }
    }
}

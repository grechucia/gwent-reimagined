// Prompt that asks where the save file should be stored.
import Foundation
import Metal
import CoreGraphics
import simd

extension Scene {
    /// Opens the save-location prompt, then runs `then`.
    func askSaveLocation(then: (() -> Void)?) { savePromptOpen = true; savePromptThen = then }

    /// Save-location prompt: this device, iCloud Drive or a custom folder.
    func drawSavePrompt() {
        renderer.rect(R(0, 0, virtualWidth, virtualHeight), RGBA.black.alpha(0.82))
        let p = R(360, 120, 1200, 840)
        glassPanel(p, alpha: 0.96)
        renderer.text(L("Where should your progress be saved?"), .gwent(44), x: 960, y: p.y + 30, color: RGBA.gold, align: .center)
        renderer.text(L("Your decks and career are kept in one file. Choose a location – you can change it later in Options."),
               .serif(19, italic: true), x: 960, y: p.y + 96, color: .gray(0.88), maxWidth: p.w - 120, align: .center)
        let ic = SaveStore.iCloudDir
        let opts: [(String, String, Bool, () -> Void)] = [
            (Platform.isDesktop ? L("On this Mac") : L("On this device"),
             Platform.isDesktop ? L("Local save. The simplest choice if you only play on this computer.")
                                : L("Local save, visible in the Files app. The simplest choice if you only play on this device."), true,
             { [weak self] in self?.finishSaveChoice(SaveStore.localDir) }),
            (L("iCloud Drive"), ic == nil
                ? (Platform.isDesktop ? L("iCloud Drive is off on this Mac (System Settings → Apple ID → iCloud).")
                                      : L("Choose a folder in iCloud Drive with “Choose a folder…”."))
                : L("Syncs between Apple devices: your Mac, iPhone and iPad share the same progress."),
             ic != nil, { [weak self] in if let u = ic { self?.finishSaveChoice(u) } }),
            (L("Choose a folder…"), L("E.g. a network drive, Dropbox or Google Drive – useful if you also want to sync with Android."), true,
             { [weak self] in self?.pickSaveFolder() })]
        for (i, o) in opts.enumerated() {
            let b = R(p.x + 80, p.y + 180 + Float(i) * 170, p.w - 160, 140)
            let hovered = o.2 && b.contains(mouse)
            renderer.rect(b, RGBA.black.alpha(hovered ? 0.5 : 0.32)); renderer.frame(b, RGBA.gold.alpha(o.2 ? (hovered ? 1 : 0.5) : 0.2), hovered ? 2.5 : 1.5)
            renderer.text(o.0, .serif(28, bold: true), x: b.x + 30, y: b.y + 22, color: o.2 ? (hovered ? .white : RGBA.gold) : .gray(0.45))
            renderer.text(o.1, .ui(18), x: b.x + 30, y: b.y + 72, color: o.2 ? .gray(0.88) : .gray(0.5), maxWidth: b.w - 60)
            if o.2 { button(b, o.3) }
        }
        if SaveStore.shared.chosen {
            renderer.text(L("Currently") + ": " + SaveStore.shared.displayPath, .ui(15), x: 960, y: p.y + p.h - 70, color: .gray(0.7), maxWidth: p.w - 100, align: .center)
            smallLink(R(960 - 120, p.y + p.h - 44, 240, 32), L("Cancel")) { [weak self] in self?.savePromptOpen = false; self?.savePromptThen = nil }
        }
    }

    /// Applies the chosen save folder and reloads saved data.
    func finishSaveChoice(_ url: URL) {
        SaveStore.shared.choose(url)
        Career.shared.load(); customDecks = DeckBuilder.loadCustom()
        savePromptOpen = false
        let t = savePromptThen; savePromptThen = nil; t?()
    }

    /// Shows the system folder picker.
    func pickSaveFolder() {
        Platform.pickFolder(message: L("Folder for GwentReimagined saves")) { [weak self] u in
            if let u = u { self?.finishSaveChoice(u) }
        }
    }
}

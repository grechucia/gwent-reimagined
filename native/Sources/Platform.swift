// Platform abstraction shared by macOS and iOS: host settings, dialogs, links and the folder picker.
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
import UniformTypeIdentifiers
#endif

/// Settings provided by the platform-specific app delegate and shown in Options.
@MainActor protocol GameHost: AnyObject {
    var renderRes: Int { get }
    func setRenderRes(_ px: Int)
    var availableFrameLimits: [Int] { get }
    var effectiveFrameLimit: Int { get }
    func setFrameLimit(_ f: Int)
    var supportsWindowModes: Bool { get }
    var isFullScreen: Bool { get }
    func setFullScreen(_ on: Bool)
    func refreshMenus()
}

/// Platform-specific helpers used by the shared game code.
@MainActor enum Platform {
    #if os(macOS)
    static let isDesktop = true
    #else
    static let isDesktop = false
    #endif

    /// Opens a URL in the default browser.
    static func openURL(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    /// Quits the app (macOS only).
    static func quit() {
        #if os(macOS)
        NSApp.terminate(nil)
        #endif
    }

    /// Asks the user for a line of text; `done` receives nil when cancelled.
    static func askText(title: String, message: String, placeholder: String, current: String, done: @escaping (String?) -> Void) {
        #if os(macOS)
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            textField.stringValue = current
            textField.placeholderString = placeholder
            alert.accessoryView = textField
            alert.addButton(withTitle: "OK"); alert.addButton(withTitle: L("Cancel"))
            alert.window.initialFirstResponder = textField
            done(alert.runModal() == .alertFirstButtonReturn ? textField.stringValue : nil)
        }
        #else
        guard let presenter = rootViewController else { done(nil); return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addTextField { $0.text = current; $0.placeholder = placeholder; $0.autocapitalizationType = .words }
        alert.addAction(UIAlertAction(title: L("Cancel"), style: .cancel) { _ in done(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in done(alert.textFields?.first?.text) })
        presenter.present(alert, animated: true)
        #endif
    }

    /// Lets the user choose a folder; on iOS access to it is kept with a security-scoped bookmark.
    static func pickFolder(message: String, done: @escaping (URL?) -> Void) {
        #if os(macOS)
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
            panel.prompt = L("Choose"); panel.message = message
            done(panel.runModal() == .OK ? panel.url : nil)
        }
        #else
        guard let presenter = rootViewController else { done(nil); return }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        let delegate = PickerDelegate { url in
            if let folder = url {
                _ = folder.startAccessingSecurityScopedResource()
                if let bookmark = try? folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    UserDefaults.standard.set(bookmark, forKey: "saveDirBookmark")
                }
            }
            done(url)
        }
        pickerDelegate = delegate
        picker.delegate = delegate
        presenter.present(picker, animated: true)
        #endif
    }

    #if os(iOS)
    static weak var iosRoot: UIViewController?
    static var rootViewController: UIViewController? {
        var presenter = iosRoot
        while let presented = presenter?.presentedViewController { presenter = presented }
        return presenter
    }
    static var pickerDelegate: PickerDelegate?
    /// Receives the result of the iOS document picker.
    final class PickerDelegate: NSObject, UIDocumentPickerDelegate {
        let done: (URL?) -> Void
        init(_ done: @escaping (URL?) -> Void) { self.done = done }
        func documentPicker(_ c: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { done(urls.first) }
        func documentPickerWasCancelled(_ c: UIDocumentPickerViewController) { done(nil) }
    }

    /// Restores access to the save folder chosen earlier on iOS.
    static func restoreBookmarkedFolder() {
        guard let bookmark = UserDefaults.standard.data(forKey: "saveDirBookmark") else { return }
        var stale = false
        if let folder = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
            _ = folder.startAccessingSecurityScopedResource()
            UserDefaults.standard.set(folder.path, forKey: "saveDir")
        }
    }
    #endif
}

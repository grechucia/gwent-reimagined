import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
import UniformTypeIdentifiers
#endif

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

@MainActor enum Platform {
    #if os(macOS)
    static let isDesktop = true
    #else
    static let isDesktop = false
    #endif

    static func openURL(_ u: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(u)
        #else
        UIApplication.shared.open(u)
        #endif
    }

    static func quit() {
        #if os(macOS)
        NSApp.terminate(nil)
        #endif
    }

    static func askText(title: String, message: String, placeholder: String, current: String, done: @escaping (String?) -> Void) {
        #if os(macOS)
        DispatchQueue.main.async {
            let a = NSAlert()
            a.messageText = title
            a.informativeText = message
            let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            tf.stringValue = current
            tf.placeholderString = placeholder
            a.accessoryView = tf
            a.addButton(withTitle: "OK"); a.addButton(withTitle: L2("Anuluj", "Cancel"))
            a.window.initialFirstResponder = tf
            done(a.runModal() == .alertFirstButtonReturn ? tf.stringValue : nil)
        }
        #else
        guard let vc = rootViewController else { done(nil); return }
        let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
        a.addTextField { $0.text = current; $0.placeholder = placeholder; $0.autocapitalizationType = .words }
        a.addAction(UIAlertAction(title: L2("Anuluj", "Cancel"), style: .cancel) { _ in done(nil) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in done(a.textFields?.first?.text) })
        vc.present(a, animated: true)
        #endif
    }

    static func pickFolder(message: String, done: @escaping (URL?) -> Void) {
        #if os(macOS)
        DispatchQueue.main.async {
            let p = NSOpenPanel()
            p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true; p.allowsMultipleSelection = false
            p.prompt = L2("Wybierz", "Choose"); p.message = message
            done(p.runModal() == .OK ? p.url : nil)
        }
        #else
        guard let vc = rootViewController else { done(nil); return }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        let d = PickerDelegate { url in
            if let u = url {
                _ = u.startAccessingSecurityScopedResource()
                if let b = try? u.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    UserDefaults.standard.set(b, forKey: "saveDirBookmark")
                }
            }
            done(url)
        }
        pickerDelegate = d
        picker.delegate = d
        vc.present(picker, animated: true)
        #endif
    }

    #if os(iOS)
    static weak var iosRoot: UIViewController?
    static var rootViewController: UIViewController? {
        var vc = iosRoot
        while let p = vc?.presentedViewController { vc = p }
        return vc
    }
    private static var pickerDelegate: PickerDelegate?
    final class PickerDelegate: NSObject, UIDocumentPickerDelegate {
        let done: (URL?) -> Void
        init(_ done: @escaping (URL?) -> Void) { self.done = done }
        func documentPicker(_ c: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { done(urls.first) }
        func documentPickerWasCancelled(_ c: UIDocumentPickerViewController) { done(nil) }
    }

    static func restoreBookmarkedFolder() {
        guard let b = UserDefaults.standard.data(forKey: "saveDirBookmark") else { return }
        var stale = false
        if let u = try? URL(resolvingBookmarkData: b, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
            _ = u.startAccessingSecurityScopedResource()
            UserDefaults.standard.set(u.path, forKey: "saveDir")
        }
    }
    #endif
}

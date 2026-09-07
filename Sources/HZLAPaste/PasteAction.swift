import AppKit
import ApplicationServices

/// Tracks the last app that was frontmost before HZLAPaste itself — used as the
/// paste-back target both from the quick popup panel and the main window, since
/// the main window can stay open across multiple app switches.
final class ForegroundAppTracker {
    static let shared = ForegroundAppTracker()

    private(set) var lastForegroundApp: NSRunningApplication?

    private init() {
        // Seed with whatever's frontmost right now — otherwise this stays nil until
        // the *next* app switch, which never happens if the target app was already
        // frontmost before HZLAPaste launched (paste would then silently no-op).
        let current = NSWorkspace.shared.frontmostApplication
        if current?.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastForegroundApp = current
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            self?.lastForegroundApp = app
        }
    }
}

enum PasteAction {
    /// ⌘Enter / Cmd+click: just puts the item back on the system pasteboard.
    static func copy(_ item: ClipItem, store: ClipboardStore, monitor: ClipboardMonitor) {
        writeToPasteboard(item, store: store, monitor: monitor)
    }

    /// Enter / click: for links, opens the URL in the default browser (a new tab in
    /// whatever's already running, standard macOS URL-open behavior) instead of
    /// pasting the raw text — a link you're selecting is one you want to visit, not
    /// retype elsewhere. Everything else still does the normal paste-back.
    static func activate(_ item: ClipItem, store: ClipboardStore, monitor: ClipboardMonitor, previousApp: NSRunningApplication?) {
        if item.kind == .url, let text = item.text, let url = URL(string: text),
           url.scheme == "http" || url.scheme == "https" {
            NSWorkspace.shared.open(url)
            return
        }
        paste(item, store: store, monitor: monitor, previousApp: previousApp)
    }

    /// Enter / double-click: writes the item back to the pasteboard, reactivates
    /// whatever app was frontmost before HZLAPaste, then simulates ⌘V into it.
    static func paste(_ item: ClipItem, store: ClipboardStore, monitor: ClipboardMonitor, previousApp: NSRunningApplication?) {
        writeToPasteboard(item, store: store, monitor: monitor)

        guard let previousApp else { return }

        // Simulating ⌘V requires Accessibility permission. Without it the item still
        // lands on the pasteboard (manual ⌘V works) but the auto-paste silently no-ops —
        // prompt once so the user can grant it instead of wondering why nothing happens.
        guard AXIsProcessTrusted() else {
            previousApp.activate()
            promptForAccessibilityIfNeeded()
            return
        }

        if previousApp.isActive {
            simulatePasteKeystroke()
            return
        }

        // Fire the keystroke the moment the target app actually regains focus, instead
        // of guessing a fixed delay — noticeably snappier than a flat sleep while still
        // safe for apps that take longer to reactivate.
        var didFire = false
        var observer: NSObjectProtocol?
        func fireOnce() {
            guard !didFire else { return }
            didFire = true
            if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
            simulatePasteKeystroke()
        }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier == previousApp.processIdentifier else { return }
            fireOnce()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { fireOnce() } // safety net

        previousApp.activate()
    }

    private static var hasPromptedForAccessibility = false

    private static func promptForAccessibilityIfNeeded() {
        guard !hasPromptedForAccessibility else { return }
        hasPromptedForAccessibility = true
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private static func writeToPasteboard(_ item: ClipItem, store: ClipboardStore, monitor: ClipboardMonitor) {
        let pb = NSPasteboard.general
        pb.clearContents()

        switch item.kind {
        case .image:
            // ponytail: file items paste back as plain path text rather than a real
            // Finder file reference; switch to NSFilePromiseProvider if that's needed.
            if let file = item.imageFile, let data = try? Data(contentsOf: store.imageURL(for: file)) {
                let pbItem = NSPasteboardItem()
                let ext = (file as NSString).pathExtension.lowercased()
                let nativeType = pasteboardType(forExtension: ext)
                if let nativeType {
                    pbItem.setData(data, forType: nativeType)
                }
                // Always include a TIFF fallback for apps that only understand generic
                // image data — animated formats still lose motion there, but at least
                // the paste isn't silently empty.
                if nativeType != .tiff, let image = NSImage(data: data), let tiff = image.tiffRepresentation {
                    pbItem.setData(tiff, forType: .tiff)
                }
                pb.writeObjects([pbItem])
            }
        case .text, .url, .file:
            if let text = item.text {
                pb.setString(text, forType: .string)
            }
        }

        monitor.markOwnWrite(changeCount: pb.changeCount)
    }

    private static func pasteboardType(forExtension ext: String) -> NSPasteboard.PasteboardType? {
        switch ext {
        case "gif": return NSPasteboard.PasteboardType("com.compuserve.gif")
        case "png": return .png
        case "jpg", "jpeg": return NSPasteboard.PasteboardType("public.jpeg")
        case "tiff", "tif": return .tiff
        default: return nil
        }
    }

    private static func simulatePasteKeystroke() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let vKeyCode: CGKeyCode = 9 // 'v'
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

import AppKit
import ApplicationServices
import SwiftUI

@main
struct HZLAPasteApp {
    static func main() {
        if CommandLine.arguments.contains("--self-check") {
            exit(runSelfCheck() ? 0 : 1)
        }
        if CommandLine.arguments.contains("--check-accessibility") {
            print("AXIsProcessTrusted: \(AXIsProcessTrusted())")
            print("Bundle path: \(Bundle.main.bundlePath)")
            print("Bundle identifier: \(Bundle.main.bundleIdentifier ?? "(none)")")
            exit(0)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(AppSettings.showInDock ? .regular : .accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var mainWindow: NSWindow?
    private let mainViewModel = MainViewModel()

    private let store = ClipboardStore()
    private let snippetStore = SnippetStore()
    private lazy var monitor = ClipboardMonitor(store: store)
    private lazy var panel = HistoryPanel(store: store, monitor: monitor)
    private lazy var hotKeyManager = HotKeyManager { [weak self] in self?.togglePanel() }
    private lazy var snippetExpander = SnippetExpander(snippetStore: snippetStore, monitor: monitor)
    private var retentionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = ForegroundAppTracker.shared // start tracking immediately
        setupStatusItem()
        monitor.start()
        hotKeyManager.register()
        panel.onOpenPreferences = { [weak self] in self?.openPreferences() }

        store.performRetentionSweep()
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.store.performRetentionSweep() }
        }

        // Safe to call even without Accessibility yet — it no-ops and we retry
        // opportunistically whenever the bar opens, so granting permission later
        // (in the same run) doesn't require restarting the app.
        snippetExpander.start()
    }

    /// Fired when the Dock icon is clicked with no HZLAPaste windows open — the
    /// clipboard bar *is* the app, so this opens that rather than a separate window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { panel.show() }
        return true
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = WolfIcon.menuBarImage()
        item.button?.image?.accessibilityDescription = "HZLAPaste"

        let menu = NSMenu()
        menu.delegate = self // rebuilt with live history each time it's about to open
        item.menu = menu
        statusItem = item
    }

    // ponytail: rebuilding on every open is O(recentCap) — plenty cheap at MVP history sizes.
    private static let recentCapInMenu = 15

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let active = store.items.filter { $0.archivedAt == nil }
        let pinned = active.filter { $0.pinned }
        let recent = active.filter { !$0.pinned }.prefix(Self.recentCapInMenu)

        if pinned.isEmpty && recent.isEmpty {
            let empty = NSMenuItem(title: "No clipboard history yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            if !pinned.isEmpty {
                pinned.forEach { menu.addItem(historyMenuItem(for: $0)) }
                menu.addItem(.separator())
            }
            recent.forEach { menu.addItem(historyMenuItem(for: $0)) }
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Show History (⌘⇧V)", action: #selector(togglePanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Snippets…", action: #selector(openSnippets), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Clear Unpinned History", action: #selector(clearHistory), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit HZLAPaste", action: #selector(quit), keyEquivalent: "q").target = self
    }

    private func historyMenuItem(for clip: ClipItem) -> NSMenuItem {
        let item = NSMenuItem(title: menuTitle(for: clip), action: #selector(selectFromMenu(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = clip.id
        item.image = menuIcon(for: clip)
        if clip.pinned {
            item.title = "📌 " + item.title
        }
        return item
    }

    private func menuTitle(for item: ClipItem) -> String {
        if item.kind == .image { return "Image" }
        let text = (item.text ?? "").replacingOccurrences(of: "\n", with: " ")
        return text.count > 60 ? String(text.prefix(60)) + "…" : text
    }

    private func menuIcon(for item: ClipItem) -> NSImage? {
        switch item.kind {
        case .image:
            guard let file = item.imageFile, let image = NSImage(contentsOf: store.imageURL(for: file)) else { return nil }
            image.size = NSSize(width: 16, height: 16)
            return image
        case .file: return NSImage(systemSymbolName: "doc", accessibilityDescription: nil)
        case .url: return NSImage(systemSymbolName: "link", accessibilityDescription: nil)
        case .text: return NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        }
    }

    /// Click pastes (or opens a link) into the previously frontmost app; ⌘-click
    /// just copies — same convention as Enter / ⌘Enter in the history panel.
    @objc private func selectFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let clip = store.items.first(where: { $0.id == id }) else { return }
        if NSEvent.modifierFlags.contains(.command) {
            PasteAction.copy(clip, store: store, monitor: monitor)
        } else {
            PasteAction.activate(clip, store: store, monitor: monitor, previousApp: ForegroundAppTracker.shared.lastForegroundApp)
        }
    }

    @objc private func togglePanel() {
        panel.isVisible ? panel.dismiss() : panel.show()
        snippetExpander.start() // opportunistic retry in case Accessibility was just granted
    }

    @objc private func openPreferences() {
        openMainWindow(tab: .preferences)
    }

    @objc private func openSnippets() {
        openMainWindow(tab: .snippets)
    }

    private func openMainWindow(tab: MainTab) {
        mainViewModel.selectedTab = tab
        if mainWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: MainView(viewModel: mainViewModel, snippetStore: snippetStore, clipboardStore: store)
            ))
            window.title = "HZLAPaste"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.isOpaque = false
            window.backgroundColor = .clear // lets the SwiftUI Material show real desktop blur through it
            window.setContentSize(NSSize(width: 480, height: 520))
            window.center()
            mainWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func clearHistory() {
        store.clearUnpinned()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

import AppKit
import SwiftUI

/// Floating, non-activating command bar — a full-width glass shelf docked just
/// above the Dock (like Paste's), not a centered Spotlight-style window.
/// Dismissable with Esc, navigable with arrow keys.
final class HistoryPanel: NSPanel {
    static let barHeight: CGFloat = 248
    // With an auto-hidden Dock, NSScreen.visibleFrame doesn't reserve space for it
    // (it's not occupying screen space most of the time), so the bar would otherwise
    // sit flush at the very bottom edge — exactly where a hidden Dock pops up on hover.
    // ponytail: fixed guess at Dock height (no public API for it while auto-hidden);
    // bump further if a larger Dock icon size still clips it.
    private static let bottomMargin: CGFloat = 90

    private let store: ClipboardStore
    private let monitor: ClipboardMonitor
    private let viewModel: HistoryViewModel
    private var previousApp: NSRunningApplication?
    private lazy var previewPanel = PreviewPanel()

    /// Set by AppDelegate — the bar doesn't own Preferences, but ⌘, should work
    /// from it anyway rather than forcing the user to close it first.
    var onOpenPreferences: () -> Void = {}

    init(store: ClipboardStore, monitor: ClipboardMonitor) {
        self.store = store
        self.monitor = monitor
        let vm = HistoryViewModel(store: store)
        viewModel = vm

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: Self.barHeight),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear // lets the SwiftUI Material show real desktop blur through it
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        vm.onPaste = { [weak self] item in self?.paste(item) }
        vm.onCopy = { [weak self] item in self?.copy(item) }
        vm.onPreview = { [weak self] item in self?.togglePreview(item) }
        vm.onEscape = { [weak self] in self?.dismiss() }
        vm.onOpenPreferences = { [weak self] in self?.onOpenPreferences() }
        contentView = NSHostingView(rootView: HistoryView(viewModel: vm))

        // Click-outside-to-dismiss, at the *app* level rather than per-window: the
        // bar and its preview panel are two windows in the same app, so focus moves
        // between them constantly (opening/closing the preview) without the user
        // ever "leaving." The app only stops being active when something genuinely
        // outside it — another app, the desktop — takes over, which is the actual
        // signal we want. A plain resignKey on the bar can't tell those apart from
        // its own preview stealing key status, which was closing the bar the moment
        // the preview opened.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.dismiss() }
    }

    override var canBecomeKey: Bool { true }

    func show() {
        // Ground truth: whatever's frontmost right now, before we steal focus below.
        // More reliable than the tracker's notification history for this transient
        // popup, since it can't be stale — the tracker exists for the persistent
        // Home window, where by click time frontmostApplication would be ourselves.
        previousApp = NSWorkspace.shared.frontmostApplication
        viewModel.query = ""
        positionAsBottomBar()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        orderOut(nil)
        previewPanel.dismiss()
    }

    private func paste(_ item: ClipItem) {
        dismiss()
        PasteAction.activate(item, store: store, monitor: monitor, previousApp: previousApp)
    }

    private func copy(_ item: ClipItem) {
        dismiss()
        PasteAction.copy(item, store: store, monitor: monitor)
    }

    private func togglePreview(_ item: ClipItem) {
        if previewPanel.isVisible {
            previewPanel.dismiss()
            return
        }
        let actions = PreviewActions(
            primaryLabel: item.kind == .url ? "Open Link" : "Paste",
            onPrimary: { [weak self] in self?.paste(item) },
            onCopy: { [weak self] in self?.copy(item) },
            onTogglePin: { [weak self] in self?.store.togglePin(item.id) },
            onDelete: { [weak self] in self?.store.delete(item.id) }
        )
        previewPanel.show(item: item, store: store, actions: actions, anchor: previewAnchor())
    }

    /// Horizontally centered on the selected card, but vertically spanning the
    /// *whole bar* rather than just the card — cards sit inside a fixed shelf below
    /// the search field, so "above the card" alone would still land inside the bar's
    /// own bounds. This keeps the preview from opening on top of the bar itself.
    private func previewAnchor() -> CGRect? {
        guard let card = screenRect(fromSwiftUIGlobal: viewModel.selectedCardFrame) else { return nil }
        return CGRect(x: card.minX, y: frame.minY, width: card.width, height: frame.height)
    }

    /// Full screen width, edge to edge, sitting flush just above the Dock — recomputed
    /// on every show() in case the display configuration changed since last time.
    private func positionAsBottomBar() {
        guard let screen = NSScreen.main else { return }
        let full = screen.frame
        let visible = screen.visibleFrame // excludes the Dock and menu bar
        setFrame(NSRect(x: full.minX, y: visible.minY + Self.bottomMargin, width: full.width, height: Self.barHeight), display: true)
    }
}

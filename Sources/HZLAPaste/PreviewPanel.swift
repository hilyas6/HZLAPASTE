import AppKit
import SwiftUI

/// Actions the preview's bottom bar can trigger, supplied by HistoryPanel (which
/// holds the store/paste-target context needed to actually perform them).
struct PreviewActions {
    let primaryLabel: String
    let onPrimary: () -> Void
    let onCopy: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void
}

extension NSWindow {
    /// Converts a SwiftUI `.global`-space rect (top-left origin, relative to this
    /// window's hosted content) into screen coordinates (bottom-left origin), so a
    /// second window can be positioned relative to a SwiftUI view inside this one.
    func screenRect(fromSwiftUIGlobal rect: CGRect) -> CGRect? {
        guard rect != .zero else { return nil }
        let x = frame.minX + rect.minX
        let y = frame.maxY - rect.minY - rect.height
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }
}

/// Space-to-preview, Quick Look-style: a large rendering of a clip, its metadata,
/// and an action bar — anchored next to whatever card triggered it rather than
/// just centered on screen.
final class PreviewPanel: NSPanel {
    private static let panelSize = NSSize(width: 560, height: 560)
    private static let minHeight: CGFloat = 340

    var onDismiss: () -> Void = {}

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
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
        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        // Dismiss when the *app* loses activation (a genuinely different app or the
        // desktop takes over) — not on plain resignKey, which also fires when the
        // Actions menu opens its own transient popup and would close the whole
        // preview before a click on a menu item ever registered.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.dismiss() }
    }

    override var canBecomeKey: Bool { true }

    /// anchor: the trigger card's frame in screen coordinates (via
    /// `screenRect(fromSwiftUIGlobal:)`), or nil to just center on screen.
    func show(item: ClipItem, store: ClipboardStore, actions: PreviewActions, anchor: CGRect?) {
        let hostingView = NSHostingView(rootView: PreviewView(item: item, store: store, actions: actions, onClose: { [weak self] in self?.dismiss() }))
        contentView = hostingView
        setFrame(NSRect(origin: frame.origin, size: Self.panelSize), display: false) // reset before repositioning below
        position(near: anchor)
        makeKeyAndOrderFront(nil)
        // Unlike the bar's TextField (a real AppKit control that grabs first responder
        // itself via @FocusState), this content is a plain SwiftUI view — it needs to
        // be handed first-responder status explicitly or Space/Escape never reach it.
        makeFirstResponder(hostingView)
    }

    func dismiss() {
        orderOut(nil)
        onDismiss()
    }

    /// Opens on whichever side of the anchor has more room — "just above the
    /// thumbnail" when there's space, flipping below when there isn't. If neither
    /// side has enough room for the full-size panel, shrinks it to fit rather than
    /// overlapping the anchor (guaranteed correct regardless of screen size). Always
    /// horizontally centered on the anchor, clamped to stay fully on-screen.
    private func position(near anchor: CGRect?) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let gap: CGFloat = 14

        guard let anchor else {
            setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2))
            return
        }

        let x = min(max(anchor.midX - frame.width / 2, visible.minX + 8), visible.maxX - frame.width - 8)

        // AppKit is bottom-left origin: a *larger* Y is higher on screen. So the
        // room "above" the anchor runs from its top edge up to the screen's top.
        let spaceAbove = visible.maxY - anchor.maxY - gap
        let spaceBelow = anchor.minY - visible.minY - gap
        let openAbove = spaceAbove >= spaceBelow

        let height = min(Self.panelSize.height, max(Self.minHeight, openAbove ? spaceAbove : spaceBelow))
        let y = openAbove ? (anchor.maxY + gap) : (anchor.minY - gap - height)

        setFrame(NSRect(x: x, y: y, width: frame.width, height: height), display: false)
    }
}

private struct PreviewView: View {
    let item: ClipItem
    let store: ClipboardStore
    let actions: PreviewActions
    let onClose: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.card)

            Divider()
            infoSection
            Divider()
            actionBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .preferredColorScheme(.dark)
        .focusable()
        .focusEffectDisabled() // suppress the default system focus ring — our own gold selection border is the only highlight we want
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(keys: [.space, .escape]) { _ in onClose(); return .handled }
        .onKeyPress(keys: [.return]) { press in
            if press.modifiers.contains(.command) {
                actions.onCopy()
            } else {
                actions.onPrimary()
            }
            onClose()
            return .handled
        }
        .onExitCommand { onClose() }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .image:
            if let file = item.imageFile, let image = NSImage(contentsOf: store.imageURL(for: file)) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).padding(24)
            } else {
                placeholder("photo")
            }

        case .url:
            if let file = item.linkImageFile, let image = NSImage(contentsOf: store.imageURL(for: file)) {
                VStack(spacing: 16) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Text(item.linkTitle ?? item.text ?? "")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.silver)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
                .padding(28)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "link").font(.system(size: 40)).foregroundStyle(Theme.linkBlue)
                    Text(item.text ?? "")
                        .font(.system(size: 16, design: .rounded))
                        .foregroundStyle(Theme.silver)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                }
                .padding(28)
            }

        case .text:
            ScrollView {
                Text(item.text ?? "")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.silver)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }

        case .file:
            VStack(spacing: 14) {
                Image(systemName: "doc").font(.system(size: 40)).foregroundStyle(Theme.fileTeal)
                Text(item.text ?? "")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Theme.silver)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
            .padding(28)
        }
    }

    private func placeholder(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 40)).foregroundStyle(Theme.silverDim)
    }

    private var infoSection: some View {
        VStack(spacing: 10) {
            infoRow("Source") {
                HStack(spacing: 6) {
                    if let icon = appIcon {
                        Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    }
                    Text(item.sourceAppName ?? "Unknown")
                }
            }
            infoRow("Content type") { Text(contentTypeLabel) }
            if let dimensions { infoRow("Dimensions") { Text(dimensions) } }
            if let fileSize { infoRow("Size") { Text(fileSize) } }
            if item.kind == .text, let length = item.text?.count {
                infoRow("Length") { Text("\(length) characters") }
            }
            infoRow("Copied") { Text(copiedLabel) }
        }
        .padding(18)
        .background(Theme.panel)
    }

    private func infoRow(_ title: String, @ViewBuilder value: () -> some View) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Theme.silverDim)
            Spacer()
            value()
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.silver)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Spacer()

            Button {
                actions.onPrimary()
                onClose()
            } label: {
                HStack(spacing: 6) {
                    Text(actions.primaryLabel)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.silver)
                    keyCap("↵")
                }
            }
            .buttonStyle(.plain)

            Divider().frame(height: 14)

            Menu {
                Button(item.pinned ? "Unpin" : "Pin") { actions.onTogglePin(); onClose() }
                Button("Copy") { actions.onCopy(); onClose() }
                Divider()
                Button("Delete", role: .destructive) { actions.onDelete(); onClose() }
            } label: {
                HStack(spacing: 6) {
                    Text("Actions")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.silverDim)
                    keyCap("⌘K")
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .keyboardShortcut("k", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.panel)
    }

    private func keyCap(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.silver)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private var appIcon: NSImage? {
        guard let bundleID = item.sourceApp,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private var contentTypeLabel: String {
        switch item.kind {
        case .text: return "Text"
        case .url: return "Link"
        case .image: return "Image"
        case .file: return "File"
        }
    }

    private var previewImageURL: URL? {
        switch item.kind {
        case .image: return item.imageFile.map { store.imageURL(for: $0) }
        case .url: return item.linkImageFile.map { store.imageURL(for: $0) }
        default: return nil
        }
    }

    private var dimensions: String? {
        guard let url = previewImageURL, let data = try? Data(contentsOf: url), let rep = NSBitmapImageRep(data: data) else { return nil }
        return "\(rep.pixelsWide)×\(rep.pixelsHigh)"
    }

    private var fileSize: String? {
        guard item.kind == .image, let file = item.imageFile,
              let size = try? FileManager.default.attributesOfItem(atPath: store.imageURL(for: file).path)[.size] as? Int else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    private var copiedLabel: String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(item.date) {
            formatter.dateFormat = "'Today at' h:mm:ss a"
        } else {
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
        }
        return formatter.string(from: item.date)
    }
}

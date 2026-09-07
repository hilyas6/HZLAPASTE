import AppKit

/// Polls the general pasteboard for changes (the standard technique — no private
/// API and no permission prompt needed) and files new content into the store.
final class ClipboardMonitor {
    private let store: ClipboardStore
    private var timer: Timer?
    private var lastChangeCount: Int
    private var ownChangeCount: Int?

    init(store: ClipboardStore) {
        self.store = store
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Called by PasteAction right before it writes back to the pasteboard, so that
    /// resulting change isn't re-captured as a brand new history entry.
    func markOwnWrite(changeCount: Int) {
        ownChangeCount = changeCount
    }

    /// Direct-type image UTIs in priority order, so we grab the original bytes
    /// (e.g. an actual animated GIF) instead of always round-tripping through a
    /// TIFF→PNG conversion, which silently discards GIF animation.
    private static let imageTypesByPriority: [(NSPasteboard.PasteboardType, String)] = [
        (NSPasteboard.PasteboardType("com.compuserve.gif"), "gif"),
        (.png, "png"),
        (NSPasteboard.PasteboardType("public.jpeg"), "jpg"),
        (.tiff, "tiff")
    ]

    private static let imageFileExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "tiff", "tif", "heic", "bmp", "webp"]

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        if let own = ownChangeCount, own == pb.changeCount { return }

        guard let item = pb.pasteboardItems?.first else { return }

        // Respect the org.nspasteboard convention password managers use to mark
        // copies (e.g. a generated password) as not meant to be stored.
        let concealedTypes: Set<String> = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"]
        if item.types.contains(where: { concealedTypes.contains($0.rawValue) }) { return }

        let frontmost = NSWorkspace.shared.frontmostApplication
        let sourceApp = frontmost?.bundleIdentifier
        let sourceAppName = frontmost?.localizedName
        if let sourceApp, ExcludedApps.contains(sourceApp) { return }

        if let fileURLString = item.string(forType: .fileURL), let url = URL(string: fileURLString) {
            let ext = url.pathExtension.lowercased()
            if Self.imageFileExtensions.contains(ext), let data = try? Data(contentsOf: url) {
                // Read the real file bytes (not a pasteboard-derived copy) so an
                // animated GIF file copied from Finder pastes back animated.
                store.addImage(data, ext: ext == "jpeg" ? "jpg" : ext, sourceApp: sourceApp, sourceAppName: sourceAppName)
            } else {
                store.addText(url.path, kind: .file, sourceApp: sourceApp, sourceAppName: sourceAppName)
            }
        } else if let (data, ext) = Self.imageTypesByPriority.lazy.compactMap({ type, ext in item.data(forType: type).map { ($0, ext) } }).first {
            store.addImage(data, ext: ext, sourceApp: sourceApp, sourceAppName: sourceAppName)
        } else if let text = item.string(forType: .string) {
            let looksLikeURL = !text.contains(" ") && !text.contains("\n") && URL(string: text)?.scheme != nil
            store.addText(text, kind: looksLikeURL ? .url : .text, sourceApp: sourceApp, sourceAppName: sourceAppName)
        }
    }
}

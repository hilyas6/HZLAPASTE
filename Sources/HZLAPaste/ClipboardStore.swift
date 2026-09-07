import Foundation

enum ClipKind: String, Codable, CaseIterable {
    case text, image, file, url

    var symbol: String {
        switch self {
        case .text: return "doc.text"
        case .image: return "photo"
        case .file: return "doc"
        case .url: return "link"
        }
    }

    var label: String {
        switch self {
        case .text: return "Text"
        case .image: return "Images"
        case .file: return "Files"
        case .url: return "Links"
        }
    }
}

struct ClipItem: Codable, Identifiable, Equatable {
    let id: UUID
    var kind: ClipKind
    var text: String?          // text/url/file path
    var imageFile: String?     // filename within Images/, for kind == .image
    var linkTitle: String? = nil     // OG-fetched page title, for kind == .url
    var linkImageFile: String? = nil // OG-fetched preview image filename within Images/, for kind == .url
    var sourceApp: String?
    var sourceAppName: String?
    var date: Date
    var pinned: Bool

    var previewText: String {
        guard kind == .image else { return text ?? "" }
        let ext = imageFile.map { ($0 as NSString).pathExtension.uppercased() } ?? ""
        return ext.isEmpty ? "Image" : "\(ext) Image"
    }
}

extension Array where Element == ClipItem {
    func filtered(query: String) -> [ClipItem] {
        guard !query.isEmpty else { return self }
        return filter { ($0.text ?? "").localizedCaseInsensitiveContains(query) }
    }
}

/// Whether the app shows a Dock icon in addition to the menu bar item. Read at
/// launch (App.swift) and toggled live from PreferencesView.
enum AppSettings {
    private static let showInDockKey = "showInDock"

    static var showInDock: Bool {
        get { UserDefaults.standard.object(forKey: showInDockKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: showInDockKey) }
    }

    /// Whether copying a link fetches its title/preview image (network request to
    /// whatever site was copied). Default on to match Paste's behavior; off for
    /// anyone who'd rather HZLAPaste never phone out on their behalf.
    static var fetchLinkPreviews: Bool {
        get { UserDefaults.standard.object(forKey: "fetchLinkPreviews") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "fetchLinkPreviews") }
    }
}

/// Bundle IDs of apps whose copies should never be captured. Backed by UserDefaults
/// so both the monitor and the preferences UI read/write the same list.
enum ExcludedApps {
    private static let key = "excludedBundleIDs"

    static var list: [String] {
        get { UserDefaults.standard.stringArray(forKey: key) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func contains(_ bundleID: String) -> Bool { list.contains(bundleID) }

    static func add(_ bundleID: String) {
        guard !list.contains(bundleID) else { return }
        list.append(bundleID)
    }

    static func remove(_ bundleID: String) {
        list.removeAll { $0 == bundleID }
    }
}

final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    private let fileManager = FileManager.default
    private let imagesDir: URL
    private let jsonURL: URL

    var historyLimit: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: "historyLimit")
            return v > 0 ? v : 200
        }
        set { UserDefaults.standard.set(newValue, forKey: "historyLimit") }
    }

    /// baseDirectory is injectable so tests don't touch the real Application Support folder.
    init(baseDirectory: URL? = nil) {
        let base = baseDirectory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HZLAPaste", isDirectory: true)
        imagesDir = base.appendingPathComponent("Images", isDirectory: true)
        jsonURL = base.appendingPathComponent("history.json")
        try? fileManager.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        load()
    }

    func imageURL(for filename: String) -> URL {
        imagesDir.appendingPathComponent(filename)
    }

    @discardableResult
    func addText(_ text: String, kind: ClipKind, sourceApp: String?, sourceAppName: String?) -> Bool {
        guard !text.isEmpty else { return false }
        if let idx = items.firstIndex(where: { $0.kind == kind && $0.text == text }) {
            var item = items.remove(at: idx)
            item.date = Date()
            items.insert(item, at: 0)
            save()
            return true
        }
        let item = ClipItem(id: UUID(), kind: kind, text: text, imageFile: nil,
                             sourceApp: sourceApp, sourceAppName: sourceAppName, date: Date(), pinned: false)
        items.insert(item, at: 0)
        trim()
        save()
        if kind == .url, AppSettings.fetchLinkPreviews {
            LinkPreviewFetcher.fetchAndStore(itemID: item.id, urlString: text, into: self)
        }
        return true
    }

    @discardableResult
    func addImage(_ data: Data, ext: String, sourceApp: String?, sourceAppName: String?) -> Bool {
        let filename = UUID().uuidString + "." + ext
        guard (try? data.write(to: imagesDir.appendingPathComponent(filename))) != nil else { return false }
        let item = ClipItem(id: UUID(), kind: .image, text: nil, imageFile: filename,
                             sourceApp: sourceApp, sourceAppName: sourceAppName, date: Date(), pinned: false)
        items.insert(item, at: 0)
        trim()
        save()
        return true
    }

    /// Called by LinkPreviewFetcher once a copied link's title/OG-image come back.
    func setLinkPreview(itemID: UUID, title: String?, imageData: Data?) {
        guard let idx = items.firstIndex(where: { $0.id == itemID }) else { return }
        if let imageData, !imageData.isEmpty {
            let filename = UUID().uuidString + ".jpg" // NSImage sniffs real format from content, not the extension
            if (try? imageData.write(to: imagesDir.appendingPathComponent(filename))) != nil {
                items[idx].linkImageFile = filename
            }
        }
        if let title, !title.isEmpty {
            items[idx].linkTitle = title
        }
        save()
    }

    func togglePin(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].pinned.toggle()
        save()
    }

    func delete(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        removeImageFiles(for: items[idx])
        items.remove(at: idx)
        save()
    }

    func clearUnpinned() {
        for item in items where !item.pinned {
            removeImageFiles(for: item)
        }
        items.removeAll { !$0.pinned }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: jsonURL),
              let decoded = try? JSONDecoder().decode([ClipItem].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: jsonURL, options: .atomic)
    }

    private func removeImageFiles(for item: ClipItem) {
        for file in [item.imageFile, item.linkImageFile].compactMap({ $0 }) {
            try? fileManager.removeItem(at: imagesDir.appendingPathComponent(file))
        }
    }

    // ponytail: O(n) rescan per removal, fine at MVP history sizes (hundreds of items).
    private func trim() {
        let limit = historyLimit
        while items.count > limit {
            guard let idx = items.lastIndex(where: { !$0.pinned }) else { break } // all pinned, allow overflow
            removeImageFiles(for: items[idx])
            items.remove(at: idx)
        }
    }
}

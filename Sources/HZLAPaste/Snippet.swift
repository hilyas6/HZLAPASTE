import Foundation

/// A keyword → body text-expansion pair, managed from Settings and expanded
/// system-wide by SnippetExpander. Unlike clipboard history, snippets are
/// permanent — the user authored them deliberately, so retention/archiving
/// never touches this store.
struct Snippet: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var keyword: String
    var body: String
    var createdAt: Date
    var lastUsedAt: Date?
    var useCount: Int

    init(id: UUID = UUID(), name: String, keyword: String, body: String,
         createdAt: Date = Date(), lastUsedAt: Date? = nil, useCount: Int = 0) {
        self.id = id
        self.name = name
        self.keyword = keyword
        self.body = body
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
    }
}

final class SnippetStore: ObservableObject {
    @Published private(set) var snippets: [Snippet] = []

    private let jsonURL: URL

    /// baseDirectory is injectable so tests don't touch the real Application Support folder.
    init(baseDirectory: URL? = nil) {
        let base = baseDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HZLAPaste", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        jsonURL = base.appendingPathComponent("snippets.json")
        load()
    }

    @discardableResult
    func add(name: String, keyword: String, body: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !keyword.isEmpty, !body.isEmpty else { return false }
        snippets.insert(Snippet(name: name, keyword: keyword, body: body), at: 0)
        save()
        return true
    }

    func update(_ id: UUID, name: String, keyword: String, body: String) {
        guard let idx = snippets.firstIndex(where: { $0.id == id }) else { return }
        snippets[idx].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        snippets[idx].keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        snippets[idx].body = body
        save()
    }

    func delete(_ id: UUID) {
        snippets.removeAll { $0.id == id }
        save()
    }

    /// Called by SnippetExpander right after a successful expansion.
    func recordUse(_ id: UUID) {
        guard let idx = snippets.firstIndex(where: { $0.id == id }) else { return }
        snippets[idx].useCount += 1
        snippets[idx].lastUsedAt = Date()
        save()
    }

    private func load() {
        guard let raw = try? Data(contentsOf: jsonURL) else { return }
        if let decrypted = SecureStorage.decrypt(raw), let decoded = try? JSONDecoder().decode([Snippet].self, from: decrypted) {
            snippets = decoded
            return
        }
        if let decoded = try? JSONDecoder().decode([Snippet].self, from: raw) {
            snippets = decoded
            save()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(snippets), let encrypted = SecureStorage.encrypt(data) else { return }
        try? encrypted.write(to: jsonURL, options: .atomic)
    }
}

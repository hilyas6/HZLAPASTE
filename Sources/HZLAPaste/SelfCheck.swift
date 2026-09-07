import Foundation

/// Runs with `swift run HZLAPaste --self-check`. Exercises the non-trivial pure
/// logic (trim/pin/dedup/search) against a throwaway directory — no UI, no
/// touching the real Application Support folder. Manual checks rather than
/// `assert` so this still works when built with `-c release` (asserts are
/// stripped there).
func runSelfCheck() -> Bool {
    var failures: [String] = []
    func check(_ condition: Bool, _ message: String) {
        if !condition { failures.append(message) }
    }

    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }

    let trimStore = ClipboardStore(baseDirectory: root.appendingPathComponent("trim"))
    trimStore.historyLimit = 3
    trimStore.addText("one", kind: .text, sourceApp: nil, sourceAppName: nil)
    trimStore.togglePin(trimStore.items[0].id)
    trimStore.addText("two", kind: .text, sourceApp: nil, sourceAppName: nil)
    trimStore.addText("three", kind: .text, sourceApp: nil, sourceAppName: nil)
    trimStore.addText("four", kind: .text, sourceApp: nil, sourceAppName: nil)
    let texts = trimStore.items.compactMap { $0.text }
    check(trimStore.items.count == 3, "trim should cap at historyLimit (got \(trimStore.items.count))")
    check(texts.contains("one"), "pinned item must survive trimming")
    check(!texts.contains("two"), "oldest unpinned item should be dropped first")

    let dedupStore = ClipboardStore(baseDirectory: root.appendingPathComponent("dedup"))
    dedupStore.addText("alpha", kind: .text, sourceApp: nil, sourceAppName: nil)
    dedupStore.addText("beta", kind: .text, sourceApp: nil, sourceAppName: nil)
    dedupStore.addText("alpha", kind: .text, sourceApp: nil, sourceAppName: nil)
    check(dedupStore.items.count == 2, "re-copying should not duplicate (got \(dedupStore.items.count))")
    check(dedupStore.items.first?.text == "alpha", "re-copied item should move back to top")

    let results = dedupStore.items.filtered(query: "ALPHA")
    check(results.count == 1 && results.first?.text == "alpha", "search should be a case-insensitive substring match")

    // LinkPreviewFetcher's HTML parsing — pure functions, no network involved.
    let html = """
    <html><head>
    <meta name="description" content="not this one">
    <meta content="Sample Title &amp; More" property="og:title">
    <meta property="og:image" content="https://example.com/img.jpg">
    <title>Fallback Title</title>
    </head></html>
    """
    check(LinkPreviewFetcher.metaContent(html, property: "og:title") == "Sample Title & More",
          "og:title extraction should work regardless of attribute order and decode entities")
    check(LinkPreviewFetcher.metaContent(html, property: "og:image") == "https://example.com/img.jpg",
          "og:image extraction")
    check(LinkPreviewFetcher.titleTag("<title>Just A Title</title>") == "Just A Title",
          "<title> fallback extraction when no og:title is present")

    // SecureStorage — AES-GCM round trip for the encrypted-at-rest history/snippets files.
    let secret = "hzlapaste secret \(UUID())".data(using: .utf8)!
    let encrypted = SecureStorage.encrypt(secret)
    check(encrypted != nil && encrypted != secret, "encrypt should produce non-nil ciphertext distinct from the plaintext")
    check(encrypted.flatMap(SecureStorage.decrypt) == secret, "decrypt(encrypt(x)) should round-trip to the original bytes")
    check(SecureStorage.decrypt("not encrypted at all".data(using: .utf8)!) == nil,
          "decrypting non-ciphertext (e.g. legacy plaintext JSON) should fail cleanly, not crash or return garbage")

    // matchSnippet — the pure keyword-matching core of SnippetExpander.
    let snippets = [
        Snippet(name: "Email", keyword: ";email", body: "hanzlailyas345@gmail.com"),
        Snippet(name: "Sig", keyword: "sig", body: "Best,\nHanzla"),
    ]
    check(matchSnippet(buffer: ";email", in: snippets)?.body == "hanzlailyas345@gmail.com",
          "exact keyword match should return the matching snippet")
    check(matchSnippet(buffer: ";emai", in: snippets) == nil, "a partial keyword should not match")
    check(matchSnippet(buffer: "sig2", in: snippets) == nil, "a keyword must match the whole word, not just a prefix")
    check(matchSnippet(buffer: "Sig", in: snippets) == nil, "matching is case-sensitive by design")
    check(matchSnippet(buffer: "", in: snippets) == nil, "an empty buffer never matches")

    // Retention sweep — archive after N days, delete after M days, pinned items exempt.
    // now: is injectable specifically so this can simulate time passing without
    // needing to fabricate items with backdated timestamps.
    // archiveAfterDays/deleteAfterDays are UserDefaults-backed (real app settings,
    // not sandboxed like ClipboardStore's baseDirectory) — pin them to known
    // values for the duration of this check and restore whatever was there
    // before, so running --self-check can't silently change the user's real
    // retention settings.
    let originalArchiveDays = AppSettings.archiveAfterDays
    let originalDeleteDays = AppSettings.deleteAfterDays
    AppSettings.archiveAfterDays = 7
    AppSettings.deleteAfterDays = 30
    defer {
        AppSettings.archiveAfterDays = originalArchiveDays
        AppSettings.deleteAfterDays = originalDeleteDays
    }

    let retentionStore = ClipboardStore(baseDirectory: root.appendingPathComponent("retention"))
    retentionStore.addText("stays-active", kind: .text, sourceApp: nil, sourceAppName: nil)
    retentionStore.addText("gets-archived", kind: .text, sourceApp: nil, sourceAppName: nil)
    retentionStore.addText("pinned-forever", kind: .text, sourceApp: nil, sourceAppName: nil)
    retentionStore.togglePin(retentionStore.items.first { $0.text == "pinned-forever" }!.id)

    let eightDaysOut = Date().addingTimeInterval(8 * 86400)
    retentionStore.performRetentionSweep(now: eightDaysOut)
    let afterArchive = Dictionary(uniqueKeysWithValues: retentionStore.items.map { ($0.text, $0.archivedAt != nil) })
    check(afterArchive["gets-archived"] == true, "unpinned items past archiveAfterDays should be archived")
    check(afterArchive["pinned-forever"] == false, "pinned items are exempt from archiving")

    let thirtyOneDaysOut = Date().addingTimeInterval(31 * 86400)
    retentionStore.performRetentionSweep(now: thirtyOneDaysOut)
    let remainingTexts = Set(retentionStore.items.compactMap { $0.text })
    check(!remainingTexts.contains("gets-archived"), "items past deleteAfterDays should be permanently removed")
    check(remainingTexts.contains("pinned-forever"), "pinned items are exempt from deletion too")

    if failures.isEmpty {
        print("✅ HZLAPaste self-check passed")
        return true
    } else {
        for f in failures { print("❌ \(f)") }
        return false
    }
}

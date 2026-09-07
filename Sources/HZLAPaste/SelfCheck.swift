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

    if failures.isEmpty {
        print("✅ HZLAPaste self-check passed")
        return true
    } else {
        for f in failures { print("❌ \(f)") }
        return false
    }
}

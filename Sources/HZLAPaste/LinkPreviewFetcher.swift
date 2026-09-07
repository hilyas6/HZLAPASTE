import Foundation

/// Fetches a copied link's Open Graph title/image (what Paste and browsers show
/// as a rich preview) and writes it back into the store once it arrives. Plain
/// completion-handler URLSession, not async/await, to match the rest of the
/// codebase's callback style and avoid mixing concurrency models for one feature.
enum LinkPreviewFetcher {
    static func fetchAndStore(itemID: UUID, urlString: String, into store: ClipboardStore) {
        guard let url = URL(string: urlString), url.scheme == "http" || url.scheme == "https" else { return }

        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) HZLAPaste/1.0", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard let data, let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
            else { return }

            let title = metaContent(html, property: "og:title") ?? titleTag(html)
            let imageURL = metaContent(html, property: "og:image").flatMap { URL(string: $0, relativeTo: url) }

            guard let imageURL else {
                finish(itemID: itemID, title: title, imageData: nil, into: store)
                return
            }
            URLSession.shared.dataTask(with: imageURL) { imageData, _, _ in
                finish(itemID: itemID, title: title, imageData: imageData, into: store)
            }.resume()
        }.resume()
    }

    private static func finish(itemID: UUID, title: String?, imageData: Data?, into store: ClipboardStore) {
        guard title != nil || imageData != nil else { return }
        DispatchQueue.main.async {
            store.setLinkPreview(itemID: itemID, title: title, imageData: imageData)
        }
    }

    /// Extracts `content` from `<meta property="…">` or `<meta name="…">`, in
    /// either attribute order, since real-world pages vary.
    static func metaContent(_ html: String, property: String) -> String? {
        guard let tagRegex = try? NSRegularExpression(pattern: "<meta[^>]+>", options: [.caseInsensitive]) else { return nil }
        let nsHTML = html as NSString
        for match in tagRegex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) {
            let tag = nsHTML.substring(with: match.range)
            let prop = attribute("property", in: tag) ?? attribute("name", in: tag)
            guard let prop, prop.caseInsensitiveCompare(property) == .orderedSame else { continue }
            if let content = attribute("content", in: tag) {
                return content.decodingHTMLEntities()
            }
        }
        return nil
    }

    static func titleTag(_ html: String) -> String? {
        guard let range = html.range(of: "<title[^>]*>([^<]*)</title>", options: [.regularExpression, .caseInsensitive]),
              let inner = html[range].range(of: ">([^<]*)<", options: .regularExpression) else { return nil }
        let text = html[range][inner].dropFirst().dropLast()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.decodingHTMLEntities()
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let range = tag.range(of: "\(name)=[\"']([^\"']*)[\"']", options: [.regularExpression, .caseInsensitive]),
              let valueRange = tag[range].range(of: "[\"']([^\"']*)[\"']", options: .regularExpression) else { return nil }
        return String(tag[range][valueRange].dropFirst().dropLast())
    }
}

private extension String {
    func decodingHTMLEntities() -> String {
        replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}

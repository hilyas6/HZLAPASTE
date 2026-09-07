import SwiftUI
import AppKit

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var query = ""
    @Published var selectedID: UUID?
    @Published var kindFilter: ClipKind?

    let store: ClipboardStore
    var onPaste: (ClipItem) -> Void = { _ in }   // Enter / click: paste, or open a link in the browser
    var onCopy: (ClipItem) -> Void = { _ in }    // ⌘Enter: just copy to the pasteboard
    var onPreview: (ClipItem) -> Void = { _ in } // Space: big Quick Look-style preview
    var onEscape: () -> Void = {}
    var onOpenPreferences: () -> Void = {}       // ⌘,

    /// The selected card's on-screen frame (SwiftUI global space — top-left origin,
    /// updated by a GeometryReader on whichever card is currently selected), so the
    /// preview panel can anchor itself right next to the card instead of just
    /// centering blindly on screen.
    @Published var selectedCardFrame: CGRect = .zero

    init(store: ClipboardStore) {
        self.store = store
    }

    var filtered: [ClipItem] {
        let active = store.items.filter { $0.archivedAt == nil } // archived items live in the Archive tab, not the bar
        let pinned = active.filter { $0.pinned }
        let unpinned = active.filter { !$0.pinned }
        var items = (pinned + unpinned).filtered(query: query)
        if let kindFilter {
            items = items.filter { $0.kind == kindFilter }
        }
        return items
    }

    func resetSelection() {
        selectedID = filtered.first?.id
    }

    func move(_ delta: Int) {
        let list = filtered
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.id == selectedID } ?? 0
        selectedID = list[max(0, min(list.count - 1, current + delta))].id
    }

    func confirmSelection() {
        guard let id = selectedID, let item = filtered.first(where: { $0.id == id }) else { return }
        onPaste(item)
    }

    func confirmCopyOnly() {
        guard let id = selectedID, let item = filtered.first(where: { $0.id == id }) else { return }
        onCopy(item)
    }

    func confirmPreview() {
        guard let id = selectedID, let item = filtered.first(where: { $0.id == id }) else { return }
        onPreview(item)
    }
}

private let cardMinWidth: CGFloat = 168
private let cardHeight: CGFloat = 150
private let gridSpacing: CGFloat = 12

/// Bubbles the currently-selected card's on-screen frame up to HistoryView, so it
/// can hand it off when opening the preview panel.
private struct SelectedCardFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    // Only the selected card reports a non-zero frame; every other (unselected)
    // sibling reports .zero. Plain "last wins" would let whichever unselected card
    // happens to reduce last stomp the real value with its .zero — ignore zero
    // contributions instead, so the one real value always survives regardless of
    // sibling iteration order.
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

struct HistoryView: View {
    @ObservedObject var viewModel: HistoryViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            barContent

            if viewModel.filtered.isEmpty {
                Spacer(minLength: 0)
                Text(viewModel.store.items.isEmpty ? "No clipboard history yet" : "No matches")
                    .foregroundStyle(Theme.silverDim)
                    .padding()
                Spacer(minLength: 0)
            }
        }
        .background(backgroundShape.fill(.regularMaterial))
        .clipShape(backgroundShape)
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.resetSelection()
            searchFocused = true
        }
        .onChange(of: viewModel.query) { viewModel.resetSelection() }
    }

    private var barContent: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: gridSpacing) {
                    ForEach(viewModel.filtered) { item in
                        cardView(for: item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel.selectedID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
            .onPreferenceChange(SelectedCardFramePreferenceKey.self) { viewModel.selectedCardFrame = $0 }
        }
    }

    /// A single click acts immediately (paste/open) — this is a quick-glance shelf,
    /// not a browsing grid, so there's no need for a separate select-then-confirm step.
    private func cardView(for item: ClipItem) -> some View {
        HistoryCard(item: item, isSelected: item.id == viewModel.selectedID, store: viewModel.store)
            .id(item.id)
            .frame(width: cardMinWidth, height: cardHeight)
            .background(selectedFrameReporter(for: item))
            .contentShape(Rectangle())
            .onTapGesture(count: 1) { viewModel.selectedID = item.id; viewModel.onPaste(item) }
            .contextMenu {
                Button(item.pinned ? "Unpin" : "Pin") { viewModel.store.togglePin(item.id) }
                Button("Delete", role: .destructive) { viewModel.store.delete(item.id) }
            }
    }

    /// Structurally identical for every card (always a GeometryReader; only the
    /// reported *value* depends on selection) — swapping between two different view
    /// types via if/else here caused preference updates to silently stop propagating
    /// after a selection change, since SwiftUI treats that as remounting a new subtree.
    private func selectedFrameReporter(for item: ClipItem) -> some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: SelectedCardFramePreferenceKey.self,
                value: item.id == viewModel.selectedID ? geo.frame(in: .global) : .zero
            )
        }
    }

    /// The bar sits flush against the Dock, so only its top corners should read as
    /// rounded — rounding the bottom too would look like the bar is floating.
    private var backgroundShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 22, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 22,
            style: .continuous
        )
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.silverDim)
            TextField("Search clipboard history…", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.silver)
                .focused($searchFocused)
                .onKeyPress(keys: [.upArrow, .leftArrow]) { _ in viewModel.move(-1); return .handled }
                .onKeyPress(keys: [.downArrow, .rightArrow]) { _ in viewModel.move(1); return .handled }
                // Space previews instead of typing a literal space — same convention
                // as Spotlight/Quick Look, which this app already mirrors elsewhere.
                .onKeyPress(keys: [.space]) { _ in viewModel.confirmPreview(); return .handled }
                .onKeyPress(keys: [","]) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    viewModel.onOpenPreferences()
                    return .handled
                }
                .onKeyPress(keys: [.return]) { press in
                    if press.modifiers.contains(.command) {
                        viewModel.confirmCopyOnly()
                    } else {
                        viewModel.confirmSelection()
                    }
                    return .handled
                }
                .onExitCommand { viewModel.onEscape() }

            FilterDock(selected: $viewModel.kindFilter)

            Button(action: viewModel.onOpenPreferences) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.silverDim)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .background(.thinMaterial, in: Circle())
            .help("Settings (⌘,)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .padding(10)
    }
}

/// A row of clickable kind icons — "All" plus one per ClipKind — instead of a
/// dropdown menu, so filtering is a single click right next to the search field.
private struct FilterDock: View {
    @Binding var selected: ClipKind?

    var body: some View {
        HStack(spacing: 3) {
            dockButton(symbol: "square.grid.2x2", isSelected: selected == nil, label: "All") { selected = nil }
            ForEach(ClipKind.allCases, id: \.self) { kind in
                dockButton(symbol: kind.symbol, isSelected: selected == kind, label: kind.label) { selected = kind }
            }
        }
        .padding(4)
        .background(.thinMaterial, in: Capsule())
    }

    private func dockButton(symbol: String, isSelected: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Theme.background : Theme.silverDim)
        .background(Capsule().fill(isSelected ? Theme.gold : Color.clear))
    }
}

private let relativeTimeFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter
}()

private struct HistoryCard: View {
    let item: ClipItem
    let isSelected: Bool
    let store: ClipboardStore
    @State private var isHovering = false

    private var thumbnail: NSImage? {
        guard item.kind == .image, let file = item.imageFile else { return nil }
        return NSImage(contentsOf: store.imageURL(for: file))
    }

    private var linkPreviewImage: NSImage? {
        guard item.kind == .url, let file = item.linkImageFile else { return nil }
        return NSImage(contentsOf: store.imageURL(for: file))
    }

    private var domain: String? {
        guard let text = item.text, let url = URL(string: text), let host = url.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private var relativeTime: String {
        relativeTimeFormatter.localizedString(for: item.date, relativeTo: Date())
    }

    var body: some View {
        Group {
            if let thumbnail {
                imageCard(thumbnail)
            } else if let linkPreviewImage {
                linkPreviewCard(linkPreviewImage)
            } else {
                textCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(isSelected ? Theme.gold : Color.clear, lineWidth: 2)
        )
        .shadow(color: .black.opacity(isHovering ? 0.35 : 0.18), radius: isHovering ? 10 : 4, y: isHovering ? 5 : 2)
        .onHover { isHovering = $0 }
    }

    private func imageCard(_ image: NSImage) -> some View {
        ZStack(alignment: .bottom) {
            // GeometryReader hands the image an exact, known box before it scales —
            // chaining separate .frame() modifiers around .aspectRatio(.fill) lets
            // each one get resolved against a different proposed size and can distort
            // the image; this boxes it once so it can only crop, never stretch.
            GeometryReader { geo in
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }

            HStack {
                Text(relativeTime)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.silver)
                Spacer()
                if item.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.gold)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
        }
        .background(Theme.card)
    }

    /// A copied link whose Open Graph title/image have come back — richer than
    /// textCard's plain link chip, and with a real footer (not text stamped over
    /// a photo) since we actually have a title to show here.
    private func linkPreviewCard(_ image: NSImage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                GeometryReader { geo in
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }

                if item.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.gold)
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(6)
                }
            }
            .frame(height: cardHeight * 0.6)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.linkTitle ?? item.previewText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.silver)
                    .lineLimit(2)
                Text(domain ?? relativeTime)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(Theme.silverDim)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial)
        }
        .background(Theme.card)
    }

    private var textCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ZStack {
                    Circle().fill(Theme.accent(for: item.kind).opacity(0.2))
                    Image(systemName: item.kind.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accent(for: item.kind))
                }
                .frame(width: 26, height: 26)

                Spacer()

                if item.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.gold)
                }
            }

            Text(item.linkTitle ?? item.previewText)
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.silver)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if item.linkTitle != nil, let domain {
                Text(domain)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(Theme.silverDim)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(relativeTime)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(Theme.silverDim)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.thinMaterial)
    }

}

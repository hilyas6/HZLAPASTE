import SwiftUI

/// The "bin" for clipboard items between archiving (after archiveAfterDays)
/// and permanent deletion (after deleteAfterDays) — browse, restore, or clear
/// them early.
struct ArchiveView: View {
    @ObservedObject var store: ClipboardStore

    private var archived: [ClipItem] {
        store.items.filter { $0.archivedAt != nil }.sorted { ($0.archivedAt ?? $0.date) > ($1.archivedAt ?? $1.date) }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            Text("Items older than \(AppSettings.archiveAfterDays) days move here automatically, and are deleted forever after \(AppSettings.deleteAfterDays) days total.")
                .font(.caption)
                .foregroundStyle(Theme.silverDim)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)

            if archived.isEmpty {
                Spacer()
                Text("Archive is empty")
                    .foregroundStyle(Theme.silverDim)
                Spacer()
            } else {
                List {
                    ForEach(archived) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.previewText)
                                    .foregroundStyle(Theme.silver)
                                    .lineLimit(1)
                                if let archivedAt = item.archivedAt {
                                    Text("Archived \(Self.dateFormatter.string(from: archivedAt))")
                                        .font(.caption)
                                        .foregroundStyle(Theme.silverDim)
                                }
                            }
                            Spacer()
                            Button("Restore") { store.restore(item.id) }
                            Button("Delete Now", role: .destructive) { store.delete(item.id) }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(minWidth: 460, minHeight: 460)
        .background(.regularMaterial)
        .preferredColorScheme(.dark)
    }
}

import SwiftUI

struct SnippetsView: View {
    @ObservedObject var store: SnippetStore
    @State private var editing: Snippet?
    @State private var isPresentingNew = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Type a keyword anywhere, then a space/tab/return — it expands to the snippet body.")
                    .font(.caption)
                    .foregroundStyle(Theme.silverDim)
                Spacer()
                Button {
                    isPresentingNew = true
                } label: {
                    Label("New Snippet", systemImage: "plus")
                }
                .tint(Theme.gold)
            }
            .padding(16)

            if store.snippets.isEmpty {
                Spacer()
                Text("No snippets yet")
                    .foregroundStyle(Theme.silverDim)
                Spacer()
            } else {
                List {
                    ForEach(store.snippets) { snippet in
                        Button {
                            editing = snippet
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(snippet.name)
                                        .foregroundStyle(Theme.silver)
                                    Text(snippet.body)
                                        .font(.caption)
                                        .foregroundStyle(Theme.silverDim)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(snippet.keyword)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .foregroundStyle(Theme.gold)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Edit") { editing = snippet }
                            Button("Delete", role: .destructive) { store.delete(snippet.id) }
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet { store.delete(store.snippets[index].id) }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(minWidth: 460, minHeight: 460)
        .background(.regularMaterial)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isPresentingNew) {
            SnippetEditorView(store: store, snippet: nil)
        }
        .sheet(item: $editing) { snippet in
            SnippetEditorView(store: store, snippet: snippet)
        }
    }
}

private struct SnippetEditorView: View {
    @ObservedObject var store: SnippetStore
    let snippet: Snippet?
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var keyword = ""
    @State private var bodyText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(snippet == nil ? "New Snippet" : "Edit Snippet")
                .font(Theme.headerFont)
                .foregroundStyle(Theme.silver)

            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(.caption).foregroundStyle(Theme.silverDim)
                TextField("e.g. Work Email", text: $name).textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Keyword").font(.caption).foregroundStyle(Theme.silverDim)
                TextField("e.g. ;email", text: $keyword).textFieldStyle(.roundedBorder)
                Text("Tip: a distinctive prefix like \";\" or \":\" avoids accidentally triggering on real words.")
                    .font(.caption2)
                    .foregroundStyle(Theme.silverDim)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Snippet").font(.caption).foregroundStyle(Theme.silverDim)
                TextEditor(text: $bodyText)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 120)
                    .padding(6)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .scrollContentBackground(.hidden)
            }

            HStack {
                if snippet != nil {
                    Button("Delete", role: .destructive) {
                        store.delete(snippet!.id)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button(snippet == nil ? "Add" : "Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.gold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                        || keyword.trimmingCharacters(in: .whitespaces).isEmpty
                        || bodyText.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(.regularMaterial)
        .preferredColorScheme(.dark)
        .onAppear {
            guard let snippet else { return }
            name = snippet.name
            keyword = snippet.keyword
            bodyText = snippet.body
        }
    }

    private func save() {
        if let snippet {
            store.update(snippet.id, name: name, keyword: keyword, body: bodyText)
        } else {
            store.add(name: name, keyword: keyword, body: bodyText)
        }
        dismiss()
    }
}

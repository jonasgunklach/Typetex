//
//  SnippetsView.swift
//  Typetex
//

import SwiftUI

// MARK: - Snippets palette

struct SnippetsView: View {
    let onInsert: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var selectedCategory: String? = nil

    private var categories: [String] { LaTeXSnippet.categories }

    private var filtered: [LaTeXSnippet] {
        let base = selectedCategory.map { cat in LaTeXSnippet.all.filter { $0.category == cat } }
                   ?? LaTeXSnippet.all
        guard !search.isEmpty else { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.code.localizedCaseInsensitiveContains(search) ||
            $0.description.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        CategoryPill(label: "All", isSelected: selectedCategory == nil) {
                            selectedCategory = nil
                        }
                        ForEach(categories, id: \.self) { cat in
                            CategoryPill(label: cat, isSelected: selectedCategory == cat) {
                                selectedCategory = selectedCategory == cat ? nil : cat
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .background(.bar)

                Divider()

                // Snippet list
                if filtered.isEmpty {
                    ContentUnavailableView.search(text: search)
                        .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filtered) { snippet in
                            SnippetRow(snippet: snippet) {
                                onInsert(snippet.code)
                                dismiss()
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Snippets")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .searchable(text: $search)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
#if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
#endif
    }
}

// MARK: - Snippet row

struct SnippetRow: View {
    let snippet: LaTeXSnippet
    let onInsert: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onInsert) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(snippet.name)
                        .font(.body.weight(.medium))
                    Spacer()
                    Text(snippet.category)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.12), in: Capsule())
                        .foregroundStyle(.tint)
                }
                Text(snippet.code)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Category pill

struct CategoryPill: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

#Preview {
    SnippetsView { code in print(code) }
}

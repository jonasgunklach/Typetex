//
//  SidebarContentViews.swift
//  Typetex
//
//  Outline, TODOs, and Errors sidebar panels.
//

import SwiftUI

// MARK: - Outline

struct OutlineListView: View {
    let document: LaTeXDocument?
    @Environment(EditorViewModel.self) private var vm

    var body: some View {
        Group {
            if let _ = document {
                if vm.outlineItems.isEmpty {
                    emptyState(
                        icon: "list.bullet.indent",
                        title: "No Sections",
                        body: "Add \\section{…} headings to build the outline."
                    )
                } else {
                    List {
                        ForEach(vm.outlineItems) { item in
                            OutlineRow(item: item)
                        }
                    }
                    .listStyle(.sidebar)
                }
            } else {
                noDocumentState
            }
        }
    }
}

struct OutlineRow: View {
    let item: OutlineItem

    var body: some View {
        Button {
            NotificationCenter.default.post(
                name: .jumpToLine,
                object: nil,
                userInfo: ["line": item.lineNumber]
            )
        } label: {
            Label {
                Text(item.title)
                    .font(item.level == .chapter || item.level == .section ? .body.weight(.semibold) : .body)
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: item.level.systemImage)
                    .foregroundStyle(.tint)
            }
            .padding(.leading, item.level.indentWidth)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - TODOs

struct TodoListView: View {
    let document: LaTeXDocument?
    @Environment(EditorViewModel.self) private var vm

    var body: some View {
        Group {
            if let _ = document {
                if vm.todoItems.isEmpty {
                    emptyState(
                        icon: "checkmark.circle",
                        title: "No TODOs",
                        body: "Add % TODO: comments to track tasks."
                    )
                } else {
                    List {
                        ForEach(vm.todoItems) { todo in
                            TodoRow(item: todo)
                        }
                    }
                    .listStyle(.sidebar)
                }
            } else {
                noDocumentState
            }
        }
    }
}

struct TodoRow: View {
    let item: TodoItem

    var body: some View {
        Button {
            NotificationCenter.default.post(
                name: .jumpToLine,
                object: nil,
                userInfo: ["line": item.lineNumber]
            )
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.text)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text("Line \(item.lineNumber)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "circle")
                    .foregroundStyle(.orange)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}

// MARK: - Errors / Warnings

struct ErrorListView: View {
    let document: LaTeXDocument?
    @Environment(EditorViewModel.self) private var vm

    var body: some View {
        Group {
            if let _ = document {
                if vm.compileMessages.isEmpty {
                    emptyState(
                        icon: "checkmark.seal",
                        title: "No Issues",
                        body: "Compile your document to check for errors."
                    )
                } else {
                    List {
                        ForEach(vm.compileMessages) { msg in
                            ErrorRow(message: msg)
                        }
                    }
                    .listStyle(.sidebar)
                }
            } else {
                noDocumentState
            }
        }
    }
}

struct ErrorRow: View {
    let message: CompileMessage

    var iconColor: Color {
        switch message.severity {
        case .error:   return .red
        case .warning: return .orange
        case .info:    return .blue
        }
    }

    var body: some View {
        Button {
            if let ln = message.lineNumber {
                NotificationCenter.default.post(
                    name: .jumpToLine,
                    object: nil,
                    userInfo: ["line": ln]
                )
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.message)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let ln = message.lineNumber {
                        Text("Line \(ln)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let ctx = message.context {
                        Text(ctx)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } icon: {
                Image(systemName: message.severity.systemImage)
                    .foregroundStyle(iconColor)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}

// MARK: - Shared helper views

private var noDocumentState: some View {
    ContentUnavailableView(
        "No Document",
        systemImage: "doc.text",
        description: Text("Select a document to see its details.")
    )
}

private func emptyState(icon: String, title: String, body: String) -> some View {
    ContentUnavailableView(title, systemImage: icon, description: Text(body))
}

//
//  PDFPreviewView.swift
//  Typetex
//

import SwiftUI

struct PDFPreviewView: View {
    @Environment(EditorViewModel.self) private var vm

    private var doc: TypesetDocument { vm.typesetDocument }

    var body: some View {
        Group {
            if !doc.pages.isEmpty {
                pageScrollView
            } else {
                placeholder
            }
        }
        .navigationTitle("Preview")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    CHITestBenchView()
                } label: {
                    Label("ACM CHI Test Bench", systemImage: "doc.badge.gearshape")
                }
            }
        }
    }

    // MARK: - Page scroll view

    private var pageScrollView: some View {
        ScrollView {
            VStack(spacing: 28) {
                ForEach(Array(doc.pages.enumerated()), id: \.offset) { _, page in
                    TeXPageView(page: page,
                                geometry: doc.geometry,
                                fonts: doc.fonts)
                        .shadow(color: .black.opacity(0.18), radius: 8, x: 2, y: 4)
                }
            }
            .padding(.vertical, 36)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
        }
        .background(Color(white: 0.78))  // gray desktop background like Overleaf/TeXworks
    }

    // MARK: - Placeholder

    private var placeholder: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("No Preview Yet")
                    .font(.title2.bold())

                switch vm.compileState {
                case .idle:
                    Text("Press **Render** in the editor toolbar to preview the document.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                case .compiling:
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Rendering\u{2026}")
                            .foregroundStyle(.secondary)
                    }
                case .failed:
                    Text("Check the **Errors** panel for issues.")
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                case .success:
                    EmptyView()
                }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

//
//  Item.swift
//  Typetex
//

import Foundation
import SwiftData

// MARK: - Core data model

@Model
final class LaTeXDocument {
    @Attribute(.unique) var id: UUID
    var title: String
    var content: String
    var createdAt: Date
    var modifiedAt: Date
    var templateName: String
    var workspace: LaTeXWorkspace?    // nil = standalone SwiftData doc
    var relativePath: String?         // path relative to workspace folder; nil = standalone

    init(
        title: String = "Untitled",
        content: String = LaTeXDocument.defaultContent,
        templateName: String = "Article"
    ) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.templateName = templateName
    }

    static let defaultContent = """
\\documentclass[12pt,a4paper]{article}
\\usepackage[utf8]{inputenc}
\\usepackage{amsmath}

\\title{Untitled}
\\author{}
\\date{\\today}

\\begin{document}

\\maketitle

\\section{Introduction}

Hello, \\LaTeX!

\\end{document}
"""
}

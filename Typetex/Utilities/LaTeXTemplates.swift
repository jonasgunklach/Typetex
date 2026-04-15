//
//  LaTeXTemplates.swift
//  Typetex
//

import Foundation

// MARK: - Template

struct LaTeXTemplate: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let description: String
    let content: String
}

// MARK: - Built-in templates

extension LaTeXTemplate {
    static let article = LaTeXTemplate(
        name: "Article",
        icon: "doc.text",
        description: "Standard academic article",
        content: """
\\documentclass[12pt,a4paper]{article}
\\usepackage[utf8]{inputenc}
\\usepackage[T1]{fontenc}
\\usepackage{amsmath,amssymb}
\\usepackage{graphicx}
\\usepackage{hyperref}

\\title{Article Title}
\\author{Author Name}
\\date{\\today}

\\begin{document}

\\maketitle

\\begin{abstract}
Your abstract goes here. Summarise the key contributions of your work.
\\end{abstract}

\\section{Introduction}
\\label{sec:intro}

Your introduction here. Cite sources like this~\\cite{key2024}.

\\section{Main Content}

\\subsection{Subsection}

Inline math: $E = mc^2$. Display math:
\\begin{equation}
    \\int_0^\\infty e^{-x^2}\\,dx = \\frac{\\sqrt{\\pi}}{2}
\\end{equation}

\\section{Conclusion}

Your conclusion here.

% TODO: Add bibliography file

\\bibliographystyle{plain}
\\bibliography{references}

\\end{document}
"""
    )

    static let report = LaTeXTemplate(
        name: "Report",
        icon: "doc.richtext",
        description: "Formal report with chapters",
        content: """
\\documentclass[12pt,a4paper]{report}
\\usepackage[utf8]{inputenc}
\\usepackage[T1]{fontenc}
\\usepackage{amsmath,amssymb}
\\usepackage{graphicx}
\\usepackage{hyperref}

\\title{Report Title}
\\author{Author Name}
\\date{\\today}

\\begin{document}

\\maketitle
\\tableofcontents

\\chapter{Introduction}
\\label{chap:intro}

% TODO: Write introduction

\\chapter{Background}

\\chapter{Methodology}

\\chapter{Results}

\\chapter{Conclusion}

\\bibliographystyle{plain}
\\bibliography{references}

\\end{document}
"""
    )

    static let thesis = LaTeXTemplate(
        name: "Thesis",
        icon: "graduationcap",
        description: "University thesis / dissertation",
        content: """
\\documentclass[12pt,a4paper,twoside]{report}
\\usepackage[utf8]{inputenc}
\\usepackage[T1]{fontenc}
\\usepackage{amsmath,amssymb,amsthm}
\\usepackage{graphicx}
\\usepackage{hyperref}
\\usepackage{setspace}
\\usepackage{geometry}

\\geometry{a4paper, inner=3cm, outer=2.5cm, top=2.5cm, bottom=2.5cm}
\\doublespacing

\\title{Thesis Title}
\\author{Your Name}
\\date{\\today}

\\begin{document}

\\maketitle

\\begin{abstract}
\\addcontentsline{toc}{chapter}{Abstract}
Your abstract here.
\\end{abstract}

\\tableofcontents
\\listoffigures
\\listoftables

\\chapter{Introduction}
\\label{chap:introduction}

\\section{Background}

\\section{Research Questions}

\\section{Thesis Structure}

\\chapter{Literature Review}

\\chapter{Methodology}

\\chapter{Results}

\\chapter{Discussion}

\\chapter{Conclusion}

\\appendix
\\chapter{Appendix}

\\bibliographystyle{apalike}
\\bibliography{references}

\\end{document}
"""
    )

    static let beamer = LaTeXTemplate(
        name: "Presentation",
        icon: "play.rectangle",
        description: "Beamer slides presentation",
        content: """
\\documentclass{beamer}
\\usepackage[utf8]{inputenc}
\\usepackage{amsmath}

\\usetheme{Madrid}
\\usecolortheme{default}

\\title{Presentation Title}
\\author{Author Name}
\\institute{Institution}
\\date{\\today}

\\begin{document}

\\begin{frame}
\\titlepage
\\end{frame}

\\begin{frame}{Outline}
\\tableofcontents
\\end{frame}

\\section{Introduction}

\\begin{frame}{Introduction}
\\begin{itemize}
    \\item First point
    \\item Second point
    \\item Third point
\\end{itemize}
\\end{frame}

\\section{Main Content}

\\begin{frame}{A Slide with Math}
\\begin{block}{Key Result}
    $\\displaystyle \\sum_{n=1}^{\\infty} \\frac{1}{n^2} = \\frac{\\pi^2}{6}$
\\end{block}
\\end{frame}

\\begin{frame}{Summary}
\\begin{itemize}
    \\item Conclusion one
    \\item Conclusion two
\\end{itemize}
\\end{frame}

\\end{document}
"""
    )

    static let letter = LaTeXTemplate(
        name: "Letter",
        icon: "envelope",
        description: "Formal correspondence letter",
        content: """
\\documentclass[12pt]{letter}
\\usepackage[utf8]{inputenc}

\\signature{Your Name}
\\address{Your Address \\\\ City, Country}

\\begin{document}

\\begin{letter}{Recipient Name \\\\ Recipient Address \\\\ City, Country}

\\opening{Dear Sir/Madam,}

Body of your letter goes here.

\\closing{Yours sincerely,}

\\end{letter}

\\end{document}
"""
    )

    static let minimal = LaTeXTemplate(
        name: "Minimal",
        icon: "minus.circle",
        description: "Blank canvas, minimal preamble",
        content: """
\\documentclass{article}

\\begin{document}

Hello, \\LaTeX!

\\end{document}
"""
    )

    static let all: [LaTeXTemplate] = [
        .article, .report, .thesis, .beamer, .letter, .minimal
    ]
}

// MARK: - Snippets

struct LaTeXSnippet: Identifiable {
    let id = UUID()
    let name: String
    let category: String
    let code: String
    let description: String
}

extension LaTeXSnippet {
    static let all: [LaTeXSnippet] = [
        // Text Formatting
        LaTeXSnippet(name: "Bold",          category: "Formatting", code: "\\textbf{text}",          description: "Bold text"),
        LaTeXSnippet(name: "Italic",        category: "Formatting", code: "\\textit{text}",          description: "Italic text"),
        LaTeXSnippet(name: "Emphasis",      category: "Formatting", code: "\\emph{text}",            description: "Emphasised text"),
        LaTeXSnippet(name: "Underline",     category: "Formatting", code: "\\underline{text}",       description: "Underlined text"),
        LaTeXSnippet(name: "Mono",          category: "Formatting", code: "\\texttt{text}",          description: "Monospace text"),
        LaTeXSnippet(name: "Small caps",    category: "Formatting", code: "\\textsc{text}",          description: "Small caps"),

        // Structure
        LaTeXSnippet(name: "Section",       category: "Structure",  code: "\\section{Title}",        description: "New section"),
        LaTeXSnippet(name: "Subsection",    category: "Structure",  code: "\\subsection{Title}",     description: "New subsection"),
        LaTeXSnippet(name: "Chapter",       category: "Structure",  code: "\\chapter{Title}",        description: "New chapter"),
        LaTeXSnippet(name: "Label",         category: "Structure",  code: "\\label{sec:name}",       description: "Add a label"),
        LaTeXSnippet(name: "Ref",           category: "Structure",  code: "\\ref{sec:name}",         description: "Reference a label"),
        LaTeXSnippet(name: "Cite",          category: "Structure",  code: "\\cite{key}",             description: "Bibliography citation"),

        // Math
        LaTeXSnippet(name: "Inline math",   category: "Math",       code: "$x = y$",                 description: "Inline math mode"),
        LaTeXSnippet(name: "Display math",  category: "Math",       code: "\\[\n    \n\\]",           description: "Display math"),
        LaTeXSnippet(name: "Equation",      category: "Math",       code: "\\begin{equation}\n    \n\\end{equation}", description: "Numbered equation"),
        LaTeXSnippet(name: "Align",         category: "Math",       code: "\\begin{align}\n    a &= b \\\\\n    c &= d\n\\end{align}", description: "Aligned equations"),
        LaTeXSnippet(name: "Fraction",      category: "Math",       code: "\\frac{numerator}{denominator}", description: "Fraction"),
        LaTeXSnippet(name: "Square root",   category: "Math",       code: "\\sqrt{x}",               description: "Square root"),
        LaTeXSnippet(name: "Sum",           category: "Math",       code: "\\sum_{i=1}^{n} x_i",    description: "Summation"),
        LaTeXSnippet(name: "Integral",      category: "Math",       code: "\\int_0^\\infty f(x)\\,dx", description: "Integral"),
        LaTeXSnippet(name: "Matrix",        category: "Math",       code: "\\begin{pmatrix}\n    a & b \\\\\n    c & d\n\\end{pmatrix}", description: "2×2 matrix"),

        // Environments
        LaTeXSnippet(name: "Itemize",       category: "Lists",      code: "\\begin{itemize}\n    \\item First item\n    \\item Second item\n\\end{itemize}", description: "Bullet list"),
        LaTeXSnippet(name: "Enumerate",     category: "Lists",      code: "\\begin{enumerate}\n    \\item First item\n    \\item Second item\n\\end{enumerate}", description: "Numbered list"),
        LaTeXSnippet(name: "Description",   category: "Lists",      code: "\\begin{description}\n    \\item[Term] Definition\n\\end{description}", description: "Description list"),

        // Figures
        LaTeXSnippet(name: "Figure",        category: "Figures",    code: "\\begin{figure}[htbp]\n    \\centering\n    \\includegraphics[width=0.8\\textwidth]{filename}\n    \\caption{Caption text}\n    \\label{fig:label}\n\\end{figure}", description: "Floating figure"),
        LaTeXSnippet(name: "Table",         category: "Figures",    code: "\\begin{table}[htbp]\n    \\centering\n    \\begin{tabular}{|c|c|c|}\n        \\hline\n        A & B & C \\\\\n        \\hline\n        1 & 2 & 3 \\\\\n        \\hline\n    \\end{tabular}\n    \\caption{Caption}\n    \\label{tab:label}\n\\end{table}", description: "Floating table"),

        // Packages
        LaTeXSnippet(name: "AMS Math",      category: "Packages",   code: "\\usepackage{amsmath,amssymb}", description: "AMS Math packages"),
        LaTeXSnippet(name: "Graphics",      category: "Packages",   code: "\\usepackage{graphicx}",  description: "Include graphics"),
        LaTeXSnippet(name: "Hyperref",      category: "Packages",   code: "\\usepackage{hyperref}",  description: "Hyperlinks in PDF"),
        LaTeXSnippet(name: "Geometry",      category: "Packages",   code: "\\usepackage[a4paper, margin=2.5cm]{geometry}", description: "Page geometry"),
        LaTeXSnippet(name: "TikZ",          category: "Packages",   code: "\\usepackage{tikz}",      description: "TikZ graphics"),
        LaTeXSnippet(name: "Listings",      category: "Packages",   code: "\\usepackage{listings}",  description: "Code listings"),

        // Beamer
        LaTeXSnippet(name: "Frame",         category: "Beamer",     code: "\\begin{frame}{Title}\n    \n\\end{frame}", description: "Beamer slide"),
        LaTeXSnippet(name: "Block",         category: "Beamer",     code: "\\begin{block}{Title}\n    \n\\end{block}", description: "Highlighted block"),
        LaTeXSnippet(name: "Columns",       category: "Beamer",     code: "\\begin{columns}\n    \\begin{column}{0.5\\textwidth}\n        Left\n    \\end{column}\n    \\begin{column}{0.5\\textwidth}\n        Right\n    \\end{column}\n\\end{columns}", description: "Two columns layout"),
    ]

    static var categories: [String] {
        var seen = Set<String>()
        return all.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
    }
}

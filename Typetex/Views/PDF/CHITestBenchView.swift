//
//  CHITestBenchView.swift
//  Typetex
//
//  ACM CHI–style two-column test bench — compiles a hardcoded paper through the
//  full TeXTypesetter → TeXPageView pipeline so output can be compared to Overleaf.
//

import SwiftUI

// MARK: - Sample ACM CHI LaTeX source

private let chiSampleSource = #"""
\documentclass[sigconf]{acmart}
\usepackage{amsmath}
\title{Understanding Natural Rendering: A Study on Native LaTeX Typesetting in iOS Applications}
\author{Jane A. Smith}
\affiliation{\institution{University of Typography}}
\author{Bob T. Jones}
\affiliation{\institution{Institute for Document Systems}}
\date{2025}

\begin{document}
\maketitle

\begin{abstract}
We present \textbf{Typetex}, a fully native Swift application that renders \LaTeX{} documents
using CoreText and CoreGraphics without any external dependencies. Our approach achieves
near-\TeX{} typographic quality including Knuth--Plass line breaking, full math layout, and
accurate two-column document geometry. A user study ($n = 32$) confirms that readers rate
native-rendered output at $4.2 \pm 0.3$ out of 5 for readability.
\end{abstract}

\section{Introduction}

Existing iOS and macOS LaTeX tools either rely on server-side compilation or bundle large
binary TeX distributions, making them unsuitable for App Store distribution. We propose
an alternative: a pure Swift rendering pipeline that covers the most common constructs
found in academic papers submitted to CHI, UIST, and related venues.

Our contributions are:
\begin{itemize}
  \item A CoreText-based paragraph typesetter with Knuth--Plass optimal line breaking.
  \item A full math layout engine supporting fractions, radicals, scripts, and operators.
  \item Two-column ACM \texttt{sigconf}-style geometry with proper gutter and margins.
  \item An open-source implementation suitable for App Store distribution.
\end{itemize}

\section{Related Work}

\subsection{Server-Side Compilation}
Tools such as Overleaf~\cite{overleaf2023} compile \LaTeX{} on remote servers.
While feature-complete, they require network connectivity and cannot function offline.

\subsection{Bundled TeX Distributions}
MiKTeX and MacTeX bundle the full Knuth TeX engine. Binary sizes exceed 500\,MB,
violating Apple's App Store size guidelines for on-demand content.

\subsection{Unicode Math Substitution}
Several apps substitute Unicode characters for math symbols. While compact,
this approach fails for complex expressions such as:
\[
  \int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}
\]
and multi-line aligned equations.

\section{System Design}

\subsection{Parsing}
The \texttt{LaTeXParser} converts raw \LaTeX{} source into a typed \texttt{[TexBlock]}
abstract syntax tree. Supported block types include paragraphs, section headings,
display math, code blocks, itemised and enumerated lists, tables, and figures.

\subsection{Math Layout}
The \texttt{MathRenderer} implements a subset of TeX math layout rules:

\begin{enumerate}
  \item Atom sizing by math style (display, text, script, scriptscript).
  \item Fraction construction: $\frac{a+b}{c-d}$ with proper rule thickness.
  \item Radical layout: $\sqrt[n]{x^2 + y^2}$ with surd glyph scaling.
  \item Large operators: $\sum_{i=0}^{n} x_i$ with display-mode limits.
\end{enumerate}

The axis height is set to $0.258\,f_s$ and rule thickness to $\max(0.055\,f_s,\,0.4\,\text{pt})$,
matching the values used in Computer Modern metrics.

\subsection{Line Breaking}
We implement the Knuth--Plass algorithm~\cite{knuth1981} with:

\[
  d(b_1, b_2) = w + t + r \cdot s
\]

where $w$ is the ideal line width, $t$ is the tolerance threshold, $r$ is the adjustment
ratio, and $s$ is the stretch/shrink of the glue at each breakpoint.

\subsection{Document Geometry}

Table~\ref{tab:geometry} shows the page geometry parameters used by Typetex for
the two supported document classes.

\begin{table}[h]
  \caption{Document geometry presets}
  \label{tab:geometry}
  \begin{tabular}{lrr}
    \hline
    Parameter & article & acmSigConf \\
    \hline
    Paper width (pt) & 612 & 612 \\
    Paper height (pt) & 792 & 792 \\
    Top margin (pt) & 72 & 57 \\
    Columns & 1 & 2 \\
    Column sep (pt) & — & 18 \\
    Body font & Palatino 11pt & Times 9pt \\
    \hline
  \end{tabular}
\end{table}

\section{Evaluation}

We recruited 32 participants from a university mailing list (16 F, 15 M, 1 NB;
ages 22--48, $\bar{x} = 29.4$). Each rated readability of three renderers on a
5-point Likert scale. Results (Table~\ref{tab:results}) show Typetex scoring
significantly above the Unicode-substitution baseline ($p < 0.001$, Wilcoxon).

\begin{table}[h]
  \caption{Mean readability scores (SD)}
  \label{tab:results}
  \begin{tabular}{lr}
    \hline
    Renderer & Score \\
    \hline
    Overleaf (ground truth) & $4.7 \pm 0.2$ \\
    Typetex (ours) & $4.2 \pm 0.3$ \\
    Unicode substitution & $2.9 \pm 0.7$ \\
    \hline
  \end{tabular}
\end{table}

\section{Conclusion}

We have demonstrated that high-quality LaTeX typesetting is achievable on Apple platforms
using only system frameworks. Typetex renders academic papers in real time, entirely offline,
and within App Store binary size limits. Future work will add BibTeX support and
equation numbering.

\end{document}
"""#

// MARK: - View

struct CHITestBenchView: View {

    @State private var typesetDocument: TypesetDocument = .empty
    @State private var isCompiling = false

    var body: some View {
        Group {
            if typesetDocument.pages.isEmpty {
                compilingOrEmptyView
            } else {
                pageScrollView
            }
        }
        .navigationTitle("ACM CHI Test Bench")
        .task { compile() }
    }

    // MARK: Private subviews

    private var compilingOrEmptyView: some View {
        VStack(spacing: 12) {
            if isCompiling {
                ProgressView("Typesetting…")
            } else {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("CHI Test Bench")
                    .font(.headline)
                Text("Compiles a sample ACM CHI paper through the full rendering pipeline.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("Render") { compile() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.78))
    }

    private var pageScrollView: some View {
        ScrollView {
            VStack(spacing: 28) {
                ForEach(typesetDocument.pages.indices, id: \.self) { i in
                    TeXPageView(
                        page: typesetDocument.pages[i],
                        geometry: typesetDocument.geometry,
                        fonts: typesetDocument.fonts
                    )
                    .shadow(color: .black.opacity(0.22), radius: 10, x: 3, y: -4)
                }
            }
            .padding(.vertical, 28)
        }
        .background(Color(white: 0.78))
    }

    // MARK: Compilation

    private func compile() {
        isCompiling = true
        Task.detached(priority: .userInitiated) {
            let blocks = LaTeXParser.parseDocument(chiSampleSource)
            let typesetter = TeXTypesetter()
            typesetter.geometry     = .acmSigConf
            typesetter.fonts        = .timesACM
            typesetter.documentClass = "acmart"
            let doc = typesetter.typeset(blocks)
            await MainActor.run {
                typesetDocument = doc
                isCompiling = false
            }
        }
    }
}

#Preview {
    NavigationStack {
        CHITestBenchView()
    }
}

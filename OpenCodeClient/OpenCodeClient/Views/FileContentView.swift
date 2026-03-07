//
//  FileContentView.swift
//  OpenCodeClient
//

import SwiftUI
import MarkdownUI
import UniformTypeIdentifiers

struct FileContentView: View {
    @Bindable var state: AppState
    let filePath: String
    @State private var content: String?
    @State private var imageData: Data?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var showPreview = true

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "tif", "heic", "heif", "ico"]

    private var isImage: Bool {
        let ext = filePath.lowercased().split(separator: ".").last.map(String.init) ?? ""
        return Self.imageExtensions.contains(ext)
    }

    private var isMarkdown: Bool {
        filePath.lowercased().hasSuffix(".md") || filePath.lowercased().hasSuffix(".markdown")
    }

    private var fileName: String {
        filePath.split(separator: "/").last.map(String.init) ?? filePath
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if let content {
            ToolbarItem(placement: .primaryAction) {
                if isMarkdown && showPreview {
                    ShareLink(
                        item: RichMarkdownContent(text: content),
                        preview: SharePreview(fileName)
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                } else {
                    ShareLink(item: content, subject: Text(fileName)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        if let imageData, let uiImage = UIImage(data: imageData) {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(
                    item: Image(uiImage: uiImage),
                    preview: SharePreview(fileName, image: Image(uiImage: uiImage))
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        if isMarkdown {
            ToolbarItem(placement: .primaryAction) {
                Button(showPreview ? "Markdown" : "Preview") {
                    showPreview.toggle()
                }
            }
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loadError {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(err))
            } else if let data = imageData, let uiImage = UIImage(data: data) {
                ImageView(uiImage: uiImage)
            } else if let text = content {
                contentView(text: text)
            } else {
                ContentUnavailableView("No content", systemImage: "doc.text")
            }
        }
        .navigationTitle(fileName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear {
            loadContent()
        }
        .refreshable {
            loadContent()
        }
    }

    @ViewBuilder
    private func contentView(text: String) -> some View {
        if isMarkdown {
            if showPreview {
                MarkdownPreviewView(text: text)
            } else {
                RawTextView(text: text, monospaced: true)
            }
        } else {
            CodeView(text: text, path: filePath)
        }
    }

    private func loadContent() {
        isLoading = true
        loadError = nil
        imageData = nil
        content = nil
        Task {
            do {
                let fc = try await state.loadFileContent(path: filePath)
                await MainActor.run {
                    if let text = fc.text {
                        content = text
                    } else if let base64 = fc.content, fc.type == "binary" {
                        if isImage {
                            if let data = Data(base64Encoded: base64) {
                                imageData = data
                            } else {
                                loadError = "Failed to decode image data"
                            }
                        } else {
                            loadError = "Binary file"
                        }
                    }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    loadError = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

/// Simple code view with line numbers
struct CodeView: View {
    let text: String
    let path: String

    private var lines: [String] {
        text.components(separatedBy: .newlines)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(i + 1)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                            Text(line)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)
                    }
                }
                .padding(.vertical, 8)
                .frame(minWidth: 400, alignment: .leading)
            }
        }
    }
}

/// Markdown preview using MarkdownUI library for full GFM rendering.
struct MarkdownPreviewView: View {
    let text: String

    var body: some View {
        ScrollView {
            Markdown(text)
                .textSelection(.enabled)
                .padding()
        }
    }
}

/// Raw text view for Markdown source (wraps to fill available width).
struct RawTextView: View {
    let text: String
    var monospaced: Bool = false

    var body: some View {
        ScrollView {
            Text(text)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
    }
}

/// Image view with zoom support
struct ImageView: View {
    let uiImage: UIImage
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let newScale = lastScale * value
                                    scale = min(max(newScale, 0.5), 5.0)
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                },
                            DragGesture()
                                .onChanged { value in
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                    )
                    .frame(
                        width: max(uiImage.size.width * scale, geometry.size.width),
                        height: max(uiImage.size.height * scale, geometry.size.height)
                    )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation { scale = 1.0; lastScale = 1.0; offset = .zero; lastOffset = .zero }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
            }
        }
    }
}

struct RichMarkdownContent: Transferable {
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .html) { item in
            Data(MarkdownHTMLConverter.convert(item.text).utf8)
        }
        DataRepresentation(exportedContentType: .plainText) { item in
            Data(item.text.utf8)
        }
    }
}

enum MarkdownHTMLConverter {

    static func convert(_ markdown: String) -> String {
        var html = Self.htmlPrefix
        let lines = markdown.components(separatedBy: "\n")
        var i = 0
        var inCode = false
        var para: [String] = []

        func flush() {
            guard !para.isEmpty else { return }
            html += "<p>\(Self.processInline(para.joined(separator: " ")))</p>\n"
            para = []
        }

        while i < lines.count {
            let raw = lines[i]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCode {
                    html += "</code></pre>\n"
                    inCode = false
                } else {
                    flush()
                    inCode = true
                    html += "<pre><code>"
                }
                i += 1; continue
            }
            if inCode {
                html += Self.escapeHTML(raw) + "\n"
                i += 1; continue
            }

            if trimmed.isEmpty { flush(); i += 1; continue }

            if let r = trimmed.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                flush()
                let level = trimmed[r].filter { $0 == "#" }.count
                let text = String(trimmed[r.upperBound...])
                html += "<h\(level)>\(Self.processInline(text))</h\(level)>\n"
                i += 1; continue
            }

            if Self.isHorizontalRule(trimmed) { flush(); html += "<hr>\n"; i += 1; continue }

            if trimmed.hasPrefix(">") {
                flush()
                var buf: [String] = []
                while i < lines.count {
                    let ql = lines[i].trimmingCharacters(in: .whitespaces)
                    guard ql.hasPrefix(">") else { break }
                    let content = ql.hasPrefix("> ") ? String(ql.dropFirst(2)) : String(ql.dropFirst(1))
                    buf.append(content)
                    i += 1
                }
                html += "<blockquote><p>\(Self.processInline(buf.joined(separator: " ")))</p></blockquote>\n"
                continue
            }

            if trimmed.range(of: #"^[-*+]\s+"#, options: .regularExpression) != nil {
                flush()
                html += "<ul>\n"
                while i < lines.count {
                    let ll = lines[i].trimmingCharacters(in: .whitespaces)
                    guard let r = ll.range(of: #"^[-*+]\s+"#, options: .regularExpression) else { break }
                    html += "<li>\(Self.processInline(String(ll[r.upperBound...])))</li>\n"
                    i += 1
                }
                html += "</ul>\n"
                continue
            }

            if trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil {
                flush()
                html += "<ol>\n"
                while i < lines.count {
                    let ll = lines[i].trimmingCharacters(in: .whitespaces)
                    guard let r = ll.range(of: #"^\d+\.\s+"#, options: .regularExpression) else { break }
                    html += "<li>\(Self.processInline(String(ll[r.upperBound...])))</li>\n"
                    i += 1
                }
                html += "</ol>\n"
                continue
            }

            para.append(trimmed)
            i += 1
        }

        flush()
        if inCode { html += "</code></pre>\n" }
        html += "</body></html>"
        return html
    }

    private static func processInline(_ text: String) -> String {
        var s = escapeHTML(text)
        s = s.replacingOccurrences(
            of: #"`([^`]+)`"#,
            with: "<code>$1</code>", options: .regularExpression)
        s = s.replacingOccurrences(
            of: #"!\[([^\]]*)\]\(([^)]+)\)"#,
            with: #"<img src="$2" alt="$1">"#, options: .regularExpression)
        s = s.replacingOccurrences(
            of: #"\[([^\]]+)\]\(([^)]+)\)"#,
            with: #"<a href="$2">$1</a>"#, options: .regularExpression)
        s = s.replacingOccurrences(
            of: #"\*\*\*(.+?)\*\*\*"#,
            with: "<strong><em>$1</em></strong>", options: .regularExpression)
        s = s.replacingOccurrences(
            of: #"\*\*(.+?)\*\*"#,
            with: "<strong>$1</strong>", options: .regularExpression)
        s = s.replacingOccurrences(
            of: #"\*(.+?)\*"#,
            with: "<em>$1</em>", options: .regularExpression)
        s = s.replacingOccurrences(
            of: #"~~(.+?)~~"#,
            with: "<del>$1</del>", options: .regularExpression)
        return s
    }

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let s = line.replacingOccurrences(of: " ", with: "")
        return s.count >= 3
            && (s.allSatisfy { $0 == "-" }
                || s.allSatisfy { $0 == "*" }
                || s.allSatisfy { $0 == "_" })
    }

    private static let htmlPrefix =
        "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><style>" +
        "body{font-family:-apple-system,system-ui,sans-serif;line-height:1.6;color:#24292f;}" +
        "h1,h2,h3,h4,h5,h6{margin-top:24px;margin-bottom:16px;font-weight:600;}" +
        "h1{font-size:2em;padding-bottom:.3em;border-bottom:1px solid #d0d7de;}" +
        "h2{font-size:1.5em;padding-bottom:.3em;border-bottom:1px solid #d0d7de;}" +
        "h3{font-size:1.25em;}" +
        "code{background:rgba(175,184,193,0.2);padding:.2em .4em;border-radius:6px;" +
        "font-size:85%;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;}" +
        "pre{padding:16px;overflow:auto;font-size:85%;line-height:1.45;background:#f6f8fa;border-radius:6px;}" +
        "pre code{background:none;padding:0;font-size:100%;}" +
        "blockquote{padding:0 1em;color:#656d76;border-left:.25em solid #d0d7de;margin:0 0 16px;}" +
        "hr{border:0;border-top:1px solid #d0d7de;margin:24px 0;}" +
        "a{color:#0969da;text-decoration:none;}" +
        "img{max-width:100%;}" +
        "li{margin-top:.25em;}" +
        "</style></head><body>\n"
}

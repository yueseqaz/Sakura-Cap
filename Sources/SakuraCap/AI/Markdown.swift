import AppKit

/// 轻量 Markdown → NSAttributedString 渲染器（无第三方依赖）。
/// 块级：标题 / 代码块 / 引用 / 列表 / 表格 / 分隔线 / 段落；
/// 行内：`code`、**粗体**、*斜体*、[链接](url)。渲染结果供聊天气泡使用。
enum Markdown {
    enum TableAlignment {
        case leading
        case center
        case trailing
    }

    struct Table {
        let header: [NSAttributedString]
        let rows: [[NSAttributedString]]
        let alignments: [TableAlignment]

        var columnCount: Int { alignments.count }
    }

    enum Block {
        case text(NSAttributedString)
        case table(Table)
    }

    /// Splits a document into regular Markdown text and GitHub-style table blocks.
    /// Tables inside fenced code blocks intentionally remain code, just like other
    /// fenced content.
    static func blocks(_ markdown: String, baseSize: CGFloat = 14) -> [Block] {
        let lines = markdown.components(separatedBy: "\n")
        var blocks: [Block] = []
        var textLines: [String] = []
        var inCode = false
        var index = 0

        func flushText() {
            guard !textLines.isEmpty else { return }
            blocks.append(.text(attributed(textLines.joined(separator: "\n"), baseSize: baseSize)))
            textLines = []
        }

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if !inCode, let parsed = parseTable(lines, startingAt: index, baseSize: baseSize) {
                flushText()
                blocks.append(.table(parsed.table))
                index = parsed.nextIndex
                continue
            }

            textLines.append(lines[index])
            if line.hasPrefix("```") {
                inCode.toggle()
            }
            index += 1
        }
        flushText()
        return blocks
    }

    static func attributed(_ markdown: String, baseSize: CGFloat = 14) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let baseFont = NSFont.systemFont(ofSize: baseSize)
        let baseColor = NSColor.labelColor
        let lineSpacing: CGFloat = 4

        var paragraph: [String] = []
        var inCode = false
        var codeLines: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            let attributed = inline(paragraph.joined(separator: "\n"), font: baseFont, color: baseColor)
            attributed.addAttribute(.paragraphStyle, value: paragraphStyle(lineSpacing),
                                    range: NSRange(location: 0, length: attributed.length))
            output.append(attributed)
            output.append(spacer(baseFont, lineSpacing))
            paragraph = []
        }

        func flushCode() {
            guard !codeLines.isEmpty else { return }
            let code = NSMutableAttributedString(string: codeLines.joined(separator: "\n") + "\n", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: baseSize - 1, weight: .regular),
                .foregroundColor: baseColor,
                .backgroundColor: NSColor.systemGray.withAlphaComponent(0.14),
            ])
            let style = paragraphStyle(1)
            style.firstLineHeadIndent = 8
            style.headIndent = 8
            style.tailIndent = -8
            code.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: code.length))
            output.append(code)
            output.append(spacer(baseFont, lineSpacing))
            codeLines = []
        }

        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if inCode {
                if line.hasPrefix("```") {
                    flushCode()
                    inCode = false
                } else {
                    codeLines.append(rawLine)
                }
                continue
            }
            if line.hasPrefix("```") {
                flushParagraph()
                inCode = true
                continue
            }
            if line.isEmpty {
                flushParagraph()
                continue
            }
            if let level = headingLevel(line) {
                flushParagraph()
                let text = line.drop { $0 == "#" || $0 == " " }
                output.append(NSAttributedString(string: String(text) + "\n", attributes: [
                    .font: NSFont.systemFont(ofSize: baseSize + CGFloat(max(1, 7 - level)) - 2, weight: .semibold),
                    .foregroundColor: baseColor,
                ]))
                output.append(spacer(baseFont, lineSpacing / 2))
                continue
            }
            if line == "---" || line == "***" {
                flushParagraph()
                output.append(NSAttributedString(string: "\n", attributes: [.font: baseFont]))
                continue
            }
            if line.hasPrefix(">") {
                flushParagraph()
                let text = line.dropFirst().trimmingCharacters(in: .whitespaces)
                let attributed = inline(text, font: baseFont, color: NSColor.secondaryLabelColor)
                let style = paragraphStyle(lineSpacing)
                style.firstLineHeadIndent = 12
                style.headIndent = 12
                attributed.addAttribute(.paragraphStyle, value: style,
                                        range: NSRange(location: 0, length: attributed.length))
                output.append(attributed)
                output.append(spacer(baseFont, lineSpacing))
                continue
            }
            if let item = listItem(rawLine) {
                flushParagraph()
                // Keep the marker as part of the attributed paragraph so wrapped
                // lines can use a hanging indent instead of looking like a new item.
                let prefix = String(repeating: "  ", count: item.level)
                let marker = prefix + (item.ordered ? "\(item.marker)  " : (item.level == 0 ? "•  " : "◦  "))
                let attributed = NSMutableAttributedString(string: marker, attributes: [
                    .font: baseFont, .foregroundColor: baseColor,
                ])
                attributed.append(inline(item.body + "\n", font: baseFont, color: baseColor))
                let style = paragraphStyle(lineSpacing)
                let indent = CGFloat(item.level) * 14 + 4
                style.firstLineHeadIndent = indent
                let markerIndent = item.ordered ? max(24, CGFloat(item.marker.count + 2) * 8) : 14
                style.headIndent = indent + markerIndent
                style.paragraphSpacing = 4
                attributed.addAttribute(.paragraphStyle, value: style,
                                        range: NSRange(location: 0, length: attributed.length))
                output.append(attributed)
                continue
            }
            paragraph.append(line)
        }
        flushParagraph()
        flushCode()

        if output.length == 0 {
            return NSAttributedString(string: markdown, attributes: [.font: baseFont, .foregroundColor: baseColor])
        }
        return output
    }

    // MARK: - 行内解析（正则一次找出 code/bold/italic/link）

    private static let inlineRegex: NSRegularExpression = {
        // 依次：`code` | **bold** | *italic* | [text](url)
        let pattern = "(`([^`]+)`)|(\\*\\*([^*]+)\\*\\*)|(\\*([^*\\n]+)\\*)|(\\[([^\\]]+)\\]\\(([^)]+)\\))"
        return try! NSRegularExpression(pattern: pattern)
    }()

    static func inline(_ text: String, font: NSFont, color: NSColor) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color,
        ])
        let range = NSRange(text.startIndex..., in: text)
        // 从后往前替换，避免偏移失效
        let matches = inlineRegex.matches(in: text, range: range).reversed()
        for match in matches {
            let attributed: NSAttributedString
            let target: NSRange
            let mono = NSFont.monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular)
            let bold = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            let italic = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            if match.range(at: 2).location != NSNotFound {
                target = match.range(at: 1)
                attributed = NSAttributedString(string: (text as NSString).substring(with: match.range(at: 2)), attributes: [
                    .font: mono, .foregroundColor: NSColor.labelColor,
                    .backgroundColor: NSColor.systemGray.withAlphaComponent(0.14),
                ])
            } else if match.range(at: 4).location != NSNotFound {
                target = match.range(at: 3)
                attributed = NSAttributedString(string: (text as NSString).substring(with: match.range(at: 4)), attributes: [
                    .font: bold, .foregroundColor: color,
                ])
            } else if match.range(at: 6).location != NSNotFound {
                target = match.range(at: 5)
                attributed = NSAttributedString(string: (text as NSString).substring(with: match.range(at: 6)), attributes: [
                    .font: italic, .foregroundColor: color,
                ])
            } else if match.range(at: 8).location != NSNotFound, let url = URL(string: (text as NSString).substring(with: match.range(at: 9))) {
                target = match.range(at: 7)
                attributed = NSAttributedString(string: (text as NSString).substring(with: match.range(at: 8)), attributes: [
                    .font: font, .foregroundColor: NSColor.linkColor, .link: url,
                ])
            } else {
                continue
            }
            result.replaceCharacters(in: target, with: attributed)
        }
        return result
    }

    // MARK: - 辅助

    private static func paragraphStyle(_ lineSpacing: CGFloat) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        return style
    }

    private static func spacer(_ font: NSFont, _ spacing: CGFloat) -> NSAttributedString {
        NSAttributedString(string: "\n", attributes: [.font: font, .paragraphStyle: paragraphStyle(spacing)])
    }

    private static func headingLevel(_ line: String) -> Int? {
        var count = 0
        for ch in line {
            if ch == "#" { count += 1 } else { break }
        }
        guard count >= 1, count <= 6 else { return nil }
        let rest = line.dropFirst(count)
        guard rest.hasPrefix(" ") || rest.isEmpty else { return nil }
        return count
    }

    private static func parseTable(_ lines: [String], startingAt start: Int,
                                   baseSize: CGFloat) -> (table: Table, nextIndex: Int)? {
        guard start + 1 < lines.count,
              let header = tableCells(in: lines[start]),
              let separator = tableCells(in: lines[start + 1]),
              header.count >= 2,
              separator.count == header.count else { return nil }

        let alignments = separator.compactMap(tableAlignment)
        guard alignments.count == separator.count else { return nil }

        let font = NSFont.systemFont(ofSize: baseSize)
        let color = NSColor.labelColor
        var rows: [[NSAttributedString]] = []
        var next = start + 2
        while next < lines.count, let cells = tableCells(in: lines[next]) {
            rows.append(cells.prefix(header.count).map { inline($0, font: font, color: color) }
                + Array(repeating: NSAttributedString(string: "", attributes: [
                    .font: font, .foregroundColor: color,
                ]), count: max(0, header.count - cells.count)))
            next += 1
        }

        let renderedHeader = header.map { inline($0, font: font, color: color) }
        return (Table(header: renderedHeader, rows: rows, alignments: alignments), next)
    }

    /// Splits a pipe-delimited row while preserving escaped pipes inside a cell.
    private static func tableCells(in rawLine: String) -> [String]? {
        var line = rawLine.trimmingCharacters(in: .whitespaces)
        guard line.contains("|") else { return nil }
        if line.first == "|" { line.removeFirst() }
        if line.last == "|" { line.removeLast() }

        var cells: [String] = []
        var current = ""
        var escaped = false
        for character in line {
            if character == "|" && !escaped {
                cells.append(current.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "\\|", with: "|"))
                current = ""
            } else {
                current.append(character)
            }
            escaped = character == "\\" && !escaped
        }
        cells.append(current.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\\|", with: "|"))
        return cells.isEmpty ? nil : cells
    }

    private static func tableAlignment(_ cell: String) -> TableAlignment? {
        let value = cell.trimmingCharacters(in: .whitespaces)
        guard value.count >= 3 else { return nil }
        let leading = value.first == ":"
        let trailing = value.last == ":"
        let start = value.index(value.startIndex, offsetBy: leading ? 1 : 0)
        let end = value.index(value.endIndex, offsetBy: trailing ? -1 : 0)
        guard start < end, value[start..<end].allSatisfy({ $0 == "-" }) else { return nil }
        if leading && trailing { return .center }
        if trailing { return .trailing }
        return .leading
    }

    private struct ListItem {
        let level: Int
        let ordered: Bool
        let marker: String
        let body: String
    }

    /// Parses the common Markdown list forms while retaining indentation for nested items.
    private static func listItem(_ rawLine: String) -> ListItem? {
        var leading = 0
        var index = rawLine.startIndex
        while index < rawLine.endIndex {
            switch rawLine[index] {
            case " ": leading += 1
            case "\t": leading += 4
            default: break
            }
            guard rawLine[index] == " " || rawLine[index] == "\t" else { break }
            index = rawLine.index(after: index)
        }

        let content = String(rawLine[index...])
        guard !content.isEmpty else { return nil }
        let characters = Array(content)
        if let first = characters.first, ["-", "*", "+", "•", "◦"].contains(first),
           characters.dropFirst().first.map({ $0 == " " || $0 == "\t" }) == true {
            let body = String(content.dropFirst()).trimmingCharacters(in: .whitespaces)
            return ListItem(level: min(leading / 2, 8), ordered: false, marker: "", body: body)
        }

        var digits = 0
        while digits < characters.count, characters[digits].isNumber { digits += 1 }
        guard digits > 0, digits + 1 < characters.count,
              characters[digits] == "." || characters[digits] == ")",
              characters[digits + 1] == " " || characters[digits + 1] == "\t" else { return nil }
        let marker = String(characters[..<digits]) + String(characters[digits])
        let bodyStart = content.index(content.startIndex, offsetBy: digits + 1)
        let body = String(content[bodyStart...]).trimmingCharacters(in: .whitespaces)
        return ListItem(level: min(leading / 2, 8), ordered: true, marker: marker, body: body)
    }

    /// 估算渲染高度（气泡布局用）
    static func height(of attributed: NSAttributedString, width: CGFloat) -> CGFloat {
        let bounds = attributed.boundingRect(
            with: CGSize(width: max(40, width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return ceil(bounds.height)
    }
}

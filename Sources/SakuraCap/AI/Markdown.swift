import AppKit

/// 轻量 Markdown → NSAttributedString 渲染器（无第三方依赖）。
/// 块级：标题 / 代码块 / 引用 / 列表 / 分隔线 / 段落；
/// 行内：`code`、**粗体**、*斜体*、[链接](url)。渲染结果供聊天气泡使用。
enum Markdown {
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
            if isListLine(line) {
                flushParagraph()
                let leadingSpaces = rawLine.prefix { $0 == " " || $0 == "\t" }
                    .reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
                let indent = CGFloat(min(leadingSpaces / 2, 8)) * 14 + 4
                let attributed = inline(line + "\n", font: baseFont, color: baseColor)
                let style = paragraphStyle(lineSpacing)
                style.firstLineHeadIndent = indent
                style.headIndent = indent + 14
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

    private static func isListLine(_ line: String) -> Bool {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("  - ") || line.hasPrefix("  * ") { return true }
        return line.range(of: "^\\s{0,2}\\d{1,3}\\. ", options: .regularExpression) != nil
    }

    /// 估算渲染高度（气泡布局用）
    static func height(of attributed: NSAttributedString, width: CGFloat) -> CGFloat {
        let bounds = attributed.boundingRect(
            with: CGSize(width: max(40, width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return ceil(bounds.height)
    }
}

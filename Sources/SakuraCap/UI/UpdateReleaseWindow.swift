import AppKit

@MainActor
final class UpdateReleaseWindow: NSWindowController {
    private static var current: UpdateReleaseWindow?
    private var pageURL: URL?
    private var onInstall: () -> Void

    static func show(version: String, notes: String, isNewer: Bool, pageURL: URL?,
                     activate: Bool = true, onInstall: @escaping () -> Void) {
        // 复用已有窗口时必须原地刷新内容——否则再次检查更新只会把
        // 上一次的旧版本信息原样顶到前面（窗口没关时尤为明显）
        if let current {
            current.pageURL = pageURL
            current.onInstall = onInstall
            current.buildPage(version: version, notes: notes, isNewer: isNewer)
            current.present(activate: activate)
            return
        }
        let controller = UpdateReleaseWindow(version: version, notes: notes, isNewer: isNewer,
                                             pageURL: pageURL, onInstall: onInstall)
        current = controller
        controller.window?.center()
        controller.present(activate: activate)
    }

    private func present(activate: Bool) {
        if activate {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        } else {
            window?.orderFront(nil)
        }
    }

    private init(version: String, notes: String, isNewer: Bool, pageURL: URL?, onInstall: @escaping () -> Void) {
        self.pageURL = pageURL
        self.onInstall = onInstall
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 540),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = L("Sakura-Cap 更新")
        WindowPresentation.configure(window)
        super.init(window: window)
        buildPage(version: version, notes: notes, isNewer: isNewer)
    }

    required init?(coder: NSCoder) { nil }

    private func buildPage(version: String, notes: String, isNewer: Bool) {
        let canvas = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 620, height: 540))
        canvas.material = .windowBackground
        canvas.state = .active
        window?.contentView = canvas

        let icon = NSImageView(frame: NSRect(x: 32, y: 418, width: 64, height: 64))
        icon.image = NSApp.applicationIconImage
        canvas.addSubview(icon)
        addLabel(isNewer ? L("发现新版本") : L("已是最新版本"),
                 frame: NSRect(x: 114, y: 464, width: 460, height: 19),
                 font: .systemFont(ofSize: 12, weight: .semibold), color: .secondaryLabelColor, to: canvas)
        addLabel("Sakura-Cap \(version)", frame: NSRect(x: 112, y: 425, width: 470, height: 40),
                 font: .systemFont(ofSize: 28, weight: .bold), color: .labelColor, to: canvas)
        addLabel(isNewer ? String(format: L("当前版本 v%@，已发布新版本。"), AppInfo.version)
                         : L("看看这个版本有哪些变化。"),
                 frame: NSRect(x: 114, y: 405, width: 470, height: 20),
                 font: .systemFont(ofSize: 13), color: .secondaryLabelColor, to: canvas)
        addLabel(L("版本更新内容"), frame: NSRect(x: 32, y: 359, width: 160, height: 24),
                 font: .systemFont(ofSize: 16, weight: .semibold), color: .labelColor, to: canvas)
        addSeparator(y: 350, to: canvas)

        let scroll = NSScrollView(frame: NSRect(x: 32, y: 79, width: 556, height: 258))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 542, height: 258))
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.isHorizontallyResizable = false
        text.isVerticallyResizable = true
        text.textContainer?.widthTracksTextView = true
        text.textContainerInset = NSSize(width: 0, height: 8)
        text.textStorage?.setAttributedString(Self.renderNotes(notes))
        scroll.documentView = text
        canvas.addSubview(scroll)

        addSeparator(y: 64, to: canvas)
        if pageURL != nil {
            let link = NSButton(title: L("查看发布页"), target: self, action: #selector(openRelease))
            link.bezelStyle = .inline
            link.contentTintColor = .controlAccentColor
            link.frame = NSRect(x: 28, y: 20, width: 118, height: 28)
            canvas.addSubview(link)
        }
        let close = NSButton(title: isNewer ? L("稍后") : L("完成"), target: self, action: #selector(hide))
        close.bezelStyle = .rounded
        close.frame = NSRect(x: isNewer ? 390 : 510, y: 18, width: 78, height: 30)
        canvas.addSubview(close)
        if isNewer {
            let install = NSButton(title: L("下载并安装"), target: self, action: #selector(installUpdate))
            install.bezelStyle = .rounded
            install.keyEquivalent = "\r"
            install.frame = NSRect(x: 474, y: 18, width: 114, height: 30)
            canvas.addSubview(install)
        }
    }

    private func addLabel(_ value: String, frame: NSRect, font: NSFont, color: NSColor, to view: NSView) {
        let label = NSTextField(labelWithString: value)
        label.frame = frame
        label.font = font
        label.textColor = color
        view.addSubview(label)
    }

    private func addSeparator(y: CGFloat, to view: NSView) {
        let line = NSBox(frame: NSRect(x: 32, y: y, width: 556, height: 1))
        line.boxType = .separator
        view.addSubview(line)
    }

    private static func renderNotes(_ markdown: String) -> NSAttributedString {
        let output = NSMutableAttributedString(string: "")
        var inCode = false
        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { inCode.toggle(); continue }
            if trimmed.isEmpty { continue }
            let heading = trimmed.prefix(while: { $0 == "#" }).count
            let isHeading = !inCode && (1...6).contains(heading) && trimmed.dropFirst(heading).hasPrefix(" ")
            if output.length == 0, isHeading { continue }
            let bullet = !inCode && (trimmed.hasPrefix("- ") || trimmed.hasPrefix("* "))
            let quote = !inCode && trimmed.hasPrefix("> ")
            let content = isHeading ? String(trimmed.dropFirst(heading + 1))
                        : bullet || quote ? String(trimmed.dropFirst(2)) : trimmed
            let prefix = bullet ? "•  " : quote ? "▏  " : ""
            let font: NSFont = inCode ? .monospacedSystemFont(ofSize: 12, weight: .regular)
                : isHeading ? .systemFont(ofSize: heading <= 2 ? 17 : 15, weight: .semibold)
                : .systemFont(ofSize: 13)
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 4
            style.paragraphSpacing = isHeading ? 13 : 9
            if bullet { style.headIndent = 22 }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: isHeading ? NSColor.labelColor : NSColor.secondaryLabelColor,
                .paragraphStyle: style
            ]
            let rendered = NSMutableAttributedString(string: prefix, attributes: attributes)
            if let inline = try? AttributedString(markdown: content,
                                                  options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                let decorated = NSMutableAttributedString(attributedString: NSAttributedString(inline))
                decorated.addAttributes(attributes, range: NSRange(location: 0, length: decorated.length))
                var fontRuns: [(NSRange, NSFont)] = []
                decorated.enumerateAttribute(NSAttributedString.Key("NSInlinePresentationIntent"),
                                             in: NSRange(location: 0, length: decorated.length)) { value, range, _ in
                    let intent = (value as? NSNumber)?.intValue ?? 0
                    if intent & 2 != 0 {
                        fontRuns.append((range, .systemFont(ofSize: font.pointSize, weight: .semibold)))
                    } else if intent & 4 != 0 {
                        fontRuns.append((range, .monospacedSystemFont(ofSize: font.pointSize, weight: .regular)))
                    } else if intent & 1 != 0 {
                        fontRuns.append((range, NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)))
                    }
                }
                for (range, font) in fontRuns { decorated.addAttribute(.font, value: font, range: range) }
                rendered.append(decorated)
            } else {
                rendered.append(NSAttributedString(string: content, attributes: attributes))
            }
            rendered.append(NSAttributedString(string: "\n", attributes: attributes))
            output.append(rendered)
        }
        if output.length == 0 {
            output.append(NSAttributedString(string: L("暂时无法获取更新说明，可在发布页查看。"),
                                             attributes: [.font: NSFont.systemFont(ofSize: 13),
                                                          .foregroundColor: NSColor.secondaryLabelColor]))
        }
        return output
    }

    @objc private func hide() { window?.orderOut(nil) }
    @objc private func openRelease() { if let pageURL { NSWorkspace.shared.open(pageURL) } }
    @objc private func installUpdate() { window?.orderOut(nil); onInstall() }
}

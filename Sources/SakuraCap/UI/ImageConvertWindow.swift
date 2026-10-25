import AppKit
import ImageIO
import UniformTypeIdentifiers

/// 图片格式转换：批量把图片转成 PNG / JPEG / HEIC，
/// 可调压缩质量（JPEG/HEIC）、可限制长边；输出保存在原文件旁边，绝不覆盖。
@MainActor
final class ImageConvertToolController: NSObject {
    static let shared = ImageConvertToolController()

    private var window: NSWindow?
    private var items: [ConvertItem] = []
    private var converting = false

    private enum OutputFormat: Int, CaseIterable {
        case png = 0, jpeg, heic

        var title: String {
            switch self {
            case .png: return "PNG"
            case .jpeg: return "JPEG"
            case .heic: return "HEIC"
            }
        }
        var utType: UTType {
            switch self {
            case .png: return .png
            case .jpeg: return .jpeg
            case .heic: return .heic
            }
        }
        var pathExtension: String {
            switch self {
            case .png: return "png"
            case .jpeg: return "jpg"
            case .heic: return "heic"
            }
        }
        var supportsQuality: Bool { self != .png }
    }

    private var format: OutputFormat = .jpeg
    private var quality = 0.9
    private var longEdgeLimit: Int = 0 // 0 = 不限制

    private var tableView: NSTableView!
    private var hintLabel: NSTextField!
    private var qualitySlider: NSSlider!
    private var qualityLabel: NSTextField!
    private var qualityTitleLabel: NSTextField!
    private var convertButton: NSButton!
    private var formatPopup: NSPopUpButton!
    private var longEdgePopup: NSPopUpButton!

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = L("图片格式转换")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 560, height: 400)
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.sharingType = .readOnly

        // 列表
        tableView = NSTableView()
        let nameColumn = NSTableColumn(identifier: .init("name"))
        nameColumn.title = L("文件")
        nameColumn.width = 380
        let sizeColumn = NSTableColumn(identifier: .init("size"))
        sizeColumn.title = L("尺寸")
        sizeColumn.width = 120
        let bytesColumn = NSTableColumn(identifier: .init("bytes"))
        bytesColumn.title = L("大小")
        bytesColumn.width = 100
        for column in [nameColumn, sizeColumn, bytesColumn] {
            tableView.addTableColumn(column)
        }
        tableView.rowHeight = 26
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.style = .inset
        tableView.dataSource = self
        tableView.delegate = self

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .windowBackgroundColor

        let dropArea = ImageConvertDropView(frame: .zero)
        dropArea.onDrop = { [weak self] urls in self?.add(urls: urls) }
        dropArea.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        dropArea.addSubview(scroll)

        // 顶栏
        let addButton = NSButton(title: L("添加图片…"), target: self, action: #selector(addTapped))
        addButton.bezelStyle = .rounded
        let removeButton = NSButton(title: L("移除所选"), target: self, action: #selector(removeSelectedTapped))
        removeButton.bezelStyle = .rounded

        formatPopup = NSPopUpButton()
        for item in OutputFormat.allCases { formatPopup.addItem(withTitle: item.title) }
        formatPopup.selectItem(at: OutputFormat.jpeg.rawValue)
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged)
        let formatLabel = NSTextField(labelWithString: L("输出格式"))

        qualitySlider = NSSlider(value: 0.9, minValue: 0.1, maxValue: 1.0, target: self, action: #selector(qualityChanged))
        qualitySlider.controlSize = .small
        qualityLabel = NSTextField(labelWithString: "90%")
        qualityLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        qualityTitleLabel = NSTextField(labelWithString: L("质量"))

        longEdgePopup = NSPopUpButton()
        for (title, value) in [(L("不限制"), 0), ("4096 px", 4096), ("2560 px", 2560), ("1920 px", 1920), ("1280 px", 1280)] {
            longEdgePopup.addItem(withTitle: title)
            longEdgePopup.lastItem?.representedObject = value
        }
        longEdgePopup.target = self
        longEdgePopup.action = #selector(longEdgeChanged)
        let longEdgeLabel = NSTextField(labelWithString: L("长边限制"))

        hintLabel = NSTextField(labelWithString: L("拖入图片到这里，或点击「添加图片」"))
        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.lineBreakMode = .byTruncatingTail
        hintLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        convertButton = NSButton(title: L("转换"), target: self, action: #selector(convertTapped))
        convertButton.bezelStyle = .rounded
        convertButton.keyEquivalent = "\r"
        convertButton.contentTintColor = .controlAccentColor

        let bar = NSVisualEffectView()
        bar.material = .windowBackground
        bar.blendingMode = .withinWindow
        let stack = NSStackView(views: [addButton, removeButton,
                                        formatLabel, formatPopup,
                                        qualityTitleLabel, qualitySlider, qualityLabel,
                                        longEdgeLabel, longEdgePopup,
                                        hintLabel, convertButton])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)

        let footnote = NSTextField(labelWithString: L("转换后的图片保存在原文件旁边，不会覆盖已有文件"))
        footnote.font = .systemFont(ofSize: 11)
        footnote.textColor = .secondaryLabelColor
        footnote.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(dropArea)
        container.addSubview(bar)
        container.addSubview(footnote)
        NSLayoutConstraint.activate([
            dropArea.topAnchor.constraint(equalTo: container.topAnchor),
            dropArea.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            dropArea.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            dropArea.bottomAnchor.constraint(equalTo: bar.topAnchor),
            scroll.topAnchor.constraint(equalTo: dropArea.topAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: dropArea.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: dropArea.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: dropArea.bottomAnchor, constant: -8),
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: footnote.topAnchor),
            bar.heightAnchor.constraint(equalToConstant: 48),
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            qualitySlider.widthAnchor.constraint(equalToConstant: 90),
            formatPopup.widthAnchor.constraint(equalToConstant: 92),
            longEdgePopup.widthAnchor.constraint(equalToConstant: 100),
            footnote.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            footnote.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
            footnote.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        ])
        window.contentView = container
        self.window = window
        refreshUI()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - 数据

    private func add(urls: [URL]) {
        let imageUrls = urls.filter { $0.isFileURL && (UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) ?? false) }
        guard !imageUrls.isEmpty else { return }
        for url in imageUrls where !items.contains(where: { $0.url == url }) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = props[kCGImagePropertyPixelWidth] as? Int,
                  let height = props[kCGImagePropertyPixelHeight] as? Int else { continue }
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let bytes = (attrs?[.size] as? Int) ?? 0
            items.append(ConvertItem(url: url, pixelWidth: width, pixelHeight: height, fileSize: bytes))
        }
        refreshUI()
    }

    private func refreshUI() {
        tableView?.reloadData()
        let isJPEGLike = format.supportsQuality
        setQualityVisible(isJPEGLike)
        qualitySlider.isEnabled = isJPEGLike
        convertButton.isEnabled = !items.isEmpty && !converting
        if !converting {
            hintLabel.stringValue = items.isEmpty
                ? L("拖入图片到这里，或点击「添加图片」")
                : String(format: L("已添加 %d 张，输出格式 %@"), items.count, format.title)
        }
    }

    private func setQualityVisible(_ visible: Bool) {
        // PNG 无损，隐藏质量控件
        qualityTitleLabel.isHidden = !visible
        qualitySlider.isHidden = !visible
        qualityLabel.isHidden = !visible
    }

    // MARK: - 转换

    @objc private func convertTapped() {
        guard !converting else { return }
        guard !items.isEmpty else {
            Toast.show(title: L("没有可转换的图片"), detail: nil)
            return
        }
        converting = true
        convertButton.isEnabled = false
        Task { await runConversion() }
    }

    private func runConversion() async {
        let total = items.count
        var outputs: [URL] = []
        var failures = 0
        for (index, item) in items.enumerated() {
            await MainActor.run {
                hintLabel.stringValue = String(format: L("转换中 %d / %d…"), index + 1, total)
            }
            do {
                let output = try await convertOne(item)
                outputs.append(output)
            } catch {
                failures += 1
                Log.app.error("图片转换失败 \(item.url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        await MainActor.run {
            converting = false
            refreshUI()
            if failures > 0 {
                Toast.show(title: String(format: L("已转换 %d 张，失败 %d 张"), outputs.count, failures), detail: nil)
            } else {
                Toast.show(title: String(format: L("已转换 %d 张图片"), outputs.count), detail: nil)
            }
            if !outputs.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(outputs)
            }
        }
    }

    private func convertOne(_ item: ConvertItem) async throws -> URL {
        let source = try require(CGImageSourceCreateWithURL(item.url as CFURL, nil),
                                 message: L("无法读取图片"))
        let cg = try require(CGImageSourceCreateImageAtIndex(source, 0, nil),
                             message: L("无法读取图片"))
        // 长边限制：等比缩小（只缩不放大）
        var image = cg
        if longEdgeLimit > 0, max(cg.width, cg.height) > longEdgeLimit {
            let scale = CGFloat(longEdgeLimit) / CGFloat(max(cg.width, cg.height))
            let newSize = CGSize(width: (CGFloat(cg.width) * scale).rounded(),
                                 height: (CGFloat(cg.height) * scale).rounded())
            guard let ctx = CGContext(data: nil, width: Int(newSize.width), height: Int(newSize.height),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw ConvertError.write
            }
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(origin: .zero, size: newSize))
            guard let scaled = ctx.makeImage() else { throw ConvertError.write }
            image = scaled
        }
        // JPEG 不支持透明：铺白底
        if format == .jpeg, hasAlpha(image) {
            guard let white = CGContext(data: nil, width: image.width, height: image.height,
                                        bitsPerComponent: 8, bytesPerRow: 0,
                                        space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw ConvertError.write
            }
            NSColor.white.setFill()
            white.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            white.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard let flattened = white.makeImage() else { throw ConvertError.write }
            image = flattened
        }

        let output = uniqueOutputURL(for: item.url)
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL,
                                                                format.utType.identifier as CFString, 1, nil) else {
            throw ConvertError.unsupported
        }
        var properties: [CFString: Any] = [:]
        if format.supportsQuality {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ConvertError.write }
        return output
    }

    private func hasAlpha(_ image: CGImage) -> Bool {
        let alpha = image.alphaInfo
        return alpha == .premultipliedFirst || alpha == .premultipliedLast || alpha == .first || alpha == .last
    }

    /// 输出与源文件同目录、同名换扩展名；重名自动追加序号
    private func uniqueOutputURL(for source: URL) -> URL {
        let directory = source.deletingPathExtension()
        let base = directory.lastPathComponent
        let folder = source.deletingLastPathComponent()
        var output = folder.appendingPathComponent("\(base).\(format.pathExtension)")
        var counter = 2
        while FileManager.default.fileExists(atPath: output.path) {
            output = folder.appendingPathComponent("\(base) \(counter).\(format.pathExtension)")
            counter += 1
        }
        return output
    }

    private func require<T>(_ value: T?, message: String) throws -> T {
        guard let value else { throw ConvertError.read(message) }
        return value
    }

    private enum ConvertError: LocalizedError {
        case read(String)
        case write
        case unsupported

        var errorDescription: String? {
            switch self {
            case .read(let message): return message
            case .write: return L("写入文件失败")
            case .unsupported: return L("此设备不支持该输出格式")
            }
        }
    }

    // MARK: - 交互

    @objc private func addTapped() {
        guard !converting else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = L("选择要转换的图片")
        guard panel.runModal() == .OK else { return }
        add(urls: panel.urls)
    }

    @objc private func removeSelectedTapped() {
        guard !converting else { return }
        let indexes = tableView.selectedRowIndexes
        guard !indexes.isEmpty else { return }
        items.remove(atOffsets: IndexSet(indexes))
        refreshUI()
    }

    @objc private func formatChanged() {
        format = OutputFormat(rawValue: formatPopup.indexOfSelectedItem) ?? .jpeg
        refreshUI()
    }

    @objc private func qualityChanged() {
        quality = qualitySlider.doubleValue
        qualityLabel.stringValue = "\(Int((quality * 100).rounded()))%"
    }

    @objc private func longEdgeChanged() {
        longEdgeLimit = longEdgePopup.selectedItem?.representedObject as? Int ?? 0
    }
}

// MARK: - 列表数据源

extension ImageConvertToolController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < items.count else { return nil }
        let item = items[row]
        let identifier = tableColumn?.identifier ?? .init("name")
        let cell = NSTextField(labelWithString: "")
        cell.lineBreakMode = .byTruncatingMiddle
        cell.font = .systemFont(ofSize: 12)
        switch identifier.rawValue {
        case "name":
            cell.stringValue = item.url.lastPathComponent
        case "size":
            cell.stringValue = "\(item.pixelWidth) × \(item.pixelHeight)"
            cell.textColor = .secondaryLabelColor
        default:
            cell.stringValue = ByteCountFormatter.string(fromByteCount: Int64(item.fileSize), countStyle: .file)
            cell.textColor = .secondaryLabelColor
        }
        return cell
    }
}

/// 接收拖入图片文件的容器
final class ImageConvertDropView: NSView {
    var onDrop: (([URL]) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                               options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }
}

struct ConvertItem {
    let url: URL
    let pixelWidth: Int
    let pixelHeight: Int
    let fileSize: Int
}

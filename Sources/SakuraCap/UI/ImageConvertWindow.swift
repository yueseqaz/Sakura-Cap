import AppKit
import ImageIO
import UniformTypeIdentifiers

/// 批量图片格式转换：质量滑块、实际编码大小预览；输出保存在原文件旁边，绝不覆盖。
@MainActor
final class ImageConvertToolController: NSObject {
    static let shared = ImageConvertToolController()

    private var window: NSWindow?
    private var items: [ConvertItem] = []
    private var converting = false

    private let formats = ImageOutputFormat.available
    private let worker = ImageConversionWorker()
    private var estimateTask: Task<Void, Never>?
    private var estimateID = UUID()
    private var estimatedSizes: [URL: Int] = [:]
    private var estimateFailures = Set<URL>()
    private var format: ImageOutputFormat = .jpeg
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
    private var estimateLabel: NSTextField!

    private var options: ImageConversionOptions {
        ImageConversionOptions(format: format, quality: quality, longEdgeLimit: longEdgeLimit)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.makeKeyAndOrderFront(nil)
            refreshUI()
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 480),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = L("图片格式转换")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 640, height: 400)
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.sharingType = .readOnly
        window.delegate = self

        // 列表
        tableView = NSTableView()
        let nameColumn = NSTableColumn(identifier: .init("name"))
        nameColumn.title = L("文件")
        nameColumn.width = 260
        nameColumn.minWidth = 120
        let sizeColumn = NSTableColumn(identifier: .init("size"))
        sizeColumn.title = L("尺寸")
        sizeColumn.width = 100
        let bytesColumn = NSTableColumn(identifier: .init("bytes"))
        bytesColumn.title = L("原始大小")
        bytesColumn.width = 100
        let estimatedColumn = NSTableColumn(identifier: .init("estimated"))
        estimatedColumn.title = L("预计输出大小")
        estimatedColumn.width = 120
        for column in [nameColumn, sizeColumn, bytesColumn, estimatedColumn] {
            tableView.addTableColumn(column)
        }
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
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
        for item in formats { formatPopup.addItem(withTitle: item.title) }
        formatPopup.selectItem(at: formats.firstIndex(of: format) ?? 0)
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged)
        let formatLabel = NSTextField(labelWithString: L("输出格式"))

        qualitySlider = NSSlider(value: 0.9, minValue: 0.1, maxValue: 1.0, target: self, action: #selector(qualityChanged))
        qualitySlider.controlSize = .small
        qualitySlider.isContinuous = true
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
        hintLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        estimateLabel = NSTextField(labelWithString: L("添加图片以预览输出大小"))
        estimateLabel.identifier = .init("conversionEstimateSummary")
        estimateLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        estimateLabel.textColor = .secondaryLabelColor
        estimateLabel.lineBreakMode = .byTruncatingTail
        estimateLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        estimateLabel.translatesAutoresizingMaskIntoConstraints = false

        convertButton = NSButton(title: L("转换"), target: self, action: #selector(convertTapped))
        convertButton.bezelStyle = .rounded
        convertButton.keyEquivalent = "\r"
        convertButton.contentTintColor = .controlAccentColor

        let bar = NSVisualEffectView()
        bar.material = .windowBackground
        bar.blendingMode = .withinWindow
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(estimateLabel)
        let fileRow = NSStackView(views: [addButton, removeButton, hintLabel])
        let qualityRow = NSStackView(views: [qualitySlider, qualityLabel])
        qualityRow.spacing = 6
        let formatGroup = NSStackView(views: [formatLabel, formatPopup])
        let qualityGroup = NSStackView(views: [qualityTitleLabel, qualityRow])
        let longEdgeGroup = NSStackView(views: [longEdgeLabel, longEdgePopup])
        for group in [formatGroup, qualityGroup, longEdgeGroup] {
            group.orientation = .vertical
            group.alignment = .leading
            group.spacing = 4
        }
        let settingsRow = NSStackView(views: [formatGroup, qualityGroup, longEdgeGroup, NSView(), convertButton])
        for row in [fileRow, settingsRow] {
            row.orientation = .horizontal
            row.spacing = 8
            row.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(row)
        }

        let footnote = NSTextField(labelWithString: L("转换后的图片保存在原文件旁边，不会覆盖已有文件"))
        footnote.font = .systemFont(ofSize: 11)
        footnote.textColor = .secondaryLabelColor
        footnote.lineBreakMode = .byTruncatingTail
        footnote.toolTip = L("动画及多页图片仅转换首帧；GIF 输出为静态图片")
        footnote.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(origin: .zero, size: window.contentLayoutRect.size))
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
            bar.heightAnchor.constraint(equalToConstant: 136),
            fileRow.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            fileRow.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            fileRow.topAnchor.constraint(equalTo: bar.topAnchor, constant: 8),
            settingsRow.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            settingsRow.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            settingsRow.bottomAnchor.constraint(equalTo: estimateLabel.topAnchor, constant: -8),
            estimateLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            estimateLabel.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            estimateLabel.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -8),
            qualitySlider.widthAnchor.constraint(equalToConstant: 100),
            qualityLabel.widthAnchor.constraint(equalToConstant: 38),
            formatPopup.widthAnchor.constraint(equalToConstant: 120),
            longEdgePopup.widthAnchor.constraint(equalToConstant: 92),
            footnote.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            footnote.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
            footnote.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        ])
        window.contentView = container
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        refreshUI()
    }

    // MARK: - 数据

    private func add(urls: [URL]) {
        guard !converting else { return }
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
        setQualityVisible(format.supportsQuality)
        qualitySlider.isEnabled = format.supportsQuality && !converting
        formatPopup.isEnabled = !converting
        longEdgePopup.isEnabled = !converting
        convertButton.isEnabled = !items.isEmpty && !converting
        if !converting {
            hintLabel.stringValue = items.isEmpty
                ? L("拖入图片到这里，或点击「添加图片」")
                : String(format: L("已添加 %d 张，输出格式 %@"), items.count, format.title)
            if format == .gif { hintLabel.stringValue += " · " + L("GIF 为静态图片") }
            scheduleEstimates()
        }
    }

    private func setQualityVisible(_ visible: Bool) {
        // 无损/固定压缩格式不提供有损质量滑块。
        qualityTitleLabel.isHidden = !visible
        qualitySlider.isHidden = !visible
        qualityLabel.isHidden = !visible
    }

    // MARK: - 编码大小预览

    private func scheduleEstimates() {
        estimateTask?.cancel()
        let id = UUID()
        estimateID = id
        estimatedSizes.removeAll()
        estimateFailures.removeAll()
        tableView.reloadData()
        guard !items.isEmpty else {
            estimateLabel.stringValue = L("添加图片以预览输出大小")
            return
        }
        guard window?.isVisible == true else { return }
        estimateLabel.stringValue = L("正在计算输出大小…")
        let snapshot = items
        let settings = options
        estimateTask = Task { @MainActor in
            do {
                // 连续拖动时只编码最新设置，避免每一个鼠标事件都重新压缩整批图片。
                try await Task.sleep(nanoseconds: 200_000_000)
                for item in snapshot {
                    do {
                        let size = try await worker.estimatedSize(source: item.url, options: settings)
                        guard !Task.isCancelled, self.estimateID == id else { return }
                        self.estimatedSizes[item.url] = size
                    } catch is CancellationError { return }
                    catch {
                        guard !Task.isCancelled, self.estimateID == id else { return }
                        self.estimateFailures.insert(item.url)
                    }
                    self.tableView.reloadData()
                }
                self.updateEstimateSummary()
            } catch { /* A newer slider value or a closed window cancels this preview. */ }
        }
    }

    private func updateEstimateSummary() {
        let original = items.reduce(Int64(0)) { $0 + Int64($1.fileSize) }
        let output = estimatedSizes.values.reduce(Int64(0)) { $0 + Int64($1) }
        guard estimateFailures.isEmpty else {
            estimateLabel.stringValue = L("部分图片无法估算，请检查源文件或更换格式")
            return
        }
        var text = String(format: L("预计合计：%@ → %@"), Self.byteString(original), Self.byteString(output))
        if original > 0 {
            let change = (Double(output) / Double(original) - 1) * 100
            text += " · " + String(format: change > 0 ? L("增加 %.0f%%") : L("减少 %.0f%%"), abs(change))
        }
        estimateLabel.stringValue = text
    }

    private static func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - 转换

    @objc private func convertTapped() {
        guard !converting else { return }
        guard !items.isEmpty else {
            Toast.show(title: L("没有可转换的图片"), detail: nil)
            return
        }
        converting = true
        estimateTask?.cancel()
        estimateID = UUID()
        let snapshot = items
        let settings = options
        refreshUI()
        Task { await runConversion(items: snapshot, options: settings) }
    }

    private func runConversion(items: [ConvertItem], options: ImageConversionOptions) async {
        let total = items.count
        var outputs: [URL] = []
        var failures = 0
        for (index, item) in items.enumerated() {
            await MainActor.run {
                hintLabel.stringValue = String(format: L("转换中 %d / %d…"), index + 1, total)
            }
            do {
                let output = try await worker.convert(source: item.url, options: options)
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
        guard !converting, formats.indices.contains(formatPopup.indexOfSelectedItem) else { return }
        format = formats[formatPopup.indexOfSelectedItem]
        refreshUI()
    }

    @objc private func qualityChanged() {
        guard !converting else { return }
        quality = (qualitySlider.doubleValue * 100).rounded() / 100
        qualityLabel.stringValue = "\(Int((quality * 100).rounded()))%"
        scheduleEstimates()
    }

    @objc private func longEdgeChanged() {
        guard !converting else { return }
        longEdgeLimit = longEdgePopup.selectedItem?.representedObject as? Int ?? 0
        scheduleEstimates()
    }
}

// MARK: - 列表数据源

extension ImageConvertToolController: NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        estimateTask?.cancel()
        estimateID = UUID()
    }

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
        case "estimated":
            if let size = estimatedSizes[item.url] {
                cell.stringValue = Self.byteString(Int64(size))
            } else {
                cell.stringValue = estimateFailures.contains(item.url) ? L("无法估算") : "…"
            }
            cell.textColor = .secondaryLabelColor
        default:
            cell.stringValue = Self.byteString(Int64(item.fileSize))
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

struct ConvertItem: Sendable {
    let url: URL
    let pixelWidth: Int
    let pixelHeight: Int
    let fileSize: Int
}

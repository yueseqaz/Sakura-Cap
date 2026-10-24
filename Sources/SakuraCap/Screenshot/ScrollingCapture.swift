import AppKit
import ScreenCaptureKit

/// 长截图（滚动截屏）：框选一个区域后，边滚动边连续采样，按重叠自动纵向拼接成一张长图。
/// 说明：这是"滚动 + 拼接"的初版，遇到固定顶栏/悬浮元素可能拼不完美。
@MainActor
final class ScrollingCapture {
    static let shared = ScrollingCapture()

    private var region: RegionSelection?
    private var timer: Timer?
    private var autoScrollTask: Task<Void, Never>?
    private var scrollMonitor: Any?
    private var localScrollMonitor: Any?
    private var hud: ScrollingHUDWindow?
    private var preview: ScrollingPreviewWindow?
    private var capturing = false
    private var filter: SCContentFilter?
    private var config: SCStreamConfiguration?
    private var pixelScale: (x: CGFloat, y: CGFloat) = (2, 2)
    private var lastPreviewTime: Date = .distantPast
    private var segments: [(image: CGImage, rect: CGRect)] = []
    private var stitchedHeight = 0
    private var stitchedWidth = 0
    private var lastGray: [UInt8] = []
    private var autoScrolling = false

    func start(region: RegionSelection) {
        stopAutoScroll()
        self.region = region
        segments.removeAll()
        stitchedHeight = 0
        lastGray = []
        let hud = ScrollingHUDWindow(onFinish: { [weak self] in self?.finish() },
                                     onCancel: { [weak self] in self?.cancel() },
                                     onToggleScroll: { [weak self] in self?.toggleAutoScroll() })
        hud.orderFrontRegardless()
        self.hud = hud
        let preview = ScrollingPreviewWindow(region: region)
        preview.orderFrontRegardless()
        self.preview = preview
        filter = nil
        config = nil
        startTimer()
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            // Synthetic events carry our marker; a user's wheel/trackpad input pauses automation.
            guard event.cgEvent?.getIntegerValueField(.eventSourceUserData) != Self.scrollMarker else { return }
            Task { @MainActor in self?.stopAutoScroll() }
        }
        localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            if event.cgEvent?.getIntegerValueField(.eventSourceUserData) != Self.scrollMarker {
                self?.stopAutoScroll()
            }
            return event
        }
    }

    private func startTimer() {
        let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.captureOnce() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Task { @MainActor in
            await prepareCapture()
            await captureOnce()
            startAutoScroll()
        }
    }

    private static let scrollMarker: Int64 = 0x53414b555241

    private func startAutoScroll() {
        guard region != nil, !autoScrolling, !segments.isEmpty else { return }
        guard PermissionCenter.accessibilityGranted() || PermissionCenter.requestAccessibility() else {
            hud?.setScrollState(L("自动滚动需要辅助功能权限，请手动滚动"), running: false)
            PermissionCenter.openAccessibilitySettings()
            return
        }
        autoScrolling = true
        // In automatic mode capture one settled frame per scroll step. The old
        // independent timer sampled intermediate frames and made late stitching
        // increasingly ambiguous as the page moved.
        stopTimer()
        hud?.setScrollState(L("自动滚动中"), running: true)
        autoScrollTask = Task { @MainActor [weak self] in
            while let self, self.autoScrolling, !Task.isCancelled {
                self.postScroll()
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, self.autoScrolling else { break }
                var advanced = false
                // Retry the same scroll position before sending another scroll.
                // This prevents one late/animated frame from causing the next
                // successful match to swallow several page segments.
                for attempt in 0..<3 {
                    advanced = await self.captureOnce()
                    if advanced { break }
                    if attempt < 2 {
                        try? await Task.sleep(for: .milliseconds(300))
                    }
                }
                guard advanced else {
                    self.stopAutoScroll(message: L("无法确认新的滚动内容，已停止滚动"))
                    break
                }
                try? await Task.sleep(for: .milliseconds(350))
            }
        }
    }

    private var lastAutoHeight = 0

    private func postScroll() {
        guard let region, let screen = NSScreen.screens.first(where: { $0.displayID == region.displayID }),
              let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                                  wheel1: -3, wheel2: 0, wheel3: 0) else { return }
        let frame = ScreenCoordinate.cgFrame(of: screen)
        event.location = CGPoint(x: frame.minX + region.sckRect.midX,
                                 y: frame.minY + region.sckRect.midY)
        event.setIntegerValueField(.eventSourceUserData, value: Self.scrollMarker)
        event.post(tap: .cghidEventTap)
    }

    private func toggleAutoScroll() {
        if autoScrolling { stopAutoScroll() } else { lastAutoHeight = stitchedHeight; startAutoScroll() }
    }

    private func stopAutoScroll(message: String? = nil) {
        autoScrolling = false
        autoScrollTask?.cancel()
        autoScrollTask = nil
        hud?.setScrollState(message ?? L("已暂停自动滚动"), running: false)
    }

    /// 只构建一次过滤器/配置，之后每帧直接重采样，更跟手也更稳
    private func prepareCapture() async {
        guard #available(macOS 14.0, *), filter == nil, let region else { return }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.displayID == region.displayID }) else { return }
        // Keep these controls visible to remote viewers, but out of the long
        // screenshot itself so they cannot be stitched back into the page.
        let controlIDs = Set([hud?.windowNumber, preview?.windowNumber].compactMap { $0 })
        let controls = content.windows.filter { controlIDs.contains(Int($0.windowID)) }
        let newFilter = SCContentFilter(display: display, excludingWindows: controls)
        // SCK 配置要真实像素、裁剪要真实缩放；CGDisplayPixelsWide 返回逻辑点，不能用
        let pixels = DisplayPixelMetrics.size(region.displayID)
        let (scaleX, scaleY) = DisplayPixelMetrics.scale(region.displayID)
        let newConfig = SCStreamConfiguration()
        newConfig.width = pixels.width
        newConfig.height = pixels.height
        newConfig.showsCursor = false
        newConfig.captureResolution = .best
        filter = newFilter
        config = newConfig
        pixelScale = (scaleX, scaleY)
    }

    @discardableResult
    private func captureOnce() async -> Bool {
        guard !capturing, let region else { return false }
        capturing = true
        defer { capturing = false }
        guard #available(macOS 14.0, *), let filter, let config else { return false }
        guard let full = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { return false }
        let scale = pixelScale
        let rect = CGRect(x: region.sckRect.minX * scale.x, y: region.sckRect.minY * scale.y,
                          width: region.sckRect.width * scale.x, height: region.sckRect.height * scale.y).integral
        return append(full.cropping(to: rect) ?? full)
    }

    private func append(_ frame: CGImage) -> Bool {
        let width = frame.width
        let height = frame.height
        guard height > 4 else { return false }

        if segments.isEmpty {
            segments = [(frame, CGRect(x: 0, y: 0, width: width, height: height))]
            stitchedHeight = height
            stitchedWidth = width
            lastGray = gray(frame)
            updateHUD()
            return true
        }

        let grayNew = gray(frame)
        let shift = bestVerticalShift(prev: lastGray, next: grayNew, width: 60, height: height)
        guard shift >= 3, shift < height - 8 else {
            return false // 保留上一帧作为基准，等待同一步的稳定画面重试
        }
        guard stitchedHeight < 60000 else {
            return false // 安全上限，避免长图无限长
        }
        // next 真正新增的部分：next 的底部 shift 行（内容坐标从上一帧底部继续）
        let newRect = CGRect(x: 0, y: height - shift, width: width, height: shift)
        segments.append((frame, newRect))
        stitchedHeight += shift
        lastGray = grayNew
        updateHUD()
        return true
    }

    private func updateHUD() {
        hud?.setHeight(stitchedHeight)
        // 预览节流，避免长图越拼越大时合成开销拖慢采集
        let now = Date()
        guard now.timeIntervalSince(lastPreviewTime) > 1.2 else { return }
        lastPreviewTime = now
        if let composed = compose() { preview?.update(image: composed) }
    }

    private func finish() {
        stopAutoScroll()
        removeScrollMonitor()
        stopTimer()
        hud?.orderOut(nil)
        hud = nil
        preview?.orderOut(nil)
        preview = nil
        guard let composed = compose() else { cancel(); return }
        let name = FileName.make(ext: "png")
        AnnotationEditorController.shared.open(image: composed, suggestedName: name, source: .newCapture)
        region = nil
    }

    private func cancel() {
        stopAutoScroll()
        removeScrollMonitor()
        stopTimer()
        hud?.orderOut(nil)
        hud = nil
        preview?.orderOut(nil)
        preview = nil
        segments.removeAll()
        region = nil
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func removeScrollMonitor() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        if let localScrollMonitor { NSEvent.removeMonitor(localScrollMonitor) }
        scrollMonitor = nil
        localScrollMonitor = nil
    }

    private func compose() -> CGImage? {
        guard stitchedWidth > 0, stitchedHeight > 0 else { return nil }
        guard let ctx = CGContext(data: nil, width: stitchedWidth, height: stitchedHeight,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var yFromTop = 0
        for segment in segments {
            guard let sub = segment.image.cropping(to: segment.rect) else { continue }
            let drawY = CGFloat(stitchedHeight - yFromTop) - segment.rect.height
            ctx.draw(sub, in: CGRect(x: 0, y: drawY, width: CGFloat(segment.rect.width), height: segment.rect.height))
            yFromTop += Int(segment.rect.height)
        }
        return ctx.makeImage()
    }

    // MARK: - 重叠匹配

    private func gray(_ image: CGImage, sampleWidth: Int = 60) -> [UInt8] {
        let height = image.height
        guard height > 0, let ctx = CGContext(data: nil, width: sampleWidth, height: height,
                                              bitsPerComponent: 8, bytesPerRow: sampleWidth,
                                              space: CGColorSpaceCreateDeviceGray(),
                                              bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return [] }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: height))
        guard let data = ctx.data else { return [] }
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: sampleWidth * height))
    }

    /// 在 next 里找到 prev 底部的重叠，返回滚动量 shift（0 = 没滚动 / 没把握）
    private func bestVerticalShift(prev: [UInt8], next: [UInt8], width: Int, height: Int) -> Int {
        guard !prev.isEmpty, !next.isEmpty, prev.count >= width * height, next.count >= width * height else { return 0 }
        let maxShift = Int(Double(height) * 0.75) // 允许更快滚动（至少 25% 重叠）
        var bestShift = 0
        var bestScore = Int.max
        var shift = 0 // 关键：从 0 开始，静止画面才能正确匹配为 0
        while shift <= maxShift {
            var diff = 0
            var samples = 0
            // Ignore the extreme bottom/top bands where fixed toolbars and
            // chat composers commonly stay pinned during scrolling.
            var y = max(shift, Int(Double(height) * 0.10))
            let endY = Int(Double(height) * 0.88)
            while y < endY {
                let py = y * width
                let ny = (y - shift) * width
                var x = 0
                while x < width {
                    diff += abs(Int(prev[py + x]) - Int(next[ny + x]))
                    x += 1
                }
                samples += width
                y += 6
            }
            if samples > 0 {
                let score = diff / samples
                if score < bestScore { bestScore = score; bestShift = shift }
            }
            shift += 2
        }
        // 没把握就不动，避免把静止/无重叠的画面误当滚动而重复拼接
        return bestScore <= 10 ? bestShift : 0
    }
}

/// 长截图时的悬浮提示条
final class ScrollingHUDWindow: NSPanel {
    private let heightLabel = NSTextField(labelWithString: "")
    private let stateLabel = NSTextField(labelWithString: L("准备自动滚动…"))
    private let scrollButton = NSButton(title: L("暂停"), target: nil, action: nil)
    init(onFinish: @escaping () -> Void, onCancel: @escaping () -> Void,
         onToggleScroll: @escaping () -> Void) {
        let size = NSSize(width: 390, height: 52)
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        sharingType = .readOnly
        isMovableByWindowBackground = true

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.94).cgColor
        container.layer?.cornerRadius = 12
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor.separatorColor.cgColor

        stateLabel.font = .systemFont(ofSize: 12)
        heightLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        heightLabel.textColor = .secondaryLabelColor

        scrollButton.bezelStyle = .rounded
        scrollButton.target = ClosureTarget.shared
        scrollButton.action = #selector(ClosureTarget.toggleScrollTapped)
        ClosureTarget.shared.toggleScroll = onToggleScroll

        let finish = NSButton(title: L("完成"), target: nil, action: nil)
        finish.bezelStyle = .rounded
        finish.target = ClosureTarget.shared
        finish.action = #selector(ClosureTarget.finishTapped)
        ClosureTarget.shared.finish = onFinish
        let cancel = NSButton(title: L("取消"), target: nil, action: nil)
        cancel.bezelStyle = .rounded
        cancel.target = ClosureTarget.shared
        cancel.action = #selector(ClosureTarget.cancelTapped)
        ClosureTarget.shared.cancel = onCancel

        let stack = NSStackView(views: [stateLabel, heightLabel, scrollButton, finish, cancel])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
        ])
        contentView = container
        container.layoutSubtreeIfNeeded()
        let fitted = container.fittingSize
        if fitted.width > 1 { setContentSize(fitted) }
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visible = screen.visibleFrame
            setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2, y: visible.minY + 24))
        }
    }

    func setHeight(_ height: Int) {
        heightLabel.stringValue = String(format: L("已拼接 %d px"), height)
    }

    func setScrollState(_ message: String, running: Bool) {
        stateLabel.stringValue = message
        scrollButton.title = running ? L("暂停") : L("继续")
        contentView?.layoutSubtreeIfNeeded()
        let fitted = contentView?.fittingSize ?? frame.size
        if fitted.width > 1 { setContentSize(fitted) }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 简单闭包目标（按钮 target/action）
final class ClosureTarget: NSObject {
    static let shared = ClosureTarget()
    var finish: (() -> Void)?
    var cancel: (() -> Void)?
    var toggleScroll: (() -> Void)?
    @objc func finishTapped() { finish?() }
    @objc func cancelTapped() { cancel?() }
    @objc func toggleScrollTapped() { toggleScroll?() }
}

/// 长截图实时预览：把当前拼接结果缩略显示在旁边
final class ScrollingPreviewWindow: NSWindow {
    private let imageView = NSImageView()

    init(region: RegionSelection) {
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maxHeight = min(440, visible.height * 0.55)
        let aspect = region.sckRect.height > 0 ? region.sckRect.width / region.sckRect.height : 0.6
        let width = max(120, min(maxHeight * aspect, 320))
        super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: maxHeight),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.35)
        hasShadow = true
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        sharingType = .readOnly
        ignoresMouseEvents = true
        imageView.frame = NSRect(origin: .zero, size: NSSize(width: width, height: maxHeight))
        imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        contentView = imageView
        setFrameOrigin(NSPoint(x: visible.maxX - width - 16, y: visible.midY - maxHeight / 2))
    }

    func update(image: CGImage) {
        imageView.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}

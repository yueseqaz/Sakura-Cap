import AppKit
import ScreenCaptureKit

/// 长截图（滚动截屏）：框选一个区域后，边滚动边连续采样，按重叠自动纵向拼接成一张长图。
/// 说明：这是"滚动 + 拼接"的初版，遇到固定顶栏/悬浮元素可能拼不完美。
@MainActor
final class ScrollingCapture {
    static let shared = ScrollingCapture()

    private var region: RegionSelection?
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
    private var manualMode = false
    private var manualTrackingTask: Task<Void, Never>?
    private var manualLastScrollAt = Date.distantPast
    private var manualCandidateFrame: CGImage?
    private var manualCandidateShift = 0
    private var manualCandidateReliable = false
    private var manualPreviousCandidateShift: Int?
    private var manualStableSamples = 0
    private var manualTargetShift = 0
    private var manualMinShift = 0
    private var manualMaxShift = 0

    func start(region: RegionSelection) {
        // 防重入：已有会话进行中时忽略再次进入。
        // 否则下面的覆盖赋值会让旧滚动事件 monitor / HUD 永远失去引用、无法清理。
        guard hud == nil else { return }
        self.region = region
        segments.removeAll()
        stitchedHeight = 0
        lastGray = []
        let hud = ScrollingHUDWindow(onFinish: { [weak self] in self?.finish() },
                                     onCancel: { [weak self] in self?.cancel() },
                                     onToggleScroll: { [weak self] in self?.toggleAutoScroll() },
                                     onChooseAuto: { [weak self] in self?.chooseAuto() },
                                     onChooseManual: { [weak self] in self?.chooseManual() },
                                     onUndo: { [weak self] in self?.undoLastSegment() })
        hud.orderFrontRegardless()
        self.hud = hud
        let preview = ScrollingPreviewWindow(region: region)
        preview.orderFrontRegardless()
        self.preview = preview
        filter = nil
        config = nil
        exclusionComplete = false
        placeControls()
        hud.setChooseMode()
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            // Synthetic events carry our marker; a user's wheel/trackpad input pauses automation.
            guard event.cgEvent?.getIntegerValueField(.eventSourceUserData) != Self.scrollMarker else { return }
            Task { @MainActor in self?.handleUserScroll(event) }
        }
        localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            if event.cgEvent?.getIntegerValueField(.eventSourceUserData) != Self.scrollMarker {
                Task { @MainActor in self?.handleUserScroll(event) }
            }
            return event
        }
        // 预热采集配置；真正的首帧在选择滚动方式之后才拍
        Task { @MainActor in await prepareCapture() }
    }

    // MARK: - 滚动方式选择

    private func chooseAuto() {
        guard segments.isEmpty, region != nil else { return }
        hud?.setRunningMode()
        Task { @MainActor in
            await prepareCapture()
            await captureOnce()
            startAutoScroll()
        }
    }

    private func chooseManual() {
        guard segments.isEmpty, region != nil else { return }
        hud?.setRunningMode()
        Task { @MainActor in
            await prepareCapture()
            guard await captureOnce() else {
                hud?.setScrollState(L("无法采集当前画面"), running: false)
                return
            }
            beginManualGuidance()
        }
    }

    /// 把控制条/预览窗放到框选所在屏幕上与区域不重叠的位置。
    /// SCK 的 excludingWindows 过滤在部分系统版本上不生效，物理避开才是可靠兜底。
    private func placeControls() {
        guard let region,
              let screen = NSScreen.screens.first(where: { $0.displayID == region.displayID }) ?? NSScreen.main else { return }
        var regionRect = ScreenCoordinate.appKitLocalRect(fromSCKRect: region.sckRect, in: screen)
        regionRect.origin.x += screen.frame.minX
        regionRect.origin.y += screen.frame.minY
        let visible = screen.visibleFrame
        if let hud {
            let size = hud.frame.size
            let candidates = [
                NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 16),
                NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 16),
            ]
            hud.setFrameOrigin(candidates.first { CGRect(origin: $0, size: size).intersection(regionRect).isNull } ?? candidates[0])
        }
        if let preview {
            let size = preview.frame.size
            let candidates = [
                NSPoint(x: visible.maxX - size.width - 16, y: visible.midY - size.height / 2),
                NSPoint(x: visible.minX + 16, y: visible.midY - size.height / 2),
            ]
            preview.setFrameOrigin(candidates.first { CGRect(origin: $0, size: size).intersection(regionRect).isNull } ?? candidates[0])
        }
    }

    private static let scrollMarker: Int64 = 0x53414b555241

    private func startAutoScroll() {
        guard region != nil, !autoScrolling, !segments.isEmpty else { return }
        guard PermissionCenter.accessibilityGranted() || PermissionCenter.requestAccessibility() else {
            beginManualGuidance(message: L("自动滚动需要辅助功能权限，请精准滚动"))
            PermissionCenter.openAccessibilitySettings()
            return
        }
        manualMode = false
        manualTrackingTask?.cancel()
        manualTrackingTask = nil
        autoScrolling = true
        // In automatic mode capture one settled frame per scroll step. The old
        // Independent sampling of intermediate frames made late stitching
        // increasingly ambiguous as the page moved.
        hud?.setRunningMode()
        hud?.setScrollState(L("自动滚动中"), running: true)
        autoScrollTask = Task { @MainActor [weak self] in
            while let self, self.autoScrolling, !Task.isCancelled {
                var advanced = false
                // 每步两轮：先常规步长，匹配不到再加大步长重发一次，
                // 兼容滚动动画慢、对 line 滚动不敏感的页面。
                for lines in [3, 6] {
                    guard self.autoScrolling, !Task.isCancelled else { break }
                    self.postScroll(lines: lines)
                    try? await Task.sleep(for: .milliseconds(500))
                    // Retry the same scroll position before sending another scroll.
                    // This prevents one late/animated frame from causing the next
                    // successful match to swallow several page segments.
                    for attempt in 0..<3 {
                        guard !Task.isCancelled, self.autoScrolling else { break }
                        advanced = await self.captureOnce()
                        if advanced { break }
                        if attempt < 2 {
                            try? await Task.sleep(for: .milliseconds(300))
                        }
                    }
                    if advanced { break }
                }
                guard advanced else {
                    // 放弃自动滚动但不停会话：切入精准手动模式。
                    self.stopAutoScroll(message: L("未确认到新的滚动内容，已切换精准手动"))
                    break
                }
                try? await Task.sleep(for: .milliseconds(350))
            }
        }
    }

    private func postScroll(lines: Int) {
        guard let region, let screen = NSScreen.screens.first(where: { $0.displayID == region.displayID }),
              let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                                  wheel1: -Int32(lines), wheel2: 0, wheel3: 0) else { return }
        let frame = ScreenCoordinate.cgFrame(of: screen)
        event.location = CGPoint(x: frame.minX + region.sckRect.midX,
                                 y: frame.minY + region.sckRect.midY)
        event.setIntegerValueField(.eventSourceUserData, value: Self.scrollMarker)
        event.post(tap: .cghidEventTap)
    }

    private func toggleAutoScroll() {
        if autoScrolling { stopAutoScroll() } else { startAutoScroll() }
    }

    private func stopAutoScroll(message: String? = nil, continueManually: Bool = true) {
        guard autoScrolling else { return }
        autoScrolling = false
        autoScrollTask?.cancel()
        autoScrollTask = nil
        if continueManually {
            beginManualGuidance(message: message ?? L("已暂停自动滚动，请精准滚动"))
        }
    }

    /// 手动模式不是持续拼接，而是一次只校准一个滚动段。
    private func beginManualGuidance(message: String? = nil) {
        manualMode = true
        manualTrackingTask?.cancel()
        manualTrackingTask = nil
        manualCandidateFrame = nil
        manualCandidateShift = 0
        manualCandidateReliable = false
        manualPreviousCandidateShift = nil
        manualStableSamples = 0
        configureManualTarget()
        hud?.setManualMode()
        hud?.setManualProgress(shift: 0, target: manualTargetShift,
                               min: manualMinShift, max: manualMaxShift,
                               state: message ?? L("请向下滚动至绿色区域"))
    }

    private func configureManualTarget() {
        let height = segments.last?.image.height ?? 0
        guard height > 0 else {
            manualTargetShift = 0
            manualMinShift = 0
            manualMaxShift = 0
            return
        }
        // Aim for roughly half a viewport, retaining enough overlap for a stable match.
        manualTargetShift = max(12, Int((Double(height) * 0.52).rounded()))
        manualMinShift = max(8, Int((Double(height) * 0.38).rounded()))
        manualMaxShift = min(height - 8, Int((Double(height) * 0.66).rounded()))
    }

    private func handleUserScroll(_ event: NSEvent) {
        if autoScrolling {
            stopAutoScroll()
            return
        }
        guard manualMode else { return }
        guard abs(event.scrollingDeltaY) > 0.01 else { return }
        manualLastScrollAt = Date()
        hud?.setManualProgress(shift: manualCandidateShift, target: manualTargetShift,
                               min: manualMinShift, max: manualMaxShift,
                               state: L("检测到滚动，请停下"))
        guard manualTrackingTask == nil else { return }
        manualTrackingTask = Task { @MainActor [weak self] in
            await self?.trackManualScroll()
        }
    }

    private func trackManualScroll() async {
        defer { manualTrackingTask = nil }
        try? await Task.sleep(for: .milliseconds(100))
        while manualMode && !Task.isCancelled {
            if let frame = await captureCurrentFrame() {
                updateManualCandidate(frame)
            }
            let quietFor = Date().timeIntervalSince(manualLastScrollAt)
            if quietFor >= 0.32 {
                let settleStartedAt = manualLastScrollAt
                hud?.setManualProgress(shift: manualCandidateShift, target: manualTargetShift,
                                       min: manualMinShift, max: manualMaxShift,
                                       state: L("正在等待页面稳定"))
                try? await Task.sleep(for: .milliseconds(160))
                guard manualMode, !Task.isCancelled else { return }
                if let frame = await captureCurrentFrame() {
                    updateManualCandidate(frame)
                }
                try? await Task.sleep(for: .milliseconds(110))
                guard manualMode, !Task.isCancelled else { return }
                if let frame = await captureCurrentFrame() {
                    updateManualCandidate(frame)
                }
                // A new gesture during the settle window invalidates these samples.
                // Keep tracking instead of committing a frame from the previous step.
                guard manualLastScrollAt == settleStartedAt else { continue }
                commitManualCandidateIfReady()
                return
            }
            try? await Task.sleep(for: .milliseconds(120))
        }
    }

    private func updateManualCandidate(_ frame: CGImage) {
        guard !segments.isEmpty else { return }
        let grayNew = blurVertical(gray(frame), width: 60, height: frame.height)
        let match = bestVerticalShift(prev: lastGray, next: grayNew, width: 60, height: frame.height)
        manualCandidateShift = match.shift
        manualCandidateReliable = isReliable(match: match, height: frame.height)
        manualCandidateFrame = manualCandidateReliable ? frame : nil
        if manualCandidateReliable {
            if let previous = manualPreviousCandidateShift, abs(previous - match.shift) <= 4 {
                manualStableSamples += 1
            } else {
                manualStableSamples = 1
            }
            manualPreviousCandidateShift = match.shift
        } else {
            manualStableSamples = 0
            manualPreviousCandidateShift = nil
        }

        let state: String
        if !manualCandidateReliable || match.shift < 3 {
            state = L("请向下滚动至绿色区域")
        } else if match.shift < manualMinShift {
            state = L("滚动距离太小，请再向下滚一点")
        } else if match.shift > manualMaxShift {
            state = L("滚动过多，请向上回滚")
        } else {
            state = L("位置合适，请停下")
        }
        hud?.setManualProgress(shift: match.shift, target: manualTargetShift,
                               min: manualMinShift, max: manualMaxShift, state: state)
    }

    private func commitManualCandidateIfReady() {
        guard manualCandidateReliable,
              manualStableSamples >= 2,
              let frame = manualCandidateFrame,
              manualCandidateShift >= manualMinShift,
              manualCandidateShift <= manualMaxShift else {
            let state: String
            if manualCandidateShift > manualMaxShift {
                state = L("滚动过多，请向上回滚")
            } else if manualCandidateShift > 0 && manualCandidateShift < manualMinShift {
                state = L("滚动距离太小，请再向下滚一点")
            } else {
                state = L("未找到可靠重叠，请回到上一段重试")
            }
            hud?.setManualProgress(shift: manualCandidateShift, target: manualTargetShift,
                                   min: manualMinShift, max: manualMaxShift, state: state)
            return
        }
        guard append(frame) else {
            hud?.setManualProgress(shift: manualCandidateShift, target: manualTargetShift,
                                   min: manualMinShift, max: manualMaxShift,
                                   state: L("未找到可靠重叠，请回到上一段重试"))
            return
        }
        manualCandidateFrame = nil
        manualCandidateShift = 0
        manualCandidateReliable = false
        manualPreviousCandidateShift = nil
        manualStableSamples = 0
        configureManualTarget()
        hud?.setManualProgress(shift: 0, target: manualTargetShift,
                               min: manualMinShift, max: manualMaxShift,
                               state: L("已拼接，请向下滚动至绿色区域"))
    }

    private func isReliable(match: (shift: Int, score: Int, score0: Int), height: Int) -> Bool {
        guard match.shift >= 3, match.shift < height - 8 else { return false }
        return match.score <= 10 || match.score < match.score0 - match.score
    }

    private func captureCurrentFrame() async -> CGImage? {
        guard !capturing, let region else { return nil }
        capturing = true
        defer { capturing = false }
        guard #available(macOS 14.0, *), let filter, let config else { return nil }
        guard let full = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { return nil }
        let scale = pixelScale
        let rect = CGRect(x: region.sckRect.minX * scale.x, y: region.sckRect.minY * scale.y,
                          width: region.sckRect.width * scale.x, height: region.sckRect.height * scale.y).integral
        return full.cropping(to: rect) ?? full
    }

    /// 只构建一次过滤器/配置，之后每帧直接重采样，更跟手也更稳。
    /// 注意：SCShareableContent 的窗口列表会滞后于刚 orderFront 的控制窗——
    /// 若在注册完成前建过滤器，排除列表为空，状态条/预览就会被截进长图
    /// （且过滤器被缓存后永不重建）。因此重试到两个窗口都出现在列表里再缓存。
    private var exclusionComplete = false

    private func prepareCapture() async {
        guard #available(macOS 14.0, *), let region else { return }
        guard filter == nil || !exclusionComplete else { return }
        for _ in 0..<8 {
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
                  let display = content.displays.first(where: { $0.displayID == region.displayID }) else { return }
            let controlIDs = Set([hud?.windowNumber, preview?.windowNumber].compactMap { $0 })
            let controls = content.windows.filter { controlIDs.contains(Int($0.windowID)) }
            if controls.count == controlIDs.count {
                // Keep these controls visible to remote viewers, but out of the long
                // screenshot itself so they cannot be stitched back into the page.
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
                exclusionComplete = true
                Log.capture.info("长截图过滤器就绪，排除控制窗 \(controls.count) 个")
                return
            }
            try? await Task.sleep(for: .milliseconds(150))
        }
        Log.capture.error("长截图过滤器未等到控制窗注册，排除列表可能不完整")
    }

    @discardableResult
    private func captureOnce() async -> Bool {
        guard let frame = await captureCurrentFrame() else { return false }
        return append(frame)
    }

    private func append(_ frame: CGImage) -> Bool {
        let width = frame.width
        let height = frame.height
        guard height > 4 else { return false }

        if segments.isEmpty {
            segments = [(frame, CGRect(x: 0, y: 0, width: width, height: height))]
            stitchedHeight = height
            stitchedWidth = width
            lastGray = blurVertical(gray(frame), width: 60, height: height)
            updateHUD()
            return true
        }

        let grayNew = blurVertical(gray(frame), width: 60, height: height)
        let match = bestVerticalShift(prev: lastGray, next: grayNew, width: 60, height: height)
        Log.capture.debug("长截图匹配 shift=\(match.shift) score=\(match.score) score0=\(match.score0) height=\(height)")
        guard match.shift >= 3, match.shift < height - 8 else {
            return false // 保留上一帧作为基准，等待同一步的稳定画面重试
        }
        // 绝对阈值或相对阈值任一通过：非整数落点靠模糊压低分数；
        // 懒加载/局部动画靠"远优于静止基线 score0"的相对判定兜底
        guard match.score <= 10 || match.score < match.score0 - match.score else {
            return false
        }
        guard stitchedHeight < 60000 else {
            return false // 安全上限，避免长图无限长
        }
        // next 真正新增的部分：next 的底部 shift 行（内容坐标从上一帧底部继续）
        let newRect = CGRect(x: 0, y: height - match.shift, width: width, height: match.shift)
        segments.append((frame, newRect))
        stitchedHeight += match.shift
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
        stopAutoScroll(continueManually: false)
        manualMode = false
        manualTrackingTask?.cancel()
        manualTrackingTask = nil
        removeScrollMonitor()
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
        stopAutoScroll(continueManually: false)
        manualMode = false
        manualTrackingTask?.cancel()
        manualTrackingTask = nil
        removeScrollMonitor()
        hud?.orderOut(nil)
        hud = nil
        preview?.orderOut(nil)
        preview = nil
        segments.removeAll()
        region = nil
    }

    private func undoLastSegment() {
        guard !autoScrolling else { return }
        guard segments.count > 1 else {
            hud?.setManualProgress(shift: manualCandidateShift, target: manualTargetShift,
                                   min: manualMinShift, max: manualMaxShift,
                                   state: L("还没有可撤销的段落"))
            return
        }
        segments.removeLast()
        stitchedHeight = segments.reduce(0) { $0 + Int($1.rect.height) }
        if let last = segments.last {
            lastGray = blurVertical(gray(last.image), width: 60, height: last.image.height)
        }
        manualCandidateFrame = nil
        manualCandidateShift = 0
        manualCandidateReliable = false
        manualPreviousCandidateShift = nil
        manualStableSamples = 0
        configureManualTarget()
        updateHUD()
        if manualMode {
            hud?.setManualProgress(shift: 0, target: manualTargetShift,
                                   min: manualMinShift, max: manualMaxShift,
                                   state: L("已撤销上一段，请重新滚动至绿色区域"))
        }
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

    /// 在 next 里找到 prev 底部的重叠。
    /// 返回 (shift, score, score0)：shift=0 表示没滚动/没把握；score0 是 shift=0 的静止基线。
    /// 逐行打分后取截尾均值（去掉最差 25% 的行），固定顶栏/悬浮元素不再左右总分。
    private func bestVerticalShift(prev: [UInt8], next: [UInt8], width: Int, height: Int) -> (shift: Int, score: Int, score0: Int) {
        guard !prev.isEmpty, !next.isEmpty, prev.count >= width * height, next.count >= width * height else { return (0, .max, .max) }
        let maxShift = Int(Double(height) * 0.75) // 允许更快滚动（至少 25% 重叠）
        var bestShift = 0
        var bestScore = Int.max
        var score0 = Int.max
        var shift = 0 // 从 0 开始，静止画面才能正确匹配为 0
        while shift <= maxShift {
            var rowScores: [Int] = []
            // Ignore the extreme bottom/top bands where fixed toolbars and
            // chat composers commonly stay pinned during scrolling.
            var y = max(shift, Int(Double(height) * 0.10))
            let endY = Int(Double(height) * 0.88)
            while y < endY {
                let py = y * width
                let ny = (y - shift) * width
                var diff = 0
                var x = 0
                while x < width {
                    diff += abs(Int(prev[py + x]) - Int(next[ny + x]))
                    x += 1
                }
                rowScores.append(diff / width)
                y += 6
            }
            if !rowScores.isEmpty {
                rowScores.sort()
                let keep = max(1, rowScores.count * 3 / 4)
                let score = rowScores.prefix(keep).reduce(0, +) / keep
                if shift == 0 { score0 = score }
                if score < bestScore { bestScore = score; bestShift = shift }
            }
            shift += 2
        }
        return (bestShift, bestScore, score0)
    }

    /// 纵向均值模糊（5-tap）：洗掉 Retina 非整数滚动落点造成的亚像素差。
    /// 不模糊的话，半像素位移的匹配分数会超过阈值、被误判成"没滚动"。
    private func blurVertical(_ g: [UInt8], width: Int, height: Int, radius: Int = 2) -> [UInt8] {
        guard height > 2 * radius + 1 else { return g }
        var out = [UInt8](repeating: 0, count: g.count)
        for y in 0..<height {
            let lo = max(0, y - radius)
            let hi = min(height - 1, y + radius)
            for x in 0..<width {
                var sum = 0
                for yy in lo...hi { sum += Int(g[yy * width + x]) }
                out[y * width + x] = UInt8(sum / (hi - lo + 1))
            }
        }
        return out
    }
}

/// 长截图时的悬浮提示条：框选后选择自动或精准手动，手动模式显示位移校准条。
final class ScrollingHUDWindow: NSPanel {
    private let heightLabel = NSTextField(labelWithString: "")
    private let stateLabel = NSTextField(labelWithString: L("选择滚动方式"))
    private let manualMeter = ManualScrollMeterView()
    private let scrollButton = NSButton(title: L("暂停"), target: nil, action: nil)
    private let autoChoiceButton = NSButton(title: L("自动滚动"), target: nil, action: nil)
    private let manualChoiceButton = NSButton(title: L("精准手动"), target: nil, action: nil)
    private let undoButton = NSButton(title: L("撤销上一段"), target: nil, action: nil)
    private let finishButton = NSButton(title: L("完成"), target: nil, action: nil)
    private let cancelButton = NSButton(title: L("取消"), target: nil, action: nil)

    init(onFinish: @escaping () -> Void, onCancel: @escaping () -> Void,
         onToggleScroll: @escaping () -> Void,
         onChooseAuto: @escaping () -> Void, onChooseManual: @escaping () -> Void,
         onUndo: @escaping () -> Void) {
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
        SettingsAppearance.applySurface(to: container, fill: SettingsAppearance.sidebar,
                                        border: SettingsAppearance.separator, radius: 12)

        stateLabel.font = .systemFont(ofSize: 12)
        heightLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        heightLabel.textColor = .secondaryLabelColor

        scrollButton.bezelStyle = .rounded
        scrollButton.target = ClosureTarget.shared
        scrollButton.action = #selector(ClosureTarget.toggleScrollTapped)
        ClosureTarget.shared.toggleScroll = onToggleScroll

        autoChoiceButton.bezelStyle = .rounded
        autoChoiceButton.target = ClosureTarget.shared
        autoChoiceButton.action = #selector(ClosureTarget.chooseAutoTapped)
        ClosureTarget.shared.chooseAuto = onChooseAuto

        manualChoiceButton.bezelStyle = .rounded
        manualChoiceButton.target = ClosureTarget.shared
        manualChoiceButton.action = #selector(ClosureTarget.chooseManualTapped)
        ClosureTarget.shared.chooseManual = onChooseManual

        undoButton.bezelStyle = .rounded
        undoButton.target = ClosureTarget.shared
        undoButton.action = #selector(ClosureTarget.undoTapped)
        ClosureTarget.shared.undo = onUndo

        finishButton.bezelStyle = .rounded
        finishButton.target = ClosureTarget.shared
        finishButton.action = #selector(ClosureTarget.finishTapped)
        ClosureTarget.shared.finish = onFinish
        cancelButton.bezelStyle = .rounded
        cancelButton.target = ClosureTarget.shared
        cancelButton.action = #selector(ClosureTarget.cancelTapped)
        ClosureTarget.shared.cancel = onCancel

        manualMeter.translatesAutoresizingMaskIntoConstraints = false
        manualMeter.isHidden = true
        manualMeter.widthAnchor.constraint(equalToConstant: 110).isActive = true
        manualMeter.heightAnchor.constraint(equalToConstant: 10).isActive = true

        let stack = NSStackView(views: [stateLabel, heightLabel, manualMeter, scrollButton,
                                        autoChoiceButton, manualChoiceButton,
                                        undoButton, finishButton, cancelButton])
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
        setChooseMode()
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visible = screen.visibleFrame
            setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2, y: visible.minY + 24))
        }
    }

    private func refit() {
        contentView?.layoutSubtreeIfNeeded()
        let fitted = contentView?.fittingSize ?? frame.size
        if fitted.width > 1 { setContentSize(fitted) }
    }

    /// 框选后的第一步：只展示「自动滚动 / 精准手动 / 取消」
    func setChooseMode() {
        stateLabel.stringValue = L("选择滚动方式")
        heightLabel.isHidden = true
        scrollButton.isHidden = true
        manualMeter.isHidden = true
        undoButton.isHidden = true
        undoButton.isEnabled = false
        finishButton.isHidden = true
        autoChoiceButton.isHidden = false
        manualChoiceButton.isHidden = false
        refit()
    }

    /// 选定滚动方式后：展示运行态控件（进度 / 暂停或恢复自动 / 完成 / 取消）
    func setRunningMode() {
        autoChoiceButton.isHidden = true
        manualChoiceButton.isHidden = true
        manualMeter.isHidden = true
        heightLabel.isHidden = false
        scrollButton.isHidden = false
        undoButton.isHidden = false
        undoButton.isEnabled = false
        finishButton.isHidden = false
        refit()
    }

    func setManualMode() {
        setRunningMode()
        manualMeter.isHidden = false
        undoButton.isEnabled = true
        scrollButton.title = L("自动滚动")
        refit()
    }

    func setHeight(_ height: Int) {
        heightLabel.stringValue = String(format: L("已拼接 %d px"), height)
    }

    func setScrollState(_ message: String, running: Bool) {
        stateLabel.stringValue = message
        // running=自动滚动中可暂停；停止后按钮变为恢复自动滚动（手动模式常驻）
        scrollButton.title = running ? L("暂停") : L("自动滚动")
        refit()
    }

    func setManualProgress(shift: Int, target: Int, min: Int, max: Int, state: String) {
        stateLabel.stringValue = state
        manualMeter.update(shift: shift, target: target, min: min, max: max)
        heightLabel.stringValue = target > 0
            ? String(format: L("本段 %d / %d px"), shift, target)
            : L("等待首帧")
        refit()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 手动长截图的位移校准条：绿色区域是本次允许提交的滚动范围。
final class ManualScrollMeterView: NSView {
    private var shift = 0
    private var target = 1
    private var minShift = 0
    private var maxShift = 1

    func update(shift: Int, target: Int, min: Int, max maxShiftValue: Int) {
        self.shift = Swift.max(0, shift)
        self.target = Swift.max(1, target)
        self.minShift = Swift.max(0, min)
        self.maxShift = Swift.max(self.minShift + 1, maxShiftValue)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = bounds.insetBy(dx: 1, dy: 2)
        let radius = bounds.height / 2
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()

        let scale = bounds.width / CGFloat(maxShift)
        let safe = CGRect(x: bounds.minX + CGFloat(minShift) * scale,
                          y: bounds.minY,
                          width: CGFloat(maxShift - minShift) * scale,
                          height: bounds.height)
        NSColor.systemGreen.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: safe, xRadius: radius, yRadius: radius).fill()

        let targetX = min(bounds.maxX, max(bounds.minX, bounds.minX + CGFloat(target) * scale))
        NSColor.white.withAlphaComponent(0.9).setFill()
        NSBezierPath(rect: CGRect(x: targetX - 1, y: bounds.minY, width: 2, height: bounds.height)).fill()

        let x = min(bounds.maxX, max(bounds.minX, bounds.minX + CGFloat(shift) * scale))
        NSColor.labelColor.setFill()
        NSBezierPath(ovalIn: CGRect(x: x - 3, y: bounds.midY - 3, width: 6, height: 6)).fill()
    }
}

/// 简单闭包目标（按钮 target/action）
final class ClosureTarget: NSObject {
    static let shared = ClosureTarget()
    var finish: (() -> Void)?
    var cancel: (() -> Void)?
    var toggleScroll: (() -> Void)?
    var chooseAuto: (() -> Void)?
    var chooseManual: (() -> Void)?
    var undo: (() -> Void)?
    @objc func finishTapped() { finish?() }
    @objc func cancelTapped() { cancel?() }
    @objc func toggleScrollTapped() { toggleScroll?() }
    @objc func chooseAutoTapped() { chooseAuto?() }
    @objc func chooseManualTapped() { chooseManual?() }
    @objc func undoTapped() { undo?() }
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

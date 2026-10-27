import AppKit
import AVFoundation
import Combine


/// 摄像头画中画：一个可拖动的无边框预览窗口，`sharingType = .readOnly`，
/// 因此会被 ScreenCaptureKit 录进画面。只在「待开始 / 准备 / 倒计时 / 录制」阶段显示。
@MainActor
final class CameraPiP: ObservableObject {
    static let shared = CameraPiP()

    @Published private(set) var devices: [AVCaptureDevice] = []
    @Published private(set) var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var permissionDenied = false
    @Published private(set) var running = false
    @Published private(set) var previewEnabled = false
    private var previewScale: CGFloat = 1
    private var previewFrameInitialized = false

    /// Used by screenshot filters to exclude the preview from captured images.
    var previewWindowNumber: CGWindowID? {
        guard previewEnabled, let number = window?.windowNumber, number > 0 else { return nil }
        return CGWindowID(number)
    }

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.sakura.sakuracap.camera")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let frameStore = CameraFrameStore()
    /// delegate 队列必须持久持有（输出对 queue 的持有行为未文档化，内联创建有被释放的风险）
    private let frameQueue = DispatchQueue(label: "com.sakura.sakuracap.camera.frames")
    private var window: CameraPiPWindow?
    private var cancellables = Set<AnyCancellable>()
    private weak var controller: RecordingController?
    private var configuredDeviceID: String?

    private init() { refreshDevices() }

    /// 系统设置切回来后重新读取权限；设置页通过 ObservableObject 自动刷新状态。
    func refreshPermissionStatus() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        permissionDenied = authorizationStatus != .authorized && authorizationStatus != .notDetermined
    }

    /// Requests camera access from the permissions panel. If macOS has already
    /// made a decision, the caller should take the user to System Settings.
    func requestPermission(completion: @escaping () -> Void) {
        refreshPermissionStatus()
        guard authorizationStatus == .notDetermined else {
            completion()
            return
        }
        AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPermissionStatus()
                completion()
            }
        }
    }

    /// 绑定录制状态，自动在合适阶段显示/隐藏
    func attach(controller: RecordingController) {
        guard self.controller == nil else { return }
        self.controller = controller
        controller.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sync() }
            .store(in: &cancellables)
    }

    func refreshDevices() {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        if #available(macOS 14.0, *) { types.append(.external) } else { types.append(.externalUnknown) }
        devices = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified).devices
        if devices.isEmpty { stop() }
    }

    /// 设置面板开关
    func setEnabled(_ enabled: Bool) {
        guard enabled else { sync(); return }
        refreshPermissionStatus()
        requestPermissionIfNeeded { [weak self] in self?.sync() }
    }

    func togglePreview() {
        refreshPermissionStatus()
        if !previewEnabled, permissionDenied {
            PermissionCenter.openCameraSettings()
            Toast.show(title: L("需要摄像头权限"), detail: L("请在系统设置中允许摄像头访问"))
            return
        }
        previewEnabled.toggle()
        previewFrameInitialized = false
        sync()
    }

    func enlargePreview() {
        previewScale = min(2.5, previewScale * 1.2)
        if previewEnabled { applyConfiguration() }
    }

    func shrinkPreview() {
        previewScale = max(0.5, previewScale / 1.2)
        if previewEnabled { applyConfiguration() }
    }

    func resetPreviewSize() {
        previewScale = 1
        if previewEnabled { applyConfiguration() }
    }

    /// 画中画上的关闭按钮：关掉并同步关闭设置开关
    func disable() {
        if previewEnabled {
            previewEnabled = false
            sync()
            return
        }
        AppSettings.shared.cameraPiPEnabled = false
        sync()
    }

    /// 运行中改动设置（设备 / 大小 / 位置 / 镜像）后调用
    func refreshConfiguration() {
        guard running else { return }
        configureDeviceIfNeeded()
        applyConfiguration()
    }

    // MARK: - 状态同步

    func sync() {
        let visible: [RecordingController.State] = [.ready, .preparing, .countdown, .recording]
        guard previewEnabled || (AppSettings.shared.cameraPiPEnabled &&
              controller.map { visible.contains($0.state) } == true) else {
            stop()
            return
        }
        start()
    }

    private func start() {
        refreshPermissionStatus()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            requestPermissionIfNeeded { [weak self] in self?.sync() }
            return
        default:
            permissionDenied = true
            return
        }
        permissionDenied = false
        if devices.isEmpty { refreshDevices() }
        guard !devices.isEmpty else {
            stop()
            Toast.show(title: L("没有可用的摄像头"), detail: L("请连接摄像头后重试"))
            return
        }
        configureDeviceIfNeeded()
        showWindow()
        applyConfiguration()
        // running 不依赖主线程读到的 session.isRunning：stop() 的 stopRunning 是
        // 异步排队的，快速停→启时这里可能仍读到 true，跳过赋值会让 running 卡在
        // false（预览可见但截取被 guard 静默拦下）。统一入队检查并置位。
        let session = self.session
        sessionQueue.async { if !session.isRunning { session.startRunning() } }
        running = true
        // 预览层连接在会话起转后才可用，稍后再同步一次镜像
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.applyConfiguration() }
    }

    private func stop() {
        window?.orderOut(nil)
        if session.isRunning {
            let session = self.session
            sessionQueue.async { if session.isRunning { session.stopRunning() } }
        }
        running = false
    }

    // MARK: - 会话配置

    private func configureDeviceIfNeeded() {
        let id = AppSettings.shared.cameraPiPDeviceID
        guard configuredDeviceID != id else { return }
        configuredDeviceID = id
        let device = devices.first { $0.uniqueID == id } ?? AVCaptureDevice.default(for: .video)
        sessionQueue.async { [session, videoOutput, frameStore, frameQueue] in
            session.beginConfiguration()
            for input in session.inputs { session.removeInput(input) }
            if let device, let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                session.addInput(input)
            }
            // 抓帧输出：剪刀按钮按下时取最近一帧进标注页（幂等，重复配置设备不重复添加）
            if !session.outputs.contains(videoOutput), session.canAddOutput(videoOutput) {
                videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                videoOutput.alwaysDiscardsLateVideoFrames = true
                videoOutput.setSampleBufferDelegate(frameStore, queue: frameQueue)
                session.addOutput(videoOutput)
            }
            session.commitConfiguration()
        }
    }

    /// 画中画上的剪刀按钮：把摄像头当前帧送进标注编辑器
    func captureSnapshot() {
        window?.playCaptureFlash()
        frameStore.requestFrame { image in
            Task { @MainActor in
                guard let image else {
                    Toast.show(title: L("摄像头还没有画面"), detail: L("请稍候再试"))
                    return
                }
                AnnotationEditorController.shared.open(image: image,
                                                       suggestedName: FileName.make(ext: "png"),
                                                       source: .newCapture)
            }
        }
    }

    private func requestPermissionIfNeeded(completion: @escaping () -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor [weak self] in
                    self?.refreshPermissionStatus()
                    self?.permissionDenied = !granted
                    completion()
                }
            }
        default:
            permissionDenied = true
        }
    }

    // MARK: - 窗口

    private func showWindow() {
        if window == nil {
            let created = CameraPiPWindow(session: session, videoOutput: videoOutput)
            created.onClose = { [weak self] in self?.disable() }
            created.onCapture = { [weak self] in self?.captureSnapshot() }
            window = created
        }
        window?.orderFrontRegardless()
    }

    private func applyConfiguration() {
        guard let window else { return }
        let settings = AppSettings.shared
        if previewEnabled {
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
                ?? NSScreen.main ?? NSScreen.screens.first
            guard let screen else { return }
            let visible = screen.visibleFrame
            if !previewFrameInitialized {
                let width = min(400, visible.width * 0.42) * previewScale
                let size = NSSize(width: width, height: width * 3 / 4)
                window.setFrame(NSRect(x: visible.midX - size.width / 2,
                                       y: visible.midY - size.height / 2,
                                       width: size.width, height: size.height), display: true)
                previewFrameInitialized = true
            }
            // Preview is intentionally part of screenshots and recordings.
            window.sharingType = .readOnly
            window.setMirrored(true)
            return
        }
        window.sharingType = .readOnly
        let target = RecordingTarget.rect() ?? (NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900))
        let width = max(160, target.width * settings.cameraPiPSize / 100)
        let size = NSSize(width: width, height: (width * 9.0 / 16.0).rounded())
        window.setFrame(Self.frame(size: size, corner: settings.cameraPiPCorner, in: target), display: true)
        window.setMirrored(settings.cameraPiPMirror)
    }

    private static func frame(size: NSSize, corner: PiPCorner, in target: NSRect) -> NSRect {
        let margin: CGFloat = 24
        let origin: NSPoint
        switch corner {
        case .topLeft:
            origin = NSPoint(x: target.minX + margin, y: target.maxY - size.height - margin)
        case .topRight:
            origin = NSPoint(x: target.maxX - size.width - margin, y: target.maxY - size.height - margin)
        case .bottomLeft:
            origin = NSPoint(x: target.minX + margin, y: target.minY + margin)
        case .bottomRight:
            origin = NSPoint(x: target.maxX - size.width - margin, y: target.minY + margin)
        }
        return NSRect(origin: origin, size: size)
    }
}

/// 画中画窗口内容：视频预览 + 悬停时显示的关闭 / 截取按钮
private final class CameraPiPContentView: NSView {
    var onClose: (() -> Void)?
    var onCapture: (() -> Void)?
    private let closeButton = NSButton()
    private let captureButton = NSButton()
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 14
        layer?.masksToBounds = true

        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.wantsLayer = true
        closeButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        closeButton.layer?.cornerRadius = 12
        let closeSymbol = NSImage(systemSymbolName: "xmark", accessibilityDescription: L("关闭窗口"))
        closeButton.image = closeSymbol?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .bold))
        closeButton.contentTintColor = .white
        closeButton.imagePosition = .imageOnly
        closeButton.target = self
        closeButton.action = #selector(handleClose)
        closeButton.isHidden = true
        closeButton.autoresizingMask = [.minXMargin, .minYMargin]
        closeButton.frame = NSRect(x: bounds.width - 8 - 24, y: bounds.height - 8 - 24, width: 24, height: 24)
        addSubview(closeButton)

        captureButton.isBordered = false
        captureButton.bezelStyle = .regularSquare
        captureButton.wantsLayer = true
        captureButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        captureButton.layer?.cornerRadius = 12
        let cutSymbol = NSImage(systemSymbolName: "scissors", accessibilityDescription: L("截取摄像头画面"))
        captureButton.image = cutSymbol?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .bold))
        captureButton.contentTintColor = .white
        captureButton.imagePosition = .imageOnly
        captureButton.toolTip = L("截取摄像头画面")
        captureButton.target = self
        captureButton.action = #selector(handleCapture)
        captureButton.isHidden = true
        captureButton.autoresizingMask = [.minXMargin, .minYMargin]
        captureButton.frame = NSRect(x: bounds.width - 8 - 24 - 6 - 24, y: bounds.height - 8 - 24, width: 24, height: 24)
        addSubview(captureButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func handleClose() { onClose?() }
    @objc private func handleCapture() {
        onCapture?()
    }

    /// 截取时的白色闪光反馈（拍照效果）
    func playCaptureFlash() {
        guard let container = layer else { return }
        let flash = CALayer()
        flash.backgroundColor = NSColor.white.cgColor
        flash.frame = bounds
        flash.opacity = 0
        container.addSublayer(flash)
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0.85
        animation.toValue = 0
        animation.duration = 0.35
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        flash.add(animation, forKey: "captureFlash")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { flash.removeFromSuperlayer() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        closeButton.isHidden = false
        captureButton.isHidden = false
    }
    override func mouseExited(with event: NSEvent) {
        closeButton.isHidden = true
        captureButton.isHidden = true
    }
}

/// 把 AVCaptureVideoPreviewLayer 作为 backing layer 的视图（保证关闭按钮渲染在其之上）
private final class CameraPreviewView: NSView {
    override func makeBackingLayer() -> CALayer {
        let layer = AVCaptureVideoPreviewLayer()
        layer.videoGravity = .resizeAspectFill
        return layer
    }

    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

/// 画中画窗口：无边框、置顶、可拖动，圆角裁剪，可被录制
private final class CameraPiPWindow: NSWindow {
    private let content = CameraPiPContentView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
    private let preview = CameraPreviewView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))

    var onClose: (() -> Void)? {
        didSet { content.onClose = onClose }
    }

    var onCapture: (() -> Void)? {
        didSet { content.onCapture = onCapture }
    }

    func playCaptureFlash() { content.playCaptureFlash() }

    private let videoOutput: AVCaptureVideoDataOutput

    init(session: AVCaptureSession, videoOutput: AVCaptureVideoDataOutput) {
        self.videoOutput = videoOutput
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
                   styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        sharingType = .readOnly // 与按键显示同理：会被录进画面
        hasShadow = true
        ignoresMouseEvents = false
        isMovableByWindowBackground = true
        minSize = NSSize(width: 180, height: 120)
        maxSize = NSSize(width: 1200, height: 900)

        preview.wantsLayer = true
        preview.previewLayer.session = session
        preview.autoresizingMask = [.width, .height]
        content.addSubview(preview, positioned: .below, relativeTo: nil)

        contentView = content
    }

    func setMirrored(_ mirrored: Bool) {
        if let connection = preview.previewLayer.connection,
           connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
        if let connection = videoOutput.connection(with: .video),
           connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}


/// 摄像头最近一帧的缓存：剪刀按下时标记，下一帧到达即转换回调（不做逐帧转换，省 CPU）
private final class CameraFrameStore: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let lock = NSLock()
    private var pending: [(id: UUID, fn: (CGImage?) -> Void)] = []
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    func requestFrame(completion: @escaping (CGImage?) -> Void) {
        let id = UUID()
        lock.lock()
        pending.append((id, completion))
        lock.unlock()
        // 超时兜底：1 秒内没有帧到达（会话未起转等）也给出反馈，而不是静默
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            if let index = self.pending.firstIndex(where: { $0.id == id }) {
                let waiter = self.pending.remove(at: index).fn
                self.lock.unlock()
                waiter(nil)
            } else {
                self.lock.unlock()
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        lock.lock()
        let waiters = pending.map { $0.fn }
        pending.removeAll()
        lock.unlock()
        guard !waiters.isEmpty else { return }
        guard let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            waiters.forEach { $0(nil) }
            return
        }
        let ciImage = CIImage(cvPixelBuffer: pixel)
        let image = ciContext.createCGImage(ciImage, from: ciImage.extent)
        waiters.forEach { $0(image) }
    }
}

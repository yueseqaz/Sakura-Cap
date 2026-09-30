import AppKit
import AVFoundation
import Combine

/// 摄像头画中画：一个可拖动的无边框预览窗口，`sharingType = .readOnly`，
/// 因此会被 ScreenCaptureKit 录进画面。只在「待开始 / 准备 / 倒计时 / 录制」阶段显示。
@MainActor
final class CameraPiP: ObservableObject {
    static let shared = CameraPiP()

    @Published private(set) var devices: [AVCaptureDevice] = []
    @Published private(set) var permissionDenied = false
    @Published private(set) var running = false

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.sakura.sakuracap.camera")
    private var window: CameraPiPWindow?
    private var cancellables = Set<AnyCancellable>()
    private weak var controller: RecordingController?
    private var configuredDeviceID: String?

    private init() { refreshDevices() }

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
    }

    /// 设置面板开关
    func setEnabled(_ enabled: Bool) {
        guard enabled else { stop(); return }
        requestPermissionIfNeeded { [weak self] in self?.sync() }
    }

    /// 画中画上的关闭按钮：关掉并同步关闭设置开关
    func disable() {
        AppSettings.shared.cameraPiPEnabled = false
        stop()
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
        guard AppSettings.shared.cameraPiPEnabled,
              let state = controller?.state, visible.contains(state) else {
            stop()
            return
        }
        start()
    }

    private func start() {
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
        configureDeviceIfNeeded()
        showWindow()
        applyConfiguration()
        if !session.isRunning {
            let session = self.session
            sessionQueue.async { if !session.isRunning { session.startRunning() } }
            running = true
            // 预览层连接在会话起转后才可用，稍后再同步一次镜像
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.applyConfiguration() }
        }
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
        sessionQueue.async { [session] in
            session.beginConfiguration()
            for input in session.inputs { session.removeInput(input) }
            if let device, let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                session.addInput(input)
            }
            session.commitConfiguration()
        }
    }

    private func requestPermissionIfNeeded(completion: @escaping () -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor [weak self] in
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
            let created = CameraPiPWindow(session: session)
            created.onClose = { [weak self] in self?.disable() }
            window = created
        }
        window?.orderFrontRegardless()
    }

    private func applyConfiguration() {
        guard let window else { return }
        let settings = AppSettings.shared
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

/// 画中画窗口内容：视频预览 + 悬停时显示的关闭按钮
private final class CameraPiPContentView: NSView {
    var onClose: (() -> Void)?
    private let closeButton = NSButton()
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
        let closeSymbol = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭")
        closeButton.image = closeSymbol?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .bold))
        closeButton.contentTintColor = .white
        closeButton.imagePosition = .imageOnly
        closeButton.target = self
        closeButton.action = #selector(handleClose)
        closeButton.isHidden = true
        closeButton.autoresizingMask = [.minXMargin, .minYMargin]
        closeButton.frame = NSRect(x: bounds.width - 8 - 24, y: bounds.height - 8 - 24, width: 24, height: 24)
        addSubview(closeButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func handleClose() { onClose?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { closeButton.isHidden = false }
    override func mouseExited(with event: NSEvent) { closeButton.isHidden = true }
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

    init(session: AVCaptureSession) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        sharingType = .readOnly // 与按键显示同理：会被录进画面
        hasShadow = true
        ignoresMouseEvents = false
        isMovableByWindowBackground = true

        preview.wantsLayer = true
        preview.previewLayer.session = session
        preview.autoresizingMask = [.width, .height]
        content.addSubview(preview, positioned: .below, relativeTo: nil)

        contentView = content
    }

    func setMirrored(_ mirrored: Bool) {
        guard let connection = preview.previewLayer.connection else { return }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

import AppKit
import SwiftUI
import AVFoundation

/// 首次启动的欢迎 / 引导窗口：欢迎 → 权限 → 使用提示。
/// 之后可从菜单「欢迎使用…」再次打开（也方便回来复查权限状态）。
@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?
    private var model: OnboardingViewModel?
    private var timer: Timer?

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if window == nil {
            let model = OnboardingViewModel()
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 480),
                                  styleMask: [.titled, .closable],
                                  backing: .buffered, defer: false)
            window.title = L("欢迎使用 Sakura-Cap")
            window.isReleasedWhenClosed = false
            window.sharingType = .none // 永不进入录制
            window.contentView = NSHostingView(rootView: OnboardingView(model: model))
            model.onFinish = { [weak self] in self?.window?.close() }
            window.center()
            self.model = model
            self.window = window
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                   object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    // 关掉即视为已看过，避免每次启动都弹（菜单里仍可重新打开）
                    AppSettings.shared.hasCompletedOnboarding = true
                    self?.stopPolling()
                }
            }
        }
        model?.page = 0
        model?.refreshPermissions()
        startPolling()
        window?.makeKeyAndOrderFront(nil)
    }

    /// 轮询权限状态，用户去系统设置授权后回来能自动刷新
    private func startPolling() {
        stopPolling()
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model?.refreshPermissions() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var page = 0
    @Published var screenGranted = false
    @Published var micGranted = false
    @Published var inputGranted = false
    @Published var cameraGranted = false

    let pages = 3
    var onFinish: (() -> Void)?

    init() { refreshPermissions() }

    func refreshPermissions() {
        screenGranted = PermissionCenter.screenCaptureGranted()
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) != .denied
        inputGranted = PermissionCenter.inputMonitoringGranted()
        cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    func next() {
        if page < pages - 1 { page += 1 } else { finish() }
    }

    func back() { if page > 0 { page -= 1 } }

    func finish() {
        AppSettings.shared.hasCompletedOnboarding = true
        onFinish?()
    }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.page {
                case 0: welcome
                case 1: permissions
                default: tips
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
            footer
        }
        .frame(width: 480, height: 480)
    }

    // MARK: - 欢迎

    private var welcome: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 8)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 96, height: 96)
            Text("Sakura-Cap").font(.largeTitle).fontWeight(.semibold)
            Text(String(format: L("版本 %@"), AppInfo.version))
                .font(.caption).foregroundStyle(.secondary)
            Text(L("菜单栏常驻的极简 Mac 录屏 / 截图 / 标注工具。"))
                .font(.callout)
            Text(L("点一下菜单栏图标，就能录制屏幕、截图、OCR 取字、滚动截屏；录完还能裁剪，截图还能标注。"))
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
            HStack(spacing: 6) {
                Image(systemName: "camera.aperture").foregroundStyle(.pink)
                Text(L("图标常驻菜单栏右侧，随时可点。")).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 2)
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
    }

    // MARK: - 权限

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("授予权限")).font(.title3).fontWeight(.semibold)
            Text(L("「屏幕录制」是必需权限；其余三项按需开启，缺失只影响对应功能。"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            permissionRow(L("屏幕录制"), required: true, granted: model.screenGranted,
                          detail: L("录制与截图需要。")) { PermissionCenter.openScreenCaptureSettings() }
            permissionRow(L("麦克风"), required: false, granted: model.micGranted,
                          detail: L("录制麦克风声音需要。")) { PermissionCenter.openMicrophoneSettings() }
            permissionRow(L("输入监控"), required: false, granted: model.inputGranted,
                          detail: L("鼠标点击标记 / 键盘按键显示需要。")) { PermissionCenter.openInputMonitoringSettings() }
            permissionRow(L("摄像头"), required: false, granted: model.cameraGranted,
                          detail: L("摄像头画中画需要。")) { PermissionCenter.openCameraSettings() }

            Text(L("在系统设置里授权后回到这里，状态会自动刷新。屏幕录制可能需要重启 App 才生效。"))
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(24)
    }

    private func permissionRow(_ name: String, required: Bool, granted: Bool,
                               detail: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : (required ? "exclamationmark.triangle.fill" : "circle.dashed"))
                .foregroundStyle(granted ? Color.green : (required ? Color.orange : Color.secondary))
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name).font(.callout).fontWeight(.medium)
                    if required {
                        Text(L("必需"))
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.18)))
                            .foregroundStyle(.orange)
                    }
                }
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { action() } label: { Text(granted ? L("打开系统设置") : L("去授权")) }
                .controlSize(.small)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    // MARK: - 使用提示

    private var tips: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("开始使用")).font(.title3).fontWeight(.semibold)
            tipRow("record.circle", L("录制"), L("菜单栏 →「开始录制」，可选全屏 / 区域 / 窗口。"))
            tipRow("camera.viewfinder", L("截图"), L("全屏 / 区域截图、OCR 取字、滚动截屏都在「截图」子菜单。"))
            tipRow("pencil.tip", L("标注与裁剪"), L("截图后进标注编辑器，录屏后进裁剪页，都能直接保存、拷贝或定住。"))
            tipRow("keyboard", L("快捷键"), L("全局快捷键默认为空，去「设置 → 快捷键」绑定你习惯的组合键。"))
            Text(L("随时可点菜单栏图标开始；也可以从菜单「欢迎使用…」重新打开本引导。"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(24)
    }

    private func tipRow(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.pink).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 页脚

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(0..<model.pages, id: \.self) { i in
                    Circle()
                        .fill(i == model.page ? Color.pink : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            Spacer()
            if model.page > 0 {
                Button { model.back() } label: { Text(L("上一步")) }
            }
            Button {
                model.next()
            } label: {
                Text(model.page == model.pages - 1 ? L("完成") : L("下一步"))
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(14)
    }
}

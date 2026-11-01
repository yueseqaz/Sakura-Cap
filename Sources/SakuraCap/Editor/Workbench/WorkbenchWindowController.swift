import AppKit

/// 裁剪面板的来源：录屏结束后自动打开，还是用户主动打开/选文件
enum TrimOrigin { case recording, manual }

/// 视频工作台入口：窗口创建/去重/快捷键/关窗确认统一在 MediaEditorWindowPresenter，
/// 此处保留类名与 show(url:origin:) 接口，调用方无需改动。
@MainActor
final class WorkbenchWindowController {
    static let shared = WorkbenchWindowController()

    func show(url: URL, origin: TrimOrigin, clicks: [RecordedClick] = []) {
        // 自动打开路径直接带点击；手动打开最近录制时按文件回查
        var resolved = clicks
        if resolved.isEmpty, let controller = RecordingController.active {
            resolved = controller.lastSavedRecordings
                .first { $0.url.standardizedFileURL == url.standardizedFileURL }?.clicks ?? []
        }
        MediaEditorWindowPresenter.shared.show(url: url, origin: origin, kind: .workbench, clicks: resolved)
    }
}

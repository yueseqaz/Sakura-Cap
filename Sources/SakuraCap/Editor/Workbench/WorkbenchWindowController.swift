import AppKit

/// 裁剪面板的来源：录屏结束后自动打开，还是用户主动打开/选文件
enum TrimOrigin { case recording, manual }

/// 视频工作台入口：窗口创建/去重/快捷键/关窗确认统一在 MediaEditorWindowPresenter，
/// 此处保留类名与 show(url:origin:) 接口，调用方无需改动。
@MainActor
final class WorkbenchWindowController {
    static let shared = WorkbenchWindowController()

    func show(url: URL, origin: TrimOrigin) {
        MediaEditorWindowPresenter.shared.show(url: url, origin: origin, kind: .workbench)
    }
}

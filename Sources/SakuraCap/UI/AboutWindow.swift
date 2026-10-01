import AppKit
import SwiftUI

/// 关于窗口：应用图标、名称、版本，以及指向 GitHub 仓库的链接。
@MainActor
final class AboutWindowController {
    static let shared = AboutWindowController()

    private var window: NSWindow?

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 320),
                                  styleMask: [.titled, .closable],
                                  backing: .buffered, defer: false)
            window.title = L("关于 Sakura-Cap")
            window.isReleasedWhenClosed = false
            window.sharingType = .none // 永不进入录制
            window.contentView = NSHostingView(rootView: AboutView())
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Sakura-Cap")
                .font(.title2).fontWeight(.semibold)
            Text(String(format: L("版本 %@"), AppInfo.version))
                .font(.caption).foregroundStyle(.secondary)
            Text("菜单栏常驻的录屏 / 截图 / 标注工具")
                .font(.callout).foregroundStyle(.secondary)

            Divider().padding(.vertical, 4)

            Link(destination: AppInfo.repository) {
                Label("访问 GitHub 仓库", systemImage: "link")
            }
            Text(AppInfo.repository.absoluteString)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)

            Spacer(minLength: 0)

            Text("© 2026 Sakura")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(width: 320, height: 320)
    }
}

import AppKit
import SwiftUI

/// 聊天记录窗口的视图模型：左侧会话列表 + 右侧当前选中会话
@MainActor
final class AIHistoryViewModel: ObservableObject {
    @Published private(set) var sessions: [AIChatSession] = []
    @Published var selected: AIChatViewModel?

    init() {
        reload()
    }

    func reload() {
        sessions = AIChatStore.shared.sessions
        // 选中项被外部删除/不在列表时清空
        if let id = selected?.session.id, !sessions.contains(where: { $0.id == id }) {
            selected = nil
        }
    }

    func select(_ session: AIChatSession) {
        selected = AIChatViewModel(session: session)
    }

    /// 彻底删除：会话文件 + 其中所有图片（二次确认）
    func requestDelete(_ session: AIChatSession) {
        let alert = NSAlert()
        alert.messageText = L("删除这段聊天记录？")
        alert.informativeText = L("将同时清理其中的图片文件，删除后无法恢复。")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("取消"))
        alert.addButton(withTitle: L("删除"))
        guard runModalAlert(alert) == .alertSecondButtonReturn else { return }
        AIChatStore.shared.delete(session)
        if selected?.session.id == session.id { selected = nil }
        reload()
    }
}

/// 聊天记录窗口：左侧会话列表（可删除），右侧聊天面板
@MainActor
final class AIHistoryPresenter {
    static let shared = AIHistoryPresenter()

    private var window: NSWindow?
    private let model = AIHistoryViewModel()

    func open() {
        NSApp.activate(ignoringOtherApps: true)
        model.reload()
        if let window {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1400, height: 900)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0,
                                                  width: min(980, screen.width * 0.72),
                                                  height: min(680, screen.height * 0.82)),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = L("聊天记录")
        window.isReleasedWhenClosed = false
        window.sharingType = .readOnly
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 680, height: 460)
        window.contentView = NSHostingView(rootView: AIHistoryView(model: model))
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}

struct AIHistoryView: View {
    @ObservedObject var model: AIHistoryViewModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            if let chat = model.selected {
                ChatPane(model: chat)
                    .background(SettingsAppearance.color(SettingsAppearance.canvas))
            } else {
                placeholder
            }
        }
        .background(SettingsAppearance.color(SettingsAppearance.canvas))
        .frame(minWidth: 680, minHeight: 460)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(format: L("聊天记录（%d）"), model.sessions.count))
                    .font(SettingsAppearance.bodyFont.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Divider()
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.sessions) { session in
                        SessionRow(session: session,
                                   isSelected: model.selected?.session.id == session.id,
                                   onSelect: { model.select(session) },
                                   onDelete: { model.requestDelete(session) })
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
        }
        .frame(width: 248)
        .background(SettingsAppearance.color(SettingsAppearance.sidebar))
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text(L("选择左侧的聊天记录查看"))
                .font(SettingsAppearance.detailFont)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SessionRow: View {
    let session: AIChatSession
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title.isEmpty ? L("新对话") : session.title)
                    .font(SettingsAppearance.detailFont)
                    .lineLimit(1)
                Text(Self.date(session.updatedAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("删除这段聊天记录？"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(RoundedRectangle(cornerRadius: 6)
            .fill(isSelected ? SettingsAppearance.color(SettingsAppearance.selection) : .clear))
        .onTapGesture(perform: onSelect)
    }

    private static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

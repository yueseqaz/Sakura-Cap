import AppKit
import SwiftUI

@MainActor
final class TranslationViewModel: ObservableObject {
    let original: String
    @Published var translation = ""
    @Published var isLoading = false
    @Published var error: String?
    var onClose: (() -> Void)?

    init(original: String) { self.original = original }
}

/// 翻译结果弹窗：原文 + 译文，手动关闭。
@MainActor
final class TranslationPresenter {
    static let shared = TranslationPresenter()
    private var windows: [NSWindow] = []

    @discardableResult
    func present(original: String) -> TranslationViewModel {
        NSApp.activate(ignoringOtherApps: true)
        let model = TranslationViewModel(original: original)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 470),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = L("翻译")
        window.isReleasedWhenClosed = false
        window.sharingType = .none
        window.minSize = NSSize(width: 360, height: 340)
        window.contentView = NSHostingView(rootView: TranslationView(model: model))
        model.onClose = { [weak window] in window?.close() }
        window.center()
        window.makeKeyAndOrderFront(nil)
        windows.append(window)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                               object: window, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let closed = note.object as? NSWindow else { return }
                self?.windows.removeAll { $0 === closed }
            }
        }
        return model
    }
}

struct TranslationView: View {
    @ObservedObject var model: TranslationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("原文")).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
            box {
                ScrollView {
                    Text(model.original)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: 130)

            Text(L("译文")).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
            box {
                ScrollView {
                    Group {
                        if model.isLoading {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(L("翻译中…")).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else if let error = model.error {
                            Text(error).foregroundStyle(.red).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text(model.translation).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(2)
                }
            }
            .frame(height: 170)

            HStack {
                Spacer()
                Button { copy() } label: { Text(L("复制译文")) }
                    .disabled(model.translation.isEmpty)
                Button { model.onClose?() } label: { Text(L("关闭窗口")) }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(minWidth: 360, minHeight: 340)
    }

    private func box<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.translation, forType: .string)
        Toast.show(title: L("已复制译文"), detail: nil)
    }
}

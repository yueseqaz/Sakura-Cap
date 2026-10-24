import AppKit
import SwiftUI

/// 翻译窗口的视图模型：原文可编辑（输入翻译 / OCR 结果回填共用），
/// 翻译执行统一走 translate()，调用方不再各自内联服务逻辑。
@MainActor
final class TranslationViewModel: ObservableObject {
    @Published var original = "" { didSet { translation = ""; error = nil } }
    @Published var translation = ""
    @Published var isLoading = false
    @Published var error: String?
    var onClose: (() -> Void)?

    /// 预填原文并可选立即翻译（OCR 流程用）
    convenience init(original: String, autoTranslate: Bool) {
        self.init()
        self.original = original
        if autoTranslate, !original.isEmpty {
            translate()
        }
    }

    init() {}

    /// 窗口内切换语言/风格后：已有原文且不在加载中时自动重译
    func retranslateIfPossible() {
        if !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isLoading {
            translate()
        }
    }

    /// 统一的翻译执行入口：设置里的服务商 / 模型 / 语言 / 风格
    func translate() {
        let text = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }
        let config = AppSettings.shared.translationConfig
        isLoading = true
        error = nil
        translation = ""
        Task {
            do {
                translation = try await TranslationService.translate(text, config: config)
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }
}

/// 翻译窗口：顶部原文输入（可键入 / 粘贴），下方译文。
/// OCR 翻译与手动输入翻译共用这一个窗口。
@MainActor
final class TranslationPresenter {
    static let shared = TranslationPresenter()
    private var windows: [NSWindow] = []

    /// 打开翻译窗口；original 非空则回填并（autoTranslate 时）立即翻译
    @discardableResult
    func present(original: String = "", autoTranslate: Bool = false) -> TranslationViewModel {
        NSApp.activate(ignoringOtherApps: true)
        // 已有窗口则复用：回填原文并翻译，避免开一堆窗口
        if let model = reuseExisting() {
            model.original = original
            if autoTranslate, !original.isEmpty { model.translate() }
            return model
        }
        let model = TranslationViewModel(original: original, autoTranslate: autoTranslate)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 470),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = L("翻译")
        window.isReleasedWhenClosed = false
        window.sharingType = .readOnly
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

    private func reuseExisting() -> TranslationViewModel? {
        guard let window = windows.last,
              let hosting = window.contentView as? NSHostingView<TranslationView> else { return nil }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return hosting.rootView.model
    }
}

struct TranslationView: View {
    @ObservedObject var model: TranslationViewModel
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 语言 / 风格就地可调（写入设置，OCR 翻译同样生效）；改动后自动重译
            HStack(spacing: 12) {
                Text(L("译成")).font(.caption).foregroundStyle(.secondary)
                Picker(L("译成"), selection: Binding(
                    get: { settings.translateTargetLang },
                    set: { settings.translateTargetLang = $0; model.retranslateIfPossible() })) {
                    ForEach(TranslateLanguage.allCases.filter { $0 != .auto }) { l in Text(l.label).tag(l.rawValue) }
                }.pickerStyle(.menu).labelsHidden().frame(width: 120)
                Spacer()
                Text(L("风格")).font(.caption).foregroundStyle(.secondary)
                Picker(L("风格"), selection: Binding(
                    get: { settings.translateStyle },
                    set: { settings.translateStyle = $0; model.retranslateIfPossible() })) {
                    ForEach(TranslateStyle.allCases) { st in Text(st.label).tag(st.rawValue) }
                }.pickerStyle(.menu).labelsHidden().frame(width: 90)
            }
            HStack {
                Text(L("原文")).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                Spacer()
                Button { model.translate() } label: { Text(L("翻译")) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isLoading || model.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            box {
                // AppKit 文本视图：键入 / 粘贴 / ⌘A 全选（SwiftUI TextEditor 在
                // CLT 工具链下行为不稳，且 NSTextView 换行与选中行为更可靠）
                EditableText(text: $model.original, font: NSFont.systemFont(ofSize: 13))
                    .frame(height: 120)
            }

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
            .frame(minHeight: 140)

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

/// NSTextView 包装（可编辑、多行）。用 NSTextView.scrollableTextView() 工厂：
/// 手工 new 出的 NSTextView 初始尺寸为零，点不中也无法输入。
struct EditableText: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .systemFont(ofSize: 13)

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: EditableText
        init(_ parent: EditableText) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        if let textView = scroll.documentView as? NSTextView {
            textView.isRichText = false
            textView.allowsUndo = true
            textView.drawsBackground = false
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.font = font
            textView.textColor = .labelColor
            textView.delegate = context.coordinator
            textView.string = text
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }
        // 空内容时文本视图高度会被压到 0，点不中输入框；撑到可视高度
        let visibleHeight = scroll.contentView.bounds.height
        if textView.frame.height < visibleHeight {
            textView.frame.size.height = visibleHeight
        }
    }
}

import AppKit
import SwiftUI

/// AI 聊天窗口的视图模型：当前会话 + 输入 + 附件 + 流式状态
@MainActor
final class AIChatViewModel: ObservableObject {
    @Published private(set) var session: AIChatSession
    @Published var input = ""
    /// 待发送的图片附件（文件名，来自标注页 / 截屏问 AI）
    @Published var stagedImages: [String] = []
    /// 流式中的助手内容（空 = 空闲）
    @Published private(set) var streamingText = ""
    @Published private(set) var isStreaming = false
    @Published var error: String?
    /// 每次内容变化自增，驱动滚动到底部
    @Published private(set) var scrollStamp = 0

    private var streamTask: Task<Void, Never>?
    private let store = AIChatStore.shared

    init(session: AIChatSession) {
        self.session = session
    }

    var isEmpty: Bool { session.messages.isEmpty && streamingText.isEmpty && stagedImages.isEmpty }

    func attach(image: CGImage) {
        if let name = store.saveImage(image) {
            stagedImages.append(name)
            scrollStamp += 1
        }
    }

    func removeStagedImage(_ name: String) {
        stagedImages.removeAll { $0 == name }
    }

    func image(_ name: String) -> CGImage? {
        store.loadImage(name)
    }

    func startNewSession() {
        cancelStreaming()
        session = AIChatSession()
        input = ""
        stagedImages = []
        error = nil
        scrollStamp += 1
    }

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !stagedImages.isEmpty, !isStreaming else { return }
        let userMessage = AIChatMessage(role: .user, text: text, imageFiles: stagedImages)
        session.messages.append(userMessage)
        store.save(&session)
        input = ""
        stagedImages = []
        error = nil
        scrollStamp += 1
        streamReply()
    }

    private func streamReply() {
        let history = session.messages
        let config = AppSettings.shared.translationConfig
        isStreaming = true
        streamingText = ""
        scrollStamp += 1
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let full = try await AIChatClient.stream(messages: history, config: config, store: self.store) { [weak self] delta in
                    guard let self else { return }
                    Task { @MainActor in
                        self.streamingText += delta
                        self.scrollStamp += 1
                    }
                }
                self.session.messages.append(AIChatMessage(role: .assistant, text: full))
                self.store.save(&self.session)
            } catch is CancellationError {
                // 手动停止：保留已流出的部分
                if !self.streamingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.session.messages.append(AIChatMessage(role: .assistant, text: self.streamingText))
                    self.store.save(&self.session)
                }
            } catch {
                if !self.streamingText.isEmpty {
                    self.session.messages.append(AIChatMessage(role: .assistant, text: self.streamingText))
                    self.store.save(&self.session)
                }
                self.error = error.localizedDescription
            }
            self.streamingText = ""
            self.isStreaming = false
            self.scrollStamp += 1
        }
    }

    func cancelStreaming() {
        streamTask?.cancel()
        streamTask = nil
    }

    func stopTapped() { cancelStreaming() }
}

/// AI 聊天窗口（单实例复用）：菜单 / 标注页 / 截屏问 AI 共用入口
@MainActor
final class AIChatPresenter {
    static let shared = AIChatPresenter()

    private var window: NSWindow?
    private(set) var model: AIChatViewModel?

    /// 打开窗口：session 为空则续接最近会话（没有则新建）
    func open(session: AIChatSession? = nil) {
        let target = session ?? AIChatStore.shared.sessions.first ?? AIChatSession()
        present(model: AIChatViewModel(session: target))
    }

    /// 带图片打开（标注页问 AI / 截屏问 AI 图片）：新会话 + 附件就位，焦点在输入框
    func openWithImage(_ image: CGImage) {
        let model = AIChatViewModel(session: AIChatSession())
        model.attach(image: image)
        present(model: model)
    }

    /// 带 OCR 文本打开（截屏问 AI OCR）：新会话，输入框预填引用文本
    func openWithText(_ text: String) {
        let model = AIChatViewModel(session: AIChatSession())
        model.input = text
        present(model: model)
    }

    private func present(model: AIChatViewModel) {
        NSApp.activate(ignoringOtherApps: true)
        self.model = model
        if let window {
            window.contentView = NSHostingView(rootView: AIChatView(model: model))
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 900)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0,
                                                  width: min(560, screen.width * 0.5),
                                                  height: min(680, screen.height * 0.8)),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = L("AI 助手")
        window.isReleasedWhenClosed = false
        window.sharingType = .readOnly
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 380, height: 460)
        window.contentView = NSHostingView(rootView: AIChatView(model: model))
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}

// MARK: - 视图

struct AIChatView: View {
    @ObservedObject var model: AIChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            messageList
            Divider()
            composer
        }
        .background(SettingsAppearance.color(SettingsAppearance.canvas))
        .frame(minWidth: 380, minHeight: 460)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(SettingsAppearance.color(SettingsAppearance.accent))
            Text(model.session.title.isEmpty ? L("新对话") : model.session.title)
                .lineLimit(1)
                .font(SettingsAppearance.bodyFont)
            Spacer()
            if model.isStreaming {
                Button(L("停止")) { model.stopTapped() }
                    .buttonStyle(.bordered)
            }
            Button(L("新对话")) { model.startNewSession() }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if model.isEmpty {
                        emptyHint
                    }
                    ForEach(model.session.messages) { message in
                        MessageBubble(message: message, model: model)
                            .id(message.id)
                    }
                    if !model.streamingText.isEmpty {
                        MessageBubble(message: AIChatMessage(role: .assistant, text: model.streamingText),
                                      model: model, streaming: true)
                            .id("streaming")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(12)
            }
            .onChange(of: model.scrollStamp) { _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(L("问点什么，或从标注页 / 截屏把内容带进来"))
                .font(SettingsAppearance.detailFont)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if !model.stagedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.stagedImages, id: \.self) { name in
                            ZStack(alignment: .topTrailing) {
                                if let cg = model.image(name) {
                                    Image(nsImage: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 64, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                Button { model.removeStagedImage(name) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .offset(x: 5, y: -5)
                            }
                        }
                    }
                }
                .frame(height: 70)
                .padding(.horizontal, 12)
            }
            HStack(alignment: .bottom, spacing: 8) {
                EditableText(text: $model.input)
                    .frame(height: 72)
                VStack(spacing: 6) {
                    Button {
                        model.send()
                    } label: {
                        Image(systemName: model.isStreaming ? "stop.circle" : "arrow.up.circle.fill")
                            .font(.system(size: 22))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(SettingsAppearance.color(SettingsAppearance.accent))
                    .disabled(model.isStreaming && model.streamingText.isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help(model.isStreaming ? L("停止生成") : L("发送 ⌘↩"))
                }
                .padding(.bottom, 6)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .overlay(alignment: .top) {
            if let error = model.error {
                Text(error)
                    .font(SettingsAppearance.detailFont)
                    .foregroundStyle(SettingsAppearance.color(SettingsAppearance.error))
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }
        }
    }
}

/// 单条消息气泡：用户（右、纯文本+图片）/ 助手（左、Markdown）
private struct MessageBubble: View {
    let message: AIChatMessage
    @ObservedObject var model: AIChatViewModel
    var streaming = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user { Spacer(minLength: 32) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                if !message.imageFiles.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(message.imageFiles, id: \.self) { name in
                            if let cg = model.image(name) {
                                Image(nsImage: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 120, height: 90)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
                if !message.text.isEmpty {
                    if message.role == .assistant {
                        GeometryReader { geometry in
                            let attributed = Markdown.attributed(message.text)
                            let height = Markdown.height(of: attributed, width: geometry.size.width - 24)
                            MarkdownTextView(attributed: attributed)
                                .frame(height: height + 10)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(message.text)
                            .textSelection(.enabled)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 10)
                                .fill(SettingsAppearance.color(SettingsAppearance.accent)))
                    }
                }
                if streaming {
                    HStack(spacing: 4) {
                        Circle().fill(Color.secondary).frame(width: 5, height: 5)
                        Circle().fill(Color.secondary).frame(width: 5, height: 5)
                        Circle().fill(Color.secondary).frame(width: 5, height: 5)
                    }
                    .padding(.top, 2)
                }
            }
            if message.role == .assistant { Spacer(minLength: 32) }
        }
    }
}

/// 只读 Markdown 文本视图（可选中、链接可点）
struct MarkdownTextView: NSViewRepresentable {
    let attributed: NSAttributedString

    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.heightTracksTextView = true
        view.textContainerInset = NSSize(width: 10, height: 5)
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        view.textStorage?.setAttributedString(attributed)
    }
}

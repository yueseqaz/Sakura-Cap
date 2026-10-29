import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// AI 聊天窗口的视图模型：当前会话 + 输入 + 附件 + 流式状态
@MainActor
final class AIChatViewModel: ObservableObject {
    typealias ReplyStream = ([AIChatMessage], TranslationConfig, AIChatStore, String?,
                            @escaping (String) -> Void) async throws -> String
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
    private var streamID: UUID?
    private let store: AIChatStore
    private let replyStream: ReplyStream

    init(session: AIChatSession, store: AIChatStore? = nil,
         replyStream: @escaping ReplyStream = AIChatClient.stream) {
        self.session = session
        self.store = store ?? AIChatStore.shared
        self.replyStream = replyStream
    }

    var isEmpty: Bool { session.messages.isEmpty && streamingText.isEmpty && stagedImages.isEmpty }
    var canSend: Bool { !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !stagedImages.isEmpty }
    var canRetry: Bool { error != nil && !isStreaming && session.messages.contains { $0.role == .user } }

    func retry() {
        guard canRetry, let lastUser = session.messages.lastIndex(where: { $0.role == .user }) else { return }
        // Retrying replaces only the failed answer, never duplicates the question.
        let answerStart = lastUser + 1
        if answerStart < session.messages.count {
            session.messages.removeSubrange(answerStart..<session.messages.count)
        }
        error = nil
        store.save(&session)
        streamReply()
    }

    func sendOrStop() {
        if isStreaming { stopTapped() } else { send() }
    }

    func attach(image: CGImage) {
        if let name = store.saveImage(image) {
            stagedImages.append(name)
            scrollStamp += 1
        }
    }

    func removeStagedImage(_ name: String) {
        stagedImages.removeAll { $0 == name }
    }

    /// 加号按钮：从文件选择图片附件
    func attachFromPicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let image = NSImage(contentsOf: url),
               let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                attach(image: cg)
            }
        }
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

    /// 记忆压缩参数：超过阈值后，早期对话滚动摘要、最近消息原文携带
    private static let summarizeThreshold = 28
    private static let keepRecent = 12

    /// 超过阈值时把 summarizedUpTo..<(count-keepRecent) 的新增对话并入滚动摘要
    private func compressMemoryIfNeeded(config: TranslationConfig) async {
        let total = session.messages.count
        let summarized = session.summarizedUpTo ?? 0
        guard total > Self.summarizeThreshold, total - summarized > Self.keepRecent else { return }
        let range = summarized..<(total - Self.keepRecent)
        guard range.lowerBound < range.upperBound else { return }
        let transcript = session.messages[range].map { message in
            "\(message.role == .user ? "用户" : "AI")：\(message.text.prefix(600))"
        }.joined(separator: "\n")
        let prompt = """
        请把以下对话压缩成滚动摘要：保留关键事实、结论与代码意图，合并进已有摘要，300 字以内，只输出摘要正文。
        \(session.summary.map { "已有摘要：\n\($0)\n\n" } ?? "")新增对话：
        \(transcript)
        """
        let sessionID = session.id
        if let merged = try? await replyStream([AIChatMessage(role: .user, text: prompt)], config, store, nil, { _ in }),
           !Task.isCancelled, session.id == sessionID {
            session.summary = merged
            session.summarizedUpTo = total - Self.keepRecent
            store.save(&session)
        }
    }

    private func streamReply() {
        let config = AppSettings.shared.translationConfig
        let requestID = UUID()
        streamID = requestID
        isStreaming = true
        streamingText = ""
        scrollStamp += 1
        streamTask = Task { [weak self] in
            guard let self else { return }
            await self.compressMemoryIfNeeded(config: config)
            guard !Task.isCancelled, self.streamID == requestID else { return }
            // 已有摘要时只携带未压缩的最近消息
            let summarized = self.session.summarizedUpTo ?? 0
            let clamped = min(summarized, self.session.messages.count)
            let history = summarized > 0 ? Array(self.session.messages[clamped...]) : self.session.messages
            let summary = summarized > 0 ? self.session.summary : nil
            do {
                let full = try await self.replyStream(history, config, self.store, summary) { [weak self] delta in
                    guard let self else { return }
                    Task { @MainActor in
                        guard self.streamID == requestID else { return }
                        self.streamingText += delta
                        self.scrollStamp += 1
                    }
                }
                guard self.streamID == requestID else { return }
                self.session.messages.append(AIChatMessage(role: .assistant, text: full))
                self.store.save(&self.session)
            } catch is CancellationError {
                guard self.streamID == requestID else { return }
                // 手动停止：保留已流出的部分
                if !self.streamingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.session.messages.append(AIChatMessage(role: .assistant, text: self.streamingText))
                    self.store.save(&self.session)
                }
            } catch {
                guard self.streamID == requestID else { return }
                if !self.streamingText.isEmpty {
                    self.session.messages.append(AIChatMessage(role: .assistant, text: self.streamingText))
                    self.store.save(&self.session)
                }
                self.error = error.localizedDescription
            }
            self.streamingText = ""
            self.isStreaming = false
            self.streamID = nil
            self.streamTask = nil
            self.scrollStamp += 1
        }
    }

    func cancelStreaming() {
        streamTask?.cancel()
        streamTask = nil
        streamID = nil
        if !streamingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            session.messages.append(AIChatMessage(role: .assistant, text: streamingText))
            store.save(&session)
        }
        streamingText = ""
        isStreaming = false
        scrollStamp += 1
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
        WindowPresentation.configure(window)
        window.minSize = NSSize(width: 380, height: 460)
        window.contentView = NSHostingView(rootView: AIChatView(model: model))
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}

/// 附件缩略图：点击放大查看，右上角移除（热区 22pt，完整露出）
private struct StagedThumb: View {
    let name: String
    let model: AIChatViewModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let cg = model.image(name) {
                    Image(nsImage: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .onTapGesture {
                            if let cg = model.image(name) { AIChatImageViewer.shared.show(cg) }
                        }
                }
            }
            Button {
                model.removeStagedImage(name)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: 7, y: -7)
        }
    }
}

// MARK: - 视图

struct AIChatView: View {
    @ObservedObject var model: AIChatViewModel

    var body: some View {
        ChatPane(model: model)
            .background(SettingsAppearance.color(SettingsAppearance.canvas))
            .frame(minWidth: 380, minHeight: 460)
    }
}

/// 聊天主体（顶栏 + 消息列表 + 输入区），独立窗口与历史窗口共用
struct ChatPane: View {
    @ObservedObject var model: AIChatViewModel
    @StateObject private var scrollState = ChatScrollState()
    @StateObject private var composerState = ChatComposerState()

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            messageList
            composer
        }
    }

    @ObservedObject private var settings = AppSettings.shared

    /// 左侧显示当前生效的模型（翻译与 AI 共用这套服务配置）
    private var modelLabel: String {
        if settings.translateProvider == .deepSeek {
            return "DeepSeek · \(settings.activeTranslateModel)"
        }
        let format = CustomAPIFormat(rawValue: settings.translateCustomFormat) ?? .openAIChat
        return String(format: L("自定义 · %@ · %@"), format.label, settings.activeTranslateModel)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(SettingsAppearance.color(SettingsAppearance.accent))
            Text(modelLabel)
                .lineLimit(1)
                .truncationMode(.middle)
                .font(SettingsAppearance.bodyFont)
                .help(modelLabel)
            if !model.session.title.isEmpty {
                Text(model.session.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .font(SettingsAppearance.detailFont)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.session.summary != nil {
                Image(systemName: "brain")
                    .foregroundStyle(.tertiary)
                    .help(L("早期对话已压缩为摘要，随对话滚动更新"))
            }
            Button { model.startNewSession() } label: {
                Label(L("新对话"), systemImage: "square.and.pencil")
            }
            .buttonStyle(SettingsButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var messageList: some View {
        ScrollView {
            // Markdown has variable height. Lazy row estimates can change the
            // document height above the viewport while reading older messages.
            VStack(spacing: 20) {
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
                } else if model.isStreaming {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L("正在连接模型…"))
                            .font(SettingsAppearance.detailFont)
                            .foregroundStyle(SettingsAppearance.color(SettingsAppearance.secondary))
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                    .id("streaming")
                }
                Color.clear.frame(height: 1)
            }
            .frame(maxWidth: 720)
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(ChatScrollTracking(state: scrollState) { scrollState.followsLatestMessage = $0 })
        }
        .onChange(of: model.session.id) { _ in
            scrollState.followsLatestMessage = true
            scrollState.scrollToLatest()
        }
        .onChange(of: model.session.messages.last(where: { $0.role == .user })?.id) { _ in
            scrollState.followsLatestMessage = true
            scrollState.scrollToLatest()
        }
        .onChange(of: model.scrollStamp) { _ in scrollState.scrollToLatest() }
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
        VStack(alignment: .leading, spacing: 10) {
            if let error = model.error {
                VStack(alignment: .leading, spacing: 8) {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(SettingsAppearance.detailFont)
                        .foregroundStyle(SettingsAppearance.color(SettingsAppearance.error))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        if model.canRetry {
                            Button(L("重试")) { model.retry() }
                        }
                        Button(L("服务设置")) { StatusItemController.showSettings(section: "translate") }
                        Spacer(minLength: 0)
                        Button { model.error = nil } label: { Image(systemName: "xmark") }
                            .accessibilityLabel(L("关闭提示"))
                    }
                    .font(SettingsAppearance.detailFont)
                    .buttonStyle(.plain)
                    .foregroundStyle(SettingsAppearance.color(SettingsAppearance.focus))
                }
                .padding(.horizontal, 2)
            }
            if !model.stagedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(model.stagedImages, id: \.self) { name in
                            StagedThumb(name: name, model: model)
                        }
                    }
                    .padding(.top, 10)   // 给移除按钮留出上方空间，不被分隔线压住
                }
                .frame(height: 80)
            }
            ZStack(alignment: .topLeading) {
                if model.input.isEmpty && !composerState.isComposing {
                    Text(L("继续提问，或添加图片…"))
                        .foregroundStyle(SettingsAppearance.color(SettingsAppearance.secondary))
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                EditableText(text: $model.input, font: .systemFont(ofSize: 14),
                             onCommit: { model.send() },
                             onHeightChange: { composerState.height = $0 },
                             onCompositionChange: { composerState.isComposing = $0 })
                    .frame(height: composerState.height)
                    .accessibilityLabel(L("消息输入"))
            }
            HStack(spacing: 8) {
                Button { model.attachFromPicker() } label: {
                    Label(L("图片"), systemImage: "plus")
                        .frame(minHeight: 30)
                }
                .buttonStyle(.plain)
                .help(L("添加图片"))
                Spacer(minLength: 0)
                Text(L("Enter 发送 · Shift Enter 换行"))
                    .font(SettingsAppearance.detailFont)
                    .foregroundStyle(SettingsAppearance.color(SettingsAppearance.secondary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                Button { model.sendOrStop() } label: {
                    Image(systemName: model.isStreaming ? "stop.fill" : "arrow.up")
                        .frame(width: 18)
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(!model.isStreaming && !model.canSend)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityLabel(model.isStreaming ? L("停止生成") : L("发送"))
                .help(model.isStreaming ? L("停止生成") : L("发送 ⏎"))
            }
        }
        .font(.system(size: 14))
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(SettingsAppearance.color(SettingsAppearance.sidebar)))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(SettingsAppearance.color(SettingsAppearance.separator), lineWidth: SettingsAppearance.borderWidth))
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .padding(.top, 4)
    }
}

private final class ChatComposerState: ObservableObject {
    @Published var height: CGFloat = 52
    @Published var isComposing = false
}

/// 单条消息气泡：用户（右、纯文本+图片）/ 助手（左、Markdown）
private struct MessageBubble: View {
    let message: AIChatMessage
    let model: AIChatViewModel
    var streaming = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user { Spacer(minLength: 32) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                if !message.imageFiles.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 160), alignment: .leading)], alignment: .leading, spacing: 8) {
                        ForEach(message.imageFiles, id: \.self) { name in
                            if let cg = model.image(name) {
                                Image(nsImage: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: 160, maxHeight: 120)
                                    .background(SettingsAppearance.color(SettingsAppearance.control))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .onTapGesture { AIChatImageViewer.shared.show(cg) }
                            }
                        }
                    }
                }
                if !message.text.isEmpty {
                    if message.role == .assistant {
                        if streaming {
                            // Keep the live response in SwiftUI's layout system so each
                            // token immediately gets a visible, resize-safe text frame.
                            Text(message.text)
                                .font(.system(size: 14))
                                .lineSpacing(4)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            // Markdown view reports its intrinsic height after the stream ends.
                            MarkdownTextView(markdown: message.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        Text(message.text)
                            .textSelection(.enabled)
                            .font(.system(size: 14))
                            .foregroundStyle(SettingsAppearance.color(SettingsAppearance.text))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 10)
                                .fill(SettingsAppearance.color(SettingsAppearance.selection)))
                    }
                }
                if streaming {
                    HStack(spacing: 6) {
                        Circle().fill(SettingsAppearance.color(SettingsAppearance.focus)).frame(width: 5, height: 5)
                        Text(L("正在生成…"))
                            .font(SettingsAppearance.detailFont)
                            .foregroundStyle(SettingsAppearance.color(SettingsAppearance.secondary))
                    }
                    .padding(.top, 2)
                }
            }
            if message.role == .assistant { Spacer(minLength: 32) }
        }
    }
}

/// 只读 Markdown 文本视图（可选中、链接可点）。
/// 使用 SwiftUI 原生文本布局，避免 AppKit 文本视图在窗口调整尺寸时
/// 反复失效 intrinsic height，导致气泡闪烁或内容被裁掉。
struct MarkdownTextView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Markdown.blocks(markdown).enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let attributed):
                    // AttributedString keeps the Markdown renderer's fonts, colors,
                    // paragraph spacing, and links while letting SwiftUI recalculate
                    // the wrapped height atomically whenever the window width changes.
                    Text(AttributedString(attributed))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .table(let table):
                    MarkdownTableView(table: table)
                }
            }
        }
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A compact, wrapping table for GitHub-style Markdown table blocks.
private struct MarkdownTableView: View {
    let table: Markdown.Table

    var body: some View {
        VStack(spacing: 0) {
            row(table.header, isHeader: true)
            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, cells in
                row(cells, isHeader: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .stroke(SettingsAppearance.color(SettingsAppearance.border), lineWidth: 0.5))
    }

    @ViewBuilder
    private func row(_ cells: [NSAttributedString], isHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<table.columnCount, id: \.self) { column in
                let cell = column < cells.count ? cells[column] : NSAttributedString(string: "")
                let alignment = table.alignments[column]
                Text(AttributedString(cell))
                    .multilineTextAlignment(alignment.textAlignment)
                    .frame(maxWidth: .infinity, alignment: alignment.horizontalAlignment)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(isHeader
                        ? SettingsAppearance.color(SettingsAppearance.control)
                        : SettingsAppearance.color(SettingsAppearance.canvas))
                    .overlay(Rectangle()
                        .stroke(SettingsAppearance.color(SettingsAppearance.separator), lineWidth: 0.5))
            }
        }
    }
}

private extension Markdown.TableAlignment {
    var horizontalAlignment: Alignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}


/// 图片查看器：点击聊天里的图片弹出大图（悬浮窗，可缩放窗口）
@MainActor
final class AIChatImageViewer {
    static let shared = AIChatImageViewer()

    private var window: NSWindow?

    func show(_ image: CGImage, title: String = "") {
        NSApp.activate(ignoringOtherApps: true)
        window?.close()
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let width = min(screen.width * 0.6, max(320, CGFloat(image.width) + 48))
        let height = min(screen.height * 0.7, max(240, CGFloat(image.height) + 48))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = title.isEmpty ? L("图片") : title
        window.isReleasedWhenClosed = false
        WindowPresentation.configure(window)
        let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        imageView.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        window.contentView = imageView
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}

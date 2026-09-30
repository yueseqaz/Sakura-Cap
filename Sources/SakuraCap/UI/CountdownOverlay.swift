import AppKit
import SwiftUI

/// 3-2-1 倒计时覆盖层。倒计时期间 writer 未 arm，画面不落盘 → 倒计时不会出现在视频中。
@MainActor
enum CountdownCoordinator {
    static func run(seconds: Int, on screens: [NSScreen], shouldContinue: @escaping () -> Bool) async {
        guard !screens.isEmpty else { return }
        let model = CountdownModel()
        var windows: [NSWindow] = []
        for screen in screens {
            let window = CountdownWindow(screen: screen)
            window.contentView = NSHostingView(
                rootView: CountdownView(model: model)
                    .frame(width: screen.frame.width, height: screen.frame.height)
            )
            window.orderFrontRegardless()
            windows.append(window)
        }
        var remaining = seconds
        while remaining > 0 {
            guard shouldContinue() else { break }
            model.value = remaining
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            remaining -= 1
        }
        for window in windows { window.orderOut(nil) }
    }
}

@MainActor
final class CountdownModel: ObservableObject {
    @Published var value: Int = 0
}

final class CountdownWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        sharingType = .none // 双保险：倒计时层永不进入录制（writer 未 arm 之外再排除）
        hasShadow = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct CountdownView: View {
    @ObservedObject var model: CountdownModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.15)
            Text("\(max(model.value, 0))")
                .font(.system(size: 170, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 24)
                .id(model.value)
                .transition(.scale.combined(with: .opacity))
                .animation(.easeOut(duration: 0.3), value: model.value)
        }
    }
}

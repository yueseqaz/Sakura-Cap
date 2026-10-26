import AppKit
import SwiftUI

@MainActor
final class ChatScrollState: ObservableObject {
    var followsLatestMessage = true
    weak var scrollView: NSScrollView?
    private var pendingScroll: DispatchWorkItem?

    func scrollToLatest() {
        pendingScroll?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.followsLatestMessage,
                  let scroll = self.scrollView, let document = scroll.documentView else { return }
            let y = document.isFlipped
                ? max(document.bounds.minY, document.bounds.maxY - scroll.contentView.bounds.height)
                : document.bounds.minY
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        pendingScroll = work
        DispatchQueue.main.async(execute: work)
    }
}

/// Only user-driven scrolling changes follow mode; streaming layout must not.
struct ChatScrollTracking: NSViewRepresentable {
    let state: ChatScrollState
    var onFollowChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.state = state
        view.onFollowChange = onFollowChange
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onFollowChange = onFollowChange
    }

    final class TrackingView: NSView {
        weak var state: ChatScrollState?
        var onFollowChange: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard window != nil, let scrollView = enclosingScrollView else { return }
            state?.scrollView = scrollView
            for name in [NSScrollView.didLiveScrollNotification, NSScrollView.didEndLiveScrollNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: scrollView,
                                                                         queue: .main) { [weak self, weak scrollView] _ in
                    MainActor.assumeIsolated {
                        guard let scrollView, let document = scrollView.documentView else { return }
                        let visible = scrollView.documentVisibleRect
                        let gap = document.isFlipped ? document.bounds.maxY - visible.maxY
                            : visible.minY - document.bounds.minY
                        self?.onFollowChange?(gap <= 48)
                    }
                })
            }
            if let document = scrollView.documentView {
                document.postsFrameChangedNotifications = true
                observers.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification,
                                                                         object: document, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.state?.scrollToLatest() }
                })
            }
            state?.scrollToLatest()
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}

import Foundation
import CoreGraphics

/// 全局鼠标点击监听：CGEventTap listen-only（只听不改，不消费事件，对正常操作零干扰）。
/// 需要「输入监控」权限；创建失败（返回 nil）即为无权限。
final class ClickMonitor {
    var onLeftClick: (@MainActor (CGPoint) -> Void)?
    var onRightClick: (@MainActor (CGPoint) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isRunning = false

    @discardableResult
    func start() -> Bool {
        if eventTap != nil {
            isRunning = true
            return true
        }
        let mask = (CGEventMask(1) << CGEventType.leftMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.rightMouseDown.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .listenOnly, eventsOfInterest: mask,
                                          callback: clickTapCallback, userInfo: context),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            Log.indicator.error("创建 CGEventTap 失败（通常为缺少「输入监控」权限）")
            isRunning = false
            return false
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        isRunning = true
        Log.indicator.info("点击监听已启动")
        return true
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        isRunning = false
    }

    /// 事件回调挂在主 RunLoop 上，此处必然在主线程
    fileprivate func dispatch(type: CGEventType, event: CGEvent) {
        let location = event.location // CG 全局坐标（左上原点，pt）
        MainActor.assumeIsolated {
            switch type {
            case .leftMouseDown: onLeftClick?(location)
            case .rightMouseDown: onRightClick?(location)
            default: break
            }
        }
    }
}

private func clickTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let userInfo {
        let monitor = Unmanaged<ClickMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        monitor.dispatch(type: type, event: event)
    }
    return Unmanaged.passUnretained(event) // listen-only：原样放行
}

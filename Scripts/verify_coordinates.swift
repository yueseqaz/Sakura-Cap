// 坐标系换算验证脚本（零依赖，替代 XCTest：纯 CLT 工具链不含 XCTest）
// 运行: swift Scripts/verify_coordinates.swift
// 复刻 ScreenCoordinateKit 中两个纯函数的公式，任何改动请与源码同步修改。
import Foundation
import CoreGraphics

// ---- 与 ScreenCoordinateKit 保持一致的两个纯函数 ----
func appKitPoint(fromCG point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
    CGPoint(x: point.x, y: primaryHeight - point.y)
}

func sckSourceRect(fromAppKitLocalRect rect: CGRect, screenHeight: CGFloat) -> CGRect {
    CGRect(x: rect.minX, y: screenHeight - rect.maxY, width: rect.width, height: rect.height)
}

func appKitLocalRect(fromSCKRect rect: CGRect, screenHeight: CGFloat) -> CGRect {
    CGRect(x: rect.minX, y: screenHeight - rect.maxY, width: rect.width, height: rect.height)
}

// ---- 断言工具 ----
var passed = 0
func check(_ condition: Bool, _ name: String) {
    precondition(condition, "❌ 未通过: \(name)")
    passed += 1
    print("✅ \(name)")
}
func equal(_ a: CGFloat, _ b: CGFloat, _ name: String) {
    check(abs(a - b) < 0.001, name)
}

// 1. CG(左上) → AppKit(左下)：y 翻转
let p = appKitPoint(fromCG: CGPoint(x: 100, y: 40), primaryHeight: 1000)
equal(p.x, 100, "CG→AppKit: x 不变")
equal(p.y, 960, "CG→AppKit: y = 主屏高 - y")

// 2. 往返一致
let original = CGPoint(x: 300, y: 250)
let roundTrip = appKitPoint(fromCG: CGPoint(x: original.x, y: 1000 - original.y), primaryHeight: 1000)
equal(roundTrip.x, original.x, "往返: x")
equal(roundTrip.y, original.y, "往返: y")

// 3. AppKit 屏幕本地矩形 → SCK sourceRect（顶边对齐翻转）
let rect = CGRect(x: 20, y: 300, width: 400, height: 200) // y=300 是底边、顶边在 500
let sck = sckSourceRect(fromAppKitLocalRect: rect, screenHeight: 800)
equal(sck.minX, 20, "AppKit→SCK: x 不变")
equal(sck.minY, 300, "AppKit→SCK: minY = 屏高 - maxY = 800-500")
equal(sck.width, 400, "AppKit→SCK: 宽不变")
equal(sck.height, 200, "AppKit→SCK: 高不变")

// 4. 全屏区域在两套坐标下完全一致
let full = CGRect(x: 0, y: 0, width: 1440, height: 900)
check(sckSourceRect(fromAppKitLocalRect: full, screenHeight: 900) == full, "全屏矩形恒等")

// 5. 贴顶边的矩形 → SCK minY = 0
let top = CGRect(x: 10, y: 700, width: 200, height: 100) // 700+100=800=屏高
let sckTop = sckSourceRect(fromAppKitLocalRect: top, screenHeight: 800)
equal(sckTop.minY, 0, "贴顶边矩形 → SCK minY=0")
equal(sckTop.maxY, 100, "贴顶边矩形 → SCK maxY=100")

// 6. SCK 矩形 → AppKit 本地矩形：与 sckSourceRect 互逆（曾漏减一次 height 导致选区预览偏移）
let back = appKitLocalRect(fromSCKRect: sck, screenHeight: 800)
check(back == rect, "SCK→AppKit 本地: 与 sckSourceRect 互逆")
// 贴顶边矩形（screenHeight=800）→ AppKit y = 800 - 100 = 700
let backTop = appKitLocalRect(fromSCKRect: CGRect(x: 0, y: 0, width: 200, height: 100), screenHeight: 800)
equal(backTop.minY, 700, "SCK 贴顶边 → AppKit 本地 minY = 屏高 - 高")

print("\n共 \(passed) 项断言全部通过 ✅")

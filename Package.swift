// swift-tools-version:5.9
import PackageDescription

// Sakura-Cap：菜单栏极简录屏。零第三方依赖，仅系统框架。
let package = Package(
    name: "SakuraCap",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "SakuraCap",
            path: "Sources/SakuraCap"
        )
        // 注：坐标换算单测见 Scripts/verify_coordinates.swift（`swift Scripts/verify_coordinates.swift`）。
        // 纯 CLT 工具链不含 XCTest，无法使用 testTarget，故用零依赖断言脚本替代。
    ]
)

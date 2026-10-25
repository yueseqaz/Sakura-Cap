// swift-tools-version:5.9
import PackageDescription

// Sakura-Cap：系统框架 + 静态链接的内置 libwebp，不依赖用户安装命令行工具。
let package = Package(
    name: "SakuraCap",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SakuraCap", targets: ["SakuraCap"]),
        .library(name: "SakuraWebP", type: .static, targets: ["CWebP"])
    ],
    targets: [
        .target(
            name: "CWebP",
            path: "ThirdParty/libwebp",
            exclude: ["COPYING", "PATENTS", "AUTHORS", "README.sakura.md"],
            sources: ["src/dec", "src/dsp", "src/enc", "src/utils", "sharpyuv"],
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath("."), .define("WEBP_USE_THREAD")]
        ),
        .executableTarget(
            name: "SakuraCap",
            dependencies: ["CWebP"],
            path: "Sources/SakuraCap"
        )
        // 注：坐标换算单测见 Scripts/verify_coordinates.swift（`swift Scripts/verify_coordinates.swift`）。
        // 纯 CLT 工具链不含 XCTest，无法使用 testTarget，故用零依赖断言脚本替代。
    ]
)

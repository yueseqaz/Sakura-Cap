# 开发文档

面向开发者/维护者。README 只讲「这个项目是什么」，构建、权限、内部约定等放在这里。

## 构建与运行

```bash
./build.sh          # swift build -c release → 组装 .app → codesign
./run.sh            # 构建并启动；./run.sh --log 附带实时日志
./clean.sh          # 清理 .build 与 build
swift Scripts/verify_coordinates.swift   # 坐标换算断言（CLT 无 XCTest，用零依赖脚本）
./verify.sh [录像.mp4]                    # 用 ffprobe 校验输出文件的分辨率/码率/色彩标注
```

不使用 Xcode / Interface Builder / xcassets：Info.plist 由 `Config/Info.plist.template` 模板生成，图标由 `Resources/AppIcon.png`（1024×1024）经 `sips` + `iconutil` 生成；把自定义 PNG 放到该路径重新构建即可。

> 注意：纯 Command Line Tools 工具链下，SwiftUI 的宏（`@State` / `@StateObject`）以及 `AVKit` 的 SwiftUI `VideoPlayer` 都不可用（缺 `SwiftUIMacros` 插件 / `_AVKit_SwiftUI` 元数据会崩）。本项目一律用 AppKit（`NSViewRepresentable`、AppKit 控件、自绘 NSView）与 `@ObservedObject` 承载状态。

## 签名与 TCC 权限

`build.sh` 的签名策略由 `SIGN_IDENTITY` 控制：

- **默认 `auto`**：查找名字含 `sakura-cap` 的本地证书，找不到用 **ad-hoc（`codesign -s -`）**。
- **ad-hoc 的坑**：每次重编译 cdhash 都会变化，系统按「bundle id + 签名身份」记录的 TCC 授权随之失效——表现为再次弹权限框，或列表显示已授权但采集不到内容（如屏幕录制黑屏、输入监控收不到事件、摄像头不显示）。**每次重编译后如权限失效：重新授权，或重置后重来。**
- **推荐：本地自签证书**（钥匙串访问 → 证书助理 → 创建证书，名称如 `Sakura-Cap Dev`，类型「代码签名」，信任 → 代码签名 → 始终信任）。之后：
  ```bash
  SIGN_IDENTITY="Sakura-Cap Dev" ./build.sh
  ```
  bundle id 固定为 `com.sakura.sakuracap`，TCC 记录即可长期有效。

### 查看与重置 TCC 权限

```bash
# 查看（终端需先获得「完全磁盘访问」）
sqlite3 "$HOME/Library/Application Support/com.apple.TCC/TCC.db" \
  'select service, client, auth_value from access where client like "%sakuracap%"'

# 重置（务必带 bundle id！裸服务名会重置所有应用的该权限）
tccutil reset ScreenCapture com.sakura.sakuracap   # 屏幕录制
tccutil reset Microphone    com.sakura.sakuracap   # 麦克风
tccutil reset Camera        com.sakura.sakuracap   # 摄像头
tccutil reset ListenEvent   com.sakura.sakuracap   # 输入监控（点击标记 / 按键显示）
```

> 输入监控（ListenEvent）授权后通常需要**重启应用**才生效。

## 发版（Homebrew）

1. 改 `build.sh` 的 `VERSION`。
2. `./build.sh`，然后打包并发布：
   ```bash
   ZIP="Sakura-Cap-$VERSION.zip"
   ditto -c -k --keepParent build/Sakura-Cap.app "$ZIP"
   gh release create "v$VERSION" "$ZIP" --title "Sakura-Cap v$VERSION" --notes "..."
   shasum -a 256 "$ZIP"
   ```
3. 更新 `Casks/sakura-cap.rb` 的 `version` 与 `sha256`，提交推送。

## 调试

```bash
# 实时日志（统一 os.Logger，subsystem = com.sakura.sakuracap）
log stream --predicate 'process == "SakuraCap"' --level debug

# 崩溃日志：~/Library/Logs/DiagnosticReports/SakuraCap-*.ips（JSON 格式）
# 符号化（release 构建保留符号）：从 ips 的 binary images 段取 load 地址
atos -o build/Sakura-Cap.app/Contents/MacOS/SakuraCap -arch arm64 -l <loadAddress> <crashAddress>
```

## 画质管线约定（防发灰/发虚/雾蒙蒙）

1. **采集**：`pixelFormat = BGRA`（全范围 RGB 直采）+ `colorSpaceName` 显式指定（设置可选 sRGB / Display P3；实测 BGRA 不指定色彩空间会录出全黑）。
2. **编码标注**：`AVVideoCompressionPropertiesKey` 必含 `AVVideoColorPropertiesKey`（primaries / transfer / YCbCr matrix = ITU_R_709_2 三项齐全）——缺失时播放器自行猜测 4:2:0 的矩阵与范围，表现为发灰发雾。
3. **原生分辨率**：`captureResolution = .best`，让 SCK 以显示器原生像素采样；输出尺寸 = 点值 × `SCContentFilter.pointPixelScale`；宽高强制偶数（4:2:0 要求）。
4. **输出分辨率**：仅等比缩小、不放大；全屏模式直接让 SCK 输出目标尺寸，区域模式原生采集后裁剪再缩放到目标尺寸。
5. **码率**：像素 × 帧率 × bpp，档位见 `RecordingModels.VideoQuality`；60fps 按 1.5× 权重；H.264 High Profile；GOP = 2s。
6. **自检**：`./verify.sh` 用 ffprobe 校验输出文件；对比方法：同一画面用系统 ⌘⇧5 与 Sakura-Cap 各录一段，QuickTime 逐帧对比文字边缘。

## 已知坑与设计对策

1. **ad-hoc 重编译 → TCC 失效**：见上文自签证书方案。
2. **多套坐标系**（AppKit 左下 / CG 全局左上 / SCK 左上原点，另有像素维度）：全部收口在 `Platform/ScreenCoordinateKit.swift`，配套 `Scripts/verify_coordinates.swift` 断言；副屏在主屏左侧时全局原点为负，跨屏运算只在 CG 全局空间进行。
3. **不设置 `sourceRect`**：全屏模式不传 `sourceRect`，区域模式原生采集整屏后由 `StreamSession` 用 Core Image 按像素裁剪 + 缩放，规避不同 macOS 对 `sourceRect` 单位解释的差异。
4. **`CIContext.render(_:to:)` 不缩放**：它只做 1:1 渲染并裁掉超出部分。裁剪后需把 extent 原点平移回 (0,0)，缩放需显式 `transformed(by:)`，否则画面错位/全黑。
5. **Retina / 混合 DPI**：输出缓冲用「像素」，按每屏 `pointPixelScale` 独立推导。
6. **音画同步**：SCK 的视频与音频样本同源于 hostTimeClock，天然同轴；writer `startSession(atSourceTime:)` 锚在最早样本，起点之前的样本丢弃。
7. **暂停/继续的时间轴**：暂停期间丢帧，续录时按视频 PTS 间隔累加偏移，并用 `CMSampleBufferCreateCopyWithNewTiming` 重定时，把暂停时段从时间轴剔除。
8. **覆盖层与录制**：`sharingType = .none` 的窗口不进录制（面板 / 选区 / 倒计时 / HUD）；点击标记、按键显示、摄像头画中画保持 `.readOnly`（会被录进画面）。倒计时「不入视频」另由「writer 未 arm 前全部丢帧」保证。
9. **崩溃时 MP4 未 finalize 不可播放**：处理了应用正常退出（`willTerminateNotification` 同步尽力收尾，最多等 2s）；硬崩溃仍会丢文件，属已知限制。
10. **AVAssetWriter 轨道必须预建**：`startWriting()` 之后再 `addInput` 会抛 NSException 闪退；音轨在创建 `FileWriter` 时全部建好，麦克风先 `start()` 拿到实测格式再建 writer。
11. **长录制内存**：`queueDepth` + `isReadyForMoreMediaData` 背压（过载直接丢帧，绝不排队堆积）；`SCFrameStatus != .complete` 的 idle 帧跳过。
12. **CLT 工具链限制**：见上文「构建与运行」的注意点。

## 目录结构

```
SakuraCap/
├── Package.swift / build.sh / run.sh / clean.sh / verify.sh
├── Casks/       sakura-cap.rb（Homebrew Cask）
├── Config/      Info.plist.template, SakuraCap.entitlements
├── Scripts/     make_default_icon.swift, verify_coordinates.swift
├── Resources/   AppIcon.png
└── Sources/SakuraCap/
    ├── main.swift, Main/AppDelegate.swift
    ├── UI/          PanelView/ViewModel, StatusItemController, RecordingHUD,
    │                AboutWindow, HotKeyRecorder, RegionSelection/, CountdownOverlay
    ├── Editor/      TrimWindow（裁剪：时间轴 + 预览 + 导出）
    ├── Capture/     RecordingController, StreamSession, StreamPlanner, FileWriter, MicCapture
    ├── Camera/      CameraPiP（摄像头画中画）
    ├── ClickIndicator/  ClickMonitor(CGEventTap), IndicatorEngine, IndicatorWindow
    ├── KeyDisplay/  KeyboardMonitor(CGEventTap), KeyDisplay
    ├── Platform/    ScreenCoordinateKit, RecordingTarget, DisplayCatalog,
    │                PermissionCenter, HotKeyManager(Carbon), ScreenChangeMonitor
    ├── Model/       AppSettings, RecordingModels, DisplayInfo
    └── Support/     Logger, CompletionNotifier, OutputDirectoryPicker, SoundCue,
                     FocusMode, AppInfo
```

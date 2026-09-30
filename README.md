# Sakura-Cap

菜单栏常驻的极简 Mac 录屏工具。启动快、占用低、2 步内开始录制（点状态栏 → 开始，或直接按 ⌘⇧R）。

- **技术栈**：Swift 5.9 + SwiftUI（必要处 AppKit）；采集 ScreenCaptureKit（SCStream）；编码 AVFoundation（AVAssetWriter，H.264 / HEVC 可选）；输出 MP4
- **零第三方依赖**，仅系统框架；**纯 Command Line Tools 构建**，全程无 .xcodeproj
- **最低系统**：macOS 13
- **体积**：约 2.2MB（二进制 1.1MB）

## 功能（MVP）

| 功能 | 说明 |
|---|---|
| 菜单栏图标 | 无 Dock 图标（LSUIElement）；点击弹菜单：**开始录制（全屏录制 / 框选区域）**、设置…、退出；录制中图标变红并显示 `mm:ss` 计时 |
| 可视化选择 | 「全屏录制」：悬停哪块屏哪块屏蓝框高亮，单击即录该屏；「框选区域」：拖拽蓝框框选（不跨屏，实时尺寸），松手即录；Esc 取消 |
| 录制模式 | 屏幕（单屏 / 所有显示器并行各存一个文件）、自定义区域；设置中可为快捷键快捷启动预选默认模式 |
| 音频 | 系统声音、麦克风可分别开关，各自独立 AAC 音轨写入同一 MP4 |
| 鼠标点击指示 | 默认关闭；开启后左键（可选右键）出现扩散圆环/指向箭头，样式、颜色、大小、时长可配置并持久化；需要「输入监控」权限，缺失时录制不受影响 |
| 全局快捷键 | 默认 ⌘⇧R 开始/停止（按设置中的默认模式直接开录，跳过选择），可在设置中录制自定义组合 |
| 悬浮控制条 | 录制中在屏幕（默认右上角，可拖动、位置自动记忆）出现迷你控制条：计时、暂停/继续、停止；本身 `sharingType = .none`，不会进入录像 |
| 暂停 / 继续 | 录制中可暂停与继续；暂停时段从时间轴剔除（输出无缝、不留静帧），音画同步保持；菜单栏图标与 HUD 同步反映暂停态 |
| 键盘按键显示 | 可选（默认关）；开启后在**录制区域左下角**浮出所按按键（如 ⌘⇧R、Space、方向键），约 1 秒后淡出；跟随当前键盘布局；需「输入监控」权限，缺失时录制不受影响 |
| 开始/结束提示音 | 可选（默认开）；录制正式开始与结束时播放系统提示音。因采集端开启 `excludesCurrentProcessAudio`，提示音不会被录进视频 |
| 开机自启 | 设置-通用中开关「开机时自动启动」，走系统登录项（`SMAppService`），首次可能需在系统设置→通用→登录项中允许 |
| 倒计时 | 开始前 3 秒（可关闭），倒计时**不会**录入视频 |
| 输出 | 目录必须由用户首次选择并记住；文件名 `SakuraCap yyyy-MM-dd HH.mm.ss.mp4`；完成后系统通知，可一键在 Finder 中显示 |
| 权限引导 | 屏幕录制 / 麦克风 / 输入监控缺失时给出卡片或弹窗提示并可跳转系统设置 |
| 热插拔 | 录制中拔掉显示器：该路流优雅停止、已录内容照常保存并通知 |

## 构建与运行

```bash
./build.sh          # swift build -c release → 组装 .app → codesign
./run.sh            # 构建并启动；./run.sh --log 附带实时日志
./clean.sh          # 清理 .build 与 build
swift Scripts/verify_coordinates.swift   # 坐标换算断言（CLT 无 XCTest，用零依赖脚本）
```

不使用 Xcode / Interface Builder / xcassets：Info.plist 由 `Config/Info.plist.template` 模板生成，图标默认由 `Scripts/make_default_icon.swift` 代码绘制；想用自定义图标，把 1024×1024 PNG 放到 `Resources/AppIcon.png` 重新构建即可（当前附带的参考图 `Resources/attached-icon-reference.png` 是通用 PNG 占位图，如需启用：`cp Resources/attached-icon-reference.png Resources/AppIcon.png && ./build.sh`）。

## 签名与 TCC 权限（重点）

`build.sh` 的签名策略由 `SIGN_IDENTITY` 控制：

- **默认 `auto`**：查找名字含 `sakura-cap` 的本地证书，找不到用 **ad-hoc（`codesign -s -`）**。
- **ad-hoc 的坑**：每次重编译 cdhash 都会变化，系统按「bundle id + 签名身份」记录的 TCC 授权随之失效——表现为再次弹权限框，或列表显示已授权但录制黑屏。**每次重编译后如权限失效：重新授权，或重置后重来。**
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
tccutil reset ListenEvent   com.sakura.sakuracap   # 输入监控（点击指示）
tccutil reset Accessibility com.sakura.sakuracap   # 辅助功能（本应用未用，备用）
```

> 输入监控（ListenEvent）授权后通常需要**重启应用**才生效。

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
3. **1:1 分辨率**：`sourceRect` 与缓冲尺寸以物理像素表达 = 点值 × `SCContentFilter.pointPixelScale`（macOS 14+，回退该屏 `backingScaleFactor`）；每路流独立换算；宽高强制偶数（4:2:0 要求）。
4. **码率**：像素 × 帧率 × bpp，档位 高(0.15/0.09)/中(0.09/0.055)/低(0.05/0.03)/自定义；60fps 按 1.5× 权重；H.264 High Profile；GOP = 2s。
5. **自检**：`./verify.sh [录像.mp4]`（自动找最新录像）用 ffprobe 校验分辨率/码率/pix_fmt/色彩三元组非 unknown。
   对比方法：同一画面用系统 ⌘⇧5 与 Sakura-Cap 各录一段，QuickTime 逐帧对比文字边缘；若 QuickTime 里 Sakura-Cap 的文件清晰而其他播放器发灰，是播放器对色彩标注的解释问题而非编码问题。

## 已知坑与设计对策

1. **ad-hoc 重编译 → TCC 失效**：见上文自签证书方案。
2. **三套坐标系**（AppKit 左下 / CG 全局左上 / SCK filter 左上原点，另有像素维度）：全部收口在 `Platform/ScreenCoordinateKit.swift`，配套 `Scripts/verify_coordinates.swift` 断言；副屏在主屏左侧时全局原点为负，跨屏运算只在 CG 全局空间进行。
3. **`sourceRect` 的单位按「像素」解释（macOS 27 实测）**：传「点」值只会抓到 Retina 屏左上角 1/4 画面再拉伸成视频（表现为”只有一小块区域”且模糊）。对策：全屏与窗口模式**不设置 sourceRect**（默认抓全部内容，规避歧义）；区域模式把框选的点值 × `backingScaleFactor` 换算成像素再传。
4. **色彩保真**：`pixelFormat = BGRA` 直采 + `colorSpaceName = sRGB`（14+），避免默认 YCbCr 采样路径的色偏；码率 H.264 ≈0.09bpp。
5. **Retina / 混合 DPI**：输出缓冲用「像素」，按每屏 `backingScaleFactor` 独立推导；窗口跨屏导致 DPI 变化时，缓冲尺寸在开始时钉死、由 SCK 缩放适配（轻微重采样，不崩溃）。
6. **音画同步**：SCK 的视频与音频样本同源于 hostTimeClock，天然同轴；writer `startSession(atSourceTime:)` 锚在最早样本，起点之前的样本丢弃。系统音与麦克风各自独立轨道，互不校时。
7. **覆盖层被排除出录制**：`sharingType = .none` 的窗口和进入 `excludingWindows` 列表的窗口都录不进去。本应用约定：面板/选区/倒计时窗口一律 `.none`（不出现视频中）；点击指示窗口保持 `.readOnly`（NSWindow 默认值，可被 SCK 读取；macOS 27 SDK 已移除 `.shared`，SCK 采集只需读权限）。倒计时”不入视频”由「writer 未 arm 前全部丢帧」保证。
8. **崩溃时 MP4 未 finalize 不可播放**：处理了应用正常退出（`willTerminateNotification` 同步尽力收尾，最多等 2s）；硬崩溃仍会丢文件，属已知限制。
9. **AVAssetWriter 轨道必须预建**：`startWriting()` 之后再 `addInput` 会抛 NSException 闪退。因此音轨在创建 FileWriter 时全部建好——系统音用配置值（48k/2ch），麦克风先 `start()` 等首个样本拿到实测格式再建 writer；`appendAudio` 收到未预建的轨道直接丢弃。
10. **长录制内存**：`queueDepth=6` + `isReadyForMoreMediaData` 背压（过载直接丢帧，绝不排队堆积）；`SCFrameStatus != .complete` 的 idle 帧跳过，静止画面不重复编码。
11. **无麦克风/静音设备**：自动降级为无麦克风音轨并提示，录制不中断。
12. **多实例**：启动时检测同 bundle id 实例，激活已存在实例后退出。
13. **窗口录制已移除**：`desktopIndependentWindow` 过滤器在部分系统/内容组合下不稳定（曾伴随编码会话异常），且桌面壁纸窗口会污染悬停命中；产品决策聚焦全屏与区域两条路径，相关代码已清理（如需恢复参考 git 历史思路：候选窗口须排除 Finder 桌面窗口与非法 frame）。

## 非 MVP（仅预留接口）

暂停/继续、悬浮控制条、开机自启、键盘按键显示、提示音已实现；GIF 导出、简单裁剪仍未实现：`RecordingController`/`FileWriter` 结构已预留扩展点。

## 目录结构

```
SakuraCap/
├── Package.swift / build.sh / run.sh / clean.sh
├── Config/Info.plist.template, SakuraCap.entitlements
├── Scripts/  make_default_icon.swift, verify_coordinates.swift
├── Resources/  AppIcon.png（默认代码绘制生成）
└── Sources/SakuraCap/
    ├── main.swift, Main/AppDelegate.swift
    ├── UI/        PanelView/ViewModel, StatusItemController, HotKeyRecorder,
    │              RegionSelection/, CountdownOverlay
    ├── Capture/   RecordingController, StreamSession, StreamPlanner, FileWriter, MicCapture
    ├── ClickIndicator/  ClickMonitor(CGEventTap), IndicatorEngine, IndicatorWindow
    ├── Platform/  ScreenCoordinateKit, DisplayCatalog, PermissionCenter,
    │              HotKeyManager(Carbon), ScreenChangeMonitor
    ├── Model/     AppSettings, RecordingModels, DisplayInfo
    └── Support/   Logger, CompletionNotifier, OutputDirectoryPicker
```

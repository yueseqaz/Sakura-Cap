# 开发文档

面向开发者/维护者。README 只讲「这个项目是什么」，构建、权限、内部约定等放在这里。

## 构建与运行

```bash
./build.sh          # swift build -c release → 组装 .app → codesign；版本号默认读 Casks 里的已发布版本
./run.sh            # 构建并启动；./run.sh --log 附带实时日志
./Scripts/package_dmg.sh   # 打包已有 .app → build/Sakura-Cap-版本.dmg；不重编译、不重启应用
./Scripts/verify_dmg.sh build/Sakura-Cap-版本.dmg  # 挂载、布局、签名及自动更新兼容性回归
./clean.sh          # 清理 .build 与 build
swift Scripts/verify_coordinates.swift   # 坐标换算断言（CLT 无 XCTest，用零依赖脚本）
bash Scripts/verify_inline_screenshot.sh # 截图标注：设置、工具对齐、选框/缩放/裁剪撤销、像素导出及两种界面生命周期回归
./verify.sh [录像.mp4]                    # 用 ffprobe 校验输出文件的分辨率/码率/色彩标注
```

版本号来源优先级：`VERSION` 环境变量 > `Casks/sakura-cap.rb` 的 `version` > 兜底 `2.0.0`——本地构建自动跟随已发版本，不再停留在 2.0.0。

### 官网

GitHub Pages 从 `main` 的 `docs/` 发布。`docs/index.html` 为中文入口，`docs/en.html` 为英文入口，
通过导航栏语言链接切换；两者共用 `site.css`、`site.js` 和界面截图，无框架或新增运行依赖。
更新文案时同步维护两种语言；截图来源与隐私检查要求见 `docs/assets/screenshots/README.md`。

```bash
python3 -m http.server 8819 --bind 127.0.0.1 --directory docs
python3 Scripts/verify_website.py
node --check docs/site.js
```

网站检查涵盖双语结构、内部链接、图片属性、标签页关系及 WebP 隐私元数据，并纳入 CI。

不使用 Xcode / Interface Builder / xcassets：Info.plist 由 `Config/Info.plist.template` 模板生成，图标由 `Resources/AppIcon.png`（1024×1024）经 `sips` + `iconutil` 生成；把自定义 PNG 放到该路径重新构建即可。

### 截图标注模式

- `AppSettings.screenshotAnnotationMode` 持久化为 `window` / `inline`，未设置时默认 `window`，保留独立标注窗口流程。
- 菜单和快捷键共用的截图入口仅在原地模式下交给 `InlineScreenshotController`；OCR、翻译、滚动截图、图片文件编辑不变。
- 原地模式先捕获所有显示器，再显示冻结覆盖层。画布复用 `AnnotationCanvas`，标注保留在整屏图片像素坐标中；调整选框只改变导出范围，不移动标注或重新截图。
- `调整选区` 用于移动整个选框；边缘及八个控制点始终可拖动。Command-C 复制、Enter / Command-S 保存、Tab 临时隐藏工具、Esc 先取消取色/测量/识别，再退出截图；保存目录对话框取消时返回当前冻结画面，显示器配置变化时结束会话。
- 原地与独立窗口共用 `AnnotationEditorActions`（取色、测量、OCR/二维码、翻译、AI、上传、复制、保存、定住）。独立窗口的外观和默认入口保持不变。
- 原地界面使用屏幕底部主工具栏、右侧快捷栏与按工具显示的属性条；工具栏可拖动，选框调整不会带着它移动。窄屏使用两行紧凑排布。
- 选框持久化为原始图片像素坐标，通过画布变换投影到屏幕，支持缩放/平移。原地裁剪只变更导出区域，并进入画布撤销栈，不破坏冻结底图或移动标注；手动调整选框不进入标注撤销栈。只导出选框内的原始像素与标注，不含遮罩、边框或工具栏。
- 系统对话框临时隐藏覆盖层并在取消时恢复；AI/翻译结果展示前降低冻结画面层级，保留编辑状态；异步识别在会话关闭或换屏后不再写剪贴板或打开结果。

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

发版已全自动化（`.github/workflows/release.yml`，打 tag 触发）：

1. 确认改动已合入 `main`（CI 门禁通过）。
2. 写 `ReleaseNotes/<版本>.md`（将作为 Release 正文），提交推送，提交信息惯例 `docs: x.x.x 发版说明`。
3. 打**轻量 tag**（不要 annotated）并推送：
   ```bash
   git tag v2.5.0 && git push origin v2.5.0
   ```
4. 流水线自动完成：构建 `.app` → 制作 DMG 并验证 → 创建 GitHub Release（正文取 ReleaseNotes，仅发布 DMG 及 sha256）→ 同时更新 `Casks/sakura-cap.rb` 的 `version` / `sha256` 并以 bot 提交推回 `main`。
5. 本地 `git pull --ff-only origin main` 同步即可；之后本地构建的版本号自动跟上。

### DMG 布局与更新

- `Resources/DMG/background.png` 是维护者提供的 1100×602 原图，完整保留图内署名；发布前请确认拥有再分发权限。`安装前必看.txt` 随 DMG 放在根目录。
- 打包使用系统 `hdiutil`，通过 `Scripts/dmg_layout.py` 写 Finder `.DS_Store`，不需要启动 Finder，适合 CI。仅打包工具需要 Python 3，首次在 `.build/dmg-tools` 创建隔离环境并安装 `Scripts/dmg-requirements.txt` 中固定版本的依赖；可通过 `DMG_PYTHON` 指定已安装依赖的 Python。
- 安装窗口约 780×480，背景按原比例显示为 770×421.4。使用 TIFF DPI 元数据控制显示尺寸，不裁剪、不重采样原图；素材放进应用包并参与签名，DMG 根目录无 `.background` 文件夹，即使显示隐藏文件也只出现应用、Applications 和说明文件三个项目（Finder 自身的 `.DS_Store` 除外）。
- 本地如不希望覆盖正在运行的构建，可用 `BUILD_DIR=build/dmg-source ./build.sh`，然后 `./Scripts/package_dmg.sh build/dmg-source/Sakura-Cap.app`。
- 自动更新仅支持 DMG，校验 sha256 后只读挂载、验证应用标识/版本/签名、暂存到原应用旁，然后卸载；不再选择或解压 ZIP。
- 后续版本不再发布兼容 ZIP；仅支持 ZIP 更新的旧版需要从发布页手动下载 DMG 安装一次，不应跳过哈希校验。
- Cask 固定使用 DMG 下载地址，不要填入本地试打包的校验值；由 tag 发布流水线同步更新版本和校验值。
- DMG 不等于 Apple 公证，当前签名策略与 TCC 授权行为不变。说明文件仅提供应用级隔离标记处理，不全局关闭 Gatekeeper，也不内置自动执行的修复脚本。

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
2. **多套坐标系**（AppKit 左下 / CG 全局左上 / SCK 左上原点，另有像素维度）：全部收口在 `Platform/ScreenCoordinateKit.swift`，配套 `Scripts/verify_coordinates.swift` 断言（脚本是源码公式的复刻，两侧必须同步改；CI 会在每次 push/PR 自动跑它，见 `.github/workflows/ci.yml`）；副屏在主屏左侧时全局原点为负，跨屏运算只在 CG 全局空间进行。
3. **不设置 `sourceRect`**：全屏模式不传 `sourceRect`，区域模式原生采集整屏后由 `StreamSession` 用 Core Image 按像素裁剪 + 缩放，规避不同 macOS 对 `sourceRect` 单位解释的差异。
4. **`CIContext.render(_:to:)` 不缩放**：它只做 1:1 渲染并裁掉超出部分。裁剪后需把 extent 原点平移回 (0,0)，缩放需显式 `transformed(by:)`，否则画面错位/全黑。
5. **Retina / 混合 DPI**：输出缓冲用「像素」，按每屏 `pointPixelScale` 独立推导。
6. **音画同步**：SCK 的视频与音频样本同源于 hostTimeClock，天然同轴；writer `startSession(atSourceTime:)` 锚在最早样本，起点之前的样本丢弃。
7. **暂停/继续的时间轴**：暂停期间丢帧，续录时按视频 PTS 间隔累加偏移，并用 `CMSampleBufferCreateCopyWithNewTiming` 重定时，把暂停时段从时间轴剔除。
8. **覆盖层与录制**：只有录制 HUD 使用 `sharingType = .none`，不进入录屏、截图或远程共享；其余可见窗口使用 `.readOnly`。截图选择层在采集前撤下，倒计时在 writer arm 前结束。注意：**SCK 的显示器采集不理会 `sharingType = .none`**（探针实测：声明 .none 的窗口照样进画面）；长截图的控制条/预览靠 `SCContentFilter(excludingWindows:)` 排除（实测有效）+ 物理避开选区双保险。另一个坑：`SCShareableContent` 的窗口列表**滞后**于刚 `orderFront` 的窗口，太早建过滤器会拿到空排除列表且被缓存——`ScrollingCapture.prepareCapture` 会重试等到控制窗注册完成再缓存。
9. **崩溃时 MP4 未 finalize 不可播放**：处理了应用正常退出（`willTerminateNotification` 同步尽力收尾，最多等 2s）；硬崩溃仍会丢文件，属已知限制。
10. **AVAssetWriter 轨道必须预建**：`startWriting()` 之后再 `addInput` 会抛 NSException 闪退；音轨在创建 `FileWriter` 时全部建好，麦克风先 `start()` 拿到实测格式再建 writer。
11. **长录制内存**：`queueDepth` + `isReadyForMoreMediaData` 背压（过载直接丢帧，绝不排队堆积）；`SCFrameStatus != .complete` 的 idle 帧跳过。
12. **CLT 工具链限制**：见上文「构建与运行」的注意点。
13. **API Key 脱敏存 UserDefaults（base64）**：翻译/AI 的 API Key 以 base64 编码存 UserDefaults（键 `translateAPIKey.b64` / `translateCustomAPIKey.b64`；脱敏 ≠ 加密，防的是偏好文件/备份里直接读到明文）。≤2.3.0 的旧明文键在启动时自动迁移。2.4.0–2.4.1 曾用 Keychain，因 ad-hoc 签名每次构建都变、访问旧条目频繁弹授权框而移除——那两个版本写入 Keychain 的值不再读取，受影响用户需重填一次。
14. **更新器强制 sha256**：自动更新要求 Release 资产带 `sha256:` 摘要（GitHub API 的 `digest` 字段）。被限流走的重定向回退路径拿不到摘要时会拒绝自动安装、引导手动下载——这是有意为之（ad-hoc 签名无法 pin 开发者身份，摘要是唯一强校验）。
15. **框选与焦点**：选区覆盖层必须 `NSApp.activate` 才能接收鼠标事件，但框选结束时若不归还激活态，系统会把应用自己的窗口（更新弹窗、菜单面板）顶到用户正在操作的页面前。`SelectionController.restoreFocusIfNeeded()` 在每次框选结束（含 Esc 取消）后 `NSApp.deactivate` + 必要时轻推原应用；后续真正需要用户注意的窗口（编辑器/结果窗）各自 `NSApp.activate`，互不冲突。
16. **麦克风权限按需申请**：不要在启动或面板出现时 `requestAccess`（抢跑弹 TCC 框还会顶掉菜单）。只在两处申请：开录且勾选麦克风（`RecordingController.startMicrophoneAndGetFormat`，拒绝则本次无麦克风继续录）与用户主动打开麦克风开关。
17. **长截图拼接匹配**：Retina 滚动落点几乎必为非整数像素，逐像素直接比对会把半像素位移误判成「没滚动」（2.4.x 自动手动全失败的根因）。现流程：60 列灰度 → 纵向 5-tap 均值模糊（洗亚像素差）→ 逐行打分取**截尾均值**（去最差 25% 行，抗固定顶栏/懒加载）→ 接受条件 `shift ≥ 3` 且 `score ≤ 10` 或 `score < score0/2`（score0 = shift 0 静止基线）。调试看 `log stream --predicate 'process == "SakuraCap"' --level debug` 的 `长截图匹配` 行。

## 本地化

- 支持语言：中文（源语言）+ English。
- SwiftUI 的 `Text` / `Button` / `Toggle` / `Label` / `Picker` 以及 `card()` / `permissionCard()` 用字符串**字面量**时，会自动按 `LocalizedStringKey` 本地化，无需改动。
- 其它作为 `String` 使用的文案（菜单项、弹窗、枚举 `label`、banner 等）用 `L("中文")`（见 `Support/Localization.swift`）。
- 翻译文件在 `Resources/<lang>.lproj/Localizable.strings`，**key 就是中文原文**；`build.sh` 会把 `*.lproj` 拷进 `.app/Contents/Resources/`。
- 新增语言：加 `Resources/xx.lproj/Localizable.strings`（拷贝一份 en 的改值），并把语言代码加进 `Config/Info.plist.template` 的 `CFBundleLocalizations`。

## 目录结构

```
SakuraCap/
├── Package.swift / build.sh / run.sh / clean.sh / verify.sh
├── Casks/        sakura-cap.rb（Homebrew Cask，发版流水线自动升 version/sha256）
├── Config/       Info.plist.template, SakuraCap.entitlements
├── ReleaseNotes/ 各版本发布说明（发版时作为 GitHub Release 正文）
├── Scripts/      make_default_icon.swift, verify_coordinates.swift
├── Resources/    AppIcon.png, en.lproj / zh-Hans.lproj 本地化
└── Sources/SakuraCap/
    ├── main.swift
    ├── Main/         AppDelegate, CaptureIntentCoordinator（选区结果按用途路由）
    ├── UI/           PanelView/ViewModel, StatusItemController, RecordingHUD, AudioHUD,
    │                 RegionSelection/（SelectionController 选区覆盖层）, OnboardingWindow,
    │                 UpdateReleaseWindow, CompareWindow, TranslationWindow,
    │                 HotKeyRecorder, CountdownOverlay, FPSOverlay, SettingsAppearance
    ├── Screenshot/   ScreenshotController（截图/OCR/二维码/对比入口）, ScrollingCapture（长截图）
    ├── Editor/       Workbench（视频工作台/裁剪）, VideoAnnotation
    ├── Capture/      RecordingController, StreamSession, StreamPlanner, FileWriter, MicCapture
    ├── Annotation/   AnnotationEditor, AnnotationCanvas, PinnedImage（定住）, ScreenAnnotation
    ├── OCR/          OCR, Barcode
    ├── AI/           AIChatWindow/Client/Models/History, Markdown, AIChatPresenter
    ├── Audio/        AudioRecorder, AudioEditorWindow/Views
    ├── Camera/       CameraPiP（摄像头画中画）
    ├── ClickIndicator/  ClickMonitor(CGEventTap), IndicatorEngine, IndicatorWindow
    ├── KeyDisplay/   KeyboardMonitor(CGEventTap), KeyDisplay
    ├── Platform/     ScreenCoordinateKit, RecordingTarget, DisplayCatalog,
    │                 PermissionCenter, HotKeyManager(Carbon), ScreenChangeMonitor
    ├── Model/        AppSettings, RecordingModels, DisplayInfo
    └── Support/      Logger, Localization, UpdateChecker/Installer, Toast, ModalAlert,
                      CompletionNotifier, OutputDirectoryPicker, SoundCue, FocusMode, AppInfo,
                      FileName, CaptureDevices, TranslationService
```

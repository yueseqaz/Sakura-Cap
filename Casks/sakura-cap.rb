cask "sakura-cap" do
  version "1.4.3"
  sha256 "fee70794ebe872857b3c9a2b7c4e34a5a749c2419acb46796a09328ada1544f2"

  url "https://github.com/yueseqaz/Sakura-Cap/releases/download/v#{version}/Sakura-Cap-#{version}.zip"
  name "Sakura-Cap"
  desc "菜单栏极简录屏 / 截图 / 标注工具"
  homepage "https://github.com/yueseqaz/Sakura-Cap"

  app "Sakura-Cap.app"

  caveats <<~EOS
    Sakura-Cap 是菜单栏应用（无 Dock 图标），启动后点菜单栏图标即可使用。
    首次使用请在「系统设置 → 隐私与安全性」中按需授权：
      · 屏幕录制（必需）
      · 麦克风 / 摄像头 / 输入监控（按需，用于声音、摄像头画中画、点击标记）
  EOS
end

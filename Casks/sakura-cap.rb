cask "sakura-cap" do
  version "2.9.7"
  sha256 "b6bdc952cf7c4dc0bf6575ae99d9e9f83431e3176a365adec2367a812f2251c6"

  url "https://github.com/yueseqaz/Sakura-Cap/releases/download/v#{version}/Sakura-Cap-#{version}.dmg"
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

cask "sakura-cap" do
  version "2.9.6"
  sha256 "9343d25070807c467d736b4fa6d710298d8b30a6e73e888dc007b9810d78b579"

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

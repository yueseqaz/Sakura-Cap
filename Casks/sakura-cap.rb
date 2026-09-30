cask "sakura-cap" do
  version "0.1.0"
  sha256 "0000afc50f94e5662275705377556b2c87b9228ff7c39bc3e7081a7d3cbd45e3"

  url "https://github.com/yueseqaz/Sakura-Cap/releases/download/v#{version}/Sakura-Cap-#{version}.zip"
  name "Sakura-Cap"
  desc "菜单栏极简录屏工具（全屏 / 区域）"
  homepage "https://github.com/yueseqaz/Sakura-Cap"

  app "Sakura-Cap.app"

  caveats <<~EOS
    Sakura-Cap 是菜单栏应用（无 Dock 图标），启动后点菜单栏图标即可使用。
    首次使用请在「系统设置 → 隐私与安全性」中按需授权：
      · 屏幕录制（必需）
      · 麦克风 / 摄像头 / 输入监控（按需，用于声音、摄像头画中画、点击标记）
  EOS
end

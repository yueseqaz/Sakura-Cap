import AppKit

/// 录制开始/结束提示音。
/// 提示音由本进程播放，而采集端设置了 `excludesCurrentProcessAudio`，
/// 因此不会被录进视频（系统里其他 App 的声音仍会正常采集）。
enum SoundCue {
    static func playStart() { play("Tink") }
    static func playStop() { play("Glass") }

    private static func play(_ name: String) {
        guard AppSettings.shared.soundEnabled else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}

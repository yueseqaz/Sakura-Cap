import AVFoundation

/// 采集设备枚举（麦克风 / 摄像头），供设置与 HUD 选择。
enum CaptureDevices {
    static func microphones() -> [AVCaptureDevice] {
        if #available(macOS 14.0, *) {
            return AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external],
                                                    mediaType: .audio, position: .unspecified).devices
        } else {
            return AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInMicrophone, .externalUnknown],
                                                    mediaType: .audio, position: .unspecified).devices
        }
    }

    static func cameras() -> [AVCaptureDevice] {
        if #available(macOS 14.0, *) {
            return AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external],
                                                    mediaType: .video, position: .unspecified).devices
        } else {
            return AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
                                                    mediaType: .video, position: .unspecified).devices
        }
    }
}

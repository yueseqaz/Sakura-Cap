import AVFoundation
import os

/// 麦克风采集：AVCaptureSession + AVCaptureAudioDataOutput，直接产出 CMSampleBuffer。
/// 先 start() 拿到首个样本的实测格式（用于预建 AVAssetWriter 音轨），再用 setOnBuffer 接线。
final class MicCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "com.sakura.sakuracap.mic", qos: .userInitiated)
    private var onBuffer: ((CMSampleBuffer) -> Void)?

    /// 首个样本实测的设备格式（写入在采集队列，主线程轮询读取，一次性写入）
    private(set) var audioFormat: (sampleRate: Double, channels: Int)?

    func start() throws {
        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw RecordingError.noMicrophone
        }
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw RecordingError.microphoneInit(error.localizedDescription)
        }
        session.beginConfiguration()
        session.addInput(input)
        output.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(output)
        session.commitConfiguration()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            session.startRunning()
            Log.audio.info("麦克风采集运行中: \(self.session.isRunning)")
        }
    }

    /// 等待设备格式就绪（一般几百毫秒内）
    func waitForFormat(timeout: TimeInterval) async -> (sampleRate: Double, channels: Int)? {
        let deadline = Date().addingTimeInterval(timeout)
        while audioFormat == nil, Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return audioFormat
    }

    func setOnBuffer(_ handler: ((CMSampleBuffer) -> Void)?) {
        onBuffer = handler
    }

    func stop() {
        onBuffer = nil
        session.stopRunning()
        Log.audio.info("麦克风采集已停止")
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if audioFormat == nil,
           let desc = CMSampleBufferGetFormatDescription(sampleBuffer),
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee {
            audioFormat = (asbd.mSampleRate, Int(asbd.mChannelsPerFrame))
            Log.audio.info("麦克风格式: \(self.audioFormat!.sampleRate, format: .fixed(precision: 0)) Hz × \(self.audioFormat!.channels) ch")
        }
        onBuffer?(sampleBuffer)
    }
}

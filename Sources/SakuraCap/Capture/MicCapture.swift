import AVFoundation
import os

/// 麦克风采集：AVCaptureSession + AVCaptureAudioDataOutput，直接产出 CMSampleBuffer。
/// 先 start() 拿到首个样本的实测格式（用于预建 AVAssetWriter 音轨），再用 setOnBuffer 接线。
final class MicCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "com.sakura.sakuracap.mic", qos: .userInitiated)

    // onBuffer：主线程写、采集队列读；audioFormat：采集队列写、任意线程轮询读。
    // 两者都跨线程，统一用锁保护（高频路径只做一次加锁取引用）。
    private let lock = NSLock()
    private var _onBuffer: ((CMSampleBuffer) -> Void)?
    private var _audioFormat: (sampleRate: Double, channels: Int)?

    /// 首个样本实测的设备格式（写入在采集队列，主线程轮询读取，一次性写入）
    var audioFormat: (sampleRate: Double, channels: Int)? {
        lock.lock(); defer { lock.unlock() }
        return _audioFormat
    }

    func start() throws {
        let selectedID = AppSettings.shared.microphoneDeviceID
        let device = CaptureDevices.microphones().first { $0.uniqueID == selectedID }
            ?? AVCaptureDevice.default(for: .audio)
        guard let device else {
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
        lock.lock(); defer { lock.unlock() }
        _onBuffer = handler
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        _onBuffer = nil
        session.stopRunning()
        Log.audio.info("麦克风采集已停止")
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        var firstFormat: (sampleRate: Double, channels: Int)?
        lock.lock()
        if _audioFormat == nil,
           let desc = CMSampleBufferGetFormatDescription(sampleBuffer),
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee {
            _audioFormat = (asbd.mSampleRate, Int(asbd.mChannelsPerFrame))
            firstFormat = _audioFormat
        }
        let handler = _onBuffer
        lock.unlock()
        if let firstFormat {
            Log.audio.info("麦克风格式: \(firstFormat.sampleRate, format: .fixed(precision: 0)) Hz × \(firstFormat.channels) ch")
        }
        handler?(sampleBuffer)
    }
}

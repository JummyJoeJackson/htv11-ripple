import AVFoundation
import Foundation
import RippleKit

/// Records the Watch microphone as 16 kHz mono 16-bit PCM, in chunks of about
/// a quarter second. watchOS has no speech recognition, so the chunks go to
/// the iPhone. Use on the main thread.
final class WatchMicrophone {
    /// Called on the main thread.
    var onChunk: ((Data) -> Void)?

    private let engine = AVAudioEngine()
    private(set) var isRecording = false

    var isRunning: Bool { isRecording && engine.isRunning }

    static var allowed: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    /// Asks once, outside an alarm, so the prompt never covers the circle.
    static func requestPermission() {
        guard AVAudioApplication.shared.recordPermission == .undetermined else { return }
        AVAudioApplication.requestRecordPermission { _ in }
    }

    /// False if the microphone couldn't start, for example while the app is in the background.
    func start() -> Bool {
        if isRunning { return true }
        stop()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [])
            try session.setActive(true)

            let input = engine.inputNode
            let inputFormat = input.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0,
                  let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: VoiceAudio.sampleRate, channels: 1, interleaved: true),
                  let converter = AVAudioConverter(from: inputFormat, to: target)
            else {
                stop()
                return false
            }
            let chunker = Chunker(converter: converter, target: target, onChunk: onChunk)
            input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { buffer, _ in
                chunker.add(buffer)
            }
            engine.prepare()
            try engine.start()
            isRecording = true
            return true
        } catch {
            stop()
            return false
        }
    }

    func stop() {
        if isRecording {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            isRecording = false
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Converts one recording's buffers and cuts them into chunks. Used only on
/// the audio thread.
private final class Chunker {
    private let converter: AVAudioConverter
    private let target: AVAudioFormat
    private let onChunk: ((Data) -> Void)?
    private let chunkBytes = Int(VoiceAudio.sampleRate / 4) * MemoryLayout<Int16>.size
    private var pending = Data()

    init(converter: AVAudioConverter, target: AVAudioFormat, onChunk: ((Data) -> Void)?) {
        self.converter = converter
        self.target = target
        self.onChunk = onChunk
    }

    func add(_ buffer: AVAudioPCMBuffer) {
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }

        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil, output.frameLength > 0, let samples = output.int16ChannelData else { return }

        pending.append(Data(bytes: samples[0], count: Int(output.frameLength) * MemoryLayout<Int16>.size))
        guard pending.count >= chunkBytes, let onChunk else { return }
        let chunk = pending
        pending = Data()
        DispatchQueue.main.async { onChunk(chunk) }
    }
}

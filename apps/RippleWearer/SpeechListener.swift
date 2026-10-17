import AVFoundation
import Foundation
import RippleKit
import Speech

/// Speech recognition for the Watch. watchOS has none, so while an alarm is
/// open the Watch streams its microphone here and gets back what was heard.
/// The Watch decides whether it was the phrase. Use on the main thread.
final class SpeechListener {
    /// Called on the main thread.
    var onHeard: ((VoiceHeard) -> Void)?

    private let recognizer = SFSpeechRecognizer()
    private let format = AVAudioFormat(standardFormatWithSampleRate: VoiceAudio.sampleRate, channels: 1)
    private var sessionId: String?
    private var phrase = ""
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var lastAudioAt = Date.distantPast
    private var lastSent = ""
    private var problemSent = false

    var statusText: String {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return recognizer?.supportsOnDeviceRecognition == true ? "Allowed, on this iPhone" : "Allowed"
        case .denied: return "Denied in Settings"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not asked yet"
        @unknown default: return "Unknown"
        }
    }

    /// Asks once, while the app is open, so an alarm never waits on the prompt.
    func requestPermission() {
        guard SFSpeechRecognizer.authorizationStatus() == .notDetermined else { return }
        SFSpeechRecognizer.requestAuthorization { _ in }
    }

    /// About a quarter second of audio from the Watch. A new session id starts over.
    func receive(sessionId: String, audio: Data, phrase: String) {
        if sessionId != self.sessionId {
            stop()
            self.sessionId = sessionId
            self.phrase = phrase
        }
        lastAudioAt = Date()
        if let problem = problem() {
            report(VoiceHeard(sessionId: sessionId, text: "", problem: problem))
            return
        }
        if request == nil { startRecognition() }
        if let buffer = makeBuffer(audio) { request?.append(buffer) }
    }

    func stop(sessionId: String) {
        guard sessionId == self.sessionId else { return }
        stop()
    }

    /// Ends a session the Watch stopped sending to without saying so.
    func endIfQuiet() {
        guard sessionId != nil, Date().timeIntervalSince(lastAudioAt) > 5 else { return }
        stop()
    }

    private func stop() {
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        sessionId = nil
        lastSent = ""
        problemSent = false
    }

    private func problem() -> String? {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: break
        case .notDetermined: return "Open Ripple on your iPhone and allow speech recognition."
        default: return "Speech recognition is off for Ripple on your iPhone."
        }
        guard let recognizer else { return "Your iPhone can't recognize speech in its language." }
        guard recognizer.isAvailable else { return "Speech recognition isn't available on your iPhone right now." }
        return nil
    }

    private func startRecognition() {
        guard let recognizer, let session = sessionId else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.contextualStrings = [phrase]
        // On the iPhone when it can: private, works offline and has no time limit.
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self, self.sessionId == session else { return }
            if let result {
                let best = result.bestTranscription.formattedString
                let others = result.transcriptions.map(\.formattedString).filter { $0 != best }
                self.report(VoiceHeard(sessionId: session, text: best, alternatives: others))
            }
            // Recognition ends after a silence, an error or a time limit. The next audio starts a new one.
            if (error != nil || result?.isFinal == true), self.request === request {
                self.request = nil
                self.task = nil
            }
        }
    }

    private func report(_ heard: VoiceHeard) {
        if heard.problem != nil {
            guard !problemSent else { return }
            problemSent = true
        } else {
            guard !heard.text.isEmpty, heard.text != lastSent else { return }
            lastSent = heard.text
        }
        onHeard?(heard)
    }

    /// The Watch sends 16-bit samples; recognition takes float buffers.
    private func makeBuffer(_ audio: Data) -> AVAudioPCMBuffer? {
        let frames = audio.count / MemoryLayout<Int16>.size
        guard frames > 0, let format,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        audio.withUnsafeBytes { raw in
            for index in 0..<frames {
                let sample = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: index * 2, as: Int16.self))
                channel[index] = Float(sample) / 32_768
            }
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        return buffer
    }
}

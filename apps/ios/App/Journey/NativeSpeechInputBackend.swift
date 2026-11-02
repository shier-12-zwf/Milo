import Foundation
@preconcurrency import AVFoundation
@preconcurrency import Speech
import OSLog

struct SpeechInputFailure: Error { let message: String }

/// These factories have no actor isolation. Legacy Objective-C callbacks may
/// arrive on TCC, recognition or realtime audio queues; never inherit MainActor.
enum SpeechCallbacks {
    nonisolated static func authorization(_ resume: @escaping @Sendable (Bool) -> Void)
        -> @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void {
        { status in resume(status == .authorized) }
    }
    nonisolated static func recognition(_ deliver: @escaping @Sendable (SpeechInputEvent) -> Void)
        -> @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { result, error in
            let failure = error as NSError?
            if let failure {
                Logger(subsystem: "com.milo.echoes.ios", category: "SpeechInput")
                    .error("Recognition failed: \(failure.domain, privacy: .public) code=\(failure.code, privacy: .public)")
            }
            deliver(SpeechInputEvent(text: result?.bestTranscription.formattedString,
                                     finished: result?.isFinal == true, failed: error != nil,
                                     message: failure.map { error in
                                         if error.domain == "kAFAssistantErrorDomain", error.code == 1110 {
                                             return "没有听清，可以重试或使用键盘。"
                                         }
                                         return "语音识别服务暂时不可用，请稍后重试或使用键盘输入。"
                                     }))
        }
    }
    nonisolated static func audioTap(_ request: SFSpeechAudioBufferRecognitionRequest) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { @Sendable buffer, _ in request.append(buffer) }
    }
    nonisolated static func interruption(_ deliver: @escaping @Sendable (SpeechInputEvent) -> Void)
        -> @Sendable (Notification) -> Void {
        { notification in
            if notification.name == AVAudioSession.interruptionNotification {
                guard (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                        == AVAudioSession.InterruptionType.began.rawValue else { return }
            } else if notification.name == AVAudioSession.routeChangeNotification {
                guard (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                        == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            }
            deliver(SpeechInputEvent(finished: true, message: "录音已中断，已保留文字，可以重试或使用键盘。"))
        }
    }
}

@MainActor final class NativeSpeechInputBackend: SpeechInputBackend {
    private var engine: AVAudioEngine?
    private var input: AVAudioInputNode?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var tapInstalled = false
    private var sessionActive = false
    private var observers: [NSObjectProtocol] = []

    func speechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization(SpeechCallbacks.authorization { continuation.resume(returning: $0) })
        }
    }
    func microphonePermission() async -> Bool { await AVAudioApplication.requestRecordPermission() }

    func start(deliver: @escaping @Sendable (SpeechInputEvent) -> Void) throws {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")), recognizer.isAvailable else {
            throw SpeechInputFailure(message: "语音服务暂时不可用，请使用键盘输入。")
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: .defaultToSpeaker)
        try session.setActive(true); sessionActive = true
        guard session.isInputAvailable, session.sampleRate.isFinite, session.sampleRate > 0,
              session.inputNumberOfChannels > 0 else {
            throw SpeechInputFailure(message: "未找到可用麦克风，请使用键盘输入。")
        }
        let engine = AVAudioEngine(); self.engine = engine
        let request = SFSpeechAudioBufferRecognitionRequest(); self.request = request
        request.shouldReportPartialResults = true
        // Simulator can report support while its local language assets are absent.
        // Explicitly disable the local route on Simulator; even default routing
        // can select a broken simulator model. This public property is writable.
        #if targetEnvironment(simulator)
        recognizer.supportsOnDeviceRecognition = false
        #else
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        #endif
        let input = engine.inputNode; self.input = input
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate.isFinite, format.sampleRate > 0, format.channelCount > 0 else {
            throw SpeechInputFailure(message: "未找到可用麦克风，请使用键盘输入。")
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: SpeechCallbacks.audioTap(request))
        tapInstalled = true
        recognition = recognizer.recognitionTask(with: request, resultHandler: SpeechCallbacks.recognition(deliver))
        let interrupted = SpeechCallbacks.interruption(deliver)
        observers = [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
                     AVAudioSession.mediaServicesWereResetNotification].map {
            NotificationCenter.default.addObserver(forName: $0, object: session, queue: nil, using: interrupted)
        }
        engine.prepare(); try engine.start()
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
        engine?.stop()
        if tapInstalled { input?.removeTap(onBus: 0); tapInstalled = false }
        // Stop the tap producer before ending/cancelling the recognition request.
        request?.endAudio(); recognition?.cancel()
        input = nil; engine = nil; request = nil; recognition = nil
        if sessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            sessionActive = false
        }
    }
}

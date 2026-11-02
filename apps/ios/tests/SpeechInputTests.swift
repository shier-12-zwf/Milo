import XCTest
@preconcurrency import AVFoundation
@preconcurrency import Speech
@testable import Milo

@MainActor private final class ControlledSpeechBackend: SpeechInputBackend {
    var speechAllowed = true
    var micAllowed = true
    var holdSpeech = false
    var permissions: [CheckedContinuation<Bool, Never>] = []
    var events: [@Sendable (SpeechInputEvent) -> Void] = []
    var starts = 0
    var stops = 0
    var failStart = false
    func speechPermission() async -> Bool {
        if holdSpeech { return await withCheckedContinuation { permissions.append($0) } }
        return speechAllowed
    }
    func microphonePermission() async -> Bool { micAllowed }
    func start(deliver: @escaping @Sendable (SpeechInputEvent) -> Void) throws {
        starts += 1; events.append(deliver)
        if failStart { throw SpeechInputFailure(message: "未找到可用麦克风，请使用键盘输入。") }
    }
    func stop() { stops += 1 }
}

@MainActor final class SpeechInputTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private func drain() async { for _ in 0..<20 { await Task.yield() } }

    func testNativeAssetPreparationDiagnostic() async {
        guard #available(iOS 26.0, *) else { return }
        let locales = await DictationTranscriber.supportedLocales
        let installed = await DictationTranscriber.installedLocales
        print("MILO_SPEECH_ASSETS dictationSupported=\(locales.map(\.identifier)) installed=\(installed.map(\.identifier)) transcriberAvailable=\(SpeechTranscriber.isAvailable)")
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: "zh-CN")) else {
            print("MILO_SPEECH_ASSETS Chinese dictation unavailable; diagnostic only, NOT speech acceptance")
            return
        }
        let module = DictationTranscriber(locale: locale, preset: .progressiveShortDictation)
        print("MILO_SPEECH_ASSETS before=\(await AssetInventory.status(forModules: [module]))")
        do {
            if let download = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                try await download.downloadAndInstall()
            }
            print("MILO_SPEECH_ASSETS after=\(await AssetInventory.status(forModules: [module])); NOT speech acceptance")
        } catch {
            let failure = error as NSError
            print("MILO_SPEECH_ASSETS download failed \(failure.domain) code=\(failure.code); diagnostic only, NOT speech acceptance")
        }
    }

    func testAuthorizationBridgeOnBackgroundQueue() async {
        for status in [SFSpeechRecognizerAuthorizationStatus.authorized, .denied, .restricted, .notDetermined] {
            let accepted = await withCheckedContinuation { continuation in
                let handler = SpeechCallbacks.authorization { continuation.resume(returning: $0) }
                DispatchQueue.global().async {
                    XCTAssertFalse(Thread.isMainThread)
                    handler(status)
                }
            }
            XCTAssertEqual(accepted, status == .authorized)
        }
    }
    func testActualRecognitionHandlerOnBackgroundQueue() async {
        let event = await withCheckedContinuation { continuation in
            let handler = SpeechCallbacks.recognition { continuation.resume(returning: $0) }
            DispatchQueue.global().async {
                XCTAssertFalse(Thread.isMainThread)
                handler(nil, NSError(domain: "SpeechRegression", code: 1))
            }
        }
        XCTAssertTrue(event.failed); XCTAssertNil(event.text)
        XCTAssertTrue(event.message?.contains("服务暂时不可用") == true)
    }
    func testActualAudioTapOnBackgroundQueue() async {
        let finished = await withCheckedContinuation { continuation in
            let tap = SpeechCallbacks.audioTap(SFSpeechAudioBufferRecognitionRequest())
            DispatchQueue.global().async {
                XCTAssertFalse(Thread.isMainThread)
                let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32)!
                buffer.frameLength = 32
                buffer.floatChannelData![0].initialize(repeating: 0, count: 32)
                tap(buffer, AVAudioTime(sampleTime: 0, atRate: 44100))
                continuation.resume(returning: true)
            }
        }
        XCTAssertTrue(finished)
    }
    func testDeniedPermissionsNeverStartCapture() async {
        for denySpeech in [true, false] {
            let backend = ControlledSpeechBackend(); backend.speechAllowed = !denySpeech; backend.micAllowed = denySpeech
            let model = SpeechInputModel(backend: backend); await model.start()
            XCTAssertFalse(model.isActive); XCTAssertEqual(backend.starts, 0)
            XCTAssertTrue(model.errorMessage?.contains(denySpeech ? "语音识别权限" : "麦克风权限") == true)
        }
    }
    func testCancelPendingPermissionThenRestartIgnoresOldDefer() async {
        let backend = ControlledSpeechBackend(); backend.holdSpeech = true
        let model = SpeechInputModel(backend: backend)
        let old = Task { await model.start() }; await drain(); XCTAssertEqual(backend.permissions.count, 1)
        model.stop()
        let new = Task { await model.start() }; await drain(); XCTAssertEqual(backend.permissions.count, 2)
        backend.permissions[0].resume(returning: true); await old.value
        XCTAssertTrue(model.isStarting); XCTAssertEqual(backend.starts, 0)
        backend.permissions[1].resume(returning: true); await new.value
        XCTAssertTrue(model.isRecording); XCTAssertEqual(backend.starts, 1); model.stop()
    }
    func testDuplicatePendingAndRecordingStarts() async {
        let backend = ControlledSpeechBackend(); backend.holdSpeech = true
        let model = SpeechInputModel(backend: backend)
        let first = Task { await model.start() }; await drain()
        await model.start(); XCTAssertEqual(backend.permissions.count, 1)
        backend.permissions[0].resume(returning: true); await first.value
        await model.start(); XCTAssertEqual(backend.starts, 1); model.stop()
    }
    func testCancelledTaskDoesNotStartAudio() async {
        let backend = ControlledSpeechBackend(); backend.holdSpeech = true
        let model = SpeechInputModel(backend: backend)
        let start = Task { await model.start() }; await drain()
        start.cancel(); backend.permissions[0].resume(returning: true); await start.value
        XCTAssertFalse(model.isActive); XCTAssertEqual(backend.starts, 0)
    }
    func testStaleCompletionCannotStopOrOverwriteNewSession() async {
        let backend = ControlledSpeechBackend(); let model = SpeechInputModel(backend: backend)
        await model.start(); model.stop(); await model.start()
        backend.events[0](SpeechInputEvent(text: "旧文本", finished: true)); await drain()
        XCTAssertTrue(model.isRecording); XCTAssertEqual(model.transcript, "")
        let deliver = backend.events[1]
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { deliver(SpeechInputEvent(text: "新的文字")); continuation.resume() }
        }
        await drain(); XCTAssertEqual(model.transcript, "新的文字"); model.stop()
    }
    func testPartialTranscriptSurvivesFailureAndIdempotentStop() async {
        let backend = ControlledSpeechBackend(); let model = SpeechInputModel(backend: backend)
        await model.start(); backend.events[0](SpeechInputEvent(text: "保留这句话")); await drain()
        backend.events[0](SpeechInputEvent(failed: true)); await drain()
        XCTAssertFalse(model.isActive); XCTAssertEqual(model.transcript, "保留这句话")
        model.stop(); model.stop(); XCTAssertEqual(model.transcript, "保留这句话")
    }
    func testSetupFailureCleansUpAndAllowsRetry() async {
        let backend = ControlledSpeechBackend(); backend.failStart = true
        let model = SpeechInputModel(backend: backend); await model.start()
        XCTAssertFalse(model.isActive); XCTAssertEqual(backend.stops, 1)
        XCTAssertTrue(model.errorMessage?.contains("麦克风") == true)
        backend.failStart = false; await model.start(); XCTAssertTrue(model.isRecording); model.stop()
    }
    func testRealInterruptionNotificationBridgeStopsAndPreservesText() async {
        for kind in 0..<3 {
            let backend = ControlledSpeechBackend(); let model = SpeechInputModel(backend: backend)
            await model.start(); backend.events[0](SpeechInputEvent(text: "中断前文字")); await drain()
            let handler = SpeechCallbacks.interruption(backend.events[0])
            await withCheckedContinuation { continuation in
                DispatchQueue.global().async {
                    let notification: Notification
                    switch kind {
                    case 0: notification = Notification(name: AVAudioSession.interruptionNotification,
                        userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
                    case 1: notification = Notification(name: AVAudioSession.routeChangeNotification,
                        userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
                    default: notification = Notification(name: AVAudioSession.mediaServicesWereResetNotification)
                    }
                    handler(notification); continuation.resume()
                }
            }
            await drain(); XCTAssertFalse(model.isActive); XCTAssertEqual(model.transcript, "中断前文字")
            XCTAssertTrue(model.errorMessage?.contains("中断") == true)
            await model.start(); XCTAssertTrue(model.isRecording); model.stop()
        }
    }
    func testNativeBackendCleanupWithoutTapIsRepeatable() {
        let backend = NativeSpeechInputBackend(); backend.stop(); backend.stop()
    }
}

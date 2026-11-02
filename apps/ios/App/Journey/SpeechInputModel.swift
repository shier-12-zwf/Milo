import Foundation
import Observation

struct SpeechInputEvent: Sendable {
    var text: String? = nil
    var finished = false
    var failed = false
    var message: String? = nil
}

@MainActor protocol SpeechInputBackend: AnyObject {
    func speechPermission() async -> Bool
    func microphonePermission() async -> Bool
    func start(deliver: @escaping @Sendable (SpeechInputEvent) -> Void) throws
    func stop()
}

@MainActor
@Observable
final class SpeechInputModel {
    private(set) var isRecording = false
    private(set) var isStarting = false
    private(set) var transcript = ""
    var errorMessage: String?
    var isActive: Bool { isStarting || isRecording }
    @ObservationIgnored private let backend: any SpeechInputBackend
    @ObservationIgnored private var sessionID = UUID()

    init(backend: any SpeechInputBackend = NativeSpeechInputBackend()) { self.backend = backend }

    func start() async {
        guard !isActive else { return }
        isStarting = true; errorMessage = nil
        let current = UUID(); sessionID = current
        // A cancelled old permission request must not clear a newer start.
        defer { if current == sessionID { isStarting = false } }
        let speechAllowed = await backend.speechPermission()
        guard current == sessionID else { return }
        guard !Task.isCancelled else { stop(); return }
        guard speechAllowed else { errorMessage = "语音识别权限未开启，仍可使用键盘输入。"; return }
        let micAllowed = await backend.microphonePermission()
        guard current == sessionID else { return }
        guard !Task.isCancelled else { stop(); return }
        guard micAllowed else { errorMessage = "麦克风权限未开启，仍可使用键盘输入。"; return }
        do {
            try backend.start { [weak self] event in
                Task { @MainActor [weak self] in
                    guard let self, self.sessionID == current else { return }
                    if let text = event.text, !text.isEmpty { self.transcript = text }
                    if event.finished || event.failed {
                        if let message = event.message { self.errorMessage = message }
                        else if event.failed && self.transcript.isEmpty { self.errorMessage = "没有听清，可以重试或使用键盘。" }
                        self.stop()
                    }
                }
            }
            transcript = ""
            isRecording = true
        } catch {
            stop()
            errorMessage = (error as? SpeechInputFailure)?.message ?? "录音暂时无法开始，请使用键盘输入。"
        }
    }

    func stop() {
        sessionID = UUID()
        isStarting = false; isRecording = false
        backend.stop()
    }
}

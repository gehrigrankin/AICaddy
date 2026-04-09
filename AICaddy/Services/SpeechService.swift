import Foundation
import Speech
import AVFoundation

@Observable
final class SpeechService {
    var isListening = false
    var transcript = ""
    var error: String?
    var isAuthorized = false

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.isAuthorized = status == .authorized
                if status != .authorized {
                    self?.error = "Speech recognition not authorized"
                }
            }
        }
    }

    func startListening(onResult: @escaping (String) -> Void) {
        guard let recognizer, recognizer.isAvailable else {
            error = "Speech recognition unavailable"
            return
        }

        // Stop any existing session
        stopListening()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false  // use server for accuracy, falls back to on-device

        recognitionRequest = request
        transcript = ""
        error = nil

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch let audioError {
            self.error = "Audio session error: \(audioError.localizedDescription)"
            return
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
        } catch let engineError {
            self.error = "Could not start audio engine: \(engineError.localizedDescription)"
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] taskResult, taskError in
            guard let self else { return }

            if let taskResult {
                let text = taskResult.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.transcript = text
                }

                if taskResult.isFinal {
                    DispatchQueue.main.async {
                        self.stopListening()
                        onResult(text)
                    }
                }
            }

            if let taskError {
                DispatchQueue.main.async {
                    // Don't report cancellation errors
                    if (taskError as NSError).code != 216 {
                        self.error = taskError.localizedDescription
                    }
                    self.stopListening()
                }
            }
        }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }
}

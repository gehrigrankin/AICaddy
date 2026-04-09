import SwiftUI

struct VoiceInputView: View {
    let onResult: (String) -> Void
    let disabled: Bool
    let placeholder: String

    @State private var textInput = ""
    @Bindable var speech: SpeechService

    var body: some View {
        VStack(spacing: 12) {
            // Big mic button
            Button {
                if speech.isListening {
                    speech.stopListening()
                } else {
                    speech.startListening { result in
                        onResult(result)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: speech.isListening ? "stop.fill" : "mic.fill")
                        .font(.title2)
                    Text(speech.isListening ? "Listening... Tap to stop" : "Tap to speak")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(.white)
                .background(speech.isListening ? Color.red : Color.green)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .opacity(speech.isListening ? 1 : 1)
                .animation(speech.isListening ? .easeInOut(duration: 0.8).repeatForever() : .default, value: speech.isListening)
            }
            .disabled(disabled)
            .sensoryFeedback(.impact, trigger: speech.isListening)

            // Live transcript
            if !speech.transcript.isEmpty {
                Text("\"\(speech.transcript)\"")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
            }

            // Text fallback
            HStack(spacing: 8) {
                TextField(placeholder, text: $textInput)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .submitLabel(.go)
                    .onSubmit { submitText() }

                Button("Go") { submitText() }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(textInput.isEmpty ? Color.green.opacity(0.5) : Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .disabled(textInput.isEmpty)
            }
        }
    }

    private func submitText() {
        guard !textInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onResult(textInput.trimmingCharacters(in: .whitespaces))
        textInput = ""
    }
}

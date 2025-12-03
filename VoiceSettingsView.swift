//
//  VoiceSettingsView.swift
//  GlassesTestAssistant
//

import SwiftUI

struct VoiceSettingsView: View {

    @AppStorage(VoiceUserDefaultsKeys.engine) private var engineRaw: String = VoiceEngine.iosSystem.rawValue
    @AppStorage(VoiceUserDefaultsKeys.rate)   private var rate: Double = 0.45   // 0.3...0.7
    @AppStorage(VoiceUserDefaultsKeys.pitch)  private var pitch: Double = 1.0  // 0.8...1.2
    @AppStorage(VoiceUserDefaultsKeys.tone)   private var toneRaw: String = VoiceTone.neutral.rawValue

    private var engine: VoiceEngine {
        get { VoiceEngine(rawValue: engineRaw) ?? .iosSystem }
        set { engineRaw = newValue.rawValue }
    }

    private var tone: VoiceTone {
        get { VoiceTone(rawValue: toneRaw) ?? .neutral }
        set { toneRaw = newValue.rawValue }
    }

    var body: some View {
        Form {
            Section("Voice Engine") {
                Picker("Engine", selection: $engineRaw) {
                    ForEach(VoiceEngine.allCases) { eng in
                        Text(eng.displayName).tag(eng.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Text("ChatGPT Voice will use OpenAI TTS when wired; iOS System uses on-device speech.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Section("iOS Voice Tuning") {
                HStack {
                    Text("Speed")
                    Slider(value: $rate, in: 0.3...0.7, step: 0.02)
                }
                HStack {
                    Text("Pitch")
                    Slider(value: $pitch, in: 0.8...1.2, step: 0.02)
                }

                Picker("Tone", selection: $toneRaw) {
                    ForEach(VoiceTone.allCases) { t in
                        Text(t.displayName).tag(t.rawValue)
                    }
                }
            }

            Section {
                Button("Play Test (Answer Style)") {
                    SpeechService.shared.speak("This is a test of your current voice settings for answers.")
                }
                Button("Play Test (Question Style)") {
                    let sample = """
                    Statistical Math Problem number two.

                    Find the mean, median, mode, and interquartile range.
                    """
                    SpeechService.shared.speakQuestion(sample, pauseBetweenLines: 3.0)
                }
            }
        }
        .navigationTitle("Voice & Audio")
        .navigationBarTitleDisplayMode(.inline)
    }
}

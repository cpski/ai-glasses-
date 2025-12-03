//
//  SpeechService.swift
//  GlassesTestAssistant
//

import Foundation
import AVFoundation

/// Global speech helper that can use either iOS system TTS or ChatGPT voice
/// depending on user settings.
final class SpeechService {

    static let shared = SpeechService()

    private let synthesizer = AVSpeechSynthesizer()
    private let defaults = UserDefaults.standard

    /// Choose a natural-sounding English voice for iOS engine.
    private let preferredVoice: AVSpeechSynthesisVoice? = {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        if let enhanced = voices.first(where: { v in
            v.language == "en-US" && v.quality == .enhanced
        }) {
            return enhanced
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }()

    private init() {}

    // MARK: - Settings helpers

    private func currentEngine() -> VoiceEngine {
        let raw = defaults.string(forKey: VoiceUserDefaultsKeys.engine) ?? VoiceEngine.iosSystem.rawValue
        return VoiceEngine(rawValue: raw) ?? .iosSystem
    }

    private func currentTone() -> VoiceTone {
        let raw = defaults.string(forKey: VoiceUserDefaultsKeys.tone) ?? VoiceTone.neutral.rawValue
        return VoiceTone(rawValue: raw) ?? .neutral
    }

    private func currentRate(isQuestion: Bool) -> Float {
        // Slider stores 0.3...0.7; default if unset.
        let stored = defaults.double(forKey: VoiceUserDefaultsKeys.rate)
        let base = stored == 0 ? 0.45 : stored // safe default
        let rate = Float(base)

        if isQuestion {
            // Slightly slower for questions
            return max(0.3, min(rate * 0.8, 0.7))
        } else {
            return max(0.3, min(rate, 0.7))
        }
    }

    private func currentPitch() -> Float {
        let stored = defaults.double(forKey: VoiceUserDefaultsKeys.pitch)
        let base = stored == 0 ? 1.0 : stored
        return Float(max(0.8, min(base, 1.2)))
    }

    // MARK: - Public API

    /// Default "answer" speech – uses chosen engine.
    func speak(_ text: String) {
        speakInternal(text, isQuestion: false)
    }

    /// "Question mode" – slower, line-by-line with pauses; still respects engine choice.
    func speakQuestion(_ text: String,
                       pauseBetweenLines seconds: TimeInterval = 4.0) {

        let engine = currentEngine()
        let tone   = currentTone()

        switch engine {
        case .iosSystem:
            // iOS voice: split into lines and speak with pauses
            let lines = text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard !lines.isEmpty else { return }

            let rate  = currentRate(isQuestion: true)
            let pitch = adjustedPitch(for: tone)

            for line in lines {
                let utt = AVSpeechUtterance(string: line)
                utt.voice = preferredVoice
                utt.rate  = rate
                utt.pitchMultiplier = pitch
                utt.postUtteranceDelay = seconds
                synthesizer.speak(utt)
            }

        case .chatGPT:
            // Single call to GPT voice; tone & "question" flag when you wire TTS.
            GPTVoiceService.shared.speak(text: text, tone: tone, isQuestion: true)
        }
    }

    /// Stop whatever is currently being spoken.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        GPTVoiceService.shared.stop()
    }

    // MARK: - Internal

    private func speakInternal(_ text: String, isQuestion: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let engine = currentEngine()
        let tone   = currentTone()

        switch engine {
        case .iosSystem:
            let utt = AVSpeechUtterance(string: trimmed)
            utt.voice = preferredVoice
            utt.rate  = currentRate(isQuestion: isQuestion)
            utt.pitchMultiplier = adjustedPitch(for: tone)
            utt.postUtteranceDelay = isQuestion ? 0.5 : 0.25
            synthesizer.speak(utt)

        case .chatGPT:
            GPTVoiceService.shared.speak(text: trimmed, tone: tone, isQuestion: isQuestion)
        }
    }

    private func adjustedPitch(for tone: VoiceTone) -> Float {
        let base = currentPitch()

        switch tone {
        case .neutral:
            return base
        case .calm:
            return max(0.8, base - 0.05)
        case .energetic:
            return min(1.2, base + 0.07)
        case .serious:
            return max(0.85, base - 0.02)
        }
    }
}

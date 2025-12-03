//
//  GPTVoiceService.swift
//  GlassesTestAssistant
//
//  Created by Connor Pauley on 12/2/25.
//

import Foundation
import AVFoundation

/// ChatGPT-style voice service using OpenAI's Text-to-Speech API.
final class GPTVoiceService {

    static let shared = GPTVoiceService()

    private var audioPlayer: AVAudioPlayer?
    private let session = URLSession(configuration: .default)

    private init() {}

    /// Speak using a ChatGPT-style voice.
    ///
    /// - Parameters:
    ///   - text: The text to speak.
    ///   - tone: Voice tone (neutral / calm / energetic / serious).
    ///   - isQuestion: Whether this is a "question mode" utterance.
    func speak(text: String, tone: VoiceTone, isQuestion: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // You can adjust style based on tone / isQuestion if you want.
        let styledText = styled(text: trimmed, tone: tone, isQuestion: isQuestion)

        // Kick off the network TTS call.
        requestTTS(for: styledText)
    }

    /// Stop any currently playing ChatGPT voice audio.
    func stop() {
        DispatchQueue.main.async {
            self.audioPlayer?.stop()
            self.audioPlayer = nil
        }
    }

    // MARK: - Internal helpers

    /// Optional: tweak the prompt slightly based on tone.
    private func styled(text: String, tone: VoiceTone, isQuestion: Bool) -> String {
        // You can get fancy here later. For now, just return the normal text.
        // Example of future logic:
        // switch tone { case .calm: return "Read this calmly: \(text)" ... }
        return text
    }

    /// Hit OpenAI's /v1/audio/speech endpoint and play the result.
    private func requestTTS(for text: String) {
        guard let url = URL(string: "https://api.openai.com/v1/audio/speech") else {
            print("GPTVoiceService: invalid TTS URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(Secrets.openAIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Choose a voice & model. You can later make these configurable.
        let voiceName = "alloy"          // OpenAI voice name
        let modelName = "gpt-4o-mini-tts" // TTS-capable model

        let payload: [String: Any] = [
            "model": modelName,
            "input": text,
            "voice": voiceName,
            // Optional: choose an audio format; "mp3" / "aac" / "wav" / "flac"
            "format": "aac"
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            print("GPTVoiceService: failed to encode TTS payload: \(error)")
            return
        }

        // Configure audio session once before playback
        configureAudioSessionIfNeeded()

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                print("GPTVoiceService: TTS request failed: \(error.localizedDescription)")
                return
            }

            guard
                let http = response as? HTTPURLResponse,
                let data = data
            else {
                print("GPTVoiceService: invalid TTS response")
                return
            }

            guard 200..<300 ~= http.statusCode else {
                let body = String(data: data, encoding: .utf8) ?? "<no body>"
                print("GPTVoiceService: HTTP \(http.statusCode) – \(body)")
                return
            }

            // Play audio on the main thread
            DispatchQueue.main.async {
                self.playAudio(data: data)
            }
        }

        task.resume()
    }

    private func configureAudioSessionIfNeeded() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Spoken audio category; you can tweak options if needed.
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true, options: [])
        } catch {
            print("GPTVoiceService: failed to set audio session: \(error)")
        }
    }

    private func playAudio(data: Data) {
        // Stop any currently playing audio first
        audioPlayer?.stop()
        audioPlayer = nil

        do {
            let player = try AVAudioPlayer(data: data)
            player.prepareToPlay()
            player.play()
            audioPlayer = player
        } catch {
            print("GPTVoiceService: failed to create AVAudioPlayer: \(error)")
        }
    }
}

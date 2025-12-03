//
//  VoiceSettings.swift
//  GlassesTestAssistant
//

import Foundation

enum VoiceEngine: String, CaseIterable, Identifiable {
    case iosSystem = "ios"
    case chatGPT   = "chatgpt"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .iosSystem: return "iOS System Voice"
        case .chatGPT:   return "ChatGPT Voice"
        }
    }
}

enum VoiceTone: String, CaseIterable, Identifiable {
    case neutral
    case calm
    case energetic
    case serious

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .neutral:   return "Neutral"
        case .calm:      return "Calm"
        case .energetic: return "Energetic"
        case .serious:   return "Serious"
        }
    }
}

struct VoiceUserDefaultsKeys {
    static let engine   = "voice_engine"
    static let rate     = "voice_rate"     // Double (0.3...0.7)
    static let pitch    = "voice_pitch"    // Double (0.8...1.2)
    static let tone     = "voice_tone"     // String (VoiceTone.rawValue)
}

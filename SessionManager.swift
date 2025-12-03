//
//  SessionManager.swift
//  GlassesTestAssistant
//

import Foundation

/// Tracks the current test session timing.
final class SessionManager: ObservableObject {

    @Published var sessionStartTime: Date?

    func startNewSession() {
        sessionStartTime = Date()
    }
}

//
//  GlassesTestAssistantApp.swift
//  GlassesTestAssistant
//

import SwiftUI

@main
struct GlassesTestAssistantApp: App {

    @StateObject private var controller = SessionController()

    var body: some Scene {
        WindowGroup {
            RootView(controller: controller)
        }
    }
}


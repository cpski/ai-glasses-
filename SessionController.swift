//
//  SessionController.swift
//  GlassesTestAssistant
//
//  Created by Connor Pauley on 12/2/25.
//

import Foundation
import SwiftUI
import Photos
import UIKit
import AVFoundation
import AudioToolbox

// MARK: - Photo Source

enum SessionPhotoSource: String, CaseIterable, Identifiable {
    case metaGlasses
    case phoneCamera

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .metaGlasses: return "Meta Glasses"
        case .phoneCamera: return "Phone Camera"
        }
    }
}

// MARK: - Session Controller

final class SessionController: ObservableObject {

    // MARK: - Constants

    static let maxPhotosPerSession = 10

    // MARK: - Dependencies

    /// Tracks when the current session started.
    private let sessionManager = SessionManager()

    // MARK: - Published State (UI reads this)

    @Published var statusMessage: String = "Idle"
    @Published var isProcessing: Bool = false

    /// Queue of solved answers ready to be read.
    @Published var answersQueue: [(image: UIImage, answer: String, explanation: String)] = []

    @Published var currentImage: UIImage?
    @Published var currentAnswer: String = ""
    @Published var currentExplanation: String = ""

    /// User taps once per expected photo (Meta glasses mode).
    @Published var expectedPhotoCount: Int = 0

    /// Index of the answer currently being read.
    @Published var currentAnswerIndex: Int = 0

    /// True when a session is active.
    @Published var isSessionActive: Bool = false

    /// True when speech reading is active.
    @Published var isReading: Bool = false

    /// Current photo source for this session.
    @Published var photoSource: SessionPhotoSource = .metaGlasses

    /// Camera photos captured when using phone camera mode (max 10).
    @Published var cameraImages: [UIImage] = []

    /// When true, we auto-start reading after processing camera photos.
    private var shouldAutoStartReadingAfterProcessing = false

    // MARK: - Internal State (logic only)

    private var photoPollTimer: Timer?
    private var tapWindowTimer: Timer?
    private var expectationResetTimer: Timer?

    private var processedAssetIDs: Set<String> = []

    private var tapWindowActive: Bool = false
    private var tapWindowRemaining: Int = 0

    private var firstPhotoDetectedAt: Date?
    private var lastUnprocessedCount: Int = 0

    // MARK: - Lifecycle

    deinit {
        photoPollTimer?.invalidate()
        tapWindowTimer?.invalidate()
        expectationResetTimer?.invalidate()
    }

    // MARK: - Public API (called from views)

    /// Backwards-compatible overload so existing callers can just call `startTestSession()`.
    /// Defaults to Meta Glasses mode.
    func startTestSession() {
        startTestSession(source: .metaGlasses)
    }

    /// Start a new test session with a chosen photo source.
    func startTestSession(source: SessionPhotoSource) {
        // Stop any ongoing speech
        SpeechService.shared.stop()

        // Set source
        photoSource = source

        // Clear old state
        answersQueue.removeAll()
        currentImage = nil
        currentAnswer = ""
        currentExplanation = ""
        processedAssetIDs.removeAll()
        isProcessing = false

        expectedPhotoCount = 0
        tapWindowActive = false
        tapWindowRemaining = 0

        cameraImages.removeAll()
        shouldAutoStartReadingAfterProcessing = false

        // Reset detection state
        firstPhotoDetectedAt = nil
        lastUnprocessedCount = 0

        // Kill timers
        photoPollTimer?.invalidate(); photoPollTimer = nil
        tapWindowTimer?.invalidate(); tapWindowTimer = nil
        expectationResetTimer?.invalidate(); expectationResetTimer = nil

        // Start session timing
        sessionManager.startNewSession()
        isSessionActive = true

        switch photoSource {
        case .metaGlasses:
            statusMessage = "Session started (Meta). Tap once per expected photo (up to 10), then start taking glasses photos."
            startPhotoPolling()  // same behavior as before

        case .phoneCamera:
            statusMessage = "Session started (Phone Camera). Use the top button to take up to 10 photos."
            // No polling; photos will be pushed via addCameraImage(_:)
        }
    }

    // MARK: - Meta Glasses: Expected Photos

    /// User taps once per expected photo (up to maxPhotosPerSession).
    func tapExpectedPhoto() {
        // Only valid in Meta glasses mode
        guard photoSource == .metaGlasses else { return }
        guard !isProcessing else { return }

        if expectedPhotoCount < Self.maxPhotosPerSession {
            expectedPhotoCount += 1
        }

        // Short vibration for each tap
        vibratePattern(times: 1)

        if !tapWindowActive {
            tapWindowActive = true
            tapWindowRemaining = 5
            statusMessage = "Tap once per photo. \(tapWindowRemaining)s left. Expecting \(expectedPhotoCount) photos."

            tapWindowTimer?.invalidate()
            tapWindowTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                DispatchQueue.main.async {
                    guard self.tapWindowActive else {
                        timer.invalidate()
                        self.tapWindowTimer = nil
                        return
                    }

                    if self.tapWindowRemaining <= 1 {
                        self.tapWindowActive = false
                        timer.invalidate()
                        self.tapWindowTimer = nil
                        self.statusMessage = "Expecting \(self.expectedPhotoCount) photos this session. Start taking them with your glasses."
                    } else {
                        self.tapWindowRemaining -= 1
                        self.statusMessage = "Tap once per photo. \(self.tapWindowRemaining)s left. Expecting \(self.expectedPhotoCount) photos."
                    }
                }
            }
        } else {
            statusMessage = "Tap once per photo. \(tapWindowRemaining)s left. Expecting \(expectedPhotoCount) photos."
        }
    }

    /// Long-press on "Photos Expected" to reset.
    func resetExpectedPhotos() {
        expectedPhotoCount = 0
        tapWindowActive = false
        tapWindowRemaining = 0
        statusMessage = "Expected photo count reset."
        // Longer vibration pattern
        vibratePattern(times: 4)
    }

    // MARK: - Phone Camera Mode

    /// Called by RootView when a new camera photo is captured in phone camera mode.
    func addCameraImage(_ image: UIImage) {
        guard photoSource == .phoneCamera else { return }

        guard cameraImages.count < Self.maxPhotosPerSession else {
            statusMessage = "Max of \(Self.maxPhotosPerSession) camera photos reached."
            return
        }

        cameraImages.append(image)
        statusMessage = "Captured \(cameraImages.count) camera photo(s)."
    }

    /// Process all captured camera photos and populate answersQueue.
    func processCameraImages(autoStartReading: Bool = false) {
        guard photoSource == .phoneCamera else { return }

        guard !cameraImages.isEmpty else {
            statusMessage = "No camera photos to process."
            return
        }

        guard !isProcessing else {
            statusMessage = "Already processing camera photos…"
            return
        }

        isProcessing = true
        shouldAutoStartReadingAfterProcessing = autoStartReading
        answersQueue.removeAll()
        currentAnswerIndex = 0

        let images = cameraImages
        statusMessage = "Processing \(images.count) camera photo(s)…"
        vibrateProcessingStart()

        processCameraImagesSequentially(images: images, index: 0)
    }

    /// Sequentially process camera images using VisionSolveAPI.
    private func processCameraImagesSequentially(images: [UIImage], index: Int) {
        if index >= images.count {
            DispatchQueue.main.async {
                self.isProcessing = false
                if self.answersQueue.isEmpty {
                    self.statusMessage = "Finished processing, but no readable questions were found."
                    self.shouldAutoStartReadingAfterProcessing = false
                } else {
                    self.currentAnswerIndex = 0
                    self.statusMessage = "Answers ready (\(self.answersQueue.count)). Tap 'Glasses On – Start Reading'."
                    self.vibrateAnswersReady()

                    if self.shouldAutoStartReadingAfterProcessing {
                        self.shouldAutoStartReadingAfterProcessing = false
                        self.isReading = true
                        self.statusMessage = "Reading answers…"
                        self.speakCurrentAndScheduleNext()
                    }
                }
            }
            return
        }

        let image = images[index]

        VisionSolveAPI.shared.solve(from: image) { result in
            switch result {
            case .failure(let error):
                DispatchQueue.main.async {
                    print("Camera image \(index + 1) error: \(error.localizedDescription)")
                    self.statusMessage = "Skipped camera photo \(index + 1) due to AI error."
                }
                self.processCameraImagesSequentially(images: images, index: index + 1)

            case .success(let response):
                DispatchQueue.main.async {
                    for q in response.questions {
                        let numberPart: String
                        if let part = q.part,
                           !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            numberPart = "Question \(q.number) part \(part)"
                        } else {
                            numberPart = "Question \(q.number)"
                        }

                        let answerText = q.answer.trimmingCharacters(in: .whitespacesAndNewlines)
                        let explanationText = (q.explanation ?? "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)

                        guard !answerText.isEmpty else { continue }

                        // We treat q.answer as already concise ("final answers only").
                        let spoken = "\(numberPart). \(answerText)"
                        self.answersQueue.append((image, spoken, explanationText))
                    }
                }
                self.processCameraImagesSequentially(images: images, index: index + 1)
            }
        }
    }

    // MARK: - Reading Controls

    /// Tap on bottom pad: pause / resume reading.
    func toggleReading() {
        if isReading {
            // Pause reading
            SpeechService.shared.stop()
            isReading = false
            statusMessage = "Reading paused."
            return
        }

        // If we're in phone camera mode and no answers yet, process first.
        if photoSource == .phoneCamera && answersQueue.isEmpty {
            if cameraImages.isEmpty {
                statusMessage = "No camera photos to process yet."
                return
            }
            processCameraImages(autoStartReading: true)
            return
        }

        guard !answersQueue.isEmpty else {
            statusMessage = "No answers in the queue yet."
            return
        }

        // If we've already gone past the end, start over from the beginning.
        if currentAnswerIndex >= answersQueue.count {
            currentAnswerIndex = 0
        }

        isReading = true
        statusMessage = "Reading answers…"
        speakCurrentAndScheduleNext()
    }

    /// Long-press on bottom pad: stop and restart from the first answer.
    func restartReadingFromBeginning() {
        guard !answersQueue.isEmpty else {
            statusMessage = "No answers to restart."
            return
        }

        SpeechService.shared.stop()
        currentAnswerIndex = 0
        isReading = true
        statusMessage = "Restarting from beginning…"
        speakCurrentAndScheduleNext()
    }

    /// Simple TTS test.
    func testSpeechOutput() {
        statusMessage = "Testing voice output…"
        SpeechService.shared.speak("This is a test of the reading voice.")
    }

    /// Debug helper: process just the latest phone photo since session start.
    func debugProcessMostRecentPhoto() {
        guard let startTime = sessionManager.sessionStartTime else {
            statusMessage = "No session start time. Tap 'Start Test Session' first."
            return
        }

        PhotosFetcher.shared.requestPhotoLibraryAccess { granted in
            guard granted else {
                DispatchQueue.main.async {
                    self.statusMessage = "Photo access is required. Enable it in Settings → Privacy → Photos."
                }
                return
            }

            PhotosFetcher.shared.fetchPhotos(since: startTime) { assets in
                guard let asset = assets.last else {
                    DispatchQueue.main.async {
                        self.statusMessage = "No recent photos found."
                    }
                    return
                }

                PhotosFetcher.shared.loadUIImage(from: asset) { image in
                    guard let image = image else {
                        DispatchQueue.main.async {
                            self.statusMessage = "Failed to load latest photo."
                        }
                        return
                    }

                    VisionSolveAPI.shared.solve(from: image) { result in
                        DispatchQueue.main.async {
                            self.answersQueue.removeAll()

                            switch result {
                            case .failure(let error):
                                self.statusMessage = "DEBUG: Failed to solve image. \(error.localizedDescription)"

                            case .success(let response):
                                for q in response.questions {
                                    let numberPart: String
                                    if let part = q.part,
                                       !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        numberPart = "Question \(q.number) part \(part)"
                                    } else {
                                        numberPart = "Question \(q.number)"
                                    }

                                    let answerText = q.answer.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let explanationText = (q.explanation ?? "")
                                        .trimmingCharacters(in: .whitespacesAndNewlines)

                                    guard !answerText.isEmpty else { continue }

                                    let spoken = "\(numberPart). \(q.question) Answer: \(answerText)."
                                    self.answersQueue.append((image, spoken, explanationText))
                                }

                                // Preview the first item and reset to start
                                if let first = self.answersQueue.first {
                                    self.currentImage = first.image
                                    self.currentAnswer = first.answer
                                    self.currentExplanation = first.explanation
                                }

                                self.currentAnswerIndex = 0
                                self.statusMessage = "DEBUG: Latest photo processed. Tap 'Glasses On – Start Reading' to hear answers."
                            }
                        }
                    }
                }
            }
        }
    }

    /// End the current session (used by RootView X button).
    func endSession() {
        isSessionActive = false
        isProcessing = false
        isReading = false
        statusMessage = "Idle"

        photoPollTimer?.invalidate(); photoPollTimer = nil
        tapWindowTimer?.invalidate(); tapWindowTimer = nil
        expectationResetTimer?.invalidate(); expectationResetTimer = nil

        SpeechService.shared.stop()
    }

    // MARK: - Internal: Photo Polling (Meta Glasses)

    private func startPhotoPolling() {
        guard photoSource == .metaGlasses else { return }
        guard sessionManager.sessionStartTime != nil else { return }

        photoPollTimer?.invalidate()
        photoPollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.pollForNewPhotos()
        }
    }

    private func pollForNewPhotos() {
        guard photoSource == .metaGlasses else { return }
        guard let startTime = sessionManager.sessionStartTime, !isProcessing else { return }

        PhotosFetcher.shared.requestPhotoLibraryAccess { granted in
            guard granted else {
                DispatchQueue.main.async {
                    self.statusMessage = "Photo access is required. Enable it in Settings → Privacy → Photos."
                }
                return
            }

            PhotosFetcher.shared.fetchPhotos(since: startTime) { assets in
                // Filter out those we've already processed
                let unprocessed = assets.filter { !self.processedAssetIDs.contains($0.localIdentifier) }

                let totalExpected = min(self.expectedPhotoCount, Self.maxPhotosPerSession)
                let foundCount = unprocessed.count

                // Nothing new yet
                guard foundCount > 0 else { return }

                let now = Date()

                // First time we see any new photos this session
                if self.firstPhotoDetectedAt == nil {
                    self.firstPhotoDetectedAt = now
                    self.lastUnprocessedCount = foundCount

                    DispatchQueue.main.async {
                        let remaining = max(totalExpected - foundCount, 0)
                        if remaining > 0, totalExpected > 0 {
                            self.statusMessage = "Found \(foundCount). Waiting for \(remaining) more…"
                        } else {
                            self.statusMessage = "Found \(foundCount) photo\(foundCount == 1 ? "" : "s"). Waiting briefly before processing…"
                        }
                    }
                    return
                }

                // If we have more photos than last time, reset the 5s wait window
                if foundCount > self.lastUnprocessedCount {
                    self.lastUnprocessedCount = foundCount
                    self.firstPhotoDetectedAt = now

                    DispatchQueue.main.async {
                        let remaining = max(totalExpected - foundCount, 0)
                        if remaining > 0, totalExpected > 0 {
                            self.statusMessage = "Found \(foundCount). Waiting for \(remaining) more…"
                        } else {
                            self.statusMessage = "Found \(foundCount) photo\(foundCount == 1 ? "" : "s"). Waiting briefly before processing…"
                        }
                    }
                    return
                }

                // We have at least one photo, and the count hasn't changed.
                // If it's been at least 5 seconds since the last new photo, process whatever we have.
                guard let firstDetected = self.firstPhotoDetectedAt else { return }
                let elapsed = now.timeIntervalSince(firstDetected)

                if elapsed < 5.0 {
                    DispatchQueue.main.async {
                        let remaining = max(totalExpected - foundCount, 0)
                        if remaining > 0, totalExpected > 0 {
                            self.statusMessage = "Found \(foundCount). Waiting up to 5s for \(remaining) more…"
                        } else {
                            self.statusMessage = "Found \(foundCount) photo\(foundCount == 1 ? "" : "s"). Waiting up to 5s before processing…"
                        }
                    }
                    return
                }

                // 5 seconds passed with no additional photos:
                // - If expectedPhotoCount is larger than what we have (e.g., tapped 6 but only 5 synced),
                //   process the photos we do have so we don't get stuck.
                let effectiveExpected = totalExpected > 0 ? totalExpected : min(foundCount, Self.maxPhotosPerSession)
                let toProcess = min(foundCount, effectiveExpected)

                DispatchQueue.main.async {
                    self.isProcessing = true
                    self.statusMessage = "Processing \(toProcess) photo\(toProcess == 1 ? "" : "s") (found \(foundCount), expected \(totalExpected))."
                    self.vibrateProcessingStart()
                    self.fetchAndProcessSessionPhotos(expectedCount: toProcess)

                    // Reset detection window so a new batch can start fresh
                    self.firstPhotoDetectedAt = nil
                    self.lastUnprocessedCount = 0
                }
            }
        }
    }

    private func fetchAndProcessSessionPhotos(expectedCount: Int) {
        guard let startTime = sessionManager.sessionStartTime else {
            statusMessage = "No session start time. Tap 'Start Test Session' first."
            isProcessing = false
            return
        }

        answersQueue.removeAll()
        currentAnswerIndex = 0

        PhotosFetcher.shared.requestPhotoLibraryAccess { granted in
            guard granted else {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.statusMessage = "Photo access is required. Enable it in Settings → Privacy → Photos."
                }
                return
            }

            PhotosFetcher.shared.fetchPhotos(since: startTime) { assets in
                let unprocessed = assets.filter { !self.processedAssetIDs.contains($0.localIdentifier) }
                let limitedAssets = Array(unprocessed.prefix(expectedCount))

                if limitedAssets.isEmpty {
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        self.statusMessage = "No new photos found to process."
                    }
                    return
                }

                // Mark these as processed
                limitedAssets.forEach { asset in
                    self.processedAssetIDs.insert(asset.localIdentifier)
                }

                self.processAssetsSequentiallyToQueue(assets: limitedAssets, index: 0)
            }
        }
    }

    private func processAssetsSequentiallyToQueue(assets: [PHAsset], index: Int) {
        if index >= assets.count {
            DispatchQueue.main.async {
                self.isProcessing = false
                if self.answersQueue.isEmpty {
                    self.statusMessage = "Finished processing, but no readable questions were found."
                } else {
                    self.currentAnswerIndex = 0
                    self.statusMessage = "Answers ready (\(self.answersQueue.count)). Tap 'Glasses On – Start Reading'."
                    self.vibrateAnswersReady()
                    self.scheduleExpectationReset()
                }
            }
            return
        }

        let asset = assets[index]

        PhotosFetcher.shared.loadUIImage(from: asset) { image in
            guard let image = image else {
                self.processAssetsSequentiallyToQueue(assets: assets, index: index + 1)
                return
            }

            VisionSolveAPI.shared.solve(from: image) { result in
                switch result {
                case .failure(let error):
                    DispatchQueue.main.async {
                        print("Error on photo \(index + 1): \(error.localizedDescription)")
                        self.statusMessage = "Skipped photo \(index + 1) due to AI parse error."
                    }
                    self.processAssetsSequentiallyToQueue(assets: assets, index: index + 1)

                case .success(let response):
                    DispatchQueue.main.async {
                        for q in response.questions {
                            let numberPart: String
                            if let part = q.part,
                               !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                numberPart = "Question \(q.number) part \(part)"
                            } else {
                                numberPart = "Question \(q.number)"
                            }

                            let answerText = q.answer.trimmingCharacters(in: .whitespacesAndNewlines)
                            let explanationText = (q.explanation ?? "")
                                .trimmingCharacters(in: .whitespacesAndNewlines)

                            guard !answerText.isEmpty else { continue }

                            let spoken = "\(numberPart). \(q.question) Answer: \(answerText)."
                            self.answersQueue.append((image, spoken, explanationText))
                        }
                    }

                    self.processAssetsSequentiallyToQueue(assets: assets, index: index + 1)
                }
            }
        }
    }

    private func scheduleExpectationReset() {
        expectationResetTimer?.invalidate()
        expectationResetTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.expectedPhotoCount = 0
                self.statusMessage = "Session reset. Tap once per photo to start a new batch."
            }
        }
    }

    // MARK: - Reading Answers (index-based, supports pause/resume/restart)

    /// Reads the current answer and schedules the next while `isReading` is true.
    private func speakCurrentAndScheduleNext() {
        guard isReading else { return }
        guard !answersQueue.isEmpty else {
            statusMessage = "No answers in queue."
            isReading = false
            return
        }

        let index = currentAnswerIndex
        guard index < answersQueue.count else {
            statusMessage = "Finished reading all answers."
            isReading = false
            return
        }

        let item = answersQueue[index]
        currentImage = item.image
        currentAnswer = item.answer
        currentExplanation = item.explanation

        SpeechService.shared.speak(item.answer)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            guard self.isReading else { return }

            // Only increment if we haven't been manually changed.
            if self.currentAnswerIndex == index {
                self.currentAnswerIndex += 1
            }

            self.speakCurrentAndScheduleNext()
        }
    }

    // MARK: - Haptics

    private func vibratePattern(times: Int) {
        for i in 0..<times {
            let delay = Double(i) * 0.25
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        }
    }

    private func vibrateProcessingStart() {
        vibratePattern(times: 2)
    }

    private func vibrateAnswersReady() {
        vibratePattern(times: 3)
    }
}

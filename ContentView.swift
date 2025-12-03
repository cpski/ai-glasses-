import SwiftUI

struct ContentView: View {

    @ObservedObject var controller: SessionController

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // Status
                Text(controller.statusMessage)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Preview of current image + answer
                if let image = controller.currentImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .cornerRadius(12)
                        .padding(.horizontal)
                }

                if !controller.currentAnswer.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current Answer")
                            .font(.headline)
                        Text(controller.currentAnswer)
                            .font(.body)
                    }
                    .padding(.horizontal)
                }

                if !controller.currentExplanation.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Explanation")
                            .font(.headline)
                        Text(controller.currentExplanation)
                            .font(.body)
                    }
                    .padding(.horizontal)
                }

                Spacer()

                // Controls
                VStack(spacing: 12) {
                    Button("Start Test Session") {
                        controller.startTestSession()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.isProcessing)

                    Button(controller.isReading ? "Stop Reading" : "Glasses On – Start Reading") {
                        controller.toggleReading()
                    }
                    .buttonStyle(.bordered)
                    .disabled(controller.answersQueue.isEmpty && !controller.isReading)

                    Button("Tap for each photo (expected: \(controller.expectedPhotoCount))") {
                        controller.tapExpectedPhoto()
                    }
                    .buttonStyle(.bordered)
                    .tint(.purple)
                    .disabled(controller.isProcessing || controller.expectedPhotoCount >= SessionController.maxPhotosPerSession)

                    Button("DEBUG: Use Latest Photo Now") {
                        controller.debugProcessMostRecentPhoto()
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .disabled(controller.isProcessing)

                    Button("Test Voice Output") {
                        controller.testSpeechOutput()
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                }
                .padding(.horizontal)

                Spacer(minLength: 8)

                Text("Tip: Tap once per expected glasses photo (max 10). The app will wait ~5s after the last new photo, then process whatever it has.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.bottom)
                    .padding(.horizontal)
            }
            .navigationTitle("Debug – Glasses Test Assistant")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(controller: SessionController())
    }
}

import SwiftUI

struct RootView: View {

    @StateObject var controller: SessionController

    @State private var showDeveloperMenu = false
    @State private var showDebugOverlay = false

    // For phone camera capture
    @State private var showCamera = false

    // Session source selection (not persisted; you can add AppStorage if you want)
    @State private var selectedSource: SessionPhotoSource = .metaGlasses

    var body: some View {
        ZStack {
            // Dark minimal background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black,
                    Color(red: 0.06, green: 0.06, blue: 0.06)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if controller.isSessionActive {
                activeSessionView
            } else {
                startSessionView
            }

            if showDebugOverlay {
                debugOverlay
            }
        }
        .sheet(isPresented: $showDeveloperMenu) {
            developerMenuSheet
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView { image in
                controller.addCameraImage(image)
                showCamera = false
            }
        }
    }

    // MARK: - Start Session Screen

    private var startSessionView: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: {
                    showDeveloperMenu = true
                }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.5))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .padding(.top, 12)
                .padding(.trailing, 16)
            }

            Spacer()

            VStack(spacing: 16) {
                Text("Glasses Test Assistant")
                    .font(.caption)
                    .foregroundColor(Color.white.opacity(0.35))

                // Source picker
                VStack(spacing: 8) {
                    Text("Photo Source")
                        .font(.footnote)
                        .foregroundColor(Color.white.opacity(0.6))

                    Picker("Source", selection: $selectedSource) {
                        ForEach(SessionPhotoSource.allCases) { src in
                            Text(src.displayName).tag(src)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 32)
                }

                Button(action: {
                    controller.startTestSession(source: selectedSource)
                }) {
                    Text("Start Test Session")
                        .font(.system(size: 20, weight: .semibold))
                        .tracking(0.4)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 24)
                                .fill(Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
            }

            Spacer()

            Text(controller.statusMessage)
                .font(.footnote)
                .foregroundColor(Color.white.opacity(0.4))
                .padding(.bottom, 20)
                .padding(.horizontal)
        }
    }

    // MARK: - Active Session Screen

    private var activeSessionView: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {

                // Top Half – Source-dependent
                if controller.photoSource == .metaGlasses {
                    // Existing Expected Photos UI
                    Button(action: {
                        controller.tapExpectedPhoto()
                    }) {
                        VStack(spacing: 10) {
                            Text("Photos Expected")
                                .font(.caption)
                                .foregroundColor(Color.white.opacity(0.4))

                            Text("\(controller.expectedPhotoCount)")
                                .font(.system(size: 54, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.bottom, 4)

                            Text("Tap for each photo expected")
                                .font(.footnote)
                                .foregroundColor(Color.white.opacity(0.5))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .frame(width: geo.size.width, height: geo.size.height * 0.5)
                        .background(
                            RoundedRectangle(cornerRadius: 32, style: .continuous)
                                .fill(Color.white.opacity(0.03))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                                )
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                        )
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.8)
                            .onEnded { _ in
                                controller.resetExpectedPhotos()
                            }
                    )

                } else {
                    // Phone camera mode – Take Photo button
                    Button(action: {
                        if controller.cameraImages.count < SessionController.maxPhotosPerSession {
                            showCamera = true
                        }
                    }) {
                        VStack(spacing: 10) {
                            Text("Camera Photos")
                                .font(.caption)
                                .foregroundColor(Color.white.opacity(0.4))

                            Text("\(controller.cameraImages.count)/\(SessionController.maxPhotosPerSession)")
                                .font(.system(size: 54, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.bottom, 4)

                            Text("Tap to take a photo using the phone camera")
                                .font(.footnote)
                                .foregroundColor(Color.white.opacity(0.5))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .frame(width: geo.size.width, height: geo.size.height * 0.5)
                        .background(
                            RoundedRectangle(cornerRadius: 32, style: .continuous)
                                .fill(Color.white.opacity(0.03))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                                )
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(controller.cameraImages.count >= SessionController.maxPhotosPerSession)
                }

                // Bottom Half – Glasses On / Start Reading
                VStack(spacing: 12) {
                    Text("Glasses On")
                        .font(.caption)
                        .foregroundColor(Color.white.opacity(0.4))

                    Text(controller.isReading ? "Pause Reading" : "Start Reading")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.vertical, 6)

                    if controller.photoSource == .phoneCamera {
                        Text("Tap to process and read camera photos.")
                            .font(.footnote)
                            .foregroundColor(Color.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    } else {
                        Text("Tap to pause/resume. Hold to restart from the beginning.")
                            .font(.footnote)
                            .foregroundColor(Color.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height * 0.5)
                .background(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 32, style: .continuous)
                                .stroke(
                                    controller.isReading
                                    ? Color.white.opacity(0.2)
                                    : Color.white.opacity(0.06),
                                    lineWidth: 1
                                )
                        )
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    controller.toggleReading()
                }
                .onLongPressGesture(minimumDuration: 0.8) {
                    controller.restartReadingFromBeginning()
                }

            }
            .overlay(
                VStack {
                    HStack {
                        Button(action: {
                            controller.endSession()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.6))
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 18)
                                        .fill(Color.black.opacity(0.5))
                                )
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)

                    Spacer()

                    Text(controller.statusMessage)
                        .font(.footnote)
                        .foregroundColor(Color.white.opacity(0.45))
                        .padding(.bottom, 14)
                        .padding(.horizontal)
                }
            )
        }
    }

    // MARK: - Developer Menu

    private var developerMenuSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("Debug").textCase(nil)) {
                    Toggle("Show debug overlay", isOn: $showDebugOverlay)

                    Button("Test voice output") {
                        SpeechService.shared.speak("This is a test of the reading voice.")
                    }

                    NavigationLink("Voice & Audio Settings") {
                        VoiceSettingsView()
                    }

                    Button("Log raw JSON sample") {
                        print("Sample JSON log placeholder.")
                    }

                    NavigationLink("Open full debug UI") {
                        ContentView(controller: controller)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        controller.endSession()
                    } label: {
                        Text("Reset session state")
                    }
                }
            }
            .navigationTitle("Developer Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        showDeveloperMenu = false
                    }
                }
            }
        }
    }

    // MARK: - Debug Overlay

    private var debugOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DEBUG")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
            Text("Session active: \(controller.isSessionActive ? "yes" : "no")")
            Text("Source: \(controller.photoSource.displayName)")
            Text("Expected photos: \(controller.expectedPhotoCount)")
            Text("Camera photos: \(controller.cameraImages.count)")
            Text("Reading: \(controller.isReading ? "yes" : "no")")
            Text("Queue size: \(controller.answersQueue.count)")
            Text("Status: \(controller.statusMessage)")
        }
        .font(.caption2)
        .foregroundColor(.white.opacity(0.8))
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.7))
        )
        .padding(.top, 40)
        .padding(.leading, 12)
    }
}

struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView(controller: SessionController())
            .preferredColorScheme(.dark)
    }
}
// MARK: - CameraCaptureView

struct CameraCaptureView: UIViewControllerRepresentable {

    typealias UIViewControllerType = UIImagePickerController

    var onImageCaptured: (UIImage) -> Void

    @Environment(\.presentationMode) private var presentationMode

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCaptureView

        init(parent: CameraCaptureView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImageCaptured(image)
            }
            parent.presentationMode.wrappedValue.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}


import Foundation
import Photos

/// Monitors the photo library for new images after a session start time.
/// Used to detect when the first glasses photo has synced in.
final class PhotoMonitor: NSObject, PHPhotoLibraryChangeObserver {

    static let shared = PhotoMonitor()

    /// When the test session was started in the app.
    var sessionStartTime: Date?

    /// When the first new photo from the glasses was seen.
    var firstPhotoTime: Date?

    /// Callback to trigger when the first new photo is detected.
    var onFirstPhotoDetected: (() -> Void)?

    private override init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func startSession() {
        sessionStartTime = Date()
        firstPhotoTime = nil
    }

    func reset() {
        sessionStartTime = nil
        firstPhotoTime = nil
        onFirstPhotoDetected = nil
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        guard let start = sessionStartTime else { return }

        // Fetch any photos created after session start.
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.predicate = NSPredicate(format: "creationDate > %@", start as NSDate)

        let newPhotos = PHAsset.fetchAssets(with: .image, options: options)

        guard newPhotos.count > 0 else { return }

        // Only care about the very first time we see new photos.
        if firstPhotoTime == nil {
            firstPhotoTime = newPhotos.firstObject?.creationDate ?? Date()
            DispatchQueue.main.async { [weak self] in
                self?.onFirstPhotoDetected?()
            }
        }
    }
}

//
//  PhotosFetcher.swift
//  GlassesTestAssistant
//

import Foundation
import Photos
import UIKit

/// Wraps Photo Library permission and fetching images created after a given time.
final class PhotosFetcher {

    static let shared = PhotosFetcher()

    private init() {}

    // MARK: - Permissions

    func requestPhotoLibraryAccess(completion: @escaping (Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            completion(true)

        case .denied, .restricted:
            completion(false)

        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                DispatchQueue.main.async {
                    completion(newStatus == .authorized || newStatus == .limited)
                }
            }

        @unknown default:
            completion(false)
        }
    }

    // MARK: - Fetching

    /// Fetch all image assets created on or after the given date, newest first.
    func fetchPhotos(since date: Date, completion: @escaping ([PHAsset]) -> Void) {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d AND creationDate >= %@", PHAssetMediaType.image.rawValue, date as NSDate)

        let result = PHAsset.fetchAssets(with: .image, options: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }

        completion(assets)
    }

    /// Load a UIImage from a PHAsset.
    func loadUIImage(from asset: PHAsset, completion: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            completion(image)
        }
    }
}

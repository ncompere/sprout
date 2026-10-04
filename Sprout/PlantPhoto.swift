import Combine
import ImageIO
import UIKit
import UniformTypeIdentifiers

enum PlantPhotoProcessor {
    static let maximumDimension = 1_600

    enum ProcessingError: Error { case invalidImage, encodingFailed }

    /// ImageIO downsamples without decoding the full-resolution original and applies EXIF orientation.
    static func jpegData(from data: Data) throws -> Data {
        guard let image = preview(from: data, maximumDimension: maximumDimension) else {
            throw ProcessingError.invalidImage
        }
        guard let cgImage = image.cgImage else { throw ProcessingError.invalidImage }
        return try encode(cgImage)
    }

    /// Camera images may carry a UIImage orientation rather than EXIF data.
    static func jpegData(from image: UIImage) throws -> Data {
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        guard width.isFinite, height.isFinite, width > 0, height > 0 else {
            throw ProcessingError.invalidImage
        }
        let ratio = min(1, CGFloat(maximumDimension) / max(width, height))
        let size = CGSize(width: max(1, floor(width * ratio)), height: max(1, floor(height * ratio)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            UIColor.white.setFill()
            renderer.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let cgImage = normalized.cgImage else { throw ProcessingError.invalidImage }
        return try encode(cgImage)
    }

    static func preview(from data: Data, maximumDimension: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    private static func encode(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ProcessingError.encodingFailed
        }
        // Only pixel data is copied; location and other original metadata are omitted.
        CGImageDestinationAddImage(destination, image,
                                  [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ProcessingError.encodingFailed }
        return data as Data
    }
}

enum PlantPhotoAlert: String, Identifiable {
    case importFailed, cameraDenied, cameraUnavailable
    var id: String { rawValue }
}

/// A form-local draft: loading, removing, or cancelling never mutates the persisted plant.
@MainActor
final class PlantPhotoDraft: ObservableObject {
    @Published private(set) var photoData: Data?
    @Published private(set) var isLoading = false
    @Published var alert: PlantPhotoAlert?
    private var generation = UUID()
    private var loadingTask: Task<Void, Never>?

    init(photoData: Data?) { self.photoData = photoData }

    @discardableResult
    func load(using loader: @escaping () async throws -> Data) -> Task<Void, Never> {
        cancelLoading()
        let request = generation
        isLoading = true
        alert = nil
        let task = Task {
            do {
                let data = try await loader()
                try Task.checkCancellation()
                guard generation == request else { return }
                photoData = data
                isLoading = false
            } catch {
                guard generation == request, !Task.isCancelled else { return }
                isLoading = false
                alert = .importFailed
            }
        }
        loadingTask = task
        return task
    }

    func remove() {
        cancelLoading()
        photoData = nil
        alert = nil
    }

    func cancelLoading() {
        generation = UUID()
        loadingTask?.cancel()
        loadingTask = nil
        isLoading = false
    }
}

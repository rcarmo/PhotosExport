import Foundation
import Photos

func requestPhotosAccess(logger: LineLogger? = nil) async throws {
  let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
  await logDebug(logger, "photos.auth status=\(status.rawValue)")
  if status == .authorized || status == .limited { return }

  try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
    PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
      if let logger {
        Task { await logger.log("photos.auth requestAuthorization result=\(newStatus.rawValue)") }
      }
      if newStatus == .authorized || newStatus == .limited {
        cont.resume(returning: ())
      } else {
        cont.resume(throwing: NSError(domain: "PhotosExport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Photos access denied: \(newStatus)"]))
      }
    }
  }
}

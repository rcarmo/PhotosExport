import Foundation
import Photos
import UniformTypeIdentifiers

enum PhotosExportErrorInfoKey {
  static let assetIdentifier = "PhotosExportAssetIdentifier"
  static let captureTimestamp = "PhotosExportCaptureTimestamp"
  static let mediaType = "PhotosExportMediaType"
  static let mediaSubtypes = "PhotosExportMediaSubtypes"
  static let pixelSize = "PhotosExportPixelSize"
  static let duration = "PhotosExportDuration"
  static let failedResources = "PhotosExportFailedResources"
}

func exportFilename(
  captureDate: Date,
  originalFilename: String,
  fallbackSeed: String,
  uti: String,
  usedNames: inout Set<String>
) -> String {
  let ts = captureTimestampString(captureDate)

  let preferredExt = UTType(uti)?.preferredFilenameExtension
  let originalExt = (originalFilename as NSString).pathExtension
  let extRaw = !originalExt.isEmpty ? originalExt : (preferredExt ?? "")
  let ext = extRaw.lowercased()

  let baseCandidate = ext.isEmpty ? ts : "\(ts).\(ext)"
  if !usedNames.contains(baseCandidate) {
    usedNames.insert(baseCandidate)
    return baseCandidate
  }

  let seed = originalFilename.isEmpty ? fallbackSeed : "\(originalFilename)|\(fallbackSeed)"

  var attempt = 0
  while true {
    let cycle = attempt / 26
    let offset = attempt % 26
    let h = cycle == 0 ? fnv1a64(seed) : fnv1a64("\(seed)#\(cycle)")
    let letter = alphaLetter(from: h, offset: offset)
    let stem = "\(ts)\(letter)"
    let candidate = ext.isEmpty ? stem : "\(stem).\(ext)"
    if !usedNames.contains(candidate) {
      usedNames.insert(candidate)
      return candidate
    }
    attempt += 1
  }
}

func resourceTypeLabel(_ type: PHAssetResourceType) -> String {
  switch type {
  case .photo: return "photo"
  case .video: return "video"
  case .audio: return "audio"
  case .alternatePhoto: return "alternatePhoto"
  case .fullSizePhoto: return "fullSizePhoto"
  case .fullSizeVideo: return "fullSizeVideo"
  case .adjustmentData: return "adjustmentData"
  default: return "type\(type.rawValue)"
  }
}

func filenameForResource(asset: PHAsset, resource: PHAssetResource, captureDate: Date, usedNames: inout Set<String>) -> String {
  let metaSeed = [
    "asset=\(asset.localIdentifier)",
    "mediaType=\(asset.mediaType.rawValue)",
    "subtypes=\(asset.mediaSubtypes.rawValue)",
    "px=\(asset.pixelWidth)x\(asset.pixelHeight)",
    "dur=\(asset.duration)",
    "resType=\(resource.type.rawValue)",
    "uti=\(resource.uniformTypeIdentifier)",
  ].joined(separator: "|")

  return exportFilename(
    captureDate: captureDate,
    originalFilename: resource.originalFilename,
    fallbackSeed: metaSeed,
    uti: resource.uniformTypeIdentifier,
    usedNames: &usedNames
  )
}

func exportOriginalResource(asset: PHAsset, to folder: URL, logger: LineLogger? = nil) async throws -> URL {
  let resources = PHAssetResource.assetResources(for: asset)

  func score(_ r: PHAssetResource) -> Int {
    switch r.type {
    case .fullSizePhoto, .fullSizeVideo: return 100
    case .photo, .video: return 80
    default: return 10
    }
  }

  guard let chosen = resources.max(by: { score($0) < score($1) }) else {
    throw NSError(domain: "PhotosExport", code: 2, userInfo: [NSLocalizedDescriptionKey: "No exportable resources"])
  }

  await logger?.log("asset.resource chosen asset=\(asset.localIdentifier) type=\(chosen.type.rawValue) uti=\(chosen.uniformTypeIdentifier) name=\(chosen.originalFilename)")

  let originalName = chosen.originalFilename
  let filename = sanitize(originalName.isEmpty ? UUID().uuidString : originalName)
  let destination = folder.appendingPathComponent(filename)

  await logger?.log("asset.export plan asset=\(asset.localIdentifier) mediaType=\(asset.mediaType.rawValue) resourceType=\(chosen.type.rawValue) original=\(originalName) dest=\(destination.path)")

  var finalURL = destination
  if FileManager.default.fileExists(atPath: finalURL.path) {
    let ext = finalURL.pathExtension
    let base = finalURL.deletingPathExtension().lastPathComponent
    finalURL = folder.appendingPathComponent("\(base)-\(UUID().uuidString)").appendingPathExtension(ext)
    await logger?.log("fs.file collision original=\(destination.path) new=\(finalURL.path)")
  }

  let opts = PHAssetResourceRequestOptions()
  opts.isNetworkAccessAllowed = true

  await logger?.log("asset.export writeData begin asset=\(asset.localIdentifier) dest=\(finalURL.path) networkAllowed=\(opts.isNetworkAccessAllowed)")

  do {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
      PHAssetResourceManager.default().writeData(for: chosen, toFile: finalURL, options: opts) { err in
        if let err = err {
          cont.resume(throwing: err)
        } else {
          cont.resume(returning: ())
        }
      }
    }
  } catch {
    await logger?.log("asset.export writeData failed asset=\(asset.localIdentifier) dest=\(finalURL.path) error=\(error)")
    throw error
  }

  if let attrs = try? FileManager.default.attributesOfItem(atPath: finalURL.path),
     let size = attrs[.size] as? NSNumber {
    await logger?.log("asset.export done asset=\(asset.localIdentifier) path=\(finalURL.path) bytes=\(size.int64Value)")
  } else {
    await logger?.log("asset.export done asset=\(asset.localIdentifier) path=\(finalURL.path)")
  }

  return finalURL
}

func exportAllResources(
  asset: PHAsset,
  captureDate: Date,
  to folder: URL,
  incremental: Bool,
  errorLogURL: URL,
  logger: LineLogger? = nil,
  usedNames: inout Set<String>
) async throws -> [(PHAssetResource, URL)] {
  let resources = PHAssetResource.assetResources(for: asset)
  await logDebug(logger, "asset.resources count=\(resources.count) asset=\(asset.localIdentifier)")

  var exported: [(PHAssetResource, URL)] = []
  exported.reserveCapacity(resources.count)

  var failures: [String] = []

  let opts = PHAssetResourceRequestOptions()
  opts.isNetworkAccessAllowed = true

  for (idx, r) in resources.enumerated() {
    let typeLabel = resourceTypeLabel(r.type)
    let filename = filenameForResource(asset: asset, resource: r, captureDate: captureDate, usedNames: &usedNames)
    let finalURL = folder.appendingPathComponent(filename)

    if incremental && FileManager.default.fileExists(atPath: finalURL.path) {
      await logDebug(logger, "asset.resource.skip existing asset=\(asset.localIdentifier) type=\(typeLabel) dest=\(finalURL.path)")
      exported.append((r, finalURL))
      continue
    }

    if !incremental && FileManager.default.fileExists(atPath: finalURL.path) {
      do {
        await logDebug(logger, "asset.resource.overwrite remove dest=\(finalURL.path)")
        try FileManager.default.removeItem(at: finalURL)
      } catch {
        let line = "\(Date()) asset=\(asset.localIdentifier) capture=\(captureTimestampString(captureDate)) resourceType=\(typeLabel) uti=\(r.uniformTypeIdentifier) name=\(r.originalFilename) dest=\(finalURL.path) removeExistingFailed \(errorDetails(error))"
        logError(line)
        await logDebug(logger, "asset.resource.overwrite failed \(line)")
        appendLine(line, to: errorLogURL)
        continue
      }
    }

    await logDebug(logger, "asset.resource.start asset=\(asset.localIdentifier) index=\(idx + 1)/\(resources.count) type=\(typeLabel) uti=\(r.uniformTypeIdentifier) name=\(r.originalFilename) dest=\(finalURL.path)")

    do {
      try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
        PHAssetResourceManager.default().writeData(for: r, toFile: finalURL, options: opts) { err in
          if let err = err {
            cont.resume(throwing: err)
          } else {
            cont.resume(returning: ())
          }
        }
      }
    } catch {
      let detail = errorDetails(error)
      let line = "\(Date()) asset=\(asset.localIdentifier) capture=\(captureTimestampString(captureDate)) resourceType=\(typeLabel) uti=\(r.uniformTypeIdentifier) name=\(r.originalFilename) dest=\(finalURL.path) \(detail)"
      failures.append("type=\(typeLabel) uti=\(r.uniformTypeIdentifier) name=\(r.originalFilename) dest=\(finalURL.lastPathComponent) \(detail)")

      logError(line)
      await logDebug(logger, "asset.resource.failed \(line)")
      appendLine(line, to: errorLogURL)
      continue
    }

    if let attrs = try? FileManager.default.attributesOfItem(atPath: finalURL.path),
       let size = attrs[.size] as? NSNumber {
      await logDebug(logger, "asset.resource.done asset=\(asset.localIdentifier) type=\(typeLabel) path=\(finalURL.path) bytes=\(size.int64Value)")
    } else {
      await logDebug(logger, "asset.resource.done asset=\(asset.localIdentifier) type=\(typeLabel) path=\(finalURL.path)")
    }

    exported.append((r, finalURL))
  }

  if !failures.isEmpty {
    let capture = captureTimestampString(captureDate)
    let meta = "asset=\(asset.localIdentifier) capture=\(capture) mediaType=\(asset.mediaType.rawValue) subtypes=\(asset.mediaSubtypes.rawValue) px=\(asset.pixelWidth)x\(asset.pixelHeight) dur=\(asset.duration)"
    let failureSummary = failures.joined(separator: "; ")

    appendBlock(
      "\(Date()) asset.failed \(meta) failures=\(failures.count)/\(resources.count)",
      lines: failures,
      to: errorLogURL
    )

    throw NSError(
      domain: "PhotosExport",
      code: 20,
      userInfo: [
        NSLocalizedDescriptionKey: "One or more resources failed to export (\(failures.count)/\(resources.count)) \(meta). Failed: \(failureSummary)",
        PhotosExportErrorInfoKey.assetIdentifier: asset.localIdentifier,
        PhotosExportErrorInfoKey.captureTimestamp: capture,
        PhotosExportErrorInfoKey.mediaType: asset.mediaType.rawValue,
        PhotosExportErrorInfoKey.mediaSubtypes: asset.mediaSubtypes.rawValue,
        PhotosExportErrorInfoKey.pixelSize: "\(asset.pixelWidth)x\(asset.pixelHeight)",
        PhotosExportErrorInfoKey.duration: asset.duration,
        PhotosExportErrorInfoKey.failedResources: failures,
      ]
    )
  }

  return exported
}

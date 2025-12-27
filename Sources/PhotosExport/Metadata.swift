import Foundation
import Photos
import ImageIO
import CoreLocation
@preconcurrency import AVFoundation

@MainActor
func jsonSafe(_ value: Any) -> Any {
  switch value {
  case let v as String: return v
  case let v as NSNumber: return v
  case is NSNull: return value
  case let v as Date: return isoTimestamp(v)
  case let v as URL: return v.absoluteString
  case let v as Data: return v.base64EncodedString()
  case let v as [Any]: return v.map { jsonSafe($0) }
  case let v as [String: Any]: return jsonSafeDict(v)
  default: return String(describing: value)
  }
}

@MainActor
func jsonSafeDict(_ dict: [String: Any]) -> [String: Any] {
  var out: [String: Any] = [:]
  for (k, v) in dict {
    out[k] = jsonSafe(v)
  }
  return out
}

@MainActor
func avMetadataItemsToJSON(_ items: [AVMetadataItem]) async -> [[String: Any]] {
  var result: [[String: Any]] = []
  result.reserveCapacity(items.count)

  for item in items {
    var entry: [String: Any] = [:]
    if let id = item.identifier?.rawValue { entry["identifier"] = id }
    if let key = item.key?.description { entry["key"] = key }
    if let common = item.commonKey?.rawValue { entry["commonKey"] = common }

    if #available(macOS 13.0, *) {
      if let stringValue = try? await item.load(.stringValue) {
        entry["value"] = stringValue
      } else if let numberValue = try? await item.load(.numberValue) {
        entry["value"] = numberValue
      } else if let dateValue = try? await item.load(.dateValue) {
        entry["value"] = isoTimestamp(dateValue)
      } else if let dataValue = try? await item.load(.dataValue) {
        entry["valueBase64"] = dataValue.base64EncodedString()
      }
    } else {
      if let stringValue = item.stringValue {
        entry["value"] = stringValue
      } else if let numberValue = item.numberValue {
        entry["value"] = numberValue
      } else if let dateValue = item.dateValue {
        entry["value"] = isoTimestamp(dateValue)
      } else if let dataValue = item.dataValue {
        entry["valueBase64"] = dataValue.base64EncodedString()
      }
    }

    if !entry.isEmpty {
      result.append(entry)
    }
  }

  return result
}

@MainActor
func extractMetadata(asset: PHAsset, logger: LineLogger? = nil) async -> [String: Any] {
  var metadata: [String: Any] = [:]

  metadata["localIdentifier"] = asset.localIdentifier
  metadata["mediaType"] = asset.mediaType.rawValue
  metadata["mediaSubtypes"] = asset.mediaSubtypes.rawValue
  metadata["pixelWidth"] = asset.pixelWidth
  metadata["pixelHeight"] = asset.pixelHeight
  metadata["duration"] = asset.duration
  metadata["favorite"] = asset.isFavorite
  metadata["hidden"] = asset.isHidden
  metadata["playbackStyle"] = asset.playbackStyle.rawValue
  metadata["isLivePhoto"] = asset.mediaSubtypes.contains(.photoLive)
  metadata["isPanorama"] = asset.mediaSubtypes.contains(.photoPanorama)
  metadata["isHDR"] = asset.mediaSubtypes.contains(.photoHDR)
  metadata["isScreenshot"] = asset.mediaSubtypes.contains(.photoScreenshot)
  metadata["isDepthEffect"] = asset.mediaSubtypes.contains(.photoDepthEffect)
  metadata["isHighFrameRateVideo"] = asset.mediaSubtypes.contains(.videoHighFrameRate)
  metadata["isTimeLapseVideo"] = asset.mediaSubtypes.contains(.videoTimelapse)

  if let creationDate = asset.creationDate { metadata["creationDate"] = isoTimestamp(creationDate) }
  if let modificationDate = asset.modificationDate { metadata["modificationDate"] = isoTimestamp(modificationDate) }

  if let location = asset.location {
    var locationInfo: [String: Any] = [:]
    locationInfo["latitude"] = location.coordinate.latitude
    locationInfo["longitude"] = location.coordinate.longitude
    if location.altitude != 0 { locationInfo["altitude"] = location.altitude }
    if location.speed >= 0 { locationInfo["speed"] = location.speed }
    if location.course >= 0 { locationInfo["course"] = location.course }
    if location.horizontalAccuracy >= 0 { locationInfo["horizontalAccuracy"] = location.horizontalAccuracy }
    if location.verticalAccuracy >= 0 { locationInfo["verticalAccuracy"] = location.verticalAccuracy }
    metadata["location"] = locationInfo

    do {
      let geocoder = CLGeocoder()
      let placemarks = try await geocoder.reverseGeocodeLocation(location)
      if let placemark = placemarks.first {
        var place: [String: Any] = [:]
        if let v = placemark.name { place["name"] = v }
        if let v = placemark.locality { place["locality"] = v }
        if let v = placemark.subLocality { place["subLocality"] = v }
        if let v = placemark.administrativeArea { place["administrativeArea"] = v }
        if let v = placemark.subAdministrativeArea { place["subAdministrativeArea"] = v }
        if let v = placemark.postalCode { place["postalCode"] = v }
        if let v = placemark.country { place["country"] = v }
        if let v = placemark.isoCountryCode { place["isoCountryCode"] = v }
        if let v = placemark.ocean { place["ocean"] = v }
        if let v = placemark.inlandWater { place["inlandWater"] = v }
        if let v = placemark.areasOfInterest, !v.isEmpty { place["areasOfInterest"] = v }
        if !place.isEmpty { metadata["placemark"] = place }
      }
    } catch {
      await logDebug(logger, "metadata.geocode failed asset=\(asset.localIdentifier) error=\(error)")
    }
  }

  metadata["sourceType"] = asset.sourceType.rawValue
  if let burstIdentifier = asset.burstIdentifier {
    metadata["burstIdentifier"] = burstIdentifier
    metadata["burstSelectionTypes"] = asset.burstSelectionTypes.rawValue
  }

  let resources = PHAssetResource.assetResources(for: asset)
  metadata["resources"] = resources.map { r in
    [
      "type": r.type.rawValue,
      "originalFilename": r.originalFilename,
      "uniformTypeIdentifier": r.uniformTypeIdentifier
    ]
  }

  // Extract data from PHContentEditingInput in the completion handler to avoid sending non-Sendable types
  nonisolated(unsafe) let contentData: (uniformType: String?, orientation: Int32, livePhotoId: String?, adjustmentData: [String: Any]?, avAsset: AVAsset?, fullSizeImageURL: URL?)? = await withUnsafeContinuation { cont in
    let opts = PHContentEditingInputRequestOptions()
    opts.isNetworkAccessAllowed = true
    asset.requestContentEditingInput(with: opts) { input, _ in
      guard let input = input else {
        cont.resume(returning: nil)
        return
      }
      let uniformType = input.uniformTypeIdentifier
      let orientation = input.fullSizeImageOrientation
      let livePhotoId = input.value(forKey: "livePhotoPairingIdentifier") as? String
      let adjustmentData: [String: Any]? = input.adjustmentData.map { adj in
        [
          "formatIdentifier": adj.formatIdentifier,
          "formatVersion": adj.formatVersion,
          "dataBase64": adj.data.base64EncodedString()
        ]
      }
      let avAsset = input.audiovisualAsset
      let fullSizeImageURL = input.fullSizeImageURL
      cont.resume(returning: (uniformType, orientation, livePhotoId, adjustmentData, avAsset, fullSizeImageURL))
    }
  }
  
  if let data = contentData {
    metadata["contentUniformType"] = data.uniformType
    metadata["fullSizeImageOrientation"] = data.orientation
    if let livePhotoId = data.livePhotoId {
      metadata["livePhotoPairingIdentifier"] = livePhotoId
    }
    if let adjustmentData = data.adjustmentData {
      metadata["adjustmentData"] = adjustmentData
    }
  }

  if let avAsset = contentData?.avAsset {
    if #available(macOS 13.0, *) {
      if let duration = try? await avAsset.load(.duration) {
        metadata["avAssetDurationSeconds"] = CMTimeGetSeconds(duration)
      }
      if let tracks = try? await avAsset.loadTracks(withMediaType: .video), let videoTrack = tracks.first {
        if let size = try? await videoTrack.load(.naturalSize) {
          metadata["avVideoDimensions"] = ["width": size.width, "height": size.height]
        }
      }
      if let items = try? await avAsset.load(.metadata) {
        metadata["avMetadata"] = await avMetadataItemsToJSON(items)
      }
    } else {
      metadata["avAssetDurationSeconds"] = CMTimeGetSeconds(avAsset.duration)
      if let videoTrack = avAsset.tracks(withMediaType: .video).first {
        metadata["avVideoDimensions"] = [
          "width": videoTrack.naturalSize.width,
          "height": videoTrack.naturalSize.height
        ]
      }
      metadata["avMetadata"] = await avMetadataItemsToJSON(avAsset.metadata)
    }
  }

  if let url = contentData?.fullSizeImageURL,
     let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
     let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] {
    metadata["imageProperties"] = jsonSafeDict(imageProperties)

    if let exif = imageProperties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
      let safeExif = jsonSafeDict(exif)
      metadata["exif"] = safeExif
      var camera: [String: Any] = metadata["camera"] as? [String: Any] ?? [:]
      if let v = exif["LensModel"] as? String { camera["lensModel"] = v }
      if let v = exif["LensMake"] as? String { camera["lensMake"] = v }
      if let v = exif["LensSerialNumber"] as? String { camera["lensSerialNumber"] = v }
      if let v = exif["BodySerialNumber"] as? String { camera["bodySerialNumber"] = v }
      if !camera.isEmpty { metadata["camera"] = camera }
    }

    if let gps = imageProperties[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
      metadata["gps"] = jsonSafeDict(gps)
    }

    if let tiff = imageProperties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
      let safeTiff = jsonSafeDict(tiff)
      metadata["tiff"] = safeTiff
      var camera = metadata["camera"] as? [String: Any] ?? [:]
      if let v = tiff["Model"] as? String { camera["model"] = v }
      if let v = tiff["Make"] as? String { camera["make"] = v }
      if !camera.isEmpty { metadata["camera"] = camera }
    }

    if let iptc = imageProperties[kCGImagePropertyIPTCDictionary as String] as? [String: Any] {
      let safeIptc = jsonSafeDict(iptc)
      metadata["iptc"] = safeIptc
      if let keywords = iptc[kCGImagePropertyIPTCKeywords as String] as? [String], !keywords.isEmpty {
        metadata["keywords"] = keywords
      }
      if let caption = iptc[kCGImagePropertyIPTCCaptionAbstract as String] as? String, !caption.isEmpty {
        metadata["caption"] = caption
      }
    }

    if let xmp = imageProperties["{XMP}"] as? [String: Any] {
      metadata["xmp"] = jsonSafeDict(xmp)
    }

    if let makerNote = imageProperties[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any] {
      metadata["makerApple"] = jsonSafeDict(makerNote)
    }
  }

  return metadata
}

@MainActor
func saveMetadataJSON(metadata: [String: Any], to url: URL, logger: LineLogger? = nil) async throws {
  let jsonData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
  try jsonData.write(to: url)

  if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
     let size = attrs[.size] as? NSNumber {
    await logDebug(logger, "metadata.json.saved path=\(url.path) bytes=\(size.int64Value)")
  } else {
    await logDebug(logger, "metadata.json.saved path=\(url.path)")
  }
}

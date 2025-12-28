import Foundation
import Photos
import UniformTypeIdentifiers

@main
enum Main {
  @MainActor
  static func main() async {
    let settings: Settings
    do {
      settings = try parseSettings(CommandLine.arguments)
    } catch {
      fputs("Invalid arguments: \(error)\n", stderr)
      fputs("Usage: PhotosExport [--debug] [--incremental] [--metadata] [--year YYYY] [--log-file /path/to/log] [--export-directory /path/to/export]\n", stderr)
      exit(2)
    }

    let fm = FileManager.default
    let exportBase = if let exportDirectory = settings.exportDirectory {
        exportDirectory
    } else {
      fm.homeDirectoryForCurrentUser.appendingPathComponent(
        "Pictures/Exports",
        isDirectory: true
      )
    }
    let errorLog = exportBase.appendingPathComponent("export_errors.log")

    do {
      let debugLogger: LineLogger?
      if let logFile = settings.logFile {
        try await ensureDir(logFile.deletingLastPathComponent(), logger: nil)
        debugLogger = try? LineLogger(fileURL: logFile)
      } else if settings.debug {
        debugLogger = LineLogger(handle: .standardError)
      } else {
        debugLogger = nil
      }

      try await ensureDir(exportBase, logger: debugLogger)

      if settings.debug {
        fputs("Export base: \(exportBase.path)\n", stderr)
        fputs("Errors log:  \(errorLog.path)\n", stderr)
        if let logFile = settings.logFile {
          fputs("Debug log:   \(logFile.path)\n", stderr)
        }
      }

      await logDebug(debugLogger, "run.start cwd=\(fm.currentDirectoryPath) exportBase=\(exportBase.path)")

      try await requestPhotosAccess(logger: debugLogger)

      let (start, end) = settings.yearOverride.map(yearRange) ?? currentYearRange()
      await logDebug(debugLogger, "fetch.range start=\(isoTimestamp(start)) end=\(isoTimestamp(end))")

      let opts = PHFetchOptions()
      opts.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@", start as NSDate, end as NSDate)
      let assets = PHAsset.fetchAssets(with: opts)

      let total = assets.count
      var exported = 0
      var bar = ProgressBar(total: max(1, total))

      await logDebug(debugLogger, "fetch.done total=\(total)")

      if total == 0 {
        print("No assets found for current year.")
        return
      }

      await logDebug(debugLogger, "iterate.begin total=\(total)")
      for idx in 0..<total {
        let asset = assets.object(at: idx)
        let mediaLabel = asset.mediaType == .video ? "video" : "photo"
        let label = "\(idx + 1)/\(total) \(mediaLabel)"
        do {
          await logDebug(debugLogger, "asset.start index=\(idx + 1) total=\(total) id=\(asset.localIdentifier) mediaType=\(asset.mediaType.rawValue)")

          let date: Date
          if let creationDate = asset.creationDate {
            date = creationDate
          } else {
            date = Date()
            logWarn("asset=\(asset.localIdentifier) missing creationDate; using current time")
          }

          let y = yearString(date)
          let m = monthString(date)

          let folder = exportBase.appendingPathComponent(y, isDirectory: true).appendingPathComponent(m, isDirectory: true)
          try await ensureDir(folder, logger: debugLogger)
          await logDebug(debugLogger, "asset.folder asset=\(asset.localIdentifier) folder=\(folder.path)")

          var usedNames = Set<String>()
          let exportedResources = try await exportAllResources(
            asset: asset,
            captureDate: date,
            to: folder,
            incremental: settings.incremental,
            errorLogURL: errorLog,
            logger: debugLogger,
            usedNames: &usedNames
          )

          if settings.metadata {
            let sidecarName = exportFilename(
              captureDate: date,
              // Don't inherit the extension from any exported resource (e.g., .heic).
              // We always want a JSON sidecar.
              originalFilename: "",
              fallbackSeed: "asset=\(asset.localIdentifier)|metadata",
              uti: UTType.json.identifier,
              usedNames: &usedNames
            )
            let sidecarURL = folder.appendingPathComponent(sidecarName)

            var metadata = await extractMetadata(asset: asset, logger: debugLogger)

            metadata["exportedFiles"] = exportedResources.map { res, url in
              var entry: [String: Any] = [
                "type": res.type.rawValue,
                "uniformTypeIdentifier": res.uniformTypeIdentifier,
                "originalFilename": res.originalFilename,
                "exportedFilename": url.lastPathComponent,
                "path": url.lastPathComponent
              ]
              if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
                if let size = attrs[.size] as? NSNumber { entry["fileSize"] = size }
                if let mod = attrs[.modificationDate] as? Date { entry["fileModificationDate"] = isoTimestamp(mod) }
              }
              return entry
            }

            try await saveMetadataJSON(metadata: metadata, to: sidecarURL, logger: debugLogger)
          }

          exported += 1
          bar.tick(label + " ✓")
        } catch {
          let ns = error as NSError
          var line = "\(Date()) asset=\(asset.localIdentifier) index=\(idx + 1)/\(total) \(errorDetails(error))"
          if ns.domain == "PhotosExport", ns.code == 20 {
            if let capture = ns.userInfo[PhotosExportErrorInfoKey.captureTimestamp] as? String {
              line += " capture=\(capture)"
            }
            if let px = ns.userInfo[PhotosExportErrorInfoKey.pixelSize] as? String {
              line += " px=\(px)"
            }
            if let failed = ns.userInfo[PhotosExportErrorInfoKey.failedResources] as? [String], !failed.isEmpty {
              line += " failedCount=\(failed.count)"
              appendBlock(
                "\(Date()) asset.failed.details asset=\(asset.localIdentifier) index=\(idx + 1)/\(total)",
                lines: failed,
                to: errorLog
              )
            }
          }

          appendLine(line, to: errorLog)
          logError("asset.error \(line)")
          await logDebug(debugLogger, "asset.error \(line)")
          bar.tick(label + " ✗")
        }
      }

      await logDebug(debugLogger, "run.done exported=\(exported) total=\(total)")
      print("Export complete: \(exported) of \(total) assets exported to \(exportBase.path)")
      if fm.fileExists(atPath: errorLog.path) {
        print("Errors logged to: \(errorLog.path)")
      }
    } catch {
      fputs("Fatal: \(error)\n", stderr)
      if (error as NSError).domain == "PhotosExport", (error as NSError).code == 1 {
        fputs("Hint: macOS Photos permission is denied. Enable Photos access for the launching app (often Terminal) in System Settings -> Privacy & Security -> Photos, then re-run.\n", stderr)
      }
      exit(1)
    }
  }
}

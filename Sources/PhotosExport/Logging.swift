import Foundation

actor LineLogger {
  private let handle: FileHandle

  init(handle: FileHandle) {
    self.handle = handle
  }

  init(fileURL: URL) throws {
    if !FileManager.default.fileExists(atPath: fileURL.path) {
      FileManager.default.createFile(atPath: fileURL.path, contents: nil)
    }
    self.handle = try FileHandle(forWritingTo: fileURL)
    try self.handle.seekToEnd()
  }

  func log(_ message: String) {
    let line = "\(isoTimestamp()) \(message)\n"
    if let data = line.data(using: .utf8) {
      do {
        try handle.write(contentsOf: data)
      } catch {
        // Best-effort logging; ignore failures.
      }
    }
  }
}

func logDebug(_ logger: LineLogger?, _ message: String) async {
  await logger?.log(message)
}

func logWarn(_ message: String) {
  fputs("Warning: \(message)\n", stderr)
}

func logError(_ message: String) {
  fputs("Error: \(message)\n", stderr)
}

func errorDetails(_ error: Error) -> String {
  let ns = error as NSError
  var parts: [String] = ["domain=\(ns.domain)", "code=\(ns.code)"]
  if !ns.localizedDescription.isEmpty {
    parts.append("desc=\(ns.localizedDescription)")
  }
  if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
    parts.append("underlying=\(underlying.domain)(\(underlying.code))")
    if !underlying.localizedDescription.isEmpty {
      parts.append("underDesc=\(underlying.localizedDescription)")
    }
  }
  if let reason = ns.userInfo[NSLocalizedFailureReasonErrorKey] as? String, !reason.isEmpty {
    parts.append("reason=\(reason)")
  }
  if let recovery = ns.userInfo[NSLocalizedRecoverySuggestionErrorKey] as? String, !recovery.isEmpty {
    parts.append("recovery=\(recovery)")
  }
  return parts.joined(separator: " ")
}

func appendLine(_ line: String, to url: URL) {
  guard let data = (line + "\n").data(using: .utf8) else { return }
  if FileManager.default.fileExists(atPath: url.path) == false {
    FileManager.default.createFile(atPath: url.path, contents: nil)
  }
  if let handle = try? FileHandle(forWritingTo: url) {
    _ = try? handle.seekToEnd()
    try? handle.write(contentsOf: data)
    try? handle.close()
  }
}

func appendBlock(_ header: String, lines: [String], to url: URL) {
  appendLine(header, to: url)
  for l in lines {
    appendLine("  \(l)", to: url)
  }
}

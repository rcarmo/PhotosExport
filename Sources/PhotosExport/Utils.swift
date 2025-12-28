import Foundation

func isoTimestamp(_ date: Date = Date()) -> String {
  let f = ISO8601DateFormatter()
  f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return f.string(from: date)
}

func captureTimestampString(_ date: Date) -> String {
  let f = DateFormatter()
  f.locale = Locale(identifier: "en_US_POSIX")
  f.calendar = Calendar(identifier: .gregorian)
  f.timeZone = TimeZone.current
  f.dateFormat = "yyyyMMddHHmmss"
  return f.string(from: date)
}

func fnv1a64(_ s: String) -> UInt64 {
  let prime: UInt64 = 1099511628211
  var hash: UInt64 = 14695981039346656037
  for b in s.utf8 {
    hash ^= UInt64(b)
    hash &*= prime
  }
  return hash
}

func alphaLetter(from hash: UInt64, offset: Int = 0) -> Character {
  let idx = Int((hash % 26) + UInt64((offset % 26 + 26) % 26)) % 26
  return Character(UnicodeScalar(97 + idx)!)
}

func sanitize(_ s: String) -> String {
  return s.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "-")
}

func monthString(_ date: Date) -> String {
  let cal = Calendar(identifier: .gregorian)
  let m = cal.component(.month, from: date)
  return String(format: "%02d", m)
}

func yearString(_ date: Date) -> String {
  let cal = Calendar(identifier: .gregorian)
  return String(cal.component(.year, from: date))
}

func yearRange(startYear: Int, endYear: Int) -> (start: Date, end: Date) {
  var cal = Calendar(identifier: .gregorian)
  // Use a stable timezone to avoid DST/locale edge cases when building date boundaries.
  cal.timeZone = TimeZone(secondsFromGMT: 0)!
  let start = cal.date(from: DateComponents(year: startYear, month: 1, day: 1, hour: 0, minute: 0, second: 0))!
  let end = cal.date(from: DateComponents(year: endYear, month: 12, day: 31, hour: 23, minute: 59, second: 59))!
  return (start, end)
}

func currentYearRange() -> (start: Date, end: Date) {
  let cal = Calendar(identifier: .gregorian)
  let now = Date()
  let year = cal.component(.year, from: now)
  return yearRange(startYear: year, endYear: year)
}

func ensureDir(_ url: URL, logger: LineLogger? = nil) async throws {
  var isDir: ObjCBool = false
  if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
    if isDir.boolValue {
      await logDebug(logger, "fs.dir exists path=\(url.path)")
      return
    }
    throw NSError(domain: "PhotosExport", code: 10, userInfo: [NSLocalizedDescriptionKey: "Path exists but is not a directory: \(url.path)"])
  }

  await logDebug(logger, "fs.dir create path=\(url.path)")
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
}

struct ProgressBar {
  let total: Int
  var current: Int = 0
  let width: Int = 32
  let start = Date()

  mutating func tick(_ label: String) {
    current += 1
    let pct = total == 0 ? 1.0 : Double(current) / Double(total)
    let filled = Int(Double(width) * pct)
    let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: max(0, width - filled))
    let elapsed = Int(Date().timeIntervalSince(start))
    let line = String(format: "\r[%@] %3d%% %d/%d %ds  %@", bar, Int(pct * 100), current, total, elapsed, label)
    FileHandle.standardError.write(Data(line.utf8))
    if current == total {
      FileHandle.standardError.write(Data("\n".utf8))
    }
  }
}

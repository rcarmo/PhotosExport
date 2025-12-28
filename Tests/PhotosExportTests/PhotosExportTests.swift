import XCTest
@testable import PhotosExport

final class PhotosExportTests: XCTestCase {
  private func makeTempDir(prefix: String = "photosexport-tests") throws -> URL {
    let base = FileManager.default.temporaryDirectory
    let dir = base.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  func testParseSettingsIncrementalFlag() {
    let s = try! parseSettings(["PhotosExport", "--incremental"])
    XCTAssertTrue(s.incremental)
    XCTAssertFalse(s.debug)
  }

  func testParseSettingsMetadataFlag() {
    let s = try! parseSettings(["PhotosExport", "--metadata"])
    XCTAssertTrue(s.metadata)
    XCTAssertFalse(s.incremental)
  }

  func testParseSettingsDebugFlag() {
    let s = try! parseSettings(["PhotosExport", "--debug"])
    XCTAssertTrue(s.debug)
    XCTAssertFalse(s.incremental)
    XCTAssertFalse(s.metadata)
  }

  func testParseSettingsLogFile() throws {
    let tmp = try makeTempDir(prefix: "logfile")
    let log = tmp.appendingPathComponent("run.log")
    let s = try parseSettings(["PhotosExport", "--log-file", log.path])
    XCTAssertEqual(s.logFile?.standardizedFileURL.path, log.standardizedFileURL.path)
  }

  func testParseSettingsLogFileMissingArgThrows() {
    XCTAssertThrowsError(try parseSettings(["PhotosExport", "--log-file"]))
  }

  func testParseSettingsYearOverrideValid() {
    let s = try! parseSettings(["PhotosExport", "--year", "2024"])
    XCTAssertEqual(s.yearOverride, Settings.YearOverride(startYear: 2024, endYear: 2024))

    let s1 = try! parseSettings(["PhotosExport", "--start-year", "2024"])
    XCTAssertEqual(s1.yearOverride, s.yearOverride)

    let s2 = try! parseSettings(["PhotosExport", "--end-year", "2024"])
    XCTAssertEqual(s2.yearOverride, s.yearOverride)

    let s3 = try! parseSettings(["PhotosExport", "--start-year", "2022", "--end-year", "2025"])
    XCTAssertEqual(s3.yearOverride, Settings.YearOverride(startYear: 2022, endYear: 2025))
  }

  func testParseSettingsYearOverrideMissingValueThrows() {
    XCTAssertThrowsError(try parseSettings(["PhotosExport", "--year"]))
  }

  func testParseSettingsYearOverrideRejectsInvalid() {
    XCTAssertThrowsError(try parseSettings(["PhotosExport", "--year", "abcd"]))
    XCTAssertThrowsError(try parseSettings(["PhotosExport", "--year", "99"]))
    XCTAssertThrowsError(try parseSettings(["PhotosExport", "--year", "1969"]))
  }

  func testCaptureTimestampStringFormat() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    let date = cal.date(from: DateComponents(year: 2025, month: 12, day: 27, hour: 13, minute: 56, second: 27))!

    // This function uses TimeZone.current, so we can only assert the shape here.
    let s = captureTimestampString(date)
    XCTAssertEqual(s.count, 14)
    XCTAssertTrue(s.allSatisfy({ $0 >= "0" && $0 <= "9" }))
  }

  func testIsoTimestampLooksLikeISO8601WithFractionalSeconds() {
    let s = isoTimestamp(Date(timeIntervalSince1970: 0))
    XCTAssertTrue(s.contains("T"))
    XCTAssertTrue(s.contains("."))
    XCTAssertTrue(s.hasSuffix("Z"))
  }

  func testFNV1a64IsDeterministic() {
    XCTAssertEqual(fnv1a64("IMG_0001.JPG"), fnv1a64("IMG_0001.JPG"))
    XCTAssertNotEqual(fnv1a64("IMG_0001.JPG"), fnv1a64("IMG_0002.JPG"))
  }

  func testAlphaLetterMapsToLowercase() {
    let c0 = alphaLetter(from: 0)
    XCTAssertTrue(("a"..."z").contains(String(c0)))

    let c1 = alphaLetter(from: 123456789)
    XCTAssertTrue(("a"..."z").contains(String(c1)))
  }

  func testAlphaLetterOffsetWrapsAndHandlesNegative() {
    let base = alphaLetter(from: 0, offset: 0) // 'a'
    XCTAssertEqual(base, "a")
    XCTAssertEqual(alphaLetter(from: 0, offset: 1), "b")
    XCTAssertEqual(alphaLetter(from: 0, offset: 26), "a")
    XCTAssertEqual(alphaLetter(from: 0, offset: -1), "z")
    XCTAssertEqual(alphaLetter(from: 0, offset: -27), "z")
  }

  func testSanitizeReplacesSlashAndColon() {
    XCTAssertEqual(sanitize("a/b:c"), "a_b-c")
  }

  func testMonthAndYearString() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    let date = cal.date(from: DateComponents(year: 2025, month: 1, day: 2))!
    XCTAssertEqual(yearString(date), "2025")
    XCTAssertEqual(monthString(date), "01")
  }

  func testCurrentYearRangeIsSane() {
    let (start, end) = currentYearRange()
    XCTAssertLessThanOrEqual(start, end)
  }

  func testYearRangeBounds() {
    let (start, end) = yearRange(startYear: 2022, endYear: 2025)
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    XCTAssertEqual(cal.component(.year, from: start), 2022)
    XCTAssertEqual(cal.component(.month, from: start), 1)
    XCTAssertEqual(cal.component(.day, from: start), 1)
    XCTAssertEqual(cal.component(.hour, from: start), 0)
    XCTAssertEqual(cal.component(.minute, from: start), 0)
    XCTAssertEqual(cal.component(.second, from: start), 0)

    XCTAssertEqual(cal.component(.year, from: end), 2025)
    XCTAssertEqual(cal.component(.month, from: end), 12)
    XCTAssertEqual(cal.component(.day, from: end), 31)
    XCTAssertEqual(cal.component(.hour, from: end), 23)
    XCTAssertEqual(cal.component(.minute, from: end), 59)
    XCTAssertEqual(cal.component(.second, from: end), 59)
  }

  func testEnsureDirCreatesDirectory() async throws {
    let tmp = try makeTempDir(prefix: "ensuredir")
    let target = tmp.appendingPathComponent("nested/dir", isDirectory: true)
    try await ensureDir(target, logger: nil)
    var isDir: ObjCBool = false
    XCTAssertTrue(FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir))
    XCTAssertTrue(isDir.boolValue)
  }

  func testEnsureDirExistingDirectoryIsOk() async throws {
    let tmp = try makeTempDir(prefix: "ensuredir-exists")
    try await ensureDir(tmp, logger: nil)
    try await ensureDir(tmp, logger: nil)
  }

  func testEnsureDirThrowsIfPathIsAFile() async throws {
    let tmp = try makeTempDir(prefix: "ensuredir-file")
    let fileURL = tmp.appendingPathComponent("not-a-dir")
    FileManager.default.createFile(atPath: fileURL.path, contents: Data("x".utf8))
    do {
      try await ensureDir(fileURL, logger: nil)
      XCTFail("Expected ensureDir to throw for file path")
    } catch {
      let ns = error as NSError
      XCTAssertEqual(ns.domain, "PhotosExport")
      XCTAssertEqual(ns.code, 10)
    }
  }

  func testErrorDetailsIncludesDomainCodeAndUnderlying() {
    let underlying = NSError(domain: "Underlying", code: 42, userInfo: [NSLocalizedDescriptionKey: "boom"])
    let err = NSError(
      domain: "Top",
      code: 7,
      userInfo: [
        NSLocalizedDescriptionKey: "nope",
        NSUnderlyingErrorKey: underlying,
        NSLocalizedFailureReasonErrorKey: "because",
        NSLocalizedRecoverySuggestionErrorKey: "do the thing"
      ]
    )

    let s = errorDetails(err)
    XCTAssertTrue(s.contains("domain=Top"))
    XCTAssertTrue(s.contains("code=7"))
    XCTAssertTrue(s.contains("underlying=Underlying(42)"))
    XCTAssertTrue(s.contains("reason=because"))
    XCTAssertTrue(s.contains("recovery=do the thing"))
  }

  func testAppendLineAndBlockWriteExpectedContent() throws {
    let tmp = try makeTempDir(prefix: "append")
    let fileURL = tmp.appendingPathComponent("out.log")

    appendLine("one", to: fileURL)
    appendBlock("hdr", lines: ["a", "b"], to: fileURL)

    let contents = try String(contentsOf: fileURL, encoding: .utf8)
    XCTAssertTrue(contents.contains("one\n"))
    XCTAssertTrue(contents.contains("hdr\n"))
    XCTAssertTrue(contents.contains("  a\n"))
    XCTAssertTrue(contents.contains("  b\n"))
  }

  func testExportFilenameUsesHashedLetterAndIsStable() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    let date = cal.date(from: DateComponents(year: 2025, month: 1, day: 2, hour: 3, minute: 4, second: 5))!

    var usedA = Set<String>()
    let a = exportFilename(
      captureDate: date,
      originalFilename: "IMG_0001.JPG",
      fallbackSeed: "assetid",
      uti: "public.jpeg",
      usedNames: &usedA
    )

    var usedB = Set<String>()
    let b = exportFilename(
      captureDate: date,
      originalFilename: "IMG_0001.JPG",
      fallbackSeed: "assetid",
      uti: "public.jpeg",
      usedNames: &usedB
    )

    XCTAssertEqual(a, b)
    XCTAssertTrue(a.hasSuffix(".jpg"))
    XCTAssertEqual(a.count, 14 + 4) // YYYYMMDDHHMMSS + .ext
  }

  func testExportFilenameCollisionAdvancesLetter() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    let date = cal.date(from: DateComponents(year: 2025, month: 1, day: 2, hour: 3, minute: 4, second: 5))!

    var used = Set<String>()
    let base = exportFilename(
      captureDate: date,
      originalFilename: "IMG_0001.JPG",
      fallbackSeed: "assetid",
      uti: "public.jpeg",
      usedNames: &used
    )

    // Force a collision for the same timestamp.
    let b = exportFilename(
      captureDate: date,
      originalFilename: "IMG_0002.JPG",
      fallbackSeed: "assetid",
      uti: "public.jpeg",
      usedNames: &used
    )

    let c = exportFilename(
      captureDate: date,
      originalFilename: "IMG_0002.JPG",
      fallbackSeed: "assetid",
      uti: "public.jpeg",
      usedNames: &used
    )

    XCTAssertNotEqual(base, b)
    XCTAssertNotEqual(b, c)

    // Base has no letter; collisions do.
    XCTAssertEqual(base.count, 14 + 4)
    XCTAssertEqual(b.count, 14 + 1 + 4)
    XCTAssertEqual(c.count, 14 + 1 + 4)

    // Letter is deterministic from original filename (then advanced for further collisions).
    // Seed now includes name + metadata.
    let metaSeed = [
      "asset=assetid",
      "mediaType=0",
      "subtypes=0",
      "px=0x0",
      "dur=0.0",
      "resType=0",
      "uti=public.jpeg",
    ].joined(separator: "|")
    let h = fnv1a64("IMG_0002.JPG|\(metaSeed)")
    let expectedLetter = alphaLetter(from: h, offset: 0)
    XCTAssertEqual(b.dropLast(4).dropFirst(14).first, expectedLetter)
  }

  func testExportFilenameWrapsAfterZToA() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    let date = cal.date(from: DateComponents(year: 2025, month: 1, day: 2, hour: 3, minute: 4, second: 5))!

    let ts = captureTimestampString(date)
    let metaSeed = "meta"

    // Find an originalFilename whose collision-seed hashes to a 'z' (mod 26 == 25).
    var nameForZ: String? = nil
    for i in 0..<50_000 {
      let candidate = "name_\(i).JPG"
      let seed = "\(candidate)|\(metaSeed)"
      if fnv1a64(seed) % 26 == 25 {
        nameForZ = candidate
        break
      }
    }
    guard let nameForZ else {
      XCTFail("Failed to find seed mapping to z")
      return
    }

    var used = Set<String>()
    // Force base collision first.
    _ = exportFilename(
      captureDate: date,
      originalFilename: nameForZ,
      fallbackSeed: metaSeed,
      uti: "public.jpeg",
      usedNames: &used
    )

    // Force 'z' collision next, so it must wrap to 'a'.
    used.insert("\(ts)z.jpg")

    let wrapped = exportFilename(
      captureDate: date,
      originalFilename: nameForZ,
      fallbackSeed: metaSeed,
      uti: "public.jpeg",
      usedNames: &used
    )

    XCTAssertEqual(wrapped, "\(ts)a.jpg")
  }
}

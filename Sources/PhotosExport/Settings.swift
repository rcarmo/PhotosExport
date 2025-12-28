import Foundation

enum SettingsError: Error, LocalizedError {
  case missingValue(String)
  case invalidYear(String)

  var errorDescription: String? {
    switch self {
    case .missingValue(let flag):
      return "Missing value for \(flag)"
    case .invalidYear(let raw):
      return "Invalid year '\(raw)'. Expected a valid integer."
    }
  }
}

struct Settings {
  var logFile: URL? = nil
  var debug: Bool = false
  var incremental: Bool = false
  var metadata: Bool = false

  struct YearOverride: Equatable {
    var startYear: Int
    var endYear: Int
  }
  var yearOverride: YearOverride? = nil
}

func parseSettings(_ args: [String]) throws -> Settings {
  var settings = Settings()
  var i = 1
  while i < args.count {
    switch args[i] {
    case "--debug":
      settings.debug = true
      i += 1
    case "--incremental":
      settings.incremental = true
      i += 1
    case "--metadata":
      settings.metadata = true
      i += 1
    case "--year":
      guard i + 1 < args.count else {
        throw SettingsError.missingValue("--year")
      }
      let raw = args[i + 1]
      guard let year = Int(raw) else {
        throw SettingsError.invalidYear(raw)
      }
      settings.yearOverride = Settings.YearOverride(startYear: year, endYear: year)
      i += 2
    case "--start-year":
        guard i + 1 < args.count else {
            throw SettingsError.missingValue("--start-year")
        }
        let raw = args[i + 1]
        guard let year = Int(raw) else {
            throw SettingsError.invalidYear(raw)
        }
        if settings.yearOverride != nil {
            settings.yearOverride?.startYear = year
        } else {
            settings.yearOverride = Settings.YearOverride(startYear: year, endYear: year)
        }
        i += 2
    case "--end-year":
        guard i + 1 < args.count else {
            throw SettingsError.missingValue("--end-year")
        }
        let raw = args[i + 1]
        guard let year = Int(raw) else {
            throw SettingsError.invalidYear(raw)
        }
        if settings.yearOverride != nil {
            settings.yearOverride?.endYear = year
        } else {
            settings.yearOverride = Settings.YearOverride(startYear: year, endYear: year)
        }
        i += 2
    case "--log-file":
      if i + 1 < args.count {
        settings.logFile = URL(fileURLWithPath: args[i + 1]).standardizedFileURL
        i += 2
      } else {
        throw SettingsError.missingValue("--log-file")
      }
    default:
      i += 1
    }
  }
  return settings
}

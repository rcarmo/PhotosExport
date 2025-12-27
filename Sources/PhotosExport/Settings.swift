import Foundation

struct Settings {
  var logFile: URL? = nil
  var debug: Bool = false
  var incremental: Bool = false
  var metadata: Bool = false
}

func parseSettings(_ args: [String]) -> Settings {
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
    case "--log-file":
      if i + 1 < args.count {
        settings.logFile = URL(fileURLWithPath: args[i + 1]).standardizedFileURL
        i += 2
      } else {
        i += 1
      }
    default:
      i += 1
    }
  }
  return settings
}

import Foundation

/// The action requested on the command line.
public enum CLIAction: Equatable, Sendable {
  /// Initialize the single connected camera, or the one at the given USB
  /// location ID when the user selected one with --device.
  case initialize(deviceLocation: UInt32?)
  case list
  case help
}

/// A command line misuse. Reported on stderr with exit status 2.
public struct UsageError: Error, Equatable, Sendable {
  public let message: String

  public init(message: String) {
    self.message = message
  }
}

/// Parses a USB location ID as written on the command line: an optional
/// "0x" prefix followed by one to eight hexadecimal digits.
public func parseLocationID(_ raw: String) -> UInt32? {
  var digits = raw
  if digits.hasPrefix("0x") || digits.hasPrefix("0X") {
    digits.removeFirst(2)
  }
  guard !digits.isEmpty, digits.count <= 8, digits.allSatisfy(\.isHexDigit) else {
    return nil
  }
  return UInt32(digits, radix: 16)
}

/// Parses the full argument vector. Anything unknown, duplicated, conflicting,
/// or with a malformed location ID is a `UsageError` (exit status 2).
public func parseArguments(_ arguments: [String]) -> Result<CLIAction, UsageError> {
  var helpRequested = false
  var listRequested = false
  var deviceLocation: UInt32?
  var deviceRequested = false
  var index = 0

  while index < arguments.count {
    let argument = arguments[index]
    switch argument {
    case "--help":
      if helpRequested {
        return .failure(UsageError(message: "--help may be given only once."))
      }
      helpRequested = true
      index += 1
    case "--list":
      if listRequested {
        return .failure(UsageError(message: "--list may be given only once."))
      }
      listRequested = true
      index += 1
    case "--device":
      if deviceRequested {
        return .failure(UsageError(message: "--device may be given only once."))
      }
      guard index + 1 < arguments.count else {
        return .failure(UsageError(message: missingDeviceValueMessage))
      }
      switch parseDeviceValue(arguments[index + 1]) {
      case .success(let location):
        deviceRequested = true
        deviceLocation = location
        index += 2
      case .failure(let error):
        return .failure(error)
      }
    default:
      if argument.hasPrefix("--device=") {
        if deviceRequested {
          return .failure(UsageError(message: "--device may be given only once."))
        }
        switch parseDeviceValue(String(argument.dropFirst("--device=".count))) {
        case .success(let location):
          deviceRequested = true
          deviceLocation = location
          index += 1
        case .failure(let error):
          return .failure(error)
        }
      } else if argument.hasPrefix("-") {
        return .failure(UsageError(message: "unknown option '\(argument)'."))
      } else {
        return .failure(
          UsageError(
            message: "unexpected argument '\(argument)'; rf4 takes no positional arguments."
          )
        )
      }
    }
  }

  if helpRequested {
    if listRequested {
      return .failure(UsageError(message: "options --help and --list cannot be combined."))
    }
    if deviceRequested {
      return .failure(UsageError(message: "options --help and --device cannot be combined."))
    }
    return .success(.help)
  }
  if listRequested {
    if deviceRequested {
      return .failure(UsageError(message: "options --list and --device cannot be combined."))
    }
    return .success(.list)
  }
  return .success(.initialize(deviceLocation: deviceLocation))
}

private let missingDeviceValueMessage =
  "--device requires a hexadecimal USB location ID, for example --device 0x14100000."

private func parseDeviceValue(_ raw: String) -> Result<UInt32, UsageError> {
  guard !raw.isEmpty else {
    return .failure(UsageError(message: missingDeviceValueMessage))
  }
  guard let location = parseLocationID(raw) else {
    return .failure(
      UsageError(
        message: "invalid USB location ID '\(raw)': expected up to 8 hexadecimal digits, "
          + "for example 0x14100000."
      )
    )
  }
  return .success(location)
}

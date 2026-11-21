import Darwin
import Foundation

/// Runtime failures of the rf4 tool that are not usage errors. All of them
/// lead to exit status 1; none of them modify the camera.
public enum CLIError: Error, LocalizedError, Equatable, Sendable {
  case noCameraConnected
  case multipleCamerasConnected(locations: [UInt32])
  case noCameraAtLocation(requested: UInt32, connected: [UInt32])
  case deviceEnumerationFailed(status: Int32)
  case deviceOpenFailed(detail: String)
  case concurrentInitialization(locationID: UInt32)
  case lockFailed(operation: String, systemError: Int32)

  public var errorDescription: String? {
    switch self {
    case .noCameraConnected:
      return "No RF4 RF-4KC7 camera is connected (expected USB vendor 0x0ac8 product 0x3420). "
        + "Connect the camera and try again."
    case .multipleCamerasConnected(let locations):
      let connected = locations.map(hexLocation).sorted().joined(separator: ", ")
      return "\(locations.count) RF4 cameras are connected (\(connected)). "
        + "Run 'rf4 --list' and choose one with --device <location>."
    case .noCameraAtLocation(let requested, let connected):
      let available =
        connected.isEmpty
        ? "no RF4 cameras are connected"
        : "connected RF4 cameras: \(connected.map(hexLocation).sorted().joined(separator: ", "))"
      return "No RF4 camera found at USB location \(hexLocation(requested)); \(available)."
    case .deviceEnumerationFailed(let status):
      return "Could not enumerate USB devices "
        + "(IOServiceGetMatchingServices returned \(String(format: "0x%x", status)))."
    case .deviceOpenFailed(let detail):
      return "Could not open the RF4 camera: \(detail). "
        + "If a capture application has the camera open, close it and try again."
    case .concurrentInitialization(let locationID):
      return "Another rf4 process is already initializing the RF4 camera at "
        + "\(hexLocation(locationID)); wait for it to finish and try again."
    case .lockFailed(let operation, let systemError):
      return "Could not acquire the initialization lock during '\(operation)': "
        + "\(String(cString: strerror(systemError)))."
    }
  }
}

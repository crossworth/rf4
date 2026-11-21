import Darwin
import Foundation
import RF4Core

let helpText = """
  RF4 RF-4KC7 camera initializer

  Usage:
    rf4                  Initialize the single connected RF4 camera
    rf4 --device <id>    Initialize the RF4 camera at USB location <id>
    rf4 --list           List connected RF4 cameras (read-only)
    rf4 --help           Show this help

  Options:
    --device <id>        Select a camera by hexadecimal USB location ID, for
                         example --device 0x14100000. Use 'rf4 --list' to see
                         the connected cameras.
    --list               Print the USB location and device revision of every
                         connected RF4 camera; does not open or change cameras.
    --help               Print this help.

  Close every capture application (QuickTime Player, OBS, ffmpeg, browsers,
  and similar) before running rf4. Initialization is refused while the camera
  is streaming, and the camera must not be reconfigured by another process.

  After initialization, open your capture application and select 3840x2160 at 30 fps.

  Exit status: 0 success, 1 runtime error, 2 usage error.
  """

@main
public enum RF4Command {
  public static func main() {
    exit(run(arguments: Array(CommandLine.arguments.dropFirst())))
  }

  /// Runs one invocation and returns the process exit status:
  /// 0 for help/list/success, 1 for runtime errors, 2 for usage errors.
  public static func run(arguments: [String]) -> Int32 {
    let action: CLIAction
    switch parseArguments(arguments) {
    case .success(let parsed):
      action = parsed
    case .failure(let usage):
      fputs("rf4: \(usage.message)\nTry 'rf4 --help' for usage.\n", stderr)
      return 2
    }

    do {
      switch action {
      case .help:
        print(helpText)
        return 0
      case .list:
        printCameraList(try discoverRF4Cameras().map(\.record))
        return 0
      case .initialize(let requestedLocation):
        let outcome = try initializeCamera(requestedLocation: requestedLocation)
        print(
          "Initialized RF4 camera at \(hexLocation(outcome.record.locationID)) "
            + "(revision \(hexRevision(outcome.record.deviceRevision))); configured 3840x2160/30, "
            + "USB payload \(outcome.payloadSize) bytes. Open your capture application."
        )
        return 0
      }
    } catch {
      report(error)
      return 1
    }
  }
}

private func report(_ error: Error) {
  let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
  fputs("rf4: \(message)\n", stderr)
}

private func printCameraList(_ cameras: [CameraRecord]) {
  guard !cameras.isEmpty else {
    print("No RF4 RF-4KC7 cameras are connected.")
    return
  }
  for camera in cameras.sorted(by: { $0.locationID < $1.locationID }) {
    print("\(hexLocation(camera.locationID))  revision \(hexRevision(camera.deviceRevision))")
  }
}

func initializeCamera(
  requestedLocation: UInt32?
) throws -> (record: CameraRecord, payloadSize: UInt32) {
  let cameras = try discoverRF4Cameras()
  let record = try selectCamera(cameras.map(\.record), requestedLocation: requestedLocation)
  guard let camera = cameras.first(where: { $0.record == record }) else {
    throw CLIError.noCameraAtLocation(
      requested: record.locationID, connected: cameras.map { $0.record.locationID }
    )
  }

  do {
    // The advisory lock covers opening the device and the whole negotiation.
    // It is released when this function returns; the lock file is never unlinked.
    let lock = try RF4Lock.acquire(
      RF4Lock.path(locationID: record.locationID, in: try RF4Lock.defaultDirectory())
    )
    return try withExtendedLifetime(lock) {
      let transport = try USBHostControlTransport(ioService: camera.ioService.service)
      let result = try RF4Initializer.initialize(using: transport)
      return (record: record, payloadSize: result.payloadSize)
    }
  } catch let error as ProcessLockError {
    switch error {
    case .contention:
      throw CLIError.concurrentInitialization(locationID: record.locationID)
    case .failed(let operation, let systemError):
      throw CLIError.lockFailed(operation: operation, systemError: systemError)
    }
  }
}

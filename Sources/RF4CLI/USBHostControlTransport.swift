import Foundation
import IOKit
import IOUSBHost
import RF4Core

public enum USBTransferError: Error, Equatable, LocalizedError, Sendable {
  case lengthNotTransferable(Int)

  public var errorDescription: String? {
    switch self {
    case .lengthNotTransferable(let length):
      return "Control transfer length \(length) does not fit the 16-bit USB control limit."
    }
  }
}

/// Converts a buffer length to the `wLength` field of a control request,
/// refusing lengths that USB control transfers cannot express.
public func wLength(forLength length: Int) throws -> UInt16 {
  guard length >= 0, length <= Int(UInt16.max) else {
    throw USBTransferError.lengthNotTransferable(length)
  }
  return UInt16(length)
}

public func makeDeviceRequest(
  _ request: ControlRequest, dataLength: Int
) throws -> IOUSBDeviceRequest {
  var setup = IOUSBDeviceRequest()
  setup.bmRequestType = request.requestType
  setup.bRequest = request.request
  setup.wValue = request.value
  setup.wIndex = request.index
  setup.wLength = try wLength(forLength: dataLength)
  return setup
}

/// Sends UVC control requests over the native IOUSBHost interface using the
/// proved synchronous path. The device is never claimed, seized, reset, or
/// otherwise reconfigured; no privileges are required.
final class USBHostControlTransport: USBControlTransport {
  private let device: IOUSBHostDevice

  init(ioService: io_service_t) throws {
    do {
      device = try IOUSBHostDevice(
        __ioService: ioService, options: [], queue: nil, interestHandler: nil
      )
    } catch {
      throw CLIError.deviceOpenFailed(detail: String(describing: error))
    }
  }

  /// Returns the number of bytes actually transferred, as reported by the host
  /// controller; judging shortness is the initializer's job.
  func transfer(_ request: ControlRequest, data: NSMutableData) throws -> Int {
    let setup = try makeDeviceRequest(request, dataLength: data.length)
    var transferred = 0
    try device.__send(setup, data: data, bytesTransferred: &transferred, completionTimeout: 2.0)
    return transferred
  }
}

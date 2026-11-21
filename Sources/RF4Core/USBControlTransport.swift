import Foundation

public struct ControlRequest: Equatable, Sendable {
  public let requestType: UInt8
  public let request: UInt8
  public let value: UInt16
  public let index: UInt16

  public init(requestType: UInt8, request: UInt8, value: UInt16, index: UInt16) {
    self.requestType = requestType
    self.request = request
    self.value = value
    self.index = index
  }
}

public protocol USBControlTransport {
  func transfer(_ request: ControlRequest, data: NSMutableData) throws -> Int
}

public enum RF4Profile {
  public static let vendorID: UInt16 = 0x0AC8
  public static let productID: UInt16 = 0x3420
  public static let deviceRevision: UInt16 = 0x0409
  public static let streamingInterface: UInt16 = 1
  public static let controlLength = 34
  public static let formatIndex: UInt8 = 1
  public static let frameIndex: UInt8 = 4
  public static let frameInterval: UInt32 = 333_333
  public static let maximumPayload: UInt32 = 3072
}

public struct InitializationResult: Equatable, Sendable {
  public let payloadSize: UInt32

  public init(payloadSize: UInt32) {
    self.payloadSize = payloadSize
  }
}

public enum RF4Error: Error, LocalizedError, Equatable {
  case unsupportedDevice(String)
  case cameraInUse
  case invalidResponse(String)
  case shortTransfer(expected: Int, actual: Int)

  public var errorDescription: String? {
    switch self {
    case .unsupportedDevice(let detail):
      return "Unsupported camera: \(detail). No initialization was applied."
    case .cameraInUse:
      return "The camera is already streaming. Close camera applications and try again."
    case .invalidResponse(let detail):
      return "Invalid camera response: \(detail)."
    case .shortTransfer(let expected, let actual):
      return "Incomplete USB transfer: expected \(expected) bytes, received \(actual)."
    }
  }
}

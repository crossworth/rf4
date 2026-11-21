import Foundation
import RF4Core

/// Scripted in-memory stand-in for the RF4 RF-4KC7. It answers exactly the control
/// requests `RF4Initializer` issues and records every transfer, so tests can prove
/// which requests were sent, in which order, and with which payloads.
final class ScriptedCamera: USBControlTransport {

  struct Call: Equatable {
    let request: ControlRequest
    let payload: [UInt8]  // bytes sent by host-to-device requests; empty otherwise
  }

  /// Proved 18-byte device descriptor (VID 0x0AC8, PID 0x3420, revision 0x0409).
  static let provedDeviceDescriptor: [UInt8] = [
    0x12, 0x01, 0x00, 0x02, 0xEF, 0x02, 0x01, 0x40,
    0xC8, 0x0A, 0x20, 0x34, 0x09, 0x04, 0x01, 0x02,
    0x03, 0x01,
  ]

  /// Real 34-byte probe block captured during the proved exchange: 4K MJPEG,
  /// interval 333333, frame size 0x2F7600, payload 3072.
  static let provedProbeBlock: [UInt8] = [
    0x01, 0x00, 0x01, 0x04, 0x15, 0x16, 0x05, 0x00,  // bmHint 1, format 1, frame 4, interval 333333
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // rates, quality, delay
    0x00, 0x00, 0x00, 0x76, 0x2F, 0x00, 0x00, 0x0C,  // frame size 0x2F7600, payload 0x0C00
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0x01,  // clock frequency 0, framing, versions
    0x00, 0x01,
  ]

  var deviceDescriptor: [UInt8] = ScriptedCamera.provedDeviceDescriptor
  var configurationDescriptor: [UInt8] = ScriptedCamera.capturedConfiguration()

  /// Reply to GET_CONFIGURATION.
  var activeConfiguration: UInt8 = 1
  /// Reply to GET_INTERFACE on the streaming interface; 1 simulates an active stream.
  var streamingAlternateSetting: UInt8 = 0

  /// Successive GET_CUR probe replies, consumed in order; the last one repeats.
  var getCurReplies: [[UInt8]] = []
  var defaultGetCurReply: [UInt8] = ScriptedCamera.provedProbeBlock
  var getMinimumReply: [UInt8] = ScriptedCamera.provedProbeBlock
  var getMaximumReply: [UInt8] = ScriptedCamera.provedProbeBlock

  /// Optional per-request override of the transferred byte count (short transfers).
  var transferredCountOverride: ((ControlRequest) -> Int?)?

  private(set) var calls: [Call] = []
  private(set) var unexpectedRequest: ControlRequest?

  func transfer(_ request: ControlRequest, data: NSMutableData) throws -> Int {
    calls.append(Call(request: request, payload: outgoingPayload(request, data)))
    let count: Int
    switch (request.requestType, request.request, request.value, request.index) {
    case (0x80, 0x06, 0x0100, 0x0000):
      count = fill(data, from: deviceDescriptor)
    case (0x80, 0x06, 0x0200, 0x0000):
      count = fill(data, from: configurationDescriptor)
    case (0x80, 0x08, 0x0000, 0x0000):
      count = fill(data, from: [activeConfiguration])
    case (0x81, 0x0A, 0x0000, RF4Profile.streamingInterface):
      count = fill(data, from: [streamingAlternateSetting])
    case (0xA1, 0x81, 0x0100, RF4Profile.streamingInterface):
      let reply =
        getCurReplies.count > 1
        ? getCurReplies.removeFirst() : (getCurReplies.first ?? defaultGetCurReply)
      count = fill(data, from: reply)
    case (0xA1, 0x82, 0x0100, RF4Profile.streamingInterface):
      count = fill(data, from: getMinimumReply)
    case (0xA1, 0x83, 0x0100, RF4Profile.streamingInterface):
      count = fill(data, from: getMaximumReply)
    case (0x21, 0x01, 0x0100, RF4Profile.streamingInterface),
      (0x21, 0x01, 0x0200, RF4Profile.streamingInterface):
      count = data.length
    default:
      unexpectedRequest = request
      count = 0
    }
    if let overridden = transferredCountOverride?(request) {
      return overridden
    }
    return count
  }

  /// Every host-to-device request, in order.
  var setCalls: [Call] {
    calls.filter { $0.request.requestType == 0x21 }
  }

  /// Payloads of the probe SET_CUR requests.
  var probeSetPayloads: [[UInt8]] {
    setCalls.filter { $0.request.value == 0x0100 }.map(\.payload)
  }

  /// Payloads of the commit SET_CUR requests.
  var commitPayloads: [[UInt8]] {
    setCalls.filter { $0.request.value == 0x0200 }.map(\.payload)
  }

  private func fill(_ data: NSMutableData, from reply: [UInt8]) -> Int {
    let count = min(data.length, reply.count)
    if count > 0 {
      data.replaceBytes(in: NSRange(location: 0, length: count), withBytes: reply, length: count)
    }
    return count
  }

  private func outgoingPayload(_ request: ControlRequest, _ data: NSMutableData) -> [UInt8] {
    guard request.requestType & 0x80 == 0, data.length > 0 else { return [] }
    return [UInt8](
      UnsafeBufferPointer(start: data.bytes.assumingMemoryBound(to: UInt8.self), count: data.length)
    )
  }

  static func capturedConfiguration() -> [UInt8] {
    guard
      let url = Bundle.module.url(
        forResource: "configuration", withExtension: "bin", subdirectory: "Fixtures"),
      let bytes = try? Data(contentsOf: url)
    else {
      preconditionFailure("captured configuration fixture is missing from the test bundle")
    }
    return [UInt8](bytes)
  }
}

extension Array where Element == UInt8 {
  /// Copy with one byte replaced, keeping per-test fixture mutations declarative.
  func withByte(_ index: Int, _ value: UInt8) -> [UInt8] {
    var copy = self
    copy[index] = value
    return copy
  }
}

func little32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
  UInt32(bytes[offset])
    | UInt32(bytes[offset + 1]) << 8
    | UInt32(bytes[offset + 2]) << 16
    | UInt32(bytes[offset + 3]) << 24
}

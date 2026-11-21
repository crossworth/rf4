import Foundation

/// Initializes the RF4 RF-4KC7 for 4K MJPEG capture by replaying the proved USB video
/// negotiation: the camera is inspected read-only first, the proved mode is probed, and
/// only then is exactly the block the camera negotiated committed. The camera is never
/// claimed, reset, or re-flashed, and any unexpected response aborts without retries.
public enum RF4Initializer {

  // Standard read-only requests.
  private static let getDeviceDescriptor =
    ControlRequest(requestType: 0x80, request: 0x06, value: 0x0100, index: 0x0000)
  private static let getConfigurationDescriptor =
    ControlRequest(requestType: 0x80, request: 0x06, value: 0x0200, index: 0x0000)
  private static let getActiveConfiguration =
    ControlRequest(requestType: 0x80, request: 0x08, value: 0x0000, index: 0x0000)
  private static let getStreamingAlternateSetting =
    ControlRequest(
      requestType: 0x81, request: 0x0A, value: 0x0000, index: RF4Profile.streamingInterface)

  // Class-specific probe and commit requests on the streaming interface.
  private static let getProbe =
    ControlRequest(
      requestType: 0xA1, request: 0x81, value: 0x0100, index: RF4Profile.streamingInterface)
  private static let getProbeMinimum =
    ControlRequest(
      requestType: 0xA1, request: 0x82, value: 0x0100, index: RF4Profile.streamingInterface)
  private static let getProbeMaximum =
    ControlRequest(
      requestType: 0xA1, request: 0x83, value: 0x0100, index: RF4Profile.streamingInterface)
  private static let setProbe =
    ControlRequest(
      requestType: 0x21, request: 0x01, value: 0x0100, index: RF4Profile.streamingInterface)
  private static let setCommit =
    ControlRequest(
      requestType: 0x21, request: 0x01, value: 0x0200, index: RF4Profile.streamingInterface)

  private static let deviceDescriptorLength = 18
  private static let configurationHeaderLength = 9

  /// Prepares an idle supported camera for 4K capture. An error stops the exchange;
  /// failed negotiation may leave Probe parameters changed, but is never retried.
  public static func initialize(using transport: any USBControlTransport) throws
    -> InitializationResult
  {
    let capability = try inspectCamera(using: transport)
    return try negotiateCaptureMode(using: transport, capability: capability)
  }

  /// Reads and validates the camera's descriptors and idle state. Performs no writes.
  private static func inspectCamera(using transport: any USBControlTransport) throws
    -> RF4StreamCapability
  {
    let buffer = NSMutableData()

    // The device must be the proved RF4 RF-4KC7 revision.
    buffer.length = deviceDescriptorLength
    try transfer(
      getDeviceDescriptor, expected: deviceDescriptorLength, data: buffer, using: transport)
    try validateDeviceDescriptor(buffer.bytes)

    // Read the configuration header first, then the full descriptor within bounded memory.
    buffer.length = configurationHeaderLength
    try transfer(
      getConfigurationDescriptor, expected: configurationHeaderLength, data: buffer,
      using: transport)
    let header = buffer.bytes
    guard Int(load8(header, 0)) == configurationHeaderLength, load8(header, 1) == 0x02 else {
      throw RF4Error.unsupportedDevice("malformed configuration descriptor header")
    }
    let totalLength = Int(loadLE16(header, 2))
    guard totalLength > configurationHeaderLength,
      totalLength <= RF4ConfigurationDescriptor.maximumTotalLength
    else {
      throw RF4Error.unsupportedDevice(
        "configuration descriptor length \(totalLength) is out of bounds")
    }

    buffer.length = totalLength
    try transfer(getConfigurationDescriptor, expected: totalLength, data: buffer, using: transport)
    let capability = try RF4ConfigurationDescriptor.parse(buffer.bytes, length: totalLength)

    // Configuration 1 must be active and the streaming interface must sit idle at
    // alternate setting 0; anything else means a capture application is streaming.
    buffer.length = 1
    try transfer(getActiveConfiguration, expected: 1, data: buffer, using: transport)
    guard load8(buffer.bytes, 0) == 1 else {
      throw RF4Error.unsupportedDevice("active configuration \(load8(buffer.bytes, 0)) is not 1")
    }

    buffer.length = 1
    try transfer(getStreamingAlternateSetting, expected: 1, data: buffer, using: transport)
    guard load8(buffer.bytes, 0) == 0 else { throw RF4Error.cameraInUse }

    return capability
  }

  private static func validateDeviceDescriptor(_ bytes: UnsafeRawPointer) throws {
    guard load8(bytes, 0) == 0x12, load8(bytes, 1) == 0x01 else {
      throw RF4Error.unsupportedDevice("malformed device descriptor")
    }
    let vendor = loadLE16(bytes, 8)
    let product = loadLE16(bytes, 10)
    guard vendor == RF4Profile.vendorID, product == RF4Profile.productID else {
      throw RF4Error.unsupportedDevice(
        "device 0x\(hex16(vendor))/0x\(hex16(product)) is not the RF4 RF-4KC7")
    }
    let revision = loadLE16(bytes, 12)
    guard revision == RF4Profile.deviceRevision else {
      throw RF4Error.unsupportedDevice(
        "device revision 0x\(hex16(revision)) is not the proved 0x\(hex16(RF4Profile.deviceRevision))"
      )
    }
  }

  /// Replays the proved probe and commit exchange and returns the negotiated payload size.
  private static func negotiateCaptureMode(
    using transport: any USBControlTransport,
    capability: RF4StreamCapability
  ) throws -> InitializationResult {
    let length = RF4Profile.controlLength
    let request = NSMutableData()  // the block we ask the camera to negotiate
    let response = NSMutableData()  // reused for every probe read
    request.length = length
    response.length = length

    // Start from the camera's own control block and override only the proved fields,
    // leaving every other returned byte exactly as the camera reported it.
    try transfer(getProbe, expected: length, data: response, using: transport)
    request.mutableBytes.copyMemory(from: response.bytes, byteCount: length)
    let block = request.mutableBytes.bindMemory(to: UInt8.self, capacity: length)
    block[0] = 0x01  // bmHint: the frame interval in this request is mandatory
    block[1] = 0x00
    block[2] = RF4Profile.formatIndex
    block[3] = RF4Profile.frameIndex
    storeLE32(block, 4, RF4Profile.frameInterval)
    storeLE32(block, 22, 0)  // payload: let the camera state its own limit

    // Prove the mode: submit it, read it back, and have the camera evaluate its limits.
    try transfer(setProbe, expected: length, data: request, using: transport)
    try transfer(getProbe, expected: length, data: response, using: transport)
    try transfer(getProbeMaximum, expected: length, data: response, using: transport)
    try transfer(getProbeMinimum, expected: length, data: response, using: transport)

    // The proved exchange repeats the identical zero-payload probe after the limit queries.
    try transfer(setProbe, expected: length, data: request, using: transport)
    try transfer(getProbe, expected: length, data: response, using: transport)

    // Commit exactly the block the camera negotiated, never a reconstructed one.
    let negotiated = response.bytes
    try validateNegotiatedBlock(negotiated, capability: capability)
    let payloadSize = loadLE32(negotiated, 22)
    try transfer(setCommit, expected: length, data: response, using: transport)
    return InitializationResult(payloadSize: payloadSize)
  }

  private static func validateNegotiatedBlock(
    _ bytes: UnsafeRawPointer,
    capability: RF4StreamCapability
  ) throws {
    let formatIndex = load8(bytes, 2)
    let frameIndex = load8(bytes, 3)
    let frameInterval = loadLE32(bytes, 4)
    guard formatIndex == RF4Profile.formatIndex, frameIndex == RF4Profile.frameIndex,
      frameInterval == RF4Profile.frameInterval
    else {
      throw RF4Error.invalidResponse(
        "camera retained format \(formatIndex) frame \(frameIndex) interval \(frameInterval) "
          + "instead of the proved mode")
    }
    let payloadSize = loadLE32(bytes, 22)
    guard payloadSize == capability.maxPayloadTransferSize else {
      throw RF4Error.invalidResponse(
        "negotiated payload \(payloadSize) is not the proved \(capability.maxPayloadTransferSize) bytes"
      )
    }
    let frameSize = loadLE32(bytes, 18)
    guard frameSize > 0, frameSize <= capability.maxVideoFrameBufferSize else {
      throw RF4Error.invalidResponse(
        "negotiated frame size \(frameSize) is not sensible for 3840x2160")
    }
  }

  @discardableResult
  private static func transfer(
    _ request: ControlRequest,
    expected: Int,
    data: NSMutableData,
    using transport: any USBControlTransport
  ) throws -> Int {
    let transferred = try transport.transfer(request, data: data)
    if transferred < expected {
      throw RF4Error.shortTransfer(expected: expected, actual: transferred)
    }
    if transferred > expected {
      throw RF4Error.invalidResponse(
        "device reported \(transferred) of \(expected) requested bytes")
    }
    return transferred
  }
}

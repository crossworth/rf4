import RF4Core
import Testing

@Suite("Profile validation refuses unsupported cameras before any write")
struct RF4ProfileValidationTests {

  @Test func refusesForeignVendorAndProduct() {
    let camera = ScriptedCamera()
    camera.deviceDescriptor = ScriptedCamera.provedDeviceDescriptor.withByte(8, 0x34)
    expectRefusalBeforeWrites(camera)
  }

  @Test func refusesUnknownDeviceRevision() {
    let camera = ScriptedCamera()
    camera.deviceDescriptor = ScriptedCamera.provedDeviceDescriptor.withByte(13, 0x05)
    expectRefusalBeforeWrites(camera)
  }

  @Test func refusesTruncatedDeviceDescriptor() {
    let camera = ScriptedCamera()
    camera.deviceDescriptor = Array(ScriptedCamera.provedDeviceDescriptor.prefix(12))
    let error = initializationError(camera)
    #expect((error as? RF4Error) == .shortTransfer(expected: 18, actual: 12))
    #expect(camera.setCalls.isEmpty)
  }

  @Test func refusesOversizedConfigurationDescriptor() {
    let camera = ScriptedCamera()
    camera.configurationDescriptor = camera.configurationDescriptor.withByte(3, 0x11)  // 4389 bytes
    expectRefusalBeforeWrites(camera)
  }

  @Test func refusesTruncatedConfigurationDescriptor() {
    let camera = ScriptedCamera()
    camera.configurationDescriptor = Array(camera.configurationDescriptor.prefix(200))
    let error = initializationError(camera)
    #expect((error as? RF4Error) == .shortTransfer(expected: 293, actual: 200))
    #expect(camera.setCalls.isEmpty)
  }

  @Test func refusesCorruptedDescriptorWalk() {
    let camera = ScriptedCamera()
    // Interface descriptor bLength.
    camera.configurationDescriptor = camera.configurationDescriptor.withByte(17, 0x05)
    expectRefusalBeforeWrites(camera)
  }

  @Test func refusesUnsupportedUVCVersion() {
    let camera = ScriptedCamera()
    // bcdUVC 1.50.
    camera.configurationDescriptor = camera.configurationDescriptor.withByte(29, 0x50)
    expectRefusalBeforeWrites(camera)
  }

  @Test func refusesNonVideoControlInterface() {
    let camera = ScriptedCamera()
    // VideoControl interface subclass.
    camera.configurationDescriptor = camera.configurationDescriptor.withByte(23, 0x02)
    expectRefusalBeforeWrites(camera)
  }

  @Test func refusesNonVideoStreamingInterface() {
    let camera = ScriptedCamera()
    // VideoStreaming interface subclass.
    camera.configurationDescriptor = camera.configurationDescriptor.withByte(123, 0x00)
    expectRefusalBeforeWrites(camera)
  }

  @Test func refusesUncompressedFormat() {
    let camera = ScriptedCamera()
    // Replace the MJPEG format subtype with uncompressed.
    camera.configurationDescriptor = camera.configurationDescriptor.withByte(142, 0x04)
    expectRefusalBeforeWrites(camera)
  }

  @Test func refusesTruncatedUncompressedDescriptorAtEndOfBuffer() {
    let camera = ScriptedCamera()
    camera.configurationDescriptor += [3, 0x24, 0x04]
    let length = camera.configurationDescriptor.count
    camera.configurationDescriptor[2] = UInt8(truncatingIfNeeded: length)
    camera.configurationDescriptor[3] = UInt8(truncatingIfNeeded: length >> 8)
    expectRefusalBeforeWrites(camera)
  }

  @Test func refusesAnUnmatchedConfigurationValue() {
    let camera = ScriptedCamera()
    camera.configurationDescriptor[5] = 2
    expectRefusalBeforeWrites(camera)
  }

  @Test func refusesWrongFrameGeometry() {
    let camera = ScriptedCamera()
    // Frame 4 height, high byte.
    camera.configurationDescriptor = camera.configurationDescriptor.withByte(249, 0x40)
    expectRefusalBeforeWrites(camera)
  }

  @Test func refusesUnsupportedFrameInterval() {
    let camera = ScriptedCamera()
    camera.configurationDescriptor = camera.configurationDescriptor.withByte(267, 0xFF)  // 333567
    expectRefusalBeforeWrites(camera)
  }

  @Test func refusesWrongStreamingEndpointAddress() {
    let camera = ScriptedCamera()
    camera.configurationDescriptor = camera.configurationDescriptor.withByte(288, 0x82)
    expectRefusalBeforeWrites(camera)
  }

  @Test func refusesReducedStreamingPayload() {
    let camera = ScriptedCamera()
    // Reduce the endpoint's maximum payload to 2048 bytes.
    camera.configurationDescriptor = camera.configurationDescriptor.withByte(291, 0x0C)
    expectRefusalBeforeWrites(camera)
  }

  @Test func refusesReservedTransactionEncoding() {
    let camera = ScriptedCamera()
    // wMaxPacketSize 0x1B00 encodes 768x4 = 3072 through the reserved transactions bits.
    camera.configurationDescriptor = camera.configurationDescriptor
      .withByte(290, 0x00)
      .withByte(291, 0x1B)
    expectRefusalBeforeWrites(camera)
  }

  @Test func refusesInactiveConfiguration() {
    let camera = ScriptedCamera()
    camera.activeConfiguration = 0
    expectRefusalBeforeWrites(camera)
  }

  @Test func refusesBusyStreamingInterface() {
    let camera = ScriptedCamera()
    camera.streamingAlternateSetting = 1
    let error = initializationError(camera)
    #expect((error as? RF4Error) == .cameraInUse)
    #expect(camera.setCalls.isEmpty)
  }
}

private func initializationError(_ camera: ScriptedCamera) -> Error? {
  do {
    _ = try RF4Initializer.initialize(using: camera)
    return nil
  } catch {
    return error
  }
}

private func expectRefusalBeforeWrites(
  _ camera: ScriptedCamera,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  do {
    _ = try RF4Initializer.initialize(using: camera)
    Issue.record(
      "expected the camera to be refused, but initialization succeeded",
      sourceLocation: sourceLocation)
  } catch let error as RF4Error {
    guard case .unsupportedDevice = error else {
      Issue.record("expected unsupportedDevice, got \(error)", sourceLocation: sourceLocation)
      return
    }
    if !camera.setCalls.isEmpty {
      Issue.record("camera was written to before it was refused", sourceLocation: sourceLocation)
    }
  } catch {
    Issue.record("unexpected error type \(error)", sourceLocation: sourceLocation)
  }
}

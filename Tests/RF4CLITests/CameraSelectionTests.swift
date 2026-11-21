import RF4CLI
import Testing

private let cameraA = CameraRecord(locationID: 0x1410_0000, deviceRevision: 0x0409)
private let cameraB = CameraRecord(locationID: 0x1420_0000, deviceRevision: 0x0409)

@Test func defaultSelectionRequiresExactlyOneCamera() throws {
  #expect(throws: CLIError.noCameraConnected) {
    try selectCamera([], requestedLocation: nil)
  }
  #expect(try selectCamera([cameraA], requestedLocation: nil) == cameraA)
  #expect(
    throws: CLIError.multipleCamerasConnected(locations: [0x1410_0000, 0x1420_0000])
  ) {
    try selectCamera([cameraA, cameraB], requestedLocation: nil)
  }
}

@Test func explicitLocationSelectsTheMatchingCamera() throws {
  #expect(try selectCamera([cameraA, cameraB], requestedLocation: 0x1420_0000) == cameraB)
  #expect(
    throws: CLIError.noCameraAtLocation(
      requested: 0x9999_9999, connected: [0x1410_0000, 0x1420_0000])
  ) {
    try selectCamera([cameraA, cameraB], requestedLocation: 0x9999_9999)
  }
  #expect(throws: CLIError.noCameraAtLocation(requested: 0x1410_0000, connected: [])) {
    try selectCamera([], requestedLocation: 0x1410_0000)
  }
}

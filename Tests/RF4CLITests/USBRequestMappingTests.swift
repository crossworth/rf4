import IOKit
import RF4CLI
import RF4Core
import Testing

@Test func controlLengthsMapToWLengthWithinTheUSBBound() throws {
  #expect(try wLength(forLength: 0) == 0)
  #expect(try wLength(forLength: 1) == 1)
  #expect(try wLength(forLength: 34) == 34)
  #expect(try wLength(forLength: 65_535) == 65_535)
  #expect(throws: USBTransferError.lengthNotTransferable(65_536)) {
    try wLength(forLength: 65_536)
  }
}

@Test func controlRequestsMapOntoIOUSBDeviceRequestFields() throws {
  let request = ControlRequest(requestType: 0xA1, request: 0x81, value: 0x0100, index: 1)
  let setup = try makeDeviceRequest(request, dataLength: 34)
  #expect(setup.bmRequestType == 0xA1)
  #expect(setup.bRequest == 0x81)
  #expect(setup.wValue == 0x0100)
  #expect(setup.wIndex == 1)
  #expect(setup.wLength == 34)
}

@Test func commitRequestMappingPreservesValueAndIndex() throws {
  let request = ControlRequest(requestType: 0x21, request: 0x01, value: 0x0200, index: 1)
  let setup = try makeDeviceRequest(request, dataLength: 34)
  #expect(setup.bmRequestType == 0x21)
  #expect(setup.wValue == 0x0200)
  #expect(setup.wLength == 34)
}

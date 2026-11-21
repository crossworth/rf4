import Foundation
import IOKit
import RF4Core

/// A connected camera as seen in the IORegistry. Only numeric properties are
/// read; untrusted USB strings are never queried or printed.
public struct CameraRecord: Equatable, Sendable {
  public let locationID: UInt32
  public let deviceRevision: UInt16

  public init(locationID: UInt32, deviceRevision: UInt16) {
    self.locationID = locationID
    self.deviceRevision = deviceRevision
  }
}

func hexLocation(_ value: UInt32) -> String {
  String(format: "0x%08x", value)
}

func hexRevision(_ value: UInt16) -> String {
  String(format: "0x%04x", value)
}

/// Picks the camera to initialize. Without an explicit location, exactly one
/// matching camera must be connected; rf4 never initializes all of them nor
/// picks arbitrarily among several.
public func selectCamera(
  _ cameras: [CameraRecord], requestedLocation: UInt32?
) throws -> CameraRecord {
  if let requested = requestedLocation {
    guard let match = cameras.first(where: { $0.locationID == requested }) else {
      throw CLIError.noCameraAtLocation(requested: requested, connected: cameras.map(\.locationID))
    }
    return match
  }
  switch cameras.count {
  case 1:
    return cameras[0]
  case 0:
    throw CLIError.noCameraConnected
  default:
    throw CLIError.multipleCamerasConnected(locations: cameras.map(\.locationID))
  }
}

/// An IOKit service reference released exactly once when the wrapper dies.
final class RetainedIOService {
  let service: io_service_t

  init?(_ service: io_service_t) {
    guard service != MACH_PORT_NULL else {
      return nil
    }
    self.service = service
  }

  deinit {
    IOObjectRelease(service)
  }
}

struct DiscoveredCamera {
  let record: CameraRecord
  let ioService: RetainedIOService
}

/// Enumerates IOUSBHostDevice services matching the RF4 vendor and product ID.
/// Pure registry lookups: no device is opened here.
func discoverRF4Cameras(
  vendorID: UInt16 = RF4Profile.vendorID,
  productID: UInt16 = RF4Profile.productID
) throws -> [DiscoveredCamera] {
  guard let matching = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary? else {
    throw CLIError.deviceEnumerationFailed(status: KERN_FAILURE)
  }
  matching["idVendor"] = Int(vendorID)
  matching["idProduct"] = Int(productID)

  var iterator = io_iterator_t(MACH_PORT_NULL)
  let status = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
  guard status == KERN_SUCCESS else {
    throw CLIError.deviceEnumerationFailed(status: status)
  }
  defer { IOObjectRelease(iterator) }

  var cameras: [DiscoveredCamera] = []
  while true {
    let service = IOIteratorNext(iterator)
    guard let retained = RetainedIOService(service) else {
      break
    }
    if let record = cameraRecord(forService: retained.service) {
      cameras.append(DiscoveredCamera(record: record, ioService: retained))
    }
  }
  return cameras
}

private func cameraRecord(forService service: io_service_t) -> CameraRecord? {
  var properties: Unmanaged<CFMutableDictionary>?
  let status = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
  guard status == KERN_SUCCESS, let dictionary = properties?.takeRetainedValue() as? [String: Any]
  else {
    return nil
  }
  guard let location = dictionary["locationID"] as? NSNumber,
    let revision = dictionary["bcdDevice"] as? NSNumber
  else {
    return nil
  }
  return CameraRecord(locationID: location.uint32Value, deviceRevision: revision.uint16Value)
}

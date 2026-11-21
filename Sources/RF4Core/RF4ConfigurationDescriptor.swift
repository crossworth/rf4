import Foundation

/// Capabilities of the proved RF4 RF-4KC7 streaming configuration, taken from its
/// captured configuration descriptor.
struct RF4StreamCapability: Equatable {
  /// Bandwidth of the proved high-bandwidth isochronous endpoint, per service interval.
  let maxPayloadTransferSize: UInt32
  /// Frame buffer size MJPEG frame index 4 advertises for 3840x2160.
  let maxVideoFrameBufferSize: UInt32
}

/// Bounded parser for the RF4 RF-4KC7 configuration descriptor. It accepts exactly the
/// captured hardware profile — UVC 1.10 video control on interface 0, MJPEG streaming
/// with the proved 4K frame on interface 1, and one high-bandwidth isochronous IN
/// endpoint — and rejects every deviation before the camera is modified.
enum RF4ConfigurationDescriptor {

  /// Anything larger is not a descriptor this hardware produces.
  static let maximumTotalLength = 4096

  private static let configurationType: UInt8 = 0x02
  private static let interfaceType: UInt8 = 0x04
  private static let endpointType: UInt8 = 0x05
  private static let classSpecificInterfaceType: UInt8 = 0x24

  private static let videoClass: UInt8 = 0x0E
  private static let videoControlSubclass: UInt8 = 0x01
  private static let videoStreamingSubclass: UInt8 = 0x02

  private static let controlHeaderSubtype: UInt8 = 0x01
  private static let formatUncompressedSubtype: UInt8 = 0x04
  private static let formatMJPEGSubtype: UInt8 = 0x06
  private static let frameMJPEGSubtype: UInt8 = 0x07

  private static let provedUVCVersion: UInt16 = 0x0110
  private static let provedFrameWidth: UInt16 = 3840
  private static let provedFrameHeight: UInt16 = 2160
  private static let streamEndpointAddress: UInt8 = 0x81
  private static let streamEndpointAttributes: UInt8 = 0x05  // isochronous, asynchronous, data
  /// Exact proved raw value: 1024-byte packets with two additional transactions per interval.
  private static let streamEndpointMaxPacketSize: UInt16 = 0x1400

  static func parse(_ bytes: UnsafeRawPointer, length: Int) throws -> RF4StreamCapability {
    guard length >= 9, load8(bytes, 0) == 9, load8(bytes, 1) == configurationType,
      Int(loadLE16(bytes, 2)) == length, load8(bytes, 4) == 2, load8(bytes, 5) == 1
    else {
      throw RF4Error.unsupportedDevice("configuration 1 descriptor does not match its header")
    }
    let streamingInterface = Int(RF4Profile.streamingInterface)

    var sawControlHeader = false
    var sawMJPEGFormat = false
    var sawUncompressedFormat = false
    var sawProvedFrame = false
    var maxVideoFrameBufferSize: UInt32 = 0
    var streamingEndpoints = 0
    var maxPayloadTransferSize: UInt32 = 0

    var interface = -1
    var alternateSetting = -1
    var subclass: UInt8 = 0
    var offset = 0

    while offset < length {
      let descriptorLength = Int(load8(bytes, offset))
      guard descriptorLength >= 2, offset + descriptorLength <= length else {
        throw RF4Error.unsupportedDevice("malformed descriptor at offset \(offset)")
      }

      switch load8(bytes, offset + 1) {
      case configurationType:
        guard descriptorLength == 9 else {
          throw RF4Error.unsupportedDevice("malformed configuration descriptor header")
        }

      case interfaceType:
        guard descriptorLength == 9 else {
          throw RF4Error.unsupportedDevice("malformed interface descriptor at offset \(offset)")
        }
        interface = Int(load8(bytes, offset + 2))
        alternateSetting = Int(load8(bytes, offset + 3))
        let endpointCount = Int(load8(bytes, offset + 4))
        let classCode = load8(bytes, offset + 5)
        subclass = load8(bytes, offset + 6)
        guard classCode == videoClass else {
          throw RF4Error.unsupportedDevice("interface \(interface) is not a video interface")
        }
        if interface == 0 {
          guard alternateSetting == 0, subclass == videoControlSubclass else {
            throw RF4Error.unsupportedDevice(
              "interface 0 is not the proved video control interface")
          }
        } else if interface == streamingInterface {
          guard subclass == videoStreamingSubclass, alternateSetting == 0 || alternateSetting == 1
          else {
            throw RF4Error.unsupportedDevice(
              "interface 1 is not the proved video streaming interface")
          }
          if alternateSetting == 0 {
            guard endpointCount == 0 else {
              throw RF4Error.unsupportedDevice(
                "streaming idle setting must not advertise endpoints")
            }
          } else {
            guard endpointCount == 1 else {
              throw RF4Error.unsupportedDevice(
                "streaming alternate setting 1 must advertise exactly one endpoint")
            }
            streamingEndpoints = 0
          }
        } else {
          throw RF4Error.unsupportedDevice("unexpected interface \(interface)")
        }

      case endpointType:
        guard descriptorLength == 7 else {
          throw RF4Error.unsupportedDevice("malformed endpoint descriptor at offset \(offset)")
        }
        // The VideoControl status endpoint is unrelated to streaming bandwidth.
        guard interface == streamingInterface else { break }
        guard alternateSetting == 1 else {
          throw RF4Error.unsupportedDevice("streaming idle setting must not expose endpoints")
        }
        streamingEndpoints += 1
        let address = load8(bytes, offset + 2)
        let attributes = load8(bytes, offset + 3)
        guard streamingEndpoints == 1, address == streamEndpointAddress,
          attributes == streamEndpointAttributes
        else {
          throw RF4Error.unsupportedDevice(
            "streaming endpoint 0x\(hex8(address)) does not match the proved isochronous IN endpoint"
          )
        }
        let rawMaxPacketSize = loadLE16(bytes, offset + 4)
        guard rawMaxPacketSize == streamEndpointMaxPacketSize else {
          throw RF4Error.unsupportedDevice(
            "streaming endpoint wMaxPacketSize 0x\(hex16(rawMaxPacketSize)) is not the proved "
              + "0x\(hex16(streamEndpointMaxPacketSize))"
          )
        }
        maxPayloadTransferSize =
          UInt32(rawMaxPacketSize & 0x07FF) * (UInt32((rawMaxPacketSize >> 11) & 0x03) + 1)

      case classSpecificInterfaceType:
        guard descriptorLength >= 3 else {
          throw RF4Error.unsupportedDevice(
            "malformed class-specific descriptor at offset \(offset)")
        }
        let subtype = load8(bytes, offset + 2)
        if interface == 0 {
          guard subclass == videoControlSubclass, subtype == controlHeaderSubtype else { break }
          guard descriptorLength >= 12 else {
            throw RF4Error.unsupportedDevice("malformed video control header at offset \(offset)")
          }
          let version = loadLE16(bytes, offset + 3)
          guard version == provedUVCVersion else {
            throw RF4Error.unsupportedDevice(
              "UVC version 0x\(hex16(version)) is not the proved 1.10")
          }
          sawControlHeader = true
        } else if interface == streamingInterface {
          guard subclass == videoStreamingSubclass else { break }
          switch subtype {
          case formatMJPEGSubtype:
            guard descriptorLength == 11 else {
              throw RF4Error.unsupportedDevice(
                "malformed MJPEG format descriptor at offset \(offset)")
            }
            guard load8(bytes, offset + 3) == RF4Profile.formatIndex else {
              throw RF4Error.unsupportedDevice("only MJPEG format 1 is supported")
            }
            sawMJPEGFormat = true
          case frameMJPEGSubtype:
            guard sawMJPEGFormat else {
              throw RF4Error.unsupportedDevice("MJPEG frame appears before its format")
            }
            guard descriptorLength >= 26 else {
              throw RF4Error.unsupportedDevice(
                "malformed MJPEG frame descriptor at offset \(offset)")
            }
            guard load8(bytes, offset + 3) == RF4Profile.frameIndex else { break }
            let width = loadLE16(bytes, offset + 5)
            let height = loadLE16(bytes, offset + 7)
            guard width == provedFrameWidth, height == provedFrameHeight else {
              throw RF4Error.unsupportedDevice("frame 4 is \(width)x\(height), not 3840x2160")
            }
            maxVideoFrameBufferSize = loadLE32(bytes, offset + 17)
            guard maxVideoFrameBufferSize > 0 else {
              throw RF4Error.unsupportedDevice("frame 4 does not declare a frame buffer size")
            }
            let intervalCount = Int(load8(bytes, offset + 25))
            guard intervalCount >= 1, descriptorLength == 26 + 4 * intervalCount else {
              throw RF4Error.unsupportedDevice("frame 4 does not declare discrete frame intervals")
            }
            var intervalSupported = false
            for index in 0..<intervalCount
            where
              loadLE32(bytes, offset + 26 + 4 * index) == RF4Profile.frameInterval
            {
              intervalSupported = true
              break
            }
            guard intervalSupported else {
              throw RF4Error.unsupportedDevice("frame 4 does not support the proved frame interval")
            }
            sawProvedFrame = true
          case formatUncompressedSubtype:
            guard descriptorLength >= 4 else {
              throw RF4Error.unsupportedDevice("truncated uncompressed format descriptor")
            }
            if load8(bytes, offset + 3) == RF4Profile.formatIndex {
              sawUncompressedFormat = true
            }
          default:
            break
          }
        }

      default:
        break  // interface associations and other descriptors do not affect this profile
      }

      offset += descriptorLength
    }

    guard sawControlHeader else {
      throw RF4Error.unsupportedDevice("UVC 1.10 video control header on interface 0 is missing")
    }
    guard sawMJPEGFormat else {
      throw RF4Error.unsupportedDevice(
        sawUncompressedFormat
          ? "format 1 is uncompressed, not MJPEG" : "MJPEG format 1 on interface 1 is missing")
    }
    guard sawProvedFrame else {
      throw RF4Error.unsupportedDevice("MJPEG frame 4 (3840x2160) is missing")
    }
    guard streamingEndpoints == 1 else {
      throw RF4Error.unsupportedDevice(
        "streaming alternate setting 1 must expose exactly one isochronous endpoint")
    }
    guard maxPayloadTransferSize == RF4Profile.maximumPayload else {
      throw RF4Error.unsupportedDevice(
        "streaming payload \(maxPayloadTransferSize) is not the proved \(RF4Profile.maximumPayload) bytes"
      )
    }

    return RF4StreamCapability(
      maxPayloadTransferSize: maxPayloadTransferSize,
      maxVideoFrameBufferSize: maxVideoFrameBufferSize
    )
  }
}

@inline(__always)
func load8(_ bytes: UnsafeRawPointer, _ offset: Int) -> UInt8 {
  bytes.loadUnaligned(fromByteOffset: offset, as: UInt8.self)
}

@inline(__always)
func loadLE16(_ bytes: UnsafeRawPointer, _ offset: Int) -> UInt16 {
  bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self).littleEndian
}

@inline(__always)
func loadLE32(_ bytes: UnsafeRawPointer, _ offset: Int) -> UInt32 {
  bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian
}

@inline(__always)
func storeLE32(_ bytes: UnsafeMutablePointer<UInt8>, _ offset: Int, _ value: UInt32) {
  bytes[offset] = UInt8(truncatingIfNeeded: value)
  bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
  bytes[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
  bytes[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
}

func hex8(_ value: UInt8) -> String {
  String(format: "%02X", value)
}

func hex16(_ value: UInt16) -> String {
  String(format: "%04X", value)
}

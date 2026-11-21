import Darwin
import Foundation

public enum ProcessLockError: Error, LocalizedError, Equatable, Sendable {
  /// The lock is already held by another open file description.
  case contention
  case failed(operation: String, systemError: Int32)

  public var errorDescription: String? {
    switch self {
    case .contention:
      return "The lock is already held by another process."
    case .failed(let operation, let systemError):
      return "Lock operation '\(operation)' failed: \(String(cString: strerror(systemError)))."
    }
  }
}

/// An advisory lock held for the lifetime of the object. Closing the
/// descriptor in `deinit` releases the flock; the lock file is deliberately
/// never unlinked so its inode stays stable across invocations.
public final class ProcessLock {
  private let descriptor: Int32
  public let path: String

  init(descriptor: Int32, path: String) {
    self.descriptor = descriptor
    self.path = path
  }

  deinit {
    // Releasing the descriptor releases the advisory lock. The lock file is
    // intentionally never unlinked: keeping the inode stable avoids the
    // replace-and-lock race, and a tiny per-user file per camera is harmless.
    close(descriptor)
  }
}

public enum RF4Lock {
  /// One lock file per camera location ID, in a per-user temporary directory.
  public static func path(locationID: UInt32, in directory: String) -> String {
    let base = directory.hasSuffix("/") ? directory : directory + "/"
    return base + "rf4-" + String(format: "%08x", locationID) + ".lock"
  }

  /// The per-user temporary directory (confstr _CS_DARWIN_USER_TEMP_DIR).
  public static func defaultDirectory() throws -> String {
    let size = confstr(_CS_DARWIN_USER_TEMP_DIR, nil, 0)
    guard size > 0 else {
      throw ProcessLockError.failed(
        operation: "confstr(_CS_DARWIN_USER_TEMP_DIR)", systemError: errno
      )
    }
    var buffer = [CChar](repeating: 0, count: size)
    let written = confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, size)
    guard written > 0, written <= size else {
      throw ProcessLockError.failed(
        operation: "confstr(_CS_DARWIN_USER_TEMP_DIR)", systemError: errno
      )
    }
    return buffer.withUnsafeBufferPointer { bytes in
      String(
        decoding: UnsafeRawBufferPointer(start: bytes.baseAddress, count: written - 1),
        as: UTF8.self
      )
    }
  }

  /// Opens (or creates) the lock file and takes a non-blocking exclusive
  /// flock. O_NOFOLLOW refuses symlinked lock paths; O_CLOEXEC keeps the
  /// descriptor out of child processes; mode 0600 keeps it per-user.
  @discardableResult
  public static func acquire(_ path: String) throws -> ProcessLock {
    let descriptor = open(path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else {
      throw translate(errno: errno, operation: "open \(path)")
    }
    let status = flock(descriptor, LOCK_EX | LOCK_NB)
    guard status == 0 else {
      let code = errno
      close(descriptor)
      throw translate(errno: code, operation: "flock \(path)")
    }
    return ProcessLock(descriptor: descriptor, path: path)
  }

  private static func translate(errno code: Int32, operation: String) -> ProcessLockError {
    if code == EWOULDBLOCK {
      return .contention
    }
    return .failed(operation: operation, systemError: code)
  }
}

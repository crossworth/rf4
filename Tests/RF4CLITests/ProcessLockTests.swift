import Darwin
import Foundation
import RF4CLI
import Testing

/// Creates a unique temporary directory per test and removes it afterwards.
private final class TemporaryDirectory {
  let url: URL

  init() throws {
    let template = NSTemporaryDirectory() + "rf4-clitests-" + UUID().uuidString + "-XXXXXX"
    var buffer = template.cString(using: .utf8)!
    guard let path = mkdtemp(&buffer) else {
      throw ProcessLockError.failed(operation: "mkdtemp", systemError: errno)
    }
    url = URL(fileURLWithPath: String(cString: path))
  }

  deinit {
    try? FileManager.default.removeItem(at: url)
  }
}

@Test func lockIsExclusiveAndReportsContention() throws {
  let directory = try TemporaryDirectory()
  let path = directory.url.appendingPathComponent("rf4-14100000.lock").path
  let first = try RF4Lock.acquire(path)
  _ = withExtendedLifetime(first) {
    #expect(throws: ProcessLockError.contention) {
      try RF4Lock.acquire(path)
    }
  }
}

@Test func lockIsReleasedWithItsObjectAndTheFileIsKept() throws {
  let directory = try TemporaryDirectory()
  let path = directory.url.appendingPathComponent("rf4-14100000.lock").path
  do {
    _ = try RF4Lock.acquire(path)
  }
  #expect(FileManager.default.fileExists(atPath: path))
  _ = try RF4Lock.acquire(path)
}

@Test func lockFilesAreCreatedPrivateToTheUser() throws {
  let directory = try TemporaryDirectory()
  let path = directory.url.appendingPathComponent("rf4-0000002a.lock").path
  let lock = try RF4Lock.acquire(path)
  try withExtendedLifetime(lock) {
    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    #expect(attributes[.posixPermissions] as? Int == 0o600)
  }
}

@Test func lockIdentityHandlesTrailingSlashesAndDistinctCameras() throws {
  let directory = try TemporaryDirectory()
  let path = RF4Lock.path(locationID: 0x1410_0000, in: directory.url.path)
  let lock = try RF4Lock.acquire(path)
  try withExtendedLifetime(lock) {
    #expect(throws: ProcessLockError.contention) {
      try RF4Lock.acquire(
        RF4Lock.path(locationID: 0x1410_0000, in: directory.url.path + "/")
      )
    }
    _ = try RF4Lock.acquire(
      RF4Lock.path(locationID: 0x1420_0000, in: directory.url.path)
    )
  }
}

@Test func symlinkedLockPathsAreRefused() throws {
  let directory = try TemporaryDirectory()
  let target = directory.url.appendingPathComponent("target.lock").path
  #expect(FileManager.default.createFile(atPath: target, contents: nil))
  let link = directory.url.appendingPathComponent("rf4-symlink.lock").path
  try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)

  do {
    _ = try RF4Lock.acquire(link)
    Issue.record("acquiring a lock through a symlink should fail")
  } catch let error as ProcessLockError {
    guard case .failed(_, let systemError) = error else {
      Issue.record("expected .failed, got \(error)")
      return
    }
    #expect(systemError == ELOOP)
  }
}

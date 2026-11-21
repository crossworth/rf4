import RF4CLI
import Testing

private func expectUsageError(_ arguments: [String]) {
  guard case .failure = parseArguments(arguments) else {
    Issue.record("expected a usage error for \(arguments)")
    return
  }
}

@Test func noArgumentsParsesAsDefaultInitialization() {
  #expect(parseArguments([]) == .success(.initialize(deviceLocation: nil)))
}

@Test func helpAndListFlagsParse() {
  #expect(parseArguments(["--help"]) == .success(.help))
  #expect(parseArguments(["--list"]) == .success(.list))
}

@Test func deviceAcceptsHexLocationIDsInSeveralSpellings() {
  let cases: [([String], UInt32)] = [
    (["--device", "14100000"], 0x1410_0000),
    (["--device", "0x14100000"], 0x1410_0000),
    (["--device", "0X14100000"], 0x1410_0000),
    (["--device", "0x141000AB"], 0x1410_00AB),
    (["--device", "141000ab"], 0x1410_00AB),
    (["--device=14100000"], 0x1410_0000),
    (["--device=0x14100000"], 0x1410_0000),
  ]
  for (arguments, expected) in cases {
    #expect(parseArguments(arguments) == .success(.initialize(deviceLocation: expected)))
  }
}

@Test func malformedOrConflictingArgumentsAreUsageErrors() {
  let cases = [
    ["--verbose"], ["-v"], ["--device-id"], ["--"], ["extra"],
    ["--device"], ["--device="], ["--device", ""], ["--device", "xyz"],
    ["--device", "0x"], ["--device", "1410000g"], ["--device", "123456789"],
    ["--device", "-1"], ["--help", "--help"], ["--list", "--list"],
    ["--device", "1", "--device", "1"], ["--device=0x1", "--device", "1"],
    ["--help", "--list"], ["--list", "--help"], ["--help", "--device", "0x1"],
    ["--list", "--device", "0x1"], ["--device", "0x1", "--list"],
  ]
  for arguments in cases {
    expectUsageError(arguments)
  }
}

@Test func locationIDParsingBounds() {
  #expect(parseLocationID("0") == 0)
  #expect(parseLocationID("ffffffff") == 0xFFFF_FFFF)
  #expect(parseLocationID("FFFFFFFF") == 0xFFFF_FFFF)
  #expect(parseLocationID("0xffffffff") == 0xFFFF_FFFF)
  #expect(parseLocationID("123456789") == nil)
  #expect(parseLocationID("0x100000000") == nil)
  #expect(parseLocationID("") == nil)
  #expect(parseLocationID("0x") == nil)
  #expect(parseLocationID("1410000 ") == nil)
  #expect(parseLocationID("0b101") == 0xB101)
  #expect(parseLocationID("-1") == nil)
}

@Test func runMapsUsageErrorsToExitStatusTwo() {
  #expect(RF4Command.run(arguments: ["--help"]) == 0)
  #expect(RF4Command.run(arguments: ["--nope"]) == 2)
  #expect(RF4Command.run(arguments: ["--device"]) == 2)
  #expect(RF4Command.run(arguments: ["--device", "nothex"]) == 2)
  #expect(RF4Command.run(arguments: ["--list", "--device", "0x1"]) == 2)
}

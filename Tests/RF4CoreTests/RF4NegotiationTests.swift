import RF4Core
import Testing

@Suite("Probe and commit negotiation against the proved exchange")
struct RF4NegotiationTests {

  @Test func performsTheProvedExchangeInOrder() throws {
    let camera = ScriptedCamera()
    let result = try RF4Initializer.initialize(using: camera)
    #expect(result == InitializationResult(payloadSize: RF4Profile.maximumPayload))
    #expect(camera.unexpectedRequest == nil)

    let interface = RF4Profile.streamingInterface
    #expect(
      camera.calls.map(\.request) == [
        ControlRequest(requestType: 0x80, request: 0x06, value: 0x0100, index: 0x0000),
        ControlRequest(requestType: 0x80, request: 0x06, value: 0x0200, index: 0x0000),
        ControlRequest(requestType: 0x80, request: 0x06, value: 0x0200, index: 0x0000),
        ControlRequest(requestType: 0x80, request: 0x08, value: 0x0000, index: 0x0000),
        ControlRequest(requestType: 0x81, request: 0x0A, value: 0x0000, index: interface),
        ControlRequest(requestType: 0xA1, request: 0x81, value: 0x0100, index: interface),
        ControlRequest(requestType: 0x21, request: 0x01, value: 0x0100, index: interface),
        ControlRequest(requestType: 0xA1, request: 0x81, value: 0x0100, index: interface),
        ControlRequest(requestType: 0xA1, request: 0x83, value: 0x0100, index: interface),
        ControlRequest(requestType: 0xA1, request: 0x82, value: 0x0100, index: interface),
        ControlRequest(requestType: 0x21, request: 0x01, value: 0x0100, index: interface),
        ControlRequest(requestType: 0xA1, request: 0x81, value: 0x0100, index: interface),
        ControlRequest(requestType: 0x21, request: 0x01, value: 0x0200, index: interface),
      ])
  }

  @Test func repeatsTheIdenticalZeroPayloadProbeAfterTheLimitQueries() throws {
    let camera = ScriptedCamera()
    camera.getCurReplies = [
      ScriptedCamera.provedProbeBlock.withByte(3, 0x01),
      ScriptedCamera.provedProbeBlock,
      ScriptedCamera.provedProbeBlock,
    ]
    camera.getMinimumReply = ScriptedCamera.provedProbeBlock.withByte(3, 0x01)
    _ = try RF4Initializer.initialize(using: camera)
    let probes = camera.probeSetPayloads
    #expect(probes.count == 2)
    guard probes.count == 2 else { return }
    #expect(probes[0] == probes[1])
    #expect(little32(probes[0], 22) == 0)
    #expect(
      Array(probes[0][0..<8])
        == [0x01, 0x00, RF4Profile.formatIndex, RF4Profile.frameIndex, 0x15, 0x16, 0x05, 0x00])
    // Every field outside the proved overrides survives untouched from the first response.
    let captured = ScriptedCamera.provedProbeBlock
    #expect(Array(probes[0][8..<22]) == Array(captured[8..<22]))
    #expect(Array(probes[0][26..<34]) == Array(captured[26..<34]))
  }

  @Test func commitsTheExactFinalNegotiatedBlockIncludingPayload() throws {
    let camera = ScriptedCamera()
    let negotiated = ScriptedCamera.provedProbeBlock.withByte(12, 0x2A)
    camera.getCurReplies = [
      ScriptedCamera.provedProbeBlock.withByte(3, 0x01),
      ScriptedCamera.provedProbeBlock.withByte(12, 0x11),
      negotiated,
    ]
    _ = try RF4Initializer.initialize(using: camera)
    let commits = camera.commitPayloads
    #expect(commits.count == 1)
    guard commits.count == 1 else { return }
    #expect(commits[0] == negotiated)
    #expect(little32(commits[0], 22) == RF4Profile.maximumPayload)
  }

  @Test func abortsWhenTheInitialProbeReadIsShort() {
    let camera = ScriptedCamera()
    camera.transferredCountOverride = { request in
      request == ControlRequest(requestType: 0xA1, request: 0x81, value: 0x0100, index: 1)
        ? 20 : nil
    }
    #expect((initializationError(camera) as? RF4Error) == .shortTransfer(expected: 34, actual: 20))
    #expect(camera.setCalls.isEmpty)
  }

  @Test func abortsWhenTheMaximumLimitQueryIsShort() {
    let camera = ScriptedCamera()
    camera.transferredCountOverride = { request in
      request == ControlRequest(requestType: 0xA1, request: 0x83, value: 0x0100, index: 1)
        ? 12 : nil
    }
    #expect((initializationError(camera) as? RF4Error) == .shortTransfer(expected: 34, actual: 12))
    #expect(camera.probeSetPayloads.count == 1)
    #expect(camera.commitPayloads.isEmpty)
  }

  @Test func abortsWhenAProbeWriteIsShort() {
    let camera = ScriptedCamera()
    camera.transferredCountOverride = { request in
      request == ControlRequest(requestType: 0x21, request: 0x01, value: 0x0100, index: 1)
        ? 30 : nil
    }
    #expect((initializationError(camera) as? RF4Error) == .shortTransfer(expected: 34, actual: 30))
    #expect(camera.probeSetPayloads.count == 1)
    #expect(camera.commitPayloads.isEmpty)
  }

  @Test func abortsWhenTheCommitWriteIsShort() {
    let camera = ScriptedCamera()
    camera.transferredCountOverride = { request in
      request == ControlRequest(requestType: 0x21, request: 0x01, value: 0x0200, index: 1) ? 0 : nil
    }
    #expect((initializationError(camera) as? RF4Error) == .shortTransfer(expected: 34, actual: 0))
    #expect(camera.probeSetPayloads.count == 2)
    #expect(camera.commitPayloads.count == 1)
  }

  @Test func refusesWhenTheFinalBlockKeepsAnotherFormat() {
    let camera = ScriptedCamera()
    camera.getCurReplies = [
      ScriptedCamera.provedProbeBlock,
      ScriptedCamera.provedProbeBlock,
      ScriptedCamera.provedProbeBlock.withByte(2, 0x02),
    ]
    expectNoCommit(camera)
  }

  @Test func refusesWhenTheFinalBlockKeepsAnotherInterval() {
    let camera = ScriptedCamera()
    camera.getCurReplies = [
      ScriptedCamera.provedProbeBlock,
      ScriptedCamera.provedProbeBlock,
      ScriptedCamera.provedProbeBlock.withByte(6, 0x0A),  // interval 661525
    ]
    expectNoCommit(camera)
  }

  @Test func refusesWhenTheFinalBlockReportsNoPayload() {
    let camera = ScriptedCamera()
    camera.getCurReplies = [
      ScriptedCamera.provedProbeBlock,
      ScriptedCamera.provedProbeBlock,
      ScriptedCamera.provedProbeBlock.withByte(23, 0x00),
    ]
    expectNoCommit(camera)
  }

  @Test func refusesWhenTheFinalBlockReportsAClampedPayload() {
    let camera = ScriptedCamera()
    camera.getCurReplies = [
      ScriptedCamera.provedProbeBlock,
      ScriptedCamera.provedProbeBlock,
      ScriptedCamera.provedProbeBlock.withByte(23, 0x08),  // 2048 bytes
    ]
    expectNoCommit(camera)
  }

  @Test func refusesWhenTheFinalBlockReportsNoFrameSize() {
    let camera = ScriptedCamera()
    camera.getCurReplies = [
      ScriptedCamera.provedProbeBlock,
      ScriptedCamera.provedProbeBlock,
      ScriptedCamera.provedProbeBlock.withByte(19, 0x00).withByte(20, 0x00),
    ]
    expectNoCommit(camera)
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

private func expectNoCommit(
  _ camera: ScriptedCamera,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  do {
    _ = try RF4Initializer.initialize(using: camera)
    Issue.record(
      "expected the negotiation to be refused, but it committed", sourceLocation: sourceLocation)
  } catch let error as RF4Error {
    guard case .invalidResponse = error else {
      Issue.record("expected invalidResponse, got \(error)", sourceLocation: sourceLocation)
      return
    }
    if !camera.commitPayloads.isEmpty {
      Issue.record(
        "camera was committed despite an invalid final block", sourceLocation: sourceLocation)
    }
  } catch {
    Issue.record("unexpected error type \(error)", sourceLocation: sourceLocation)
  }
}

import AVFoundation
import CryptoKit
import XCTest
@testable import FluidAudio

/// Opt-in file replay only. Never downloads models or opens capture devices.
final class EmptyEmissionFinalWindowAudioTests: XCTestCase {
    func testTokenEmptyEarlyWindowsDoNotLoseTheRetainedPrefixAtEOF() async throws {
        guard let directory = ProcessInfo.processInfo.environment["FLUIDAUDIO_EMPTY_EMISSION_MODEL_DIR"] else {
            throw XCTSkip("Set FLUIDAUDIO_EMPTY_EMISSION_MODEL_DIR to an existing local Parakeet v3 int8 installation.")
        }
        guard let audio = Bundle.module.url(forResource: "Fixtures/dral-es-002-3.34-3s-16k-mono", withExtension: "wav")
        else {
            XCTFail("The public CC0 regression fixture must be bundled.")
            return
        }
        let expectedDigest = "05d1926f0e71b7439cfdd3bd23a09955d2c1f9fd6ccfc8aafd9deddc604879d3"
        let actualDigest = SHA256.hash(data: try Data(contentsOf: audio)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(actualDigest, expectedDigest)
        ModelHub.offlineMode = true
        let models = try AsrModels.loadLocal(
            from: URL(fileURLWithPath: directory), version: .v3, encoderPrecision: .int8)
        let batch = AsrManager(config: ASRConfig(parallelChunkConcurrency: 1, melChunkContext: false))
        try await batch.loadModels(models)
        var state = try TdtDecoderState()
        let reference = try await batch.transcribe(audio, decoderState: &state, language: nil).text
        await batch.cleanup()
        XCTAssertEqual(words(reference), words("Lo estoy interpretando como yo quiero y como yo pienso."))

        let config = SlidingWindowAsrConfig(
            chunkSeconds: 1, hypothesisChunkSeconds: 1, leftContextSeconds: 11, rightContextSeconds: 0.4,
            minContextForConfirmation: 10, confirmationThreshold: 0.80)
        let manager = SlidingWindowAsrManager(config: config)
        try await manager.loadModels(models)
        try await manager.startStreaming(source: .microphone)  // Channel label only; no capture is started.
        let updates = await manager.tokenUpdates
        let consumer = Task { () throws -> [SlidingWindowTokenUpdate] in
            var received: [SlidingWindowTokenUpdate] = []
            for try await update in updates { received.append(update) }
            return received
        }
        do {
            let samples = try AudioConverter().resampleAudioFile(audio)
            XCTAssertEqual(samples.count, 48000)
            for offset in stride(from: 0, to: samples.count, by: 1600) {
                try await Task.sleep(nanoseconds: 100_000_000)
                let end = min(offset + 1600, samples.count)
                guard let buffer = Self.makeChunk(samples[offset..<end]) else { throw FixtureError.bufferAllocation }
                await manager.streamAudio(buffer)
            }
            let live = try await manager.finish()
            await manager.cancel()
            let received = try await consumer.value
            XCTAssertTrue(received.last?.revision.isTerminal == true)
            XCTAssertTrue(received.prefix(2).allSatisfy { $0.tokens.isEmpty })
            XCTAssertEqual(
                words(live), words(reference), "EOF must recover the retained prefix after token-empty early windows.")
            await manager.cleanup()
        } catch {
            await manager.cancel()
            consumer.cancel()
            _ = try? await consumer.value
            await manager.cleanup()
            throw error
        }
    }

    private enum FixtureError: Error { case bufferAllocation }

    // Construct and fill outside the async caller, so no local pointer aliases
    // remain when ownership of the fresh buffer is transferred to the actor.
    private nonisolated static func makeChunk(_ samples: ArraySlice<Float>) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
            let destination = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (index, sample) in samples.enumerated() { destination[index] = sample }
        return buffer
    }

    private func words(_ text: String) -> [String] {
        String(
            text.precomposedStringWithCanonicalMapping.unicodeScalars.map {
                CharacterSet.punctuationCharacters.contains($0) ? " " : String($0)
            }.joined()
        ).lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    }
}

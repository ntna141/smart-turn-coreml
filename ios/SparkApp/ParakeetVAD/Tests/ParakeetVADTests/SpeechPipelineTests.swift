@testable import ParakeetVAD
import XCTest

final class SpeechPipelineTests: XCTestCase {
    func testRejectsInvalidInputFormat() async throws {
        let asr = AsrManager()
        let vad = VadManager(skipModelLoading: true)

        XCTAssertThrowsError(
            try SpeechPipeline(
                asr: asr,
                vad: vad,
                inputFormat: PCMFormat(sampleRate: 48_000, channelCount: 1, sampleType: .float32)
            )
        ) { error in
            guard case AudioInputError.invalidFormat = error else {
                return XCTFail("Expected invalid format error")
            }
        }
    }

    func testRejectsMisalignedBytes() async throws {
        let asr = AsrManager()
        let vad = VadManager(skipModelLoading: true)
        let pipeline = try SpeechPipeline(
            asr: asr,
            vad: vad,
            inputFormat: .parakeetVADLiveInput
        )

        await XCTAssertThrowsErrorAsync(
            try await pipeline.append(bytes: Data([0x00, 0x01, 0x02]))
        ) { error in
            guard case AudioInputError.misalignedByteCount = error else {
                return XCTFail("Expected misaligned byte count error")
            }
        }
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown")
    } catch {
        errorHandler(error)
    }
}

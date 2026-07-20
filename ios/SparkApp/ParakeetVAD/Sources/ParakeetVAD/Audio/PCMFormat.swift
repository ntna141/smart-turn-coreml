import Foundation

public struct PCMFormat: Sendable, Equatable {
    public enum SampleType: Sendable, Equatable {
        case float32
    }

    public let sampleRate: Int
    public let channelCount: Int
    public let sampleType: SampleType

    public init(sampleRate: Int, channelCount: Int, sampleType: SampleType) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.sampleType = sampleType
    }

    public static let parakeetVADLiveInput = PCMFormat(
        sampleRate: 16_000,
        channelCount: 1,
        sampleType: .float32
    )
}

public enum AudioInputError: Error, LocalizedError, Sendable {
    case invalidFormat(expected: PCMFormat, actual: PCMFormat)
    case misalignedByteCount

    public var errorDescription: String? {
        switch self {
        case .invalidFormat(let expected, let actual):
            return "Invalid PCM format. Expected \(expected.description), got \(actual.description)"
        case .misalignedByteCount:
            return "Byte count must be aligned to Float32 samples"
        }
    }
}

extension PCMFormat: CustomStringConvertible {
    public var description: String {
        "\(sampleRate)Hz/\(channelCount)ch/\(sampleType)"
    }
}

extension PCMFormat.SampleType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .float32:
            return "float32"
        }
    }
}

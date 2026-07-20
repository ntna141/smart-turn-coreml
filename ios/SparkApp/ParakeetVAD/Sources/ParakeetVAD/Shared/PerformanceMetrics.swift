import Foundation

public struct ASRPerformanceMetrics: Codable, Sendable {
    public let preprocessorTime: TimeInterval
    public let encoderTime: TimeInterval
    public let decoderTime: TimeInterval
    public let totalProcessingTime: TimeInterval
    public let rtfx: Float
    public let peakMemoryMB: Float
    public let gpuUtilization: Float?

    public init(
        preprocessorTime: TimeInterval,
        encoderTime: TimeInterval,
        decoderTime: TimeInterval,
        totalProcessingTime: TimeInterval,
        rtfx: Float,
        peakMemoryMB: Float,
        gpuUtilization: Float? = nil
    ) {
        self.preprocessorTime = preprocessorTime
        self.encoderTime = encoderTime
        self.decoderTime = decoderTime
        self.totalProcessingTime = totalProcessingTime
        self.rtfx = rtfx
        self.peakMemoryMB = peakMemoryMB
        self.gpuUtilization = gpuUtilization
    }
}

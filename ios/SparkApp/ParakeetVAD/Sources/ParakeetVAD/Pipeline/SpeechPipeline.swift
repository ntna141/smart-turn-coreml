import Foundation

public enum SpeechPipelineEvent: Sendable {
    case speechStarted(sampleIndex: Int)
    case speechEnded(sampleIndex: Int)
    case vadProbability(Float)
    case transcription(ASRResult)
}

public actor SpeechPipeline {
    public let inputFormat: PCMFormat

    private let asr: AsrManager
    private let vad: VadManager
    private let vadConfig: VadSegmentationConfig
    private let source: AudioSource

    private var vadStreamState = VadStreamState.initial()
    private var vadPendingSamples: [Float] = []
    private var preSpeechSamples: [Float] = []
    private var turnSamples: [Float] = []

    public init(
        asr: AsrManager,
        vad: VadManager,
        inputFormat: PCMFormat,
        vadConfig: VadSegmentationConfig = .default,
        source: AudioSource = .microphone
    ) throws {
        guard inputFormat == .parakeetVADLiveInput else {
            throw AudioInputError.invalidFormat(expected: .parakeetVADLiveInput, actual: inputFormat)
        }

        self.asr = asr
        self.vad = vad
        self.inputFormat = inputFormat
        self.vadConfig = vadConfig
        self.source = source
    }

    public func append(bytes: Data) async throws -> [SpeechPipelineEvent] {
        guard bytes.count.isMultiple(of: MemoryLayout<Float>.stride) else {
            throw AudioInputError.misalignedByteCount
        }

        bufferIncoming(bytes: bytes)
        return try await processPendingVadChunks()
    }

    public func finishCurrentTurn() async throws -> ASRResult? {
        let finalTurnSamples = turnSamples
        resetState()

        guard !finalTurnSamples.isEmpty else {
            return nil
        }

        return try await asr.transcribe(finalTurnSamples, source: source)
    }

    public func reset() {
        resetState()
    }

    private func processPendingVadChunks() async throws -> [SpeechPipelineEvent] {
        var events: [SpeechPipelineEvent] = []

        while vadPendingSamples.count >= VadManager.chunkSize {
            let chunk = Array(vadPendingSamples.prefix(VadManager.chunkSize))
            vadPendingSamples.removeFirst(VadManager.chunkSize)

            let result = try await vad.processStreamingChunk(
                chunk,
                state: vadStreamState,
                config: vadConfig
            )

            vadStreamState = result.state
            events.append(.vadProbability(result.probability))

            guard let event = result.event else {
                continue
            }

            if event.isStart {
                if turnSamples.isEmpty {
                    turnSamples = preSpeechSamples
                    preSpeechSamples.removeAll(keepingCapacity: false)
                }
                events.append(.speechStarted(sampleIndex: event.sampleIndex))
                continue
            }

            events.append(.speechEnded(sampleIndex: event.sampleIndex))

            guard !turnSamples.isEmpty else {
                continue
            }

            let capturedTurn = turnSamples
            turnSamples.removeAll(keepingCapacity: false)
            preSpeechSamples.removeAll(keepingCapacity: false)

            do {
                let transcription = try await asr.transcribe(capturedTurn, source: source)
                events.append(.transcription(transcription))
            } catch ASRError.invalidAudioData {
                turnSamples = capturedTurn
            }
        }

        return events
    }

    private func bufferIncoming(bytes: Data) {
        guard !bytes.isEmpty else { return }

        bytes.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Float.self)
            guard !samples.isEmpty else { return }

            if turnSamples.isEmpty {
                preSpeechSamples.append(contentsOf: samples)
                trimPreSpeechSamples()
            } else {
                turnSamples.append(contentsOf: samples)
            }

            vadPendingSamples.append(contentsOf: samples)
        }
    }

    private func trimPreSpeechSamples() {
        let sampleLimit = max(
            VadManager.sampleRate,
            Int(vadConfig.speechPadding * Double(VadManager.sampleRate)) + VadManager.chunkSize
        )
        guard preSpeechSamples.count > sampleLimit else { return }
        preSpeechSamples.removeFirst(preSpeechSamples.count - sampleLimit)
    }

    private func resetState() {
        vadStreamState = .initial()
        vadPendingSamples.removeAll(keepingCapacity: false)
        preSpeechSamples.removeAll(keepingCapacity: false)
        turnSamples.removeAll(keepingCapacity: false)
    }
}

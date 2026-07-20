@preconcurrency import AVFAudio
import ParakeetVAD
import Foundation
import Observation
import OSLog

enum RecorderError: Error, Equatable, LocalizedError {
    case alreadyRecording
    case microphonePermissionDenied
    case inputUnavailable
    case outputFormatUnavailable
    case converterUnavailable
    case audioSessionSetupFailed(String)
    case audioEngineStartFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "Recording is already in progress"
        case .microphonePermissionDenied:
            return "Microphone permission was denied"
        case .inputUnavailable:
            return "Microphone input is unavailable"
        case .outputFormatUnavailable:
            return "Recording output format is unavailable"
        case .converterUnavailable:
            return "Audio converter is unavailable"
        case .audioSessionSetupFailed(let message):
            return message
        case .audioEngineStartFailed(let message):
            return message
        }
    }
}

extension AVAudioInputNode {
    nonisolated var isEnabled: Bool {
        let inputFormat = inputFormat(forBus: 0)
        if inputFormat.sampleRate.isZero || inputFormat.sampleRate.isNaN {
            return false
        }
        if inputFormat.channelCount == 0 {
            return false
        }
        return true
    }
}

fileprivate nonisolated final class RecorderEngine {
    private let audioEngine = AVAudioEngine()
    private let inputBus: AVAudioNodeBus = 0

    func startRecording(
        targetSampleRate: Double,
        targetChannelCount: AVAudioChannelCount,
        tapBufferSize: AVAudioFrameCount,
        onBytes: @escaping @Sendable (Data) -> Void
    ) throws {
        audioEngine.reset()

        let inputNode = audioEngine.inputNode
        guard inputNode.isEnabled else {
            throw RecorderError.inputUnavailable
        }

        let inputFormat = inputNode.outputFormat(forBus: inputBus)
        guard
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: targetSampleRate,
                channels: targetChannelCount,
                interleaved: false
            )
        else {
            throw RecorderError.outputFormatUnavailable
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw RecorderError.converterUnavailable
        }

        inputNode.removeTap(onBus: inputBus)
        inputNode.installTap(
            onBus: inputBus,
            bufferSize: tapBufferSize,
            format: inputFormat
        ) { [outputFormat, converter] buffer, _ in
            let frameCapacity = AVAudioFrameCount(
                (Double(buffer.frameLength) * outputFormat.sampleRate / inputFormat.sampleRate).rounded(.up)
            )
            guard
                let convertedBuffer = AVAudioPCMBuffer(
                    pcmFormat: outputFormat,
                    frameCapacity: max(frameCapacity, 1)
                )
            else {
                return
            }

            var didProvideInput = false
            var conversionError: NSError?
            let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
                if didProvideInput {
                    outStatus.pointee = .noDataNow
                    return nil
                }

                didProvideInput = true
                outStatus.pointee = .haveData
                return buffer
            }

            guard conversionError == nil else {
                return
            }

            guard status == .haveData || status == .inputRanDry else {
                return
            }

            guard let channelData = convertedBuffer.floatChannelData?.pointee else {
                return
            }

            let byteCount = Int(convertedBuffer.frameLength) * MemoryLayout<Float>.stride
            let bytes = Data(bytes: channelData, count: byteCount)
            onBytes(bytes)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: inputBus)
        audioEngine.reset()
    }
}

@MainActor
@Observable
final class TranscriptionViewModel {

    enum State: Equatable {
        case idle
        case downloading(progress: Double)
        case loadingModels
        case recording
        case transcribing
        case pickingFile
    }

    var state: State = .idle
    var transcriptionText: String = ""
    var confidence: Float = 0
    var duration: TimeInterval = 0
    var processingTime: TimeInterval = 0
    var errorMessage: String?
    var isSpeaking: Bool = false
    var vadConfidence: Float = 0
    var turnStatus: String = "Idle"

    private var asrManager: AsrManager?
    private var speechPipeline: SpeechPipeline?
    private let recorderEngine = RecorderEngine()
    private let audioSession = AVAudioSession.sharedInstance()
    private let targetSampleRate: Double = 16_000
    private let targetChannelCount: AVAudioChannelCount = 1
    private let tapBufferSize: AVAudioFrameCount = 1_024
    private let vadConfig = VadConfig(defaultThreshold: 0.50)
    private let vadSegmentationConfig = VadSegmentationConfig(
        minSpeechDuration: 0.05,
        minSilenceDuration: 0.2,
        maxSpeechDuration: 14.0,
        speechPadding: 0.03,
        silenceThresholdForSplit: 0.70,
        negativeThreshold: 0.70,
        negativeThresholdOffset: 0.10,
        minSilenceAtMaxSpeech: 0.098,
        useMaxPossibleSilenceAtMaxSpeech: true
    )
    private let logger = Logger(
        subsystem: "com.fluidinference.ParakeetTestApp",
        category: "TranscriptionViewModel"
    )

    var rtfx: Float {
        guard processingTime > 0 else { return 0 }
        return Float(duration) / Float(processingTime)
    }

    var isReady: Bool {
        asrManager != nil && speechPipeline != nil
    }

    func loadModels() async {
        errorMessage = nil

        do {
            let version: AsrModelVersion = .v3
            let cacheDirectory = AsrModels.defaultCacheDirectory(for: version)
            let hasCachedModels = AsrModels.modelsExist(at: cacheDirectory, version: version)

            let models: AsrModels
            if hasCachedModels {
                state = .loadingModels
                models = try await AsrModels.loadFromCache(version: version)
            } else {
                state = .downloading(progress: 0)
                models = try await AsrModels.downloadAndLoad(
                    version: version,
                    progressHandler: { progress in
                        Task { @MainActor in
                            self.state = .downloading(progress: progress.fractionCompleted)
                        }
                    }
                )
            }
            let config = ASRConfig(
                tdtConfig: TdtConfig(blankId: version.blankId),
                encoderHiddenSize: version.encoderHiddenSize
            )
            let manager = AsrManager(config: config)
            state = .loadingModels
            try await manager.loadModels(models)
            let vadManager = try await VadManager(config: vadConfig)
            let speechPipeline = try SpeechPipeline(
                asr: manager,
                vad: vadManager,
                inputFormat: .parakeetVADLiveInput,
                vadConfig: vadSegmentationConfig,
                source: .microphone
            )

            asrManager = manager
            self.speechPipeline = speechPipeline
            await resetTurnDetectionState()
            state = .idle
        } catch {
            errorMessage = error.localizedDescription
            state = .idle
        }
    }

    func transcribeFile(url: URL) async {
        guard let manager = asrManager else { return }
        errorMessage = nil
        state = .transcribing

        do {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }

            let result = try await manager.transcribe(url, source: .system)
            apply(result: result)
            state = .idle
        } catch {
            errorMessage = error.localizedDescription
            state = .idle
        }
    }

    func startRecording() async {
        errorMessage = nil

        guard state != .recording else {
            errorMessage = RecorderError.alreadyRecording.localizedDescription
            return
        }
        guard isReady else { return }

        let isPermissionGranted = await requestRecordPermission()
        guard isPermissionGranted else {
            errorMessage = RecorderError.microphonePermissionDenied.localizedDescription
            return
        }

        do {
            try configureAudioSession()
            await resetTurnDetectionState()
            try recorderEngine.startRecording(
                targetSampleRate: targetSampleRate,
                targetChannelCount: targetChannelCount,
                tapBufferSize: tapBufferSize,
                onBytes: { [weak self] bytes in
                    Task { @MainActor [weak self] in
                        await self?.handleRecordedBytes(bytes)
                    }
                }
            )
            state = .recording
        } catch let error as RecorderError {
            stopRecording()
            errorMessage = error.localizedDescription
        } catch {
            stopRecording()
            errorMessage = RecorderError.audioEngineStartFailed(error.localizedDescription).localizedDescription
        }
    }

    func stopRecordingAndTranscribe() async {
        stopRecording()
        guard let speechPipeline else { return }

        do {
            if let result = try await speechPipeline.finishCurrentTurn() {
                apply(result: result)
                turnStatus = "Turn Transcribed"
                logger.info("Parakeet transcription completed")
            } else {
                await resetTurnDetectionState()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleRecordedBytes(_ bytes: Data) async {
        guard state == .recording else { return }
        guard let speechPipeline else { return }

        do {
            let events = try await speechPipeline.append(bytes: bytes)
            apply(events: events)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(result: ASRResult) {
        transcriptionText = result.text
        confidence = result.confidence
        duration = result.duration
        processingTime = result.processingTime
    }

    private func stopRecording() {
        recorderEngine.stopRecording()
        state = .idle

        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Failed to stop recording: \(error.localizedDescription)"
        }
    }

    private func configureAudioSession() throws {
        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.allowBluetoothHFP, .defaultToSpeaker]
            )
            try audioSession.setPreferredSampleRate(targetSampleRate)
            try audioSession.setActive(true)
        } catch {
            throw RecorderError.audioSessionSetupFailed(error.localizedDescription)
        }
    }

    private func requestRecordPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { isGranted in
                continuation.resume(returning: isGranted)
            }
        }
    }

    private func apply(events: [SpeechPipelineEvent]) {
        for event in events {
            switch event {
            case .speechStarted(let sampleIndex):
                logger.info("VAD speech started at sample \(sampleIndex)")
                isSpeaking = true
                turnStatus = "Speaking"
            case .speechEnded(let sampleIndex):
                logger.info("VAD speech ended at sample \(sampleIndex)")
                isSpeaking = false
                turnStatus = "VAD Silence Commit"
            case .vadProbability(let probability):
                vadConfidence = probability
            case .transcription(let result):
                apply(result: result)
                turnStatus = "Turn Transcribed"
                logger.info("Parakeet transcription completed")
            }
        }
    }

    private func resetTurnDetectionState() async {
        await speechPipeline?.reset()
        isSpeaking = false
        vadConfidence = 0
        turnStatus = "Idle"
    }
}

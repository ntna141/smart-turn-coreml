@preconcurrency import CoreML
import Foundation

public enum ParakeetVADModelStore {
    public static func downloadParakeet(
        to directory: URL? = nil,
        progressHandler: DownloadUtils.ProgressHandler? = nil
    ) async throws -> URL {
        try await AsrModels.download(to: directory, progressHandler: progressHandler)
    }

    public static func makeAsrManager(
        directory: URL? = nil,
        configuration: MLModelConfiguration? = nil,
        progressHandler: DownloadUtils.ProgressHandler? = nil
    ) async throws -> AsrManager {
        let models = try await AsrModels.downloadAndLoad(
            to: directory,
            configuration: configuration,
            progressHandler: progressHandler
        )
        let manager = AsrManager(
            config: ASRConfig(
                tdtConfig: TdtConfig(blankId: AsrModelVersion.v3.blankId),
                encoderHiddenSize: AsrModelVersion.v3.encoderHiddenSize
            )
        )
        try await manager.loadModels(models)
        return manager
    }

    public static func makeVadManager(
        directory: URL? = nil,
        config: VadConfig = .default,
        progressHandler: DownloadUtils.ProgressHandler? = nil
    ) async throws -> VadManager {
        if let directory {
            return try await VadManager(
                config: config,
                modelDirectory: directory,
                progressHandler: progressHandler
            )
        }

        return try await VadManager(
            config: config,
            progressHandler: progressHandler
        )
    }
}

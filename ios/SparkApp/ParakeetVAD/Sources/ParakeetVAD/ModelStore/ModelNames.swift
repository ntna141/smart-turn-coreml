import Foundation

public enum Repo: String, CaseIterable, Sendable {
    case vad = "FluidInference/silero-vad-coreml"
    case parakeet = "FluidInference/parakeet-tdt-0.6b-v3-coreml"

    public var name: String {
        switch self {
        case .vad:
            return "silero-vad-coreml"
        case .parakeet:
            return "parakeet-tdt-0.6b-v3-coreml"
        }
    }

    public var remotePath: String {
        rawValue
    }

    public var subPath: String? {
        nil
    }

    public var folderName: String {
        name.replacingOccurrences(of: "-coreml", with: "")
    }
}

public enum ModelNames {
    public enum ASR {
        public static let preprocessor = "Preprocessor"
        public static let encoder = "Encoder"
        public static let decoder = "Decoder"
        public static let joint = "JointDecision"
        public static let vocabularyFile = "parakeet_vocab.json"
        public static let preprocessorFile = preprocessor + ".mlmodelc"
        public static let encoderFile = encoder + ".mlmodelc"
        public static let decoderFile = decoder + ".mlmodelc"
        public static let jointFile = joint + ".mlmodelc"
        public static let requiredModels: Set<String> = [
            preprocessorFile,
            encoderFile,
            decoderFile,
            jointFile,
        ]
    }

    public enum VAD {
        public static let sileroVad = "silero-vad-unified-256ms-v6.0.0"
        public static let sileroVadFile = sileroVad + ".mlmodelc"
        public static let requiredModels: Set<String> = [
            sileroVadFile
        ]
    }

    static func getRequiredModelNames(for repo: Repo, variant: String? = nil) -> Set<String> {
        switch repo {
        case .parakeet:
            return ASR.requiredModels.union([ASR.vocabularyFile])
        case .vad:
            return VAD.requiredModels
        }
    }
}

import Foundation

public enum SystemInfo {
    public static var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    public static func summary() -> String {
        let processInfo = ProcessInfo.processInfo
        return processInfo.operatingSystemVersionString
    }

    public static func logOnce(using logger: AppLogger) async {
        await SystemInfoReporter.shared.logIfNeeded(logger: logger)
    }
}

actor SystemInfoReporter {
    static let shared = SystemInfoReporter()

    private var didLog = false

    func logIfNeeded(logger: AppLogger) {
        guard !didLog else { return }
        didLog = true
        logger.info("Host environment: \(SystemInfo.summary())")
    }
}

import Foundation

/// Small facts about the running bundle, in one place.
enum AppInfo {

    /// Logging subsystem, also used as the `UserDefaults` key prefix elsewhere.
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.andreadepasquale.HaptiTrack"

    static let name = "HaptiTrack"

    /// Marketing version and build, formatted for display, e.g. `0.1.0 (1)`.
    static var versionDescription: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }
}

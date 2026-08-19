import Foundation

/// Small facts about the running bundle, in one place.
enum AppInfo {

    /// Logging subsystem, also used as the `UserDefaults` key prefix elsewhere.
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.rachel.HaptiTrack.SE"

    /// Uses the bundle display name so locally branded builds such as
    /// HaptiTrack SE carry that name through their window, menu and intro.
    static var name: String {
        let info = Bundle.main.infoDictionary
        return info?["CFBundleDisplayName"] as? String
            ?? info?["CFBundleName"] as? String
            ?? "HaptiTrack SE"
    }

    /// Marketing version and build, formatted for display, e.g. `0.1.0 (1)`.
    static var versionDescription: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }
}

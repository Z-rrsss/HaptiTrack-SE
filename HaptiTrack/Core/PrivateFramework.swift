import Foundation
import OSLog

/// A private system framework opened at runtime.
///
/// HaptiTrack needs three things macOS exposes no public API for: raw
/// multitouch positions, internal display brightness, and the Night Shift
/// colour temperature. All three live in private frameworks.
///
/// Every one of them is reached through `dlopen`/`dlsym` rather than by linking
/// against the framework, which matters for more than tidiness: a linked
/// private framework that Apple renames or removes stops the app from
/// launching at all, whereas a failed `dlsym` is just an optional that comes
/// back `nil`. Every caller here treats that as "this control is unavailable"
/// and carries on.
///
/// None of this is supported by Apple, and none of it is App Store material.
/// It is deliberate: HaptiTrack is a private, personal build, and the features
/// that need these frameworks cannot be written any other way.
struct PrivateFramework {

    private static let logger = Logger(subsystem: AppInfo.subsystem, category: "PrivateFramework")

    private let handle: UnsafeMutableRawPointer
    private let path: String

    /// Opens the framework, or returns `nil` if it is not present.
    init?(path: String) {
        guard let handle = dlopen(path, RTLD_LAZY) else {
            let reason = dlerror().map { String(cString: $0) } ?? "unknown error"
            Self.logger.error("Could not open \(path, privacy: .public): \(reason, privacy: .public)")
            return nil
        }
        self.handle = handle
        self.path = path
    }

    /// Looks up a C function and reinterprets it as `T`, which must be an
    /// `@convention(c)` function type matching the real signature.
    ///
    /// Nothing verifies that the signature is right — it cannot be — so every
    /// use of this must be accompanied by a comment recording where the
    /// signature came from and whether it has been checked against a running
    /// system.
    func function<T>(_ name: String) -> T? {
        guard let symbol = dlsym(handle, name) else {
            Self.logger.notice("Symbol \(name, privacy: .public) missing from \(self.path, privacy: .public)")
            return nil
        }
        return unsafeBitCast(symbol, to: T.self)
    }

    /// Whether a symbol exists, without binding it to a signature.
    func hasSymbol(_ name: String) -> Bool {
        dlsym(handle, name) != nil
    }
}

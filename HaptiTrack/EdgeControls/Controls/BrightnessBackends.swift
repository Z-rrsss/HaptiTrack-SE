import CoreGraphics
import Foundation
import IOKit
import OSLog

/// A hardware path that can read and write one display's brightness.
///
/// Keeping the native and DDC implementations behind the same seam lets
/// `BrightnessControl` choose a path once at gesture start and lets the unit
/// tests exercise the fallback order without touching real displays.
protocol HardwareBrightnessServicing: AnyObject {
    func readBrightness(for displayID: CGDirectDisplayID) -> Double?
    func writeBrightness(_ value: Double, for displayID: CGDirectDisplayID) -> Bool
}

/// The visual fallback used when neither hardware path can drive a display.
protocol SoftwareDimmingServicing: AnyObject {
    func isAvailable(for displayID: CGDirectDisplayID) -> Bool
    func readBrightness(for displayID: CGDirectDisplayID) -> Double
    @discardableResult
    func writeBrightness(_ value: Double, for displayID: CGDirectDisplayID) -> Bool
    func clearDimming(for displayID: CGDirectDisplayID)
}

enum BrightnessControlMethod: Equatable {
    case native
    case ddc
    case software
}

/// Apple's own brightness path for built-in displays and external displays
/// that macOS exposes as natively controllable.
final class NativeDisplayBrightnessService: HardwareBrightnessServicing {

    private typealias GetBrightness = @convention(c) (
        CGDirectDisplayID,
        UnsafeMutablePointer<Float>
    ) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CanChangeBrightness = @convention(c) (CGDirectDisplayID) -> Bool
    private typealias GetUserBrightness = @convention(c) (CGDirectDisplayID) -> Double
    private typealias SetUserBrightness = @convention(c) (CGDirectDisplayID, Double) -> Int32

    private static let displayServicesPath =
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
    private static let coreDisplayPath =
        "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay"

    private let getBrightness: GetBrightness?
    private let setBrightness: SetBrightness?
    private let canChangeBrightness: CanChangeBrightness?
    private let getUserBrightness: GetUserBrightness?
    private let setUserBrightness: SetUserBrightness?

    init() {
        let displayServices = PrivateFramework(path: Self.displayServicesPath)
        let coreDisplay = PrivateFramework(path: Self.coreDisplayPath)

        getBrightness = displayServices?.function("DisplayServicesGetBrightness")
        setBrightness = displayServices?.function("DisplayServicesSetBrightness")
        canChangeBrightness = displayServices?.function("DisplayServicesCanChangeBrightness")
        getUserBrightness = coreDisplay?.function("CoreDisplay_Display_GetUserBrightness")
        setUserBrightness = coreDisplay?.function("CoreDisplay_Display_SetUserBrightness")
    }

    func readBrightness(for displayID: CGDirectDisplayID) -> Double? {
        let canChange = canChangeBrightness?(displayID)
        guard canChange != false else { return nil }

        if let getBrightness {
            var brightness: Float = 0
            if getBrightness(displayID, &brightness) == 0, brightness.isFinite {
                return Double(brightness).clamped(to: 0...1)
            }
        }

        // CoreDisplay has no error-bearing getter. Only trust it when the
        // separate capability query explicitly said this display is writable;
        // otherwise an unsupported display's zero would look like a real level.
        if canChange == true, let getUserBrightness {
            let brightness = getUserBrightness(displayID)
            if brightness.isFinite {
                return brightness.clamped(to: 0...1)
            }
        }

        return nil
    }

    func writeBrightness(_ value: Double, for displayID: CGDirectDisplayID) -> Bool {
        guard canChangeBrightness?(displayID) != false else { return false }
        let clamped = value.clamped(to: 0...1)

        if let setBrightness, setBrightness(displayID, Float(clamped)) == 0 {
            return true
        }
        if let setUserBrightness, setUserBrightness(displayID, clamped) == 0 {
            return true
        }
        return false
    }
}

// MARK: - DDC/CI

/// The pieces used to pair a Core Graphics display with an IOAV DDC service.
/// Internal so the matcher can be tested without exposing private IOKit types.
struct DDCDisplayDescriptor: Equatable {
    var ioDisplayLocation: String = ""
    var productName: String = ""
    var serialNumber: Int64 = 0
    var vendorID: UInt32 = 0
    var productID: UInt32 = 0
    var edidUUID: String = ""
}

enum DDCDisplayMatcher {

    static func score(display: DDCDisplayDescriptor, candidate: DDCDisplayDescriptor) -> Int {
        var score = 0

        if !display.ioDisplayLocation.isEmpty,
           display.ioDisplayLocation == candidate.ioDisplayLocation {
            score += 100
        }
        if display.serialNumber != 0,
           display.serialNumber == candidate.serialNumber {
            score += 20
        }
        if !display.productName.isEmpty,
           display.productName.caseInsensitiveCompare(candidate.productName) == .orderedSame {
            score += 10
        }

        // Apple Silicon framebuffers expose an EDID-derived UUID. Its first
        // four hex digits are the vendor and the next four are the little-
        // endian product ID. These are useful when a monitor has no serial.
        let edid = candidate.edidUUID.uppercased()
        if display.vendorID != 0 {
            let vendor = String(format: "%04X", display.vendorID & 0xFFFF)
            if edid.hasPrefix(vendor) { score += 4 }
        }
        if display.productID != 0, edid.count >= 8 {
            let product = UInt16(truncatingIfNeeded: display.productID)
            let littleEndian = String(
                format: "%02X%02X",
                UInt8(truncatingIfNeeded: product),
                UInt8(truncatingIfNeeded: product >> 8)
            )
            let start = edid.index(edid.startIndex, offsetBy: 4)
            let end = edid.index(start, offsetBy: 4)
            if String(edid[start..<end]) == littleEndian { score += 4 }
        }

        return score
    }
}

enum DDCPacket {

    static let brightnessVCP: UInt8 = 0x10
    private static let chipAddress: UInt8 = 0x37
    private static let dataAddress: UInt8 = 0x51

    static func readRequest(vcp: UInt8) -> [UInt8] {
        var packet: [UInt8] = [0x82, 0x01, vcp, 0]
        packet[packet.count - 1] = checksum(initial: chipAddress << 1, bytes: packet.dropLast())
        return packet
    }

    static func writeRequest(vcp: UInt8, value: UInt16) -> [UInt8] {
        var packet: [UInt8] = [
            0x84,
            0x03,
            vcp,
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value),
            0,
        ]
        packet[packet.count - 1] = checksum(
            initial: (chipAddress << 1) ^ dataAddress,
            bytes: packet.dropLast()
        )
        return packet
    }

    static func parseFeatureReply(_ reply: [UInt8], expectedVCP: UInt8) -> (current: UInt16, maximum: UInt16)? {
        guard reply.count == 11,
              checksum(initial: 0x50, bytes: reply.dropLast()) == reply[10],
              reply[2] == 0x02,
              reply[3] == 0x00,
              reply[4] == expectedVCP
        else { return nil }

        let maximum = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
        guard maximum > 0 else { return nil }
        return (min(current, maximum), maximum)
    }

    static func checksum<S: Sequence>(initial: UInt8, bytes: S) -> UInt8 where S.Element == UInt8 {
        bytes.reduce(initial, ^)
    }
}

/// DDC/CI brightness over the IOAV service used by Apple Silicon display
/// connections. It intentionally resolves the private entry points at runtime,
/// so an OS update can disable DDC without stopping the app from launching.
///
/// Packet construction, IOAV transport, retry timing and IORegistry matching
/// were adapted from the MIT-licensed AppleSiliconDDC project by Istvan T.
/// The implementation is kept local rather than vendoring that package. See
/// THIRD_PARTY_NOTICES.md for its copyright and complete license text.
final class DDCBrightnessService: HardwareBrightnessServicing {

    private typealias CreateWithService = @convention(c) (
        UnsafeRawPointer?,
        io_service_t
    ) -> UnsafeMutableRawPointer?
    private typealias ReadI2C = @convention(c) (
        UnsafeMutableRawPointer?,
        UInt32,
        UInt32,
        UnsafeMutableRawPointer?,
        UInt32
    ) -> Int32
    private typealias WriteI2C = @convention(c) (
        UnsafeMutableRawPointer?,
        UInt32,
        UInt32,
        UnsafeMutableRawPointer?,
        UInt32
    ) -> Int32
    private typealias CreateInfoDictionary = @convention(c) (
        CGDirectDisplayID
    ) -> UnsafeMutableRawPointer?

    private final class ServiceHandle {
        let raw: UnsafeMutableRawPointer

        init(raw: UnsafeMutableRawPointer) {
            self.raw = raw
        }

        deinit {
            Unmanaged<AnyObject>.fromOpaque(raw).release()
        }
    }

    private struct Candidate {
        var descriptor: DDCDisplayDescriptor
        var handle: ServiceHandle
    }

    private static let coreDisplayPath =
        "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay"
    private static let chipAddress: UInt32 = 0x37
    private static let dataAddress: UInt32 = 0x51

    private let createWithService: CreateWithService?
    private let readI2C: ReadI2C?
    private let writeI2C: WriteI2C?
    private let createInfoDictionary: CreateInfoDictionary?

    private var handles: [CGDirectDisplayID: ServiceHandle] = [:]
    private var maxima: [CGDirectDisplayID: UInt16] = [:]
    private let lock = NSLock()
    private let logger = Logger(subsystem: AppInfo.subsystem, category: "DDCBrightness")

    init() {
        let coreDisplay = PrivateFramework(path: Self.coreDisplayPath)
        createWithService = coreDisplay?.function("IOAVServiceCreateWithService")
        readI2C = coreDisplay?.function("IOAVServiceReadI2C")
        writeI2C = coreDisplay?.function("IOAVServiceWriteI2C")
        createInfoDictionary = coreDisplay?.function("CoreDisplay_DisplayCreateInfoDictionary")
    }

    func readBrightness(for displayID: CGDirectDisplayID) -> Double? {
        guard CGDisplayIsBuiltin(displayID) == 0,
              createWithService != nil,
              readI2C != nil,
              writeI2C != nil
        else { return nil }

        lock.lock()
        defer { lock.unlock() }

        let hadCachedService = handles[displayID] != nil
        if let reading = readLocked(displayID: displayID, rediscover: false) {
            return reading
        }

        // A cached IOAV object goes stale across unplug, sleep and some display
        // reconfigurations. Drop it and perform one fresh match before giving
        // up and letting software dimming take over.
        handles[displayID] = nil
        maxima[displayID] = nil
        guard hadCachedService else {
            logger.notice("DDC/CI did not answer for display \(displayID).")
            return nil
        }
        return readLocked(displayID: displayID, rediscover: true)
    }

    func writeBrightness(_ value: Double, for displayID: CGDirectDisplayID) -> Bool {
        guard CGDisplayIsBuiltin(displayID) == 0,
              let writeI2C
        else { return false }

        lock.lock()
        defer { lock.unlock() }

        guard let handle = serviceLocked(for: displayID) else { return false }
        let maximum = maxima[displayID] ?? 100
        let rawValue = UInt16((value.clamped(to: 0...1) * Double(maximum)).rounded())
        var packet = DDCPacket.writeRequest(vcp: DDCPacket.brightnessVCP, value: rawValue)

        // Two short writes are the conservative path used by monitors and
        // docks that occasionally miss the first DDC transaction.
        var succeeded = false
        for _ in 0..<2 {
            usleep(10_000)
            let writeSucceeded = packet.withUnsafeMutableBytes { bytes in
                writeI2C(
                    handle.raw,
                    Self.chipAddress,
                    Self.dataAddress,
                    bytes.baseAddress,
                    UInt32(bytes.count)
                ) == 0
            }
            succeeded = succeeded || writeSucceeded
        }

        if !succeeded {
            handles[displayID] = nil
            maxima[displayID] = nil
        }
        return succeeded
    }

    private func readLocked(displayID: CGDirectDisplayID, rediscover: Bool) -> Double? {
        guard let readI2C, let writeI2C,
              let handle = serviceLocked(for: displayID)
        else { return nil }

        var request = DDCPacket.readRequest(vcp: DDCPacket.brightnessVCP)

        for attempt in 0..<2 {
            var wrote = false
            for _ in 0..<2 {
                usleep(10_000)
                let writeSucceeded = request.withUnsafeMutableBytes { bytes in
                    writeI2C(
                        handle.raw,
                        Self.chipAddress,
                        Self.dataAddress,
                        bytes.baseAddress,
                        UInt32(bytes.count)
                    ) == 0
                }
                wrote = wrote || writeSucceeded
            }
            guard wrote else {
                if attempt == 0 { usleep(20_000) }
                continue
            }

            usleep(50_000)
            var reply = [UInt8](repeating: 0, count: 11)
            let read = reply.withUnsafeMutableBytes { bytes in
                readI2C(
                    handle.raw,
                    Self.chipAddress,
                    Self.dataAddress,
                    bytes.baseAddress,
                    UInt32(bytes.count)
                ) == 0
            }
            if read,
               let parsed = DDCPacket.parseFeatureReply(reply, expectedVCP: DDCPacket.brightnessVCP) {
                maxima[displayID] = parsed.maximum
                return Double(parsed.current) / Double(parsed.maximum)
            }

            if attempt == 0 { usleep(20_000) }
        }

        if rediscover {
            logger.notice("DDC/CI did not answer for display \(displayID).")
        }
        return nil
    }

    private func serviceLocked(for displayID: CGDirectDisplayID) -> ServiceHandle? {
        if let cached = handles[displayID] { return cached }

        let candidates = enumerateCandidates()
        guard !candidates.isEmpty else { return nil }
        let display = descriptor(for: displayID)

        let ranked = candidates.map { candidate in
            (candidate, DDCDisplayMatcher.score(display: display, candidate: candidate.descriptor))
        }.sorted { $0.1 > $1.1 }

        let selected: Candidate?
        if let best = ranked.first, best.1 > 0 {
            selected = best.0
        } else if candidates.count == 1, onlineExternalDisplayCount() == 1 {
            // Some docks strip EDID metadata. The one-to-one case is still
            // unambiguous; multiple anonymous services are not guessed at.
            selected = candidates[0]
        } else {
            selected = nil
        }

        guard let selected else { return nil }
        handles[displayID] = selected.handle
        return selected.handle
    }

    private func enumerateCandidates() -> [Candidate] {
        guard let createWithService else { return [] }

        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != IO_OBJECT_NULL else { return [] }
        defer { IOObjectRelease(root) }

        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(
            root,
            kIOServicePlane,
            IOOptionBits(kIORegistryIterateRecursively),
            &iterator
        ) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var framebuffer = DDCDisplayDescriptor()
        var candidates: [Candidate] = []

        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != IO_OBJECT_NULL else { break }

            let name = registryName(of: entry)
            if name.contains("AppleCLCD2") || name.contains("IOMobileFramebufferShim") {
                framebuffer = framebufferDescriptor(from: entry)
                IOObjectRelease(entry)
                continue
            }

            if name == "DCPAVServiceProxy",
               stringProperty("Location", from: entry) == "External",
               let raw = createWithService(nil, entry) {
                candidates.append(Candidate(
                    descriptor: framebuffer,
                    handle: ServiceHandle(raw: raw)
                ))
            }
            IOObjectRelease(entry)
        }

        return candidates
    }

    private func framebufferDescriptor(from entry: io_service_t) -> DDCDisplayDescriptor {
        var result = DDCDisplayDescriptor()
        result.edidUUID = stringProperty("EDID UUID", from: entry) ?? ""

        let path = UnsafeMutablePointer<CChar>.allocate(capacity: 512)
        defer { path.deallocate() }
        if IORegistryEntryGetPath(entry, kIOServicePlane, path) == KERN_SUCCESS {
            result.ioDisplayLocation = String(cString: path)
        }

        if let attributes = dictionaryProperty("DisplayAttributes", from: entry),
           let product = attributes["ProductAttributes"] as? NSDictionary {
            result.productName = product["ProductName"] as? String ?? ""
            result.serialNumber = Self.int64(from: product["SerialNumber"])
        }
        return result
    }

    private func descriptor(for displayID: CGDirectDisplayID) -> DDCDisplayDescriptor {
        var result = DDCDisplayDescriptor(
            serialNumber: Int64(CGDisplaySerialNumber(displayID)),
            vendorID: CGDisplayVendorNumber(displayID),
            productID: CGDisplayModelNumber(displayID)
        )

        guard let createInfoDictionary,
              let raw = createInfoDictionary(displayID)
        else { return result }

        let dictionary = Unmanaged<AnyObject>.fromOpaque(raw).takeRetainedValue()
        guard let info = dictionary as? NSDictionary else { return result }

        result.ioDisplayLocation = info["IODisplayLocation"] as? String ?? ""
        result.serialNumber = Self.int64(from: info["DisplaySerialNumber"], fallback: result.serialNumber)
        result.vendorID = Self.uint32(from: info["DisplayVendorID"], fallback: result.vendorID)
        result.productID = Self.uint32(from: info["DisplayProductID"], fallback: result.productID)
        if let names = info["DisplayProductName"] as? [String: String] {
            result.productName = names["en_US"] ?? names.values.first ?? ""
        }
        return result
    }

    private func registryName(of entry: io_service_t) -> String {
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: 128)
        defer { buffer.deallocate() }
        guard IORegistryEntryGetName(entry, buffer) == KERN_SUCCESS else { return "" }
        return String(cString: buffer)
    }

    private func stringProperty(_ key: String, from entry: io_service_t) -> String? {
        guard let property = IORegistryEntryCreateCFProperty(
            entry,
            key as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively)
        ) else { return nil }
        return property.takeRetainedValue() as? String
    }

    private func dictionaryProperty(_ key: String, from entry: io_service_t) -> NSDictionary? {
        guard let property = IORegistryEntryCreateCFProperty(
            entry,
            key as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively)
        ) else { return nil }
        return property.takeRetainedValue() as? NSDictionary
    }

    private func onlineExternalDisplayCount() -> Int {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return 0 }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return 0 }
        return displays.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 }.count
    }

    private static func int64(from value: Any?, fallback: Int64 = 0) -> Int64 {
        if let number = value as? NSNumber { return number.int64Value }
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        return fallback
    }

    private static func uint32(from value: Any?, fallback: UInt32) -> UInt32 {
        if let number = value as? NSNumber { return number.uint32Value }
        if let value = value as? UInt32 { return value }
        if let value = value as? Int { return UInt32(clamping: value) }
        return fallback
    }
}

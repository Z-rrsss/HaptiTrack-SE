import XCTest
@testable import HaptiTrack

final class DDCBrightnessServiceTests: XCTestCase {

    func testReadRequestUsesTheDDCCIGetVCPLayoutAndChecksum() {
        XCTAssertEqual(
            DDCPacket.readRequest(vcp: DDCPacket.brightnessVCP),
            [0x82, 0x01, 0x10, 0xFD]
        )
    }

    func testWriteRequestUsesTheDDCCISetVCPLayoutAndChecksum() {
        XCTAssertEqual(
            DDCPacket.writeRequest(vcp: DDCPacket.brightnessVCP, value: 50),
            [0x84, 0x03, 0x10, 0x00, 0x32, 0x9A]
        )
    }

    func testAValidFeatureReplyReturnsCurrentAndMaximumBrightness() {
        let reply: [UInt8] = [
            0x6E, 0x88, 0x02, 0x00, 0x10, 0x00,
            0x00, 0x64, 0x00, 0x32, 0xF2,
        ]

        let parsed = DDCPacket.parseFeatureReply(reply, expectedVCP: 0x10)

        XCTAssertEqual(parsed?.current, 50)
        XCTAssertEqual(parsed?.maximum, 100)
    }

    func testAReplyWithABadChecksumIsRejected() {
        let reply: [UInt8] = [
            0x6E, 0x88, 0x02, 0x00, 0x10, 0x00,
            0x00, 0x64, 0x00, 0x32, 0x00,
        ]

        XCTAssertNil(DDCPacket.parseFeatureReply(reply, expectedVCP: 0x10))
    }

    func testAReplyForAnotherVCPFeatureIsRejected() {
        var reply: [UInt8] = [
            0x6E, 0x88, 0x02, 0x00, 0x12, 0x00,
            0x00, 0x64, 0x00, 0x32, 0,
        ]
        reply[10] = DDCPacket.checksum(initial: 0x50, bytes: reply.dropLast())

        XCTAssertNil(DDCPacket.parseFeatureReply(reply, expectedVCP: 0x10))
    }

    func testDisplayLocationIsTheStrongestServiceMatch() {
        let display = DDCDisplayDescriptor(
            ioDisplayLocation: "IOService:/display/2",
            productName: "Same Monitor",
            serialNumber: 22,
            vendorID: 0x10AC,
            productID: 0x1234
        )
        let exactLocation = DDCDisplayDescriptor(
            ioDisplayLocation: "IOService:/display/2",
            productName: "Other Monitor",
            serialNumber: 99
        )
        let metadataOnly = DDCDisplayDescriptor(
            productName: "Same Monitor",
            serialNumber: 22
        )

        XCTAssertGreaterThan(
            DDCDisplayMatcher.score(display: display, candidate: exactLocation),
            DDCDisplayMatcher.score(display: display, candidate: metadataOnly)
        )
    }

    func testEDIDVendorAndProductCanMatchAMonitorWithoutASerial() {
        let display = DDCDisplayDescriptor(vendorID: 0x10AC, productID: 0x1234)
        let candidate = DDCDisplayDescriptor(edidUUID: "10AC3412-0000-0000-0000-000000000000")

        XCTAssertEqual(DDCDisplayMatcher.score(display: display, candidate: candidate), 8)
    }
}

import XCTest
@testable import ibox_fire

final class IboxCryptoTests: XCTestCase {
    func testDeviceIdStableFormat() {
        let id = IboxClient.makeDeviceId("abc.def.ghi")
        let parts = id.split(separator: "-")
        XCTAssertEqual(parts.count, 5)
        XCTAssertTrue(id.contains("-5"))
        XCTAssertTrue(id.contains("-8"))
        // same token → same id
        XCTAssertEqual(id, IboxClient.makeDeviceId("abc.def.ghi"))
    }

    func testEncryptDecryptRoundTrip() throws {
        let plain = #"{"syntheticId":1,"syntheticNum":1,"preferentialAlbumIds":[2]}"#
        let enc = try IboxCrypto.encryptBody(plain)
        XCTAssertTrue(enc.contains("encryptKey"))
        XCTAssertTrue(enc.contains("data"))
        let dec = try IboxCrypto.decryptResponse(enc)
        XCTAssertTrue(dec.contains("syntheticId"))
    }

    func testJwtNormalize() {
        let t = JwtUtil.normalize("  Bearer  aaa.bbb.ccc \n")
        XCTAssertEqual(t, "aaa.bbb.ccc")
    }
}

import XCTest
@testable import ibox_fire

final class SharedPrefsPackTests: XCTestCase {
    func testBuildHasRequiredKeys() {
        // header.payload.sig — payload: {"userId":1,"exp":9999999999,"ssoUserId":"sso1"}
        let payload = #"{"userId":1,"exp":9999999999,"ssoUserId":"sso1","preferred_username":"13800138000"}"#
        let b64 = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let token = "eyJhbGciOiJub25lIn0.\(b64).x"
        let pack = SharedPrefsPack.build(
            accessToken: token,
            refreshToken: "rt",
            deviceId: "dev-1",
            uid: 1,
            expMs: 9999999999000
        )
        XCTAssertNotNil(pack.encodedEntries["access_token"])
        XCTAssertNotNil(pack.encodedEntries["user_info"])
        XCTAssertNotNil(pack.encodedEntries["device_id"])
        XCTAssertTrue(pack.encodedEntries["access_token"]?.hasPrefix("\"") == true)
        XCTAssertTrue(pack.toBootHeadScript().contains("serviceWorker"))
        XCTAssertTrue(pack.toBootHeadScript().contains("flutter."))
    }
}

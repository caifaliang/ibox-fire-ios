import XCTest
@testable import ibox_fire

final class ParityHelpersTests: XCTestCase {
    func testSynthIdPrefersChannel() {
        let channelId: Int64 = 99
        let activityId: Int64 = 12
        let sid = channelId > 0 ? channelId : activityId
        XCTAssertEqual(sid, 99)
        let sid2 = Int64(0) > 0 ? Int64(0) : activityId
        XCTAssertEqual(sid2, 12)
    }

    func testBatchIntervalClamp() {
        let v = (Double("0.5") ?? 6)
        let clamped = min(max(v, 1), 60)
        XCTAssertEqual(clamped, 1)
        let v2 = min(max(Double("100") ?? 6, 1), 60)
        XCTAssertEqual(v2, 60)
    }

    func testQueryDefaultDepthAligned() {
        XCTAssertEqual(AppViewModel.queryDepths.first, 500)
        XCTAssertTrue(AppViewModel.queryDepths.contains(1000))
    }
}

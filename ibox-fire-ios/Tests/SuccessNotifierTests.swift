import XCTest
@testable import ibox_fire

final class SuccessNotifierTests: XCTestCase {
    func testAnnounceLockOk() {
        XCTAssertEqual(
            SuccessNotifier.matchTitle(kind: "announce", raw: "锁定OK 测试 gid=1 ¥10 12ms"),
            "公告锁定成功"
        )
        XCTAssertEqual(
            SuccessNotifier.matchTitle(kind: "announce", raw: "批量锁定OK 测试 gid=1 tip 8ms"),
            "公告锁定成功"
        )
    }

    func testBuyOrderAndPay() {
        XCTAssertEqual(
            SuccessNotifier.matchTitle(kind: "buy", raw: "下单成功 请手动支付 abc"),
            "捡漏下单成功"
        )
        XCTAssertEqual(
            SuccessNotifier.matchTitle(kind: "buy", raw: "自动支付成功! ok 进度 1/1"),
            "捡漏支付成功"
        )
        XCTAssertEqual(
            SuccessNotifier.matchTitle(kind: "buy", raw: "支付直达 https://example.com/pay"),
            "捡漏待支付"
        )
    }

    func testSynthConfirmOk() {
        XCTAssertEqual(
            SuccessNotifier.matchTitle(kind: "synth", raw: "← [本机] confirm OK 120ms x1 累计1/1"),
            "抢合成功"
        )
    }

    func testNoiseFiltered() {
        XCTAssertNil(SuccessNotifier.matchTitle(kind: "announce", raw: "跳过/失败 foo"))
        XCTAssertNil(SuccessNotifier.matchTitle(kind: "buy", raw: "iBox 登录成功 UID=1"))
        XCTAssertNil(SuccessNotifier.matchTitle(kind: "announce", raw: "公告锁定结束 成功锁 2"))
        XCTAssertNil(SuccessNotifier.matchTitle(kind: "buy", raw: "捡漏结束 成交 1/1"))
    }

    func testRecommendLock() {
        XCTAssertEqual(
            SuccessNotifier.matchTitle(kind: "recommend_lock", raw: "  批购成功 · 订单 xyz"),
            "推荐锁定成功"
        )
    }
}

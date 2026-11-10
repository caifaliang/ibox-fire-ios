import XCTest
@testable import ibox_fire

final class FeatureCatalogTests: XCTestCase {
    func testIboxTechContainsBuy() {
        let tabs = FeatureCatalog.filterFeatures(platform: "ibox", category: "tech", query: "")
        XCTAssertTrue(tabs.contains(where: { $0.key == "buy" && $0.label == "捡漏" }))
        XCTAssertFalse(tabs.contains(where: { $0.key.hasPrefix("ts_") }))
        XCTAssertFalse(tabs.contains(where: { $0.key.hasPrefix("nb_") }))
    }

    func testIbproOnlyIbTabs() {
        let tabs = FeatureCatalog.tabsForPlatform("ibpro")
        XCTAssertEqual(tabs.map(\.key), ["ib_presale", "ib_snipe", "ib_sell", "ib_query"])
    }

    func testSearchCrossCategory() {
        let tabs = FeatureCatalog.filterFeatures(platform: "ibox", category: "tech", query: "查挂")
        XCTAssertTrue(tabs.contains(where: { $0.key == "query_consignment" }))
    }

    func testShellPlatformsHideTopstar() {
        XCTAssertEqual(FeatureCatalog.platformKey(.topstar), "ibox")
        XCTAssertEqual(FeatureCatalog.catsForPlatform("ibox").map(\.key), ["tech", "query_info", "push_cat"])
    }
}

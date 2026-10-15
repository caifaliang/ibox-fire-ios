import Foundation

struct LingJiangItem: Identifiable, Hashable {
    var id: String { key }
    let key: String
    let title: String
    let type: Int
    let url: String
    let formatUrl: String
    let urlList: [String]
    let checkboxKey: String?
}

enum LingJiangStepOutcome {
    case ok
    case skip
    case loginFail
    case busyRetry
}

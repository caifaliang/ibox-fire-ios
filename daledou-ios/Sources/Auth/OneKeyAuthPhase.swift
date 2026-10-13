import Foundation

/// 一键登录统一状态机（按外部技术建议：失败即停，禁止营销页死循环）。
enum OneKeyAuthPhase: String {
    case idle
    /// 清 Cookie、加载初始授权 URL
    case preparing
    /// 等待明确可取票的授权页（xlogin）
    case awaitingAuthPage
    /// 正在 ptqrshow 取票
    case fetchingTicket
    /// 已打开 QQ，等同意 / schemacallback
    case awaitingQQ
    /// 回壳后校验游戏会话、最多刷新一次 phonepk
    case recovering
    /// connect「亿万用户」/「不支持QQ快速登录」——终态，不再自动跳转
    case unsupportedQuickLogin
    /// 取票/超时/无法开 QQ 等——终态，提示扫码或 Cookie
    case failed
    case succeeded
}

import Foundation

/// 一键登录统一状态机（原生取票路径；失败即停，WebView 不拉起 QQ）。
enum OneKeyAuthPhase: String {
    case idle
    /// canOpenURL / 清会话
    case preflight
    /// 原生 xlogin + ptqrshow 取票
    case fetchingTicket
    /// 已 open QQ，等同意（含回壳补轮询）
    case waitingQQConfirm
    /// ptqrlogin=0 后注入 Cookie
    case syncingCookies
    /// 加载 authorize / phonepk 完成 OAuth 尾段
    case loadingGame
    /// connect 营销页等（兜底日志；主路径不应再出现）
    case unsupportedQuickLogin
    case failed
    case succeeded
}

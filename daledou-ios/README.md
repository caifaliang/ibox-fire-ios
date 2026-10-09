# daledou-ios（MVP）

大乐斗 iOS 对照客户端。

## 登录（仅两种）

| 方式 | 说明 |
|------|------|
| **扫码登陆（推荐）** | 壳内 `graph.qq.com` + 桌面 UA，写游戏 Cookie |
| **Cookie 登陆** | 粘贴含 `skey` 的 Cookie 字符串 → Keychain + WKWebView |

**一键登陆不可用**：AppID `102067279` 非本包开放平台应用，无法合规完成 QQ 一键回 App 并换游戏会话（详见讨论结论）。

## 出包

GitHub Actions：`daledou-ios-ipa.yml` → `daledou-unsigned-ipa`

Bundle：`com.daledou.app`

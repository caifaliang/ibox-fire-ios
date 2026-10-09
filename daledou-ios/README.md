# daledou-ios（MVP）

大乐斗 Android APK 的 iOS 对照客户端（功能对等分期）。  
**本期 MVP**：游戏壳 WKWebView + **壳内登录/扫码拿 Cookie**（不依赖「设为默认浏览器」）+ 可选一键唤 QQ。

对齐工程：`F:\DaLedou_App_Dev\daledou`（Android）。

## MVP 范围

| 有 | 暂无 |
|---|---|
| 手机端游戏壳 | 完整代玩 Worker |
| 壳内登录 / 扫码 | Ruffle 战报 |
| Cookie → Keychain | PC 端 |
| `daledouapp://` 回调 | VIP / OTA |
| 尝试一键唤 QQ | 后台保活 |

## 登录说明（仅两种）

| 方式 | 行为 |
|------|------|
| **一键登陆** | 真唤 `wtloginmqq` + `schemacallback=daledouapp://`；QQ 若回 App，壳内加载 jump 写 Cookie |
| **扫码登陆** | 壳内 `graph.qq.com` + 桌面 UA；确认后 `continueAuthorize` → 游戏 |

- 不做密码登录（WKWebView 风控过不去）。  
- 一键若 QQ 不回调、落到 Safari/互联页 → 请改用扫码。

## 本机无 Mac

1. 改本目录源码并 push  
2. GitHub Actions：`.github/workflows/daledou-ios-ipa.yml`  
3. 下载 artifact `daledou-unsigned-ipa`  
4. 自签安装  

本地有 Mac：

```bash
cd daledou-ios
brew install xcodegen
xcodegen generate
xcodebuild -project DaLedou.xcodeproj -scheme DaLedou -configuration Release \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## 身份

- Bundle ID：`com.daledou.app`
- 显示名：大乐斗
- 版本：`0.1.0` (1)

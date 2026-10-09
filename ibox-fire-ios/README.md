# ibox-fire-ios

纯 Swift / SwiftUI 本地客户端，1:1 对标 [`ibox-fire-android`](../ibox-fire-android)。

## 功能分期

| 期 | 内容 |
|---|---|
| 一期 | 站点/VIP/Profile、iBox JWT、查询/捡漏/卖求购/上下架、前台保活 |
| 二期 | 公告锁定、抢合 FireEngine、稳定 device-id、本地通知 |
| 三期 | 抢购（服务端极验降级）、HFPay、NewBee 抢购/捡漏、短信、Sweep 引擎 |

## 本机无 Mac

1. 改 `ibox-fire-ios/` 源码并 push  
2. GitHub Actions：`.github/workflows/ios-ipa.yml`（`workflow_dispatch` 或改 iOS 路径触发）  
3. 下载 artifact `ibox-fire-unsigned-ipa`  
4. 用你的自签工具签名安装  

本地若有 Mac：

```bash
cd ibox-fire-ios
brew install xcodegen
xcodegen generate
xcodebuild -project ibox-fire.xcodeproj -scheme ibox-fire -configuration Release \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## 后台 / 锁屏保活（自签）

自签 IPA 已启用 `UIBackgroundModes=audio`：本地长任务启动时 `BackgroundKeepAlive` 会循环播放极低音量静音 WAV，锁屏或切后台可继续跑引擎（公告锁/抢合/捡漏等）。

- 「我的」页可看保活状态文案  
- 勿开低电量模式；来电等会短暂中断，结束后自动续播  
- 系统极端内存/省电策略下仍可能杀进程（不如安卓 FGS 稳）  
- **仅适合自签/企业签**，勿按此配置上架 App Store  

## 其他限制

- Geetest 默认走网站 `presale-verify`；本地 ONNX 未接（`Geetest4Solver.localEnabled=false`）。  
- HFPay 密码加密为兼容实现，若支付失败需对照 Android `HfpayCrypto` 再对齐。

## 目录

```
Sources/App        SwiftUI
Sources/Core       AppViewModel / TaskRunner
Sources/Crypto     IboxCrypto
Sources/Net        ApiRepository / IboxClient / NewbeeClient
Sources/Engines    各引擎
Sources/Proxy      ProxyPool
Sources/Geetest    占位
Sources/Util       JwtUtil
```

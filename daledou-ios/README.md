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

## 登录说明

- **主路径**：App 内 `WKWebView` 打开腾讯登录页，落地 `phonepk` 后从 `WKHTTPCookieStore` 读 Cookie。  
- 页内若跳 `wtloginmqq`/`mqq`：**拦截并留在壳内**（改加载 https jump 或密码页），避免 QQ → 系统浏览器。  
- iOS **不能**像安卓那样注册默认浏览器；真·唤 QQ 一键登录在 iOS 上易丢到 Safari，MVP 不用。

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

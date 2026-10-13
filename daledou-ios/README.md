# daledou-ios（MVP）

大乐斗 iOS 对照客户端。

## 登录（仅两种）

| 方式 | 说明 |
|------|------|
| **扫码登陆（推荐）** | 壳内 `graph.qq.com` + 桌面 UA，写游戏 Cookie |
| **Cookie 登陆** | 粘贴含 `skey` 的 Cookie 字符串 → Keychain + WKWebView |

**一键登陆**：饭点 QQ_ONE_KEY 同款 — `phonepk` → style=35 → `wtloginmqq?p=` 开 QQ，https 回跳写 Cookie。失败请用扫码或粘贴 Cookie。

## 出包

GitHub Actions：`daledou-ios-ipa.yml` → `daledou-unsigned-ipa`

Bundle：`com.daledou.app`

## Windows 一键装到已连接 iPhone（免爱思签证）

CI 出的是 **未签名 IPA**。本机用 **iPASide**（免费 Apple ID 重签 + USB 安装；Sideloadly 无稳定 CLI，故用可脚本化的同类方案）。

### 一次性准备

1. 手机用数据线连 PC，解锁并点「信任」；安装 [Apple Devices](https://apps.microsoft.com/detail/9np83lwlpz9k)（或桌面版 iTunes）。
2. PowerShell：

```powershell
cd daledou-ios\scripts
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned   # 若被策略拦住
.\Setup-SideloadTools.ps1
```

3. 编辑生成的 `config.local.ps1`：
   - `GitHubToken`：有 `actions:read` 的 [PAT](https://github.com/settings/tokens)
   - `AppleIdEmail` / `AppleIdPassword`：建议用 **小号**（勿用主 ID）
4. 登录（首次要 2FA）：

```powershell
.\Login-AppleId.ps1
.\Login-AppleId.ps1 -Code 123456    # 填短信/设备上的验证码
```

### 日常调试

```powershell
cd daledou-ios\scripts
.\Deploy-DaLedou.ps1 -WaitCi     # push 后等 CI 成功 → 下载 → 重签 → 装机
# 或
.\Deploy-DaLedou.ps1             # 直接装最新成功 artifact
.\Deploy-DaLedou.ps1 -IpaPath D:\tmp\xxx.ipa
```

手机首次：设置 → 通用 → VPN 与设备管理 → 信任开发者。免费签名约 **7 天** 有效，可在 iPASide 开自动刷新。

### 实时动画日志（免复制）

```powershell
cd daledou-ios\scripts
.\LogReceiver.ps1          # 开着别关
.\Deploy-DaLedou.ps1 -WaitCi
```

手机播官方动画时，日志会推到 `ibox-analytics\_ipa_cache\ruffle_live.log`，Cursor 可直接读，不必再转发。手机与电脑需同一局域网。

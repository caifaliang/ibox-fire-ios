# 本机 USB 装机脚本

| 脚本 | 作用 |
|------|------|
| `Setup-SideloadTools.ps1` | 装 iPASide、生成 `config.local.ps1` |
| `Login-AppleId.ps1` | Apple ID 登录（含 2FA） |
| `Deploy-DaLedou.ps1` | 下 CI IPA → 重签 → 装到手机 |
| `LogReceiver.ps1` | 本机收手机动画日志 → `_ipa_cache/ruffle_live.log` |
| `Push-DebugLogUrl.ps1` | 把本机接收地址写入 App（Deploy 后自动调） |
| `Find-IpasideEngine.ps1` | 内部：定位引擎 |
| `config.example.ps1` | 配置模板（复制为 `config.local.ps1`） |

`config.local.ps1` 含密钥，已加入 `.gitignore`，不要提交。

### 实时日志（给 Cursor 用）

1. 电脑开着接收端（测试动画时保持窗口不关）：
   ```powershell
   .\LogReceiver.ps1
   ```
2. 手机与电脑同一 Wi‑Fi（或 USB 共享网络）
3. 装 fd22+ 后跑一次 `.\Deploy-DaLedou.ps1`（会写入 `debug_log_url.txt`）
4. 手机打开官方动画 → 日志写入：
   `ibox-analytics\_ipa_cache\ruffle_live.log`
   Agent 可直接读该文件，无需再复制转发。

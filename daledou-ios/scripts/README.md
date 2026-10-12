# 本机 USB 装机脚本

| 脚本 | 作用 |
|------|------|
| `Setup-SideloadTools.ps1` | 装 iPASide、生成 `config.local.ps1` |
| `Login-AppleId.ps1` | Apple ID 登录（含 2FA） |
| `Deploy-DaLedou.ps1` | 下 CI IPA → 重签 → 装到手机 |
| `Find-IpasideEngine.ps1` | 内部：定位引擎 |
| `config.example.ps1` | 配置模板（复制为 `config.local.ps1`） |

`config.local.ps1` 含密钥，已加入 `.gitignore`，不要提交。

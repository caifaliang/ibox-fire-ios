# 已证伪 / 禁止重试（无新证据勿再试）

| 项 | 结论 | 证据 |
|----|------|------|
| iOS `wtlogin?p=` | 授权失败 | 多次实机 |
| schemacallback 换 `daledoulogin` / `daledouapp` / `tencent102067279` | 同意后均无 `callback HIT` | Exp A/B/C fd76–78 |
| 依赖饭点一键对拍 | 用户：无参考意义 | 2026-10-14 |
| waitingQQConfirm 再挂 TicketFetcher | 杀进程恢复后再开 QQ → 闪退 | fd74 |
| Int `hash33` | 冷启 SIGTRAP | fd75 |
| qrcode 里 `*` → `%2A` | 票过期 | fd58 前 |
| 等 QQ 自动回跳再做主路径 | 不可行；手动回 + harvest | E2 + Exp C |

登录 GOLDEN：`138fd75`（通知/横幅为 fd80–81 体验层，不改会话逻辑）。

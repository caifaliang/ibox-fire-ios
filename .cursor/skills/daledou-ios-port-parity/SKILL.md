---
name: daledou-ios-port-parity
description: >-
  Port or align daledou-ios features with Android/competitor by writing a behavior
  spec first, then platform mapping, screenshot/log parity checks, and one screen
  at a time. Use for 对齐笔记, 竞品对拍, 一键登录, Ruffle replay, or any
  Android→iOS transplant. Do not line-translate decompiled code.
---

# DaLedou iOS Port Parity

## When to use

- Aligning a feature with Android (`F:\DaLedou_App_Dev\daledou`) or competitor (FandianAssistant)
- **Do not** use `F:\daledou` as port source (wrong tree; purged fd88)
- Login / WebView / Ruffle / scheme / Cookie issues after a “copy competitor” attempt
- User asks for 对齐、对拍、规格、不要乱试

## Hard rules

1. **Spec before code.** Extract behavior (state machine, params, timing, edges). Do not line-translate decompiled Swift/Java.
2. **Rewrite against the spec** with own assets. Do not ship competitor art/binary blobs.
3. **One screen or one feature per change.** Verify before stacking more.
4. **Log timeline + falsify.** Record what was tried and ruled out; do not re-try a killed approach without new evidence.
5. **One-key iOS path:** `qrcode` + `schemacallback` (Android `p=` →「授权失败」— forbidden). **Do not 对拍饭点 one-key** (user: 无参考意义). Auto-return after Agree is not available; manual return + harvest is accepted.

## Workflow

### 1. Behavior spec (fill before coding)

```markdown
## Feature: <name>
### Goal (user-visible)
### States
### Triggers / inputs
### Outputs (Cookie / navigation / UI)
### Timing / timeouts
### Edges (expire, cancel, background, no QQ installed)
### Explicit non-goals (what NOT to copy)
```

### 2. Platform map

| Concern | Android / competitor | iOS target |
|--------|----------------------|------------|
| Web shell | WebView + CookieManager | WKWebView + WKHTTPCookieStore |
| Asset load | WebViewAssetLoader / file | scheme handler / Bundle |
| QQ return | default browser / custom scheme | URL scheme / stay in WKWebView |
| Replay | Activity / process | SwiftUI fullScreenCover + Ruffle |

### 3. UI tokens (if UI parity)

Extract from screenshots: color, type size, spacing, radius, animation ms → token table → implement from table, not by eye.

### 4. Parity checks

- **UI:** same state, same resolution; side-by-side screenshots; checklist of diffs.
- **Behavior:** same inputs → compare request sequence, key logs, state transitions.
- **Perf budget:** memory / jetsam / fps written in the spec.

### 5. Login (state machine — current)

目标是 **可进游戏壳的会话**。一键实测常只有 `openId`+`accessToken`+`newuin`（无 skey）；`hasGameSession` 两者都认。粘贴 Cookie 仍要求 skey。

**主路径：WebView xlogin 取票**（对齐 Fandian；fd59+）

| Phase | Behavior |
|-------|----------|
| fetchingTicket | 加载 live style=35 xlogin → JS `ptqrshow` type=1 → `polling()` |
| waitingQQConfirm | freeze 后再 `ptqrshow`；`wtloginmqq3?qrcode=`（`encodeURIComponent` 保留 `*`） |
| loadingGame | 回壳 resume → 短等 OAuth → phonepk + `syncSessionFromWebView` |
| succeeded | SessionStore 有 skey/p_skey **或** openId+accessToken |

实测：QQ 同意后常无 schemacallback；手动回 App → `index.php` 种 OpenID → phonepk。须把 OpenID Cookie 写入 SessionStore，标题才变「大乐斗」。

**GOLDEN baseline (2026-10-14 user OK):** build `138fd75` / `74977a8`. See `.cursor/memory/MEMORY.md`. Do not regress: fetcher-only-on-`fetchingTicket`, UInt32 `hash33`, jetsam cookie persist + restore harvest.

| Forbidden | Why |
|-----------|-----|
| 打开 QQ 后仍 `ptqrshow` / 加载新 xlogin | 作废当前票 |
| `waitingQQConfirm` 再挂 OneKeyTicketFetcher | 杀进程恢复后再开 QQ → 回壳闪退 |
| Int `hash33`（非 UInt32 wrap） | 冷启 restore poll → SIGTRAP |
| `*` → `%2A` | 票校验失败 |
| `wtlogin?p=` | iOS 授权失败 |
| 进游戏却不 `onCookiesCaptured` | 动画/战斗无 skey |

扫码 + Cookie 为降级路径。Ruffle 勿动。

### 6. Evidence habit

After each attempt, append to the feature note:

```text
Tried: ...
Symptom: ...
Falsified: ...
Next: ...
```

## Out of scope

- `frontend-design` for 1:1 competitor clone (it biases style)
- Copying decompiled competitor source/assets for distribution

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

- Aligning a feature with Android (`F:\daledou`) or competitor (FandianAssistant)
- Login / WebView / Ruffle / scheme / Cookie issues after a “copy competitor” attempt
- User asks for 对齐、对拍、规格、不要乱试

## Hard rules

1. **Spec before code.** Extract behavior (state machine, params, timing, edges). Do not line-translate decompiled Swift/Java.
2. **Rewrite against the spec** with own assets. Do not ship competitor art/binary blobs.
3. **One screen or one feature per change.** Verify before stacking more.
4. **Log timeline + falsify.** Record what was tried and ruled out; do not re-try a killed approach without new evidence.
5. **One-key follows Fandian iOS IPA** (`qrcode` + `schemacallback`). Android `p=` causes iOS「授权失败」— forbidden.

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

目标是 **游戏站点 skey 会话**，不是 QQ OAuth access_token。

| Phase | Behavior |
|-------|----------|
| preparing / awaitingAuthPage | Clear → load authorize；脱敏记初始 URL |
| fetchingTicket | **仅** xlogin 上 ptqrshow；离开 xlogin 停取票 |
| awaitingQQ | `wtloginmqq3?qrcode=&schemacallback=` |
| recovering | 回壳校验一次；有效则最多刷新 phonepk **一次** |
| unsupportedQuickLogin | connect「亿万用户」/「不支持快速登录」→ **终态停**，提示扫码/Cookie |
| failed | 取票失败/超时 → 终态，提示扫码/Cookie |

| Forbidden | Why |
|-----------|-----|
| phonepk ↔ connect 自动循环 | 死局 |
| `wtlogin?p=` 当真路径 | iOS 授权失败 |
| 把 style=35 当成功标准 | 服务端未必允进 |

扫码 + Cookie 为正式可用路径。Ruffle 勿动。

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

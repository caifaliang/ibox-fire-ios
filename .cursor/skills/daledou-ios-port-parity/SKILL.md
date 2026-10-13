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

**主路径：WebView xlogin 取票**（对齐 Fandian；fd59+）

| Phase | Behavior |
|-------|----------|
| fetchingTicket | 加载 live style=35 xlogin → JS `ptqrshow` type=1 → `polling()` |
| waitingQQConfirm | freeze 后再 `ptqrshow`；`wtloginmqq3?qrcode=`（`encodeURIComponent` 保留 `*`） |
| loadingGame | 回壳 resume + 推 phonepk + `syncSessionFromWebView` |
| succeeded | SessionStore 有非空 skey/p_skey |

实测：QQ 安全确认倒计时后点同意，客户端常弹「二维码已过期」，但**马上回 App** 仍可进游戏；须把 WebView Cookie 写入 SessionStore，否则官方动画报未登录。

| Forbidden | Why |
|-----------|-----|
| 打开 QQ 后仍 `ptqrshow` / 加载新 xlogin | 作废当前票 |
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

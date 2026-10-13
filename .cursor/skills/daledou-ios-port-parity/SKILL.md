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
5. **One-key follows Fandian QQ_ONE_KEY** (`phonepk` + live `p=`). Do not reintroduce ptqrshow/qrcode one-key without new evidence + user ask.

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

### 5. Login (饭点 QQ_ONE_KEY 1:1 — current)

| Step | Behavior |
|------|----------|
| Entry | Clear QQ WK data → iPhone UA → `phonepk?cmd=index&channel=0` |
| Page | Tencent → authorize → live `style=35` xlogin（可切号；用户点页内「一键登录」） |
| Jump QQ | Intercept `wtloginmqq://…?p=` → open `wtloginmqq://ptlogin/qlogin?p=<encoded>` **without** schemacallback（`returnRoute=https`） |
| Return | Allow `ssl.ptlogin2/jump` **with** clientuin/clientkey/keyindex；connect「亿万用户」→ bounce phonepk |
| Non-goals | No ptqrshow / qrcode / hide `#onekey` / blue banner / Desktop-UA for one-key |

| Forbidden | Why |
|-----------|-----|
| Desktop UA for one-key | style=33 / no `#onekey` |
| Stale hardcoded h5sig in p= | 「授权失败」 |

扫码 `graph show` + Cookie 粘贴仍为备份。官方动画（Ruffle）与一键无关，勿回退。

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

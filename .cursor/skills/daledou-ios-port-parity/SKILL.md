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
5. **iOS ≠ Android for QQ login.** Never assume `wtlogin` + `p=` + default-browser capture works on iPhone.

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

### 5. Login (known traps — do not regress)

| Approach | iOS result | Verdict |
|----------|------------|---------|
| 任何 `wtlogin?p=`（含页内「一键登录」、新鲜/过期 h5sig） | 「网页申请使用」→ 授权失败、**无切号** | **FORBIDDEN on iOS**（安卓饭点可用，iOS 不行） |
| **Desktop UA** authorize → style=33 + 等 `pt.hasInit` | 永久 `no-init` | **FORBIDDEN** |
| **iPhone UA** authorize → 新鲜 style=35 → **ptqrshow（不依赖 hasInit）** → `wtloginmqq3?qrcode=` + `schemacallback=daledoulogin://` | QQ 原生确认**可切号** | **PRIMARY** |
| 扫码 `graph show` display=pc | 壳内跟完 | OK backup |
| 粘贴 Cookie | 总兜底 | OK |

**Primary one-key on iOS (饭点 QQ_ONE_KEY 入口 + iOS 取票):** iPhone UA load `phonepk` → authorize → live `style=35` xlogin → user may switch → `ptqrshow` → `wtloginmqq3?qrcode=` only. Bounce off connect「亿万用户」marketing. Never open `p=`; never click page「一键登录」.

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

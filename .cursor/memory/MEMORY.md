# DaLedou / iBox Analytics Memory

## One-key login GOLDEN (verified 2026-10-14)

**Build:** `138fd75` / commit `74977a8` — user confirmed 「完美成功了」.

### Must-keep behavior
1. **Fandian iOS path only:** `wtloginmqq3?qrcode=` + `schemacallback=daledoulogin://`. Never Android `p=` on iOS.
2. **`attachOneKeyFetcher`:** only when `oneKeyPhase == .fetchingTicket`. Do **not** attach on `.waitingQQConfirm` (QQ-kill restore) — re-opens QQ → crash on return (fd74).
3. **`hash33`:** UInt32 wrapping (`&+` / `&<<`). Int `+=`/`<<` → EXC_BREAKPOINT / cold-start crash when restore harvests (fd75).
4. **Jetsam survival:** `persistLaunchSession` qrsig cookies → cold start `qq_kill_restore` → restore cookies + background harvest → user returns → finish.
5. **Soft enter:** OpenID session OK for shell; avoid force reinject that clears WK cookies.
6. **Waiting baseURL:** `about:blank` (not dld) so marketing bounce does not false-positive「已进游戏」.
7. **encodeURIComponent:** keep `*` unescaped in qrcode.

### Anchor files
- `daledou-ios/Sources/Core/AppViewModel.swift`
- `daledou-ios/Sources/Auth/QqOneKeyLogin.swift`
- `daledou-ios/Sources/Auth/OneKeyCheckSigCompleter.swift`
- `daledou-ios/Sources/UI/GameWebView.swift`

### Do not regress
- Re-attaching ticket fetcher after restore
- Trapping hash33
- Loading marketing as baseURL while waiting
- `wtlogin?p=` on iOS

## Auto-return after QQ Agree

### Exp A (fd76) — FALSIFIED for daledoulogin://
- Log: `qq_open cb=daledoulogin://` + `qq_open_done ok=true`
- **No** `callback HIT` / `open_url`
- Return: `became_active via=manual_or_system`
- Ticket still OK (`poll=0 ticket_ok`); login works after manual return
- Conclusion: QQ does not open `daledoulogin://` after 同意 on this path

### Exp B (fd77) — try `schemacallback=daledouapp://` (Android scheme)
Success = log shows `callback HIT`. Fail = same as A → try tencent102067279 / Fandian URL (Exp C).

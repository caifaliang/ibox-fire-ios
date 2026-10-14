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

### Exp B (fd77) — FALSIFIED for daledouapp://
- `qq_open cb=daledouapp://`, no `callback HIT`, `via=manual_or_system`
- Manual return still logs in (openid)

### Exp C (fd78) — FALSIFIED for tencent102067279://
- `qq_open cb=tencent102067279://`, **no** `callback HIT` / `open_url`
- `became_active via=manual_or_system`; login still OK after manual (`enter_game` openid)
- **Conclusion (2026-10-14):** On iOS `wtloginmqq3?qrcode=` path, QQ does **not** open any tested schemacallback after 同意. Scheme roulette stopped.
- Working UX: manual `< DaLedou` / app switch + background harvest (fd75 golden).
- Next only with new evidence: Fandian IPA dump of live wtlogin URL; Universal Link + associated domains; or local notification “点回大乐斗” after poll=0 (soft assist, not true auto).

### External AI consult (2026-10-14) — agreed plan
- Scheme roulette stopped; QQ likely ignores schemacallback for our path.
- **E1**: screen-record 饭点 Agree (manual?).
- **E2** (fd79): hook page/native wtlogin → `wtlogin_probe` log keys+cb.
- **E4**: only if E2 shows browser cb / richer keys — positive control.
- Path1 UX: status hints manual ◀ return (ship with E2).

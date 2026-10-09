# iOS Official Fight Animation Implementation Plan

> **For agentic workers:** Execute task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** On `phonepk?cmd=viewfight`, show「官方动画」FAB; fetch Act via petpk; play with bundled Ruffle + PetFunFight.swf.

**Architecture:** SwiftUI FAB overlay → `FightActFetcher` (Cookie + candidates) → fullScreenCover `ReplayWebView` with custom `app-ruffle://` scheme serving `Resources/ruffle_fight` and CDN fallback for action packs.

**Tech Stack:** SwiftUI, WKWebView, WKURLSchemeHandler, URLSession, APK `ruffle_fight` assets

---

### Task 1: Bundle ruffle_fight assets

**Files:**
- Copy: `F:/daledou/app/src/main/assets/ruffle_fight/**` → `daledou-ios/Resources/ruffle_fight/` (exclude `*.map`)
- Modify: `daledou-ios/project.yml` — add Resources folder

- [ ] Copy assets, wire XcodeGen resources, commit

### Task 2: URL helpers + Act fetcher

**Files:**
- Modify: `daledou-ios/Sources/Auth/LoginURLs.swift` — `isViewFightUrl`
- Create: `daledou-ios/Sources/Fight/FightPetCandidates.swift`
- Create: `daledou-ios/Sources/Fight/FightActFetcher.swift`

- [ ] Port candidates + extractReplayString + URLSession fetch with Cookie
- [ ] Commit

### Task 3: Replay WKWebView + FAB UI

**Files:**
- Create: `daledou-ios/Sources/Fight/RuffleSchemeHandler.swift`
- Create: `daledou-ios/Sources/Fight/ReplayWebView.swift`
- Modify: `daledou-ios/Sources/Core/AppViewModel.swift`
- Modify: `daledou-ios/Sources/App/RootView.swift`
- Modify: `daledou-ios/Resources/Info.plist` — landscape + ATS for fight hosts if needed

- [ ] Scheme handler serves bundle + CDN fallback + petpk stub
- [ ] FAB + fullScreenCover + openReplay flow
- [ ] Push main for IPA build

### Out of scope
群侠 FAB、动作包预下载、文字拼接、可拖拽 FAB 持久化

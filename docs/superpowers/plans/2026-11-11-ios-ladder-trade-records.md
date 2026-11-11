# iOS Ladder UI + Trade Records Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Website-style ladder UI on tech+H5 query; wire H5 trade records like APK.

**Architecture:** Shared SwiftUI `LadderResultView` + `TradeRecordsPane`; site API for trades; enrich query VM progress fields.

**Tech Stack:** SwiftUI, existing QueryEngine / ApiRepository / OfficialH5View

## File map

- `Sources/App/LadderResultView.swift` (new)
- `Sources/App/TradeRecordsPane.swift` (new)
- `Sources/App/Screens.swift` — QueryPane uses LadderResultView
- `Sources/App/OfficialH5/OfficialH5View.swift` — records + query overlay
- `Sources/Net/ApiRepository.swift` — fetchTradeRecords
- `Sources/Core/AppViewModel.swift` — trade + query meta
- `Sources/Engines/QueryEngine.swift` — progress pages if needed
- `project.yml` — bump build 12

### Task 1: LadderResultView + QueryPane wire
### Task 2: Trade API + VM + TradeRecordsPane
### Task 3: OfficialH5 overlay + openTool gid
### Task 4: Bump, CI, install

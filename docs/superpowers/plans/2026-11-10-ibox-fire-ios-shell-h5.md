# iBox科技 iOS 商业壳 + 官方 H5 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** iOS 并联对齐 APK 商业壳（科技/进行中/官方H5/我的）并落地官方 H5 全量注入。

**Architecture:** `Sources/App/Shell/` 新壳 + `Sources/App/OfficialH5/` WK 注入；`MainShell` 改接新壳；业务 pane 内嵌不动；矩星壳上隐藏。

**Tech Stack:** SwiftUI · WKWebView · URLSession · 现有 AppViewModel / TaskRunner

**Spec:** `docs/superpowers/specs/2026-11-10-ibox-fire-ios-shell-h5-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `Sources/App/Shell/FeatureCatalog.swift` | 对齐 Android FeatureCatalog |
| `Sources/App/Shell/FireBottomBar.swift` | 底栏四 Tab |
| `Sources/App/Shell/PlatformSegment.swift` | iBox/NewBee/ibPro |
| `Sources/App/Shell/FeatureTileGrid.swift` | 瓷砖网格 |
| `Sources/App/Shell/TechHubPage.swift` | Hub |
| `Sources/App/Shell/FeatureWorkbench.swift` | 工作台壳 |
| `Sources/App/Shell/RunningJobsPage.swift` | 进行中 |
| `Sources/App/Shell/LiveJobDock.swift` | LIVE Dock |
| `Sources/App/Shell/ShellHost.swift` | 底栏+Hub/Workbench/Me 宿主 |
| `Sources/App/OfficialH5/SharedPrefsPack.swift` | flutter.* 注入脚本 |
| `Sources/App/OfficialH5/H5ApiBridge.swift` | XHR/fetch 原生桥 |
| `Sources/App/OfficialH5/OfficialH5WebView.swift` | WK 包装 |
| `Sources/App/OfficialH5/OfficialH5View.swift` | 全屏 UI + 芯片 |
| `Sources/App/Screens.swift` | MainShell 改接 ShellHost；ModePane 保留 |
| `Tests/FeatureCatalogTests.swift` | catalog 过滤单测 |
| `Tests/SharedPrefsPackTests.swift` | 注入键单测 |
| `project.yml` | build bump |

---

### Task 1: FeatureCatalog + 单测

- [ ] Create `FeatureCatalog.swift`（TECH/QUERY/PUSH/NB/IB，无 ts_*）
- [ ] `filterFeatures(platform:category:query:)` 对齐 Android
- [ ] Tests：ibox tech 含捡漏；ibpro 仅 ib_*；搜索跨分类
- [ ] Commit

### Task 2: Shell 原子组件

- [ ] FireBottomBar / PlatformSegment / FeatureTileGrid / LiveJobDock
- [ ] Commit

### Task 3: TechHub + Workbench + Running

- [ ] TechHubPage（分段+搜索+分类+瓷砖）
- [ ] FeatureWorkbench（返回 Hub + 内容槽）
- [ ] RunningJobsPage 空态 CTA
- [ ] Commit

### Task 4: 接入 MainShell

- [ ] ShellHost 四 Tab；Hub↔Workbench；我的=Profile
- [ ] 去掉旧顶栏三层；LIVE Dock 替代顶红条
- [ ] 矩星不进分段
- [ ] Commit

### Task 5: SharedPrefsPack + H5ApiBridge

- [ ] Pack.build + boot 脚本（禁 SW）
- [ ] Bridge bootScript + WK message handler + URLSession
- [ ] 单测 Pack 键齐全
- [ ] Commit

### Task 6: OfficialH5View + 底栏入口

- [ ] 拉 HTML 注入 loadHTMLString；Cookie 预热
- [ ] 芯片浮层内嵌 ModePane 对应功能
- [ ] 无票提示
- [ ] Commit

### Task 7: 版本 + 装机

- [ ] project.yml CURRENT_PROJECT_VERSION bump
- [ ] push → Deploy-IboxFire -WaitCi -ForceInstall

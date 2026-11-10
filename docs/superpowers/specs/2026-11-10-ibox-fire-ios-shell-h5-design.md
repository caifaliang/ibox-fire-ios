# iBox科技 iOS · 商业壳对齐 + 官方 H5 注入

**日期：** 2026-11-10  
**产品：** iBox科技（`ibox-fire-ios`）  
**真理源：** `ibox-fire-android` 商业壳（`ui/shell/`）+ `OfficialH5Activity` / `H5ApiBridge` / `SharedPrefsPack`  
**状态：** 用户已确认 §1–§3，待审阅本文件后进入 implementation plan

---

## 1. 目标

把 iOS 从「旧顶栏三层堆叠 + 仅换象牙色」升级到与 APK 同构：

1. **商业壳：** 底栏「科技 / 进行中 / 官方H5 / 我的」+ Hub 瓷砖 + Workbench  
2. **官方 H5 全量：** 票注入 + 禁 SW + 原生 API 桥 + 顶栏工具芯片 + 科技浮层  

**非目标：**

- 改开火 / 捡漏 / 支付等引擎与协议  
- 网站 `/oh5` 反代、personal-center iframe（网站路径；本期对齐 APK WebView）  
- 壳上暴露矩星（代码保留，入口隐藏）  
- 双主题开关、逐页业务 pane 重设计  

---

## 2. 已锁定决策

| 项 | 选择 |
|----|------|
| 范围 | A：整壳对齐 APK + 官方 H5 全量 |
| H5 深度 | A：注入 + 禁 SW + API 桥 + 芯片浮层 |
| 矩星 | 壳上隐藏；`ts_*` 代码保留 |
| 落地路径 | 1：并联新壳 `Sources/App/Shell/` + `Sources/App/OfficialH5/` |
| 色板 | 沿用现有 iOS `Palette` 象牙墨色（对齐 FireDesign） |
| 业务 pane | Workbench / H5 浮层内嵌现有 `Screens.swift` 内容，不重写引擎 UI |

---

## 3. 信息架构

### 3.1 底栏

| Tab | 作用 |
|-----|------|
| **科技** | Hub：平台分段 + 分类 + 瓷砖 + 搜功能 |
| **进行中** | 当前/最近任务；空态 CTA「去科技」 |
| **官方H5** | 打开注入 WK 页（需 `iboxToken`） |
| **我的** | 现有 Profile |

### 3.2 科技 Tab 级联

1. **平台：** `iBox` · `NewBee` · `ibPro`（硬编码三平台，无矩星）  
2. **分类：** iBox → 科技 / 查询信息 / 推送；NewBee / ibPro → 收敛分类（抢购 · 捡漏 · ib 卖求购/查挂单等，对齐 APK `FeatureCatalog`）  
3. **功能：** 瓷砖或 Sheet 行 → `techMode`，进入 Workbench 内嵌现有 pane  

### 3.3 辅助

- 搜功能：按 label/key 过滤直达  
- LIVE Dock：有运行任务时浮于内容上方；停用现有 `stopTask`；取代旧顶红条  
- 日志：功能页默认收起，标题沿用现有「xx日志」  

### 3.4 废止

- 顶栏连续堆：平台按钮 + 分类条 + 功能芯片条  
- 顶区红色「进行中」通栏  

---

## 4. 模块边界

```
ibox-fire-ios/Sources/App/
  Shell/
    MainShell.swift          // 底栏 + tab 宿主（替换旧 MainShell 体）
    FireBottomBar.swift
    TechHubPage.swift
    FeatureWorkbench.swift
    PlatformSegment.swift
    FeatureTileGrid.swift
    FeatureCatalog.swift     // key/label 对齐 Android FeatureCatalog
    RunningJobsPage.swift
    LiveJobDock.swift
  OfficialH5/
    OfficialH5View.swift     // 全屏容器 + 顶栏芯片
    OfficialH5WebView.swift  // WKWebView 包装
    SharedPrefsPack.swift    // flutter.* 编码与 boot 脚本
    H5ApiBridge.swift        // message handler + URLSession 回灌
    OfficialH5Tools.swift    // 芯片 + 浮层内嵌 pane
  Screens.swift              // 业务 pane / 登录 / Profile 保留为内容槽
  DesignSystem/              // Tokens / Haptics / Components 沿用并按需补 token
```

- 状态源仍为 `AppViewModel` / `TaskRunner`  
- 壳只调用已有 `appPlatform` / `techMode` / `stopTask` / 登录 API  
- `project.yml` 纳入新 Swift 源文件  

---

## 5. 官方 H5 数据流

**入口：** 底栏「官方H5」→ 无票则提示「请先登录 iBox」→ 有票则全屏 `OfficialH5View`（WK，不用 SFSafari）。

**启动顺序（对齐 APK）：**

1. `SharedPrefsPack.build(access, refresh, deviceId, uid, exp)`  
   - 写入键：`access_token` / `refresh_token` / `device_id` / `user_id` / `ibTokenExpiredAt` / `ssoUserId` / `login_type` / `user_info`（JSON.encode 风格与 APK 一致）  
2. 原生拉取 `https://h5.ibox.art/` HTML  
3. 在 `</head>` 前插入：`H5ApiBridge.bootScript()` + 禁 SW + `toBootHeadScript()`（写 `flutter.*`）  
4. 去掉 / 置空 `serviceWorkerSettings`，避免 SW 劫持 API  
5. `loadHTMLString`（baseURL = H5 origin）；Cookie 预热 `token` / `expiredAt` 到 h5、sail-api、personal-center  
6. 首屏后校验 localStorage；失败可重试一次  

**API 桥：** JS patch XHR/fetch → `WKScriptMessageHandler` → 原生 `URLSession`（补 Origin/Referer 为 H5）→ base64 body 回灌 `__iboxFireNetDone`。

**顶栏芯片：** 查挂单 / 捡漏 / 卖求购 / 成交记录 → 浮层内嵌现有 pane；从 URL / 页内 JS 刮 GID+名带入（对齐 `openTechFromExternal`）。

**常量：**

- `H5_ORIGIN` = `https://h5.ibox.art`  
- `H5_BOOT` = `https://h5.ibox.art/`  
- `H5_LAUNCHER` = `https://h5.ibox.art/#/launcher`（若校验后需导航则用之）  

---

## 6. 视觉与触感

- 象牙墨色：`Bg #F7F4EE` / `Surface #FFFCF7` / `Ink #111827` / `LiveAmber #C4A574`（已在 `Palette`）  
- Hub：标题 ExtraBold「iBox科技」；瓷砖为主角；搜索/分类视觉降权  
- Workbench：少厚描边；纸感分层  
- 触感：瓷砖轻触、主 CTA 中等、停止偏重  
- 动效仅 3：Hub↔Workbench ~180ms fade+slide；底栏指示；按钮 scale；Reduce Motion 只留短 fade  

---

## 7. 错误与空态

- 搜无结果：「无匹配功能」  
- 进行中空：「暂无运行任务」+「去科技」  
- H5 无票：Toast / 横幅「请先登录 iBox」  
- H5 注入失败：状态文案 + 重试；不静默白屏  
- VIP 预览条：保留现有逻辑，套新 Surface  

---

## 8. 风险与对策

| 风险 | 对策 |
|------|------|
| WK 真机闪退 | H5 独立 WK 控制器；不复用 SiteBrowse/SFSafari 路径 |
| sail-api Failed to fetch | 必做原生 API 桥 |
| SW 劫持 | boot HTML 禁 SW + 去 serviceWorkerSettings |
| 3 App 签名限额 | 沿用现有 `com.ibox.fire` + iPASide |
| 矩星误露 | 平台分段硬编码三平台；Catalog 壳列表不含 `ts_*` |

---

## 9. 验收标准

1. 冷启动见象牙墨色商业壳；底栏四字：`科技` · `进行中` · `官方H5` · `我的`  
2. iBox：分段 → 分类 → 打开「捡漏」等且 `techMode` key 正确  
3. NewBee / ibPro：功能列表与 APK `FeatureCatalog` 一致；矩星不出现在分段  
4. 有运行任务时 LIVE Dock 可见且停止有效；无顶红条  
5. 官方 H5：已登录 iBox 可免登进入官方页；localStorage 含 `flutter.access_token` / `flutter.user_info`  
6. 芯片可打开查挂单/捡漏/卖求购/成交浮层  
7. 业务开火行为与改壳前一致；无新增崩溃路径  

---

## 10. 参考

- APK：`ui/shell/*`、`OfficialH5Activity.kt`、`H5ApiBridge.kt`、`OfficialH5Tools.kt`  
- 既有规格：`2026-11-10-ibox-fire-commercial-shell-design.md`、`2026-11-10-ibox-fire-ivory-polish-design.md`  
- MEMORY：Website / APK Official H5 inject 笔记（2026-11-05）  

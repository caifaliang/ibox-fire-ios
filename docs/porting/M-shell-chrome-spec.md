# 壳框架 · 顶栏 / 底栏（真源 DaLedou_App_Dev）

## Goal
对齐 `AppRootScaffold` + `GameShellScreen` 嵌入模式：顶工具条 + 状态条 + 统一底栏；中间为首页 WebView / 其它 Tab 占位。

## Top（embed ShellToolStrip + ShellStatusBar）
- URL chip：展示当前页；点开可粘贴/打开腾讯域链接；可复制
- 图标：截长图（本切片提示后续）、刷新、查询（本切片提示后续）
- 状态条：显示名（QQ/未登陆）、会员文案占位、后台开关 UI（本切片仅落盘开关，不跑 Worker）

## Bottom（UnifiedBottomDock）
顺序：后退 | 前进 | 首页 | **菜单** | 日志 | 记录 | 我的  
- 后退/前进：WKWebView canGoBack/Forward  
- 首页：Tab=0  
- 菜单：打开功能菜单 sheet（本切片：一键/扫码/退出；其它项灰显「按 APK 待接」）  
- 日志/记录/我的：切 Tab，内容页占位（标题对齐 APK）

## Colors
`DlColors`：Brand `#111827`、Accent `#2563EB`、Canvas `#F4F6F9`、Surface `#FFF`

## Non-goals（本切片）
- 截长图算法、查询页、日志/记录业务、后台 TaskRunner

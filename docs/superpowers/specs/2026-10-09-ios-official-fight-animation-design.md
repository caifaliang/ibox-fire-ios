# iOS 官方战斗动画（方案 A / 路径 1）

日期：2026-10-09  
范围：乐斗过程页悬浮「官方动画」→ Ruffle 播官方 SWF  
对齐：Android DaLedou `DraggableViewFightFab` + `RuffleReplayActivity` 主路径  
不做：群侠入口、50MB 动作包预下载/暖机、文字战报多页拼接

## 目标

在已登录的游戏 WebView 中，当用户打开 **查看乐斗过程**（`phonepk?cmd=viewfight`）时：

1. 右下角出现可点的「官方动画」按钮  
2. 点击后用当前 Cookie 向 `fight.pet.qq.com/cgi-bin/petpk` 拉取 Act  
3. 全屏打开包内 Ruffle 播放页，注入 Act，验证 iOS 能否播放官方动画  

成功标准：真机/签名 IPA 上能看到战斗 Flash 动画画面（允许首次联网拉 CDN 动作资源稍慢）。

## 架构

```
GameWebView (phonepk viewfight)
    │ URL 含 cmd=viewfight 且非 knightfight
    ▼
RootView 叠加「官方动画」FAB
    │ 点击
    ▼
FightActFetcher（Cookie + petpk 候选 URL）
    │ Act 字符串 + replayId
    ▼
ReplaySheet → WKWebView 加载 bundle://ruffle_fight/index.html
    │ evaluateJS __injectFightActB64(act, id)
    ▼
PetFunFight.swf + Ruffle WASM（CDN 拉 action_gg/mm 等）
```

## 组件

| 单元 | 职责 | 依赖 |
|------|------|------|
| `LoginURLs.isViewFightUrl` | 与 APK `isViewFightUrl` 一致 | 无 |
| `FightPetCandidates` | phonepk URL → petpk 候选列表（移植 `phoneViewFightPetCandidates` 常用分支） | 无 |
| `FightActFetcher` | 带 Cookie 请求候选 URL，解析 `&Build:` / JSON `"string"` | SessionStore |
| `ViewFightFab` | 右下角按钮；loading 态 | AppViewModel |
| `ReplayView` | 全屏 WKWebView + 关闭；允许 `fightimg.pet.qq.com` | Bundle 资源 |
| Bundle `ruffle_fight/` | 从 APK `assets/ruffle_fight` 拷贝官方壳 | project.yml Resources |

## 数据流

1. `onNavigated` / `currentURLString` 更新 → `showViewFightFab = isViewFightUrl`  
2. FAB 点击 → `statusText = 正在获取战斗数据…`，禁用重复点  
3. `FightActFetcher.fetch(pageUrl)`：按候选顺序请求，取到非空 Act 即停；全失败则 Toast/状态错误  
4. `showReplay = true`，传入 `act` + `replayId`（URL 的 `id`/`repid`）  
5. Replay WKWebView `loadFileURL` 或自定义 scheme 加载本地 `index.html`；`didFinish` 后 Base64 注入 Act  
6. 关闭 Sheet 回到原 viewfight 页（不强制 reload）

## Act 解析（与 APK 对齐）

- 响应体以 `&Build:` 开头 → 整段作为 Act  
- 否则解析 JSON 字段 `"string"`（含 `&Build:1;...&Act:...`）  
- MVP 优先覆盖：**普通乐斗 `cmd=viewfight&id=`**；竞技场/华山等候选映射一并移植常用分支，避免「回收」空 Act，但不保证全模式一次过

## 资源与网络

- **打进 IPA**：APK `ruffle_fight`（`index.html`、`PetFunFight.swf`、`ruffle/*`、`gres` 小 stub、字体、`petpk_query.json`）  
- **不打进 IPA**：`action_gg` / `action_mm` 约 50MB → WKWebView **允许**访问 `https://fightimg.pet.qq.com`  
- 旧半成品 `Resources/flashreplay/`：本功能改用 `ruffle_fight/`，半成品可保留不引用，避免混用  
- ATS：`Info.plist` 对 `fight.pet.qq.com`、`fightimg.pet.qq.com`、`dld.qzapp.z.qq.com` 按现有策略放行（已有全局例外则不动）

## WKWebView 要点

- `WKPreferences.isElementFullscreenEnabled` / 允许 JS  
- 需要 WASM：`WKWebpagePreferences` 默认即可；CSP 与 APK `index.html` 一致时允许 `wasm-unsafe-eval`  
- 本地文件：优先 `loadFileURL(_:allowingReadAccessTo:)` 读整个 `ruffle_fight` 目录；若相对路径失败，再改自定义 URL scheme + 拦截  
- Cookie：仅 petpk HTTP 请求带 Session Cookie；播放页 CGI stub 由本地 HTML/拦截处理（MVP 可先让 SWF 直连 CDN，缺 stub 再补 `shouldIntercept`）

## 错误处理

| 情况 | 表现 |
|------|------|
| 非 viewfight | 不显示 FAB |
| 未登录 / 无 skey | FAB 可点，提示先登录 |
| petpk 全失败 / 空 Act | 状态栏错误文案，不打开播放页 |
| Ruffle/WASM 崩 | 播放页显示错误文案 + 关闭 |
| CDN 慢 | 播放页可显示「加载动作资源…」（若 HTML 已有则复用） |

## 测试计划

1. 扫码登录 → 进游戏 → 任意乐斗 → 打开「查看乐斗过程」→ 见 FAB  
2. 点「官方动画」→ 能取到 Act → 全屏动画有画面与角色动作  
3. 关闭后仍在原文字战报页  
4. 非 viewfight 页 FAB 消失  

## 明确不做（本迭代）

- 群侠录像 FAB / `knightfight` 专用入口  
- `RuffleWarmService` / 预下载动作包到 Documents  
- `ViewFightHtmlSplicer` 多页文字拼接  
- 可拖拽 FAB 位置持久化（固定右下角即可）

## 风险

- IPA 体积：`ruffle_fight` 约数十 MB，可接受用于验证  
- iOS WKWebView + Ruffle WASM 性能/崩溃未知 → 本迭代就是为验证此风险  
- 部分战斗 type 映射不全 → 先保证普通 viewfight，其余按失败日志补候选

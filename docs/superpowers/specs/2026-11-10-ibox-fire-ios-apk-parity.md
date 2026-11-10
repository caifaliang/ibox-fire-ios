# iOS 对齐今日 APK（0.2.74–0.2.76）

**日期：** 2026-11-10  
**目标：** `ibox-fire-ios` 同步 Android 今日改动（功能 + 象牙质感）

## 已同步

| Android | iOS |
|---------|-----|
| `batch_id` 优先顶层解析 + CreateOrder 必带 | `IbproClient.parseSaleList` / `createOrder` |
| 开火前预热补齐 batch、缺则中止；每条 CreateOrder 日志 | `IbPresaleEngine` |
| 捡漏 = 本机 `batchBuy` + 间隔滑条 | `IbBatchEngine` + `IbSnipePane` |
| 卖求购 / 查挂单 | `IbSellEngine` / `IbQueryEngine` + panes + tabs |
| 象牙色板 / 按压 0.93 / 触感加强 | `Tokens` / `PrimaryButtonStyle` / `Haptics` |
| 登录 + 我的页质感 | `SiteLoginScreen` / `ProfileScreen` |

## 版本

- `project.yml`：`MARKETING_VERSION 1.0.1` / `CURRENT_PROJECT_VERSION 5`

## 未整页移植（Android 壳层）

- Hub 瓷砖 + BottomBar + FeatureWorkbench AnimatedContent：iOS 仍为顶部分段 + 横向 Tab（信息架构不同）
- 后续若要对齐商业壳，另开壳层计划

## 构建

本机无 Mac 时走 GitHub Actions `ios-ipa.yml`；有 Mac：`xcodegen generate` + `xcodebuild`。

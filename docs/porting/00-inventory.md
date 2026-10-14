# DaLedou Android → iOS 盘点

**真源：** `F:\daledou`（`com.daledou.app` Kotlin）  
**目标：** `daledou-ios`（侧载自用）  
**日期：** 2026-10-14  
**方法：** 行为规格 + Swift 重写；**禁止** Java/Kotlin/.so 直搬；**不对拍饭点**一键。

---

## 0. App 类型

| 判定 | 证据 |
|------|------|
| **WebView 游戏壳** | `GameShellScreen` + phonepk / dld H5 |
| **+ 原生功能中心** | `FeatureCatalog` / `MainMenuScreen` / 四席 Hub |
| **+ Ruffle SWF 回放** | `RuffleReplayActivity` 独立 `:ruffle` 进程 |
| **+ 后台脚本引擎** | `task/*` Workers + `TaskRunner` |

不是 Unity/Cocos。游戏战斗页主要是腾讯 H5；群侠录像是本地 Flash→Ruffle。

---

## 1. Android 用户可见表面

| 表面 | 入口 | 关键文件 |
|------|------|----------|
| 启动 / 主 Activity | LAUNCHER | `MainActivity.kt` |
| 游戏壳 WebView | 登录后默认 | `ui/shell/GameShellScreen.kt` |
| 功能中心菜单 | 壳内菜单 | `ui/menu/MainMenuScreen.kt` + `FeatureCatalog` |
| 调度 / 我的 Hub | 底栏 | `ui/shell/HubScreens.kt` + `ShellCatalog` |
| 活跃代玩 | 菜单 huoyue | `ui/shell/HuoYueDaiWanScreen.kt` |
| 代玩记录 | daiwan_ui | `ui/feature/DaiWanRecordScreen.kt` |
| 账号切换 | account_switch | `ui/feature/AccountSwitchScreen.kt` |
| 各功能设置页 | FeatureRoute | `ui/feature/refpages/*` |
| 群侠录像 / 官方动画 | qunxia_luxiang | `RuffleReplayActivity` + flash assets |
| 登录捕获 | scheme / 默认浏览器 | `auth/BrowserCaptureActivity` + `LoginHelper` |
| 关于 / 会员 | about / note_settings | `AboutScreen` / `VipRedeemScreen` |
| 更新弹窗 | 启动检查 | `AppUpdateChecker` / WebView 升级 |

顶栏动作：`帮助` / `截图` / `查询`（`FeatureCatalog.topActions`）。

---

## 2. FeatureCatalog 全表（Android 真源）

### 后台任务

| id | 标签 | Android | iOS |
|----|------|---------|-----|
| hejiu | 喝酒 | Ready | **未接** |
| jiebiao | 劫镖 | Ready | **未接** |
| kuangdong | 矿洞 | Ready | **未接** |
| liangcao | 粮草掠夺 | Ready | **未接** |
| wending | 问鼎 | Ready | **未接** |
| fuchou_wending | 问鼎复仇 | Ready | **未接** |
| open_kd | 开矿洞设置 | Ready | **未接** |
| change_guard | 换守护神设置 | Ready | **未接** |
| paiqian | 任务派遣 | Ready | **未接** |
| menpai_shouye | 门派守夜 | Ready | **未接** |
| friend_mgmt | 好友管理 | Ready | **未接** |
| xkx | 侠客行 | Ready | **未接** |
| diy_auto_daiwan | 定时自定义代玩 | Ready | **未接** |
| diy_task | 定时自定义任务 | Ready | **未接** |

### 设置相关

| id | 标签 | Android | iOS |
|----|------|---------|-----|
| huoyue | 活跃代玩 | Ready | **未接** |
| daiwan | 代玩设置 | Ready | **未接** |
| lingjiang | 领奖报名 | Ready | **未接** |
| renwu | 任务设置 | Ready | **未接** |
| paomadeng | 跑马灯 | Ready | **未接** |
| more_settings | 更多设置 | Ready | **未接** |

### 更多

| id | 标签 | Android | iOS |
|----|------|---------|-----|
| chaqu | 武林查区 | Ready | **未接** |
| daiwan_ui | 代玩-记录 | Ready | **未接** |
| piliang_douyou | 批量斗友 | Ready | **未接** |
| doudou_mall | 斗豆红包商城 | Ready | **未接** |
| xianshi_qianggou | 限时抢购 | Ready | **未接** |
| longhuang | 龙凰论武 | Ready | **未接** |
| bagua | 八卦迷阵 | Ready | **未接** |
| xydb | 幸运夺宝 | Ready | **未接** |
| wulin_chiyao | 武林吃药 | Ready | **未接** |
| qiangdipan | 抢地盘 | Ready | **未接** |
| beibao | 背包查询 | Ready | **未接** |
| qunxia_luxiang | 群侠录像 | Ready | **部分**（官方动画 FAB） |
| bangpai_wakuang | 帮派挖矿 | Ready | **未接** |
| shuqian | 书签 | Ready | **未接** |
| account_switch | 账号切换 | Ready | **未接** |
| about | 关于大乐斗 | Partial | **未接** |
| scan_login | 扫码登陆 | Ready | **已接** |
| one_login | 一键登陆 | Ready | **已接**（iOS qrcode 路径） |
| logout | 退出登陆 | Ready | **已接** |
| exit_app | 退出大乐斗 | Ready | **未接**（可系统手势） |
| note_settings | 大乐斗会员 | Partial | **未接** |

### 代玩子类型（autoDaiWanTypes，移植代玩时必须覆盖）

一键活跃代玩、一键领奖、会武、祭坛、仙武修真、竞技场、华山论剑、深渊秘境、打满问鼎、遗迹征伐、门派任务、龙凰论武、道聚城、武器充能、报名电脑/手机武林、报名群侠、矿洞监听、批量斗友×3、历练、自动换装×5、劫镖。

---

## 3. iOS 已有能力（2026-10-14）

| 模块 | 路径 | 状态 |
|------|------|------|
| 壳 | `Sources/App/RootView.swift` | 顶栏 + 简菜单 + 状态条 |
| 游戏 WebView | `Sources/UI/GameWebView.swift` | 可用 |
| 会话 | `Sources/Session/*` | Cookie 注入/同步 |
| 一键/扫码/Cookie | `Sources/Auth/*` | 可用；同意后手动回；fd81 本地通知 |
| 官方动画 | `Sources/Fight/*` | Ruffle fullScreenCover |
| 功能中心 / 后台任务 | — | **无** |
| 多账号 | — | **无** |
| 会员 / 关于 / 更新 | — | **无** |

当前 iOS 菜单仅：一键、扫码、粘贴 Cookie、进首页、刷新、退出。

---

## 4. 交互 / 配置差异（移植时注意）

| 点 | Android | iOS |
|----|---------|-----|
| QQ 一键 | `wtlogin` + 常 `p=` + `daledouapp://` | **仅** `qrcode` + schemacallback；`p=` 禁止 |
| 回 App | 浏览器/scheme 较顺 | QQ 不回调 → 手动 ◀ + 通知 |
| JS 桥 | `@JavascriptInterface` 可同步 | `WKScriptMessageHandler` 异步 |
| 后台 | Foreground Service | BGTask / 本地通知；受限 |
| Ruffle | 独立进程 `:ruffle` | 同进程；开战拆掉游戏 WK（已做） |
| UA | 自定义手机 UA | 一键必须手机 UA |

已证伪清单见 `FALSIFIED.md`。

---

## 5. 不可移植 / 替代

- `.so` / AIR runtime → 已用 Ruffle 替代回放  
- 腾讯官方 SDK 二进制 → 自研 ptlogin  
- Android 默认浏览器劫持 → iOS 不可照搬  
- 上架分发官方资源 → **仅侧载自用**

---

## 6. 建议切片顺序（完整接入）

1. **壳导航** — FeatureCatalog 菜单 UI + 路由骨架（页面可先占位）  
2. **账号** — 多账号切换（依赖 SessionStore 扩展）  
3. **书签 / 背包 / 查区** — 偏查询、依赖少  
4. **群侠录像完整页** — 对齐 Android 入口（官方动画已有）  
5. **代玩 / 领奖 / 任务设置 UI** + Worker 逐项  
6. **战场监听类**（矿洞/劫镖/粮草/问鼎…）— 需后台策略  
7. **定时代玩 / 定时任务**  
8. **会员 / 关于 / 更新**（可后置）

每片：规格 → Swift → 真机对拍 CGI/Cookie → `MODULES.md` 勾选。

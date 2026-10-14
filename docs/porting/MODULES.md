# Port modules tracker

真源：`F:\daledou` · 目标：`daledou-ios` · 盘点：`00-inventory.md`

图例：`done` / `partial` / `todo` / `blocked` / `wont`

| # | 模块 | 状态 | Android 锚点 | iOS 锚点 | 备注 |
|---|------|------|--------------|----------|------|
| M0 | 盘点文档 | done | FeatureCatalog | docs/porting | 2026-10-14 |
| M1 | 游戏壳 WebView | done | GameShellScreen | GameWebView | Cookie + phonepk |
| M2 | 一键登录 | done | one_login | Auth/* | iOS qrcode；手动回；fd81 通知 |
| M3 | 扫码登录 | done | scan_login | openScanLogin | |
| M4 | Cookie 登录 | done | （高级） | CookiePasteSheet | |
| M5 | 官方动画 / Ruffle | partial | qunxia_luxiang | Fight/* FAB | 缺完整「群侠录像」页 |
| M6 | 壳顶栏 / 简菜单 | partial | — | RootView | 需扩成功能中心 |
| M7 | **功能中心菜单 + 路由骨架** | **done** | MainMenuScreen / FeatureRoute | Feature/* + RootView | fd82：三区目录 + 占位；已接一键/扫码/退出/动画 |
| M8 | 账号切换 | done | AccountSwitchScreen | AccountStore + AccountSwitchView | fd83：保存/切换/删除/粘贴 |
| M9 | 书签 | done | shuqian | BookmarkStore + BookmarkView | fd84：多行 URL → 壳内打开 |
| M10 | 背包查询 | partial | beibao | BeiBaoService + BeiBaoView | fd84：store 刮取 + 关键词；无出售 |
| M11 | 武林查区 | partial | chaqu | ChaQuView | fd84：设置落盘；扫区后台未接 |
| M12 | 代玩设置 + Workers | todo | daiwan / DaiWanWorkers | — | 含 autoDaiWanTypes |
| M13 | 活跃代玩 | todo | huoyue | — | |
| M14 | 领奖报名 | todo | lingjiang | — | |
| M15 | 任务设置 | todo | renwu | — | |
| M16 | 跑马灯 / 更多设置 | todo | paomadeng / more_settings | — | |
| M17 | 战场监听族 | todo | kuangdong…wending | — | 后台受限 |
| M18 | 开启矿洞 / 换守护 | todo | open_kd / change_guard | — | |
| M19 | 喝酒 / 派遣 / 守夜 / 侠客行 / 好友 | todo | hejiu…friend_mgmt | — | |
| M20 | 定时代玩 / 定时任务 | todo | diy_* | — | |
| M21 | 更多玩法页 | todo | piliang…bangpai_wakuang | — | 商城/抢购等 |
| M22 | 关于 / 会员 / 退出 App | todo | about / note_settings | — | |
| M23 | 应用内更新 | todo | AppUpdateChecker | — | 侧载策略另定 |
| M24 | JS 桥 / UA 对拍 | partial | WebView hooks | GameWebView | 缺口随 H5 需求补 |

## 下一切片（建议）

**M12 代玩设置 + Workers 骨架**（或先补 M11 扫区后台）。

M7–M9/M10/M11（设置页）已随 fd84 落地。

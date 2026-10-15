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
| M6 | 壳顶栏 / 简菜单 | partial | — | RootView | |
| M7 | 功能中心菜单 + 路由骨架 | done | MainMenuScreen | Feature/* | fd82 |
| M8 | 账号切换 | done | AccountSwitchScreen | AccountStore | fd83 |
| M9 | 书签 | done | shuqian | Bookmark* | fd84 |
| M10 | 背包查询 | partial | beibao | BeiBao* | fd84 |
| M11 | 武林查区 | partial | chaqu | ChaQuView | fd84 |
| M12 | 代玩设置 + Workers | partial | daiwan / DaiWanWorkers | Task/* + DaiWan* | fd85 |
| M13 | 活跃代玩 | partial | huoyue / HuoYueRunner | HuoYue* | fd86 |
| M14 | 领奖报名 | partial | lingjiang / LingJiangRunner | LingJiang* + Resources/lingjiang | fd87：keymap 串行；QQ 列表跳过 |
| M15 | 任务设置 | todo | renwu | — | |
| M16 | 跑马灯 / 更多设置 | todo | paomadeng / more_settings | — | |
| M17 | 战场监听族 | todo | kuangdong…wending | — | 后台受限 |
| M18 | 开启矿洞 / 换守护 | todo | open_kd / change_guard | — | |
| M19 | 喝酒 / 派遣 / 守夜 / 侠客行 / 好友 | todo | hejiu…friend_mgmt | — | |
| M20 | 定时代玩 / 定时任务 | todo | diy_* | — | |
| M21 | 更多玩法页 | todo | piliang…bangpai_wakuang | — | |
| M22 | 关于 / 会员 / 退出 App | todo | about / note_settings | — | |
| M23 | 应用内更新 | todo | AppUpdateChecker | — | |
| M24 | JS 桥 / UA 对拍 | partial | WebView hooks | GameWebView | |

## 下一切片（建议）

**M15 任务设置** 或 **乐斗目标池**（补 M13）。

fd87：领奖报名 keymap + 一键领奖已落地。

# M13 活跃代玩 · 行为规格

## Feature: 活跃代玩（huoyue）

### Goal
设置页勾选官方活跃 20 条 + 常用大厅/礼包项；「一键活跃」串行编排并刷日志。

### States
- idle / running（与 DaiWanRunner 互不强制排队，用户勿同时点）
- `huoyue.<key>` bool（FeatureToggleStore）

### Triggers
- 功能中心 → 活跃代玩
- 代玩 L4「一键活跃代玩」→ 转交本 Runner

### Outputs（本切片已接）
- 同门切磋、武林报名、历程分享、镶嵌魂珠
- 大厅：神魔转盘/娃娃机/猜单双/深渊秘宝/斗境探秘/镖车（各 1～2 次 CGI）
- 打铁、护送押镖（cargo op=7）
- 活跃礼包领取（liveness_getgiftbag）
- 其它勾选项：记 stub / 转交 DaiWanRunner 子类型名

### Explicit non-goals
- 乐斗10/20 目标池战斗循环（需解析 friendlist，下一切片）
- 完整 SettingPageDefs.huoYue 全量细项 UI
- 后台 KeepAlive 轮询

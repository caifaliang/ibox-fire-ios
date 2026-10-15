# M14 领奖报名 · 行为规格

## Feature: 领奖报名（lingjiang）

### Goal
勾选领奖/报名项 →「一键领奖」按 catalog 顺序串行打腾讯 CGI。

### Data
- Bundle：`lingjiang_keymap.json`（~224 协议）+ `lingjiang_cb_to_key.json`
- 开关：`lingjiang.<cb_*>`（FeatureToggleStore）
- 默认勾选：日礼核心 6 项（login / 传功符 / 达人 / 天书 / 斗币 / 分享）

### Runner
- 仅执行有 checkbox 且已勾选的协议
- type 18/25/26/43 看时段；其它一键模式不限时段
- 主路径：urlList / url（含「随机」）/ formatUrl「格式化」两段
- 动态项（飞升/巅峰/结拜/盟主报名）本切片接线；QQ 列表类记 skip

### Explicit non-goals
- SettingPageDefs 全量分组 UI（先用可搜索 checklist）
- 游记完整战斗循环、商会复杂兑换

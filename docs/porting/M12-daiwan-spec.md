# M12 代玩设置 + Workers · 行为规格

## Feature: 代玩（daiwan / daiwan_ui）

### Goal (user-visible)
- **代玩界面 (daiwan_ui)**：开关「聚合代玩」+ L4 子类型全表开关；「立即执行」跑已开子项并刷日志。
- **代玩设置 (daiwan)**：本切片先用同一套 L4 子类型开关落盘；完整 SettingPageDefs.daiWan 细项后续切片。

### States
- idle / running（单次 run 互斥）
- 各 `daiwan_type_{i}` bool；hub `daiwan_ui` bool

### Triggers
- 功能中心 → 代玩 / 代玩界面
- 「立即执行代玩」→ 顺序跑已启用子类型

### Outputs
- TaskLog 行；部分子类型发 phonepk/petpk（本切片：手机武林 / 群侠报名已接；其余 stub 日志）

### Timing
- 子类型间间隔 ~400ms；无后台轮询（iOS BG 受限，后续再接）

### Edges
- 未登录 → 提示先登录
- 非腾讯域拒绝（LedouCGI）

### Explicit non-goals
- 不搬 HuoYueCombat / MoreExtraActions 全量战斗循环
- 不定时 diy_auto_daiwan（M20）
- 不照搬 ForegroundService

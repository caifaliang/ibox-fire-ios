# 网站 iBox 多账号槽（本地 5 槽）设计

**日期：** 2026-11-11  
**产品：** ibox-analytics 网站（科技页 / Snipe）  
**方案：** A · 浏览器 localStorage 5 槽  
**状态：** 已批准；实现计划见 `docs/superpowers/plans/2026-11-11-ibox-web-account-slots.md`  

---

## 1. 目标

1. 最多 **5** 个 iBox 账号并存，科技页一键切换  
2. 短信登录落盘 `refreshToken` + **每槽独立 `deviceId`**，吃满官方 refresh 寿命（产品口径「180 天不掉」）  
3. 现有 `snipeToken` / `snipeRefreshToken` / deviceId 等键继续作为**活跃槽镜像**，旧调用点少改  

### 非目标

- 服务端存票、跨设备云同步  
- IPA / APK 槽位对齐（后续单独做）  
- 切换账号时自动停止正在跑的任务（仅提示）  
- 改官方 refresh 接口或短信网关协议  

---

## 2. 已锁定决策

| 项 | 选择 |
|----|------|
| 范围 | 仅网站 |
| 存储 | 本地 5 槽（对齐同行 UX） |
| 活跃态 | 镜像现有 `snipe*` 键，不强迫全站改读槽 API |
| 顶号 | 硬踢只清**当前槽** |
| 纯 JWT 粘贴 | 允许；槽上标「易掉」 |

---

## 3. 数据模型

### 3.1 Keys

| Key | 类型 | 含义 |
|-----|------|------|
| `ibox_account_slots_v1` | JSON array length 5 | 账号槽 |
| `ibox_account_active_v1` | string `"0"`…`"4"` | 当前槽 index |

### 3.2 槽对象

```ts
{
  token: string          // access JWT，可空表示空槽
  refreshToken: string   // 可空；空则 UI 标「易掉」
  deviceId: string       // 该槽发码/登录/请求必须同源
  uid: string | number
  mobile: string
  nickname: string
  avatarUrl?: string
  updatedAt: number      // ms
}
```

空槽：`{}` 或 `token` 为空。

### 3.3 活跃槽镜像（写出）

切换 / 登录 / 续期成功后同步：

| 镜像键 | 来源字段 |
|--------|----------|
| `snipeToken` (+ cookie / sessionStorage 同现网) | `token` |
| `snipeRefreshToken` | `refreshToken` |
| `snipeUid` | `uid` |
| `snipePhone` | `mobile` |
| login deviceId（现 `iboxLogin` 所用键） | `deviceId` |

读侧：业务代码可继续 `getIboxToken()` / `getRefreshToken()` / `getLoginDeviceId()`；槽模块负责保证镜像正确。

---

## 4. 模块职责

新建（建议）`frontend/src/lib/iboxAccountSlots.js`：

| API | 行为 |
|-----|------|
| `loadSlots()` / `getActiveIndex()` | 读存储；缺省补齐 5 槽 |
| `migrateLegacyIfNeeded()` | 槽全空且有 `snipeToken` → 导入槽 0 并激活 |
| `setSlot(i, partial)` | 规范化后写入；可顺带更新镜像若 `i === active` |
| `activateSlot(i)` | 校验有票 → 写 active + 全量镜像 + `ibox-auth-changed` |
| `clearSlot(i)` | 清槽；若清的是当前 → 切下一有票槽或 `clearIboxSession` |
| `clearAllSlots()` | 清五槽 + `clearIboxSession` |
| `upsertLoginToSlot(i, session)` | 短信/粘贴登录结果写入目标槽并 activate |
| `syncActiveFromMirrorRefresh(token, refresh, deviceId?)` | `ensureFreshIboxToken` 成功后回写当前槽 |

改造：

- `iboxLogin.js`：`ensureFreshIboxToken` 成功路径调用槽回写  
- `iboxSession.js`：`kickIboxSession` / `clearIboxSession` 改为走「清当前槽」语义（或 kick 内调 `clearSlot(active)`）  
- `Snipe.vue` 登录区：槽条 UI + 登录写入目标槽  

---

## 5. UX

位置：科技页登录卡片上方（或卡片内顶部）。

- **槽条：** 最多 5 格；空槽虚线「+」；有票显示昵称/手机尾号；当前槽高亮  
- **点空槽：** 设 `loginTargetSlot = i`，展示短信/粘贴表单  
- **点有票非当前槽：** `activateSlot(i)`；若有任务在跑 → toast 提示「任务仍用旧号，请先停再切」但不拦截切换  
- **退出当前 / 退出该槽：** `clearSlot`  
- **退出全部：** `clearAllSlots`  
- **易掉：** `refreshToken` 为空时小标签「易掉」+ 短说明  

---

## 6. 登录与 180 天

1. **短信：** 发码前为**目标槽**确保 `deviceId`（已有则复用，空则新建 `dev_…`）；发码与 `/snipe/login` 必须带同一 `device_id`；成功后 `upsertLoginToSlot`（含 `refresh_token`）  
2. **粘贴：** 解析 access / refresh / deviceId；缺 refresh 允许写入但标「易掉」  
3. **续期：** 现有 `/snipe/token-refresh` + `ensureFreshIboxToken`；成功后回写当前槽镜像与槽数组  
4. **文案：** 推荐短信登录；勿与官方 App 共票（共票会被 App 换票踢掉）  

---

## 7. 顶号 / 迁移 / 边界

| 场景 | 行为 |
|------|------|
| 首次有旧单票 | 导入槽 0，`active=0` |
| 硬踢（别处登录 / `auth_expired`） | 只清当前槽；有其它有票槽则 activate 之并 toast；否则回登录态 |
| 切换时任务仍在跑 | 不自动 stop；toast 提示 |
| 清缓存 / 换浏览器 | 槽丢失（与同行一致；不在本期修） |

---

## 8. 验收

1. 短信登录两个号进不同槽，切换后查挂单/持仓身份跟随当前槽  
2. 续期后当前槽 `token`/`refreshToken` 更新，刷新页面仍为该号  
3. 硬踢当前槽后，另一槽仍在且可一切换继续用  
4. 旧用户仅有 `snipeToken` 时打开科技页自动进槽 0，功能不回退  
5. 无 refresh 粘贴显示「易掉」  

---

## 9. 自检

- [x] 无 TBD / 占位未决项  
- [x] 与「仅网站 / 方案 A」无矛盾  
- [x] 范围边界写清（不做云同步、不做原生）  
- [x] 镜像策略避免全站大爆炸式改造  

---

## 批准

- 2026-11-11：用户选范围「先实现网站」、方案 **A**，设计 / Spec 确认后进入实现计划  


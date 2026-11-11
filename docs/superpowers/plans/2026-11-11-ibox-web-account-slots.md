# 网站 iBox 多账号槽 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把已写好的本地 5 槽核心接到科技页可见 UI，并让单测与 API 对齐、可验收「切换 / 加号 / 易掉 / 硬踢只清当前槽」。

**Architecture:** `iboxAccountSlots.js` 管槽与镜像；`iboxSession.js` / `iboxLogin.js` 已接踢号与续期回写。缺口主要在 `Snipe.vue` 槽条 UI +「已登录时加号」流程，以及单测与实现 API 不一致。

**Tech Stack:** Vue 3、现有 `frontend/src/lib/*`、Node 原生 `assert` 单测（`node frontend/tests/*.mjs`）

**Spec:** `docs/superpowers/specs/2026-11-11-ibox-web-account-slots-design.md`

---

## 已完成（勿重做）

| 文件 | 状态 |
|------|------|
| `frontend/src/lib/iboxAccountSlots.js` | 槽 CRUD、迁移、镜像、deviceId、fragile、续期回写 API |
| `frontend/src/lib/iboxLogin.js` | `ensureFreshIboxToken` 成功后 `syncActiveFromMirrorRefresh` |
| `frontend/src/utils/iboxSession.js` | `clearIboxSession`=清当前槽；`kick` 有其它槽则切换 |
| `Snipe.vue` script | `upsertLoginToSlot` / `activateSlot` / `ensureSlotDeviceId` / logout helpers |

## File map（剩余）

| 文件 | 职责 |
|------|------|
| `frontend/src/lib/iboxAccountSlots.js` | 补测试注入 `setAccountSlotsStorage`；导出测试友好别名；`loadSlots` 可选自动 migrate |
| `frontend/tests/iboxAccountSlots.test.mjs` | 与真实 API 对齐 |
| `frontend/src/views/Snipe.vue` | 槽条 UI + 加号登录面板 + 退出当前/全部 |
| Spec 状态行 | 标为已批准并进入实现 |

---

### Task 1: 单测可注入 storage + API 对齐

**Files:**
- Modify: `frontend/src/lib/iboxAccountSlots.js`
- Modify: `frontend/tests/iboxAccountSlots.test.mjs`

- [x] **Step 1: 在 `iboxAccountSlots.js` 增加可注入 storage（默认真实 localStorage/sessionStorage）**

在文件顶部（import 之后）加入：

```js
let _store = null
let _session = null

function ls() {
  return _store || (typeof localStorage !== 'undefined' ? localStorage : null)
}
function ss() {
  return _session || (typeof sessionStorage !== 'undefined' ? sessionStorage : null)
}

/** @param {{ getItem,setItem,removeItem }|null} local @param {typeof local|null} [session] */
export function setAccountSlotsStorage(local, session) {
  _store = local
  _session = session != null ? session : local
  _slotsCache = null
  _activeCache = null
}
```

把所有 `localStorage` / `sessionStorage` 读写改为 `ls()` / `ss()`（含 `readJson`/`writeJson`/`getActiveIndex`/`setActiveIndex`/`writeMirror`/`migrateLegacyIfNeeded`/`ensureSlotDeviceId`）。`writeMirror` 里 `document.cookie` 在无 `document` 时 `try/catch` 跳过（测试环境）。

- [x] **Step 2: 导出测试别名（不改业务名）**

```js
export const saveLoginToSlot = upsertLoginToSlot
export function listSlots() {
  migrateLegacyIfNeeded()
  return loadSlots().map((s, index) => ({
    ...normalizeSlot(s),
    index,
    loggedIn: slotHasToken(s),
    fragile: slotIsFragile(s),
  }))
}
export function patchActiveSlot(partial) {
  const i = getActiveIndex()
  const cur = normalizeSlot(loadSlots()[i])
  return setSlot(i, { ...cur, ...partial, updatedAt: Date.now() })
}
```

并让 `clearSlot` 返回值带上测试期望字段：

```js
// clearSlot 末尾各 return 增加：
// { ok, active, activeIndex: active, loggedIn, promoted: next>=0 或 false }
```

- [x] **Step 3: 改写 `iboxAccountSlots.test.mjs` 以匹配上述 API**

完整测试文件：

```js
import assert from 'node:assert/strict'
import {
  SLOT_COUNT,
  setAccountSlotsStorage,
  loadSlots,
  saveLoginToSlot,
  activateSlot,
  clearSlot,
  clearAllSlots,
  listSlots,
  firstEmptySlotIndex,
  ensureSlotDeviceId,
  patchActiveSlot,
  getActiveIndex,
  migrateLegacyIfNeeded,
  SLOTS_KEY,
  ACTIVE_KEY,
  _resetSlotsCacheForTests,
} from '../src/lib/iboxAccountSlots.js'

function memStorage() {
  const m = new Map()
  return {
    getItem: (k) => (m.has(k) ? m.get(k) : null),
    setItem: (k, v) => m.set(k, String(v)),
    removeItem: (k) => m.delete(k),
  }
}

function reset() {
  const s = memStorage()
  setAccountSlotsStorage(s)
  _resetSlotsCacheForTests()
  return s
}

{
  const s = reset()
  assert.equal(loadSlots().length, SLOT_COUNT)
  assert.equal(firstEmptySlotIndex(), 0)

  s.setItem('snipeToken', 'tok-legacy')
  s.setItem('snipeRefreshToken', 'rt-legacy')
  s.setItem('ibox.login.deviceId', 'dev_legacy0001')
  s.setItem('snipeUid', '1001')
  s.setItem('snipePhone', '13800000000')
  s.removeItem(SLOTS_KEY)
  s.removeItem(ACTIVE_KEY)
  _resetSlotsCacheForTests()
  migrateLegacyIfNeeded()
  assert.equal(loadSlots()[0].token, 'tok-legacy')
  assert.equal(getActiveIndex(), 0)
}

{
  reset()
  const did = ensureSlotDeviceId(1)
  assert.match(did, /^dev_/)
  assert.equal(ensureSlotDeviceId(1), did)

  saveLoginToSlot(1, {
    token: 'tok-a',
    refreshToken: 'rt-a',
    uid: '2002',
    mobile: '13900000000',
    deviceId: did,
  })
  assert.equal(getActiveIndex(), 1)

  saveLoginToSlot(2, {
    token: 'tok-b',
    refreshToken: 'rt-b',
    uid: '3003',
    mobile: '13700000000',
    deviceId: 'dev_bbbbbbbb',
  })
  assert.equal(getActiveIndex(), 2)

  assert.equal(activateSlot(1).ok, true)
  assert.equal(getActiveIndex(), 1)

  patchActiveSlot({ token: 'tok-a2', refreshToken: 'rt-a2' })
  assert.equal(listSlots()[1].token, 'tok-a2')

  const cleared = clearSlot(1)
  assert.equal(cleared.promoted, true)
  assert.equal(cleared.activeIndex, 2)
  assert.equal(cleared.loggedIn, true)

  clearAllSlots()
  assert.equal(listSlots().every((x) => !x.loggedIn), true)
}

{
  reset()
  saveLoginToSlot(0, { token: 'only', refreshToken: '', uid: '1', deviceId: 'dev_onlyonly' })
  assert.equal(listSlots()[0].fragile, true)
  const r = clearSlot(0)
  assert.equal(r.loggedIn, false)
  assert.equal(r.promoted, false)
}

console.log('iboxAccountSlots.test.mjs: ok')
```

- [x] **Step 4: 跑测**

Run: `node frontend/tests/iboxAccountSlots.test.mjs`  
Expected: 打印 `iboxAccountSlots.test.mjs: ok`，exit 0

- [ ] **Step 5: Commit（仅当用户要求提交时执行）**

```bash
git add frontend/src/lib/iboxAccountSlots.js frontend/tests/iboxAccountSlots.test.mjs
git commit -m "test: align ibox account slots unit tests with injectable storage"
```

---

### Task 2: 科技页槽条 UI + 已登录加号

**Files:**
- Modify: `frontend/src/views/Snipe.vue`

- [x] **Step 1: 增加「加号登录」状态**

在 script（`loginTargetSlot` 旁）加入：

```js
/** 已登录时点空槽：临时展开登录表单写该槽，不踢其它槽 */
const addingAccount = ref(false)

function beginAddAccount(index) {
  loginTargetSlot.value = index
  ensureSlotDeviceId(index)
  phoneInput.value = ''
  codeInput.value = ''
  tokenInput.value = ''
  smsSent.value = false
  loginErr.value = ''
  showAdvanced.value = false
  addingAccount.value = true
}

function cancelAddAccount() {
  addingAccount.value = false
  loginTargetSlot.value = getActiveIndex()
  loginErr.value = ''
}
```

改 `onSelectAccountSlot`：空槽时调用 `beginAddAccount(index)`（无论当前是否 loggedIn）。

改 `doLogin` / `tokenLogin` 成功分支末尾：`addingAccount.value = false`。

- [x] **Step 2: 抽出槽条模板片段，插在登录区与主内容头**

在 `<!-- ═══ iBox Login -->` 之前（`vipPreview` 条之后）插入始终可见的槽条（VIP 且非 swapOnly）：

```html
    <!-- 账号槽条 -->
    <div v-if="!vipPreview && !swapOnlyMode" class="mb-4">
      <div class="mb-2 flex items-center justify-between gap-2">
        <span class="text-xs font-semibold text-slate-600">iBox 账号（最多 {{ SLOT_COUNT }}）</span>
        <span class="text-[11px] text-slate-400">短信登录可长期续期 · 勿与官方 App 共票</span>
      </div>
      <div class="grid grid-cols-5 gap-1.5">
        <button
          v-for="s in accountSlots"
          :key="s.index"
          type="button"
          @click="onSelectAccountSlot(s.index)"
          class="relative rounded-xl px-1.5 py-2 text-center text-[11px] transition-colors"
          :class="s.active && s.occupied
            ? 'bg-zinc-900 text-white shadow-sm'
            : s.occupied
              ? 'bg-white text-slate-800 ring-1 ring-black/[0.06] hover:bg-slate-50'
              : loginTargetSlot === s.index && (addingAccount || !loggedIn)
                ? 'border border-dashed border-blue-400 bg-blue-50 text-blue-700'
                : 'border border-dashed border-slate-200 bg-slate-50 text-slate-400 hover:border-slate-300'"
        >
          <div class="truncate font-medium">{{ s.occupied ? s.label : ('+' + (s.index + 1)) }}</div>
          <div v-if="s.fragile" class="mt-0.5 text-[9px] font-semibold text-amber-500">易掉</div>
          <div v-else-if="s.active && s.occupied" class="mt-0.5 text-[9px] opacity-80">当前</div>
        </button>
      </div>
      <div v-if="loggedIn" class="mt-2 flex flex-wrap gap-2">
        <button type="button" @click="doLogout"
          class="rounded-full border border-slate-200 px-2.5 py-1 text-[11px] text-slate-600 hover:border-red-300 hover:text-red-600">退出当前</button>
        <button type="button" @click="doLogoutAll"
          class="rounded-full border border-slate-200 px-2.5 py-1 text-[11px] text-slate-600 hover:border-red-300 hover:text-red-600">退出全部</button>
      </div>
    </div>
```

把登录表单的 `v-if` 从：

```html
<div v-if="!vipPreview && !loggedIn && !swapOnlyMode" ...>
```

改为：

```html
<div v-if="!vipPreview && (!loggedIn || addingAccount) && !swapOnlyMode" class="space-y-5 pt-4">
```

并在标题下加：

```html
      <div v-if="addingAccount" class="flex items-center justify-between rounded-xl bg-blue-50 px-3 py-2 text-[12px] text-blue-800">
        <span>正在登录到槽 {{ loginTargetSlot + 1 }}（其它账号保留）</span>
        <button type="button" class="font-semibold" @click="cancelAddAccount">取消</button>
      </div>
```

主内容区 `v-else` 改为在 `loggedIn || vipPreview || swapOnlyMode` 时显示（避免加号时整页被登录表单替换业务区——若加号时希望仍看到主内容，用「登录卡片叠在槽条下、主内容仍显示」）：

推荐结构：

```html
    <!-- 槽条：见上 -->

    <!-- 登录卡片：!loggedIn || addingAccount -->
    <div v-if="!vipPreview && (!loggedIn || addingAccount) && !swapOnlyMode" class="space-y-5 ...">...</div>

    <!-- 主内容：loggedIn || vipPreview || swapOnly -->
    <div v-if="loggedIn || vipPreview || swapOnlyMode">...</div>
```

（把原来的 `v-else` 主内容改成独立 `v-if`，这样 `addingAccount` 时槽条+登录表单+主内容可同屏，或按产品偏好隐藏主内容。**默认：加号时隐藏主内容**，实现更简单：）

```html
<div v-if="loggedIn && !addingAccount || vipPreview || (swapOnlyMode && !addingAccount)">
```

- [x] **Step 3: `onMounted` / `ibox-auth-changed` 已调 `applyActiveIboxSession` 则确认会 `refreshAccountSlots`；硬踢切换后 toast 读 `consumeIboxKickMsg`**

在现有 `onMounted` / `ibox-auth-changed` handler 里若已有 `applyActiveIboxSession` 则无需改。补：

```js
const kickMsg = consumeIboxKickMsg()
if (kickMsg) store.showToast(kickMsg, 'warn', 4000)
```

（若文件已 import `consumeIboxKickMsg` 则直接用；否则从 `@/utils/iboxSession` 补 import。）

- [ ] **Step 4: 浏览器手测清单（本机）**

1. 清站 localStorage 相关键后短信登号 A → 槽 1 高亮  
2. 点空槽 2 → 出现「登录到槽 2」→ 短信登号 B → 可一切换  
3. 粘贴无 refresh 的 JWT → 槽显示「易掉」  
4. 退出当前：若有 B 则切到 B；退出全部：回登录  

- [ ] **Step 5: Commit（仅当用户要求）**

```bash
git add frontend/src/views/Snipe.vue
git commit -m "feat: show iBox account slot bar and add-account flow on Snipe"
```

---

### Task 3: Spec 收尾 + 验收记录

**Files:**
- Modify: `docs/superpowers/specs/2026-11-11-ibox-web-account-slots-design.md`

- [x] **Step 1: 更新状态**

```markdown
**状态：** 已批准；实现按 `docs/superpowers/plans/2026-11-11-ibox-web-account-slots.md`
```

批准段改为：用户 2026-11-11 确认 Spec 后进入计划。

- [x] **Step 2: 再跑单测**

Run: `node frontend/tests/iboxAccountSlots.test.mjs`  
Expected: ok

---

## Spec coverage 自检

| Spec 项 | Task |
|---------|------|
| 5 槽 + 镜像键 | 已完成 + Task 1 测 |
| 短信 deviceId / refresh | 已完成 |
| 续期回写 | 已完成 |
| 硬踢只清当前 | 已完成 |
| 槽条 UX / 一键切 | Task 2 |
| 已登录加号 | Task 2 |
| 易掉标签 | Task 2 |
| 旧票迁移 | 已完成 + Task 1 测 |
| 不做云同步/原生 | 仍遵守 |

## Placeholder 扫描

无 TBD；commit 步骤标注「仅当用户要求」。

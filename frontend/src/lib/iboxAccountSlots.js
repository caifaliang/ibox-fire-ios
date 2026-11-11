/**
 * iBox 网站本地账号槽（最多 5）。
 * 活跃槽镜像现有 snipeToken / snipeRefreshToken / deviceId 等键，旧逻辑少改。
 */
import { setLoginDeviceId, setRefreshToken, getLoginDeviceId, getRefreshToken } from './iboxLogin.js'
import { randomUuid } from './iboxClient.js'

export const SLOT_COUNT = 5
export const SLOTS_KEY = 'ibox_account_slots_v1'
export const ACTIVE_KEY = 'ibox_account_active_v1'
const DEVICE_KEY = 'ibox.login.deviceId'
const REFRESH_KEY = 'snipeRefreshToken'

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

function normalizeToken(token) {
  const t = String(token || '').trim()
  if (!t) return ''
  return t.startsWith('Bearer ') ? t.slice(7).trim() : t
}

function emptySlot() {
  return {
    token: '',
    refreshToken: '',
    deviceId: '',
    uid: '',
    mobile: '',
    nickname: '',
    avatarUrl: '',
    updatedAt: 0,
  }
}

export function normalizeSlot(value) {
  const src = value && typeof value === 'object' ? value : {}
  const token = normalizeToken(src.token)
  const deviceId = String(src.deviceId || src.device_id || '').trim()
  // 空槽仍可保留 deviceId（发码预绑定）
  if (!token) {
    return { ...emptySlot(), deviceId }
  }
  return {
    token,
    refreshToken: String(src.refreshToken || src.refresh_token || '').trim(),
    deviceId,
    uid: src.uid != null && src.uid !== '' ? String(src.uid) : '',
    mobile: String(src.mobile || src.phone || '').trim(),
    nickname: String(src.nickname || src.userName || '').trim(),
    avatarUrl: String(src.avatarUrl || src.avatar || '').trim(),
    updatedAt: Number(src.updatedAt) || Date.now(),
  }
}

function readJson(key, fallback) {
  try {
    const store = ls()
    if (!store) return fallback
    const raw = store.getItem(key)
    if (!raw) return fallback
    return JSON.parse(raw)
  } catch {
    return fallback
  }
}

function writeJson(key, value) {
  try {
    const store = ls()
    if (!store) return
    store.setItem(key, JSON.stringify(value))
  } catch {}
}

let _slotsCache = null
let _activeCache = null

export function loadSlots() {
  if (_slotsCache) return _slotsCache.map((s) => ({ ...s }))
  const saved = readJson(SLOTS_KEY, [])
  const slots = Array.from({ length: SLOT_COUNT }, (_, i) =>
    normalizeSlot(Array.isArray(saved) ? saved[i] : {})
  )
  _slotsCache = slots
  return slots.map((s) => ({ ...s }))
}

function persistSlots(slots) {
  const next = Array.from({ length: SLOT_COUNT }, (_, i) => normalizeSlot(slots[i]))
  _slotsCache = next
  writeJson(SLOTS_KEY, next)
  return next.map((s) => ({ ...s }))
}

export function getActiveIndex() {
  if (_activeCache != null) return _activeCache
  let n = 0
  try {
    const store = ls()
    n = store ? Math.floor(Number(store.getItem(ACTIVE_KEY))) : 0
  } catch {
    n = 0
  }
  _activeCache = Number.isFinite(n) ? Math.max(0, Math.min(SLOT_COUNT - 1, n)) : 0
  return _activeCache
}

export function setActiveIndex(index) {
  const i = Math.max(0, Math.min(SLOT_COUNT - 1, Math.floor(Number(index) || 0)))
  _activeCache = i
  try {
    const store = ls()
    if (store) store.setItem(ACTIVE_KEY, String(i))
  } catch {}
  return i
}

/** 测试/热更新用：清内存缓存 */
export function _resetSlotsCacheForTests() {
  _slotsCache = null
  _activeCache = null
}

export function slotHasToken(slot) {
  return !!normalizeToken(slot && slot.token)
}

export function slotIsFragile(slot) {
  const s = normalizeSlot(slot)
  return !!s.token && !s.refreshToken
}

export function firstEmptySlotIndex(slots = loadSlots()) {
  for (let i = 0; i < SLOT_COUNT; i++) {
    if (!slotHasToken(slots[i])) return i
  }
  return -1
}

export function nextOccupiedSlotIndex(fromIndex, slots = loadSlots()) {
  for (let step = 1; step <= SLOT_COUNT; step++) {
    const i = (fromIndex + step) % SLOT_COUNT
    if (slotHasToken(slots[i])) return i
  }
  return -1
}

function writeMirror(session) {
  const s = normalizeSlot(session)
  const tok = s.token
  const local = ls()
  const sess = ss()
  try {
    if (tok) {
      if (local) local.setItem('snipeToken', tok)
      if (sess) sess.setItem('snipeToken', tok)
      try {
        if (typeof document !== 'undefined') {
          document.cookie = 'snipeToken=' + tok + ';max-age=2592000;path=/;SameSite=Lax'
        }
      } catch {}
    } else {
      if (local) local.removeItem('snipeToken')
      if (sess) sess.removeItem('snipeToken')
      try {
        if (typeof document !== 'undefined') {
          document.cookie = 'snipeToken=;max-age=0;path=/;SameSite=Lax'
        }
      } catch {}
    }
    if (s.uid) {
      if (local) local.setItem('snipeUid', String(s.uid))
      if (sess) sess.setItem('snipeUid', String(s.uid))
    } else {
      if (local) local.removeItem('snipeUid')
      if (sess) sess.removeItem('snipeUid')
    }
    if (s.mobile) {
      if (local) local.setItem('snipePhone', s.mobile)
      if (sess) sess.setItem('snipePhone', s.mobile)
    } else {
      if (local) local.removeItem('snipePhone')
      if (sess) sess.removeItem('snipePhone')
    }
    if (s.refreshToken) {
      if (local) local.setItem(REFRESH_KEY, s.refreshToken)
      if (sess) sess.setItem(REFRESH_KEY, s.refreshToken)
    } else {
      if (local) local.removeItem(REFRESH_KEY)
      if (sess) sess.removeItem(REFRESH_KEY)
    }
    if (s.deviceId) {
      if (local) local.setItem(DEVICE_KEY, s.deviceId)
      if (sess) sess.setItem(DEVICE_KEY, s.deviceId)
    } else {
      if (local) local.removeItem(DEVICE_KEY)
      if (sess) sess.removeItem(DEVICE_KEY)
    }
  } catch {}
  setRefreshToken(s.refreshToken || '')
  if (s.deviceId) setLoginDeviceId(s.deviceId)
  else {
    try {
      if (local) local.removeItem(DEVICE_KEY)
      if (sess) sess.removeItem(DEVICE_KEY)
    } catch {}
  }
}

function emitAuthChanged(loggedIn, extra = {}) {
  try {
    window.dispatchEvent(
      new CustomEvent('ibox-auth-changed', { detail: { loggedIn: !!loggedIn, ...extra } })
    )
  } catch {}
}

/**
 * 旧单票 → 槽 0。有槽数据则不动。
 * @returns {{ migrated: boolean, active: number }}
 */
export function migrateLegacyIfNeeded() {
  const slots = loadSlots()
  if (slots.some(slotHasToken)) {
    return { migrated: false, active: getActiveIndex() }
  }
  let token = ''
  try {
    const local = ls()
    const sess = ss()
    token = normalizeToken(
      (local && local.getItem('snipeToken')) || (sess && sess.getItem('snipeToken')) || ''
    )
  } catch {}
  if (!token) return { migrated: false, active: getActiveIndex() }

  let uid = ''
  let mobile = ''
  let refreshToken = ''
  let deviceId = ''
  try {
    const local = ls()
    const sess = ss()
    uid = (local && local.getItem('snipeUid')) || (sess && sess.getItem('snipeUid')) || ''
    mobile = (local && local.getItem('snipePhone')) || (sess && sess.getItem('snipePhone')) || ''
    refreshToken =
      (local && local.getItem(REFRESH_KEY)) || (sess && sess.getItem(REFRESH_KEY)) || ''
    deviceId =
      (local && local.getItem(DEVICE_KEY)) || (sess && sess.getItem(DEVICE_KEY)) || ''
  } catch {}
  if (!refreshToken) {
    try {
      refreshToken = getRefreshToken()
    } catch {
      refreshToken = ''
    }
  }
  if (!deviceId || deviceId.length < 8) {
    try {
      deviceId = getLoginDeviceId()
    } catch {
      deviceId = ''
    }
  }
  const session = normalizeSlot({
    token,
    refreshToken,
    deviceId,
    uid,
    mobile,
    updatedAt: Date.now(),
  })
  const next = slots.slice()
  next[0] = session
  persistSlots(next)
  setActiveIndex(0)
  writeMirror(session)
  return { migrated: true, active: 0 }
}

export function getActiveSlot() {
  migrateLegacyIfNeeded()
  const slots = loadSlots()
  return normalizeSlot(slots[getActiveIndex()])
}

export function setSlot(index, value) {
  const i = Math.max(0, Math.min(SLOT_COUNT - 1, Math.floor(Number(index) || 0)))
  const slots = loadSlots()
  const session = normalizeSlot(value)
  slots[i] = session
  persistSlots(slots)
  if (i === getActiveIndex()) {
    writeMirror(session)
    emitAuthChanged(!!session.token, { slot: i })
  }
  return session
}

/**
 * 激活有票槽：写镜像 + 事件。
 * @returns {{ ok: boolean, slot?: object, message?: string }}
 */
export function activateSlot(index) {
  migrateLegacyIfNeeded()
  const i = Math.max(0, Math.min(SLOT_COUNT - 1, Math.floor(Number(index) || 0)))
  const slots = loadSlots()
  const session = normalizeSlot(slots[i])
  if (!session.token) return { ok: false, message: '该槽未登录' }
  setActiveIndex(i)
  writeMirror(session)
  emitAuthChanged(true, { slot: i, switched: true })
  return { ok: true, slot: session, index: i }
}

/**
 * 登录结果写入目标槽并激活。
 */
export function upsertLoginToSlot(index, session) {
  const i =
    index == null || index < 0
      ? Math.max(0, firstEmptySlotIndex())
      : Math.max(0, Math.min(SLOT_COUNT - 1, Math.floor(Number(index) || 0)))
  const normalized = normalizeSlot({ ...session, updatedAt: Date.now() })
  if (!normalized.token) return { ok: false, message: '缺少 token' }
  setSlot(i, normalized)
  return activateSlot(i)
}

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

/**
 * 清槽。若清的是当前槽：切下一有票槽，否则清空镜像。
 * @returns {{ ok: boolean, active: number, activeIndex: number, loggedIn: boolean, promoted: boolean }}
 */
export function clearSlot(index) {
  const i = Math.max(0, Math.min(SLOT_COUNT - 1, Math.floor(Number(index) || 0)))
  const slots = loadSlots()
  slots[i] = emptySlot()
  persistSlots(slots)
  const active = getActiveIndex()
  if (i !== active) {
    const loggedIn = slotHasToken(slots[active])
    return { ok: true, active, activeIndex: active, loggedIn, promoted: false }
  }
  const next = nextOccupiedSlotIndex(i, slots)
  if (next >= 0) {
    activateSlot(next)
    return { ok: true, active: next, activeIndex: next, loggedIn: true, promoted: true }
  }
  setActiveIndex(0)
  writeMirror(emptySlot())
  emitAuthChanged(false, { slotCleared: i })
  return { ok: true, active: 0, activeIndex: 0, loggedIn: false, promoted: false }
}

export function clearAllSlots() {
  persistSlots(Array.from({ length: SLOT_COUNT }, () => emptySlot()))
  setActiveIndex(0)
  writeMirror(emptySlot())
  emitAuthChanged(false, { clearedAll: true })
  return { ok: true, active: 0, loggedIn: false }
}

/** 续期成功后回写当前槽 + 镜像（镜像已由 ensureFresh 写过时仍同步槽数组） */
export function syncActiveFromMirrorRefresh(token, refreshToken, deviceId) {
  const i = getActiveIndex()
  const slots = loadSlots()
  const cur = normalizeSlot(slots[i])
  if (!cur.token && !normalizeToken(token)) return { ok: false }
  const next = normalizeSlot({
    ...cur,
    token: normalizeToken(token) || cur.token,
    refreshToken: String(refreshToken || cur.refreshToken || '').trim(),
    deviceId: String(deviceId || cur.deviceId || getLoginDeviceId() || '').trim(),
    updatedAt: Date.now(),
  })
  slots[i] = next
  persistSlots(slots)
  writeMirror(next)
  return { ok: true, index: i, slot: next }
}

/**
 * 为登录目标槽准备稳定 deviceId（发码前调用）。
 * 仅复用该槽已有 deviceId；空槽始终新 mint，不复用全局活跃账号的 id。
 * 只有目标是活跃槽时才镜像到 login helpers；非活跃空槽只写槽本身。
 */
export function ensureSlotDeviceId(index) {
  const i = Math.max(0, Math.min(SLOT_COUNT - 1, Math.floor(Number(index) || 0)))
  const slots = loadSlots()
  const cur = normalizeSlot(slots[i])
  if (cur.deviceId && cur.deviceId.length >= 8) {
    if (i === getActiveIndex()) setLoginDeviceId(cur.deviceId)
    return cur.deviceId
  }
  const did = 'dev_' + randomUuid().replace(/-/g, '')
  slots[i] = normalizeSlot({ ...cur, deviceId: did, token: cur.token || '' })
  persistSlots(slots)
  if (i === getActiveIndex()) setLoginDeviceId(did)
  return did
}

export function listSlotsForUi() {
  migrateLegacyIfNeeded()
  const active = getActiveIndex()
  return loadSlots().map((slot, index) => ({
    index,
    ...normalizeSlot(slot),
    active: index === active,
    occupied: slotHasToken(slot),
    fragile: slotIsFragile(slot),
    label: slotLabel(slot),
  }))
}

export function slotLabel(slot) {
  const s = normalizeSlot(slot)
  if (!s.token) return '空槽'
  if (s.nickname) return s.nickname
  if (s.mobile && s.mobile.length >= 4) return '尾号' + s.mobile.slice(-4)
  if (s.uid) return 'UID ' + s.uid
  return '已登录'
}

/** iBox (snipeToken) session helpers — 顶号/失效时踢回登录 */

import {
  clearSlot,
  clearAllSlots,
  getActiveIndex,
  migrateLegacyIfNeeded,
} from '@/lib/iboxAccountSlots.js'

const KICK_KEY = 'iboxKickMsg'

function readCookie(name) {
  if (typeof document === 'undefined') return ''
  try {
    const parts = document.cookie.split(';')
    for (const part of parts) {
      const i = part.indexOf('=')
      if (i < 0) continue
      const k = part.slice(0, i).trim()
      if (k !== name) continue
      return part.slice(i + 1).trim()
    }
  } catch (_) {}
  return ''
}

export function getIboxToken() {
  let t = localStorage.getItem('snipeToken') || sessionStorage.getItem('snipeToken') || ''
  if (!t) {
    t = readCookie('snipeToken')
    // cookie 有值时回写 localStorage，避免各页读源不一致
    if (t) {
      try { localStorage.setItem('snipeToken', t) } catch (_) {}
    }
  }
  return t
}

function clearTaskIds() {
  ;['snipeTaskId', 'sellTaskId', 'batchJobId'].forEach((k) => {
    try {
      localStorage.removeItem(k)
      sessionStorage.removeItem(k)
    } catch (_) {}
  })
}

/**
 * 退出当前 iBox 号：只清当前槽；若还有其它槽会自动切过去。
 * @returns {{ loggedIn: boolean, active: number }}
 */
export function clearIboxSession() {
  try {
    migrateLegacyIfNeeded()
  } catch (_) {}
  clearTaskIds()
  try {
    const r = clearSlot(getActiveIndex())
    return { loggedIn: !!r.loggedIn, active: r.active }
  } catch (_) {
    ;[
      'snipeToken',
      'snipeRefreshToken',
      'snipeUid',
      'snipePhone',
    ].forEach((k) => {
      localStorage.removeItem(k)
      sessionStorage.removeItem(k)
    })
    document.cookie = 'snipeToken=;max-age=0;path=/;SameSite=Lax'
    try {
      window.dispatchEvent(new CustomEvent('ibox-auth-changed', { detail: { loggedIn: false } }))
    } catch (_) {}
    return { loggedIn: false, active: 0 }
  }
}

/** 退出全部 iBox 槽 */
export function clearAllIboxSlots() {
  clearTaskIds()
  try {
    clearAllSlots()
  } catch (_) {
    clearIboxSession()
  }
  return { loggedIn: false, active: 0 }
}

/**
 * 软判定：票可能过期/无效（可续期或提示），不等于必须立刻踢下线。
 * 注意：机房代拉寄售等也会返回 code=401，浏览器里的票仍可能有效。
 */
export function isIboxAuthExpired(payload) {
  if (!payload || typeof payload !== 'object') return false
  if (payload.auth_expired) return true
  if (payload.code === 401 || payload.code === '401') return true
  const msg = String(payload.message || payload.msg || '')
  const low = msg.toLowerCase()
  return (
    low.includes('token expired') ||
    msg.includes('Token已过期') ||
    msg.includes('Token过期') ||
    msg.includes('过期或无效') ||
    msg.includes('别处登录') ||
    msg.includes('其他地方登录') ||
    /token.*(过期|无效|失效)/i.test(msg)
  )
}

/**
 * 硬踢判定：仅在服务端明确 auth_expired，或文案确认「别处登录」时清本地票。
 * 浏览类 /snipe/ibox-consign、trade-records 等裸 401 不得走这里。
 */
export function shouldKickIboxSession(payload) {
  if (!payload || typeof payload !== 'object') return false
  if (payload.auth_expired === true) return true
  const msg = String(payload.message || payload.msg || '')
  return msg.includes('别处登录') || msg.includes('其他地方登录')
}

export function kickIboxSession(reason) {
  const had = !!getIboxToken()
  const result = clearIboxSession()
  // 还有其它槽：已自动切换，不整页踢回登录
  if (result && result.loggedIn) {
    const msg = (reason || '当前账号失效') + '，已切换到其它已登录账号'
    try {
      sessionStorage.setItem(KICK_KEY, msg)
      window.dispatchEvent(
        new CustomEvent('ibox-auth-changed', {
          detail: { loggedIn: true, kickedSlot: true, active: result.active },
        })
      )
      window.dispatchEvent(new CustomEvent('ibox-auth-switched', { detail: { active: result.active, reason: msg } }))
    } catch (_) {}
    return
  }
  if (!had && !reason) return
  sessionStorage.setItem(KICK_KEY, reason || '账号在其他地方登录，请重新登录')
  try {
    window.dispatchEvent(new CustomEvent('ibox-auth-kicked'))
  } catch (_) {}
  const path = window.location.pathname || ''
  if (path === '/snipe' || path.startsWith('/snipe?') || path === '/') {
    return
  }
  if (
    path.startsWith('/ibox') ||
    path.startsWith('/snipe') ||
    path.startsWith('/event') ||
    path.startsWith('/detail') ||
    path.startsWith('/analysis')
  ) {
    window.location.assign('/snipe')
  }
}

export function consumeIboxKickMsg() {
  const m = sessionStorage.getItem(KICK_KEY) || ''
  if (m) sessionStorage.removeItem(KICK_KEY)
  return m
}

/** 若为鉴权失效则踢回登录，返回 true 表示已处理 */
export function handleIboxAuthError(data) {
  if (!shouldKickIboxSession(data)) return false
  // 仅在本地仍有 token（已登录态）时踢出，避免登录页验 token 失败误踢
  if (!getIboxToken() && !data?.auth_expired) return false
  kickIboxSession(data?.message || '账号在其他地方登录，请重新登录')
  return true
}

/**
 * iBox 登录（短信/验证码走服务端代发，Token 校验仍可本机探活）:
 * - 发短信：/snipe/send-sms-auto（极验+发信同机，带 device_id）
 * - 验证码登录：/snipe/login（同一 device_id）
 * - Token 登录：本机 JWT 校验 + 直连探活
 *
 * 2026-10：sail-api login/verify 强制 DEVICE-ID；短信与登录必须用同一 device-id，
 * 否则会返回「验证码已失效，或输入有误」。Token 已切 lumaid ES256，业务头仍兼容。
 */
import { encrypt, decrypt } from './ibox3.js'
import { createIboxClient, decodeUid, makeDeviceId, randomUuid } from './iboxClient.js'
import { classifyIboxAuthFailure } from './iboxAuthHealth.js'

const HOST = '/oh5-api/sail-api.ibox.art'
export const GEE_CAPTCHA_ID = '0d4b08eac1cbdcad36bbf607c5bf3e1b'
const DEVICE_KEY = 'ibox.login.deviceId'
const REFRESH_KEY = 'snipeRefreshToken'

function normalizeToken(token) {
  const t = String(token || '').trim()
  if (!t) return ''
  return t.startsWith('Bearer ') ? t.slice(7).trim() : t
}

/** 发短信 / 验证码登录共用的稳定 DEVICE-ID（对齐 App dev_… 形态） */
export function getLoginDeviceId() {
  try {
    const saved = sessionStorage.getItem(DEVICE_KEY) || localStorage.getItem(DEVICE_KEY) || ''
    if (saved && saved.length >= 8) return saved
  } catch {}
  const id = 'dev_' + randomUuid().replace(/-/g, '')
  try {
    sessionStorage.setItem(DEVICE_KEY, id)
    localStorage.setItem(DEVICE_KEY, id)
  } catch {}
  return id
}

export function setLoginDeviceId(deviceId) {
  const id = String(deviceId || '').trim()
  if (!id || id.length < 8) return ''
  try {
    sessionStorage.setItem(DEVICE_KEY, id)
    localStorage.setItem(DEVICE_KEY, id)
  } catch {}
  return id
}

export function getRefreshToken() {
  try {
    return localStorage.getItem(REFRESH_KEY) || sessionStorage.getItem(REFRESH_KEY) || ''
  } catch {
    return ''
  }
}

export function setRefreshToken(rt) {
  const v = String(rt || '').trim()
  try {
    if (v) {
      localStorage.setItem(REFRESH_KEY, v)
      sessionStorage.setItem(REFRESH_KEY, v)
    } else {
      localStorage.removeItem(REFRESH_KEY)
      sessionStorage.removeItem(REFRESH_KEY)
    }
  } catch {}
  return v
}

export function decodeJwtPayload(token) {
  try {
    let b64 = normalizeToken(token).split('.')[1] || ''
    b64 = b64.replace(/-/g, '+').replace(/_/g, '/')
    while (b64.length % 4) b64 += '='
    return JSON.parse(atob(b64))
  } catch {
    return null
  }
}

export function tokenExpiresAt(token) {
  const p = decodeJwtPayload(token)
  return p && p.exp ? Number(p.exp) * 1000 : 0
}

/** refresh 一次性：同页并发续期会互顶，单飞合并 */
let _refreshInflight = null

export function isIboxRefreshInflight() {
  return !!_refreshInflight
}

/**
 * access 快过期时用 refresh 换新票（经站点代发，避免 CORS）。
 * @param {import('axios').AxiosInstance} api
 * @param {{ slackMs?: number, force?: boolean }} [opts]
 */
export async function ensureFreshIboxToken(api, opts = {}) {
  const slackMs = opts.slackMs != null ? opts.slackMs : 30 * 60 * 1000
  const force = !!opts.force
  let access = ''
  try {
    access = localStorage.getItem('snipeToken') || sessionStorage.getItem('snipeToken') || ''
  } catch {}
  access = normalizeToken(access)
  if (!access) return { status: 'skip', reason: 'no_access' }
  const expAt = tokenExpiresAt(access)
  const left = expAt ? expAt - Date.now() : 0
  if (!force && expAt && left > slackMs) {
    return { status: 'ok', token: access, refreshed: false, left_ms: left }
  }
  const refresh = getRefreshToken()
  if (!refresh) {
    if (expAt && left <= 0) {
      return { status: 'error', auth_expired: true, message: 'Token已过期且无续期票，请重新登录或粘贴新Token' }
    }
    return { status: 'ok', token: access, refreshed: false, left_ms: left, warn: 'no_refresh' }
  }
  if (!api || typeof api.post !== 'function') {
    return { status: 'error', message: '缺少 api 实例' }
  }
  if (_refreshInflight) return _refreshInflight
  _refreshInflight = (async () => {
    try {
      const r = await api.post(
        '/snipe/token-refresh',
        { refresh_token: refresh, device_id: getLoginDeviceId() },
        { timeout: 20000 }
      )
      const data = r.data || {}
      if (data.status === 'ok' && data.token) {
        const tok = normalizeToken(data.token)
        try {
          localStorage.setItem('snipeToken', tok)
          sessionStorage.setItem('snipeToken', tok)
          document.cookie = 'snipeToken=' + tok + ';max-age=2592000;path=/;SameSite=Lax'
        } catch {}
        if (data.refresh_token) setRefreshToken(data.refresh_token)
        if (data.device_id) setLoginDeviceId(data.device_id)
        // 回写当前账号槽（动态 import 避免与 slots ↔ login 循环依赖）
        try {
          const { syncActiveFromMirrorRefresh } = await import('./iboxAccountSlots.js')
          syncActiveFromMirrorRefresh(tok, data.refresh_token || refresh, data.device_id || getLoginDeviceId())
        } catch {}
        try {
          window.dispatchEvent(new CustomEvent('ibox-auth-changed', { detail: { loggedIn: true, refreshed: true } }))
        } catch {}
        return {
          status: 'ok',
          token: tok,
          refreshed: true,
          refresh_token: data.refresh_token || refresh,
          left_ms: tokenExpiresAt(tok) - Date.now(),
        }
      }
      return {
        status: 'error',
        auth_expired: !!data.auth_expired,
        message: String(data.message || '续期失败').slice(0, 80),
      }
    } catch (e) {
      return {
        status: 'error',
        message: e.response?.data?.detail || e.response?.data?.message || e.message || '续期请求失败',
      }
    } finally {
      _refreshInflight = null
    }
  })()
  return _refreshInflight
}

async function parseMaybeEncrypted(text) {
  const raw = String(text || '').trim()
  if (!raw) return { code: -1, message: 'empty' }
  let data
  try {
    data = JSON.parse(raw)
  } catch {
    return { code: -1, message: raw.slice(0, 60) }
  }
  if (data && data.encryptKey && data.data != null) {
    try {
      data = JSON.parse(decrypt(raw))
    } catch (e) {
      return { code: -3, message: 'decrypt fail: ' + String(e?.message || e).slice(0, 40) }
    }
  }
  return data
}

function anonHeaders(withBody, deviceId) {
  const did = deviceId || getLoginDeviceId()
  const h = {
    'platform-type': '1',
    'device-id': did,
    'msg-id': randomUuid() + '_android',
    'app-version-number': '30013',
    'app-version': '3.0.13',
  }
  if (withBody) h['Content-Type'] = 'application/json;charset=UTF-8'
  return h
}

/**
 * 发短信：走站点 /snipe/send-sms-auto（极验+发信同机），固定 device_id。
 * 2026-10：浏览器直连 CORS 只放行大写 DEVICE-ID，且须与登录同 device，故改服务端代发。
 * @param {import('axios').AxiosInstance} api
 */
export async function sendSmsLocal(api, phone, preferredProxy = '') {
  const ph = String(phone || '').replace(/\s/g, '')
  if (!ph || ph.length < 11) return { status: 'error', message: '请输入手机号' }
  const deviceId = getLoginDeviceId()
  try {
    const r = await api.post(
      '/snipe/send-sms-auto',
      { phone: ph, proxy: preferredProxy || '', device_id: deviceId },
      { timeout: 120000 }
    )
    const data = r.data || {}
    if (data.status === 'ok') {
      const did = data.device_id || deviceId
      try {
        sessionStorage.setItem(DEVICE_KEY, did)
        localStorage.setItem(DEVICE_KEY, did)
      } catch {}
      return {
        status: 'ok',
        message: data.message || '验证码已发送',
        engine: 'server',
        device_id: did,
      }
    }
    return { status: 'error', message: String(data.message || '短信发送失败').slice(0, 80) }
  } catch (e) {
    return {
      status: 'error',
      message: e.response?.data?.detail || e.response?.data?.message || e.message || '短信请求失败',
    }
  }
}

/**
 * 验证码登录：走站点 /snipe/login，带上与发短信相同的 device_id。
 * @param {import('axios').AxiosInstance} api
 */
export async function loginSmsLocal(api, phone, code) {
  // 兼容旧调用 loginSmsLocal(phone, code)
  if (api && typeof api.post !== 'function' && phone != null) {
    code = phone
    phone = api
    api = null
  }
  const ph = String(phone || '').replace(/\s/g, '')
  const cd = String(code || '').trim()
  if (!ph || !cd) return { status: 'error', message: '请填写手机号和验证码' }
  const deviceId = getLoginDeviceId()
  if (!api) {
    return { status: 'error', message: '登录缺少 api 实例，请刷新页面重试' }
  }
  try {
    const r = await api.post(
      '/snipe/login',
      { phone: ph, code: cd, device_id: deviceId, direct: '1' },
      { timeout: 60000 }
    )
    const data = r.data || {}
    if (data.status === 'ok' && data.token) {
      const tok = normalizeToken(data.token)
      return {
        status: 'ok',
        token: tok,
        refresh_token: data.refresh_token || '',
        user_id: data.user_id || decodeUid(tok) || 0,
        username: data.username || '',
        engine: 'server',
        device_id: data.device_id || deviceId,
      }
    }
    const msg = String(data.message || '登录失败')
    if (/DEVICE-ID|device-id|缺少/i.test(msg)) {
      return { status: 'error', message: '登录缺 DEVICE-ID，请刷新后重新获取验证码' }
    }
    return { status: 'error', message: msg.slice(0, 80) }
  } catch (e) {
    return {
      status: 'error',
      message: e.response?.data?.detail || e.response?.data?.message || e.message || '登录请求失败',
    }
  }
}

/**
 * 科技页健康检查：先续期再验活。
 * 切后台回来 access 常已过期；若直接踢会清掉仍可用的 refresh。
 *
 * @param {import('axios').AxiosInstance} api
 * @param {string} token
 * @returns {Promise<{
 *   health: '' | 'ok' | 'expired' | 'blocked' | 'error',
 *   kick: boolean,
 *   message?: string,
 *   token?: string,
 * }>}
 */
export async function runIboxSessionHealthCheck(api, token) {
  let access = normalizeToken(token)
  if (!access) return { health: '', kick: false }

  const fresh = await ensureFreshIboxToken(api, { slackMs: 2 * 60 * 60 * 1000 })
  if (fresh.status === 'ok' && fresh.token) {
    access = normalizeToken(fresh.token)
  } else if (fresh.auth_expired && !getRefreshToken()) {
    return {
      health: 'expired',
      kick: true,
      message: fresh.message || '登录已失效，请重新登录',
      token: access,
    }
  }

  let probe = await verifyTokenLocal(access)
  let action = classifyIboxAuthFailure(probe, {
    hasRefresh: !!getRefreshToken(),
    refreshAttempted: !!fresh.refreshed,
  })

  if (action === 'retry_refresh') {
    const again = await ensureFreshIboxToken(api, { force: true })
    if (again.status === 'ok' && again.token) {
      access = normalizeToken(again.token)
      probe = await verifyTokenLocal(access)
      action = classifyIboxAuthFailure(probe, {
        hasRefresh: !!getRefreshToken(),
        refreshAttempted: true,
      })
    } else {
      return {
        health: 'expired',
        kick: true,
        message: again.message || probe.message || '登录已失效，请重新登录',
        token: access,
      }
    }
  }

  if (action === 'ok') {
    return { health: 'ok', kick: false, token: access }
  }
  if (action === 'kick') {
    return {
      health: 'expired',
      kick: true,
      message: probe.message || '登录已失效，请重新登录',
      token: access,
    }
  }

  const msg = String(probe?.message || '')
  if (msg.includes('IP') || msg.includes('403')) {
    return { health: 'blocked', kick: false, token: access }
  }
  return { health: 'error', kick: false, token: access }
}

/** Token 登录 — JWT 本地校验 + 本机直连探活 */
export async function verifyTokenLocal(token) {
  const t = normalizeToken(token)
  if (!t || t.split('.').length < 2) {
    return { status: 'error', message: 'Token格式无效' }
  }
  let uid = 0
  try {
    let b64 = t.split('.')[1]
    b64 = b64.replace(/-/g, '+').replace(/_/g, '/')
    while (b64.length % 4) b64 += '='
    const payload = JSON.parse(atob(b64))
    uid = payload.userId || payload.user_id || 0
    const exp = payload.exp || 0
    if (exp && exp * 1000 < Date.now()) {
      return {
        status: 'error',
        auth_expired: true,
        code: 401,
        message: 'Token已过期，请重新登录',
      }
    }
  } catch {
    return { status: 'error', message: 'Token格式无效' }
  }

  // 探活勿打日活；爬仓/行情并发时 presence 会放大误伤
  const client = createIboxClient(t, { deviceIdMode: 'stable', touchPresence: false })
  const data = await client.get(
    '/personal-center-service/users/digital-collection-groups?pageNo=1&pageSize=1'
  )
  const code = data?.code
  const probeMsg = String(data?.message || '')
  // 裸 HTTP/业务 401：同域反代/WAF/机房出口常见误伤，绝不能直接当成「顶号」清票
  if (code === 401) {
    if (probeMsg.includes('别处登录') || probeMsg.includes('其他地方登录')) {
      return {
        status: 'error',
        auth_expired: true,
        code: 401,
        message: '账号在其他地方登录，请重新登录',
      }
    }
    return {
      status: 'error',
      code: 401,
      message: probeMsg.includes('HTTP')
        ? '探活 401（代理/网络），票未必失效'
        : (probeMsg || '探活 401（代理/网络），票未必失效'),
    }
  }
  if (code === 403) {
    return { status: 'error', message: 'HTTP 403（本机 IP 可能被风控）' }
  }
  if (code != null && code !== 0 && code !== -1) {
    // 部分账号空仓也是 code=0；非 0 仍可能 token 有效，宽松放行 JWT uid
    if (code === -3) {
      return { status: 'error', message: String(data?.message || '解密失败') }
    }
  }
  if (code === -1) {
    // 网络失败：JWT 未过期则仍可用（与宽松策略）
    if (uid) {
      return {
        status: 'ok',
        user_id: uid,
        message: 'Token本地校验通过(探活网络波动)',
        engine: 'browser-local',
        soft: true,
      }
    }
    return { status: 'error', message: String(data?.message || '网络错误') }
  }
  return {
    status: 'ok',
    user_id: uid || client.uid || 0,
    message: 'Token有效(本机直连)',
    engine: 'browser-local',
    device_id: makeDeviceId(t),
  }
}

/** 上报日活和持仓快照。token 只在当次请求使用，服务端不落库。 */
let _presenceAt = 0
export function reportIboxPresence(api, token, health, opts = {}) {
  const t = normalizeToken(token)
  if (!t || !api) return
  try {
    if (!localStorage.getItem('token')) return
  } catch {
    return
  }
  const force = !!(opts && opts.force)
  const now = Date.now()
  if (!force && now - _presenceAt < 20000) return
  _presenceAt = now
  ;(async () => {
    let portfolio = null
    // 本机直拉持仓再上报，避免机房代拉假空仓
    try {
      const { fetchPortfolio } = await import('@/lib/iboxBrowse')
      const pf = await fetchPortfolio(t)
      if (pf && pf.status === 'ok') {
        portfolio = {
          status: 'ok',
          totalHoldings: pf.totalHoldings || 0,
          totalKinds: pf.totalKinds || 0,
          items: (pf.items || []).slice(0, 80).map((it) => ({
            name: String(it.name || '').slice(0, 80),
            holdNum: Number(it.holdNum || 0),
          })),
        }
      }
    } catch {
      /* 本机拉仓失败仍上报心跳，服务端可兜底 */
    }
    const body = { token: t, health: health || '' }
    if (portfolio) body.portfolio = portfolio
    await api.post('/snipe/presence', body, { timeout: 90000 })
  })().catch(() => {
    _presenceAt = 0
  })
}

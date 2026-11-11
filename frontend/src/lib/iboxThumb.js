/**
 * iBox / Aliyun OSS cover thumbs for list UIs (market, holdings, …).
 * Detail pages should keep the original URL.
 */

const OSS_HOST_RE = /ibox\.art|aliyuncs\.com|iboxcdn/i

/**
 * @param {string} url
 * @param {{ w?: number, h?: number }} [opts]
 * @returns {string}
 */
export function thumbUrl(url, opts = {}) {
  const u = String(url || '').trim()
  if (!u) return ''
  if (/[?&]x-oss-process=/.test(u)) return u
  if (!OSS_HOST_RE.test(u)) return u
  const w = Math.max(16, Math.min(512, Number(opts.w) || 88))
  const h = Math.max(16, Math.min(512, Number(opts.h) || w))
  const process = `x-oss-process=image/resize,m_fill,w_${w},h_${h},limit_0`
  return u + (u.includes('?') ? '&' : '?') + process
}

import assert from 'node:assert/strict'
import { thumbUrl } from '../src/lib/iboxThumb.js'

assert.equal(thumbUrl(''), '')
assert.equal(thumbUrl(null), '')
assert.equal(thumbUrl('https://cdn.example.com/a.png'), 'https://cdn.example.com/a.png')

{
  const u = 'https://file.ibox.art/cover.png'
  const t = thumbUrl(u)
  assert.ok(t.includes('x-oss-process=image/resize,m_fill,w_88,h_88,limit_0'))
  assert.ok(t.startsWith(u + '?'))
}

{
  const u = 'https://file.ibox.art/cover.png?foo=1'
  const t = thumbUrl(u, { w: 80, h: 80 })
  assert.ok(t.includes('&x-oss-process=image/resize,m_fill,w_80,h_80,limit_0'))
}

{
  const u = 'https://file.ibox.art/x.png?x-oss-process=image/resize,m_fill,w_40,h_40'
  assert.equal(thumbUrl(u), u)
}

{
  const u = 'https://xxx.aliyuncs.com/a.jpg'
  assert.ok(thumbUrl(u).includes('x-oss-process='))
}

console.log('iboxThumb.test.mjs: ok')

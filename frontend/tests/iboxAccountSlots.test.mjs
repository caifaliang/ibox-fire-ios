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

{
  // Empty slot must mint a fresh deviceId — never reuse active account's id
  const store = reset()
  saveLoginToSlot(0, {
    token: 'tok-active',
    refreshToken: 'rt-active',
    uid: '1001',
    mobile: '13800000000',
    deviceId: 'dev_aaaaaaaaaaaaaaaa',
  })
  assert.equal(getActiveIndex(), 0)
  assert.equal(store.getItem('ibox.login.deviceId'), 'dev_aaaaaaaaaaaaaaaa')

  const slot1Did = ensureSlotDeviceId(1)
  assert.match(slot1Did, /^dev_/)
  assert.notEqual(slot1Did, 'dev_aaaaaaaaaaaaaaaa')
  assert.equal(loadSlots()[1].deviceId, slot1Did)
  // Non-active empty slot must not overwrite global login mirror
  assert.equal(store.getItem('ibox.login.deviceId'), 'dev_aaaaaaaaaaaaaaaa')
  // Slot-local reuse still works
  assert.equal(ensureSlotDeviceId(1), slot1Did)
}

console.log('iboxAccountSlots.test.mjs: ok')

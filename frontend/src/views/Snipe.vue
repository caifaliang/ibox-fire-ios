<script setup>
import { ref, computed, onMounted, onUnmounted, onActivated, onDeactivated, watch } from 'vue'
import { useAppStore } from '@/stores/app'
import api from '@/api'
import LogPanel from '@/components/LogPanel.vue'
import { visibleInterval } from '@/utils/visibleInterval'
import { getIboxToken, clearIboxSession, clearAllIboxSlots, kickIboxSession, consumeIboxKickMsg } from '@/utils/iboxSession'
import {
  listSlotsForUi,
  upsertLoginToSlot,
  activateSlot,
  clearSlot,
  ensureSlotDeviceId,
  firstEmptySlotIndex,
  migrateLegacyIfNeeded,
  getActiveIndex,
  getActiveSlot,
  SLOT_COUNT,
} from '@/lib/iboxAccountSlots'
import { EXE_URL, FIRE_APK_URL } from '@/constants/downloads'
import { runBatchList, runBatchUnlist } from '@/lib/localBatch'
import { runBuyLoop } from '@/lib/localBuy'
import { runSellLoop } from '@/lib/localSell'
import { runPlacePurchase } from '@/lib/localPlace'
import {
  fetchPurchaseOrders,
  fetchHoldingsDetail,
  runPrecisionSell,
} from '@/lib/localPrecision'
import { runAnnounceLock } from '@/lib/localAnnounce'
import {
  sendSmsLocal,
  loginSmsLocal,
  verifyTokenLocal,
  reportIboxPresence,
  setLoginDeviceId,
  setRefreshToken,
  getLoginDeviceId,
  getRefreshToken,
  ensureFreshIboxToken,
  runIboxSessionHealthCheck,
} from '@/lib/iboxLogin'
import { parseIboxAuthPaste } from '@/lib/iboxAuthPaste'

const store = useAppStore()

/** 非 VIP：可浏览科技页 UI，不可真正操作 */
const vipPreview = computed(() => !!store.user && !store.user.is_vip)

// === Shared login state ===
const mode = ref('buy')
const loggedIn = ref(false)
const uid = ref(0)
const token = ref('')
const phone = ref('')
const phoneInput = ref('')
const codeInput = ref('')
const showAdvanced = ref(false)
const tokenInput = ref('')
const loginLoading = ref(false)
const loginErr = ref('')
const loginProxyInput = ref(localStorage.getItem('snipeProxy') || '')
const smsLoading = ref(false)
const smsSent = ref(false)

/** 多账号槽 UI */
const accountSlots = ref([])
const loginTargetSlot = ref(0)

/** 已登录时点空槽：临时展开登录表单写该槽，不踢其它槽 */
const addingAccount = ref(false)

function beginAddAccount(index) {
  loginTargetSlot.value = index
  // Mint slot-only deviceId; do not mirror to login helpers until sendSms/doLogin
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
  try {
    const activeDid = getActiveSlot()?.deviceId
    if (activeDid && activeDid.length >= 8) setLoginDeviceId(activeDid)
  } catch {}
}

function refreshAccountSlots() {
  try {
    migrateLegacyIfNeeded()
    accountSlots.value = listSlotsForUi()
    if (!addingAccount.value) {
      loginTargetSlot.value = getActiveIndex()
    }
  } catch {
    accountSlots.value = []
  }
}

function applyActiveIboxSession(opts = {}) {
  refreshAccountSlots()
  const t = getIboxToken()
  if (t) {
    token.value = t
    uid.value =
      parseInt(sessionStorage.getItem('snipeUid')) ||
      parseInt(localStorage.getItem('snipeUid')) ||
      _decodeJWT(t).userId ||
      _decodeJWT(t).user_id ||
      0
    phone.value = sessionStorage.getItem('snipePhone') || localStorage.getItem('snipePhone') || ''
    loggedIn.value = true
    if (!opts.skipTimers) startSnipeSessionTimers()
  } else {
    token.value = ''
    uid.value = 0
    phone.value = ''
    loggedIn.value = false
    stopSnipeSessionTimers()
  }
}

function anyTaskRunning() {
  return !!(
    buyRunning.value ||
    sellRunning.value ||
    batchRunning.value ||
    rankRunning.value ||
    quantRunning.value ||
    announceRunning.value
  )
}

/** 切号后：退出加号页，清本机任务 UI，按新票刷新科技任务列表 */
function clearLocalTaskUiForSwitch() {
  try { clearInterval(buyTimer) } catch {}
  try { clearInterval(sellTimer) } catch {}
  try { clearInterval(batchTimer) } catch {}
  try { clearInterval(sweepTimer) } catch {}
  try { clearInterval(swapTimer) } catch {}
  try { clearInterval(rankTimer) } catch {}
  try { clearInterval(quantTimer) } catch {}
  try { clearInterval(announceTimer) } catch {}
  buyTimer = null
  sellTimer = null
  batchTimer = null
  sweepTimer = null
  swapTimer = null
  rankTimer = null
  quantTimer = null
  announceTimer = null
  buyRunning.value = false
  buyTaskId.value = ''
  sellRunning.value = false
  sellTaskId.value = ''
  batchRunning.value = false
  batchJobId.value = ''
  sweepRunning.value = false
  sweepJobId.value = ''
  swapRunning.value = false
  swapJobId.value = ''
  rankRunning.value = false
  rankJobId.value = ''
  quantRunning.value = false
  quantJobId.value = ''
  announceRunning.value = false
  announceJobId.value = ''
  synthRunning.value = false
  presaleRunning.value = false
  ;[
    'snipeTaskId',
    'sellTaskId',
    'batchJobId',
    'sweepJobId',
    'swapJobId',
    'rankJobId',
    'quantJobId',
    'announceJobId',
  ].forEach((k) => {
    try {
      localStorage.removeItem(k)
    } catch {}
  })
  taskHistory.value = []
  accountHealth.value = ''
  stopAllMsg.value = ''
}

async function refreshTechAfterSlotSwitch() {
  addingAccount.value = false
  loginTargetSlot.value = getActiveIndex()
  loginErr.value = ''
  clearLocalTaskUiForSwitch()
  applyActiveIboxSession()
  await tryRefreshIboxSession()
  await loadHistory()
}

function onSelectAccountSlot(index) {
  const slot = accountSlots.value.find((s) => s.index === index)
  if (!slot) return
  if (!slot.occupied) {
    beginAddAccount(index)
    return
  }
  // 加号页点回已登录槽：关掉登录表单，回到该号科技页
  if (slot.active) {
    if (addingAccount.value) {
      cancelAddAccount()
      refreshTechAfterSlotSwitch()
    }
    return
  }
  if (anyTaskRunning()) {
    store.showToast('任务仍用旧号运行，请先停再切（已切换登录态）', 'warn', 4000)
  }
  const r = activateSlot(index)
  if (!r.ok) {
    store.showToast(r.message || '切换失败', 'error', 2500)
    return
  }
  store.showToast(`已切换到 ${slot.label}`, 'success', 2000)
  refreshTechAfterSlotSwitch()
}

async function sendSms() {
  if (!store.requireVip()) return
  const ph = phoneInput.value.replace(/\s/g, '')
  if (!ph || ph.length < 11) { loginErr.value = '请输入手机号'; return }
  // 发码前绑定目标槽 deviceId（与登录同一条）；显式镜像到 login helpers
  const target =
    loginTargetSlot.value >= 0 ? loginTargetSlot.value : Math.max(0, firstEmptySlotIndex())
  loginTargetSlot.value = target
  const did = ensureSlotDeviceId(target)
  setLoginDeviceId(did)
  smsLoading.value = true; loginErr.value = ''; smsSent.value = false
  try {
    await ensureProxy()
    const data = await sendSmsLocal(api, ph, getProxy())
    if (data.status === 'ok') {
      smsSent.value = true
      loginErr.value = ''
      if (data.device_id) setLoginDeviceId(data.device_id)
    }
    else { loginErr.value = data.message || '发送失败，请重试' }
  } catch (e) { loginErr.value = e.message || '网络错误' }
  smsLoading.value = false
}

// === Shared search ===
const searchQ = ref('')
const searchResults = ref([])
let searchTimer

// === Buy state ===
const buyGid = ref(0)
const buyCname = ref('')
const buyPrice = ref('')
const buyQty = ref('')
const buyAutoPay = ref(false)
const buyPwd = ref('')
const buyProxy = ref('')
const buyRunning = ref(false)
const _cachedProxy = ref(localStorage.getItem('snipeProxy') || '')
function getProxy() { return _cachedProxy.value }
// 挂载时自动从服务器拉代理
(async () => { try { const r = await api.get('/user/proxy'); if (r.data.proxy) { _cachedProxy.value = r.data.proxy; localStorage.setItem('snipeProxy', r.data.proxy) } } catch {} })()
async function ensureProxy() {
  if (_cachedProxy.value) return _cachedProxy.value
  for (let i = 0; i < 20; i++) {  // 最多等2秒
    await new Promise(r => setTimeout(r, 100))
    if (_cachedProxy.value) return _cachedProxy.value
  }
  return ''
}
const buyTaskId = ref('')
const buyLogs = ref([])
let buyTimer = null
/** 本机直连捡漏：停止标志 */
let buyAbort = false
let buyLocalRun = null
const buyMode = ref(localStorage.getItem('buyMode') || 'cross') // normal | cross | batch
const buyBatchInterval = ref(localStorage.getItem('buyBatchInterval') || '6')
const buyModes = [
  { key: 'normal', label: '普通下单', tip: '挂单逐笔买入' },
  { key: 'cross', label: '批量+普通', tip: '批购与普通穿插', recommend: true },
  { key: 'batch', label: '纯批量', tip: '只打批购接口' },
]

// === Task History ===
const taskHistory = ref([])
const historyOpen = ref(false)
const rankRulesOpen = ref(false)
const stopAllLoading = ref(false)
const stopAllMsg = ref('')
const stopAllOk = ref(false)
async function loadHistory() {
  if (!token.value) return
  try {
    const r = await api.get('/snipe/my-tasks', { params: { token: token.value } })
    taskHistory.value = r.data.tasks || []
  } catch {}
}
async function stopAllTasks() {
  if (!token.value && !localStorage.getItem('token')) return
  stopAllLoading.value = true; stopAllMsg.value = ''; stopAllOk.value = false
  try {
    const r = await api.post('/snipe/stop-all', null, {
      params: {
        platform_token: localStorage.getItem('token') || '',
        token: token.value || localStorage.getItem('snipeToken') || '',
      },
    })
    if (r.data.status === 'ok') {
      stopAllMsg.value = '已停止 ' + r.data.stopped + ' 个任务'
      stopAllOk.value = true
      // Also stop local tracked tasks
      buyRunning.value = false; buyTaskId.value = ''
      sellRunning.value = false; sellTaskId.value = ''
      batchRunning.value = false; batchJobId.value = ''
      sweepRunning.value = false; sweepJobId.value = ''
      swapRunning.value = false; swapJobId.value = ''
      rankRunning.value = false; rankJobId.value = ''; clearInterval(rankTimer); rankTimer = null
      localStorage.removeItem('rankJobId')
      quantRunning.value = false; quantJobId.value = ''; clearInterval(quantTimer); quantTimer = null
      localStorage.removeItem('quantJobId')
      announceRunning.value = false; announceJobId.value = ''; clearInterval(announceTimer); announceTimer = null
      localStorage.removeItem('announceJobId')
      synthRunning.value = false
      presaleRunning.value = false
      loadHistory()
    } else {
      stopAllMsg.value = r.data.message || '停止失败'
    }
  } catch (e) {
    stopAllMsg.value = '网络错误'
  }
  stopAllLoading.value = false
  setTimeout(() => stopAllMsg.value = '', 3000)
}
function statusLabel(s) { return s === 'running' ? '运行中' : s === 'stopping' ? '停止中' : '已停止' }
function statusColor(s) { return s === 'running' ? 'text-green-600 bg-green-50' : s === 'stopping' ? 'text-blue-600 bg-blue-50' : 'text-slate-500 bg-slate-50' }
function timeAgo(ts) {
  const d = Math.floor(Date.now()/1000 - ts)
  if (d < 60) return d + '秒前'
  if (d < 3600) return Math.floor(d/60) + '分钟前'
  if (d < 86400) return Math.floor(d/3600) + '小时前'
  return Math.floor(d/86400) + '天前'
}
async function stopHistoryTask(tid, ttype) {
  const stopMap = {
    buy: '/snipe/stop-loop', sell: '/snipe/stop-sell-loop',
    list: '/snipe/batch-stop', unlist: '/snipe/batch-stop',
    sweep: '/snipe/batch-stop', swap: '/snipe/swap-stop',
    synth: '/snipe/synth-status',
    presale: '/snipe/stop-loop',
    rank: '/snipe/rank-farm/stop',
    quant: '/snipe/quant-sell/stop',
    announce_lock: '/snipe/announce-lock/stop',
  }
  await api.post(stopMap[ttype] || '/snipe/batch-stop', null, { params: { task_id: tid, job_id: tid } })
  await new Promise(r => setTimeout(r, 1000))
  // 同步当前运行按钮
  if (tid === buyTaskId.value) {
    buyRunning.value = false; buyTaskId.value = ''; clearInterval(buyTimer)
    localStorage.removeItem('snipeTaskId')
    addLog(buyLogs, '从历史任务停止', 'error')
  }
  if (tid === sellTaskId.value) {
    sellRunning.value = false; sellTaskId.value = ''; clearInterval(sellTimer)
    localStorage.removeItem('sellTaskId')
  }
  if (tid === sweepJobId.value) {
    sweepRunning.value = false; sweepJobId.value = ''; clearInterval(sweepTimer)
    localStorage.removeItem('sweepJobId')
  }
  if (tid === batchJobId.value) {
    batchRunning.value = false; batchJobId.value = ''; clearInterval(batchTimer)
    localStorage.removeItem('batchJobId')
  }
  if (tid === rankJobId.value) {
    rankRunning.value = false; rankJobId.value = ''; clearInterval(rankTimer); rankTimer = null
    localStorage.removeItem('rankJobId')
    addLog(rankLogs, '从历史任务停止', 'error')
  }
  if (tid === quantJobId.value) {
    quantRunning.value = false; quantJobId.value = ''; clearInterval(quantTimer); quantTimer = null
    localStorage.removeItem('quantJobId')
    addLog(quantLogs, '从历史任务停止', 'error')
  }
  if (tid === announceJobId.value) {
    announceAbort = true
    announceRunning.value = false; announceJobId.value = ''; clearInterval(announceTimer); announceTimer = null
    localStorage.removeItem('announceJobId')
    addLog(announceLogs, '从历史任务停止', 'error')
  }
  loadHistory()
}

function typeLabel(t) { return {buy:'捡漏',sell:'卖求购',place:'顶求购',list:'上架',unlist:'下架',sweep:'点对点',swap:'互刷',synth:'抢合',presale:'抢购',precision:'精准射',rank:'打榜',quant:'量化出货',announce_lock:'公告锁定'}[t] || t }

// === Form validation ===
const fieldErrors = ref({})
function markError(field) { fieldErrors.value = { ...fieldErrors.value, [field]: true }; setTimeout(() => { const e = { ...fieldErrors.value }; delete e[field]; fieldErrors.value = e }, 3000) }
function clearErrors() { fieldErrors.value = {} }
function isError(field) { return !!fieldErrors.value[field] }

// === Account health check ===
const checkingHealth = ref(false)
const accountHealth = ref('')  // 'ok' | 'expired' | 'blocked' | 'error'
let healthTimer = null
let tokenRefreshTimer = null

/** keep-alive 切到爬仓后仍会跑 visibleInterval；离开科技页必须停验活，否则行情并发 401 会误踢 */
let snipePageActive = true

async function doHealthCheck() {
  if (!snipePageActive) return
  if (!token.value) return
  checkingHealth.value = true
  accountHealth.value = ''
  try {
    // 切后台回来 access 常已过期：必须先续期再验活，避免误清 refresh
    const r = await runIboxSessionHealthCheck(api, token.value)
    if (!snipePageActive) return
    if (r.token) token.value = r.token
    accountHealth.value = r.health || 'error'
    if (r.kick) {
      kickIboxSession(r.message || '登录已失效，请重新登录')
      token.value = ''
      uid.value = 0
      loggedIn.value = false
      clearInterval(healthTimer)
      healthTimer = null
    }
  } catch {
    accountHealth.value = 'error'
  }
  checkingHealth.value = false
  if (token.value && snipePageActive) reportIboxPresence(api, token.value, accountHealth.value)
  if (accountHealth.value !== 'expired') {
    setTimeout(() => { accountHealth.value = '' }, 10000)
  }
}

function stopSnipeSessionTimers() {
  clearInterval(healthTimer)
  healthTimer = null
  clearInterval(tokenRefreshTimer)
  tokenRefreshTimer = null
}

function startSnipeSessionTimers() {
  stopSnipeSessionTimers()
  if (!getIboxToken()) return
  tokenRefreshTimer = visibleInterval(tryRefreshIboxSession, 15 * 60 * 1000)
  healthTimer = visibleInterval(doHealthCheck, 60000)
}

// === Shared consign password (sell & batch use same) ===
const consignPwd = ref('')

// === Sell state ===
const sellGid = ref(0)
const sellCname = ref('')
const sellPrice = ref('')
const sellQty = ref('')
const sellRunning = ref(false)
const sellTaskId = ref('')
const sellTimed = ref(false)
const sellFireTime = ref('')  // 精确开卖 "15:50:00"，对齐抢合时分秒
const sellCountdown = ref('')
let sellAbort = false
let sellLocalRun = null
const sellLogs = ref([])
let sellTimer = null
let sellCountdownTimer = null

// === 顶求购 place (advance-orders + auto pay) ===
const placeGid = ref(0)
const placeCname = ref('')
const placePrice = ref('')
const placeQty = ref('1')
const placePwd = ref('')
const placeAutoPay = ref(true)
const placeBusy = ref(false)
const placeLogs = ref([])

// === Batch state ===
const batchGid = ref(0)
const batchCname = ref('')
const batchPrice = ref('')
const batchQty = ref('')
const batchRunning = ref(false)
const batchStarting = ref(false)
const batchSafeMode = ref(true)  // 安全模式标签保留；上架已统一按编号顺序
const batchJobId = ref('')
const batchLogs = ref([])
let batchTimer = null
let batchPollMiss = 0
const BATCH_POLL_GRACE = 25
/** 本机直连上下架：停止标志 */
let batchAbort = false
let batchLocalRun = null

// === Rank 打榜 state ===
const rankGid = ref(0)
const rankCname = ref('')
const rankTarget = ref(10)
const rankMarkup = ref(0)
const rankSellMin = ref(100)
const rankFloor = ref(null)  // 市场地板，仅展示
const rankFloorLoading = ref(false)
const rankPayPwd = ref(localStorage.getItem('rankPayPwd') || '')
const rankConsignPwd = ref(localStorage.getItem('rankConsignPwd') || '')
const rankRunning = ref(false)
const rankJobId = ref('')
const rankLogs = ref([])
const rankEstimate = ref(null)
const RANK_HARD_MIN = 100  // 防恶意低价挂单兜底
/** 活动标的：喜糖熊猫（水）开寄售 GID（勿用 22427=2026喜糖熊猫已关寄售） */
const RANK_DEFAULT_GID = 24222
const RANK_DEFAULT_NAME = '喜糖熊猫（水）'
let rankTimer = null

async function ensureRankDefault() {
  // 进入打榜即选中活动标的（24222=喜糖熊猫（水）；勿用 22427=2026喜糖熊猫已关寄售）
  const changed = Number(rankGid.value) !== RANK_DEFAULT_GID
  rankGid.value = RANK_DEFAULT_GID
  rankCname.value = RANK_DEFAULT_NAME
  if (changed) {
    rankEstimate.value = null
    rankFloor.value = null
  }
  try {
    const r = await api.get('/collections/search', { params: { q: '喜糖熊猫（水）' } })
    const list = (r.data || []).filter(x => x.id > 0)
    const hit = list.find(x => Number(x.id) === RANK_DEFAULT_GID)
    if (hit) {
      rankGid.value = hit.id
      rankCname.value = hit.name || RANK_DEFAULT_NAME
    }
  } catch {}
  await rankFetchFloor({ silent: true })
}

async function rankFetchFloor(opts = {}) {
  const silent = !!opts.silent
  if (!rankGid.value) {
    if (!silent) store.showToast('请先选择藏品', 'warn')
    return
  }
  if (!token.value) {
    // 未登 iBox 也能先选中藏品；地板等登录后再拉
    if (!silent) store.showToast('请先登录 iBox 后再拉地板价', 'warn')
    return
  }
  rankFloorLoading.value = true
  try {
    const r = await api.get('/snipe/rank-floor', {
      params: { group_id: rankGid.value, token: token.value },
      timeout: 15000,
    })
    if (r.data?.status === 'ok') {
      const floor = parseFloat(r.data.floor) || 0
      // 输入框永远 ≥100；展示真实地板（可能被恶意压到很低）
      rankFloor.value = floor > 0 ? floor : null
      rankSellMin.value = Math.max(floor > 0 ? floor : 0, RANK_HARD_MIN)
      if (!silent) {
        if (floor > 0) store.showToast(`已填入底价 ¥${rankSellMin.value}` + (floor < RANK_HARD_MIN ? `（地板仅¥${floor}，已兜底100）` : `（地板 ¥${floor}）`), 'success')
        else store.showToast(`暂无挂单，底价兜底 ¥${RANK_HARD_MIN}`, 'warn')
      }
    } else if (!silent) {
      store.showToast(r.data?.message || '拉取地板失败', 'error')
    }
  } catch (e) {
    if (!silent) store.showToast(e.response?.data?.detail || e.message || '拉取地板超时/失败', 'error')
  } finally {
    rankFloorLoading.value = false
  }
}

async function rankRefreshEstimate() {
  if (!store.requireVip()) return
  if (!token.value || !rankGid.value) { loginErr.value = '请先登录并选择藏品'; return }
  await rankFetchFloor({ silent: true })
  try {
    const r = await api.post('/snipe/rank-score/estimate', {
      token: token.value,
      group_id: rankGid.value,
      platform_token: localStorage.getItem('token') || '',
      proxy: getProxy(),
    })
    if (r.data?.status === 'ok') rankEstimate.value = r.data
    else store.showToast(r.data?.message || '预估失败', 'error')
  } catch (e) {
    store.showToast(e.response?.data?.detail || e.message || '预估失败', 'error')
  }
}

async function rankPoll() {
  if (!rankJobId.value) return
  try {
    const r = await api.get('/snipe/rank-farm/status', { params: { job_id: rankJobId.value } })
    if (Array.isArray(r.data?.logs) && r.data.logs.length) rankLogs.value = r.data.logs
    if (r.data?.status === 'stopped') {
      rankRunning.value = false
      clearInterval(rankTimer)
      rankTimer = null
      localStorage.removeItem('rankJobId')
      rankRefreshEstimate()
    }
  } catch {}
}

async function rankStart() {
  if (!store.requireVip()) return
  if (!token.value) { loginErr.value = '请先登录'; return }
  if (!rankGid.value) { loginErr.value = '请搜索选择活动藏品'; return }
  if (!rankPayPwd.value || !rankConsignPwd.value) { loginErr.value = '请填写支付密码和寄售密码'; return }
  rankRunning.value = true; loginErr.value = ''; rankLogs.value = []
  try {
    const r = await api.post('/snipe/rank-farm/start', {
      token: token.value,
      group_id: rankGid.value,
      platform_token: localStorage.getItem('token') || '',
      collection_name: rankCname.value,
      target_pairs: parseInt(rankTarget.value) || 10,
      sell_markup: parseFloat(rankMarkup.value) || 0,
      sell_min: Math.max(parseFloat(rankSellMin.value) || 0, RANK_HARD_MIN),
      pay_password: rankPayPwd.value,
      consign_password: rankConsignPwd.value,
      proxy: getProxy(),
    })
    if (r.data?.status === 'ok' && r.data.job_id) {
      localStorage.setItem('rankPayPwd', rankPayPwd.value)
      localStorage.setItem('rankConsignPwd', rankConsignPwd.value)
      rankJobId.value = r.data.job_id
      localStorage.setItem('rankJobId', r.data.job_id)
      clearInterval(rankTimer)
      rankTimer = setInterval(rankPoll, 2000)
      rankPoll()
    } else {
      rankRunning.value = false
      store.showToast(r.data?.message || '启动失败', 'error')
    }
  } catch (e) {
    rankRunning.value = false
    store.showToast(e.response?.data?.detail || e.message || '启动失败', 'error')
  }
}

async function rankStop() {
  if (rankJobId.value) {
    try {
      await api.post('/snipe/rank-farm/stop', null, {
        params: { job_id: rankJobId.value, platform_token: localStorage.getItem('token') || '' }
      })
    } catch {}
  }
  rankRunning.value = false
  clearInterval(rankTimer)
  rankTimer = null
  localStorage.removeItem('rankJobId')
  addLog(rankLogs, '打榜已停止', 'error')
}

function rankQuickSearch(q) {
  searchQ.value = q
  doSearch()
}

async function rankPickDefaultPanda() {
  // 强制切回默认喜糖熊猫（水）并拉地板
  rankGid.value = 0
  rankCname.value = ''
  await ensureRankDefault()
  if (rankGid.value) store.showToast(`已选中 ${rankCname.value}`, 'success')
}

// === Quant 量化出货 ===
const quantGid = ref(0)
const quantCname = ref('')
const quantMarkup = ref(0)
const quantTarget = ref(1)
const quantFloor = ref(null)
const quantFloorLoading = ref(false)
const quantConsignPwd = ref(localStorage.getItem('quantConsignPwd') || '')
const quantRunning = ref(false)
const quantJobId = ref('')
const quantLogs = ref([])
let quantTimer = null

const quantPreviewPrice = computed(() => {
  const f = parseFloat(quantFloor.value)
  const m = parseFloat(quantMarkup.value)
  if (!(f > 0) || Number.isNaN(m)) return null
  return Math.round((f + m) * 100) / 100
})

async function quantFetchFloor(opts = {}) {
  const silent = !!opts.silent
  if (!quantGid.value) {
    if (!silent) store.showToast('请先选择藏品', 'warn')
    return
  }
  if (!token.value) {
    if (!silent) store.showToast('请先登录 iBox 后再拉地板价', 'warn')
    return
  }
  quantFloorLoading.value = true
  try {
    const r = await api.get('/snipe/rank-floor', {
      params: { group_id: quantGid.value, token: token.value },
      timeout: 15000,
    })
    if (r.data?.status === 'ok') {
      const floor = parseFloat(r.data.floor) || 0
      quantFloor.value = floor > 0 ? floor : null
      if (!silent) {
        if (floor > 0) store.showToast(`地板 ¥${floor}`, 'success')
        else store.showToast('暂无挂单地板', 'warn')
      }
    } else if (!silent) {
      store.showToast(r.data?.message || '拉取地板失败', 'error')
    }
  } catch (e) {
    if (!silent) store.showToast(e.response?.data?.detail || e.message || '拉取地板超时/失败', 'error')
  } finally {
    quantFloorLoading.value = false
  }
}

async function quantPoll() {
  if (!quantJobId.value) return
  try {
    const r = await api.get('/snipe/quant-sell/status', { params: { job_id: quantJobId.value } })
    if (Array.isArray(r.data?.logs) && r.data.logs.length) quantLogs.value = r.data.logs
    // 仅以 stopped 结束；not_found 可能是瞬时查询失败，勿清状态
    if (r.data?.status === 'stopped') {
      quantRunning.value = false
      clearInterval(quantTimer)
      quantTimer = null
      localStorage.removeItem('quantJobId')
      addLog(quantLogs, '量化出货已结束', 'info')
    }
  } catch {}
}

async function quantStart() {
  if (!store.requireVip()) return
  if (!token.value) { loginErr.value = '请先登录 iBox'; return }
  if (!quantGid.value) { loginErr.value = '请先搜索选择藏品'; return }
  if (!quantConsignPwd.value) { loginErr.value = '请填写寄售密码'; return }
  localStorage.setItem('quantConsignPwd', quantConsignPwd.value)
  quantLogs.value = []
  quantRunning.value = true
  loginErr.value = ''
  addLog(quantLogs, '启动量化出货...', 'info')
  try {
    const r = await api.post('/snipe/quant-sell/start', {
      token: token.value,
      group_id: quantGid.value,
      platform_token: localStorage.getItem('token') || '',
      collection_name: quantCname.value,
      markup: parseFloat(quantMarkup.value) || 0,
      consign_password: quantConsignPwd.value,
      proxy: getProxy(),
      watch_sec: 180,
      target_qty: Math.max(1, parseInt(quantTarget.value) || 1),
    })
    if (r.data?.status === 'ok' && r.data.job_id) {
      quantJobId.value = r.data.job_id
      localStorage.setItem('quantJobId', quantJobId.value)
      clearInterval(quantTimer)
      quantTimer = setInterval(quantPoll, 2000)
      quantPoll()
      loadHistory()
    } else {
      quantRunning.value = false
      store.showToast(r.data?.message || '启动失败', 'error')
      addLog(quantLogs, r.data?.message || '启动失败', 'error')
    }
  } catch (e) {
    quantRunning.value = false
    store.showToast(e.response?.data?.detail || e.message || '启动失败', 'error')
    addLog(quantLogs, e.response?.data?.detail || e.message || '启动失败', 'error')
  }
}

async function quantStop() {
  if (!quantJobId.value) { quantRunning.value = false; return }
  try {
    await api.post('/snipe/quant-sell/stop', null, {
      params: { job_id: quantJobId.value, platform_token: localStorage.getItem('token') || '' },
    })
  } catch {}
  quantRunning.value = false
  clearInterval(quantTimer)
  quantTimer = null
  localStorage.removeItem('quantJobId')
  addLog(quantLogs, '量化出货已停止', 'error')
}

// === 公告锁定（月卡每日3次 / 年卡不限）===
const announceOrderMode = ref(localStorage.getItem('announceOrderMode') || 'single')
const announceMaxCount = ref(localStorage.getItem('announceMaxCount') || '1')
const announceMaxPrice = ref(localStorage.getItem('announceMaxPrice') || '')
const announceRunning = ref(false)
const announceJobId = ref('')
const announceLogs = ref([])
let announceTimer = null
let announceAbort = false
let announceLocalRun = null
const isYearVip = computed(() => !!(store.user?.is_admin || store.user?.is_year_vip))
const isAnnounceVip = computed(() => !!(store.user?.is_admin || store.user?.is_year_vip || store.user?.is_month_vip || store.user?.is_vip))
const announceQuota = ref({ used: 0, limit: 3, remaining: 3, unlimited: false, open_now: true, open_hours: '09:00-23:59' })
const announceCanStart = computed(() => {
  if (announceRunning.value) return true
  if (!isAnnounceVip.value && !vipPreview.value) return false
  if (!announceQuota.value.unlimited && (announceQuota.value.remaining ?? 0) <= 0) return false
  if (announceQuota.value.open_now === false) return false
  return true
})

watch(announceOrderMode, (v) => localStorage.setItem('announceOrderMode', v))
watch(announceMaxCount, (v) => localStorage.setItem('announceMaxCount', String(v || '')))
watch(announceMaxPrice, (v) => localStorage.setItem('announceMaxPrice', String(v || '')))

async function refreshAnnounceQuota() {
  try {
    const pt = localStorage.getItem('token') || store.token || ''
    if (!pt) return
    const r = await api.get('/snipe/announce-lock/quota', { params: { platform_token: pt } })
    if (r.data?.status === 'ok') {
      announceQuota.value = {
        used: r.data.used || 0,
        limit: r.data.limit || 3,
        remaining: r.data.remaining ?? 0,
        unlimited: !!r.data.unlimited,
        open_now: r.data.open_now !== false,
        open_hours: r.data.open_hours || '09:00-23:59',
      }
    }
  } catch {}
}

async function announcePoll() {
  // 本机直连无需轮询云端
}

async function announceStart() {
  if (!store.requireVip()) return
  if (!isAnnounceVip.value) {
    store.showToast('公告锁定仅月卡/年卡可用', 'warn')
    return
  }
  if (!token.value) { loginErr.value = '请先登录 iBox'; return }
  await refreshAnnounceQuota()
  if (announceQuota.value.open_now === false) {
    addLog(announceLogs, `仅北京时间 ${announceQuota.value.open_hours || '09:00-23:59'} 可用`, 'error')
    return
  }
  if (!announceQuota.value.unlimited && (announceQuota.value.remaining ?? 0) <= 0) {
    addLog(announceLogs, `今日公告锁定次数已用完（每天限${announceQuota.value.limit}次）`, 'error')
    return
  }
  if (announceOrderMode.value === 'batch') {
    if (!(parseFloat(announceMaxPrice.value) > 0)) {
      addLog(announceLogs, '批量模式请填写钱包余额', 'error')
      return
    }
    if (!(parseInt(announceMaxCount.value, 10) >= 1)) {
      addLog(announceLogs, '批量模式请填写数量', 'error')
      return
    }
  }

  const platform_token = localStorage.getItem('token') || store.token || ''
  if (!platform_token) { loginErr.value = '请先登录网站账号'; return }

  announceAbort = false
  announceRunning.value = true
  announceLogs.value = []
  announceJobId.value = 'local-announce'
  localStorage.removeItem('announceJobId')
  addLog(announceLogs, '公告锁扣次…', 'info')

  try {
    const cr = await api.post('/snipe/local/consume', {
      platform_token,
      kind: 'announce_lock',
    })
    if (cr.data?.status !== 'ok') {
      addLog(announceLogs, '扣次失败: ' + (cr.data?.message || '未知'), 'error')
      announceRunning.value = false
      announceJobId.value = ''
      return
    }
    const q = cr.data.quota || cr.data
    announceQuota.value = {
      ...announceQuota.value,
      used: q.used ?? announceQuota.value.used,
      limit: q.limit ?? announceQuota.value.limit,
      remaining: q.remaining ?? announceQuota.value.remaining,
      unlimited: !!q.unlimited || announceQuota.value.unlimited,
      open_now: q.open_now !== false,
      open_hours: q.open_hours || announceQuota.value.open_hours,
    }
    addLog(
      announceLogs,
      '公告锁已扣次 剩 ' + (announceQuota.value.unlimited ? '不限' : `${announceQuota.value.remaining}/${announceQuota.value.limit}`),
      'buy'
    )
  } catch (e) {
    addLog(announceLogs, '扣次失败: ' + (e.response?.data?.detail || e.message || '网络'), 'error')
    announceRunning.value = false
    announceJobId.value = ''
    return
  }

  addLog(announceLogs, '公告发现本机直连（不走代理）· 轮询 350ms · 无共享feed', 'buy')
  if (store.user?.wxpusher_uid) addLog(announceLogs, '锁定成功将推送 WxPusher 并自动暂停', 'info')
  else addLog(announceLogs, '未绑定 WxPusher：锁定成功仍会暂停，但不推送', 'info')
  announceLocalRun = runAnnounceLock({
    token: token.value,
    orderMode: announceOrderMode.value || 'single',
    maxSinglePrice: parseFloat(announceMaxPrice.value) || 0,
    maxCount: parseInt(announceMaxCount.value, 10) || 1,
    pollMs: 350,
    durationS: 3600,
    s1SearchBase: '/api',
    api,
    platformToken: platform_token,
    wxpusherUid: store.user?.wxpusher_uid || '',
    onLog: (msg, type = 'info') => addLog(announceLogs, msg, type),
    shouldStop: () => announceAbort || !announceRunning.value,
  }).finally(() => {
    announceRunning.value = false
    announceJobId.value = ''
    announceLocalRun = null
    refreshAnnounceQuota()
    loadHistory()
  })
}

async function announceStop() {
  announceAbort = true
  announceRunning.value = false
  clearInterval(announceTimer)
  announceTimer = null
  announceJobId.value = ''
  localStorage.removeItem('announceJobId')
  addLog(announceLogs, '公告锁定已停止', 'error')
}

// === Sweep state ===
const sweepGid = ref(0)
const sweepCname = ref('')
const sweepMarkerGid = ref(0)
const sweepMarkerCname = ref('')
const sweepMarkerSearch = ref('')
const sweepMarkerResults = ref([])
let sweepMarkerTimer = null
const sweepMarkerOrders = ref([])
const sweepMarkerSortValues = ref('')
const sweepMarkerHasMore = ref(false)
const sweepMarkerLoading = ref(false)
/** @type {import('vue').Ref<null|{sso:string,uid:number,name:string,markerOrderId:string,markerGid:number,digitalCollectionId:number}>} */
const sweepSeller = ref(null)
/** Pending seller fields for confirm modal */
const sweepSellerConfirm = ref(null)
const sweepWhGroups = ref([])
const sweepWhItems = ref([])
const sweepWhPage = ref(1)
const sweepWhHasMore = ref(false)
const sweepWhLoading = ref(false)
/** Selected warehouse items for order: [{digital_collection_id,token_id,price,group_id}] */
const sweepSelected = ref([])
const sweepMaxPrice = ref('')
const sweepQty = ref('')
const sweepAutoPay = ref(false)
const sweepAutoSelecting = ref(false)
const sweepAutoSelectMsg = ref('')
let sweepAutoSelectGen = 0
let sweepAutoSelectTimer = null
const sweepRunning = ref(false)
const sweepJobId = ref('')
const sweepLogs = ref([])
const sweepHelp = ref(false)
let sweepTimer = null
const sweepCanStart = computed(() => {
  if (!sweepSeller.value) return false
  if (!sweepSelected.value.length) return false
  if (!(parseFloat(sweepMaxPrice.value) > 0)) return false
  if (sweepQty.value !== '' && !(parseInt(sweepQty.value) >= 1)) return false
  return true
})

watch([sweepMaxPrice, sweepQty], () => {
  scheduleAutoSelectWh()
})

// === Synth state ===
const synthSearch = ref('')
const synthResults = ref([])
const synthSelected = ref(null)
const synthChannels = ref([])
const synthChannelId = ref(0)
const synthMaterials = ref([])
const synthAlbumMap = ref({})
const synthChecked = ref(new Set())
const synthOwnedFilter = ref(false)
const synthOwned = ref({})
const _allMaterials = ref([])
const synthLoading = ref(false)  // 加载材料中
const synthQty = ref('')
const synthFireTime = ref('')  // 精确开抢时间 "15:50:00"
const synthThreads = ref('12')  // 对齐 EXE 默认 12 线程
const synthRunning = ref(false)
const synthLogs = ref([])
const synthCountdown = ref('')
const synthAllowBatch = ref(true)
/** 0=满额一批 1=每次1 10=每次10 */
const synthBatchChunk = ref(0)
let synthTimer = null
let synthTaskId = ''

// === Presale state ===
const presaleItems = ref([])
const presalePage = ref(1)
const presaleHasMore = ref(false)
const presaleSelected = ref(null)
const presaleRunning = ref(false)
const presaleLogs = ref([])
const presaleQty = ref('')
const presaleFireTime = ref('')  // 精确开抢时间 "15:50:00"，默认=发售时间
const presaleCountdown = ref('')
const presaleTaskId = ref('')
let presaleTimer = null
let presalePollTimer = null
const presaleAutoPay = ref(false)
const presalePayPwd = ref('')

// === Precision Sell ===
const precisionGid = ref(0)
const precisionCname = ref('')
const precisionOrders = ref([])
const precisionOrdersTotal = ref(0)
const precisionOrdersPage = ref(1)
const precisionOrdersLoading = ref(false)
const precisionSelectedOrder = ref(null)
const precisionHoldings = ref([])
const precisionHoldingsLoading = ref(false)
const precisionSelectedHolding = ref(null)
const precisionPwd = ref('')
const precisionRunning = ref(false)
const precisionResult = ref('')
const precisionUuid = ref('')
const precisionUuidLoading = ref(false)

async function loadPresaleList() {
  const proxy = _cachedProxy.value
  if (!proxy || !token.value) return
  try {
    const r = await api.post('/snipe/presale-list', { page: presalePage.value, token: token.value, proxy })
    if (r.data.items) presaleItems.value = r.data.items
    presaleHasMore.value = r.data.hasMore || false
  } catch {}
}
async function selectPresale(item) {
  presaleSelected.value = item
  presaleCountdown.value = ''
  presaleQty.value = item.userOnceMaxBuyNum || 1
  // 默认开抢时间 = 发售时间（与抢合时间轮盘一致）
  if (item.onSaleTime) {
    const t = typeof item.onSaleTime === 'number'
      ? new Date(item.onSaleTime < 1e12 ? item.onSaleTime * 1000 : item.onSaleTime)
      : new Date(String(item.onSaleTime).replace(' ', 'T'))
    if (!isNaN(t.getTime())) {
      presaleFireTime.value = t.toTimeString().slice(0, 8)
    }
  }
}
async function startPresale() {
  if (!store.requireVip()) return
  if (!presaleSelected.value || !token.value || !_cachedProxy.value) { loginErr.value = '需要Token和私人代理'; return }
  await refreshPresaleQuota()
  if (!presaleQuota.value.unlimited && (presaleQuota.value.remaining || 0) <= 0) {
    loginErr.value = `今日抢购次数已用完（每天限${presaleQuota.value.limit || 1}次）`
    addLog(presaleLogs, loginErr.value, 'error')
    return
  }
  presaleRunning.value = true; presaleLogs.value = []
  addLog(presaleLogs, '抢购启动: ' + (presaleSelected.value.digitalCollectionGroup?.name || 'GID'+presaleSelected.value.groupId), 'buy')
  // 解析开抢时间（Safari 只返 HH:MM，自动补 :00），默认已填发售时间
  let onSaleTime = new Date(String(presaleSelected.value.onSaleTime || '').replace(' ', 'T'))
  let ft = presaleFireTime.value || ''
  if (ft && /^\d{2}:\d{2}(:\d{2})?$/.test(ft)) {
    if (ft.length === 5) ft = ft + ':00'
    const [h, m, s] = ft.split(':').map(Number)
    onSaleTime = new Date()
    onSaleTime.setHours(h, m, s, 0)
    if (onSaleTime <= new Date()) onSaleTime.setDate(onSaleTime.getDate() + 1)
    addLog(presaleLogs, '定时 ' + ft + ' 开抢', 'info')
  }

  // Countdown
  const tick = () => {
    if (!presaleRunning.value) return
    const remain = onSaleTime.getTime() - Date.now()
    if (remain <= 0) { presaleCountdown.value = '00:00:00'; return }
    const h = Math.floor(remain / 3600000); const m = Math.floor((remain % 3600000) / 60000); const s = Math.floor((remain % 60000) / 1000)
    presaleCountdown.value = String(h).padStart(2,'0') + ':' + String(m).padStart(2,'0') + ':' + String(s).padStart(2,'0')
  }
  tick(); presaleTimer = visibleInterval(tick, 500)

  // Start Celery task
  try {
    const r = await api.post('/snipe/presale-start', {
      token: token.value, proxy: _cachedProxy.value,
      sale_id: presaleSelected.value.id, sale_name: presaleSelected.value.digitalCollectionGroup?.name || '',
      sale_price: presaleSelected.value.price || 0,
      quantity: parseInt(presaleQty.value) || 1,
      auto_pay: presaleAutoPay.value, pay_password: presaleAutoPay.value ? (consignPwd.value || '') : '',
      wxpusher_uid: store.user?.wxpusher_uid || '',
      fire_at: onSaleTime.getTime() / 1000,
      platform_token: localStorage.getItem('token') || '',
    })
    if (r.data?.quota) {
      presaleQuota.value = {
        used: r.data.quota.used || 0,
        limit: r.data.quota.limit || 1,
        remaining: r.data.quota.remaining ?? 0,
        unlimited: !!r.data.quota.unlimited,
      }
    } else {
      refreshPresaleQuota()
    }
    if (r.data.status === 'ok') {
      presaleTaskId.value = r.data.task_id
      addLog(presaleLogs, 'Celery任务已投递 ' + r.data.task_id.substring(0,8), 'buy')
      presalePollTimer = visibleInterval(presalePoll, 1000)
    } else {
      addLog(presaleLogs, '启动失败: ' + (r.data.message || ''), 'error')
      presaleRunning.value = false; clearInterval(presaleTimer)
    }
  } catch (e) {
    addLog(presaleLogs, '启动异常: ' + (e.message || ''), 'error')
    presaleRunning.value = false; clearInterval(presaleTimer)
  }
}
async function presalePoll() {
  if (!presaleTaskId.value) return
  try {
    const r = await api.get('/snipe/presale-status', { params: { task_id: presaleTaskId.value, _t: Date.now() } })
    if (r.data.logs && r.data.logs.length) presaleLogs.value = [...r.data.logs]
    if (r.data.status === 'done' || r.data.status === 'failed') {
      if (r.data.paid) addLog(presaleLogs, '已支付', 'pay')
      if (r.data.pay_error) addLog(presaleLogs, '支付失败: ' + r.data.pay_error, 'error')
      presaleRunning.value = false; clearInterval(presaleTimer); clearInterval(presalePollTimer)
      // Push
      if (store.user?.wxpusher_uid && r.data.order_id) {
        const pl = await api.get('/snipe/pay-link', { params: { token: token.value, digital_collection_id: 0, order_id: r.data.order_id } }).catch(()=>{})
        const link = pl?.data?.link || ''
        await api.post('/snipe/push-link', { wxpusher_uid: store.user.wxpusher_uid, pay_link: link, collection_name: presaleSelected.value?.digitalCollectionGroup?.name || '', price: presaleSelected.value?.price || 0, action: 'buy' }).catch(()=>{})
      }
    }
  } catch {}
}
async function presaleToggle() {
  if (presaleRunning.value) { await presaleStop(); return }
  await startPresale()
}
async function presaleStop() {
  addLog(presaleLogs, '停止全部任务...', 'info')
  try { await api.post('/snipe/stop-all', null, { params: { platform_token: localStorage.getItem('token') || '', token: token.value || localStorage.getItem('snipeToken') || '' } }) } catch {}
  presaleRunning.value = false; clearInterval(presaleTimer); clearInterval(presalePollTimer)
  addLog(presaleLogs, '抢购已停止', 'error')
}
// === Swap state ===
const swapGid = ref(0)
const swapCname = ref('')
const swapTokenA = ref('')
const swapTokenB = ref('')
const swapPhoneA = ref('')
const swapPhoneB = ref('')
const swapCodeA = ref('')
const swapCodeB = ref('')
const swapLoggedA = ref(false)
const swapLoggedB = ref(false)
const swapLoginA = ref(false)
const swapLoginB = ref(false)
const swapPrice = ref('')
const swapCount = ref('')      // 每轮件数
const swapRounds = ref('')     // 完整往返轮数，空=未填
const swapPayA = ref('')
const swapPayB = ref('')
const swapRunning = ref(false)
const swapJobId = ref('')
const swapLogs = ref([])
const swapSmsLoadingA = ref(false)
const swapSmsLoadingB = ref(false)
const swapSmsSentA = ref(false)
const swapSmsSentB = ref(false)
/** 仅互刷：不登科技页主号，避免大小号互相顶号 */
const swapOnlyMode = ref(false)
let swapTimer = null

const swapConfirmOpen = ref(false)
const swapConfirmFromLogin = ref(false)
const synthQuotaOpen = ref(false)
const synthQuota = ref({ used: 0, limit: 2, remaining: 2, unlimited: false })
const presaleQuotaOpen = ref(false)
const presaleQuota = ref({ used: 0, limit: 1, remaining: 1, unlimited: false })

async function refreshSynthQuota() {
  try {
    const pt = localStorage.getItem('token') || ''
    if (!pt) return
    const r = await api.get('/snipe/synth-quota', { params: { platform_token: pt } })
    if (r.data?.status === 'ok') {
      synthQuota.value = {
        used: r.data.used || 0,
        limit: r.data.limit || 2,
        remaining: r.data.remaining ?? 0,
        unlimited: !!r.data.unlimited,
      }
    }
  } catch {}
}

async function refreshPresaleQuota() {
  try {
    const pt = localStorage.getItem('token') || ''
    if (!pt) return
    const r = await api.get('/snipe/presale-quota', { params: { platform_token: pt } })
    if (r.data?.status === 'ok') {
      presaleQuota.value = {
        used: r.data.used || 0,
        limit: r.data.limit || 1,
        remaining: r.data.remaining ?? 0,
        unlimited: !!r.data.unlimited,
      }
    }
  } catch {}
}

function enterSwapOnly() {
  addingAccount.value = false
  swapConfirmFromLogin.value = true
  swapConfirmOpen.value = true
}

function exitSwapOnly() {
  swapOnlyMode.value = false
  localStorage.removeItem('snipeSwapOnly')
}

function selectMode(k) {
  // 非 VIP 预览：可自由切换各功能页，真正开任务时再拦截
  if (vipPreview.value) {
    mode.value = k
    if (k === 'rank') ensureRankDefault()
    if (k === 'announce') refreshAnnounceQuota()
    return
  }
  if (k === 'announce') {
    mode.value = 'announce'
    refreshAnnounceQuota()
    return
  }
  if (k === 'swap' && mode.value !== 'swap') {
    swapConfirmFromLogin.value = false
    swapConfirmOpen.value = true
    return
  }
  if (k === 'synth' && mode.value !== 'synth') {
    refreshSynthQuota()
    synthQuotaOpen.value = true
    return
  }
  if (k === 'presale' && mode.value !== 'presale') {
    refreshPresaleQuota()
    presaleQuotaOpen.value = true
    return
  }
  mode.value = k
  if (k === 'rank') ensureRankDefault()
}

function confirmSynthEnter() {
  synthQuotaOpen.value = false
  mode.value = 'synth'
  refreshSynthQuota()
}

function cancelSynthEnter() {
  synthQuotaOpen.value = false
}

function confirmPresaleEnter() {
  presaleQuotaOpen.value = false
  mode.value = 'presale'
  refreshPresaleQuota()
}

function cancelPresaleEnter() {
  presaleQuotaOpen.value = false
}

function confirmSwapEnter() {
  swapConfirmOpen.value = false
  addingAccount.value = false
  if (swapConfirmFromLogin.value) {
    swapOnlyMode.value = true
    localStorage.setItem('snipeSwapOnly', '1')
  }
  mode.value = 'swap'
  swapConfirmFromLogin.value = false
  // 进入互刷页时复检 token，已挤号则自动解锁可重登
  if (swapTokenA.value) verifySwapToken('A')
  if (swapTokenB.value) verifySwapToken('B')
}

function cancelSwapEnter() {
  swapConfirmOpen.value = false
  swapConfirmFromLogin.value = false
}

function persistSwapTokens() {
  if (swapTokenA.value) localStorage.setItem('swapTokenA', swapTokenA.value)
  else localStorage.removeItem('swapTokenA')
  if (swapTokenB.value) localStorage.setItem('swapTokenB', swapTokenB.value)
  else localStorage.removeItem('swapTokenB')
}

function clearSwapSlot(slot) {
  if (slot === 'A') {
    swapTokenA.value = ''
    swapLoggedA.value = false
    swapCodeA.value = ''
    swapSmsSentA.value = false
    // 保留手机号方便换号重登
  } else {
    swapTokenB.value = ''
    swapLoggedB.value = false
    swapCodeB.value = ''
    swapSmsSentB.value = false
  }
  persistSwapTokens()
  loginErr.value = ''
}

async function copySwapToken(slot) {
  const tok = ((slot === 'A' ? swapTokenA.value : swapTokenB.value) || '').trim()
  const label = slot === 'A' ? '大号' : '小号'
  if (!tok) {
    loginErr.value = label + '暂无 Token'
    return
  }
  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(tok)
    } else {
      const ta = document.createElement('textarea')
      ta.value = tok
      ta.style.position = 'fixed'
      ta.style.left = '-9999px'
      document.body.appendChild(ta)
      ta.select()
      document.execCommand('copy')
      document.body.removeChild(ta)
    }
    loginErr.value = ''
    addLog(swapLogs, label + ' Token 已复制', 'info')
  } catch {
    loginErr.value = label + ' Token 复制失败'
  }
}

async function verifySwapToken(slot) {
  const tok = (slot === 'A' ? swapTokenA.value : swapTokenB.value) || ''
  if (!tok) {
    if (slot === 'A') swapLoggedA.value = false
    else swapLoggedB.value = false
    return false
  }
  try {
    const data = await verifyTokenLocal(tok)
    if (data?.status === 'ok') {
      if (slot === 'A') swapLoggedA.value = true
      else swapLoggedB.value = true
      return true
    }
  } catch {}
  clearSwapSlot(slot)
  return false
}

function restoreSwapTokens() {
  const a = localStorage.getItem('swapTokenA') || ''
  const b = localStorage.getItem('swapTokenB') || ''
  if (a) swapTokenA.value = a
  if (b) swapTokenB.value = b
  // 先乐观展示，随后异步校验；失效则清掉并允许重登
  if (a) swapLoggedA.value = true
  if (b) swapLoggedB.value = true
  if (a) verifySwapToken('A')
  if (b) verifySwapToken('B')
}

function hasMainSnipeLogin() {
  try {
    if (localStorage.getItem('snipeToken')) return true
    if (document.cookie.includes('snipeToken=')) return true
  } catch {}
  return false
}

async function sendSwapSms(slot) {
  const phone = (slot === 'A' ? swapPhoneA.value : swapPhoneB.value).replace(/\s/g, '')
  if (!phone || phone.length < 11) { loginErr.value = '请输入' + (slot === 'A' ? '大' : '小') + '号手机号'; return }
  if (slot === 'A') { swapSmsLoadingA.value = true; swapSmsSentA.value = false }
  else { swapSmsLoadingB.value = true; swapSmsSentB.value = false }
  loginErr.value = ''
  await ensureProxy()
  const trySend = async () => sendSmsLocal(api, phone, getProxy())
  try {
    let data = await trySend()
    if (data?.status !== 'ok') {
      await new Promise(r => setTimeout(r, 600))
      data = await trySend()
    }
    if (data?.status === 'ok') {
      if (slot === 'A') swapSmsSentA.value = true
      else swapSmsSentB.value = true
    } else {
      loginErr.value = (slot === 'A' ? '大' : '小') + '号验证码失败: ' + (data?.message || '未知')
    }
  } catch (e) {
    loginErr.value = (slot === 'A' ? '大' : '小') + '号验证码异常'
  }
  if (slot === 'A') swapSmsLoadingA.value = false
  else swapSmsLoadingB.value = false
}

async function doSwapLogin(slot) {
  const phone = slot === 'A' ? swapPhoneA.value : swapPhoneB.value
  const code = slot === 'A' ? swapCodeA.value : swapCodeB.value
  if (!phone || !code) { loginErr.value = '请填写手机号和验证码'; return }
  if (slot === 'A') swapLoginA.value = true; else swapLoginB.value = true
  loginErr.value = ''
  try {
    const data = await loginSmsLocal(api, phone, code)
    if (data.status === 'ok') {
      if (slot === 'A') { swapTokenA.value = data.token; swapLoggedA.value = true }
      else { swapTokenB.value = data.token; swapLoggedB.value = true }
      persistSwapTokens()
    } else {
      loginErr.value = slot + '号登录失败: ' + (data.message || '未知')
    }
  } catch (e) {
    loginErr.value = slot + '号登录异常'
  }
  if (slot === 'A') swapLoginA.value = false; else swapLoginB.value = false
}

async function swapTokenLogin() {
  const tokA = swapTokenA.value.trim()
  const tokB = swapTokenB.value.trim()
  if (!tokA && !tokB) return
  if (tokA) {
    const ok = await verifySwapToken('A')
    if (!ok) { loginErr.value = '大号 Token 无效或已挤号'; return }
  }
  if (tokB) {
    const ok = await verifySwapToken('B')
    if (!ok) { loginErr.value = '小号 Token 无效或已挤号'; return }
  }
  persistSwapTokens()
  loginErr.value = ''
}

// Per-mode gid/cname accessor
const curGid = computed(() => mode.value === 'sell' ? sellGid.value : mode.value === 'place' ? placeGid.value : mode.value === 'batch' ? batchGid.value : mode.value === 'sweep' ? sweepGid.value : mode.value === 'precision' ? precisionGid.value : mode.value === 'rank' ? rankGid.value : mode.value === 'quant' ? quantGid.value : buyGid.value)
const curCname = computed(() => mode.value === 'sell' ? sellCname.value : mode.value === 'place' ? placeCname.value : mode.value === 'batch' ? batchCname.value : mode.value === 'sweep' ? sweepCname.value : mode.value === 'precision' ? precisionCname.value : mode.value === 'rank' ? rankCname.value : mode.value === 'quant' ? quantCname.value : buyCname.value)

// === Helpers ===
function addLog(arr, msg, type = 'info') {
  const time = new Date().toLocaleTimeString('zh-CN', { hour12: false })
  arr.value.unshift({ time, msg, type })
  if (arr.value.length > 100) arr.value.pop()
}

function formatTime(ts) {
  if (!ts) return ''
  let d
  if (typeof ts === 'string' && ts.includes('-')) {
    d = new Date(ts.replace(' ', 'T'))
  } else {
    d = new Date(ts > 99999999999 ? ts : ts * 1000)
  }
  if (isNaN(d.getTime())) return String(ts)
  return (d.getMonth()+1) + '/' + d.getDate() + ' ' +
    String(d.getHours()).padStart(2,'0') + ':' + String(d.getMinutes()).padStart(2,'0')
}

// === Init & restore ===
function _decodeJWT(tok) {
  try {
    let b64 = tok.split('.')[1]
    b64 = b64.replace(/-/g, '+').replace(/_/g, '/')
    while (b64.length % 4) b64 += '='
    return JSON.parse(atob(b64))
  } catch { return {} }
}

onMounted(() => {
  restoreSwapTokens()
  refreshAccountSlots()
  // 有科技页主号 → 永远默认捡漏，清掉互刷专用残留标记
  // 无主号且显式互刷专用 → 才进互刷
  if (hasMainSnipeLogin()) {
    swapOnlyMode.value = false
    try { localStorage.removeItem('snipeSwapOnly') } catch {}
    mode.value = 'buy'
  } else if (localStorage.getItem('snipeSwapOnly') === '1') {
    swapOnlyMode.value = true
    mode.value = 'swap'
  } else {
    mode.value = 'buy'
  }
  try { localStorage.setItem('snipeMode', mode.value) } catch {}
  snipePageActive = true
  // 顶号踢出后的提示
  try {
    const kickMsg = consumeIboxKickMsg()
    if (kickMsg) {
      loginErr.value = kickMsg
      store.showToast(kickMsg, 'warn', 4000)
    }
  } catch {}
  const onKicked = () => {
    applyActiveIboxSession()
    try {
      const kickMsg = consumeIboxKickMsg()
      if (kickMsg) {
        loginErr.value = kickMsg
        store.showToast(kickMsg, 'warn', 4000)
      }
    } catch {}
  }
  const onSwitched = () => {
    applyActiveIboxSession()
    try {
      const kickMsg = consumeIboxKickMsg()
      if (kickMsg) store.showToast(kickMsg, 'warn', 4000)
    } catch {}
  }
  const onAuthChanged = () => {
    refreshAccountSlots()
  }
  window.__snipeOnKicked = onKicked
  window.__snipeOnSwitched = onSwitched
  window.__snipeOnAuthChanged = onAuthChanged
  window.addEventListener('ibox-auth-kicked', onKicked)
  window.addEventListener('ibox-auth-switched', onSwitched)
  window.addEventListener('ibox-auth-changed', onAuthChanged)
  const t = getIboxToken()
  if (t) {
    applyActiveIboxSession()
    // 先续期再健康检查，避免并行时旧票 401 误踢；离开科技页则取消后续踢人
    tryRefreshIboxSession().finally(() => {
      if (!snipePageActive) return
      if (!token.value && !getIboxToken()) return
      doHealthCheck()
    })
  }
  // Restore proxy
  buyProxy.value = localStorage.getItem('snipeProxy') || ''
  // Listen for proxy changes from Profile page
  window._onProxyChange = (p) => { buyProxy.value = p || '' }
  if (!window._proxyListeners) window._proxyListeners = []
  window._proxyListeners.push(window._onProxyChange)
  // Override _updateProxy to notify all listeners
  const _origUpdate = window._updateProxy
  window._updateProxy = (p) => {
    if (_origUpdate) _origUpdate(p)
    if (window._proxyListeners) window._proxyListeners.forEach(fn => { try { fn(p) } catch {} })
  }
  // Restore buy — Celery 捡漏已改为本机直连，不再恢复云端任务
  localStorage.removeItem('snipeTaskId')
  // Restore sell — 本机直连不跨刷新恢复
  localStorage.removeItem('sellTaskId')
  // Restore batch — 本机直连不跨刷新恢复
  localStorage.removeItem('batchJobId')
  // Restore rank
  const rj = localStorage.getItem('rankJobId')
  if (rj && token.value) {
    rankJobId.value = rj
    rankRunning.value = true
    clearInterval(rankTimer)
    rankTimer = setInterval(rankPoll, 2000)
    rankPoll()
  }
  // Restore quant
  const qj = localStorage.getItem('quantJobId')
  if (qj && token.value) {
    quantJobId.value = qj
    quantRunning.value = true
    clearInterval(quantTimer)
    quantTimer = setInterval(quantPoll, 2000)
    quantPoll()
  }
  // Restore announce lock — 本机直连不跨刷新恢复
  localStorage.removeItem('announceJobId')
  refreshAnnounceQuota()
})

watch(mode, v => {
  localStorage.setItem('snipeMode', v)
  if (loggedIn.value) loadHistory()
  if (v === 'rank') ensureRankDefault()
  if (v === 'announce') refreshAnnounceQuota()
}, { immediate: true })
// 卖求购完成自动复位按钮
watch(sellLogs, (logs) => {
  if (sellRunning.value && logs.length) {
    const last = logs[0]?.msg || ''
    if (last.includes('目标达成') || last.includes('已停止') || last.includes('全部卖出')) {
      sellRunning.value = false
      sellTaskId.value = ''
      clearInterval(sellTimer)
      localStorage.removeItem('sellTaskId')
    }
  }
})

onUnmounted(() => {
  buyAbort = true
  batchAbort = true
  sellAbort = true
  announceAbort = true
  clearInterval(buyTimer); clearInterval(sellTimer); clearInterval(batchTimer); clearInterval(rankTimer); clearInterval(quantTimer); clearInterval(announceTimer); clearInterval(healthTimer); clearInterval(tokenRefreshTimer)
  document.removeEventListener('visibilitychange', onVisible)
  try {
    window.removeEventListener('ibox-auth-kicked', window.__snipeOnKicked)
    window.removeEventListener('ibox-auth-switched', window.__snipeOnSwitched)
    window.removeEventListener('ibox-auth-changed', window.__snipeOnAuthChanged)
  } catch {}
})

// 切回标签页时立刻拉最新状态（浏览器后台会冻结定时器）
async function onVisible() {
  if (document.hidden) return
  // 先续期再轮询，避免过期 access 打业务接口触发拦截器误踢
  await tryRefreshIboxSession()
  if (buyRunning.value && buyTaskId.value) { buyPoll() }
  if (sellRunning.value && sellTaskId.value) { sellPoll() }
  if (batchRunning.value && batchJobId.value) { batchPoll() }
  if (rankRunning.value && rankJobId.value) { rankPoll() }
  if (quantRunning.value && quantJobId.value) { quantPoll() }
  if (announceRunning.value && announceJobId.value) { announcePoll() }
}
// 注册
if (typeof document !== 'undefined') {
  document.addEventListener('visibilitychange', onVisible)
}

// === Login ===
async function doLogin() {
  if (!store.requireVip()) return
  loginErr.value = ''
  loginLoading.value = true
  try {
    const target =
      loginTargetSlot.value >= 0 ? loginTargetSlot.value : Math.max(0, firstEmptySlotIndex())
    const did = ensureSlotDeviceId(target)
    setLoginDeviceId(did)
    const data = await loginSmsLocal(api, phoneInput.value, codeInput.value)
    if (data.status === 'ok') {
      if (data.device_id) setLoginDeviceId(data.device_id)
      if (data.refresh_token) setRefreshToken(data.refresh_token)
      const up = upsertLoginToSlot(target, {
        token: data.token,
        refreshToken: data.refresh_token || '',
        deviceId: data.device_id || getLoginDeviceId(),
        uid: data.user_id,
        mobile: phoneInput.value,
        nickname: data.username || '',
        loginMethod: 'sms',
      })
      if (!up.ok) {
        loginErr.value = up.message || '写入账号槽失败'
        loginLoading.value = false
        return
      }
      addingAccount.value = false
      swapOnlyMode.value = false
      try { localStorage.removeItem('snipeSwapOnly') } catch {}
      mode.value = 'buy'
      if (loginProxyInput.value.trim()) {
        localStorage.setItem('snipeProxy', loginProxyInput.value.trim())
        if (window._updateProxy) window._updateProxy(loginProxyInput.value.trim())
      }
      applyActiveIboxSession()
      reportIboxPresence(api, data.token, 'ok', { force: true })
      if (!data.refresh_token) {
        store.showToast('已登录但无续期票，建议重试短信登录', 'warn', 4000)
      } else {
        store.showToast(`已登录到槽 ${target + 1}（可长期续期）`, 'success', 2500)
      }
    } else {
      loginErr.value = data.message || '登录失败'
    }
  } catch (e) {
    loginErr.value = e.message || '网络错误'
  }
  loginLoading.value = false
}

async function tokenLogin() {
  if (!store.requireVip()) return
  const pasted = parseIboxAuthPaste(tokenInput.value)
  const t = (pasted.token || tokenInput.value.trim()).replace(/^Bearer\s+/i, '').trim()
  if (!t) { loginErr.value = '请粘贴 Token 或整段抓包头'; return }
  if (pasted.device_id) setLoginDeviceId(pasted.device_id)
  if (pasted.refresh_token) setRefreshToken(pasted.refresh_token)
  tokenInput.value = t
  loginLoading.value = true; loginErr.value = ''
  try {
    const data = await verifyTokenLocal(t)
    if (data.status === 'ok') {
      const target =
        loginTargetSlot.value >= 0 ? loginTargetSlot.value : Math.max(0, firstEmptySlotIndex())
      const rt = pasted.refresh_token || getRefreshToken() || ''
      const did = pasted.device_id || getLoginDeviceId()
      const up = upsertLoginToSlot(target, {
        token: t,
        refreshToken: rt,
        deviceId: did,
        uid: data.user_id || 0,
        mobile: '',
        nickname: '',
        loginMethod: 'token',
      })
      if (!up.ok) {
        loginErr.value = up.message || '写入账号槽失败'
        loginLoading.value = false
        return
      }
      addingAccount.value = false
      swapOnlyMode.value = false
      try { localStorage.removeItem('snipeSwapOnly') } catch {}
      mode.value = 'buy'
      applyActiveIboxSession()
      const ready = {
        hasRefresh: !!rt,
        hasDevice: !!did,
      }
      if (!ready.hasRefresh) {
        loginErr.value = '已登录（易掉）：未解析到 refresh_token。请贴整段抓包或改用短信登录。'
        store.showToast('缺续期票，槽已标「易掉」', 'warn', 4500)
      } else if (!pasted.device_id) {
        loginErr.value = '已登录并保存续期票，但未解析到 APP 的 DEVICE-ID：建议补贴，降低与 APP 互顶概率。'
      } else {
        loginErr.value = ''
        store.showToast(`Token 已写入槽 ${target + 1}`, 'success', 2500)
      }
      reportIboxPresence(api, token.value, 'ok', { force: true })
      if (ready.hasRefresh) tryRefreshIboxSession()
    } else {
      loginErr.value = data.message || 'Token无效'
    }
  } catch (e) {
    loginErr.value = '验证失败: ' + (e.message || '网络错误')
  }
  loginLoading.value = false
}

async function tryRefreshIboxSession() {
  if (!snipePageActive) return
  if (!loggedIn.value && !localStorage.getItem('snipeToken')) return
  try {
    // 提前 2 小时续期；无 refresh 时只检查，不误踢（留给验活接口）
    const r = await ensureFreshIboxToken(api, { slackMs: 2 * 60 * 60 * 1000 })
    if (!snipePageActive) return
    if (r.status === 'ok' && r.refreshed && r.token) {
      token.value = r.token
      reportIboxPresence(api, r.token, 'ok', { force: true })
    } else if (r.auth_expired) {
      // 仅科技页前台才因续期失败清票；在爬仓页后台跑定时器不得劝退
      kickIboxSession(r.message || 'Token已过期，请重新登录')
    } else if (r.warn === 'no_refresh' && r.left_ms != null && r.left_ms < 10 * 60 * 1000) {
      store.showToast('Token 即将过期且无续期票，请重新抓包或改短信登录', 'warn', 4000)
    }
  } catch (_) {}
}

onDeactivated(() => {
  snipePageActive = false
  stopSnipeSessionTimers()
})

onActivated(() => {
  snipePageActive = true
  try {
    const kickMsg = consumeIboxKickMsg()
    if (kickMsg) {
      loginErr.value = kickMsg
      store.showToast(kickMsg, 'warn', 4000)
      applyActiveIboxSession()
      return
    }
  } catch {}
  if (getIboxToken() && loggedIn.value) {
    startSnipeSessionTimers()
  } else if (getIboxToken()) {
    // keep-alive 期间别处同步了票
    token.value = getIboxToken()
    loggedIn.value = true
    startSnipeSessionTimers()
  }
})

function doLogout() {
  buyRunning.value = false; sellRunning.value = false; batchRunning.value = false
  clearInterval(buyTimer); clearInterval(sellTimer); clearInterval(batchTimer)
  addingAccount.value = false
  const r = clearIboxSession()
  applyActiveIboxSession()
  if (r && r.loggedIn) {
    store.showToast('已退出当前号，已切换到其它账号', 'info', 3000)
  } else {
    store.showToast('已退出当前 iBox 账号', 'info', 2000)
  }
}

function doLogoutAll() {
  buyRunning.value = false; sellRunning.value = false; batchRunning.value = false
  clearInterval(buyTimer); clearInterval(sellTimer); clearInterval(batchTimer)
  addingAccount.value = false
  clearAllIboxSlots()
  applyActiveIboxSession()
  store.showToast('已退出全部 iBox 账号', 'info', 2000)
}

function removeAccountSlot(index) {
  clearSlot(index)
  applyActiveIboxSession()
}

// === Search ===
function doSearch() {
  if (!searchQ.value) { searchResults.value = []; return }
  clearTimeout(searchTimer)
  searchTimer = setTimeout(async () => {
    try {
      const r = await api.get('/collections/search', { params: { q: searchQ.value } })
      searchResults.value = (r.data || []).filter(x => x.id > 0)
    } catch {}
  }, 200)
}

function selectColl(r) {
  if (mode.value === 'sell') { sellGid.value = r.id; sellCname.value = r.name }
  else if (mode.value === 'place') { placeGid.value = r.id; placeCname.value = r.name }
  else if (mode.value === 'batch') { batchGid.value = r.id; batchCname.value = r.name }
  else if (mode.value === 'sweep') { sweepGid.value = r.id; sweepCname.value = r.name }
  else if (mode.value === 'swap') { swapGid.value = r.id; swapCname.value = r.name }
  else if (mode.value === 'precision') { precisionGid.value = r.id; precisionCname.value = r.name }
  else if (mode.value === 'rank') {
    rankGid.value = r.id
    rankCname.value = r.name
    rankEstimate.value = null
    rankFloor.value = null
    rankSellMin.value = RANK_HARD_MIN
    // 选中后立刻拉地板并写入底价输入框
    rankFetchFloor({ silent: false })
  }
  else if (mode.value === 'quant') {
    quantGid.value = r.id
    quantCname.value = r.name
    quantFloor.value = null
    quantFetchFloor({ silent: false })
  }
  else { buyGid.value = r.id; buyCname.value = r.name }
  searchQ.value = ''; searchResults.value = []
}

// ========== BUY ==========
async function buyToggle() {
  if (buyRunning.value) { await buyStop() }
  else { await buyStart() }
}

async function buyStop() {
  buyAbort = true
  addLog(buyLogs, '停止本机捡漏...', 'info')
  buyRunning.value = false
  buyTaskId.value = ''
  clearInterval(buyTimer)
  localStorage.removeItem('snipeTaskId')
  addLog(buyLogs, '捡漏已停止', 'error')
  loadHistory()
}

async function buyStart() {
  if (!store.requireVip()) return
  if (!token.value) { loginErr.value = '请先登录'; return }
  clearErrors()
  if (!buyGid.value) { markError('buySearch'); loginErr.value = '请搜索选择藏品'; return }
  if (!buyPrice.value) { markError('buyPrice'); loginErr.value = '请输入目标价'; return }
  if (!buyQty.value) { markError('buyQty'); loginErr.value = '请输入数量'; return }
  let batchGap = parseFloat(buyBatchInterval.value)
  if (!(batchGap > 0)) batchGap = 6
  if (batchGap < 1) batchGap = 1

  // 与上架同一套票：缺 refresh 只警告，不拦启动（短任务/长轮询都允许先跑）
  if (!getRefreshToken()) {
    store.showToast('缺续期票：access 过期后无法自动续，建议本站短信登录或补贴 refresh', 'warn', 4000)
  }

  const platform_token = localStorage.getItem('token') || ''
  if (!platform_token) { loginErr.value = '请先登录网站账号'; return }
  try {
    const gate = await api.post('/snipe/local-fire-gate', null, { params: { platform_token } })
    if (gate.data?.status !== 'ok') {
      loginErr.value = gate.data?.message || 'VIP 校验失败'
      return
    }
  } catch (e) {
    loginErr.value = e.response?.data?.detail || e.message || 'VIP 校验失败'
    return
  }

  buyAbort = false
  buyRunning.value = true
  loginErr.value = ''
  buyLogs.value = []
  buyTaskId.value = 'local-buy'
  localStorage.setItem('buyGid', buyGid.value)
  localStorage.setItem('buyPrice', buyPrice.value)
  localStorage.setItem('buyCname', buyCname.value || '')
  localStorage.setItem('buyMode', buyMode.value || 'cross')
  localStorage.setItem('buyBatchInterval', String(batchGap))
  localStorage.removeItem('snipeTaskId')

  const modeName = (buyModes.find(m => m.key === buyMode.value) || {}).label || buyMode.value
  addLog(buyLogs, '捡漏启动[' + modeName + '/同域反代], 目标≤¥' + (buyPrice.value || '?') + ' x' + buyQty.value, 'buy')

  const pushLog = (msg, type = 'info') => addLog(buyLogs, msg, type)
  buyLocalRun = runBuyLoop({
    token: token.value,
    groupId: buyGid.value,
    targetPrice: parseFloat(buyPrice.value) || 0,
    quantity: parseInt(buyQty.value) || 1,
    buyMode: buyMode.value || 'cross',
    batchInterval: batchGap,
    autoPay: !!buyAutoPay.value,
    payPassword: buyAutoPay.value ? buyPwd.value : '',
    uid: uid.value,
    api,
    wxpusherUid: store.user?.wxpusher_uid || '',
    platformToken: localStorage.getItem('token') || '',
    collectionName: buyCname.value || '',
    onLog: pushLog,
    shouldStop: () => buyAbort || !buyRunning.value,
    onTokenUpdate: (tok) => {
      if (!tok) return
      token.value = tok
      try {
        localStorage.setItem('snipeToken', tok)
        sessionStorage.setItem('snipeToken', tok)
      } catch {}
    },
    onAuthExpired: (reason) => {
      kickIboxSession(reason || '登录已失效，请重新登录')
    },
  }).finally(() => {
    buyRunning.value = false
    buyTaskId.value = ''
    buyLocalRun = null
    loadHistory()
  })
}

// Polling with visibility-aware refresh — prevents background-throttle freeze
function _startBuyPoll() {
  clearInterval(buyTimer)
  buyTimer = visibleInterval(buyPoll, 1500)
}

async function buyPoll() {
  if (!buyRunning.value || !buyTaskId.value) return
  try {
    const r = await api.get('/snipe/status', { params: { task_id: buyTaskId.value, _t: Date.now() } })
    if (r.data.logs) buyLogs.value = [...r.data.logs]
    if (r.data.status === 'stopped') {
      buyRunning.value = false; buyTaskId.value = ''; clearInterval(buyTimer); localStorage.removeItem('snipeTaskId')
    }
  } catch {}
}

// Resume immediately when tab becomes visible
document.addEventListener('visibilitychange', () => {
  if (!document.hidden && buyRunning.value) buyPoll()
})

// ========== SELL ==========
async function sellToggle() {
  if (sellRunning.value) { await sellStop() }
  else { await sellStart() }
}

async function sellStop() {
  sellAbort = true
  addLog(sellLogs, '正在停止本机卖求购…', 'info')
  sellRunning.value = false
  sellTaskId.value = ''
  sellCountdown.value = ''
  clearInterval(sellTimer)
  clearInterval(sellCountdownTimer)
  localStorage.removeItem('sellTaskId')
  addLog(sellLogs, '卖求购已停止', 'error')
}

function parseSellFireDate(raw) {
  let ft = (raw || '').trim()
  if (/^\d{2}:\d{2}$/.test(ft)) ft = ft + ':00'
  if (!/^\d{2}:\d{2}:\d{2}$/.test(ft)) return null
  const [h, m, s] = ft.split(':').map(Number)
  const d = new Date()
  d.setHours(h, m, s, 0)
  return { date: d, label: ft }
}

async function waitUntilSellFire(fireAt) {
  const tick = () => {
    if (!sellRunning.value) return
    const remain = fireAt.getTime() - Date.now()
    if (remain <= 0) { sellCountdown.value = '00:00:00'; return }
    const h = Math.floor(remain / 3600000)
    const m = Math.floor((remain % 3600000) / 60000)
    const sec = Math.floor((remain % 60000) / 1000)
    sellCountdown.value = String(h).padStart(2, '0') + ':' + String(m).padStart(2, '0') + ':' + String(sec).padStart(2, '0')
  }
  tick()
  clearInterval(sellCountdownTimer)
  sellCountdownTimer = setInterval(tick, 200)
  while (!sellAbort && sellRunning.value) {
    const remain = fireAt.getTime() - Date.now()
    if (remain <= 0) {
      sellCountdown.value = '00:00:00'
      clearInterval(sellCountdownTimer)
      return true
    }
    await new Promise(r => setTimeout(r, Math.min(80, remain)))
  }
  clearInterval(sellCountdownTimer)
  return false
}

async function sellStart() {
  if (!store.requireVip()) return
  if (!token.value) { loginErr.value = '请先登录'; return }
  clearErrors()
  if (!sellGid.value) { markError('buySearch'); loginErr.value = '请搜索选择藏品'; return }
  if (!sellPrice.value) { markError('sellPrice'); loginErr.value = '请输入最低接受价'; return }
  if (!consignPwd.value) { markError('consignPwd'); loginErr.value = '请填写寄售密码'; return }
  if (!sellQty.value) { markError('sellQty'); loginErr.value = '请输入数量'; return }

  let sellFireAt = null
  if (sellTimed.value) {
    const parsed = parseSellFireDate(sellFireTime.value)
    if (!parsed) { loginErr.value = '请设置定时开卖的时分秒'; return }
    const late = (Date.now() - parsed.date.getTime()) / 1000
    if (late > 10) { loginErr.value = '开火时间已过 ' + Math.floor(late) + 's，请改时间后再启动'; return }
    sellFireAt = parsed.date
  }

  const platform_token = localStorage.getItem('token') || ''
  if (!platform_token) { loginErr.value = '请先登录网站账号'; return }
  try {
    const gate = await api.post('/snipe/local-fire-gate', null, { params: { platform_token } })
    if (gate.data?.status !== 'ok') {
      loginErr.value = gate.data?.message || 'VIP 校验失败'
      return
    }
  } catch (e) {
    loginErr.value = e.response?.data?.detail || e.message || 'VIP 校验失败'
    return
  }

  sellAbort = false
  sellRunning.value = true
  loginErr.value = ''
  sellLogs.value = []
  sellCountdown.value = ''
  sellTaskId.value = 'local-sell'
  localStorage.removeItem('sellTaskId')
  addLog(sellLogs, '卖求购启动[本机直连], 目标≥¥' + (sellPrice.value || '?') + ' x' + sellQty.value, 'buy')

  if (sellFireAt) {
    addLog(sellLogs, '定时 ' + sellFireTime.value + (sellFireTime.value.length === 5 ? ':00' : '') + ' 开卖', 'info')
    const reached = await waitUntilSellFire(sellFireAt)
    if (!reached || sellAbort || !sellRunning.value) {
      sellCountdown.value = ''
      sellRunning.value = false
      sellTaskId.value = ''
      return
    }
    addLog(sellLogs, '到点开火，立即卖求购', 'buy')
  }

  sellLocalRun = runSellLoop({
    token: token.value,
    groupId: sellGid.value,
    targetPrice: parseFloat(sellPrice.value) || 0,
    consignPassword: consignPwd.value,
    quantity: parseInt(sellQty.value) || 1,
    uid: uid.value,
    api,
    wxpusherUid: store.user?.wxpusher_uid || '',
    platformToken: localStorage.getItem('token') || '',
    collectionName: sellCname.value || buyCname.value || '',
    onLog: (msg, type = 'info') => addLog(sellLogs, msg, type),
    shouldStop: () => sellAbort || !sellRunning.value,
  }).finally(() => {
    sellRunning.value = false
    sellTaskId.value = ''
    sellCountdown.value = ''
    sellLocalRun = null
    loadHistory()
  })
}

// ========== PLACE 顶求购 ==========
async function placeStart() {
  if (!store.requireVip()) return
  if (!token.value) { loginErr.value = '请先登录'; return }
  clearErrors()
  if (!placeGid.value) { markError('buySearch'); loginErr.value = '请搜索选择藏品'; return }
  if (!placePrice.value) { markError('placePrice'); loginErr.value = '请输入求购价'; return }
  if (!placeQty.value) { markError('placeQty'); loginErr.value = '请输入数量'; return }
  if (placeAutoPay.value && !placePwd.value) { markError('placePwd'); loginErr.value = '自动支付需填写支付密码'; return }

  const platform_token = localStorage.getItem('token') || ''
  if (!platform_token) { loginErr.value = '请先登录网站账号'; return }
  try {
    const gate = await api.post('/snipe/local-fire-gate', null, { params: { platform_token } })
    if (gate.data?.status !== 'ok') {
      loginErr.value = gate.data?.message || 'VIP 校验失败'
      return
    }
  } catch (e) {
    loginErr.value = e.response?.data?.detail || e.message || 'VIP 校验失败'
    return
  }

  placeBusy.value = true
  loginErr.value = ''
  placeLogs.value = []
  addLog(placeLogs, `顶求购启动[本机直连] ${placeCname.value || placeGid.value} ¥${placePrice.value} x${placeQty.value}`, 'info')
  try {
    const r = await runPlacePurchase({
      token: token.value,
      groupId: placeGid.value,
      price: parseFloat(placePrice.value) || 0,
      quantity: parseInt(placeQty.value) || 1,
      payPassword: placeAutoPay.value ? placePwd.value : '',
      autoPay: !!placeAutoPay.value,
      collectionName: placeCname.value,
      api,
      wxpusherUid: store.user?.wxpusher_uid || '',
      platformToken: platform_token,
      onLog: (msg, type = 'info') => addLog(placeLogs, msg, type),
    })
    if (r.status === 'ok') {
      if (r.order_id) addLog(placeLogs, '订单 ' + r.order_id, 'info')
      if (r.order_uuid) addLog(placeLogs, '支付单 ' + r.order_uuid, 'info')
    }
  } catch (e) {
    addLog(placeLogs, '请求异常: ' + (e.message || '网络错误'), 'error')
  }
  placeBusy.value = false
}

function _startSellPoll() {
  clearInterval(sellTimer)
  sellTimer = visibleInterval(sellPoll, 1500)
}

async function sellPoll() {
  // 本机直连卖求购无需轮询云端状态
}

document.addEventListener('visibilitychange', () => {
  if (!document.hidden && sellRunning.value) sellPoll()
})

// ========== BATCH ==========
async function batchToggle(action) {
  if (batchStarting.value) return
  if (batchRunning.value) { await batchStop(); return }
  await batchStart(action)
}

async function batchStop() {
  batchAbort = true
  addLog(batchLogs, '停止本机上下架...', 'info')
  batchRunning.value = false
  batchJobId.value = ''
  clearInterval(batchTimer)
  localStorage.removeItem('batchJobId')
  addLog(batchLogs, '批量任务已停止', 'error')
}

async function batchStart(action) {
  if (!store.requireVip()) return
  if (!token.value) { loginErr.value = '请先登录'; return }
  if (!batchGid.value) { loginErr.value = '请先搜索选择藏品'; return }
  if (action === 'list' && !consignPwd.value) { loginErr.value = '上架需要填写寄售密码'; return }
  if (batchStarting.value || batchRunning.value) return
  const platform_token = localStorage.getItem('token') || ''
  if (!platform_token) { loginErr.value = '请先登录网站账号'; return }
  batchStarting.value = true
  loginErr.value = ''
  if (!batchLogs.value.length) batchLogs.value = []
  addLog(batchLogs, '正在启动本机直连…', 'info')
  try {
    const gate = await api.post('/snipe/local-fire-gate', null, { params: { platform_token } })
    if (gate.data?.status !== 'ok') {
      addLog(batchLogs, '启动失败: ' + (gate.data?.message || 'VIP 校验失败'), 'error')
      batchStarting.value = false
      return
    }
  } catch (e) {
    const detail = e?.response?.data?.detail || e?.message || 'VIP 校验失败'
    addLog(batchLogs, '启动失败: ' + detail, 'error')
    batchStarting.value = false
    return
  }

  batchAbort = false
  batchRunning.value = true
  batchJobId.value = 'local-batch'
  localStorage.removeItem('batchJobId')
  const qty = parseInt(batchQty.value) || 0
  const label = action === 'list' ? '批量上架' : '批量下架'
  addLog(batchLogs, label + '已启动(本机直连), ' + (qty || '全部') + '件', 'buy')
  batchStarting.value = false

  const pushLog = (msg, type = 'info') => addLog(batchLogs, msg, type)
  const runner =
    action === 'list'
      ? runBatchList({
          token: token.value,
          groupId: batchGid.value,
          price: parseFloat(batchPrice.value) || 0,
          consignPassword: consignPwd.value,
          quantity: qty,
          uid: uid.value,
          onLog: pushLog,
          shouldStop: () => batchAbort || !batchRunning.value,
        })
      : runBatchUnlist({
          token: token.value,
          groupId: batchGid.value,
          quantity: qty,
          collectionName: batchCname.value || '',
          safeMode: batchSafeMode.value,
          uid: uid.value,
          onLog: pushLog,
          shouldStop: () => batchAbort || !batchRunning.value,
        })

  batchLocalRun = runner.finally(() => {
    batchRunning.value = false
    batchJobId.value = ''
    batchLocalRun = null
  })
}

async function batchPoll() {
  if (!batchJobId.value) return
  try {
    const r = await api.get('/snipe/batch-status', { params: { job_id: batchJobId.value }, timeout: 10000 })
    if (r.data.logs && r.data.logs.length) {
      batchLogs.value = r.data.logs
      batchPollMiss = 0
    }
    if (r.data.status === 'running') {
      batchPollMiss = 0
      return
    }
    if (r.data.status === 'stopped') {
      batchRunning.value = false
      batchJobId.value = ''
      clearInterval(batchTimer)
      localStorage.removeItem('batchJobId')
      const last = batchLogs.value[0]?.msg || ''
      if (last && !last.includes('完成')) {
        addLog(batchLogs, '任务已结束', 'info')
      }
      return
    }
    if (r.data.status === 'not_found') {
      batchPollMiss++
      if (batchPollMiss < BATCH_POLL_GRACE) return
      addLog(batchLogs, '任务状态丢失(可能仍在后台)，请查看历史任务', 'error')
      batchRunning.value = false
      batchJobId.value = ''
      clearInterval(batchTimer)
      localStorage.removeItem('batchJobId')
    }
  } catch {}
}

// ========== SWEEP ==========
async function sweepToggle() {
  if (sweepRunning.value) { await sweepStop() }
  else { await sweepStart() }
}

async function sweepStop() {
  addLog(sweepLogs, '停止全部任务...', 'info')
  try { await api.post('/snipe/stop-all', null, { params: { platform_token: localStorage.getItem('token') || '', token: token.value || localStorage.getItem('snipeToken') || '' } }) } catch {}
  sweepRunning.value = false; sweepJobId.value = ''; clearInterval(sweepTimer)
  localStorage.removeItem('sweepJobId')
  addLog(sweepLogs, '扫货已停止', 'error')
}

function doMarkerSearch() {
  if (!sweepMarkerSearch.value) { sweepMarkerResults.value = []; return }
  clearTimeout(sweepMarkerTimer)
  sweepMarkerTimer = setTimeout(async () => {
    try {
      const r = await api.get('/collections/search', { params: { q: sweepMarkerSearch.value } })
      sweepMarkerResults.value = (r.data || []).filter(x => x.id > 0).slice(0, 5)
    } catch {}
  }, 200)
}

function resetSweepWarehouse() {
  sweepAutoSelectGen += 1
  clearTimeout(sweepAutoSelectTimer)
  sweepAutoSelecting.value = false
  sweepAutoSelectMsg.value = ''
  sweepWhGroups.value = []
  sweepWhItems.value = []
  sweepWhPage.value = 1
  sweepWhHasMore.value = false
  sweepWhLoading.value = false
  sweepSelected.value = []
  sweepGid.value = 0
  sweepCname.value = ''
}

function clearSweepSeller() {
  sweepSeller.value = null
  sweepSellerConfirm.value = null
  resetSweepWarehouse()
}

function selectMarker(r) {
  sweepMarkerGid.value = r.id
  sweepMarkerCname.value = r.name
  sweepMarkerSearch.value = ''
  sweepMarkerResults.value = []
  clearSweepSeller()
  loadMarkerOrders(true)
}

function onMarkerOrdersScroll(e) {
  const el = e.target
  if (!el) return
  if (el.scrollTop + el.clientHeight >= el.scrollHeight - 48) {
    loadMarkerOrders(false)
  }
}

async function loadMarkerOrders(reset) {
  if (!token.value) { loginErr.value = '请先登录'; return }
  if (!sweepMarkerGid.value) return
  if (sweepMarkerLoading.value) return
  if (!reset && !sweepMarkerHasMore.value) return
  if (reset) {
    sweepMarkerSortValues.value = ''
    sweepMarkerOrders.value = []
    sweepMarkerHasMore.value = false
  }
  sweepMarkerLoading.value = true
  loginErr.value = ''
  try {
    const r = await api.post('/snipe/sweep-marker-orders', {
      token: token.value,
      marker_gid: sweepMarkerGid.value,
      sort_values: sweepMarkerSortValues.value,
      page_size: 20,
      platform_token: localStorage.getItem('token') || '',
      proxy: getProxy(),
    })
    if (r.data.status === 'ok') {
      const items = r.data.items || []
      const seen = new Set(
        sweepMarkerOrders.value.map(o => o.order_id || String(o.digital_collection_id))
      )
      const fresh = items.filter(o => {
        const k = o.order_id || String(o.digital_collection_id)
        if (!k || seen.has(k)) return false
        seen.add(k)
        return true
      })
      sweepMarkerOrders.value = reset ? items : sweepMarkerOrders.value.concat(fresh)
      const nextSv = r.data.next_sort_values || ''
      sweepMarkerSortValues.value = nextSv
      sweepMarkerHasMore.value = !!r.data.has_more && !!nextSv
      if (!reset && !fresh.length) sweepMarkerHasMore.value = false
    } else {
      loginErr.value = r.data.message || '挂单加载失败'
    }
  } catch {
    loginErr.value = '挂单加载失败'
  }
  sweepMarkerLoading.value = false
}

async function pickMarkerOrder(order) {
  if (!token.value) { loginErr.value = '请先登录'; return }
  if (!order?.digital_collection_id) return
  loginErr.value = ''
  try {
    const r = await api.post('/snipe/sweep-resolve-seller', {
      token: token.value,
      digital_collection_id: order.digital_collection_id,
      platform_token: localStorage.getItem('token') || '',
      proxy: getProxy(),
    })
    if (r.data.status === 'ok') {
      sweepSellerConfirm.value = {
        sso: r.data.seller_sso,
        uid: r.data.seller_uid || 0,
        name: r.data.seller_name || order.seller_name || '未知卖家',
        markerOrderId: order.order_id || '',
        markerGid: sweepMarkerGid.value,
        digitalCollectionId: order.digital_collection_id,
      }
    } else {
      loginErr.value = r.data.message || '无法解析卖家，请换一单'
    }
  } catch {
    loginErr.value = '解析卖家失败，请换一单'
  }
}

function confirmSweepSeller() {
  if (!sweepSellerConfirm.value) return
  sweepSeller.value = { ...sweepSellerConfirm.value }
  sweepSellerConfirm.value = null
  resetSweepWarehouse()
  loadWarehouseGroups()
}

function cancelSweepSellerConfirm() {
  sweepSellerConfirm.value = null
}

function reselectSweepSeller() {
  clearSweepSeller()
}

async function loadWarehouseGroups() {
  if (!token.value || !sweepSeller.value?.sso) return
  sweepWhLoading.value = true
  loginErr.value = ''
  try {
    const r = await api.post('/snipe/sweep-warehouse', {
      token: token.value,
      seller_sso: sweepSeller.value.sso,
      group_id: 0,
      page: 1,
      page_size: 50,
      platform_token: localStorage.getItem('token') || '',
      proxy: getProxy(),
    })
    if (r.data.status === 'ok') {
      sweepWhGroups.value = r.data.groups || []
      if (!sweepWhGroups.value.length) {
        loginErr.value = '卖家仓库为空或不可见'
      }
    } else {
      loginErr.value = r.data.message || '仓库加载失败'
    }
  } catch {
    loginErr.value = '仓库加载失败'
  }
  sweepWhLoading.value = false
}

function selectWhGroup(g) {
  if (!g?.group_id) return
  sweepGid.value = g.group_id
  sweepCname.value = g.name || ''
  sweepSelected.value = []
  scheduleAutoSelectWh(0)
}

function onWhItemsScroll(e) {
  const el = e.target
  if (!el || sweepAutoSelecting.value) return
  if (el.scrollTop + el.clientHeight >= el.scrollHeight - 48) {
    loadWarehouseItems(false)
  }
}

function scheduleAutoSelectWh(delayMs = 350) {
  clearTimeout(sweepAutoSelectTimer)
  sweepAutoSelectTimer = setTimeout(() => { autoSelectWhByPriceQty() }, delayMs)
}

async function autoSelectWhByPriceQty() {
  const gen = ++sweepAutoSelectGen
  const maxP = parseFloat(sweepMaxPrice.value)
  const N = parseInt(sweepQty.value) || 0
  if (!token.value || !sweepSeller.value?.sso || !sweepGid.value) {
    sweepAutoSelectMsg.value = ''
    return
  }
  if (!(maxP > 0) || N < 1) {
    sweepAutoSelectMsg.value = ''
    return
  }

  sweepAutoSelecting.value = true
  sweepAutoSelectMsg.value = '自动勾选中…'
  sweepSelected.value = []
  sweepWhPage.value = 1
  sweepWhItems.value = []
  sweepWhHasMore.value = true
  loginErr.value = ''

  const candidates = []
  try {
    while (candidates.length < N && gen === sweepAutoSelectGen) {
      if (!sweepWhHasMore.value && sweepWhItems.value.length > 0 && sweepWhPage.value > 1) break
      // First page: hasMore starts true; stop when API says no more after a fetch
      const page = sweepWhPage.value
      if (page > 1 && !sweepWhHasMore.value) break

      sweepWhLoading.value = true
      const r = await api.post('/snipe/sweep-warehouse', {
        token: token.value,
        seller_sso: sweepSeller.value.sso,
        group_id: sweepGid.value,
        page,
        page_size: 20,
        platform_token: localStorage.getItem('token') || '',
        proxy: getProxy(),
      })
      if (gen !== sweepAutoSelectGen) return

      if (r.data.status !== 'ok') {
        loginErr.value = r.data.message || '仓库明细加载失败'
        sweepAutoSelectMsg.value = ''
        break
      }
      const items = (r.data.items || []).map(it => ({
        ...it,
        group_id: sweepGid.value,
      }))
      sweepWhItems.value = page === 1 ? items : sweepWhItems.value.concat(items)
      const hasMore = !!r.data.has_more
      sweepWhHasMore.value = hasMore
      sweepWhPage.value = page + 1

      for (const it of items) {
        if (!it?.digital_collection_id) continue
        if (!sweepItemHasPrice(it)) continue
        const p = parseFloat(it.price)
        if (p > maxP + 0.009) continue
        if (candidates.some(c => c.digital_collection_id === it.digital_collection_id)) continue
        candidates.push({
          digital_collection_id: it.digital_collection_id,
          token_id: String(it.token_id || ''),
          price: p,
          group_id: it.group_id || sweepGid.value || 0,
        })
      }

      if (!items.length || !hasMore) break
    }

    if (gen !== sweepAutoSelectGen) return
    candidates.sort((a, b) => a.price - b.price)
    sweepSelected.value = candidates.slice(0, N)
    const x = sweepSelected.value.length
    sweepAutoSelectMsg.value = x >= N
      ? `已自动勾选 ${x}/${N}`
      : `仅找到 ${x} 件符合（目标 ${N}）`
  } catch {
    if (gen === sweepAutoSelectGen) {
      loginErr.value = '仓库明细加载失败'
      sweepAutoSelectMsg.value = ''
    }
  } finally {
    if (gen === sweepAutoSelectGen) {
      sweepAutoSelecting.value = false
      sweepWhLoading.value = false
    }
  }
}

async function loadWarehouseItems(reset) {
  if (!token.value || !sweepSeller.value?.sso || !sweepGid.value) return
  if (sweepWhLoading.value || sweepAutoSelecting.value) return
  if (!reset && !sweepWhHasMore.value) return
  if (reset) {
    sweepWhPage.value = 1
    sweepWhItems.value = []
    sweepWhHasMore.value = false
  }
  sweepWhLoading.value = true
  loginErr.value = ''
  try {
    const r = await api.post('/snipe/sweep-warehouse', {
      token: token.value,
      seller_sso: sweepSeller.value.sso,
      group_id: sweepGid.value,
      page: sweepWhPage.value,
      page_size: 20,
      platform_token: localStorage.getItem('token') || '',
      proxy: getProxy(),
    })
    if (r.data.status === 'ok') {
      const items = (r.data.items || []).map(it => ({
        ...it,
        group_id: sweepGid.value,
      }))
      sweepWhItems.value = reset ? items : sweepWhItems.value.concat(items)
      sweepWhHasMore.value = !!r.data.has_more
      if (items.length || sweepWhHasMore.value) {
        sweepWhPage.value = (sweepWhPage.value || 1) + 1
      }
    } else {
      loginErr.value = r.data.message || '仓库明细加载失败'
    }
  } catch {
    loginErr.value = '仓库明细加载失败'
  }
  sweepWhLoading.value = false
}

function sweepItemHasPrice(it) {
  const p = parseFloat(it?.price)
  return Number.isFinite(p) && p > 0
}

function isWhItemOverpriced(it) {
  const maxP = parseFloat(sweepMaxPrice.value)
  if (!sweepMaxPrice.value || !(maxP > 0)) return false
  if (!sweepItemHasPrice(it)) return false
  return parseFloat(it.price) > maxP
}

function isWhItemSelected(it) {
  const id = it?.digital_collection_id
  if (!id) return false
  return sweepSelected.value.some(x => x.digital_collection_id === id)
}

function canToggleWhItem(it) {
  if (isWhItemSelected(it)) return true
  if (isWhItemOverpriced(it)) return false
  const N = parseInt(sweepQty.value) || 1
  return sweepSelected.value.length < N
}

function toggleWhItem(it) {
  if (!it?.digital_collection_id) return
  const idx = sweepSelected.value.findIndex(x => x.digital_collection_id === it.digital_collection_id)
  if (idx >= 0) {
    sweepSelected.value.splice(idx, 1)
    return
  }
  if (isWhItemOverpriced(it)) return
  const N = parseInt(sweepQty.value) || 1
  if (sweepSelected.value.length >= N) return
  sweepSelected.value.push({
    digital_collection_id: it.digital_collection_id,
    token_id: String(it.token_id || ''),
    price: sweepItemHasPrice(it) ? parseFloat(it.price) : 0,
    group_id: it.group_id || sweepGid.value || 0,
  })
}

async function sweepStart() {
  if (!store.requireVip()) return
  if (!token.value) { loginErr.value = '请先登录'; return }
  if (!sweepSeller.value) { loginErr.value = '未确认卖家'; return }
  if (!sweepSelected.value.length) { loginErr.value = '未勾选目标'; return }
  const maxPrice = parseFloat(sweepMaxPrice.value) || 0
  if (!(maxPrice > 0)) { loginErr.value = '请填写最高接受价'; return }
  const quantity = parseInt(sweepQty.value) || 1
  if (quantity < 1) { loginErr.value = '请填写数量'; return }
  const groupId = sweepGid.value || sweepSelected.value[0]?.group_id || 0
  sweepRunning.value = true; loginErr.value = ''; sweepLogs.value = []
  try {
    const r = await api.post('/snipe/sweep-buy', {
      token: token.value,
      seller_sso: sweepSeller.value.sso,
      seller_name: sweepSeller.value.name || '',
      seller_uid: sweepSeller.value.uid || 0,
      marker_gid: sweepMarkerGid.value || sweepSeller.value.markerGid || 0,
      group_id: groupId,
      max_price: maxPrice,
      quantity,
      selected_items: sweepSelected.value.map(it => ({
        digital_collection_id: it.digital_collection_id,
        token_id: String(it.token_id || ''),
        price: it.price || 0,
        group_id: it.group_id || 0,
      })),
      auto_pay: sweepAutoPay.value,
      pay_password: sweepAutoPay.value ? consignPwd.value : '',
      wxpusher_uid: store.user?.wxpusher_uid || '',
      platform_token: localStorage.getItem('token') || '',
      proxy: getProxy(),
    })
    if (r.data.status === 'ok') {
      sweepJobId.value = r.data.job_id
      localStorage.setItem('sweepJobId', r.data.job_id)
      addLog(sweepLogs, '扫货启动: ' + (sweepCname.value || sweepSeller.value.name || '点对点'), 'buy')
      sweepTimer = visibleInterval(sweepPoll, 1000)
    } else {
      addLog(sweepLogs, '启动失败: ' + (r.data.message || '未知'), 'error')
      sweepRunning.value = false
    }
  } catch { addLog(sweepLogs, '启动失败', 'error'); sweepRunning.value = false }
}

async function sweepPoll() {
  if (!sweepJobId.value) return
  try {
    const r = await api.get('/snipe/batch-status', { params: { job_id: sweepJobId.value } })
    if (r.data.logs && r.data.logs.length) sweepLogs.value = r.data.logs
    if (r.data.status === 'stopped') {
      sweepRunning.value = false; sweepJobId.value = ''; clearInterval(sweepTimer); localStorage.removeItem('sweepJobId')
    }
  } catch {}
}

// ========== SWAP (互刷) ==========
async function swapToggle() {
  if (swapRunning.value) { await swapStop(); return }
  await swapStart()
}
async function swapStop() {
  addLog(swapLogs, '停止全部任务...', 'info')
  try {
    if (swapJobId.value) {
      await api.post('/snipe/swap-stop', null, { params: { job_id: swapJobId.value } })
    }
    await api.post('/snipe/stop-all', null, { params: { platform_token: localStorage.getItem('token') || '', token: token.value || localStorage.getItem('snipeToken') || '' } })
  } catch {}
  swapRunning.value = false; swapJobId.value = ''; clearInterval(swapTimer)
  addLog(swapLogs, '互刷已停止，可改价后重新开始', 'error')
}
async function swapStart() {
  if (!store.requireVip()) return
  // 互刷只用大小号 token，不要求科技页主号登录（避免顶号）
  if (!swapTokenA.value || !swapTokenB.value) { loginErr.value = '请先登录大小号(手机或Token)'; return }
  if (!swapGid.value) { loginErr.value = '请先搜索选择藏品'; return }
  if (!swapPrice.value || parseFloat(swapPrice.value) <= 0) { loginErr.value = '请填写挂单价'; return }
  if (!swapCount.value || parseInt(swapCount.value) < 1) { loginErr.value = '请填写件数'; return }
  if (!swapRounds.value || parseInt(swapRounds.value) < 1) { loginErr.value = '请填写轮数'; return }
  swapRunning.value = true; loginErr.value = ''; swapLogs.value = []
  const rounds = parseInt(swapRounds.value)
  const qty = parseInt(swapCount.value)
  try {
    const r = await api.post('/snipe/start-swap', {
      token_a: swapTokenA.value, token_b: swapTokenB.value,
      group_id: swapGid.value, target_price: parseFloat(swapPrice.value) || 0,
      swap_count: qty,
      swap_rounds: rounds,
      collection_name: swapCname.value, consign_password: consignPwd.value,
      pay_password_a: swapPayA.value, pay_password_b: swapPayB.value,
      platform_token: localStorage.getItem('token') || '',
      wxpusher_uid: store.user?.wxpusher_uid || '',
      proxy: getProxy(),
    })
    if (r.data.status === 'ok') {
      swapJobId.value = r.data.job_id
      persistSwapTokens()
      addLog(swapLogs, '互刷启动 ' + rounds + '轮×' + qty + '件 Y' + (swapPrice.value || '?'), 'buy')
      swapTimer = visibleInterval(swapPoll, 2000)
    } else {
      addLog(swapLogs, '启动失败: ' + (r.data.message || '未知'), 'error')
      swapRunning.value = false
    }
  } catch { addLog(swapLogs, '启动失败', 'error'); swapRunning.value = false }
}
async function swapPoll() {
  if (!swapRunning.value || !swapJobId.value) return
  try {
    const r = await api.get('/snipe/swap-status', { params: { job_id: swapJobId.value, _t: Date.now() } })
    if (r.data.logs) swapLogs.value = [...r.data.logs]
    if (r.data.status === 'stopped') {
      swapRunning.value = false; swapJobId.value = ''; clearInterval(swapTimer)
    }
  } catch {}
}

document.addEventListener('visibilitychange', () => {
  if (!document.hidden && swapRunning.value) swapPoll()
})

// ========== SYNTH ==========
let synthSearchTimer = null

async function doSynthSearch() {
  if (!synthSearch.value) { synthResults.value = []; return }
  clearTimeout(synthSearchTimer)
  synthSearchTimer = setTimeout(async () => {
    try {
      const r = await api.post('/snipe/synth-activities', { q: synthSearch.value, token: token.value, proxy: await ensureProxy() })
      synthResults.value = r.data.activities || []
    } catch {}
  }, 300)
}

async function fetchAllSynth() {
  try {
    const r = await api.post('/snipe/synth-activities', { q: '', token: token.value, proxy: await ensureProxy() })
    synthResults.value = r.data.activities || []
  } catch {}
}

async function selectSynth(a) {
  synthSelected.value = a
  synthChannels.value = []
  synthChannelId.value = 0
  synthMaterials.value = []
  synthChecked.value = new Set()
  synthSearch.value = ''; synthResults.value = []
  // Auto-set fire time = activity start - 0.5s
  if (a.startTime) {
    const t = typeof a.startTime === 'number' ? new Date(a.startTime < 1e12 ? a.startTime * 1000 : a.startTime) : new Date(a.startTime.replace(' ', 'T'))
    t.setSeconds(t.getSeconds() - 0.5)
    synthFireTime.value = t.toTimeString().slice(0, 8)
  }
  // Auto-fetch detail for channels
  if (token.value) {
    try {
      const r = await api.post('/snipe/synth-activity/' + a.id, { token: token.value, proxy: await ensureProxy() })
      if (r.data.activity) {
        const detail = r.data.activity
        synthChannels.value = detail.channels || []
        synthMaterials.value = detail.materials || []
        // Auto-select first channel
        if (synthChannels.value.length > 0) {
          selectChannel(synthChannels.value[0].id)
        }
      }
    } catch {}
  }
}

async function selectChannel(cid) {
  synthChannelId.value = cid
  if (!token.value) return
  synthLoading.value = true
  const proxy = await ensureProxy()
  const r = await api.post('/snipe/synth-channel/' + cid, { token: token.value, proxy: proxy })
  _allMaterials.value = r.data.materials || []
  const map = {}
  for (const m of _allMaterials.value) { if (m.albumId) map[m.gid] = m.albumId }
  synthAlbumMap.value = map
  synthChecked.value = new Set()
  synthOwned.value = {}
  // 批量查持仓：一次请求，后端多线程并发查
  const uniqueIds = [...new Set(_allMaterials.value.map(m => m.albumId))]
  try {
    const hr = await api.get('/snipe/my-holdings-batch', { params: { gids: uniqueIds.join(','), token: token.value, proxy: proxy } })
    const holdings = hr.data.holdings || {}
    for (const m of _allMaterials.value) {
      synthOwned.value[m.albumId] = holdings[m.albumId] || 0
    }
  } catch {}
  applyMaterialFilter()
  synthLoading.value = false
}

function applyMaterialFilter() {
  if (synthOwnedFilter.value) {
    synthMaterials.value = _allMaterials.value.filter(m => (synthOwned.value[m.albumId] || 0) > 0)
  } else {
    synthMaterials.value = _allMaterials.value
  }
}

function toggleOwnedFilter() {
  synthOwnedFilter.value = !synthOwnedFilter.value
  applyMaterialFilter()
}

function toggleMaterial(albumId) {
  const s = new Set(synthChecked.value)
  if (s.has(albumId)) s.delete(albumId)
  else s.add(albumId)
  synthChecked.value = s
}

async function synthToggle() {
  if (synthRunning.value) { await synthStop(); return }
  await synthStart()
}

async function synthStop() {
  const tid = synthTaskId
  synthRunning.value = false
  clearInterval(synthTimer)
  synthTimer = null
  synthCountdown.value = ''
  synthTaskId = ''
  if (tid) {
    try {
      await api.post('/snipe/stop-all', null, {
        params: {
          platform_token: localStorage.getItem('token') || '',
          token: token.value || '',
        },
      })
    } catch {}
  }
  addLog(synthLogs, '抢合已停止', 'error')
}

async function synthPoll() {
  if (!synthRunning.value || !synthTaskId) return
  try {
    const r = await api.get('/snipe/status', { params: { task_id: synthTaskId, _t: Date.now() } })
    if (Array.isArray(r.data?.logs)) synthLogs.value = r.data.logs.slice(0, 200)
    const wait = Number(r.data?.wait_ms || 0)
    synthCountdown.value = wait > 0 ? fmtSynthCountdown(wait) : ''
    if (r.data?.status === 'stopped') {
      synthRunning.value = false
      synthTaskId = ''
      clearInterval(synthTimer)
      synthTimer = null
      synthCountdown.value = ''
      refreshSynthQuota()
    }
  } catch {}
}

function fmtSynthCountdown(ms) {
  if (ms <= 0) return '00:00:00.000'
  const h = Math.floor(ms / 3600000)
  const m = Math.floor((ms % 3600000) / 60000)
  const s = Math.floor((ms % 60000) / 1000)
  const mil = ms % 1000
  return `${String(h).padStart(2,'0')}:${String(m).padStart(2,'0')}:${String(s).padStart(2,'0')}.${String(mil).padStart(3,'0')}`
}

async function synthStart() {
  if (!store.requireVip()) return
  if (!token.value) { loginErr.value = '请先登录'; return }
  if (!synthSelected.value) { loginErr.value = '请先搜索选择合成活动'; return }
  const cid = synthChannelId.value || 0
  if (!cid) { loginErr.value = '请先选择合成通道'; return }
  await refreshSynthQuota()
  // 网站抢合不限次；额度拦截仅 APP /local/consume
  const platformToken = localStorage.getItem('token') || ''
  synthRunning.value = true
  loginErr.value = ''
  synthLogs.value = []
  let fireTime = ''
  const ft = synthFireTime.value
  if (ft && /^\d{2}:\d{2}(:\d{2})?$/.test(ft)) fireTime = ft.length === 5 ? ft + ':00' : ft
  const batchHint = synthBatchChunk.value === 10 ? '每次10' : (synthAllowBatch.value ? '可批量' : '每次1次')
  addLog(synthLogs, '站点转发 · ' + batchHint + (fireTime ? ' · 定时 ' + fireTime : ' · 立即'), 'buy')
  try {
    const r = await api.post('/snipe/synth-snipe', {
      token: token.value,
      synthetic_id: synthSelected.value.id,
      synthetic_num: parseInt(synthQty.value) || 1,
      album_ids: Array.from(synthChecked.value),
      platform_token: platformToken,
      activity_id: synthSelected.value.id,
      channel_id: cid,
      activity_name: synthSelected.value.name || '',
      fire_time: fireTime,
      allow_batch: synthBatchChunk.value !== 1 && synthAllowBatch.value,
      batch_chunk: synthBatchChunk.value === 10 ? 10 : (synthBatchChunk.value === 1 ? 1 : 0),
      early_ms: 800,
      threads: 1,
      proxy: '',
    })
    if (r.data?.quota) {
      synthQuota.value = {
        used: r.data.quota.used || 0,
        limit: r.data.quota.limit || 2,
        remaining: r.data.quota.remaining ?? 0,
        unlimited: !!r.data.quota.unlimited,
      }
    }
    if (r.data?.status !== 'ok' || !r.data?.task_id) {
      addLog(synthLogs, r.data?.message || '派发失败', 'error')
      synthRunning.value = false
      return
    }
    if (Array.isArray(r.data.logs) && r.data.logs.length) synthLogs.value = r.data.logs
    synthTaskId = r.data.task_id
    clearInterval(synthTimer)
    synthTimer = visibleInterval(synthPoll, 400)
  } catch (e) {
    addLog(synthLogs, '派发失败: ' + (e.response?.data?.detail || e.message || '网络'), 'error')
    synthRunning.value = false
  }
}

// ========== PRECISION SELL ==========
async function loadPrecisionOrders(page) {
  if (!precisionGid.value || !token.value) return
  precisionOrdersLoading.value = true
  try {
    const r = await fetchPurchaseOrders({
      token: token.value,
      groupId: precisionGid.value,
      page: page || 1,
      uid: uid.value,
    })
    if (r.status === 'ok') {
      precisionOrders.value = r.orders || []
      precisionOrdersTotal.value = r.total || 0
      precisionOrdersPage.value = page || 1
    }
  } catch (e) {}
  precisionOrdersLoading.value = false
}
function selectPrecisionOrder(order) {
  precisionSelectedOrder.value = order
  precisionSelectedHolding.value = null
  precisionResult.value = ''
}
async function loadPrecisionHoldings() {
  if (!precisionGid.value || !token.value) return
  precisionHoldingsLoading.value = true
  try {
    const r = await fetchHoldingsDetail({
      token: token.value,
      groupId: precisionGid.value,
      uid: uid.value,
    })
    if (r && r.status === 'ok') precisionHoldings.value = r.items || []
    if (!precisionHoldings.value.length) precisionResult.value = '无持仓'
  } catch (e) { precisionResult.value = '加载失败' }
  precisionHoldingsLoading.value = false
}
async function doPrecisionSell() {
  if (!store.requireVip()) return
  if (!precisionSelectedOrder.value) { precisionResult.value = '请选求购单'; return }
  if (!precisionSelectedHolding.value) { precisionResult.value = '请选藏品'; return }
  if (!precisionPwd.value) { precisionResult.value = '请输入寄售密码'; return }

  const platform_token = localStorage.getItem('token') || ''
  if (!platform_token) { precisionResult.value = '请先登录网站账号'; return }
  try {
    const gate = await api.post('/snipe/local-fire-gate', null, { params: { platform_token } })
    if (gate.data?.status !== 'ok') {
      precisionResult.value = gate.data?.message || 'VIP 校验失败'
      return
    }
  } catch (e) {
    precisionResult.value = e.response?.data?.detail || e.message || 'VIP 校验失败'
    return
  }

  precisionRunning.value = true; precisionResult.value = '执行中(本机直连)...'
  try {
    const r = await runPrecisionSell({
      token: token.value,
      orderId: precisionSelectedOrder.value.id,
      orderRelationId: precisionSelectedOrder.value.orderRelationId,
      digitalCollectionId: precisionSelectedHolding.value.id,
      consignPassword: precisionPwd.value,
      uid: uid.value,
      api,
      wxpusherUid: store.user?.wxpusher_uid || '',
      platformToken: platform_token,
      collectionName: precisionCname.value || '',
      price: Number(precisionSelectedOrder.value.price) || 0,
      onLog: (msg) => { precisionResult.value = msg },
    })
    precisionResult.value = r.status === 'ok' ? '成功!' : (r.message || '失败')
    if (r.status === 'ok') {
      precisionHoldings.value = precisionHoldings.value.filter(h => h.id !== precisionSelectedHolding.value.id)
      precisionSelectedHolding.value = null
    }
  } catch (e) { precisionResult.value = '错误: ' + (e.message || '') }
  precisionRunning.value = false
}
async function searchPrecisionUuid() {
  const uuid = precisionUuid.value.trim()
  if (!uuid) { precisionResult.value = '请输入求购订单号'; return }
  if (!precisionGid.value) { precisionResult.value = '请先选择藏品'; return }
  if (!token.value) { precisionResult.value = '请先登录 iBox'; return }
  const norm = (s) => String(s || '').replace(/-/g, '').toLowerCase()
  const target = norm(uuid)
  precisionUuidLoading.value = true
  precisionResult.value = '搜索中(本机)...'
  let found = null
  let scanned = 0
  let totalHint = 0
  const PAGE_SIZE = 20
  const PAGE_GAP_MS = 450
  try {
    for (let page = 1; !found; page++) {
      if (page > 1) {
        await new Promise((r) => setTimeout(r, PAGE_GAP_MS))
      }
      precisionResult.value = totalHint
        ? `搜索中... 第${page}页（已扫${scanned}/${totalHint}）`
        : `搜索中... 第${page}页（已扫${scanned}）`

      let r = null
      for (let attempt = 0; attempt < 4; attempt++) {
        r = await fetchPurchaseOrders({
          token: token.value,
          groupId: precisionGid.value,
          page,
          pageSize: PAGE_SIZE,
          uid: uid.value,
        })
        if (r.status === 'ok') break
        if (r.rateLimited || String(r.message || '').includes('429')) {
          const wait = 1500 * (attempt + 1)
          precisionResult.value = `被限流，${Math.round(wait / 1000)}s 后重试第${page}页…`
          await new Promise((res) => setTimeout(res, wait))
          continue
        }
        precisionResult.value = r.message || '求购列表拉取失败'
        precisionUuidLoading.value = false
        return
      }
      if (!r || r.status !== 'ok') {
        precisionResult.value = `限流多次仍失败（已扫${scanned}条）`
        precisionUuidLoading.value = false
        return
      }

      const orders = r.orders || []
      if (!orders.length) break
      scanned += orders.length
      totalHint = Number(r.total) || totalHint
      for (const o of orders) {
        if (
          norm(o.orderUuid) === target ||
          String(o.id) === uuid ||
          norm(o.id) === target
        ) {
          found = o
          break
        }
      }
      if (found) break
      if (totalHint > 0 && scanned >= totalHint) break
      if (orders.length < PAGE_SIZE) break
    }
  } catch (e) {
    precisionResult.value = '搜索失败: ' + (e.message || '网络错误')
    precisionUuidLoading.value = false
    return
  }
  if (found) {
    precisionSelectedOrder.value = found
    precisionSelectedHolding.value = null
    precisionResult.value = '已匹配: ¥' + found.price
  } else {
    precisionResult.value = `未找到（已扫${scanned}条求购，确认藏品与订单号是否对应）`
  }
  precisionUuidLoading.value = false
}
function precisionPrevPage() { if (precisionOrdersPage.value > 1) loadPrecisionOrders(precisionOrdersPage.value - 1) }
function precisionNextPage() { if (precisionOrdersPage.value * 20 < precisionOrdersTotal.value) loadPrecisionOrders(precisionOrdersPage.value + 1) }
</script>

<template>
  <div class="mx-auto max-w-[640px] pb-12">
    <!-- 未登录网站 -->
    <div v-if="!store.user" class="flex flex-col items-center justify-center py-20 px-4">
      <p class="text-sm text-slate-500 mb-6">请先登录本站账号</p>
      <button @click="store.showLogin = true" class="inline-flex h-10 items-center justify-center rounded-xl bg-zinc-900 px-6 text-sm font-semibold text-white transition-colors hover:bg-zinc-800">登录 / 注册</button>
    </div>

    <template v-else>
    <div v-if="vipPreview"
      class="mb-4 flex items-center justify-between gap-3 rounded-2xl border border-amber-100 bg-amber-50 px-4 py-3">
      <div class="min-w-0 text-[13px] text-amber-800">预览模式 · 可浏览全部功能，开通 VIP 后才能操作</div>
      <button type="button" @click="$router.push('/profile')"
        class="shrink-0 rounded-lg bg-zinc-900 px-3 py-1.5 text-[12px] font-medium text-white">去开通</button>
    </div>

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
          <div v-if="s.occupied" class="mt-0.5 truncate text-[9px] font-semibold leading-tight"
            :class="s.active
              ? 'text-white/85'
              : s.fragile
                ? 'text-amber-600'
                : (s.methodLabel === '短信' ? 'text-emerald-600' : 'text-slate-500')">
            <span>{{ s.methodLabel || 'Token' }}</span>
            <span v-if="s.fragile"> · 易掉</span>
            <span v-else-if="s.active"> · 当前</span>
          </div>
        </button>
      </div>
      <div v-if="loggedIn" class="mt-2 flex flex-wrap gap-2">
        <button type="button" @click="doLogout"
          class="rounded-full border border-slate-200 px-2.5 py-1 text-[11px] text-slate-600 hover:border-red-300 hover:text-red-600">退出当前</button>
        <button type="button" @click="doLogoutAll"
          class="rounded-full border border-slate-200 px-2.5 py-1 text-[11px] text-slate-600 hover:border-red-300 hover:text-red-600">退出全部</button>
      </div>
    </div>

    <!-- ═══ iBox Login（VIP 且未登 iBox / 加号加槽） ═══ -->
    <div v-if="!vipPreview && (!loggedIn || addingAccount) && !swapOnlyMode" class="space-y-5 pt-4">
      <div v-if="addingAccount" class="flex items-center justify-between rounded-xl bg-blue-50 px-3 py-2 text-[12px] text-blue-800">
        <span>正在登录到槽 {{ loginTargetSlot + 1 }}（其它账号保留）</span>
        <button type="button" class="font-semibold" @click="cancelAddAccount">取消</button>
      </div>
      <div class="text-center">
        <h2 class="text-xl font-semibold text-slate-900 mb-1">登录 iBox</h2>
        <p class="text-sm text-slate-500">手机号登录 · 短信/登录本机直连（极验仍走站点）</p>
      </div>
      <div class="rounded-xl border border-amber-200 bg-amber-50 px-3.5 py-3 text-[13px] leading-relaxed text-amber-900">
        <p class="font-semibold">重要提醒</p>
        <p class="mt-1">必须点击本页的「获取验证码」，用<strong>网站内发出的短信验证码</strong>登录；不要用官方 App / 其他渠道收到的验证码，否则会登录失败。</p>
      </div>
      <div class="flex gap-3">
        <input v-model="phoneInput" placeholder="手机号" @input="smsSent=false" class="h-12 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-base outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50 flex-1" />
        <input v-model="codeInput" placeholder="本站验证码" class="h-12 w-28 rounded-xl border border-slate-200 bg-slate-50 px-3 text-base outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50" />
      </div>
      <div v-if="smsSent" class="text-sm text-green-600 text-center">本站验证码已发送，请查收短信后填写</div>
      <div v-else class="w-full">
        <button @click="sendSms" :disabled="smsLoading" class="flex h-11 w-full items-center justify-center rounded-xl border border-slate-200 bg-slate-50 text-sm font-medium text-blue-600 transition-colors hover:bg-slate-100 disabled:text-slate-400">
          {{ smsLoading ? '极验+本机发送中…' : '获取验证码（必须用本站）' }}
        </button>
      </div>
      <p v-if="loginErr" class="text-sm text-red-600 text-center">{{ loginErr }}</p>
      <button @click="doLogin" :disabled="loginLoading" class="flex h-12 w-full items-center justify-center rounded-xl bg-zinc-900 text-base font-semibold text-white transition-colors hover:bg-zinc-800 disabled:opacity-40">
        {{ loginLoading ? '登录中...' : '登录' }}
      </button>
      <button v-if="!addingAccount" type="button" @click="enterSwapOnly"
        class="flex h-12 w-full items-center justify-center rounded-xl border border-slate-200 bg-white text-base font-semibold text-slate-800 transition-colors hover:bg-slate-50">
        大小号互刷（无需主号登录）
      </button>
      <p v-if="!addingAccount" class="text-center text-[11px] text-slate-400">互刷请走上面入口，分别登大小号，不会互相顶号</p>
      <div @click="showAdvanced = !showAdvanced" class="flex h-11 w-full cursor-pointer items-center justify-center rounded-xl bg-blue-50 text-sm font-semibold text-blue-600 transition-colors hover:bg-blue-100">
        {{ showAdvanced ? '收起 ▲' : 'Token 登录' }}
      </div>
      <div v-if="showAdvanced" class="space-y-3">
        <p class="text-[11px] leading-relaxed text-slate-500">
          持久登录请粘贴<strong class="text-slate-700">整段请求头</strong>（含
          <code class="text-[10px]">Authorization</code>、
          <code class="text-[10px]">DEVICE-ID</code>、
          <code class="text-[10px]">refreshToken</code>）。
          只贴 JWT 会在过期或 APP 换票后被踢。更稳请用上方短信登录。
        </p>
        <textarea v-model="tokenInput" rows="4" placeholder="Authorization: Bearer eyJ...&#10;DEVICE-ID: dev_xxxx&#10;或 JSON：accessToken + refreshToken + deviceId"
          class="w-full rounded-xl border border-slate-200 bg-slate-50 px-3 py-2 font-mono text-xs outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50" />
        <button @click="tokenLogin" class="flex h-10 w-full items-center justify-center rounded-xl border border-slate-200 bg-white text-sm font-semibold text-slate-900 transition-colors hover:bg-slate-50">验证 Token</button>
      </div>
    </div>

    <!-- ═══ Main content ═══ -->
    <div v-if="(loggedIn && !addingAccount) || vipPreview || (swapOnlyMode && !addingAccount)">
      <!-- Header -->
      <div class="flex flex-wrap items-center gap-2 pt-2 pb-6">
        <template v-if="swapOnlyMode && !loggedIn">
          <span class="h-2 w-2 rounded-full bg-blue-500 shrink-0"></span>
          <span class="text-sm font-medium text-slate-700">互刷模式</span>
          <span class="text-xs text-slate-400">不登主号，大小号分开登录</span>
          <button type="button" @click="exitSwapOnly"
            class="ml-auto rounded-full border border-slate-200 px-3 py-1 text-xs font-semibold text-slate-600 hover:bg-slate-50">
            返回登录
          </button>
        </template>
        <template v-else-if="vipPreview">
          <span class="h-2 w-2 rounded-full bg-amber-400 shrink-0"></span>
          <span class="text-sm font-medium text-slate-700">功能预览</span>
          <span class="text-xs text-slate-400">开通 VIP 后可登录使用</span>
        </template>
        <template v-else>
        <span class="h-2 w-2 rounded-full bg-green-500 shrink-0"></span>
        <span class="text-sm text-slate-500">UID <span class="font-semibold text-slate-900">{{ uid }}</span></span>
        <button @click="doHealthCheck" :disabled="checkingHealth"
          class="rounded-full border px-3 py-1 text-xs font-semibold transition-colors"
          :class="accountHealth === 'ok' ? 'border-green-300 bg-green-50 text-green-700' :
                   accountHealth === 'expired' ? 'animate-pulse border-red-400 bg-red-100 text-red-600' :
                   accountHealth === 'blocked' ? 'border-blue-300 bg-blue-50 text-blue-600' :
                   accountHealth === 'error' ? 'border-red-300 bg-red-50 text-red-600' :
                   'border-slate-200 bg-slate-50 text-slate-500 hover:bg-slate-100'">
          {{ checkingHealth ? '检测中...' :
             accountHealth === 'ok' ? '账号有效' :
             accountHealth === 'expired' ? '⚠ TOKEN已过期 请重新登录' :
             accountHealth === 'blocked' ? 'IP被封' :
             accountHealth === 'error' ? '异常' :
             '点击账号验活' }}
        </button>
        <button @click="stopAllTasks" :disabled="stopAllLoading"
          class="rounded-full border border-red-300 bg-red-50 px-3 py-1 text-xs font-semibold text-red-600 transition-colors hover:bg-red-100">
          {{ stopAllLoading ? '...' : '停止全部任务' }}
        </button>
        <span v-if="stopAllMsg" class="text-xs" :class="stopAllOk ? 'text-green-600' : 'text-red-500'">{{ stopAllMsg }}</span>
        </template>
      </div>

      <!-- Mode tabs — 两行铺开，一眼看完 -->
      <div v-if="!(swapOnlyMode && !loggedIn)" class="mb-6 grid grid-cols-4 gap-1.5">
        <button v-for="t in [
          {k:'buy',label:'捡漏'},{k:'sell',label:'卖求购'},{k:'place',label:'顶求购',isNew:true},{k:'batch',label:'上下架'},
          {k:'sweep',label:'点对点'},{k:'swap',label:'互刷'},{k:'synth',label:'抢合'},{k:'presale',label:'抢购'},
          {k:'precision',label:'精准射'},{k:'rank',label:'打榜'},{k:'quant',label:'量化出货'},{k:'announce',label:'公告锁定',isNew:true}
        ]" :key="t.k" @click="selectMode(t.k)"
        class="relative rounded-xl py-2.5 text-xs font-medium transition-colors"
        :class="mode===t.k
          ? 'bg-white text-slate-900 shadow-[0_1px_3px_rgba(0,0,0,0.08)] ring-1 ring-black/[0.04]'
          : 'text-slate-500 hover:bg-white/70 hover:text-slate-800'">
          <span
            v-if="t.isNew"
            class="absolute -right-0.5 -top-0.5 rounded-full bg-rose-500 px-1.5 py-px text-[9px] font-semibold leading-none text-white shadow-sm"
          >新</span>
          {{ t.label }}
        </button>
      </div>
      <div v-else class="mb-6">
        <div class="inline-flex rounded-xl bg-white px-4 py-2.5 text-xs font-medium text-slate-900 shadow-[0_1px_3px_rgba(0,0,0,0.08)] ring-1 ring-black/[0.04]">互刷</div>
      </div>
      <!-- Search (hidden in synth/sweep mode) -->
      <div v-if="mode !== 'synth' && mode !== 'sweep' && mode !== 'presale' && mode !== 'announce'" class="relative mb-6">
        <input v-model="searchQ" @input="doSearch" placeholder="搜索藏品名称"
          :class="['h-12 w-full rounded-2xl border border-transparent bg-white px-4 text-base outline-none transition shadow-[0_1px_2px_rgba(0,0,0,0.04)] ring-1 ring-black/[0.06] focus:ring-2 focus:ring-slate-300/80 placeholder:text-slate-400', isError('buySearch') ? 'border-red-300' : 'border-slate-200']" />
        <span v-if="searchQ" @click="searchQ='';searchResults=[]"
          class="absolute right-4 top-1/2 -translate-y-1/2 cursor-pointer text-lg text-slate-400 hover:text-slate-600 transition-colors">&times;</span>
        <div v-if="searchResults.length" class="absolute z-20 mt-2 w-full overflow-hidden rounded-2xl bg-white shadow-[0_1px_2px_rgba(0,0,0,0.04)] ring-1 ring-black/[0.04] shadow-lg">
          <div v-for="r in searchResults" :key="r.id" @click="selectColl(r)"
            class="cursor-pointer border-b border-slate-100 px-5 py-3 last:border-0 transition-colors hover:bg-slate-50">
            <div class="truncate text-sm text-slate-900">{{ r.name }}</div>
            <div class="mt-0.5 flex items-center gap-2 text-xs text-slate-500">
              <span>ID {{ r.id }}</span>
              <span v-if="r.consignment_status === 1" class="rounded bg-emerald-50 px-1.5 py-0.5 text-[10px] font-medium text-emerald-700">已开寄售</span>
              <span v-else class="rounded bg-amber-50 px-1.5 py-0.5 text-[10px] font-medium text-amber-700">未开寄售 · 可先选</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Selected badge -->
      <div v-if="curGid && mode !== 'synth' && mode !== 'sweep' && mode !== 'presale' && mode !== 'announce'" class="mb-6 flex items-center gap-3 rounded-xl bg-white shadow-[0_1px_2px_rgba(0,0,0,0.04)] ring-1 ring-black/[0.04] px-4 py-3">
        <span class="truncate text-sm font-medium text-slate-900">{{ curCname }}</span>
        <span class="shrink-0 text-xs text-slate-500">ID {{ curGid }}</span>
        <span @click="mode==='sell'?(sellGid=0,sellCname=''):mode==='place'?(placeGid=0,placeCname=''):mode==='batch'?(batchGid=0,batchCname=''):mode==='sweep'?(sweepGid=0,sweepCname=''):mode==='precision'?(precisionGid=0,precisionCname='',precisionOrders=[],precisionSelectedOrder=null,precisionHoldings=[],precisionResult=''):mode==='rank'?(rankGid=0,rankCname='',rankEstimate=null,rankFloor=null):mode==='quant'?(quantGid=0,quantCname='',quantFloor=null):(buyGid=0,buyCname='')"
          class="ml-auto cursor-pointer text-xl leading-none text-slate-400 hover:text-slate-600 transition-colors">&times;</span>
      </div>

      <!-- ════════════════ BUY 捡漏 ════════════════ -->
      <div v-if="mode==='buy'" class="space-y-5">
        <div class="grid grid-cols-3 gap-2">
          <button
            v-for="m in buyModes"
            :key="m.key"
            type="button"
            @click="buyMode = m.key"
            class="relative rounded-xl border px-2 py-2.5 text-center transition-colors"
            :class="buyMode === m.key
              ? 'border-zinc-900 bg-zinc-900 text-white'
              : 'border-slate-200 bg-white text-slate-600'">
            <span
              v-if="m.recommend"
              class="absolute -right-1 -top-1 rounded-full bg-rose-500 px-1.5 py-px text-[9px] font-semibold leading-none text-white shadow-sm"
            >推荐</span>
            <div class="text-[12px] font-semibold leading-tight">{{ m.label }}</div>
            <div class="mt-0.5 text-[10px] opacity-70 leading-tight">{{ m.tip }}</div>
          </button>
        </div>
        <p v-if="buyMode === 'normal'" class="text-[11px] text-slate-400 -mt-3">普通：查挂单后逐笔 purchase，适合精捡。</p>
        <p v-else-if="buyMode === 'cross'" class="text-[11px] text-slate-400 -mt-3">交叉：批购与普通下单穿插（当前默认捡漏逻辑）。</p>
        <p v-else class="text-[11px] text-slate-400 -mt-3">纯批量：只打批购；过于频繁时休息 60s（原生提示）。</p>

        <div class="flex gap-3">
          <input v-model="buyPrice" type="number" placeholder="目标价 ¥" :class="['h-12 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-base outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50 flex-1', isError('buyPrice') ? 'border-red-300' : 'border-slate-200']" />
          <input v-model="buyQty" type="number" placeholder="数量" :class="['h-12 w-20 rounded-xl border border-slate-200 bg-slate-50 px-3 text-base outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50', isError('buyQty') ? 'border-red-300' : 'border-slate-200']" min="1" />
        </div>

        <div v-if="buyMode === 'batch'" class="flex items-center gap-3">
          <span class="shrink-0 text-sm text-slate-600">批购间隔</span>
          <input v-model="buyBatchInterval" type="number" min="1" step="0.5" placeholder="6"
            class="h-12 w-24 rounded-xl border border-slate-200 bg-slate-50 px-3 text-base outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50" />
          <span class="text-sm text-slate-400">秒（默认 6）</span>
        </div>

        <!-- Auto-pay toggle -->
        <label class="flex h-10 items-center justify-between text-sm font-medium">
          <span class="text-slate-600">自动支付</span>
          <input type="checkbox" v-model="buyAutoPay" class="peer sr-only" />
          <span class="relative h-6 w-11 rounded-full bg-slate-200 transition-colors after:absolute after:left-1 after:top-1 after:h-4 after:w-4 after:rounded-full after:bg-white after:transition-transform peer-checked:bg-blue-600 peer-checked:after:translate-x-5 peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-blue-600"></span>
        </label>
        <input v-if="buyAutoPay" v-model="buyPwd" type="password" placeholder="支付密码" class="h-12 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-base outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50" />

        <div class="flex items-center gap-2 text-sm text-emerald-600">
          <span class="h-1.5 w-1.5 rounded-full bg-emerald-500"></span>
          捡漏优先本机直连（CORS 才走同域反代）
        </div>

        <button @click="buyToggle" :disabled="!buyGid"
          :class="buyRunning ? 'bg-red-600 text-white' : 'bg-zinc-900 text-white hover:bg-zinc-800'"
          class="flex h-12 w-full items-center justify-center rounded-full text-base font-semibold transition-colors disabled:opacity-30">
          {{ buyRunning ? '停止' : '开始捡漏' }}
        </button>
        <LogPanel :logs="buyLogs" title="捡漏日志 · 本机直连" variant="chat" />
      </div>

      <!-- ════════════════ SELL 卖求购 ════════════════ -->
      <div v-if="mode==='sell'" class="space-y-5">
        <div class="flex gap-3">
          <input v-model="sellPrice" type="number" placeholder="最低接受价 ¥" :class="['h-12 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-base outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50 flex-1', isError('sellPrice') ? 'border-red-300' : 'border-slate-200']" />
          <input v-model="sellQty" type="number" placeholder="数量" :class="['h-12 w-20 rounded-xl border border-slate-200 bg-slate-50 px-3 text-base outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50', isError('sellQty') ? 'border-red-300' : 'border-slate-200']" min="1" />
        </div>
        <input v-model="consignPwd" type="password" placeholder="寄售密码" :class="['h-12 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-base outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50', isError('consignPwd') ? 'border-red-300' : 'border-slate-200']" />
        <label class="flex cursor-pointer items-center gap-2 text-sm text-slate-600">
          <input type="checkbox" v-model="sellTimed" class="h-4 w-4 rounded border-slate-300" />
          定时卖求购（到点立即执行）
        </label>
        <input v-if="sellTimed" v-model="sellFireTime" type="time" step="1" class="h-12 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-base outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50" />
        <div v-if="sellTimed && sellCountdown" class="rounded-2xl bg-white shadow-[0_1px_2px_rgba(0,0,0,0.04)] ring-1 ring-black/[0.04] py-3 text-center">
          <div class="mb-1 text-xs text-slate-400">距离开卖</div>
          <div class="font-mono text-2xl font-semibold tracking-wider text-zinc-900">{{ sellCountdown }}</div>
        </div>
        <p class="text-center text-sm text-slate-500">求购价 ≥ 目标价时自动卖出</p>
        <button @click="sellToggle" :disabled="!sellGid"
          :class="sellRunning ? 'bg-red-600 text-white' : 'bg-zinc-900 text-white hover:bg-zinc-800'"
          class="flex h-12 w-full items-center justify-center rounded-full text-base font-semibold transition-colors disabled:opacity-30">
          {{ sellRunning ? '停止' : '开始卖出' }}
        </button>
        <LogPanel :logs="sellLogs" title="卖出日志 · 本机直连" variant="chat" />
      </div>

      <!-- ════════════════ PLACE 顶求购 ════════════════ -->
      <div v-if="mode==='place'" class="space-y-5">
        <div class="flex gap-3">
          <input v-model="placePrice" type="number" placeholder="求购单价 ¥" :class="['h-12 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-base outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50 flex-1', isError('placePrice') ? 'border-red-300' : 'border-slate-200']" />
          <input v-model="placeQty" type="number" placeholder="数量" :class="['h-12 w-20 rounded-xl border border-slate-200 bg-slate-50 px-3 text-base outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50', isError('placeQty') ? 'border-red-300' : 'border-slate-200']" min="1" />
        </div>
        <label class="flex cursor-pointer items-center gap-2 text-sm text-slate-600">
          <input type="checkbox" v-model="placeAutoPay" class="h-4 w-4 rounded border-slate-300" />
          下单后自动支付
        </label>
        <input v-if="placeAutoPay" v-model="placePwd" type="password" placeholder="支付密码" :class="['h-12 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-base outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50', isError('placePwd') ? 'border-red-300' : 'border-slate-200']" />
        <p class="text-center text-sm text-slate-500">向市场挂求购单（advance-orders）· 填单价与数量</p>
        <button @click="placeStart" :disabled="!placeGid || placeBusy"
          class="flex h-12 w-full items-center justify-center rounded-full bg-zinc-900 text-base font-semibold text-white transition-colors hover:bg-zinc-800 disabled:opacity-30">
          {{ placeBusy ? '提交中…' : '确认顶求购' }}
        </button>
        <LogPanel :logs="placeLogs" title="顶求购日志 · 本机直连" variant="chat" />
      </div>

      <!-- ════════════════ BATCH 上下架 ════════════════ -->
      <div v-if="mode==='batch'" class="space-y-5">
        <div class="flex gap-3">
          <input v-model="batchPrice" type="number" placeholder="上架单价 ¥" class="h-12 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-base outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50 flex-1" />
          <input v-model="batchQty" placeholder="数量（0=全部）" class="h-12 w-36 rounded-xl border border-slate-200 bg-slate-50 px-3 text-base outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50" />
        </div>
        <input v-model="consignPwd" type="password" placeholder="寄售密码" :class="['h-12 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-base outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50', isError('consignPwd') ? 'border-red-300' : 'border-slate-200']" />
        <div class="flex gap-3">
          <button @click="batchToggle('list')" :disabled="!batchGid || batchStarting"
            :class="(batchRunning || batchStarting) ? 'bg-red-600 text-white' : 'bg-zinc-900 text-white hover:bg-zinc-800'"
            class="flex h-12 flex-1 items-center justify-center rounded-full text-base font-semibold transition-colors disabled:opacity-30">
            {{ batchStarting ? '启动中…' : batchRunning ? '停止' : '批量上架' }}
          </button>
          <button @click="batchToggle('unlist')" :disabled="!batchGid || batchStarting"
            :class="(batchRunning || batchStarting) ? 'bg-red-600 text-white' : 'bg-zinc-900 text-white hover:bg-zinc-800'"
            class="flex h-12 flex-1 items-center justify-center rounded-full text-base font-semibold transition-colors disabled:opacity-30">
            {{ batchStarting ? '启动中…' : batchRunning ? '停止' : '批量下架' }}
          </button>
        </div>
        <label class="flex cursor-pointer items-center justify-center gap-2 text-xs" :class="batchSafeMode ? 'text-blue-600' : 'text-slate-400'">
          <input type="checkbox" v-model="batchSafeMode" class="h-3.5 w-3.5" />
          {{ batchSafeMode ? '安全模式 固定3.5s(编号顺序)' : '快速模式 固定3.5s(编号顺序)' }}
        </label>
        <p class="text-center text-sm text-emerald-600">本机直连 · 已选 {{ batchQty || 0 }} 件 · 0 = 全部</p>
        <LogPanel :logs="batchLogs" title="上下架日志 · 本机直连" variant="chat" />
      </div>

      <!-- ════════════════ SWEEP 点对点 ════════════════ -->
      <div v-if="mode==='sweep'" class="space-y-5">
        <div>
        <div class="flex items-center gap-1.5 text-xs text-slate-400">
          <span class="rounded-full border border-slate-200 bg-slate-50 px-2 py-0.5">暗号定位</span>
          <span class="text-slate-300">→</span>
          <span class="rounded-full border border-slate-200 bg-slate-50 px-2 py-0.5">仓库点选</span>
          <span class="text-slate-300">→</span>
          <span class="rounded-full border border-slate-200 bg-slate-50 px-2 py-0.5">开始点对点</span>
          <span @click="sweepHelp = !sweepHelp" class="ml-1 cursor-pointer text-slate-400 hover:text-slate-600">{{ sweepHelp ? '收起 ▲' : '怎么用？' }}</span>
        </div>
        <div v-if="sweepHelp" class="mt-3 space-y-1 rounded-xl bg-slate-50 p-3 text-xs leading-relaxed text-slate-500">
          <div>1. 卖家在市场挂一个暗号藏品（可高价），并开放个人持仓</div>
          <div>2. 买家搜索暗号藏品 → 点选挂单 → 确认卖家昵称锁定</div>
          <div>3. 进入卖家仓库选分组；填最高接受价与数量后会自动翻页勾选「有标价且≤最高价」的件（无标价跳过，可手改）</div>
          <div>4. 确认勾选后点「开始点对点」；只买已勾选件数</div>
        </div>
      </div>

        <p v-if="loginErr && mode==='sweep'" class="rounded-xl bg-red-50 px-4 py-3 text-sm text-red-600">{{ loginErr }}</p>

        <div class="space-y-4 rounded-2xl bg-white shadow-[0_1px_2px_rgba(0,0,0,0.04)] ring-1 ring-black/[0.04] p-5">
          <div class="flex items-center justify-between gap-2">
            <div class="text-xs font-medium uppercase tracking-wide text-slate-500">暗号藏品（点选挂单定位卖家）</div>
            <button v-if="sweepSeller" type="button" @click="reselectSweepSeller"
              class="text-xs font-medium text-blue-600 hover:text-blue-700">重选卖家</button>
          </div>
          <div v-if="sweepMarkerCname" class="text-base font-semibold text-slate-900">{{ sweepMarkerCname }} <span class="ml-2 text-sm font-normal text-slate-500">GID {{ sweepMarkerGid }}</span></div>
          <div v-if="sweepSeller" class="rounded-xl bg-emerald-50 px-3 py-2 text-sm text-emerald-800">
            已锁定卖家：<span class="font-semibold">{{ sweepSeller.name || '未知' }}</span>
          </div>
          <input v-if="!sweepSeller" v-model="sweepMarkerSearch" @input="doMarkerSearch" placeholder="搜索暗号藏品..." class="h-10 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-sm outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50" />
          <div v-if="!sweepSeller && sweepMarkerResults.length" class="max-h-40 overflow-y-auto rounded-xl border border-slate-200">
            <div v-for="r in sweepMarkerResults" :key="r.id" @click="selectMarker(r)"
              class="cursor-pointer border-b border-slate-100 px-4 py-3 text-sm last:border-0 hover:bg-slate-50">{{ r.name }} <span class="text-xs text-slate-500">GID {{ r.id }}</span></div>
          </div>

          <div v-if="!sweepSeller && sweepMarkerGid" class="space-y-2">
            <div class="text-xs text-slate-500">市场挂单（价格降序，点选定位）</div>
            <div class="max-h-56 overflow-y-auto rounded-xl border border-slate-200" @scroll="onMarkerOrdersScroll">
              <div v-for="(o, mi) in sweepMarkerOrders" :key="(o.order_id || o.digital_collection_id) + '-' + mi"
                @click="pickMarkerOrder(o)"
                class="flex cursor-pointer items-center justify-between gap-3 border-b border-slate-100 px-3 py-2.5 text-sm last:border-0 hover:bg-slate-50">
                <div class="min-w-0">
                  <div class="font-medium text-slate-900">¥{{ o.price }} <span class="ml-1 font-normal text-slate-500">#{{ o.token_id || '-' }}</span></div>
                  <div class="truncate text-xs text-slate-400">{{ o.seller_name || '卖家待解析' }}</div>
                </div>
                <span class="shrink-0 text-xs text-blue-600">选择</span>
              </div>
              <div v-if="sweepMarkerLoading" class="px-3 py-2 text-center text-xs text-slate-400">加载中…</div>
              <div v-else-if="!sweepMarkerOrders.length" class="px-3 py-4 text-center text-xs text-slate-400">暂无挂单</div>
              <div v-else-if="!sweepMarkerHasMore" class="px-3 py-2 text-center text-xs text-slate-400">没有更多</div>
            </div>
          </div>
        </div>

        <div v-if="sweepSeller" class="space-y-4 rounded-2xl bg-white shadow-[0_1px_2px_rgba(0,0,0,0.04)] ring-1 ring-black/[0.04] p-5">
          <div class="text-xs font-medium uppercase tracking-wide text-slate-500">卖家仓库（勾选目标）</div>
          <div class="flex gap-3">
            <input v-model="sweepMaxPrice" type="number" placeholder="最高接受价 ¥" class="h-10 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-sm outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50 flex-1" />
            <input v-model="sweepQty" placeholder="数量 N" class="h-10 w-20 rounded-xl border border-slate-200 bg-slate-50 px-3 text-sm outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50" />
          </div>
          <div class="text-xs text-slate-500">已选 {{ sweepSelected.length }} / {{ parseInt(sweepQty) || 1 }}
            <span v-if="sweepAutoSelectMsg" class="ml-2 text-blue-600">{{ sweepAutoSelectMsg }}</span>
          </div>

          <div v-if="sweepWhGroups.length" class="max-h-40 overflow-y-auto rounded-xl border border-slate-200">
            <div v-for="g in sweepWhGroups" :key="g.group_id" @click="selectWhGroup(g)"
              :class="sweepGid === g.group_id ? 'bg-blue-50' : 'hover:bg-slate-50'"
              class="cursor-pointer border-b border-slate-100 px-3 py-2.5 text-sm last:border-0">
              <div class="truncate text-slate-900">{{ g.name || ('GID ' + g.group_id) }}</div>
              <div class="mt-0.5 text-xs text-slate-400">GID {{ g.group_id }} · {{ g.count || 0 }} 件</div>
            </div>
          </div>
          <div v-else-if="sweepWhLoading" class="text-xs text-slate-400">加载仓库分组…</div>

          <div v-if="sweepCname" class="text-sm font-semibold text-slate-900">{{ sweepCname }} <span class="ml-1 text-xs font-normal text-slate-500">GID {{ sweepGid }}</span></div>

          <div v-if="sweepGid" class="max-h-56 overflow-y-auto rounded-xl border border-slate-200" @scroll="onWhItemsScroll">
            <div v-for="it in sweepWhItems" :key="it.digital_collection_id"
              @click="canToggleWhItem(it) && toggleWhItem(it)"
              :class="[
                !canToggleWhItem(it) ? 'cursor-not-allowed opacity-40' : 'cursor-pointer hover:bg-slate-50',
                isWhItemSelected(it) ? 'bg-blue-50' : '',
                isWhItemOverpriced(it) && !isWhItemSelected(it) ? 'opacity-40' : ''
              ]"
              class="flex items-center gap-3 border-b border-slate-100 px-3 py-2.5 text-sm last:border-0">
              <span class="flex h-4 w-4 shrink-0 items-center justify-center rounded border"
                :class="isWhItemSelected(it) ? 'border-blue-600 bg-blue-600 text-white' : 'border-slate-300'">
                <span v-if="isWhItemSelected(it)" class="text-[10px] leading-none">✓</span>
              </span>
              <div class="min-w-0 flex-1">
                <div class="text-slate-900">#{{ it.token_id || '-' }}
                  <span v-if="sweepItemHasPrice(it)" class="ml-2 text-slate-600">¥{{ it.price }}</span>
                  <span v-else class="ml-2 text-[10px] text-amber-600">无标价</span>
                </div>
                <div v-if="isWhItemOverpriced(it)" class="text-[10px] text-slate-400">高于最高接受价</div>
              </div>
            </div>
            <div v-if="sweepWhLoading" class="px-3 py-2 text-center text-xs text-slate-400">加载中…</div>
            <div v-else-if="!sweepWhItems.length" class="px-3 py-4 text-center text-xs text-slate-400">该分组暂无持仓</div>
            <div v-else-if="!sweepWhHasMore" class="px-3 py-2 text-center text-xs text-slate-400">没有更多</div>
          </div>
        </div>

        <label class="flex h-10 items-center justify-between text-sm font-medium">
          <span class="text-slate-600">自动支付</span>
          <input type="checkbox" v-model="sweepAutoPay" class="peer sr-only" />
          <span class="relative h-6 w-11 rounded-full bg-slate-200 transition-colors after:absolute after:left-1 after:top-1 after:h-4 after:w-4 after:rounded-full after:bg-white after:transition-transform peer-checked:bg-blue-600 peer-checked:after:translate-x-5 peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-blue-600"></span>
        </label>
        <input v-if="sweepAutoPay" v-model="consignPwd" type="password" placeholder="支付密码" class="h-12 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-base outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50" />

        <button @click="sweepToggle" :disabled="!sweepRunning && !sweepCanStart"
          :class="sweepRunning ? 'bg-red-600 text-white' : 'bg-zinc-900 text-white hover:bg-zinc-800'"
          class="flex h-12 w-full items-center justify-center rounded-full text-base font-semibold transition-colors disabled:opacity-30">
          {{ sweepRunning ? '停止' : '开始点对点 (' + sweepSelected.length + '件)' }}
        </button>
        <LogPanel :logs="sweepLogs" title="扫货日志" variant="chat" />
      </div>

      <!-- ════════════════ SWAP 互刷 ════════════════ -->
      <div v-if="mode==='swap'" class="space-y-4">
        <p class="text-[11px] text-slate-400 -mt-1">大小号各自登录即可；不要登科技页主号，也不会互相挤下线。也可用下方 Token。</p>
        <div v-if="swapCname" class="rounded-2xl bg-white shadow-[0_1px_2px_rgba(0,0,0,0.04)] ring-1 ring-black/[0.04] px-5 py-4">
          <div class="text-base font-semibold text-slate-900">{{ swapCname }}</div>
          <div class="mt-1 text-xs text-slate-400">GID {{ swapGid }} · 持仓多的一侧先挂，满轮自动停</div>
        </div>
        <p v-else class="text-sm text-slate-500">先搜索并选择藏品</p>
        <p v-if="loginErr && mode==='swap'" class="rounded-xl bg-red-50 px-4 py-3 text-sm text-red-600">{{ loginErr }}</p>

        <div class="rounded-xl border border-amber-200 bg-amber-50 px-3 py-2.5 text-[12px] leading-relaxed text-amber-900">
          大小号也须用本页「获取验证码」发出的短信登录，勿用官方 App 验证码。
        </div>
        <!-- 大小号登录：并排 -->
        <div class="grid gap-3 sm:grid-cols-2">
          <div class="rounded-2xl bg-white shadow-[0_1px_2px_rgba(0,0,0,0.04)] ring-1 ring-black/[0.04] p-4 space-y-2.5">
            <div class="flex items-center justify-between">
              <span class="text-sm font-semibold text-slate-800">大号</span>
              <div class="flex items-center gap-2">
                <span v-if="swapLoggedA" class="text-xs font-medium text-green-600">已登录</span>
                <button v-if="swapLoggedA" type="button" @click="copySwapToken('A')"
                  class="text-xs font-medium text-blue-600 hover:text-blue-700">复制Token</button>
                <button v-if="swapLoggedA" type="button" @click="clearSwapSlot('A')"
                  class="text-xs font-medium text-slate-400 hover:text-red-500">退出/换号</button>
              </div>
            </div>
            <input v-model="swapPhoneA" placeholder="手机号" @input="swapSmsSentA=false" class="h-10 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-sm outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-50" :disabled="swapLoggedA" />
            <div class="flex gap-2">
              <input v-model="swapCodeA" placeholder="验证码" class="h-10 min-w-0 flex-1 rounded-xl border border-slate-200 bg-slate-50 px-3 text-sm outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-50" :disabled="swapLoggedA" />
              <button @click="sendSwapSms('A')" :disabled="swapSmsLoadingA || swapLoggedA"
                class="h-10 shrink-0 rounded-xl px-3 text-xs font-medium text-blue-600 disabled:text-slate-400">
                {{ swapSmsLoadingA ? '发送中...' : swapSmsSentA ? '已发送' : '获取验证码' }}
              </button>
              <button @click="doSwapLogin('A')" :disabled="swapLoginA || swapLoggedA"
                class="h-10 shrink-0 rounded-xl border border-slate-200 bg-white px-3 text-xs font-medium text-slate-700 disabled:border-0 disabled:text-green-600">
                {{ swapLoggedA ? '✓' : swapLoginA ? '...' : '登录' }}
              </button>
            </div>
            <input v-model="swapPayA" type="password" placeholder="支付密码" class="h-10 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-sm outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-50" />
          </div>

          <div class="rounded-2xl bg-white shadow-[0_1px_2px_rgba(0,0,0,0.04)] ring-1 ring-black/[0.04] p-4 space-y-2.5">
            <div class="flex items-center justify-between">
              <span class="text-sm font-semibold text-slate-800">小号</span>
              <div class="flex items-center gap-2">
                <span v-if="swapLoggedB" class="text-xs font-medium text-green-600">已登录</span>
                <button v-if="swapLoggedB" type="button" @click="copySwapToken('B')"
                  class="text-xs font-medium text-blue-600 hover:text-blue-700">复制Token</button>
                <button v-if="swapLoggedB" type="button" @click="clearSwapSlot('B')"
                  class="text-xs font-medium text-slate-400 hover:text-red-500">退出/换号</button>
              </div>
            </div>
            <input v-model="swapPhoneB" placeholder="手机号" @input="swapSmsSentB=false" class="h-10 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-sm outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-50" :disabled="swapLoggedB" />
            <div class="flex gap-2">
              <input v-model="swapCodeB" placeholder="验证码" class="h-10 min-w-0 flex-1 rounded-xl border border-slate-200 bg-slate-50 px-3 text-sm outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-50" :disabled="swapLoggedB" />
              <button @click="sendSwapSms('B')" :disabled="swapSmsLoadingB || swapLoggedB"
                class="h-10 shrink-0 rounded-xl px-3 text-xs font-medium text-blue-600 disabled:text-slate-400">
                {{ swapSmsLoadingB ? '发送中...' : swapSmsSentB ? '已发送' : '获取验证码' }}
              </button>
              <button @click="doSwapLogin('B')" :disabled="swapLoginB || swapLoggedB"
                class="h-10 shrink-0 rounded-xl border border-slate-200 bg-white px-3 text-xs font-medium text-slate-700 disabled:border-0 disabled:text-green-600">
                {{ swapLoggedB ? '✓' : swapLoginB ? '...' : '登录' }}
              </button>
            </div>
            <input v-model="swapPayB" type="password" placeholder="支付密码" class="h-10 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-sm outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-50" />
          </div>
        </div>

        <!-- 参数 -->
        <div class="rounded-2xl bg-white shadow-[0_1px_2px_rgba(0,0,0,0.04)] ring-1 ring-black/[0.04] p-4 space-y-3">
          <div class="grid grid-cols-3 gap-2">
            <div>
              <div class="mb-1 text-xs text-slate-400">挂单价</div>
              <input v-model="swapPrice" type="number" step="0.01" placeholder="0.00" class="h-11 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-sm outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-50" />
            </div>
            <div>
              <div class="mb-1 text-xs text-slate-400">件数</div>
              <input v-model="swapCount" type="number" min="1" max="100" placeholder="每轮" class="h-11 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-sm outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-50" />
            </div>
            <div>
              <div class="mb-1 text-xs text-slate-400">轮数</div>
              <input v-model="swapRounds" type="number" min="1" max="500" placeholder="往返" class="h-11 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-sm outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-50" />
            </div>
          </div>
          <input v-model="consignPwd" type="password" placeholder="寄售密码（双号共用）" class="h-11 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-sm outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-50" />
        </div>

        <div @click="showAdvanced = !showAdvanced" class="cursor-pointer text-center text-xs text-slate-400 hover:text-slate-600">
          {{ showAdvanced ? '收起 Token' : 'Token 登录' }}
        </div>
        <div v-if="showAdvanced" class="space-y-2 rounded-2xl bg-white shadow-[0_1px_2px_rgba(0,0,0,0.04)] ring-1 ring-black/[0.04] p-4">
          <input v-model="swapTokenA" placeholder="大号 Token" class="h-10 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 font-mono text-xs outline-none focus:border-blue-500" />
          <input v-model="swapTokenB" placeholder="小号 Token" class="h-10 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 font-mono text-xs outline-none focus:border-blue-500" />
          <button @click="swapTokenLogin" class="flex h-10 w-full items-center justify-center rounded-xl border border-slate-200 text-sm font-medium text-slate-700 hover:bg-slate-50">验证 Token</button>
        </div>

        <button @click="swapToggle" :disabled="!swapGid"
          :class="swapRunning ? 'bg-red-600 text-white' : 'bg-zinc-900 text-white hover:bg-zinc-800'"
          class="flex h-12 w-full items-center justify-center rounded-full text-base font-semibold transition-colors disabled:opacity-30">
          {{ swapRunning ? '停止' : '开始互刷' }}
        </button>
        <LogPanel :logs="swapLogs" title="互刷日志" variant="chat" />
      </div>

      <!-- ════════════════ SYNTH 抢合 ════════════════ -->
      <div v-if="mode==='synth'" class="space-y-5">
        <div class="rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-900">
          网站抢合不限次 · APP 本地开火仍按卡档计次
        </div>
        <p class="text-sm text-slate-500">合成由站点转发（浏览器直连会被预检拦截）· 提前 0.8 秒 · 每步日志 · 不限时（手动停止才停）</p>
        <div class="flex gap-2">
          <button type="button" @click="synthAllowBatch=true; synthBatchChunk=0" class="h-10 flex-1 rounded-xl text-sm" :class="synthBatchChunk===0 && synthAllowBatch ? 'bg-blue-600 text-white' : 'bg-slate-100 text-slate-600'">可批量</button>
          <button type="button" @click="synthAllowBatch=true; synthBatchChunk=10" class="h-10 flex-1 rounded-xl text-sm" :class="synthBatchChunk===10 ? 'bg-blue-600 text-white' : 'bg-slate-100 text-slate-600'">每次10</button>
          <button type="button" @click="synthAllowBatch=false; synthBatchChunk=1" class="h-10 flex-1 rounded-xl text-sm" :class="synthBatchChunk===1 || (!synthAllowBatch && synthBatchChunk!==10) ? 'bg-blue-600 text-white' : 'bg-slate-100 text-slate-600'">每次1次</button>
        </div>
        <p v-if="loginErr" class="rounded-xl bg-red-50 px-4 py-3 text-sm text-red-600">{{ loginErr }}</p>

        <div class="flex gap-3">
          <input v-model="synthSearch" @input="doSynthSearch" placeholder="搜索活动名称" class="h-12 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-base outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50 flex-1" />
          <button @click="fetchAllSynth" class="inline-flex h-12 shrink-0 items-center justify-center rounded-xl bg-blue-600 px-5 text-sm font-semibold text-white transition-colors hover:bg-blue-700">
            获取活动
          </button>
        </div>
        <div v-if="synthResults.length" class="max-h-64 overflow-y-auto rounded-2xl bg-white shadow-[0_1px_2px_rgba(0,0,0,0.04)] ring-1 ring-black/[0.04]">
          <div v-for="a in synthResults" :key="a.id" @click="selectSynth(a)"
            class="cursor-pointer border-b border-slate-100 px-5 py-3.5 last:border-0 transition-colors hover:bg-slate-50">
            <div class="text-sm text-slate-900">{{ a.name }}</div>
            <div class="mt-0.5 text-xs text-slate-500">{{ formatTime(a.startTime) }}</div>
          </div>
        </div>

        <div v-if="synthSelected" class="rounded-2xl bg-white shadow-[0_1px_2px_rgba(0,0,0,0.04)] ring-1 ring-black/[0.04] p-5">
          <div class="text-base font-semibold text-slate-900">{{ synthSelected.name }}</div>
          <div class="mt-2 text-sm text-slate-500">{{ formatTime(synthSelected.startTime) }} &middot; 限量 {{ synthSelected.maxSyntheticNum || '-' }} 次/人</div>
        </div>

        <div v-if="synthChannels.length" class="space-y-1 rounded-2xl bg-white shadow-[0_1px_2px_rgba(0,0,0,0.04)] ring-1 ring-black/[0.04] p-5">
          <div class="mb-3 text-sm text-slate-500">选择合成通道</div>
          <div v-for="ch in synthChannels" :key="ch.id" @click="selectChannel(ch.id)"
            class="flex cursor-pointer items-center gap-3 rounded-xl px-3 py-3 transition-colors"
            :class="synthChannelId === ch.id ? 'bg-slate-200' : 'hover:bg-slate-100'">
            <span class="flex h-5 w-5 shrink-0 items-center justify-center rounded-full border-2 text-xs transition-all"
              :class="synthChannelId === ch.id ? 'border-blue-600 bg-blue-600 text-white' : 'border-slate-200'">
              {{ synthChannelId === ch.id ? '✓' : '' }}
            </span>
            <span class="flex-1 truncate text-sm">{{ ch.name }}</span>
            <span class="text-xs text-slate-500">{{ ch.startTime?.split(' ')[0] || '' }}</span>
          </div>
        </div>

        <div v-if="synthLoading" class="py-8 text-center text-sm text-slate-500">加载材料中...</div>

        <div v-else-if="_allMaterials.length" class="space-y-1 rounded-2xl bg-white shadow-[0_1px_2px_rgba(0,0,0,0.04)] ring-1 ring-black/[0.04] p-5">
          <div class="mb-3 flex items-center justify-between">
            <span class="text-sm text-slate-500">消耗材料</span>
            <button @click="toggleOwnedFilter"
              class="rounded-full border px-3 py-1.5 text-xs transition-colors"
              :class="synthOwnedFilter ? 'border-zinc-400 bg-slate-100 text-slate-900' : 'border-slate-200 text-slate-500 hover:shadow-card-hover'">
              仅已拥有
            </button>
          </div>
          <div v-for="m in synthMaterials" :key="m.albumId" @click="toggleMaterial(m.albumId)"
            class="flex cursor-pointer items-center gap-3 rounded-xl px-3 py-3 transition-colors hover:bg-slate-100"
            :class="synthChecked.has(m.albumId) ? 'text-slate-900' : 'text-slate-500'">
            <span class="flex h-5 w-5 shrink-0 items-center justify-center rounded border-2 text-xs transition-all"
              :class="synthChecked.has(m.albumId) ? 'border-blue-600 bg-blue-600 text-white' : 'border-slate-200'">
              {{ synthChecked.has(m.albumId) ? '✓' : '' }}
            </span>
            <span class="flex-1 truncate text-sm">{{ m.name }}</span>
            <span class="text-xs text-slate-400">GID {{ m.albumId }}</span>
            <span class="text-xs font-medium" :class="(synthOwned[m.albumId]||0) > 0 ? 'text-green-600' : 'text-slate-300'">×{{ synthOwned[m.albumId] || 0 }}</span>
          </div>
        </div>
        <div v-else-if="synthSelected" class="py-8 text-center text-sm text-slate-400">
          材料列表为空，将直接提交给 iBox
        </div>

        <div class="flex gap-3">
          <input v-model="synthQty" placeholder="合成数量" class="h-12 w-20 rounded-xl border border-slate-200 bg-slate-50 px-3 text-base outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50" />
          <select v-model="synthThreads" class="h-12 w-24 rounded-xl border border-slate-200 bg-slate-50 px-3 text-base outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50">
            <option v-for="i in 12" :key="i" :value="String(i)">{{ i }}线程</option>
          </select>
          <input v-model="synthFireTime" type="time" step="1" class="h-12 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-base outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50 flex-1" />
        </div>

        <button @click="synthToggle"
          :class="synthRunning ? 'bg-red-600 text-white' : 'bg-zinc-900 text-white hover:bg-zinc-800'"
          class="flex h-12 w-full items-center justify-center rounded-full text-base font-semibold transition-colors disabled:opacity-30">
          {{ synthRunning ? '停止' : '开始抢合 (数量' + (synthQty || 1) + (synthBatchChunk===10 ? ' · 每次10' : (synthAllowBatch ? ' · 批量' : ' · 每次1')) + ')' }}
        </button>

        <div v-if="synthCountdown" class="rounded-2xl bg-white shadow-[0_1px_2px_rgba(0,0,0,0.04)] ring-1 ring-black/[0.04] py-3 text-center">
          <div class="mb-1 text-xs text-slate-400">距离开抢</div>
          <div class="font-mono text-2xl font-bold tracking-wider text-blue-600">{{ synthCountdown }}</div>
        </div>

        <LogPanel :logs="synthLogs" title="抢合日志" variant="chat" />
      </div>

      <!-- ════════════════ PRESALE 抢购 ════════════════ -->
      <div v-if="mode==='presale'" class="space-y-5">
        <div class="rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
          <template v-if="presaleQuota.unlimited">管理员不限次</template>
          <template v-else>
            今日抢购剩余 <b>{{ presaleQuota.remaining }}</b> / {{ presaleQuota.limit }} 次（每次派发计1次，提100代理）
          </template>
        </div>
        <p class="text-sm text-slate-500">选择首发藏品 → 倒计时 → 自动预验证 → 到点下单</p>
        <p v-if="!_cachedProxy" class="rounded-xl bg-red-50 px-4 py-3 text-sm text-red-600">抢购需要私人代理IP，请在"我的"页面配置</p>
        <button v-if="_cachedProxy" @click="loadPresaleList" class="flex h-11 w-full items-center justify-center rounded-xl border border-slate-200 bg-slate-50 text-sm font-medium text-blue-600 transition-colors hover:bg-slate-100">获取首发列表</button>

        <div v-if="presaleItems.length" class="max-h-96 space-y-2 overflow-y-auto">
          <div v-for="it in presaleItems" :key="it.id" @click="selectPresale(it)"
            class="cursor-pointer rounded-xl border p-3 transition-colors"
            :class="presaleSelected?.id === it.id ? 'border-zinc-400 bg-slate-100' : 'border-slate-200 hover:shadow-card-hover'">
            <div class="flex items-start justify-between">
              <span class="flex-1 truncate text-sm font-medium text-slate-900">{{ it.digitalCollectionGroup?.name || 'GID '+it.groupId }}</span>
              <span class="ml-2 shrink-0 text-sm text-blue-600">¥{{ it.price }}</span>
            </div>
            <div class="mt-1 flex items-center justify-between">
              <span class="text-xs" :class="it.saleStatus===1 ? 'text-green-600' : it.saleStatus===0 ? 'text-blue-600' : 'text-slate-400'">
                {{ it.saleStatus===1 ? '发售中' : it.saleStatus===0 ? '即将开始' : it.saleStatus===2 ? '已结束' : '状态'+it.saleStatus }}
              </span>
              <span class="text-xs text-slate-400">限购{{ it.userOnceMaxBuyNum || '-' }}件</span>
            </div>
            <div class="mt-0.5 text-xs text-slate-400">{{ it.onSaleTime }}</div>
          </div>
        </div>

        <div v-if="presaleSelected" class="space-y-3 rounded-2xl bg-white shadow-[0_1px_2px_rgba(0,0,0,0.04)] ring-1 ring-black/[0.04] p-5">
          <div class="text-base font-semibold text-slate-900">{{ presaleSelected.digitalCollectionGroup?.name }}</div>
          <div class="flex gap-3 text-sm">
            <span class="text-slate-500">¥{{ presaleSelected.price }}</span>
            <span class="text-slate-400">限购{{ presaleSelected.userOnceMaxBuyNum || '-' }}件</span>
            <span class="text-slate-400">{{ presaleSelected.onSaleTime }}</span>
          </div>
          <div v-if="presaleCountdown" class="py-2 text-center font-mono text-2xl font-bold text-blue-600">{{ presaleCountdown }}</div>
          <div class="flex gap-3">
            <input v-model="presaleQty" type="number" placeholder="数量" class="h-12 w-24 rounded-xl border border-slate-200 bg-slate-50 px-3 text-base outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50" :max="presaleSelected.userOnceMaxBuyNum" :min="1" />
            <input v-model="presaleFireTime" type="time" step="1" class="h-12 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-base outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50 flex-1" />
          </div>
          <label class="flex h-10 items-center justify-between text-sm font-medium">
            <span class="text-slate-600">自动支付</span>
            <input type="checkbox" v-model="presaleAutoPay" class="peer sr-only" />
            <span class="relative h-6 w-11 rounded-full bg-slate-200 transition-colors after:absolute after:left-1 after:top-1 after:h-4 after:w-4 after:rounded-full after:bg-white after:transition-transform peer-checked:bg-blue-600 peer-checked:after:translate-x-5 peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-blue-600"></span>
          </label>
          <input v-if="presaleAutoPay" v-model="consignPwd" type="password" placeholder="支付密码" class="h-10 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-sm outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50" />
          <button @click="presaleToggle"
            :class="presaleRunning ? 'bg-red-600 text-white' : 'bg-zinc-900 text-white hover:bg-zinc-800'"
            :disabled="!_cachedProxy"
            class="flex h-12 w-full items-center justify-center rounded-full text-base font-semibold transition-colors disabled:opacity-30">
            {{ presaleRunning ? '停止' : '开始抢购' }}
          </button>
        </div>

        <LogPanel :logs="presaleLogs" title="抢购日志" variant="chat" />
      </div>

      <!-- ════════════════ PRECISION 精准射 ════════════════ -->
      <div v-if="mode==='precision'" class="space-y-5">
        <p class="text-sm text-slate-500">搜藏品 → 贴UUID匹配 → 加载持仓 → 精准卖出</p>

        <div v-if="precisionGid" class="flex gap-2">
          <input v-model="precisionUuid" placeholder="粘贴求购订单号 (orderUuid)" class="h-10 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-sm outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50 flex-1" @keyup.enter="searchPrecisionUuid" />
          <button @click="searchPrecisionUuid" :disabled="precisionUuidLoading || !precisionUuid" class="inline-flex h-10 shrink-0 items-center justify-center rounded-xl bg-blue-600 px-4 text-sm font-semibold text-white transition-colors hover:bg-blue-700 disabled:opacity-30">{{ precisionUuidLoading ? '搜索中' : '匹配' }}</button>
        </div>

        <div
          v-if="precisionResult"
          class="rounded-xl px-4 py-2 text-sm"
          :class="precisionResult.includes('成功') || precisionResult.includes('已匹配')
            ? 'bg-green-50 text-green-700'
            : precisionResult.includes('未找到') || precisionResult.includes('失败') || precisionResult.includes('错误')
              ? 'bg-red-50 text-red-600'
              : 'bg-slate-50 text-slate-500'"
        >{{ precisionResult }}</div>

        <div v-if="precisionSelectedOrder" class="space-y-2 rounded-xl border border-slate-200 bg-slate-50 p-4">
          <div class="flex items-center gap-2">
            <span class="rounded-full bg-green-100 px-2 py-0.5 text-xs font-medium text-green-700">已匹配</span>
            <span class="text-lg font-bold text-slate-900">¥{{ precisionSelectedOrder.price }}</span>
          </div>
          <div class="grid grid-cols-2 gap-x-4 gap-y-1 text-xs">
            <span class="text-slate-500">订单号</span><span class="truncate font-mono text-slate-900">{{ precisionSelectedOrder.orderUuid }}</span>
            <span class="text-slate-500">时间</span><span class="text-slate-900">{{ precisionSelectedOrder.createdAt }}</span>
            <span class="text-slate-500">内部ID</span><span class="font-mono text-slate-900">{{ precisionSelectedOrder.id }} / {{ precisionSelectedOrder.orderRelationId }}</span>
          </div>
        </div>

        <div v-if="precisionSelectedOrder" class="space-y-3 rounded-2xl bg-white shadow-[0_1px_2px_rgba(0,0,0,0.04)] ring-1 ring-black/[0.04] p-5">
          <div class="flex items-center justify-between">
            <span class="text-sm text-slate-500">持仓操作</span>
            <button @click="loadPrecisionHoldings" :disabled="precisionHoldingsLoading" class="rounded-xl border border-slate-200 px-3 py-1.5 text-xs text-slate-500 transition-colors hover:text-slate-900 disabled:opacity-30">{{ precisionHoldingsLoading ? '加载中...' : precisionHoldings.length ? precisionHoldings.length+'件' : '加载持仓' }}</button>
          </div>
          <select v-if="precisionHoldings.length" v-model="precisionSelectedHolding" class="h-10 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-sm outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50">
            <option :value="null" disabled>选择要卖出的藏品...</option>
            <option v-for="h in precisionHoldings" :key="h.id" :value="h">{{ h.name || '#'+h.tokenId }} (#{{ h.id }})</option>
          </select>
          <input v-model="precisionPwd" type="password" placeholder="寄售密码" class="h-10 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-sm outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50" />
          <button @click="doPrecisionSell" :disabled="precisionRunning" class="flex h-12 w-full items-center justify-center rounded-xl bg-zinc-900 text-base font-semibold text-white transition-colors hover:bg-zinc-800 disabled:opacity-50">{{ precisionRunning ? '执行中...' : '精准卖出' }}</button>
        </div>
      </div>

      <!-- ════════════════ RANK 打榜 ════════════════ -->
      <div v-if="mode==='rank'" class="space-y-5">
        <div class="overflow-hidden rounded-xl bg-slate-50 text-xs leading-relaxed text-slate-600">
          <button type="button" @click="rankRulesOpen = !rankRulesOpen"
            class="flex w-full items-center justify-between gap-3 px-4 py-3 text-left transition-colors hover:bg-slate-100/80">
            <span class="min-w-0 truncate text-slate-500">活动规则 · 2026-08-16 ~ 08-18（北京时间）</span>
            <span class="shrink-0 text-[11px] text-slate-400">{{ rankRulesOpen ? '收起' : '展开' }}</span>
          </button>
          <div v-show="rankRulesOpen" class="space-y-2 border-t border-slate-200/70 px-4 pb-4 pt-3">
            <p>活动：2026-08-16 18:18:18 ~ 2026-08-18 18:18:18（北京时间）</p>
            <p><span class="font-medium text-emerald-700">绿色长条气球</span>：活动期内，每向<strong>一位新卖家</strong>买满 100 元，估 1 个（同一卖家只计 1 次）</p>
            <p><span class="font-medium text-blue-700">蓝色长条气球</span>：活动期内，每卖给<strong>一位新买家</strong>满 100 元，估 1 个（同一买家只计 1 次）</p>
            <p class="text-slate-400">紫色长条气球靠自己持仓，本工具不估算、不代囤。预估仅供参考，以官方空投为准。</p>
            <p class="text-slate-400">自动打榜只碰未交易过的对手；暂时没有新对手会等待，不会重复刷同一人。</p>
            <p class="text-slate-400">只扫寄售<strong>第一页</strong>，同地板价取前约 <strong>10</strong> 单；上架 = <strong>地板 + 上架溢价</strong>。挂仓库其他编号；售出记录确认后才买下一单；约 <strong>3 分钟</strong>未售则下架换编号并重拉地板再挂。</p>
          </div>
        </div>

        <div class="flex flex-wrap gap-2">
          <span class="text-xs text-slate-400 self-center">推荐：</span>
          <button type="button" @click="rankPickDefaultPanda"
            class="rounded-full border border-zinc-900 bg-zinc-900 px-3 py-1 text-xs font-medium text-white transition-colors hover:bg-zinc-800">喜糖熊猫（水）·默认</button>
          <button type="button" @click="rankQuickSearch('2026回家')"
            class="rounded-full border border-slate-200 bg-white px-3 py-1 text-xs text-slate-600 transition-colors hover:border-zinc-400 hover:text-slate-900">2026回家</button>
        </div>

        <div class="grid grid-cols-2 gap-2">
          <div>
            <div class="mb-1 text-[11px] text-slate-400">目标新对手数</div>
            <input v-model="rankTarget" type="number" min="1" placeholder="10" class="h-12 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-sm outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50" />
          </div>
          <div>
            <div class="mb-1 text-[11px] text-slate-400">上架溢价 ¥（地板 + 溢价）</div>
            <input v-model="rankMarkup" type="number" step="0.1" placeholder="0"
              class="h-12 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-sm outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50" />
            <div v-if="rankFloor != null" class="mt-1 text-[11px] text-emerald-600">
              预计上架 ¥{{ (Number(rankFloor) + Number(rankMarkup || 0)).toFixed(2) }}
            </div>
          </div>
        </div>

        <div>
          <div class="mb-1 text-[11px] text-slate-400">卖出底价 ¥（选藏品后自动填入，可手改，最低 100）</div>
          <div class="flex gap-2">
            <input v-model="rankSellMin" type="number" min="100" placeholder="选藏品后自动填入"
              class="h-12 min-w-0 flex-1 rounded-xl border border-slate-200 bg-white px-3 text-base font-semibold text-slate-900 outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50" />
            <button type="button" @click="rankFetchFloor({ silent: false })" :disabled="!rankGid || rankFloorLoading"
              class="inline-flex h-12 shrink-0 items-center justify-center rounded-xl bg-blue-600 px-4 text-sm font-semibold text-white transition hover:bg-blue-700 disabled:opacity-40">
              {{ rankFloorLoading ? '拉取中…' : '刷新地板价' }}
            </button>
          </div>
          <div class="mt-1.5 text-[12px]" :class="rankFloor != null ? 'font-medium text-emerald-600' : 'text-slate-400'">
            <template v-if="rankFloorLoading">正在拉取市场地板…</template>
            <template v-else-if="rankFloor != null">当前市场地板 ¥{{ rankFloor }}，已写入上方底价（≥100）</template>
            <template v-else>选择藏品后自动拉取地板并填入；也可点右侧按钮刷新</template>
          </div>
        </div>
        <div class="flex gap-3">
          <input v-model="rankPayPwd" type="password" placeholder="支付密码" class="h-12 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-base outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50 flex-1" />
          <input v-model="rankConsignPwd" type="password" placeholder="寄售密码" class="h-12 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-base outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50 flex-1" />
        </div>

        <div class="flex gap-3">
          <button type="button" @click="rankRefreshEstimate" :disabled="!rankGid"
            class="flex h-12 flex-1 items-center justify-center rounded-full border border-slate-200 bg-white text-sm font-semibold text-slate-700 transition-colors hover:bg-slate-50 disabled:opacity-30">
            刷新预估
          </button>
          <button type="button" @click="rankRunning ? rankStop() : rankStart()" :disabled="!rankGid && !rankRunning"
            :class="rankRunning ? 'bg-red-600 text-white' : 'bg-zinc-900 text-white hover:bg-zinc-800'"
            class="flex h-12 flex-1 items-center justify-center rounded-full text-base font-semibold transition-colors disabled:opacity-30">
            {{ rankRunning ? '停止' : '开始打榜' }}
          </button>
        </div>

        <div v-if="rankEstimate" class="grid grid-cols-2 gap-2">
          <div class="rounded-xl bg-emerald-50 px-3 py-3 text-center ring-1 ring-emerald-100">
            <div class="text-[10px] font-medium text-emerald-600">绿色长条气球（估）</div>
            <div class="mt-1 text-2xl font-bold text-emerald-800">{{ rankEstimate.green ?? 0 }}</div>
          </div>
          <div class="rounded-xl bg-blue-50 px-3 py-3 text-center ring-1 ring-blue-100">
            <div class="text-[10px] font-medium text-blue-600">蓝色长条气球（估）</div>
            <div class="mt-1 text-2xl font-bold text-blue-800">{{ rankEstimate.blue ?? 0 }}</div>
          </div>
        </div>

        <LogPanel :logs="rankLogs" title="打榜日志" variant="chat" />
      </div>

      <!-- ════════════════ QUANT 量化出货 ════════════════ -->
      <div v-if="mode==='quant'" class="space-y-5">
        <div class="overflow-hidden rounded-xl bg-slate-50 text-xs leading-relaxed text-slate-600">
          <div class="space-y-1.5 px-4 py-3">
            <p>每次挂 <strong>1 件</strong>：挂单价 = 地板价 + 溢价（元，可负）。不做 100 兜底。</p>
            <p>以<strong>售出记录</strong>确认卖掉；约 <strong>3 分钟</strong>未售则<strong>先确认下架</strong>，再换<strong>其他编号</strong>重拉地板挂单（同编号下架后约有 3 分钟冷却）。</p>
            <p>成功出货达到「量化件数」后<strong>自动停止</strong>。</p>
            <p class="text-slate-400">挂单间隔约 5～8 秒；相对上次挂单地板跌超 20% 会判异常并重拉。</p>
          </div>
        </div>

        <div class="grid grid-cols-2 gap-2">
          <div>
            <div class="mb-1 text-[11px] text-slate-400">量化件数（成功售出）</div>
            <input v-model="quantTarget" type="number" min="1" step="1" placeholder="1"
              class="h-12 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-sm outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50" />
          </div>
          <div>
            <div class="mb-1 text-[11px] text-slate-400">溢价 ¥（相对地板，可正可负）</div>
            <input v-model="quantMarkup" type="number" step="0.1" placeholder="0"
              class="h-12 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-sm outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50" />
          </div>
        </div>

        <div>
          <div class="mb-1 text-[11px] text-slate-400">市场地板</div>
          <div class="flex gap-2">
            <div class="flex h-12 min-w-0 flex-1 items-center rounded-xl border border-slate-200 bg-white px-3 text-base font-semibold text-slate-900">
              <template v-if="quantFloorLoading">拉取中…</template>
              <template v-else-if="quantFloor != null">¥{{ quantFloor }}</template>
              <span v-else class="font-normal text-slate-400">选藏品后自动拉取</span>
            </div>
            <button type="button" @click="quantFetchFloor({ silent: false })" :disabled="!quantGid || quantFloorLoading"
              class="inline-flex h-12 shrink-0 items-center justify-center rounded-xl bg-zinc-900 px-4 text-sm font-semibold text-white transition hover:bg-zinc-800 disabled:opacity-40">
              {{ quantFloorLoading ? '…' : '刷新地板' }}
            </button>
          </div>
          <div class="mt-1.5 text-[12px]" :class="quantPreviewPrice != null ? 'font-medium text-emerald-600' : 'text-slate-400'">
            <template v-if="quantPreviewPrice != null">预计挂单价 ¥{{ quantPreviewPrice }}（地板 {{ quantFloor }} {{ Number(quantMarkup) >= 0 ? '+' : '' }}{{ quantMarkup }}）</template>
            <template v-else>填溢价并拉到地板后显示预计挂单价</template>
          </div>
        </div>

        <input v-model="quantConsignPwd" type="password" placeholder="寄售密码"
          class="h-12 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-base outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-50" />

        <button type="button" @click="quantRunning ? quantStop() : quantStart()" :disabled="!quantGid && !quantRunning"
          :class="quantRunning ? 'bg-red-600 text-white' : 'bg-zinc-900 text-white hover:bg-zinc-800'"
          class="flex h-12 w-full items-center justify-center rounded-full text-base font-semibold transition-colors disabled:opacity-30">
          {{ quantRunning ? '停止' : '开始量化出货' }}
        </button>

        <LogPanel :logs="quantLogs" title="出货日志" variant="chat" />
      </div>

      <!-- ════════════════ 公告锁定（本机直连 · 对齐 APK） ════════════════ -->
      <div v-if="mode==='announce'" class="space-y-5">
        <div class="rounded-2xl bg-white p-5 shadow-[0_1px_2px_rgba(0,0,0,0.04)] ring-1 ring-black/[0.04] space-y-3">
          <div class="text-base font-semibold text-slate-900">公告锁定 · 本机直连</div>
          <p class="text-sm text-slate-500 leading-relaxed">
            <template v-if="isYearVip">年卡 · 公告锁不限次 · 本机直连发现/锁定（不支付）</template>
            <template v-else>月卡 · 公告锁每日 3 次 · 本机直连发现/锁定（不支付）</template>
          </p>
          <p class="text-[12px] text-slate-400">
            开放：北京时间 {{ announceQuota.open_hours || '09:00–23:59' }} · 本地轮询约 350ms · 锁到即停并推送
          </p>
          <div class="text-[13px]" :class="announceQuota.open_now === false ? 'text-amber-600' : 'text-emerald-600'">
            <template v-if="announceQuota.open_now === false">当前时段已关闭（{{ announceQuota.open_hours }}）</template>
            <template v-else-if="announceQuota.unlimited">配额：不限次</template>
            <template v-else>今日剩余 {{ announceQuota.remaining }}/{{ announceQuota.limit }}</template>
          </div>
          <div class="flex gap-2">
            <button type="button" @click="announceOrderMode='single'"
              class="flex-1 h-10 rounded-xl text-sm font-medium border transition"
              :class="announceOrderMode==='single' ? 'bg-zinc-900 text-white border-zinc-900' : 'bg-white text-slate-600 border-slate-200'">
              普通下单
            </button>
            <button type="button" @click="announceOrderMode='batch'"
              class="flex-1 h-10 rounded-xl text-sm font-medium border transition"
              :class="announceOrderMode==='batch' ? 'bg-zinc-900 text-white border-zinc-900' : 'bg-white text-slate-600 border-slate-200'">
              批量下单
            </button>
          </div>
          <div v-if="announceOrderMode==='batch'" class="flex gap-2">
            <input v-model="announceMaxPrice" type="number" step="0.01" placeholder="钱包余额 ¥"
              class="flex-1 h-11 rounded-xl border border-slate-200 bg-slate-50 px-3 text-sm outline-none focus:border-blue-500" />
            <input v-model="announceMaxCount" type="number" placeholder="数量"
              class="w-24 h-11 rounded-xl border border-slate-200 bg-slate-50 px-3 text-sm outline-none focus:border-blue-500" />
          </div>
          <button type="button"
            @click="announceRunning ? announceStop() : announceStart()"
            :disabled="!announceCanStart && !announceRunning"
            :class="announceRunning ? 'bg-red-600 text-white' : 'bg-zinc-900 text-white hover:bg-zinc-800'"
            class="flex h-12 w-full items-center justify-center rounded-full text-base font-semibold transition-colors disabled:opacity-30">
            {{ announceRunning ? '停止公告锁定' : '开始公告锁定（本地）' }}
          </button>
          <div class="flex flex-wrap gap-2 justify-center text-[11px] text-slate-400">
            <a :href="FIRE_APK_URL" download="ibox-fire.apk" class="underline">也可下 APK</a>
            <span>·</span>
            <a :href="EXE_URL" download="ibox-fire.exe" class="underline">Windows 客户端</a>
          </div>
        </div>
        <LogPanel :logs="announceLogs" title="公告锁日志 · 本机直连" variant="chat" />
      </div>

      <!-- ════════════════ 历史任务 ════════════════ -->
      <div class="overflow-hidden rounded-2xl bg-white shadow-[0_1px_2px_rgba(0,0,0,0.04)] ring-1 ring-black/[0.04]">
        <button @click="historyOpen=!historyOpen; if(historyOpen) loadHistory()" class="flex w-full items-center justify-between px-4 py-3 text-sm text-slate-500 transition-colors hover:bg-slate-50">
          <span>历史任务 ({{ taskHistory.length }})</span>
          <span class="text-xs">{{ historyOpen ? '收起' : '展开' }}</span>
        </button>
        <div v-if="historyOpen" class="max-h-72 overflow-y-auto border-t border-slate-100">
          <div v-if="taskHistory.length===0" class="px-4 py-6 text-center text-xs text-slate-400">暂无历史任务</div>
          <div v-for="t in taskHistory" :key="t.task_id" class="flex items-center gap-2 border-b border-slate-100 px-3 py-2 text-xs last:border-0 transition-colors hover:bg-slate-50">
            <span class="shrink-0 rounded px-1.5 py-0.5 font-medium" :class="statusColor(t.status)">{{ statusLabel(t.status) }}</span>
            <span class="shrink-0 text-slate-400">{{ typeLabel(t.type) }}</span>
            <span class="flex-1 truncate text-slate-900">{{ t.cname || 'GID '+t.gid }}</span>
            <span class="shrink-0 text-slate-400">Y{{ t.price }} x{{ t.qty || 1 }}</span>
            <span class="w-16 shrink-0 text-right text-slate-400">{{ timeAgo(t.time) }}</span>
            <button v-if="t.status==='running' || t.status==='stopping'" @click="stopHistoryTask(t.task_id, t.type)" class="shrink-0 rounded px-2 py-0.5 text-red-600 transition-colors hover:bg-red-100">停</button>
          </div>
        </div>
      </div>

      <!-- ════════════════ 退出登录 ════════════════ -->
      <div class="mt-6 pt-6">
        <button @click="doLogout" class="flex h-11 w-full items-center justify-center rounded-2xl bg-white shadow-[0_1px_2px_rgba(0,0,0,0.04)] ring-1 ring-black/[0.04] text-sm font-medium text-slate-500 transition-colors hover:border-red-300 hover:text-red-600">
          退出登录
        </button>
      </div>
    </div>

    <!-- 点对点：确认卖家昵称 -->
    <div v-if="sweepSellerConfirm" class="fixed inset-0 z-[100] flex items-center justify-center bg-black/40 px-6" @click.self="cancelSweepSellerConfirm">
      <div class="w-full max-w-sm rounded-2xl bg-white p-5 shadow-xl">
        <h3 class="text-base font-semibold text-slate-900">确认卖家</h3>
        <p class="mt-2 text-sm leading-relaxed text-slate-600">
          定位到卖家：<b>{{ sweepSellerConfirm.name || '未知' }}</b>，确认是 TA？
        </p>
        <div class="mt-5 flex gap-3">
          <button type="button" @click="cancelSweepSellerConfirm"
            class="flex h-11 flex-1 items-center justify-center rounded-xl border border-slate-200 text-sm font-semibold text-slate-600">
            取消
          </button>
          <button type="button" @click="confirmSweepSeller"
            class="flex h-11 flex-1 items-center justify-center rounded-xl bg-zinc-900 text-sm font-semibold text-white hover:bg-zinc-800">
            确认
          </button>
        </div>
      </div>
    </div>

    <!-- 互刷确认弹层（手机端不用 window.confirm） -->
    <div v-if="swapConfirmOpen" class="fixed inset-0 z-[100] flex items-center justify-center bg-black/40 px-6" @click.self="cancelSwapEnter">
      <div class="w-full max-w-sm rounded-2xl bg-white p-5 shadow-xl">
        <h3 class="text-base font-semibold text-slate-900">即将进入互刷页</h3>
        <p class="mt-2 text-sm leading-relaxed text-slate-600">
          大小号请在互刷里分别登录（或粘贴 Token）。不要使用科技页主号登录，以免互相顶号。
        </p>
        <div class="mt-5 flex gap-3">
          <button type="button" @click="cancelSwapEnter"
            class="flex h-11 flex-1 items-center justify-center rounded-xl border border-slate-200 text-sm font-semibold text-slate-600">
            取消
          </button>
          <button type="button" @click="confirmSwapEnter"
            class="flex h-11 flex-1 items-center justify-center rounded-xl bg-zinc-900 text-white hover:bg-zinc-800 text-sm font-semibold text-white">
            确定
          </button>
        </div>
      </div>
    </div>

    <!-- 抢合进入提醒弹层 -->
    <div v-if="synthQuotaOpen" class="fixed inset-0 z-[100] flex items-center justify-center bg-black/40 px-6" @click.self="cancelSynthEnter">
      <div class="w-full max-w-sm rounded-2xl bg-white p-5 shadow-xl">
        <h3 class="text-base font-semibold text-slate-900">进入抢合</h3>
        <p class="mt-2 text-sm leading-relaxed text-slate-600">
          网站抢合<strong>不限次</strong>（站点转发）。APP 本地开火仍按卡档计次：年卡 <b>5</b> / 月卡 <b>3</b> / 其余 <b>2</b>。
          请确认活动与时间后再派发。
        </p>
        <div class="mt-5 flex gap-3">
          <button type="button" @click="cancelSynthEnter"
            class="flex h-11 flex-1 items-center justify-center rounded-xl border border-slate-200 text-sm font-semibold text-slate-600">
            取消
          </button>
          <button type="button" @click="confirmSynthEnter"
            class="flex h-11 flex-1 items-center justify-center rounded-xl bg-zinc-900 text-white hover:bg-zinc-800 text-sm font-semibold text-white">
            知道了，进入
          </button>
        </div>
      </div>
    </div>

    <!-- 抢购次数提醒弹层 -->
    <div v-if="presaleQuotaOpen" class="fixed inset-0 z-[100] flex items-center justify-center bg-black/40 px-6" @click.self="cancelPresaleEnter">
      <div class="w-full max-w-sm rounded-2xl bg-white p-5 shadow-xl">
        <h3 class="text-base font-semibold text-slate-900">抢购次数提醒</h3>
        <p class="mt-2 text-sm leading-relaxed text-slate-600">
          每个网站账号每天仅有 <b>1</b> 次抢购机会（每次派发提取 100 条代理并并发预存极验，计为 1 次）。
          <template v-if="!presaleQuota.unlimited">
            今日已用 {{ presaleQuota.used }} / {{ presaleQuota.limit }}，剩余 <b>{{ presaleQuota.remaining }}</b> 次。
          </template>
          请确认活动与时间后再派发，避免浪费次数。
        </p>
        <div class="mt-5 flex gap-3">
          <button type="button" @click="cancelPresaleEnter"
            class="flex h-11 flex-1 items-center justify-center rounded-xl border border-slate-200 text-sm font-semibold text-slate-600">
            取消
          </button>
          <button type="button" @click="confirmPresaleEnter"
            class="flex h-11 flex-1 items-center justify-center rounded-xl bg-zinc-900 text-white hover:bg-zinc-800 text-sm font-semibold text-white">
            知道了，进入
          </button>
        </div>
      </div>
    </div>
    </template>
  </div>
</template>

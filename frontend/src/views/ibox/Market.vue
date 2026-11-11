<script setup>
import { ref, watch, nextTick, onMounted, onActivated, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { Search, ChevronDown, Star, Bell, X } from 'lucide-vue-next'
import api from '@/api'
import SkeletonList from '@/components/SkeletonList.vue'
import { getIboxToken } from '@/utils/iboxSession'
import { createIboxClient } from '@/lib/iboxClient.js'
import { toggleIboxFocus } from '@/lib/iboxBrowse.js'
import { thumbUrl } from '@/lib/iboxThumb.js'
import HoldingsMvPane from '@/views/ibox/HoldingsMvPane.vue'

const router = useRouter()

/** 列表行高（与模板 py-3 + h-11 对齐）；虚拟窗口只挂载可视区 */
const ROW_H = 72
const OVERSCAN = 10
const listAnchor = ref(null)
const listTopPad = ref(0)
const listBotPad = ref(0)
const visibleRows = ref([])
let scrollRoot = null
let windowRaf = 0
let partialTimer = null
let pendingPartial = null

function findScrollRoot(el) {
  let n = el && el.parentElement
  while (n && n !== document.body && n !== document.documentElement) {
    try {
      const st = getComputedStyle(n)
      if (/(auto|scroll)/.test(st.overflowY) && n.scrollHeight > n.clientHeight + 1) return n
    } catch {}
    n = n.parentElement
  }
  return null
}

function updateListWindow() {
  windowRaf = 0
  const all = items.value
  const n = all.length
  if (!n) {
    visibleRows.value = []
    listTopPad.value = 0
    listBotPad.value = 0
    return
  }
  if (n <= 36) {
    visibleRows.value = all.map((data, index) => ({ data, index }))
    listTopPad.value = 0
    listBotPad.value = 0
    return
  }
  const anchor = listAnchor.value
  const viewH = window.innerHeight || 640
  let scrolledInto = 0
  if (anchor) {
    const top = anchor.getBoundingClientRect().top
    scrolledInto = Math.max(0, -top)
  }
  let start = Math.floor(scrolledInto / ROW_H) - OVERSCAN
  if (start < 0) start = 0
  let end = Math.ceil((scrolledInto + viewH) / ROW_H) + OVERSCAN
  if (end > n) end = n
  if (start > end) start = Math.max(0, end - 1)
  listTopPad.value = start * ROW_H
  listBotPad.value = (n - end) * ROW_H
  visibleRows.value = all.slice(start, end).map((data, index) => ({ data, index: start + index }))
}

function scheduleListWindow() {
  if (windowRaf) return
  windowRaf = requestAnimationFrame(updateListWindow)
}

function bindListScroll() {
  const next = findScrollRoot(listAnchor.value) || window
  if (scrollRoot && scrollRoot !== next) {
    try {
      scrollRoot.removeEventListener('scroll', scheduleListWindow)
    } catch {}
  }
  scrollRoot = next
  try {
    scrollRoot.addEventListener('scroll', scheduleListWindow, { passive: true })
  } catch {}
  scheduleListWindow()
}

function unbindListScroll() {
  if (scrollRoot) {
    try {
      scrollRoot.removeEventListener('scroll', scheduleListWindow)
    } catch {}
    scrollRoot = null
  }
  if (windowRaf) {
    cancelAnimationFrame(windowRaf)
    windowRaf = 0
  }
}

function flushPartialApply() {
  if (partialTimer) {
    clearTimeout(partialTimer)
    partialTimer = null
  }
  const p = pendingPartial
  pendingPartial = null
  if (p) applyMarketData(p.partial, p.reset)
}

function queuePartialApply(partial, reset) {
  pendingPartial = { partial, reset }
  if (partialTimer) return
  partialTimer = setTimeout(() => {
    partialTimer = null
    flushPartialApply()
  }, 280)
}

const TAB_KEY = 'crawl_top_tab'
function loadTopTab() {
  try {
    const t = localStorage.getItem(TAB_KEY)
    // 默认市场首页；仅用户显式选过 holdings 才记住
    if (t === 'holdings') return 'holdings'
    return 'market'
  } catch {
    return 'market'
  }
}
const crawlTab = ref(loadTopTab())
function setCrawlTab(t) {
  crawlTab.value = t === 'holdings' ? 'holdings' : 'market'
  try {
    localStorage.setItem(TAB_KEY, crawlTab.value)
  } catch {}
  if (crawlTab.value === 'market' && hasToken.value && !hasLoaded.value) {
    fetchMarket(true)
  }
}

const activeMarket = ref('activity')
const activeSegment = ref(-1)
const keyword = ref('')
// App 新接口 /public-service/v2/markets：0=24h 1=本日 2=本周 3=本月
const timeRange = ref(0)
const showTimeDropdown = ref(false)
const timeLabels = { 0: '24h', 1: '本日', 2: '本周', 3: '本月' }

const segments = ref([])
const items = ref([])
const loading = ref(false)
const refreshing = ref(false)
const fetchError = ref('')
const hasMore = ref(false)
const total = ref(0)
const pageNo = ref(1)
const pageSize = 50
const avgRiseFall = ref(0)
const flatAll = ref([])

const ICON_TIP_KEY = 'ibox_market_icon_tip_v1'
const showIconTip = ref(false)
try { showIconTip.value = !localStorage.getItem(ICON_TIP_KEY) } catch { showIconTip.value = true }
function dismissIconTip() {
  showIconTip.value = false
  try { localStorage.setItem(ICON_TIP_KEY, '1') } catch {}
}

// v2: sortField=volume|floorPrice，sort=desc|asc
const sortField = ref('volume')
const sortDir = ref('desc')

function toggleSort(field) {
  if (sortField.value === field) {
    sortDir.value = sortDir.value === 'desc' ? 'asc' : 'desc'
  } else {
    sortField.value = field
    sortDir.value = 'desc'
  }
  fetchMarket(true)
}

const markets = [
  { key: 'activity', label: '活动市场', source: '' },
  { key: 'followed', label: '我的关注', source: 'focus' },
]
const marketSource = ref('')

const hasToken = ref(!!getIboxToken())
function getToken() {
  return getIboxToken()
}
function syncAuth() {
  const prev = hasToken.value
  hasToken.value = !!getIboxToken()
  return { prev, now: hasToken.value }
}

function buildMarketListPath() {
  const pn = pageNo.value
  const ps = pageSize
  const tr = timeRange.value
  const seg = activeSegment.value
  const source = marketSource.value
  const focusType = activeMarket.value === 'followed' ? 'activity' : activeFocusTab.value
  const name = keyword.value.trim()
  let path = ''
  if (source === 'focus') {
    if (focusType === 'flash') {
      path = `/personal-center-qt/favorites/albums?pageNo=${pn}&pageSize=${ps}&sortField=dayVolume&sortOrder=desc`
    } else if (focusType === 'physical') {
      path = `/rwa-public-service/markets/focus?pageNo=${pn}&pageSize=${ps}&sortField=2&sortType=0`
    } else {
      path = `/public-service/markets/focus?pageNo=${pn}&pageSize=${ps}&sortField=2&sortType=0`
    }
  } else if (source === 'flash') {
    path = `/public-service-qt/market/listings?pageNo=${pn}&pageSize=${ps}&sortField=comprehensive&sortOrder=desc`
  } else if (source === 'physical') {
    path = `/rwa-public-service/markets?pageNo=${pn}&pageSize=${ps}&sortField=2&sortType=0`
  } else {
    // App 3.0.13：/public-service/v2/markets?sortField=volume&sort=desc&timeRange=
    path = `/public-service/v2/markets?pageNo=${pn}&pageSize=${ps}&sortField=${encodeURIComponent(sortField.value)}&sort=${sortDir.value}&timeRange=${tr}`
    if (seg !== -1 && seg !== '-1') path += `&segmentId=${seg}`
  }
  if (name) path += `&name=${encodeURIComponent(name)}`
  return path
}

function mapMarketItems(raw) {
  return (raw || []).map((it) => ({
    id: it.itemId || it.id || 0,
    name: it.name || '',
    coverPicUrl: it.coverUrl || it.coverPicUrl || '',
    floorPrice: it.floorPrice,
    issueNum: it.issueAmount || it.issueNum || 0,
    circulationNum: it.circulation || it.circulationNum || 0,
    tradeVolume: it.volume || it.tradeVolume || 0,
    riseFallPercentage: it.riseFallPercentage || 0,
    focus: it.focused || it.focus || 0,
    groupType: it.groupType || 0,
    itemType: it.itemType || '',
  }))
}

function sortMapped(arr) {
  const field = sortField.value === 'floorPrice' ? 'floorPrice' : 'tradeVolume'
  const dir = sortDir.value === 'asc' ? 1 : -1
  return [...arr].sort((a, b) => {
    const av = Number(a[field]) || 0
    const bv = Number(b[field]) || 0
    if (av !== bv) return (av - bv) * dir
    return (Number(b.tradeVolume) || 0) - (Number(a.tradeVolume) || 0)
  })
}

async function poolMap(arr, limit, fn) {
  const n = arr.length
  if (!n) return []
  const ret = new Array(n)
  let i = 0
  const workers = Array.from({ length: Math.min(limit, n) }, async () => {
    while (i < n) {
      const idx = i++
      ret[idx] = await fn(arr[idx], idx)
    }
  })
  await Promise.all(workers)
  return ret
}

/** App 合集 itemType=collection → 拆成藏品后再按成交量/地板价全局排序 */
async function flattenCollectionRows(client, raw, tr) {
  const standalone = []
  const cids = []
  const seenC = new Set()
  for (const it of raw || []) {
    if (String(it.itemType || '') === 'collection') {
      const cid = it.itemId || it.id
      if (cid && !seenC.has(cid)) {
        seenC.add(cid)
        cids.push(cid)
      }
    } else {
      standalone.push(it)
    }
  }
  const kids = []
  const seenA = new Set()
  await poolMap(cids, 6, async (cid) => {
    for (const ff of ['UNFOCUSED', 'FOCUSED']) {
      for (let page = 1; page <= 8; page++) {
        const path = `/public-service/v2/markets/collections/${cid}/albums?timeRange=${tr}&focusFilter=${ff}&pageNo=${page}&pageSize=20`
        const data = await client.get(path, { timeoutMs: 8000 })
        const lst = data?.data?.list || []
        for (const row of lst) {
          const id = row.itemId || row.id
          if (id && !seenA.has(id)) {
            seenA.add(id)
            kids.push(row)
          }
        }
        if (!data?.data?.hasMore || lst.length < 20) break
      }
    }
  })
  const merged = []
  const seen = new Set()
  for (const it of [...standalone, ...kids]) {
    const id = it.itemId || it.id
    if (!id || seen.has(id)) continue
    seen.add(id)
    merged.push(it)
  }
  return merged
}

function packMarket(rawItems, rawSeg, source) {
  const itemsMapped = sortMapped(mapMarketItems(rawItems))
  const rises = rawItems.map((it) => it.riseFallPercentage || 0)
  const avg = rises.length ? Math.round((rises.reduce((a, b) => a + b, 0) / rises.length) * 10) / 10 : 0
  return {
    status: 'ok',
    segments: (rawSeg || []).map((s) => ({ id: s.id, name: s.name, recommend: s.isRecommend || 0 })),
    items: itemsMapped,
    hasMore: false,
    total: itemsMapped.length,
    avgRiseFall: avg,
    flat: !source,
  }
}

/** 本机直连 sail-api。先出第一屏，再后台翻页拆合集。 */
function marketAuthSoftError(code) {
  // 同域反代/WAF 401 ≠ 本地票已死；绝不能文案诱导去清登录
  return {
    status: 'error',
    message: `行情接口异常(${code || '?'})，可重试`,
    code,
    soft_auth: true,
  }
}

async function fetchMarketLocal(token, { onPartial, isStale } = {}) {
  // 行情浏览：关 presence 触摸，避免进爬仓就连环日活/验活误踢
  const client = createIboxClient(token, { deviceIdMode: 'stable', touchPresence: false })
  const source = marketSource.value
  const tr = timeRange.value
  const segP = client.get(`/public-service/markets/segments?timeRange=${tr}&pageNo=1&pageSize=50`, { timeoutMs: 8000 })

  const emit = (rawList, rawSeg, partial) => {
    if (isStale && isStale()) return
    const packed = packMarket(rawList, rawSeg, source)
    packed.partial = !!partial
    onPartial && onPartial(packed)
    return packed
  }

  if (source) {
    const listPath = buildMarketListPath()
    const [segData, listData] = await Promise.all([
      segP,
      client.get(listPath, { timeoutMs: 8000 }),
    ])
    if (listData?.code === 401 || listData?.code === 403) {
      return marketAuthSoftError(listData.code)
    }
    if (listData?.net === 'fetch_fail' || (listData?.code && listData.code !== 0)) {
      return {
        status: 'error',
        message: listData.message || `加载失败(${listData.code})`,
        code: listData.code,
        net: listData.net,
      }
    }
    const rawSeg = segData?.data?.list || []
    const rawItems = await flattenCollectionRows(client, listData?.data?.list || [], tr)
    return emit(rawItems, rawSeg, false)
  }

  const sf = sortField.value
  const sd = sortDir.value
  const name = keyword.value.trim()
  const seg = activeSegment.value
  function pagePath(pn) {
    let path = `/public-service/v2/markets?pageNo=${pn}&pageSize=10&sortField=${encodeURIComponent(sf)}&sort=${sd}&timeRange=${tr}`
    if (seg !== -1 && seg !== '-1') path += `&segmentId=${seg}`
    if (name) path += `&name=${encodeURIComponent(name)}`
    return path
  }

  const first = await client.get(pagePath(1), { timeoutMs: 8000 })
  if (first?.code === 401 || first?.code === 403) {
    return marketAuthSoftError(first.code)
  }
  if (first?.net === 'fetch_fail' || (first?.code && first.code !== 0)) {
    return {
      status: 'error',
      message: first.message || `加载失败(${first.code})`,
      code: first.code,
      net: first.net,
    }
  }

  let rawSeg = []
  try {
    const segData = await segP
    rawSeg = segData?.data?.list || []
  } catch {}

  const firstList = [...(first?.data?.list || [])]
  const firstFlat = await flattenCollectionRows(client, firstList, tr)
  emit(firstFlat, rawSeg, true)
  if (isStale && isStale()) return packMarket(firstFlat, rawSeg, source)

  const hasMorePages = !!(first?.data?.hasMore && firstList.length)
  if (hasMorePages) {
    const maxPage = name ? 8 : 16
    const rest = []
    const pages = []
    for (let pn = 2; pn <= maxPage; pn++) pages.push(pn)
    await poolMap(pages, 4, async (pn) => {
      if (isStale && isStale()) return
      const listData = await client.get(pagePath(pn), { timeoutMs: 8000 })
      if (listData?.code === 401 || listData?.code === 403) return
      if (listData?.net === 'fetch_fail' || (listData?.code && listData.code !== 0)) return
      const lst = listData?.data?.list || []
      if (lst.length) rest.push(...lst)
    })
    if (isStale && isStale()) return packMarket(firstFlat, rawSeg, source)
    const restFlat = await flattenCollectionRows(client, rest, tr)
    const seen = new Set(firstFlat.map((it) => it.itemId || it.id))
    const allFlat = [...firstFlat]
    for (const it of restFlat) {
      const id = it.itemId || it.id
      if (!id || seen.has(id)) continue
      seen.add(id)
      allFlat.push(it)
    }
    return emit(allFlat, rawSeg, false)
  }
  return packMarket(firstFlat, rawSeg, source)
}

async function fetchMarketProxy(token) {
  const sf = sortField.value === 'volume' ? 2 : 0
  const st = sortDir.value === 'desc' ? 0 : 1
  const { data } = await api.get('/snipe/ibox-market', {
    params: {
      token,
      timeRange: timeRange.value,
      pageNo: pageNo.value,
      pageSize,
      segmentId: activeSegment.value,
      sortField: sf,
      sortType: st,
      source: marketSource.value || '',
      name: keyword.value.trim(),
    },
    timeout: 20000,
  })
  return data
}

let marketGen = 0

function applyMarketData(data, reset) {
  if (data.status !== 'ok') return
  fetchError.value = ''
  const all = data.items || []
  if (data.flat) {
    // 虚拟列表只挂载可视行，flat 一次灌入全量，不再「加载更多」切片
    flatAll.value = all
    items.value = all
    hasMore.value = false
    total.value = all.length
  } else if (reset) {
    items.value = all
    hasMore.value = data.hasMore || false
    total.value = data.total || 0
  } else {
    items.value.push(...all)
    hasMore.value = data.hasMore || false
    total.value = data.total || 0
  }
  if (reset) {
    if (data.segments?.length) segments.value = data.segments
    avgRiseFall.value = data.avgRiseFall || 0
  }
  if (reset && !keyword.value.trim()) {
    const snap = {
      items: data.flat ? all : items.value,
      segments: segments.value,
      hasMore: hasMore.value,
      total: total.value,
      avgRiseFall: avgRiseFall.value,
    }
    setCache(snap)
    persistSnap(snap)
  }
  nextTick(scheduleListWindow)
}

async function fetchMarket(reset = false) {
  const token = getToken()
  if (!token) return
  if (crawlTab.value !== 'market') return
  const gen = ++marketGen

  if (!reset && flatAll.value.length) {
    items.value = flatAll.value
    hasMore.value = false
    loading.value = false
    hasLoaded.value = true
    nextTick(scheduleListWindow)
    return
  }

  if (reset) {
    pageNo.value = 1
    fetchError.value = ''
    pendingPartial = null
    if (partialTimer) {
      clearTimeout(partialTimer)
      partialTimer = null
    }
    const mem = getCached()
    const disk = mem || readSnap()
    if (disk?.items?.length) {
      flatAll.value = disk.items || []
      items.value = flatAll.value
      segments.value = disk.segments || segments.value
      hasMore.value = false
      total.value = disk.total || disk.items.length
      avgRiseFall.value = disk.avgRiseFall || 0
      loading.value = false
      refreshing.value = true
      hasLoaded.value = true
      nextTick(() => {
        bindListScroll()
        scheduleListWindow()
      })
    } else {
      items.value = []
      flatAll.value = []
      loading.value = true
    }
  } else {
    loading.value = true
  }

  try {
    const isStale = () => gen !== marketGen
    let data = await fetchMarketLocal(token, {
      isStale,
      onPartial: (partial) => {
        if (isStale()) return
        queuePartialApply(partial, reset)
        loading.value = false
        refreshing.value = true
        hasLoaded.value = true
      },
    })
    if (isStale()) return
    flushPartialApply()
    // 同域 401/断连都回退站点代拉；机房出口与浏览器反代不是同一条路
    if (
      data.status !== 'ok' &&
      (data.soft_auth ||
        data.code === 401 ||
        data.code === 403 ||
        data.net === 'fetch_fail' ||
        /CORS|无响应|Failed to fetch|行情接口异常/i.test(data.message || ''))
    ) {
      data = await fetchMarketProxy(token)
      if (data?.status === 'ok' && Array.isArray(data.items)) {
        data.items = sortMapped(data.items)
        data.flat = true
      }
    }
    if (isStale()) return
    if (data.status === 'ok') {
      applyMarketData(data, reset)
    } else {
      fetchError.value = data.message || '加载失败，请重试'
      if (reset && !items.value.length) items.value = []
    }
  } catch (e) {
    if (gen !== marketGen) return
    console.error('Market fetch failed:', e)
    const msg = e?.message || '网络异常，请重试'
    if (/timeout|超时|aborted/i.test(msg)) {
      fetchError.value = '加载超时，请重试'
    } else if (/401|403|失效/.test(msg)) {
      fetchError.value = '行情加载异常，请重试（不会因此清掉登录）'
    } else {
      fetchError.value = msg
    }
    if (reset && !items.value.length) items.value = []
  }
  if (gen !== marketGen) return
  loading.value = false
  refreshing.value = false
  hasLoaded.value = true
}

function selectSegment(id) {
  activeSegment.value = id
  if (hasCache()) {
    const cached = getCached()
    items.value = cached.items
    segments.value = cached.segments || []
    hasMore.value = cached.hasMore
    total.value = cached.total
  } else {
    fetchMarket(true)
  }
}

const activeFocusTab = ref('activity')

function selectMarket(key) {
  activeMarket.value = key
  const m = markets.find(m => m.key === key)
  marketSource.value = m ? m.source : ''
  if (key === 'followed') { activeSegment.value = -1; segments.value = [] }
  if (hasCache()) {
    const cached = getCached()
    items.value = cached.items
    segments.value = cached.segments || []
    hasMore.value = cached.hasMore
    total.value = cached.total
  } else {
    fetchMarket(true)
  }
}

const focusErr = ref('')
async function toggleFocus(item) {
  const token = getToken()
  if (!token) return
  dismissIconTip()
  if (item.focus) {
    focusErr.value = 'iBox不支持取消关注，请在App内操作'
    setTimeout(() => focusErr.value = '', 3000)
    return
  }
  item.focus = 1
  try {
    const data = await toggleIboxFocus(token, item.id)
    if (data.status !== 'ok') {
      item.focus = 0
      focusErr.value = data.message || '操作失败'
      setTimeout(() => focusErr.value = '', 3000)
    }
  } catch { item.focus = 0; focusErr.value = '网络错误'; setTimeout(() => focusErr.value = '', 3000) }
}

const pushSet = ref(new Set())
async function loadPushList() {
  try { const r = await api.get('/follow/list'); (r.data||[]).forEach(f => pushSet.value.add(f.group_id)) } catch {}
}
async function togglePush(item) {
  if (!getToken()) return
  const gid = item.id
  const on = pushSet.value.has(gid)
  try {
    await api.post('/follow/toggle', null, { params: { group_id: gid, group_name: item.name || '' } })
    if (on) pushSet.value.delete(gid); else pushSet.value.add(gid)
    dismissIconTip()
  } catch {}
}

const loadedMarkets = ref(new Set())
const marketCache = ref({})
const hasLoaded = ref(false)

watch(items, () => nextTick(scheduleListWindow))
watch(crawlTab, (t) => {
  if (t === 'market') nextTick(bindListScroll)
})

onMounted(() => {
  syncAuth()
  loadPushList()
  if (crawlTab.value === 'market') fetchMarket(true)
  window.addEventListener('ibox-auth-changed', onAuthChanged)
  window.addEventListener('resize', scheduleListWindow, { passive: true })
  nextTick(bindListScroll)
})
onActivated(() => {
  const { prev, now } = syncAuth()
  if (crawlTab.value === 'market' && now && (!prev || !hasLoaded.value)) fetchMarket(true)
  nextTick(bindListScroll)
})
onUnmounted(() => {
  window.removeEventListener('ibox-auth-changed', onAuthChanged)
  window.removeEventListener('resize', scheduleListWindow)
  unbindListScroll()
  if (partialTimer) {
    clearTimeout(partialTimer)
    partialTimer = null
  }
})
function onAuthChanged() {
  const { prev, now } = syncAuth()
  if (crawlTab.value === 'market' && now && !prev) fetchMarket(true)
  if (!now) {
    items.value = []
    hasLoaded.value = false
    visibleRows.value = []
  }
}

function cacheKey() {
  return `${activeMarket.value}|${activeSegment.value}|${timeRange.value}|${activeFocusTab.value}|${sortField.value}|${sortDir.value}|${keyword.value}`
}

const SNAP_KEY = 'ibox_mkt_v2'
function persistSnap(payload) {
  if (keyword.value.trim()) return
  try {
    sessionStorage.setItem(SNAP_KEY, JSON.stringify({ key: cacheKey(), at: Date.now(), payload }))
  } catch {}
}
function readSnap() {
  try {
    const o = JSON.parse(sessionStorage.getItem(SNAP_KEY) || 'null')
    if (!o || o.key !== cacheKey()) return null
    if (Date.now() - (o.at || 0) > 5 * 60 * 1000) return null
    return o.payload
  } catch {
    return null
  }
}

function getCached() { return marketCache.value[cacheKey()] }
function setCache(data) { marketCache.value[cacheKey()] = data; loadedMarkets.value.add(cacheKey()) }
function hasCache() { return !!marketCache.value[cacheKey()] }

function goDetail(item) {
  router.push({
    path: `/ibox/detail/${item.id}`,
    query: {
      name: item.name || '',
      issueNum: item.issueNum || 0,
      circulationNum: item.circulationNum || 0,
      cover: item.coverPicUrl || '',
      floorPrice: item.floorPrice || 0,
    }
  })
}

let _searchTimer = null
function onSearchInput() {
  clearTimeout(_searchTimer)
  _searchTimer = setTimeout(() => fetchMarket(true), 500)
}
function onSearchEnter() {
  clearTimeout(_searchTimer)
  fetchMarket(true)
}

function loadMore() { pageNo.value++; fetchMarket(false) }

function fmtNum(n) {
  if (n == null) return '--'
  if (n >= 10000) return (n / 10000).toFixed(1) + '万'
  return n.toLocaleString()
}

</script>

<template>
  <div class="bg-slate-50 pb-4" style="overscroll-behavior: contain; -webkit-overflow-scrolling: touch">
    <div v-if="focusErr" class="fixed top-4 left-1/2 z-50 -translate-x-1/2 rounded-full bg-red-500 px-4 py-2 text-xs text-white shadow-lg">{{ focusErr }}</div>

    <!-- 顶层：市场（默认首页）| 持仓市值（点开才挂载加载） -->
    <div class="px-4 pt-3">
      <div class="flex gap-1.5 rounded-2xl bg-zinc-100/80 p-1">
        <button
          type="button"
          class="flex-1 rounded-xl py-2 text-[13px] font-medium transition-colors"
          :class="crawlTab === 'market'
            ? 'bg-white text-zinc-900 shadow-[0_1px_2px_rgba(0,0,0,0.06)] ring-1 ring-black/[0.04]'
            : 'text-zinc-500 hover:text-zinc-700'"
          @click="setCrawlTab('market')"
        >市场</button>
        <button
          type="button"
          class="flex-1 rounded-xl py-2 text-[13px] font-medium transition-colors"
          :class="crawlTab === 'holdings'
            ? 'bg-white text-zinc-900 shadow-[0_1px_2px_rgba(0,0,0,0.06)] ring-1 ring-black/[0.04]'
            : 'text-zinc-500 hover:text-zinc-700'"
          @click="setCrawlTab('holdings')"
        >持仓市值</button>
      </div>
    </div>

    <!-- v-if：未点开不挂载、不请求；离开可销毁停估价 -->
    <HoldingsMvPane v-if="crawlTab === 'holdings'" />

    <template v-if="crawlTab === 'market'">
    <div v-if="!hasToken" class="px-4 py-16 text-center">
      <p class="text-sm font-medium text-zinc-800">请先登录 iBox 账号</p>
      <p class="mt-2 text-[13px] leading-relaxed text-zinc-500">
        站内账号管 VIP / 推送；iBox 手机号登录后才能看行情与做科技操作。
      </p>
      <button
        type="button"
        class="mt-6 inline-flex h-11 items-center justify-center rounded-xl bg-zinc-900 px-6 text-[14px] font-medium text-white"
        @click="router.push('/snipe')"
      >去科技页登录 iBox</button>
    </div>

    <template v-else>
      <div class="mx-4 mt-3 rounded-xl bg-zinc-900/[0.04] px-3.5 py-2.5 text-[12px] leading-relaxed text-zinc-600">
        仓位<strong class="font-medium text-zinc-800">爬仓分析</strong>：点开藏品 → 子页「爬仓分析」→ 一键分析。
      </div>

      <div v-if="showIconTip" class="mx-4 mt-2 flex items-start gap-2 rounded-xl border border-zinc-200 bg-white px-3.5 py-2.5 text-[12px] leading-relaxed text-zinc-600">
        <div class="min-w-0 flex-1">
          <span class="font-medium text-zinc-800">★ 星</span>＝iBox 关注（App 内取消）；
          <span class="font-medium text-zinc-800">铃铛</span>＝站内异动推送关注。
        </div>
        <button type="button" class="shrink-0 p-0.5 text-zinc-400" aria-label="关闭" @click="dismissIconTip"><X :size="14" /></button>
      </div>

      <div class="flex items-center gap-2 px-4 pt-3 pb-2">
        <div class="flex flex-1 gap-1.5 rounded-2xl bg-zinc-100/80 p-1">
          <button
            v-for="m in markets"
            :key="m.key"
            type="button"
            @click="selectMarket(m.key)"
            class="flex-1 rounded-xl py-2 text-[13px] font-medium transition-colors"
            :class="activeMarket === m.key
              ? 'bg-white text-zinc-900 shadow-[0_1px_2px_rgba(0,0,0,0.06)] ring-1 ring-black/[0.04]'
              : 'text-zinc-500 hover:text-zinc-700'"
          >{{ m.label }}</button>
        </div>
        <div class="relative shrink-0">
          <button type="button" @click="showTimeDropdown = !showTimeDropdown"
            class="inline-flex h-9 items-center gap-0.5 rounded-xl bg-zinc-100/80 px-3 text-[13px] font-medium text-zinc-700">
            {{ timeLabels[timeRange] }}
            <ChevronDown :size="14" class="text-zinc-400" />
          </button>
          <div v-if="showTimeDropdown" class="absolute right-0 top-10 z-20 min-w-[88px] overflow-hidden rounded-xl bg-white py-1 shadow-lg ring-1 ring-black/[0.06]">
            <button v-for="(label, val) in timeLabels" :key="val" type="button"
              @click="timeRange = Number(val); showTimeDropdown = false; fetchMarket(true)"
              class="w-full px-4 py-2 text-left text-[13px] transition-colors hover:bg-zinc-50"
              :class="timeRange === Number(val) ? 'font-semibold text-zinc-900' : 'text-zinc-600'">
              {{ label }}
            </button>
          </div>
        </div>
      </div>

      <nav v-if="activeMarket !== 'followed'" class="flex items-center gap-2 overflow-x-auto px-4 pb-2">
        <button v-for="seg in segments" :key="seg.id" type="button"
          @click="selectSegment(seg.id)"
          class="shrink-0 rounded-full px-3.5 py-1.5 text-[12px] transition-colors"
          :class="activeSegment === seg.id
            ? 'bg-zinc-900 font-medium text-white'
            : 'bg-zinc-100 font-medium text-zinc-500 hover:text-zinc-700'">
          {{ seg.name }}
        </button>
      </nav>

      <div class="px-4 py-2">
        <div class="flex items-center gap-2 rounded-xl border border-zinc-200 bg-zinc-50 px-3 py-2.5">
          <Search :size="18" class="shrink-0 text-zinc-400" />
          <input v-model="keyword" type="text" placeholder="输入藏品关键词"
            @input="onSearchInput" @keyup.enter="onSearchEnter"
            class="w-full bg-transparent text-sm text-zinc-900 outline-none placeholder:text-zinc-400">
        </div>
      </div>

      <div v-if="refreshing" class="px-4 pt-1 text-[11px] text-zinc-400">本机刷新行情…</div>
      <div class="flex items-center justify-between border-b border-zinc-100 px-4 py-3 text-[12px] text-zinc-400">
        <div class="flex items-center gap-1">
          <span>藏品名称</span>
          <span class="text-zinc-300">|</span>
          <span>发行流通</span>
        </div>
        <div class="flex items-center gap-4">
          <button type="button" @click="toggleSort('floorPrice')" class="flex items-center gap-0.5"
            :class="sortField === 'floorPrice' ? 'font-semibold text-zinc-900' : ''">
            地板价
            <span class="text-[10px]">{{ sortField === 'floorPrice' ? (sortDir === 'desc' ? '↓' : '↑') : '' }}</span>
          </button>
          <button type="button" @click="toggleSort('volume')" class="flex items-center gap-0.5"
            :class="sortField === 'volume' ? 'font-semibold text-zinc-900' : ''">
            成交量
            <span class="text-[10px]">{{ sortField === 'volume' ? (sortDir === 'desc' ? '↓' : '↑') : '' }}</span>
          </button>
        </div>
      </div>

      <div v-if="loading && !items.length" class="px-4 py-1">
        <SkeletonList variant="list" :rows="10" />
      </div>

      <div v-else-if="fetchError && !items.length" class="px-4 py-12 text-center">
        <p class="text-sm text-zinc-600">{{ fetchError }}</p>
        <div class="mt-4 flex flex-wrap items-center justify-center gap-2">
          <button type="button" class="inline-flex h-10 items-center rounded-xl bg-zinc-900 px-5 text-[13px] font-medium text-white" @click="fetchMarket(true)">重试</button>
          <button
            v-if="!hasToken"
            type="button"
            class="inline-flex h-10 items-center rounded-xl border border-zinc-200 bg-white px-5 text-[13px] font-medium text-zinc-800"
            @click="router.push('/snipe')"
          >去登录</button>
        </div>
      </div>

      <section v-else ref="listAnchor" class="px-4" style="min-height: 300px">
        <div v-if="listTopPad" :style="{ height: listTopPad + 'px' }" aria-hidden="true" />
        <div
          v-for="row in visibleRows"
          :key="row.data.id"
          @click="goDetail(row.data)"
          class="-mx-4 flex cursor-pointer items-center gap-2.5 rounded-xl border-b border-zinc-50 px-4 transition-colors active:bg-zinc-50"
          :style="{
            height: ROW_H + 'px',
            contentVisibility: 'auto',
            containIntrinsicSize: ROW_H + 'px',
          }"
        >
          <img
            v-if="row.data.coverPicUrl"
            :src="thumbUrl(row.data.coverPicUrl)"
            :alt="row.data.name"
            width="44"
            height="44"
            loading="lazy"
            decoding="async"
            class="h-11 w-11 shrink-0 rounded-xl bg-zinc-100 object-cover"
            @error="$event.target.style.display='none'"
          >
          <div v-else class="h-11 w-11 shrink-0 rounded-xl bg-zinc-100" />
          <div class="min-w-0 flex-1 pr-1">
            <div class="truncate text-sm font-semibold text-zinc-900">{{ row.data.name }}</div>
            <div class="mt-0.5 flex items-center gap-1.5">
              <span class="text-[10px] text-zinc-400">发行{{ fmtNum(row.data.issueNum) }}</span>
              <span class="text-[10px] text-zinc-300">·</span>
              <span class="text-[10px] text-zinc-400">流通{{ fmtNum(row.data.circulationNum) }}</span>
              <span v-if="row.data.riseFallPercentage"
                class="shrink-0 text-[11px] font-semibold"
                :class="row.data.riseFallPercentage >= 0 ? 'text-red-500' : 'text-emerald-600'">
                {{ row.data.riseFallPercentage >= 0 ? '+' : '' }}{{ row.data.riseFallPercentage }}%
              </span>
            </div>
          </div>
          <Star :size="16" class="shrink-0 cursor-pointer transition-transform active:scale-125"
            :class="row.data.focus ? 'fill-zinc-900 text-zinc-900' : 'text-zinc-300'"
            @click.stop="toggleFocus(row.data)" />
          <Bell :size="15" class="shrink-0 cursor-pointer transition-transform active:scale-125"
            :class="pushSet.has(row.data.id) ? 'fill-red-400 text-red-400' : 'text-zinc-300'"
            @click.stop="togglePush(row.data)" />
          <div class="w-14 shrink-0 text-right">
            <div class="text-sm font-semibold text-zinc-900">{{ row.data.floorPrice ? '¥' + row.data.floorPrice : '--' }}</div>
          </div>
          <div class="w-10 shrink-0 text-right">
            <div class="text-sm font-medium text-zinc-600">{{ row.data.tradeVolume }}</div>
          </div>
        </div>
        <div v-if="listBotPad" :style="{ height: listBotPad + 'px' }" aria-hidden="true" />

        <div v-if="hasMore" class="py-4 text-center">
          <button type="button" @click="loadMore" :disabled="loading"
            class="rounded-full border border-zinc-200 px-6 py-2 text-sm font-medium text-zinc-700 transition hover:bg-zinc-50 disabled:opacity-50">
            {{ loading ? '加载中...' : '加载更多' }}
          </button>
        </div>

        <div v-if="!loading && !items.length" class="py-12 text-center">
          <p class="text-sm text-zinc-400">暂无数据</p>
        </div>
      </section>
    </template>
    </template>
  </div>
</template>

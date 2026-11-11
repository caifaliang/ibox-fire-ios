<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import api from '@/api'

const adminToken = ref(localStorage.getItem('admin_token') || '')
const adminAuthed = ref(false)
const loginUser = ref('admin')
const loginPass = ref('')
const loginErr = ref('')
const loginLoading = ref(false)

const tab = ref('collections')

const adminApi = {
  get(path, params = {}) {
    return api.get(path, { params: { ...params, admin_token: adminToken.value } })
  },
  post(path, data = {}) {
    return api.post(path, data, { params: { admin_token: adminToken.value } })
  },
}

async function doAdminLogin() {
  loginErr.value = ''
  loginLoading.value = true
  try {
    const r = await api.post('/snipe/admin/login', {
      username: loginUser.value,
      password: loginPass.value,
    })
    if (r.data.status === 'ok' && r.data.token) {
      adminToken.value = r.data.token
      localStorage.setItem('admin_token', r.data.token)
      adminAuthed.value = true
      onEnter()
    } else {
      loginErr.value = r.data.message || '登录失败'
    }
  } catch {
    loginErr.value = '网络错误'
  }
  loginLoading.value = false
}

function doAdminLogout() {
  adminToken.value = ''
  adminAuthed.value = false
  localStorage.removeItem('admin_token')
}

function onEnter() {
  if (tab.value === 'tech') loadTech()
  if (tab.value === 'users') loadUsers()
  if (tab.value === 'presence') startPresencePoll()
  else stopPresencePoll()
  if (tab.value === 'crawler') loadCrawlerAuth()
}

watch(tab, () => {
  if (!adminAuthed.value) return
  onEnter()
})

// ── 藏品检索 ──
const searchQ = ref('')
const searchResults = ref([])
const searchLoading = ref(false)
const searchMsg = ref('')
let searchTimer = null

function onSearchInput() {
  clearTimeout(searchTimer)
  searchTimer = setTimeout(doCollectionSearch, 280)
}

async function doCollectionSearch() {
  const q = searchQ.value.trim()
  searchLoading.value = true
  searchMsg.value = ''
  try {
    const r = await api.get('/collections/search', { params: { q } })
    const raw = r.data.items || r.data.results || r.data || []
    searchResults.value = (Array.isArray(raw) ? raw : []).filter((x) => x && x.id > 0)
    if (!searchResults.value.length && q) searchMsg.value = '无结果'
  } catch {
    searchResults.value = []
    searchMsg.value = '搜索失败'
  }
  searchLoading.value = false
}

function copyText(t) {
  const s = String(t || '')
  if (!s) return
  navigator.clipboard?.writeText(s).catch(() => {})
}

// ── 科技任务 ──
const MODULES = [
  { key: 'buy', name: '捡漏' },
  { key: 'sell', name: '卖求购' },
  { key: 'list', name: '上架' },
  { key: 'unlist', name: '下架' },
  { key: 'sweep', name: '点对点' },
  { key: 'swap', name: '互刷' },
  { key: 'synth', name: '抢合' },
  { key: 'presale', name: '抢购' },
  { key: 'precision', name: '精准射' },
  { key: 'rank', name: '打榜' },
  { key: 'quant', name: '量化出货' },
  { key: 'announce_lock', name: '公告锁定' },
]

const techModule = ref('') // '' = 全部（按模块分组展示）
const techStatus = ref('running')
const techTasks = ref([])
const techLoading = ref(false)
const techMsg = ref('')
const stoppingId = ref('')

/** 按模块分组；历史任务始终分模块，方便区分 */
const techGroups = computed(() => {
  const order = techModule.value
    ? MODULES.filter((m) => m.key === techModule.value)
    : MODULES
  const map = {}
  for (const t of techTasks.value) {
    const k = t.module || 'other'
    if (!map[k]) map[k] = []
    map[k].push(t)
  }
  const groups = []
  for (const m of order) {
    const list = map[m.key] || []
    if (!list.length && techModule.value !== m.key) continue
    const ok = list.filter((x) => x.outcome === '成功').length
    const fail = list.filter((x) => x.outcome === '失败').length
    const stopped = list.filter((x) => x.outcome === '已停止').length
    groups.push({
      key: m.key,
      name: m.name,
      tasks: list,
      ok,
      fail,
      stopped,
      running: list.filter((x) => x.live_status !== 'done').length,
    })
  }
  // 未识别类型
  const known = new Set(MODULES.map((m) => m.key))
  const other = techTasks.value.filter((t) => !known.has(t.module))
  if (other.length && !techModule.value) {
    groups.push({
      key: 'other',
      name: '其他',
      tasks: other,
      ok: other.filter((x) => x.outcome === '成功').length,
      fail: other.filter((x) => x.outcome === '失败').length,
      stopped: other.filter((x) => x.outcome === '已停止').length,
      running: 0,
    })
  }
  return groups
})

const techTotal = computed(() => techTasks.value.length)

async function loadTech() {
  techLoading.value = true
  techMsg.value = ''
  try {
    const r = await adminApi.get('/snipe/admin/tech-tasks', {
      module: techModule.value,
      status: techStatus.value,
      limit: 200,
    })
    if (r.data.status === 'error') {
      if (r.data.message === '未登录') doAdminLogout()
      techMsg.value = r.data.message || '加载失败'
      techTasks.value = []
    } else {
      techTasks.value = r.data.tasks || []
    }
  } catch {
    techMsg.value = '加载失败'
    techTasks.value = []
  }
  techLoading.value = false
}

function setTechModule(key) {
  techModule.value = key
  loadTech()
}

function setTechStatus(s) {
  techStatus.value = s
  loadTech()
}

async function stopTech(t) {
  if (!t?.task_id) return
  if (!confirm(`停止「${t.module_name || ''}」任务？`)) return
  stoppingId.value = t.task_id
  try {
    await adminApi.post('/snipe/admin/tech-stop', { task_id: t.task_id, type: t.type || t.module })
    await loadTech()
  } catch {
    techMsg.value = '停止失败'
  }
  stoppingId.value = ''
}

function outcomeClass(o) {
  if (o === '成功') return 'bg-emerald-50 text-emerald-700'
  if (o === '失败') return 'bg-red-50 text-red-600'
  if (o === '已停止') return 'bg-zinc-100 text-zinc-500'
  return 'bg-zinc-100 text-zinc-500'
}

function fmtTs(sec) {
  if (!sec) return ''
  const d = new Date(Number(sec) * 1000)
  if (Number.isNaN(d.getTime())) return ''
  const p = (n) => String(n).padStart(2, '0')
  return `${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`
}

function taskTitle(t) {
  return t.cname || (t.gid ? `GID ${t.gid}` : '') || t.detail || '—'
}

function fmtPrice(p) {
  if (p === null || p === undefined || p === '') return ''
  const n = Number(p)
  if (Number.isNaN(n)) return String(p)
  if (n === 0) return ''
  return Number.isInteger(n) ? String(n) : n.toFixed(2).replace(/\.?0+$/, '')
}

function fmtQty(q) {
  if (q === null || q === undefined || q === '') return ''
  const n = Number(q)
  if (Number.isNaN(n) || n === 0) return ''
  return String(n)
}

/** 中文：数量 / 价格 */
function qtyPriceText(t) {
  const parts = []
  const qty = fmtQty(t.qty)
  const price = fmtPrice(t.price)
  if (qty) parts.push(`数量 ${qty}`)
  if (price) parts.push(`价格 ¥${price}`)
  // 历史成交件数（抢合等）
  if (!qty && t.bought != null && Number(t.bought) > 0) {
    parts.push(`成交 ${t.bought}`)
  }
  return parts.join(' · ')
}

// ── 用户管理 ──
const userSearch = ref('')
const users = ref([])
const userTotal = ref(0)
const userPage = ref(1)
const usersLoading = ref(false)
const selectedUser = ref(null)
const vipDelta = ref(7)
const quotaDelta = ref(1)
const userMsg = ref('')
const cardKey = ref('')
const cardInfo = ref(null)
const cardMsg = ref('')

async function loadUsers() {
  usersLoading.value = true
  userMsg.value = ''
  try {
    const r = await adminApi.get('/snipe/admin/users', {
      q: userSearch.value.trim(),
      page: userPage.value,
      page_size: 40,
    })
    if (r.data.status === 'error') {
      if (r.data.message === '未登录') doAdminLogout()
      userMsg.value = r.data.message || '加载失败'
      users.value = []
    } else {
      users.value = r.data.users || []
      userTotal.value = r.data.total || 0
    }
  } catch {
    userMsg.value = '加载失败'
  }
  usersLoading.value = false
}

function searchUsers() {
  userPage.value = 1
  loadUsers()
}

function selectUser(u) {
  selectedUser.value = u
  userMsg.value = ''
}

async function adjustVip() {
  if (!selectedUser.value) return
  const days = parseInt(vipDelta.value, 10)
  if (!days) return
  try {
    const r = await adminApi.post('/snipe/admin/adjust-vip', {
      user_id: selectedUser.value.id,
      days,
    })
    if (r.data.status === 'ok') {
      userMsg.value = `VIP → ${r.data.vip_expires_at || '已取消'}`
      await loadUsers()
      const u = users.value.find((x) => x.id === selectedUser.value.id)
      if (u) selectedUser.value = u
    } else userMsg.value = r.data.message || '调整失败'
  } catch {
    userMsg.value = '调整失败'
  }
}

async function adjustQuota(kind) {
  if (!selectedUser.value) return
  const delta = parseInt(quotaDelta.value, 10)
  if (!delta) return
  try {
    const r = await adminApi.post('/snipe/admin/adjust-quota', {
      user_id: selectedUser.value.id,
      kind,
      delta,
    })
    if (r.data.status === 'ok') {
      const q = r.data.quota || {}
      const label = { synth: '抢合', presale: '抢购', announce_lock: '公告锁定' }[kind]
      userMsg.value = `${label} 剩余 ${q.remaining}/${q.limit}`
      await loadUsers()
      const u = users.value.find((x) => x.id === selectedUser.value.id)
      if (u) selectedUser.value = u
    } else userMsg.value = r.data.message || '调整失败'
  } catch {
    userMsg.value = '调整失败'
  }
}

async function lookupCard() {
  cardMsg.value = ''
  cardInfo.value = null
  const key = cardKey.value.trim()
  if (!key) {
    cardMsg.value = '请输入卡密'
    return
  }
  try {
    const r = await adminApi.get('/snipe/admin/card-lookup', { key })
    if (r.data.status === 'ok') cardInfo.value = r.data.card
    else cardMsg.value = r.data.message || '查询失败'
  } catch {
    cardMsg.value = '查询失败'
  }
}

function quotaText(u, kind) {
  const q = u?.quotas?.[kind]
  if (!q) return '—'
  if (q.unlimited) return '不限'
  return `${q.remaining}/${q.limit}`
}

const TABS = [
  { k: 'collections', n: '藏品检索' },
  { k: 'tech', n: '科技任务' },
  { k: 'users', n: '用户管理' },
  { k: 'presence', n: '日活' },
  { k: 'crawler', n: '爬虫票' },
]

// ── 新开寄售爬虫凭证（access + refresh，一次写入长期自动续）──
const crawlerStatus = ref(null)
const crawlerLoading = ref(false)
const crawlerMsg = ref('')
const crawlerAccess = ref('')
const crawlerRefresh = ref('')
const crawlerDevice = ref('')
const crawlerPaste = ref('')
const crawlerSaving = ref(false)

async function loadCrawlerAuth() {
  crawlerLoading.value = true
  crawlerMsg.value = ''
  try {
    const r = await adminApi.get('/snipe/admin/crawler-auth')
    if (r.data?.status === 'ok') crawlerStatus.value = r.data
    else crawlerMsg.value = r.data?.message || '加载失败'
  } catch {
    crawlerMsg.value = '加载失败'
  }
  crawlerLoading.value = false
}

function fillCrawlerFromBrowser() {
  try {
    const access = localStorage.getItem('snipeToken') || sessionStorage.getItem('snipeToken') || ''
    const refresh = localStorage.getItem('snipeRefreshToken') || sessionStorage.getItem('snipeRefreshToken') || ''
    const device =
      localStorage.getItem('ibox.login.deviceId') ||
      sessionStorage.getItem('ibox.login.deviceId') ||
      ''
    crawlerAccess.value = access.replace(/^Bearer\s+/i, '').trim()
    crawlerRefresh.value = (refresh || '').trim()
    crawlerDevice.value = (device || '').trim()
    crawlerMsg.value = crawlerRefresh.value
      ? '已填入本机票。请确认这是「专用爬虫小号」，不是你日常科技页账号'
      : '本机只有 access、没有 refresh——请用专用小号短信登录后再填，或抓包带 refreshToken'
  } catch {
    crawlerMsg.value = '读取本机登录态失败'
  }
}

function parseCrawlerPaste() {
  const text = String(crawlerPaste.value || '')
  const auth = text.match(/Authorization:\s*Bearer\s+(\S+)/i)
  const bare = text.match(/\b(eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)\b/)
  const rt =
    text.match(/refresh[_-]?token["'\s:=]+([A-Za-z0-9._\-]+)/i) ||
    text.match(/(?:^|[;\s])refreshToken=([A-Za-z0-9._\-]+)/i)
  const did =
    text.match(/DEVICE-ID:\s*(\S+)/i) ||
    text.match(/(?:^|[;\s])deviceId=(dev_[A-Za-z0-9]+)/i)
  if (auth) crawlerAccess.value = auth[1].trim()
  else if (bare) crawlerAccess.value = bare[1]
  if (rt) crawlerRefresh.value = rt[1].trim()
  if (did) crawlerDevice.value = did[1].trim()
  crawlerMsg.value = crawlerRefresh.value
    ? '已从粘贴解析出 access + refresh'
    : '已解析；未发现 refreshToken，过期后仍需再贴'
}

async function saveCrawlerAuth() {
  if (crawlerSaving.value) return
  const access = crawlerAccess.value.trim()
  const refresh = crawlerRefresh.value.trim()
  if (!access && !refresh) {
    crawlerMsg.value = '请填写 access 或 refresh'
    return
  }
  crawlerSaving.value = true
  crawlerMsg.value = '写入中…'
  try {
    const r = await adminApi.post('/snipe/admin/crawler-auth', {
      accessToken: access,
      refreshToken: refresh,
      deviceId: crawlerDevice.value.trim(),
      clear_stale_refresh: !refresh,
    })
    crawlerMsg.value = r.data?.message || (r.data?.status === 'ok' ? '已保存' : '失败')
    if (r.data?.status === 'ok') {
      crawlerStatus.value = r.data
      crawlerAccess.value = ''
      crawlerRefresh.value = ''
      crawlerPaste.value = ''
    }
  } catch (e) {
    crawlerMsg.value = e?.response?.data?.detail || e?.message || '保存失败'
  }
  crawlerSaving.value = false
}

const presence = ref(null)
const presenceLoading = ref(false)
const presenceErr = ref('')
const presenceOpen = ref(null)
const presenceRefreshing = ref(false)
const presenceRefreshMsg = ref('')
const presenceCopyMsg = ref('')
let presenceTimer = null
let presenceCopyTimer = null

function healthLabel(h) {
  return { ok: '有效', expired: '已过期', blocked: 'IP被封', error: '异常' }[h] || '未知'
}

async function copyPresenceToken(siteUserId) {
  if (!siteUserId) return
  presenceCopyMsg.value = '取票中…'
  try {
    const r = await adminApi.post('/snipe/admin/presence/token', {
      site_user_id: siteUserId,
    })
    if (r.data?.message === '未登录') { doAdminLogout(); return }
    if (r.data?.status !== 'ok' || !r.data?.token) {
      presenceCopyMsg.value = r.data?.message || '取票失败'
      return
    }
    const t = String(r.data.token)
    try {
      await navigator.clipboard.writeText(t)
      presenceCopyMsg.value = `已复制 Token（uid ${r.data.ibox_uid || siteUserId}）`
    } catch {
      // clipboard 失败时弹窗兜底
      window.prompt('复制 Token：', t)
      presenceCopyMsg.value = '已弹出 Token，请手动复制'
    }
  } catch {
    presenceCopyMsg.value = '取票失败'
  }
  if (presenceCopyTimer) clearTimeout(presenceCopyTimer)
  presenceCopyTimer = setTimeout(() => { presenceCopyMsg.value = '' }, 4000)
}

async function loadPresence() {
  if (!presence.value) presenceLoading.value = true
  presenceErr.value = ''
  try {
    const r = await adminApi.get('/snipe/admin/presence')
    if (r.data?.message === '未登录') { doAdminLogout(); return }
    if (r.data.status === 'ok') presence.value = r.data
    else presenceErr.value = r.data.message || '加载失败'
  } catch {
    presenceErr.value = '加载失败'
  }
  presenceLoading.value = false
}

async function refreshPresenceHoldings(siteUserId = 0) {
  if (presenceRefreshing.value) return
  presenceRefreshing.value = true
  presenceRefreshMsg.value = siteUserId ? '正在刷新该用户…' : '正在刷新全部有效票…'
  try {
    const r = await adminApi.post('/snipe/admin/presence/refresh', {
      site_user_id: siteUserId || 0,
      force: true,
    })
    if (r.data?.message === '未登录') { doAdminLogout(); return }
    if (r.data?.status === 'ok') {
      const d = r.data
      presenceRefreshMsg.value = `完成：成功 ${d.ok || 0} · 失败 ${d.fail || 0} · 跳过 ${d.skipped || 0} · 清票 ${d.cleared || 0}`
      await loadPresence()
    } else {
      presenceRefreshMsg.value = r.data?.message || '刷新失败'
    }
  } catch {
    presenceRefreshMsg.value = '刷新失败'
  }
  presenceRefreshing.value = false
}

function stopPresencePoll() {
  if (presenceTimer) {
    clearInterval(presenceTimer)
    presenceTimer = null
  }
}

function startPresencePoll() {
  stopPresencePoll()
  loadPresence()
  presenceTimer = setInterval(loadPresence, 5000)
}

onMounted(async () => {
  if (!adminToken.value) return
  adminAuthed.value = true
  try {
    const r = await adminApi.get('/snipe/admin/users', { page_size: 1 })
    if (r.data.status === 'error') {
      doAdminLogout()
      return
    }
  } catch {
    doAdminLogout()
    return
  }
  onEnter()
})

onUnmounted(() => {
  stopPresencePoll()
})
</script>

<template>
  <!-- 登录 -->
  <div v-if="!adminAuthed" class="flex min-h-[100dvh] items-center justify-center bg-[#f4f4f5] px-4">
    <form class="w-full max-w-[360px] rounded-2xl bg-white p-7 shadow-sm" @submit.prevent="doAdminLogin">
      <h1 class="text-[20px] font-semibold tracking-tight text-zinc-900">后台管理</h1>
      <p class="mt-1 text-[13px] text-zinc-500">请使用管理员账号登录</p>
      <label class="mt-6 block text-[12px] font-medium text-zinc-500">账号</label>
      <input v-model="loginUser" class="mt-1.5 h-11 w-full rounded-xl border border-zinc-200 bg-zinc-50/80 px-3.5 text-[15px] outline-none focus:border-zinc-400 focus:bg-white" autocomplete="username" />
      <label class="mt-3 block text-[12px] font-medium text-zinc-500">密码</label>
      <input v-model="loginPass" type="password" class="mt-1.5 h-11 w-full rounded-xl border border-zinc-200 bg-zinc-50/80 px-3.5 text-[15px] outline-none focus:border-zinc-400 focus:bg-white" autocomplete="current-password" />
      <p v-if="loginErr" class="mt-2 text-[12px] text-red-600">{{ loginErr }}</p>
      <button type="submit" :disabled="loginLoading" class="mt-5 h-11 w-full rounded-xl bg-zinc-900 text-[14px] font-medium text-white disabled:opacity-40">
        {{ loginLoading ? '登录中…' : '登录' }}
      </button>
    </form>
  </div>

  <div v-else class="admin-shell min-h-[100dvh] bg-[#f4f4f5] pb-20">
    <header class="sticky top-0 z-20 border-b border-zinc-200/70 bg-white/90 backdrop-blur-md">
      <div class="mx-auto flex max-w-6xl items-center justify-between px-4 py-3 sm:px-6">
        <div>
          <div class="text-[15px] font-semibold tracking-tight text-zinc-900">后台管理</div>
          <div class="text-[11px] text-zinc-400">藏品 · 科技 · 用户 · 日活 · 爬虫票</div>
        </div>
        <button type="button" class="rounded-lg px-2.5 py-1.5 text-[13px] text-zinc-500 hover:bg-zinc-100 hover:text-zinc-800" @click="doAdminLogout">退出</button>
      </div>
      <nav class="mx-auto flex max-w-6xl gap-0 px-2 sm:px-4">
        <button
          v-for="t in TABS"
          :key="t.k"
          type="button"
          class="relative flex-1 px-2 pb-3 pt-1 text-[13px] font-medium transition"
          :class="tab === t.k ? 'text-zinc-900' : 'text-zinc-400 hover:text-zinc-600'"
          @click="tab = t.k"
        >
          {{ t.n }}
          <span
            v-if="tab === t.k"
            class="absolute inset-x-4 bottom-0 h-0.5 rounded-full bg-zinc-900"
          />
        </button>
      </nav>
    </header>

    <main class="mx-auto max-w-6xl px-4 pt-5 sm:px-6">
      <!-- ═══ 藏品检索 ═══ -->
      <section v-if="tab === 'collections'" class="space-y-4">
        <div class="rounded-2xl bg-white p-4 shadow-sm sm:p-5">
          <div class="text-[13px] font-medium text-zinc-900">搜索藏品</div>
          <div class="mt-1 text-[12px] text-zinc-400">与站内检索相同，支持名称模糊匹配</div>
          <div class="mt-3 flex gap-2">
            <input
              v-model="searchQ"
              class="h-11 flex-1 rounded-xl border border-zinc-200 bg-zinc-50/50 px-3.5 text-[15px] outline-none focus:border-zinc-400 focus:bg-white"
              placeholder="输入藏品名称"
              @input="onSearchInput"
              @keydown.enter="doCollectionSearch"
            />
            <button type="button" class="h-11 shrink-0 rounded-xl bg-zinc-900 px-5 text-[13px] font-medium text-white" @click="doCollectionSearch">搜索</button>
          </div>
        </div>

        <div v-if="searchLoading" class="py-12 text-center text-[13px] text-zinc-400">搜索中…</div>
        <div v-else-if="searchMsg" class="py-12 text-center text-[13px] text-zinc-400">{{ searchMsg }}</div>
        <div v-else-if="!searchResults.length" class="py-16 text-center">
          <div class="text-[14px] text-zinc-400">输入名称开始检索</div>
        </div>
        <ul v-else class="overflow-hidden rounded-2xl bg-white shadow-sm">
          <li
            v-for="(it, i) in searchResults"
            :key="it.id || i"
            class="flex items-center gap-3 border-b border-zinc-100 px-4 py-3.5 last:border-0 sm:px-5"
          >
            <div class="min-w-0 flex-1">
              <div class="truncate text-[14px] font-medium text-zinc-900">{{ it.name }}</div>
              <div class="mt-0.5 flex flex-wrap items-center gap-x-2 text-[12px] text-zinc-400">
                <span class="font-mono">GID {{ it.id }}</span>
                <span
                  class="rounded px-1.5 py-px text-[10px] font-medium"
                  :class="it.consignment_status ? 'bg-emerald-50 text-emerald-700' : 'bg-zinc-100 text-zinc-500'"
                >{{ it.consignment_status ? '已开寄售' : '未开寄售' }}</span>
              </div>
            </div>
            <button type="button" class="shrink-0 rounded-lg px-2.5 py-1.5 text-[12px] font-medium text-zinc-600 hover:bg-zinc-100" @click="copyText(it.id)">复制</button>
          </li>
        </ul>
      </section>

      <!-- ═══ 科技任务 ═══ -->
      <section v-else-if="tab === 'tech'" class="space-y-4">
        <!-- 状态切换 -->
        <div class="flex flex-wrap items-center gap-3">
          <div class="inline-flex rounded-xl bg-white p-1 shadow-sm">
            <button
              type="button"
              class="rounded-lg px-4 py-2 text-[13px] font-medium transition"
              :class="techStatus === 'running' ? 'bg-zinc-900 text-white' : 'text-zinc-500 hover:text-zinc-800'"
              @click="setTechStatus('running')"
            >运行中</button>
            <button
              type="button"
              class="rounded-lg px-4 py-2 text-[13px] font-medium transition"
              :class="techStatus === 'done' ? 'bg-zinc-900 text-white' : 'text-zinc-500 hover:text-zinc-800'"
              @click="setTechStatus('done')"
            >历史任务</button>
          </div>
          <span class="text-[12px] text-zinc-400">{{ techTotal }} 条</span>
          <button type="button" class="ml-auto text-[12px] font-medium text-zinc-500 hover:text-zinc-800" @click="loadTech">刷新</button>
        </div>

        <div class="flex flex-col gap-4 lg:flex-row lg:items-start">
          <!-- 左侧模块导航 -->
          <aside class="shrink-0 lg:sticky lg:top-28 lg:w-44">
            <div class="rounded-2xl bg-white p-2 shadow-sm">
              <div class="px-2.5 pb-1.5 pt-1 text-[11px] font-medium uppercase tracking-wide text-zinc-400">功能模块</div>
              <button
                type="button"
                class="flex w-full items-center justify-between rounded-xl px-2.5 py-2 text-left text-[13px] transition"
                :class="techModule === '' ? 'bg-zinc-900 text-white' : 'text-zinc-600 hover:bg-zinc-50'"
                @click="setTechModule('')"
              >
                <span>全部模块</span>
              </button>
              <button
                v-for="m in MODULES"
                :key="m.key"
                type="button"
                class="mt-0.5 flex w-full items-center justify-between rounded-xl px-2.5 py-2 text-left text-[13px] transition"
                :class="techModule === m.key ? 'bg-zinc-900 text-white' : 'text-zinc-600 hover:bg-zinc-50'"
                @click="setTechModule(m.key)"
              >{{ m.name }}</button>
            </div>
          </aside>

          <!-- 右侧：按模块分块 -->
          <div class="min-w-0 flex-1 space-y-4">
            <div v-if="techLoading" class="rounded-2xl bg-white py-16 text-center text-[13px] text-zinc-400 shadow-sm">加载中…</div>
            <div v-else-if="techMsg" class="rounded-2xl bg-white py-10 text-center text-[13px] text-red-600 shadow-sm">{{ techMsg }}</div>
            <div v-else-if="!techGroups.length" class="rounded-2xl bg-white py-16 text-center text-[13px] text-zinc-400 shadow-sm">
              {{ techStatus === 'running' ? '当前没有运行中的任务' : '近 24 小时暂无历史任务' }}
            </div>

            <div
              v-for="g in techGroups"
              :key="g.key"
              class="overflow-hidden rounded-2xl bg-white shadow-sm"
            >
              <!-- 模块头 -->
              <div class="flex flex-wrap items-center gap-2 border-b border-zinc-100 px-4 py-3 sm:px-5">
                <h3 class="text-[15px] font-semibold text-zinc-900">{{ g.name }}</h3>
                <span class="rounded-md bg-zinc-100 px-1.5 py-0.5 text-[11px] font-medium text-zinc-500">{{ g.tasks.length }}</span>
                <template v-if="techStatus === 'done'">
                  <span v-if="g.ok" class="text-[11px] text-emerald-600">成功 {{ g.ok }}</span>
                  <span v-if="g.fail" class="text-[11px] text-red-500">失败 {{ g.fail }}</span>
                  <span v-if="g.stopped" class="text-[11px] text-zinc-400">停止 {{ g.stopped }}</span>
                </template>
                <span v-else-if="g.running" class="text-[11px] text-zinc-400">运行 {{ g.running }}</span>
              </div>

              <div v-if="!g.tasks.length" class="px-4 py-8 text-center text-[12px] text-zinc-400 sm:px-5">该模块暂无记录</div>
              <ul v-else class="divide-y divide-zinc-50">
                <li
                  v-for="t in g.tasks"
                  :key="t.task_id"
                  class="flex items-start gap-3 px-4 py-3.5 sm:px-5"
                >
                  <div class="min-w-0 flex-1">
                    <div class="flex flex-wrap items-center gap-2">
                      <span class="truncate text-[13px] font-medium text-zinc-800">{{ taskTitle(t) }}</span>
                      <span
                        v-if="techStatus === 'done'"
                        class="shrink-0 rounded-md px-1.5 py-0.5 text-[10px] font-semibold"
                        :class="outcomeClass(t.outcome)"
                      >{{ t.outcome || '—' }}</span>
                      <span
                        v-else
                        class="shrink-0 rounded-md bg-sky-50 px-1.5 py-0.5 text-[10px] font-medium text-sky-700"
                      >{{ t.live_status === 'stopping' ? '停止中' : '运行中' }}</span>
                    </div>
                    <div class="mt-1 text-[11px] leading-relaxed text-zinc-400">
                      <span v-if="t.username">{{ t.username }}</span>
                      <span v-if="t.gid"> · GID {{ t.gid }}</span>
                      <span v-if="t.started_at"> · {{ fmtTs(t.started_at) }}</span>
                      <span v-if="t.ended_at"> · {{ t.ended_at }}</span>
                    </div>
                    <div v-if="qtyPriceText(t)" class="mt-1 text-[12px] font-medium text-zinc-700">
                      {{ qtyPriceText(t) }}
                    </div>
                    <div v-if="techStatus === 'done' && t.detail" class="mt-0.5 truncate text-[11px] text-zinc-400">{{ t.detail }}</div>
                  </div>
                  <button
                    v-if="techStatus === 'running'"
                    type="button"
                    class="mt-0.5 shrink-0 rounded-lg px-2.5 py-1 text-[12px] font-medium text-red-600 hover:bg-red-50 disabled:opacity-40"
                    :disabled="stoppingId === t.task_id"
                    @click="stopTech(t)"
                  >{{ stoppingId === t.task_id ? '…' : '停止' }}</button>
                </li>
              </ul>
            </div>
          </div>
        </div>
      </section>

      <!-- ═══ 用户管理 ═══ -->
      <section v-else-if="tab === 'users'" class="space-y-4">
        <!-- 卡密 -->
        <div class="rounded-2xl bg-white p-4 shadow-sm sm:p-5">
          <div class="text-[13px] font-medium text-zinc-900">卡密查询</div>
          <div class="mt-3 flex gap-2">
            <input v-model="cardKey" class="h-10 flex-1 rounded-xl border border-zinc-200 bg-zinc-50/50 px-3 text-[14px] outline-none focus:border-zinc-400 focus:bg-white" placeholder="粘贴卡密" @keydown.enter="lookupCard" />
            <button type="button" class="h-10 rounded-xl bg-zinc-900 px-4 text-[13px] font-medium text-white" @click="lookupCard">查询</button>
          </div>
          <p v-if="cardMsg" class="mt-2 text-[12px] text-red-600">{{ cardMsg }}</p>
          <div v-if="cardInfo" class="mt-3 grid gap-2 rounded-xl bg-zinc-50 px-3.5 py-3 text-[13px] text-zinc-700 sm:grid-cols-3">
            <div><span class="text-zinc-400">状态</span> {{ cardInfo.used ? '已使用' : '未使用' }}</div>
            <div><span class="text-zinc-400">天数</span> {{ cardInfo.days }}</div>
            <div v-if="cardInfo.used"><span class="text-zinc-400">激活</span> {{ cardInfo.used_by || cardInfo.used_by_id }} <span v-if="cardInfo.used_at" class="text-zinc-400">{{ cardInfo.used_at }}</span></div>
          </div>
        </div>

        <div class="grid gap-4 lg:grid-cols-5">
          <!-- 用户列表 -->
          <div class="rounded-2xl bg-white p-4 shadow-sm lg:col-span-3 sm:p-5">
            <div class="flex items-center justify-between gap-2">
              <div class="text-[13px] font-medium text-zinc-900">用户</div>
              <span class="text-[11px] text-zinc-400">共 {{ userTotal }}</span>
            </div>
            <div class="mt-3 flex gap-2">
              <input v-model="userSearch" class="h-10 flex-1 rounded-xl border border-zinc-200 bg-zinc-50/50 px-3 text-[14px] outline-none focus:border-zinc-400 focus:bg-white" placeholder="搜索用户名" @keydown.enter="searchUsers" />
              <button type="button" class="h-10 rounded-xl bg-zinc-900 px-4 text-[13px] font-medium text-white" @click="searchUsers">搜索</button>
            </div>
            <p v-if="usersLoading" class="mt-4 text-[13px] text-zinc-400">加载中…</p>
            <ul v-else class="mt-3 max-h-[420px] overflow-y-auto divide-y divide-zinc-50">
              <li
                v-for="u in users"
                :key="u.id"
                class="cursor-pointer rounded-xl px-2.5 py-2.5 transition hover:bg-zinc-50"
                :class="selectedUser?.id === u.id ? 'bg-zinc-100' : ''"
                @click="selectUser(u)"
              >
                <div class="flex items-center justify-between gap-2">
                  <span class="text-[14px] font-medium text-zinc-900">{{ u.username }}</span>
                  <span class="text-[11px] text-zinc-400">{{ u.is_vip ? (u.vip_expires_at?.slice(0, 10) || 'VIP') : '免费' }}</span>
                </div>
                <div class="mt-1 flex flex-wrap gap-x-3 text-[11px] text-zinc-400">
                  <span>抢合 {{ quotaText(u, 'synth') }}</span>
                  <span>抢购 {{ quotaText(u, 'presale') }}</span>
                  <span>公告锁 {{ quotaText(u, 'announce_lock') }}</span>
                </div>
              </li>
            </ul>
          </div>

          <!-- 操作面板 -->
          <div class="rounded-2xl bg-white p-4 shadow-sm lg:col-span-2 sm:p-5">
            <div v-if="!selectedUser" class="flex h-full min-h-[200px] items-center justify-center text-[13px] text-zinc-400">
              从左侧选择用户
            </div>
            <template v-else>
              <div class="text-[15px] font-semibold text-zinc-900">{{ selectedUser.username }}</div>
              <div class="mt-1 text-[12px] text-zinc-400">
                {{ selectedUser.is_vip ? `VIP · ${selectedUser.vip_expires_at?.slice(0, 10) || ''}` : '免费用户' }}
              </div>
              <p v-if="userMsg" class="mt-3 rounded-lg bg-zinc-50 px-3 py-2 text-[12px] text-zinc-600">{{ userMsg }}</p>

              <div class="mt-5">
                <div class="text-[12px] font-medium text-zinc-500">VIP 天数（可负）</div>
                <div class="mt-2 flex gap-2">
                  <input v-model="vipDelta" type="number" class="h-10 w-24 rounded-xl border border-zinc-200 px-3 text-[14px]" />
                  <button type="button" class="h-10 flex-1 rounded-xl bg-zinc-900 text-[13px] font-medium text-white" @click="adjustVip">确认增减</button>
                </div>
              </div>

              <div class="mt-5">
                <div class="text-[12px] font-medium text-zinc-500">今日次数（正数加剩余）</div>
                <div class="mt-2 flex gap-2">
                  <input v-model="quotaDelta" type="number" class="h-10 w-20 rounded-xl border border-zinc-200 px-3 text-[14px]" />
                </div>
                <div class="mt-2 grid grid-cols-3 gap-2">
                  <button type="button" class="h-10 rounded-xl text-[12px] font-medium ring-1 ring-zinc-200 hover:bg-zinc-50" @click="adjustQuota('synth')">抢合</button>
                  <button type="button" class="h-10 rounded-xl text-[12px] font-medium ring-1 ring-zinc-200 hover:bg-zinc-50" @click="adjustQuota('presale')">抢购</button>
                  <button type="button" class="h-10 rounded-xl text-[12px] font-medium ring-1 ring-zinc-200 hover:bg-zinc-50" @click="adjustQuota('announce_lock')">公告锁</button>
                </div>
              </div>
            </template>
          </div>
        </div>
      </section>

      <!-- ═══ 日活 / 持仓快照 ═══ -->
      <section v-else-if="tab === 'presence'" class="space-y-4">
        <div class="grid gap-3 sm:grid-cols-3">
          <div class="rounded-2xl bg-white p-4 shadow-sm">
            <div class="text-[12px] text-zinc-400">今日日活</div>
            <div class="mt-1 text-[28px] font-semibold tracking-tight text-zinc-900">{{ presence?.dau ?? '—' }}</div>
          </div>
          <div class="rounded-2xl bg-white p-4 shadow-sm">
            <div class="text-[12px] text-zinc-400">15 分钟内在线</div>
            <div class="mt-1 text-[28px] font-semibold tracking-tight text-zinc-900">{{ presence?.online ?? '—' }}</div>
          </div>
          <div class="rounded-2xl bg-white p-4 shadow-sm">
            <div class="text-[12px] text-zinc-400">有效存票</div>
            <div class="mt-1 text-[28px] font-semibold tracking-tight text-zinc-900">{{ presence?.with_token ?? '—' }}</div>
          </div>
        </div>
        <div class="rounded-2xl bg-white p-4 shadow-sm sm:p-5">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <div>
              <div class="text-[13px] font-medium text-zinc-900">账号健康与持仓</div>
              <div class="mt-1 text-[12px] text-zinc-400">有效票加密落库 · 每 5 分钟自动刷仓 · 可手动刷新</div>
            </div>
            <div class="flex flex-wrap gap-2">
              <button
                type="button"
                class="h-9 rounded-xl border border-zinc-200 px-3 text-[12px] font-medium text-zinc-700 disabled:opacity-40"
                :disabled="presenceRefreshing"
                @click="refreshPresenceHoldings(0)"
              >{{ presenceRefreshing ? '刷仓中…' : '刷新全部持仓' }}</button>
              <button type="button" class="h-9 rounded-xl bg-zinc-900 px-3 text-[12px] font-medium text-white" @click="loadPresence">刷新列表</button>
            </div>
          </div>
          <p v-if="presenceRefreshMsg" class="mt-2 text-[12px] text-zinc-500">{{ presenceRefreshMsg }}</p>
          <p v-if="presenceCopyMsg" class="mt-2 text-[12px] text-emerald-600">{{ presenceCopyMsg }}</p>
          <p v-if="presenceErr" class="mt-3 text-[12px] text-red-600">{{ presenceErr }}</p>
          <p v-if="presenceLoading" class="mt-4 text-[13px] text-zinc-400">加载中…</p>
          <p v-else-if="!(presence?.users || []).length" class="mt-4 text-[13px] text-zinc-400">还没有人登录 iBox</p>
          <ul v-else class="mt-3 divide-y divide-zinc-50">
            <li v-for="u in presence.users" :key="u.site_user_id" class="py-3">
              <div class="flex w-full items-start justify-between gap-3">
                <button type="button" class="min-w-0 flex-1 text-left" @click="presenceOpen = presenceOpen === u.site_user_id ? null : u.site_user_id">
                  <div class="text-[14px] font-medium text-zinc-900">{{ u.username || u.site_user_id }}</div>
                  <div class="mt-1 flex flex-wrap gap-x-3 text-[11px] text-zinc-400">
                    <span>{{ healthLabel(u.health) }}</span>
                    <span v-if="u.has_token" class="text-emerald-600">已存票</span>
                    <span v-else class="text-zinc-300">无票</span>
                    <span v-if="u.phone_mask">{{ u.phone_mask }}</span>
                    <span v-if="u.ibox_uid">iBox {{ u.ibox_uid }}</span>
                    <span>持仓 {{ u.total_holdings }} / {{ u.total_kinds }} 种</span>
                  </div>
                  <div class="mt-1 text-[11px] text-zinc-400">最近 {{ u.last_seen || '—' }}<span v-if="u.holdings_at"> · 快照 {{ u.holdings_at }}</span></div>
                </button>
                <div class="flex shrink-0 flex-col items-end gap-1">
                  <button
                    v-if="u.has_token"
                    type="button"
                    class="rounded-lg border border-zinc-200 px-2 py-1 text-[11px] text-zinc-600 disabled:opacity-40"
                    :disabled="presenceRefreshing"
                    @click.stop="refreshPresenceHoldings(u.site_user_id)"
                  >刷仓</button>
                  <button
                    v-if="u.has_token"
                    type="button"
                    class="rounded-lg border border-emerald-200 bg-emerald-50 px-2 py-1 text-[11px] text-emerald-700"
                    @click.stop="copyPresenceToken(u.site_user_id)"
                  >复制Token</button>
                  <span class="text-[11px] text-zinc-400">{{ presenceOpen === u.site_user_id ? '收起' : '明细' }}</span>
                </div>
              </div>
              <ul v-if="presenceOpen === u.site_user_id" class="mt-2 space-y-1 rounded-xl bg-zinc-50 px-3 py-2">
                <li v-if="!(u.holdings || []).length" class="text-[12px] text-zinc-400">暂无持仓快照</li>
                <li v-for="(it, i) in u.holdings" :key="i" class="flex justify-between gap-3 text-[12px] text-zinc-700">
                  <span class="min-w-0 truncate">{{ it.name || '未命名' }}</span>
                  <span class="shrink-0 text-zinc-400">{{ it.holdNum }}</span>
                </li>
              </ul>
            </li>
          </ul>
        </div>
      </section>

      <!-- ═══ 爬虫票（新开寄售索引）═══ -->
      <section v-else-if="tab === 'crawler'" class="space-y-4">
        <div class="rounded-2xl bg-white p-4 shadow-sm sm:p-5">
          <div class="flex items-start justify-between gap-3">
            <div>
              <div class="text-[13px] font-medium text-zinc-900">新开寄售爬虫凭证（专用号）</div>
              <div class="mt-1 text-[12px] text-zinc-400">
                只用<strong>单独小号</strong>短信登录拿票，写入 <b>access + refresh + deviceId</b>，走 180 天自动续期。
                默认<strong>不借用</strong>其他用户票。勿把日常科技页个人号填进来（共 refresh 会互相顶号）。
              </div>
            </div>
            <button
              type="button"
              class="shrink-0 rounded-lg border border-zinc-200 px-2.5 py-1.5 text-[12px] text-zinc-600 hover:bg-zinc-50"
              @click="loadCrawlerAuth"
            >刷新状态</button>
          </div>

          <div v-if="crawlerLoading" class="mt-4 text-[13px] text-zinc-400">加载中…</div>
          <div v-else-if="crawlerStatus" class="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-4">
            <div class="rounded-xl bg-zinc-50 px-3 py-2">
              <div class="text-[10px] text-zinc-400">access</div>
              <div class="text-[14px] font-semibold" :class="crawlerStatus.has_access ? 'text-emerald-600' : 'text-red-500'">
                {{ crawlerStatus.has_access ? '有' : '无' }}
              </div>
            </div>
            <div class="rounded-xl bg-zinc-50 px-3 py-2">
              <div class="text-[10px] text-zinc-400">refresh</div>
              <div class="text-[14px] font-semibold" :class="crawlerStatus.has_refresh ? 'text-emerald-600' : 'text-amber-600'">
                {{ crawlerStatus.has_refresh ? '有' : '缺' }}
              </div>
            </div>
            <div class="rounded-xl bg-zinc-50 px-3 py-2">
              <div class="text-[10px] text-zinc-400">剩余</div>
              <div class="text-[14px] font-semibold text-zinc-800">{{ crawlerStatus.left_h ?? '—' }} h</div>
            </div>
            <div class="rounded-xl bg-zinc-50 px-3 py-2">
              <div class="text-[10px] text-zinc-400">device</div>
              <div class="truncate text-[12px] font-medium text-zinc-700">{{ crawlerStatus.deviceId || '—' }}</div>
            </div>
          </div>
          <p v-if="crawlerStatus?.hint" class="mt-2 text-[12px] text-zinc-500">{{ crawlerStatus.hint }}</p>
        </div>

        <div class="rounded-2xl bg-white p-4 shadow-sm sm:p-5 space-y-3">
          <div class="flex flex-wrap gap-2">
            <button
              type="button"
              class="rounded-xl bg-zinc-900 px-3 py-2 text-[12px] font-medium text-white"
              @click="fillCrawlerFromBrowser"
            >从本机填入（仅专用号）</button>
            <button
              type="button"
              class="rounded-xl border border-zinc-200 px-3 py-2 text-[12px] text-zinc-700 hover:bg-zinc-50"
              @click="parseCrawlerPaste"
            >解析下方粘贴</button>
          </div>
          <textarea
            v-model="crawlerPaste"
            rows="4"
            class="w-full rounded-xl border border-zinc-200 bg-zinc-50/50 px-3 py-2 text-[12px] font-mono outline-none focus:border-zinc-400 focus:bg-white"
            placeholder="可粘贴：整段抓包头 / Cookie（含 refreshToken=）/ 登录 JSON"
          />
          <div>
            <label class="text-[11px] text-zinc-400">access JWT</label>
            <textarea v-model="crawlerAccess" rows="2" class="mt-1 w-full rounded-xl border border-zinc-200 px-3 py-2 text-[12px] font-mono outline-none focus:border-zinc-400" placeholder="eyJ…" />
          </div>
          <div>
            <label class="text-[11px] text-zinc-400">refreshToken（关键，没有就还是天天换票）</label>
            <input v-model="crawlerRefresh" class="mt-1 h-10 w-full rounded-xl border border-zinc-200 px-3 text-[13px] font-mono outline-none focus:border-zinc-400" placeholder="续期票" />
          </div>
          <div>
            <label class="text-[11px] text-zinc-400">deviceId（可选，与登录时一致更稳）</label>
            <input v-model="crawlerDevice" class="mt-1 h-10 w-full rounded-xl border border-zinc-200 px-3 text-[13px] font-mono outline-none focus:border-zinc-400" placeholder="dev_… 或 UUID" />
          </div>
          <button
            type="button"
            class="h-11 w-full rounded-xl bg-emerald-600 text-[14px] font-semibold text-white disabled:opacity-50"
            :disabled="crawlerSaving"
            @click="saveCrawlerAuth"
          >{{ crawlerSaving ? '写入中…' : '写入并试续期' }}</button>
          <p v-if="crawlerMsg" class="text-[12px]" :class="crawlerMsg.includes('失败') || crawlerMsg.includes('缺') ? 'text-amber-600' : 'text-emerald-700'">{{ crawlerMsg }}</p>
        </div>
      </section>
    </main>
  </div>
</template>

<style scoped>
.admin-shell {
  font-family: system-ui, -apple-system, "Segoe UI", "PingFang SC", "Noto Sans SC", "Microsoft YaHei", sans-serif;
}
</style>

<script setup>
/**
 * 持仓市值（轻量）：对齐 APP 体验
 * - 一次拉全量持仓列表（浏览器失败则站点 /snipe/ibox-portfolio）
 * - 封面缩略图
 * - 估价走站点批量地板，浏览器不再逐藏品狂打 sail
 * - 仅挂载时加载一次；切回不强制重刷（点刷新才拉）
 */
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { Loader, RefreshCw } from 'lucide-vue-next'
import api from '@/api'
import { getIboxToken } from '@/utils/iboxSession'
import { fetchPortfolio as fetchPortfolioLocal } from '@/lib/iboxBrowse.js'
import { thumbUrl as makeThumbUrl } from '@/lib/iboxThumb.js'
import {
  loadHoldingsMvCache,
  saveHoldingsMvCache,
  loadPrevMv,
  savePrevMv,
} from '@/lib/holdingsMv.js'

const router = useRouter()
const cache = loadHoldingsMvCache()

const hasToken = ref(!!getIboxToken())
const loading = ref(false)
const pricing = ref(false)
const error = ref('')
const items = ref(cache?.items || [])
const quotes = ref(cache?.quotes || {})
const priced = ref(cache?.priced || 0)
const priceTotal = ref(cache?.priceTotal || 0)
const marketValue = ref(cache?.marketValue || 0)
const change = ref(cache?.change ?? null)
const changePct = ref(cache?.changePct ?? null)
const lastTs = ref(cache?.ts || '')
let stopPricing = false
let loadGen = 0

const kinds = computed(() => items.value.length)
const pieces = computed(() => items.value.reduce((s, g) => s + (g.holdNum || 0), 0))

function syncAuth() {
  hasToken.value = !!getIboxToken()
}

function quoteOf(gid) {
  return quotes.value[gid] || null
}

function fmtMoney(n) {
  if (n == null || !Number.isFinite(n)) return '--'
  return '¥' + n.toLocaleString('zh-CN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}

function fmtUnit(n) {
  if (n == null || !Number.isFinite(n)) return '--'
  return '¥' + (n % 1 ? n.toFixed(2) : String(n))
}

/** 封面缩略图：OSS 裁 80px，减轻流量 */
function thumbUrl(url) {
  return makeThumbUrl(url, { w: 80, h: 80 })
}

function persist(partial = {}) {
  saveHoldingsMvCache({
    items: items.value,
    quotes: quotes.value,
    priced: priced.value,
    priceTotal: priceTotal.value,
    marketValue: marketValue.value,
    change: change.value,
    changePct: changePct.value,
    ts: lastTs.value,
    ...partial,
  })
}

function mapGroups(list) {
  return (list || [])
    .map((it) => ({
      id: Number(it.id) || 0,
      name: String(it.name || ''),
      holdNum: Number(it.holdNum) || 0,
      coverPicUrl: String(it.coverPicUrl || ''),
      floorHint: Number(it.floorPrice || it.floorHint) > 0 ? Number(it.floorPrice || it.floorHint) : 0,
    }))
    .filter((g) => g.id > 0)
}

function sumMv(list, quoteMap) {
  return (list || []).reduce((s, g) => {
    const u = quoteMap[g.id]?.unit
    return s + (Number(u) || 0) * (Number(g.holdNum) || 0)
  }, 0)
}

async function fetchPricesViaSite(token, ids) {
  const prices = {}
  const chunk = 20
  for (let i = 0; i < ids.length; i += chunk) {
    if (stopPricing) break
    const part = ids.slice(i, i + chunk)
    try {
      const r = await api.get('/snipe/ibox-prices', {
        params: { token, ids: part.join(',') },
        timeout: 60000,
      })
      if (r.data?.status === 'ok' && r.data.prices) {
        Object.assign(prices, r.data.prices)
      }
    } catch {
      /* 单块失败继续 */
    }
    // 块间停顿，压低频率
    if (i + chunk < ids.length && !stopPricing) {
      await new Promise((r) => setTimeout(r, 800))
    }
  }
  return prices
}

async function runPricing(list, prevBaseline, gen) {
  stopPricing = false
  pricing.value = true
  priceTotal.value = list.length
  priced.value = 0
  const map = { ...quotes.value }
  const token = getIboxToken()
  try {
    // 先用列表自带 floorHint 填一版，立刻有数
    list.forEach((g) => {
      if (g.floorHint > 0 && !map[g.id]?.unit) {
        map[g.id] = { gid: g.id, unit: g.floorHint, source: 'hint' }
      }
    })
    quotes.value = { ...map }
    marketValue.value = sumMv(list, map)
    priced.value = Object.keys(map).length
    persist({ ready: false })

    const need = list.filter((g) => !map[g.id]?.unit || map[g.id]?.source === 'hint').map((g) => g.id)
    if (need.length && !stopPricing && gen === loadGen) {
      const prices = await fetchPricesViaSite(token, need)
      if (gen !== loadGen) return
      need.forEach((gid) => {
        const p = Number(prices[String(gid)] || prices[gid])
        if (p > 0) map[gid] = { gid, unit: p, source: 'floor' }
      })
      quotes.value = { ...map }
      priced.value = list.filter((g) => map[g.id]?.unit != null).length
      marketValue.value = sumMv(list, map)
      persist({ ready: false })
    }

    if (stopPricing || gen !== loadGen) return
    const mv = sumMv(list, quotes.value)
    marketValue.value = mv
    const prev = prevBaseline > 0 ? prevBaseline : loadPrevMv()
    if (prev > 0 && mv > 0) {
      change.value = Math.round((mv - prev) * 100) / 100
      changePct.value = Math.round(((mv - prev) / prev) * 10000) / 100
    } else {
      change.value = null
      changePct.value = null
    }
    savePrevMv(mv)
    lastTs.value = new Date().toLocaleTimeString('zh-CN', { hour12: false })
    persist({ ready: true })
  } finally {
    if (gen === loadGen) pricing.value = false
  }
}

async function load(force = false) {
  const token = getIboxToken()
  if (!token) {
    hasToken.value = false
    return
  }
  hasToken.value = true
  if (!force && (loading.value || pricing.value)) return
  // 非强制且已有列表：不自动重刷
  if (!force && items.value.length) return

  const gen = ++loadGen
  stopPricing = true
  loading.value = true
  error.value = ''
  const prevBaseline = marketValue.value > 0 ? marketValue.value : loadPrevMv()

  try {
    const rdata = await fetchPortfolioLocal(token)
    if (gen !== loadGen) return
    if (rdata?.status !== 'ok') {
      throw new Error(rdata?.message || '持仓拉取失败')
    }
    const list = mapGroups(rdata.items)
    items.value = list
    quotes.value = {}
    marketValue.value = 0
    priced.value = 0
    priceTotal.value = list.length
    loading.value = false
    if (list.length) await runPricing(list, prevBaseline, gen)
    else {
      change.value = null
      changePct.value = null
      persist({ ready: true })
    }
  } catch (e) {
    if (gen !== loadGen) return
    if (items.value.length) {
      error.value = '持仓刷新失败，仍显示上次数据'
      loading.value = false
      return
    }
    error.value = String(e?.message || e).slice(0, 140)
    loading.value = false
    pricing.value = false
  }
}

function refresh() {
  return load(true)
}

function onAuthChanged() {
  const was = hasToken.value
  syncAuth()
  if (hasToken.value && !was) load(true)
  if (!hasToken.value) {
    stopPricing = true
    items.value = []
    quotes.value = {}
  }
}

onMounted(() => {
  syncAuth()
  window.addEventListener('ibox-auth-changed', onAuthChanged)
  // 仅在用户点开「持仓市值」挂载时加载；有缓存先展示再静默补一次
  if (hasToken.value) {
    if (items.value.length) {
      // 有缓存：不强制全量重刷，用户点刷新才打
    } else {
      load(true)
    }
  }
})
onUnmounted(() => {
  stopPricing = true
  window.removeEventListener('ibox-auth-changed', onAuthChanged)
})
</script>

<template>
  <div>
    <div v-if="!hasToken" class="px-4 py-16 text-center">
      <p class="text-sm font-medium text-zinc-800">请先登录 iBox 账号</p>
      <p class="mt-2 text-[13px] leading-relaxed text-zinc-500">
        一次拉全量持仓 · 缩略图 · 站点低频估价（不狂打本机 sail）
      </p>
      <button
        type="button"
        class="mt-6 inline-flex h-11 items-center justify-center rounded-xl bg-zinc-900 px-6 text-[14px] font-medium text-white"
        @click="router.push('/snipe')"
      >去科技页登录 iBox</button>
    </div>

    <template v-else>
      <p class="mx-4 mt-2 text-[11px] text-zinc-400">
        全量持仓一次拉取 · 市值≈地板×数量 · 点刷新才重拉
      </p>

      <section
        class="relative mx-4 mt-2 overflow-hidden rounded-2xl p-5 text-white"
        style="background: linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%);"
      >
        <div class="mb-1 flex items-center justify-between">
          <span class="text-sm text-white/60">总持仓市值</span>
          <button
            type="button"
            class="flex items-center gap-1 text-white/50 transition-transform active:scale-90 disabled:opacity-50"
            :disabled="loading || pricing"
            @click="refresh"
          >
            <Loader v-if="loading || pricing" :size="14" class="animate-spin" />
            <RefreshCw v-else :size="14" />
          </button>
        </div>
        <div class="mt-1 text-3xl font-extrabold tracking-tight tabular-nums">
          <template v-if="marketValue > 0 || priced > 0">{{ fmtMoney(marketValue) }}</template>
          <template v-else-if="pricing || loading">计算中…</template>
          <template v-else>--</template>
        </div>
        <div v-if="pricing && priceTotal > 0" class="mt-3">
          <div class="mb-1 flex items-center justify-between text-xs text-white/50">
            <span>正在估价</span>
            <span>{{ priced }} / {{ priceTotal }}</span>
          </div>
          <div class="h-1 overflow-hidden rounded-full bg-white/10">
            <div
              class="h-full rounded-full bg-amber-400 transition-all duration-300"
              :style="{ width: Math.min(100, (priced / Math.max(1, priceTotal)) * 100) + '%' }"
            />
          </div>
        </div>
        <div class="mt-3 flex flex-wrap items-center gap-2 text-sm text-white/50">
          <span>{{ kinds }} 种</span>
          <span>·</span>
          <span>{{ pieces }} 件</span>
          <template v-if="change != null">
            <span
              class="font-semibold"
              :class="change >= 0 ? 'text-red-400' : 'text-emerald-400'"
            >
              {{ change >= 0 ? '+' : '' }}{{ fmtMoney(Math.abs(change)) }}
              ({{ changePct >= 0 ? '+' : '' }}{{ changePct }}%)
            </span>
          </template>
          <span v-if="lastTs" class="ml-auto text-xs text-white/30">{{ lastTs }}</span>
        </div>
      </section>

      <div v-if="error" class="mx-4 mt-3 rounded-xl bg-red-50 px-3 py-2 text-[12px] text-red-600">
        {{ error }}
        <button type="button" class="ml-2 underline" @click="refresh">重试</button>
      </div>

      <div v-if="loading && !items.length" class="mx-4 mt-4 space-y-2">
        <div v-for="i in 6" :key="i" class="h-14 animate-pulse rounded-xl bg-zinc-100" />
      </div>

      <section v-else-if="items.length" class="mx-4 mt-4 overflow-hidden rounded-2xl border border-zinc-100 bg-white">
        <div
          v-for="g in items"
          :key="g.id"
          class="flex items-center gap-2.5 border-b border-zinc-50 px-3 py-2.5 last:border-0"
        >
          <img
            v-if="thumbUrl(g.coverPicUrl)"
            :src="thumbUrl(g.coverPicUrl)"
            :alt="g.name"
            width="40"
            height="40"
            class="h-10 w-10 shrink-0 rounded-lg bg-zinc-100 object-cover"
            loading="lazy"
            decoding="async"
            @error="$event.target.style.display = 'none'"
          >
          <div v-else class="h-10 w-10 shrink-0 rounded-lg bg-zinc-100" />
          <div class="min-w-0 flex-1">
            <div class="truncate text-[13px] font-semibold text-zinc-900">{{ g.name }}</div>
            <div class="mt-0.5 text-[11px] text-zinc-400">×{{ g.holdNum }}</div>
          </div>
          <div class="shrink-0 text-right tabular-nums">
            <div class="text-[12px] font-medium text-zinc-800">
              {{ quoteOf(g.id)?.unit != null ? fmtUnit(quoteOf(g.id).unit) : (pricing ? '…' : '--') }}
            </div>
            <div class="text-[11px] text-zinc-400">
              {{
                quoteOf(g.id)?.unit != null
                  ? fmtMoney(quoteOf(g.id).unit * g.holdNum)
                  : ''
              }}
            </div>
          </div>
        </div>
      </section>

      <div v-else-if="!loading" class="py-12 text-center text-sm text-zinc-400">暂无持仓</div>
    </template>
  </div>
</template>

# iBox Market Perf Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Speed up crawl market list images and scrolling via OSS thumbs + windowed DOM.

**Architecture:** Shared `iboxThumb.js`; Market uses page-scroll virtual window; throttle partial market applies.

**Tech Stack:** Vue 3, existing Vite frontend, Aliyun OSS image process params.

---

### Task 1: thumbUrl util + tests

**Files:**
- Create: `frontend/src/lib/iboxThumb.js`
- Create: `frontend/tests/iboxThumb.test.mjs`
- Modify: `frontend/src/views/ibox/HoldingsMvPane.vue` (use shared)

- [x] Implement `thumbUrl(url, { w, h })`
- [x] Unit tests for empty / already-processed / ibox host / other host
- [x] Point HoldingsMvPane at shared helper

### Task 2: Market virtual list + thumbs + throttle

**Files:**
- Modify: `frontend/src/views/ibox/Market.vue`

- [x] Import `thumbUrl`; img `:src="thumbUrl(item.coverPicUrl)"` with fixed box
- [x] Windowed render over `items` (spacer + visible slice; page/window scroll)
- [x] Flat mode: `items = all` (no load-more slice); throttle `onPartial` apply
- [x] `content-visibility: auto` on rows as fallback

### Task 3: Verify + deploy

- [x] `node frontend/tests/iboxThumb.test.mjs`
- [x] `npm run build` in frontend
- [x] Deploy FE to S1; hard-refresh 验收

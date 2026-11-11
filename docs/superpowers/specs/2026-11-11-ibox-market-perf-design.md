# 爬仓市场页性能优化（缩略图 + 虚拟列表）

**Date:** 2026-11-11  
**Status:** approved  
**Approach:** B（含 A）

## Problem

爬仓「市场」列表出图慢、滚动卡：封面用原图填 ~44px 缩略位；后台翻页/拆合集后 DOM 行数膨胀。

## Design

1. **Shared `thumbUrl`**：`x-oss-process=image/resize,m_fill,w_88,h_88,limit_0`（ibox/aliyun CDN）；持仓市值改复用。
2. **Market 列表虚拟化**：只挂载可视区 ± overscan；flat 模式一次灌入 `flatAll`，取消「加载更多」分页 DOM。
3. **后台合并节流**：`onPartial` 合并更新节流，减少重排闪图。
4. **Out of scope**：自建图床反代、改 sail 串行策略。

## Acceptance

首屏封面更快；数百行滚动跟手；排序/分段/关注/推送/进详情不变。

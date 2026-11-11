# iOS 查挂单网站 UI + 成交记录接入

**Date:** 2026-11-11  
**Status:** Approved (user OK, scope B)  
**Platform:** ibox-fire-ios

## Goal

1. Tech `QueryPane` + Official H5「查挂单」浮层结果区对齐网站 `Detail.vue` ladder UI.  
2. Official H5「成交记录」芯片对齐 APK `TradeRecordsPane`（站点 `/snipe/trade-records/{gid}`）.

## Non-goals

- 成交趋势 K 线  
- ibPro 查挂单 UI  
- 改网站 / APK

## Shared UI

- `LadderResultView`: 标题、进度条、四格统计、价位占比表、可售/锁定/均价  
- Used by tech QueryPane and H5 ModePane when `query_consignment` / query overlay

## Trade records

- `ApiRepository.fetchTradeRecords(gid,name,page,limit)` → site API  
- VM: `tradeGid/tradeCname/tradeRecords/...` + `loadTradeRecords(reset:)`  
- `TradeRecordsPane` in H5 overlay for tool `records`; openTool sets tradeGid from page URL

## Progress

- QueryEngine `onProgress` + publish `queryPages` / `queryActive` / `queryLocked` for ladder stats

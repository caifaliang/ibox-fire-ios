# Full-Site Local Direct (除抢合/抢购)

**Date:** 2026-09-09  
**Status:** approved (scope C + approach 1「走直连」)  
**Supersedes for scope:** `2026-09-09-browser-local-fire-design.md` P1（捡漏/上下架已落地，本文扩展为全站）

## Goal

除 **抢合开火**、**抢购开火**（Celery `cn_fire` + 易代理）外，全站凡能打上游交易/资产 API 的能力，改为 **浏览器本机 IP 直连**。站点只保留账号体系、VIP/配额、无法浏览器化的薄代理，以及抢合/抢购调度。

## Decisions (locked)

| 项 | 选择 |
|----|------|
| 范围 | **C**：iBox 全站 + Newbee + Event 等，凡能直连均改 |
| 网络策略 | **Approach 1**：本机直连为主；极验 ONNX、hfpay 无 CORS 时走站点薄代理 |
| 长循环 | 在当前标签页跑；**关页即停**（不做后台 Celery 长跑，抢合/抢购除外） |
| 抢合/抢购 | **不变**：`POST /snipe/synth-snipe`、`POST /snipe/presale-start` → `cn_fire` + 易代理 + 配额扣次 |

## Facts

- `sail-api.ibox.art` CORS 已允许 `Origin: https://ai.iboxai.top`（GET/POST）；`channel` 不在 Allow-Headers，浏览器客户端不得带该头。
- 加解密与 `backend/crawler/ibox3.py` 一致；已有 `frontend/src/lib/ibox3.js`、`iboxClient.js`。
- 已本机直连：捡漏、批量上下架、短信登录（除极验）、Token 探活。
- Newbee 上游：`https://api.newbee.net.cn`（`x-token` MD5）；支付 `pay.newbee.net.cn` / 汇付链路。服务端现用 `curl_cffi` 绕 EdgeOne；浏览器真实 Chrome 可能可直连，**若 CORS 失败则对该域名单独站点透传**（仍优先探测直连）。
- 汇付 `hfpay.cloudpnr.com`：历史 CORS 不通 → 自动支付保留 `POST /snipe/pay-execute`（及 Newbee 等价支付代理若需要）。
- 极验：服务端 ONNX + JS `w` → 保留 `POST /snipe/gee-solve`；SMS/login 业务仍浏览器直连 sail-api。

## Architecture

```
浏览器
  ├─ IboxClient / local* loops ──► sail-api.ibox.art（本机 IP）
  ├─ NewbeeClient / local* loops ──► api.newbee.net.cn（本机 IP；CORS 不通则站点透传）
  └─ axios /api/* ──► 本站
        ├─ auth / VIP / quota / WxPusher / admin / bulletin / 站内搜索索引
        ├─ gee-solve、pay-execute（薄代理）
        └─ synth-snipe、presale-start（唯一长跑开火：Celery + 易代理）

Celery cn_fire（仅）
  └─ synth_snipe_task / presale_snipe_task（+ 既有 announce 若仍云端产品策略）
```

**公告锁定**：Web 端 start 已导向 APK/EXE；本改造不强制改 announce Celery，除非产品明确要求 Web 本机锁——默认 **out of scope**。

## Stay on site (explicit)

| 能力 | 原因 |
|------|------|
| 登录注册改密、VIP 兑换、用户代理/易代理 URL 配置 | 站点账号与密钥 |
| `local-fire-gate` / synth-quota / presale-quota / 各类 consume | Redis/DB 配额与 VIP |
| `gee-solve` | ONNX + ExecJS，不宜整包进前端 |
| `pay-execute`（及必要的 Newbee 支付代理） | hfpay CORS / 加密脚本 |
| `push-link` / WxPusher 绑定 | 服务端密钥 |
| `admin/*`、运维探针 | 运维 |
| 站内 `collections/search`、trade-trend、bulletin | 本地索引/DB，非上游原始交易 |
| **抢合开火、抢购开火** | 易代理 IP 池 + 定时并发，产品要求云端 |

## Migrate to browser-local

### Already done
- `ibox3.js` / `iboxClient.js`
- `localBuy.js`（捡漏；支付走 `pay-execute`）
- `localBatch.js`（上下架）
- `iboxLogin.js`（gee-solve + 浏览器 SMS/login/verify）

### Batch 1 — Client foundation
- 扩展 `iboxClient`：覆盖 holdings、consign、market、orders、purchase、synth 浏览、presale list 等已有 `_proxy_*` 路径。
- 新增 `newbeeClient.js`（`x-token` + fetch）；启动时 CORS 探测，失败标记 `useSiteProxy`。
- 统一本地任务句柄：`createLocalJob({ id, onLog, stop })`；UI「本机直连」/「关页即停」；停止 = abort 本地循环，不再调 Celery stop（除非停抢合/抢购）。

### Batch 2 — Snipe 剩余科技（开火除外）
| 功能 | 目标 |
|------|------|
| 卖求购 | 本地循环；VIP gate 仍站点 |
| 顶求购 | 下单直连；支付走 `pay-execute` |
| 点对点 / 仓库扫 | 查询+下单本地；支付同上 |
| 互刷 / 冲榜 / 量化出货 | 本地循环；关页停 |
| 精准射 | holdings + purchase-orders + 出售本地 |
| 合成浏览 / 材料 / channel | 读路径本地；**开火仍 `synth-snipe`** |
| 预售列表 / 校验展示 | 读路径本地；**开火仍 `presale-start`** |

### Batch 3 — iBox 其它页 + Event
- `ibox/Assets.vue`：动作改 `localBuy` / `localBatch` 等，禁用 `start-loop` / `batch-list` / `batch-unlist` Celery。
- `ibox/Market.vue`、`Orders.vue`、持仓/关注：读写直连。
- `Event.vue`：verify/买卖循环本机；支付薄代理。

### Batch 4 — Newbee
- 登录（验证码若需 OCR：优先站点薄接口，业务 token 后直连）。
- 资产 / 市场 / 订单 / Tech 循环：本机；支付 CORS 不通则站点代付。
- Newbee 侧若存在「抢合/抢购类」云端开火：保持与 iBox 一致——**仅易代理定时开火留云端**；其余直连。

### Batch 5 — UX / cleanup
- 文案区分「本机直连」vs「云端易代理（抢合/抢购）」。
- 任务列表：本地 job 与云端 job 分栏或标记。
- 不删除 Celery 旧路由立即；前端停用后可标 deprecated，避免 APK/旧客户端骤断（APK 路径另议，默认不动 APK）。

## Error handling

- 直连 401：提示重新登录；不自动改走站点交易代理（避免静默换 IP）。
- 支付失败：保留「已下单、待支付」+ 可选站点 `pay-execute` 重试。
- Newbee CORS 失败：该会话降级站点透传，日志标明 `via=site-proxy`，不伪装为本机 IP。
- 关页 / 刷新：本地 AbortController 中止；不向用户承诺后台继续（抢合/抢购除外）。

## Testing

- 浏览器 Network：科技读写应出现 `sail-api.ibox.art` / `api.newbee.net.cn`；抢合/抢购 start 仅打本站 `/snipe/synth-snipe`、`/snipe/presale-start`。
- 捡漏自动支付：可见 `/snipe/pay-execute`；发短信可见 `/snipe/gee-solve` + 直连 SMS。
- 关页后本地循环停止；云端抢购任务仍可在「我的任务」看到。
- VIP 未开通：gate 拒绝，不发起本地开火循环。

## Non-goals

- 不把极验模型与 ExecJS 整包进前端（Approach 2）。
- 不把抢合/抢购改为浏览器开火。
- 不强制改造公告锁 Web start / APK。
- 不改易代理提取与 `cn_fire` worker 拓扑。

## Success criteria

1. 除抢合/抢购开火与薄代理例外外，用户可见交易流量来自本机 IP。  
2. 关页即停适用于所有已迁移本地循环。  
3. 抢合/抢购行为与配额与现网一致。  
4. UI 明确区分本机直连与云端易代理。

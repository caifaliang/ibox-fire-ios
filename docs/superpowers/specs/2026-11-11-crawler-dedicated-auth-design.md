# 爬虫专用票（不借用户）

**日期：** 2026-11-11  
**状态：** 已批准（用户「按这个改」）

## 目标

1. 新开寄售/索引爬虫只使用**后台写入的专用账号**凭证（短信 access + refresh + 同 deviceId，180 天续期）
2. **默认不再**从日活库借用其他用户 access
3. Admin 文案明确：勿把日常科技页个人号填进爬虫票

## 行为

- `ensure_bearer`：仅用 `/opt/.ibox_crawler_config.json` 内票；续期失败返回空，不借 presence
- 紧急兜底：环境变量 `IBOX_CRAWLER_BORROW_PRESENCE=1` 才允许借票（默认关）
- 日活存票/刷仓逻辑不变（仍只用 access，不吃用户 refresh）

## 验收

- 无专用 refresh 时爬虫不再静默用用户票
- Admin「爬虫票」提示改为专用号说明

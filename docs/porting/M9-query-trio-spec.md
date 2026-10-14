# M9–M11 查询三件套 · 行为规格

## 书签（M9 · ready）

- 用户编辑多行腾讯 CGI URL（phonepk/petpk），本地 UserDefaults 持久化。
- 「快速打开」或「打开第一行」→ `openExternalGameURL` → 游戏壳加载。
- 非 `.qq.com` / `.tencent.com` 拒绝。

## 背包查询（M10 · partial）

- 登录后点「刷新」：拉 `cmd=store` HTML，正则刮取道具名 + goodsid + 仓库标记。
- 关键词过滤 + 仓库 Tab；点道具 → 打开对应 phonepk 链接。
- 未做：出售 / 使用 / 批量操作（Android 有则后续切片）。

## 武林查区（M11 · partial）

- 设置页：自动更新开关、等级区间、战力、报名档位、赛区码 → UserDefaults。
- 「打开武林报名页」→ 壳内 phonepk。
- 未做：按等级扫区后台循环（需 Worker + 限流，单独切片）。

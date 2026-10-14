# M8 账号切换

## Goal
本机保存多个登录 Cookie；可保存当前号、切换、删除；切换后注入 WK 并进游戏壳。

## Behavior (from Android AccountStore / AccountSwitchScreen)
- list / save (by id or same qq replace) / delete
- saveCurrent: 需已有 cookie；name 可选，默认 `QQ{qq}`
- apply: 写 Session → 清/注 Web Cookie → 回壳
- 粘贴 Cookie 登录并入库（需 skey 或游戏会话）
- 令牌仅本机；提示勿外传

## iOS map
- AccountStore → Application Support JSON（与 Session 文件同级）
- UI → sheet from Feature Hub
- apply → SessionStore.save + cookieInjectToken + phonepk

## Non-goals
道聚城 QQ 手填（可后补）；EncryptedSharedPreferences；云同步。

## Acceptance
1. 功能中心 → 账号切换 进页  
2. 登录后「保存当前」出现在列表  
3. 切换后标题/QQ 变，能进游戏  
4. 删除生效  

# M7 Feature Hub（功能中心）

## Goal
iOS 出现与 Android `FeatureCatalog` 同结构的功能中心；已接能力可进入；未接项进占位页不崩。

## States
- hub closed / hub open (sheet)
- selected feature → wired action | placeholder

## Wired now
`one_login`, `scan_login`, `logout`, cookie（壳菜单额外）, `qunxia_luxiang`→官方动画, 进游戏首页/刷新（壳）

## Non-goals
任何后台 Worker / CGI；VIP；账号切换实现；逐像素抄 Android。

## Acceptance
1. 三区：后台任务 / 设置相关 / 更多  
2. 一键、扫码、退出、官方动画可从中心进入  
3. 点「喝酒」等未接项 → 占位「即将接入」+ id  
4. 不回归一键登录主路径  

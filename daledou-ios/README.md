# daledou-ios（MVP）

大乐斗 iOS 对照客户端。登录仅两种：**一键登陆**、**扫码登陆**。

## 一键登陆（壳内，不跳浏览器）

对齐 QQ 互联「WKWebView + 拦截回调」思路（**不再** `wtloginmqq` 唤系统 QQ）：

1. 壳内加载 `graph.qq.com/oauth2.0/authorize`（`client_id=102067279`，`display=mobile`）
2. `redirect_uri` 使用已登记地址 `https://dld.qzapp.z.qq.com/index.php`（写游戏 Cookie）
3. 导航代理中：
   - **拦截** `tencent102067279://` / `daledouapp://` 取 `code`，再壳内打开 redirect 写会话
   - **禁止** `wtlogin*` / `mqq*` 交给系统（避免跳 QQ → Safari）
4. 检测到 `skey` Cookie → 进入 `phonepk`

## 扫码登陆

壳内 `graph.qq.com/oauth2.0/show` + 桌面 UA（与安卓一致）。

## 出包

GitHub Actions：`daledou-ios-ipa.yml` → artifact `daledou-unsigned-ipa`

```bash
cd daledou-ios && brew install xcodegen && xcodegen generate
```

Bundle：`com.daledou.app` · Scheme：`daledouapp` / `tencent102067279`

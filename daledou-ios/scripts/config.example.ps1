# 复制为 config.local.ps1 后填写（config.local.ps1 已 gitignore，勿提交）
#
# 1) GitHub：用于下载 CI 打好的 unsigned IPA
#    https://github.com/settings/tokens → Fine-grained 或 classic，勾选 repo / actions:read
$GitHubToken = "ghp_xxxxxxxx"
$GitHubRepo  = "caifaliang/ibox-fire-ios"
$ArtifactName = "daledou-unsigned-ipa"

# 2) Apple ID：用于 iPASide 免费重签（建议用小号，勿用主 ID）
#    也可用环境变量 IPASIDE_APPLE_PASSWORD，不必写在文件里
$AppleIdEmail    = "your-apple-id@example.com"
$AppleIdPassword = "your-app-specific-or-account-password"

# 3) 可选
$BundleIdOverride = "com.daledou.app"   # 与工程一致；若一周 App ID 额度用尽可改后缀调试
$PreferUsb        = $true
$IpaCacheDir      = Join-Path $PSScriptRoot "..\..\_ipa_cache"

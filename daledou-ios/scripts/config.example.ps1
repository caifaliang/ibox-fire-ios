# Copy to config.local.ps1 and fill in (config.local.ps1 is gitignored)
#
# 1) GitHub PAT with actions:read
#    https://github.com/settings/tokens
$GitHubToken = "ghp_xxxxxxxx"
$GitHubRepo  = "caifaliang/ibox-fire-ios"
$ArtifactName = "daledou-unsigned-ipa"

# 2) Apple ID for free resign (prefer a spare account)
#    Or set env IPASIDE_APPLE_PASSWORD instead of password here
$AppleIdEmail    = "your-apple-id@example.com"
$AppleIdPassword = "your-password"

# 3) Optional
$BundleIdOverride = "com.daledou.app"
$PreferUsb        = $true
$IpaCacheDir      = Join-Path $PSScriptRoot "..\..\_ipa_cache"
#Requires -Version 5.1
<#
.SYNOPSIS
  安装「免费 Apple ID 重签 + USB 装机」依赖（方案 A）。

  Sideloadly 无稳定 CLI，这里用开源 iPASide 引擎（同等免费 ID 重签，可脚本化）。
#>
param(
    [switch]$SkipAppleDevicesHint
)

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot
. (Join-Path $ScriptDir "Find-IpasideEngine.ps1")

Write-Host "=== DaLedou 本机装机工具安装 ===" -ForegroundColor Cyan

# 1) Apple Devices / iTunes（usbmux）
if (-not $SkipAppleDevicesHint) {
    Write-Host @"

[必需] 让 Windows 能认出 iPhone：
  - 推荐：Microsoft Store 安装「Apple Devices」
    https://apps.microsoft.com/detail/9np83lwlpz9k
  - 或：官网桌面版 iTunes（不要用微软商店版 iTunes）
  - 手机解锁 → 点「信任此电脑」

"@ -ForegroundColor Yellow
}

# 2) iPASide
$py = Find-IpasideEngine
if ($py) {
    Write-Host "[OK] 已找到 iPASide 引擎: $py" -ForegroundColor Green
} else {
    Write-Host "[..] 下载 iPASide 安装包…" -ForegroundColor Yellow
    $api = "https://api.github.com/repos/pwnapplehat/iPASide/releases/latest"
    $headers = @{ "User-Agent" = "daledou-ios-setup"; "Accept" = "application/vnd.github+json" }
    $rel = Invoke-RestMethod -Uri $api -Headers $headers
    $asset = $rel.assets | Where-Object { $_.name -like "iPASide-Setup-*-x64.exe" } | Select-Object -First 1
    if (-not $asset) { throw "找不到 iPASide-Setup x64 资源" }

    $cache = Join-Path $env:TEMP "iPASide-Setup.exe"
    Write-Host "    $($asset.browser_download_url)"
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $cache -UseBasicParsing
    Write-Host "[..] 启动安装程序（若弹出 SmartScreen：更多信息 → 仍要运行）…" -ForegroundColor Yellow
    Start-Process -FilePath $cache -Wait
    Start-Sleep -Seconds 2
    $py = Find-IpasideEngine
    if (-not $py) {
        Write-Host @"

[!] 安装后仍找不到引擎。请确认装到了默认路径，或手动打开 iPASide 一次后再跑本脚本。
    预期: C:\Program Files\iPASide\engine\python\python.exe

"@ -ForegroundColor Red
        exit 1
    }
    Write-Host "[OK] 引擎就绪: $py" -ForegroundColor Green
}

# 3) doctor
Write-Host "`n=== iPASide doctor ===" -ForegroundColor Cyan
$code = Invoke-IpasideEngine -Args @("doctor")
if ($code -ne 0) {
    Write-Host "[!] doctor 非零退出 ($code)。请检查 Apple Devices / 数据线 / 信任提示。" -ForegroundColor Yellow
}

# 4) 配置文件
$example = Join-Path $ScriptDir "config.example.ps1"
$local = Join-Path $ScriptDir "config.local.ps1"
if (-not (Test-Path $local)) {
    Copy-Item $example $local
    Write-Host "`n[!] 已生成 config.local.ps1 —— 请编辑填入 GitHub Token 与 Apple ID。" -ForegroundColor Yellow
    notepad $local
} else {
    Write-Host "`n[OK] 已有 config.local.ps1" -ForegroundColor Green
}

Write-Host @"

下一步：
  1. 编辑 scripts\config.local.ps1（GitHubToken / AppleId）
  2. 手机 USB 连接并解锁信任
  3. 登录 Apple ID（只需一次，含 2FA）：
       .\Login-AppleId.ps1
       .\Login-AppleId.ps1 -Code 123456
  4. 一键下 CI 包并装机：
       .\Deploy-DaLedou.ps1
       .\Deploy-DaLedou.ps1 -WaitCi    # 等当前 commit 的 Actions 完成再装

"@ -ForegroundColor Cyan

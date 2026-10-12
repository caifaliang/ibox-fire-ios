#Requires -Version 5.1
<#
.SYNOPSIS
  用 config.local.ps1 里的 Apple ID 登录 iPASide（免费账号首次会要 2FA）。
#>
param(
    [string]$Code = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot
. (Join-Path $ScriptDir "Find-IpasideEngine.ps1")

$local = Join-Path $ScriptDir "config.local.ps1"
if (-not (Test-Path $local)) {
    throw "缺少 config.local.ps1。请先运行 Setup-SideloadTools.ps1"
}
. $local

if (-not $AppleIdEmail) { throw "config.local.ps1 未设置 `$AppleIdEmail" }

$pass = $AppleIdPassword
if (-not $pass) { $pass = $env:IPASIDE_APPLE_PASSWORD }
if (-not $pass) { throw "请在 config.local.ps1 设置 `$AppleIdPassword，或设环境变量 IPASIDE_APPLE_PASSWORD" }

$credsPath = Join-Path $env:TEMP "ipaside-creds-daledou.json"
@{ email = $AppleIdEmail; password = $pass } | ConvertTo-Json | Set-Content -Path $credsPath -Encoding UTF8

try {
    $args = @("login", "--creds-file", $credsPath)
    if ($Code) { $args += @("--code", $Code) }
    $code = Invoke-IpasideEngine -Args $args
    if ($code -ne 0) { exit $code }

    Write-Host "`n=== 登录状态 ===" -ForegroundColor Cyan
    Invoke-IpasideEngine -Args @("login", "--status") | Out-Null
} finally {
    Remove-Item -LiteralPath $credsPath -Force -ErrorAction SilentlyContinue
}

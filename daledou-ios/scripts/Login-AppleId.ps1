#Requires -Version 5.1
param(
    [string]$Code = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot
. (Join-Path $ScriptDir "Find-IpasideEngine.ps1")

$local = Join-Path $ScriptDir "config.local.ps1"
if (-not (Test-Path $local)) {
    throw "Missing config.local.ps1. Run Setup-SideloadTools.ps1 first."
}
. $local

if (-not $AppleIdEmail) { throw "config.local.ps1: set `$AppleIdEmail" }

$pass = $AppleIdPassword
if (-not $pass) { $pass = $env:IPASIDE_APPLE_PASSWORD }
if (-not $pass) { throw "Set `$AppleIdPassword in config.local.ps1 or env IPASIDE_APPLE_PASSWORD" }

$credsPath = Join-Path $env:TEMP "ipaside-creds-daledou.json"
# IMPORTANT: no UTF-8 BOM — Python json.loads(utf-8) rejects BOM
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$json = (@{ email = $AppleIdEmail; password = $pass } | ConvertTo-Json)
[System.IO.File]::WriteAllText($credsPath, $json, $utf8NoBom)

try {
    $engineArgs = @("login", "--creds-file", $credsPath)
    if ($Code) { $engineArgs += @("--code", $Code) }
    $code = Invoke-IpasideEngine -EngineArgs $engineArgs
    if ($code -ne 0) { exit $code }

    Write-Host ""
    Write-Host "=== login status ===" -ForegroundColor Cyan
    [void](Invoke-IpasideEngine -EngineArgs @("login", "--status"))
} finally {
    Remove-Item -LiteralPath $credsPath -Force -ErrorAction SilentlyContinue
}
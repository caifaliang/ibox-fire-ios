#Requires -Version 5.1
param(
    [switch]$SkipAppleDevicesHint
)

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot
. (Join-Path $ScriptDir "Find-IpasideEngine.ps1")

Write-Host "=== DaLedou local install tools ===" -ForegroundColor Cyan

if (-not $SkipAppleDevicesHint) {
    Write-Host ""
    Write-Host "[NEED] Windows must see the iPhone:" -ForegroundColor Yellow
    Write-Host "  - Install Apple Devices from Microsoft Store:"
    Write-Host "    https://apps.microsoft.com/detail/9np83lwlpz9k"
    Write-Host "  - Or desktop iTunes (NOT Microsoft Store iTunes)"
    Write-Host "  - Unlock phone and tap Trust"
    Write-Host ""
}

$py = Find-IpasideEngine
if ($py) {
    Write-Host "[OK] iPASide engine: $py" -ForegroundColor Green
} else {
    Write-Host "[..] Downloading iPASide setup..." -ForegroundColor Yellow
    $api = "https://api.github.com/repos/pwnapplehat/iPASide/releases/latest"
    $headers = @{ "User-Agent" = "daledou-ios-setup"; "Accept" = "application/vnd.github+json" }
    $rel = Invoke-RestMethod -Uri $api -Headers $headers
    $asset = $rel.assets | Where-Object { $_.name -like "iPASide-Setup-*-x64.exe" } | Select-Object -First 1
    if (-not $asset) { throw "iPASide-Setup x64 asset not found" }

    $cache = Join-Path $env:TEMP "iPASide-Setup.exe"
    Write-Host "    $($asset.browser_download_url)"
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $cache -UseBasicParsing
    Write-Host "[..] Starting installer (SmartScreen: More info -> Run anyway)..." -ForegroundColor Yellow
    Start-Process -FilePath $cache -Wait
    Start-Sleep -Seconds 2
    $py = Find-IpasideEngine
    if (-not $py) {
        Write-Host ""
        Write-Host "[!] Engine still not found after install." -ForegroundColor Red
        Write-Host "    Expected: C:\Program Files\iPASide\engine\python\python.exe"
        Write-Host "    Open iPASide once, then re-run this script."
        exit 1
    }
    Write-Host "[OK] Engine ready: $py" -ForegroundColor Green
}

Write-Host ""
Write-Host "=== iPASide doctor ===" -ForegroundColor Cyan
$code = Invoke-IpasideEngine -EngineArgs @("doctor")
if ($code -ne 0) {
    Write-Host "[!] doctor exit=$code - check Apple Devices / cable / Trust" -ForegroundColor Yellow
}

$example = Join-Path $ScriptDir "config.example.ps1"
$local = Join-Path $ScriptDir "config.local.ps1"
if (-not (Test-Path $local)) {
    Copy-Item $example $local
    Write-Host ""
    Write-Host "[!] Created config.local.ps1 - fill GitHubToken and Apple ID" -ForegroundColor Yellow
    notepad $local
} else {
    Write-Host ""
    Write-Host "[OK] config.local.ps1 already exists" -ForegroundColor Green
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Edit config.local.ps1 (GitHubToken / AppleId)"
Write-Host "  2. Plug iPhone USB, unlock, Trust"
Write-Host "  3. Login Apple ID (once, with 2FA):"
Write-Host "       .\Login-AppleId.ps1"
Write-Host "       .\Login-AppleId.ps1 -Code 123456"
Write-Host "  4. Deploy:"
Write-Host "       .\Deploy-DaLedou.ps1"
Write-Host "       .\Deploy-DaLedou.ps1 -WaitCi"
Write-Host ""
#Requires -Version 5.1
# Download CI unsigned IPA 鈫?iPASide resign 鈫?install to USB iPhone.
# Reuses daledou-ios/scripts sideload tooling + config.local.ps1.
param(
    [switch]$WaitCi,
    [string]$IpaPath = "",
    [switch]$SkipInstall,
    [switch]$InstallOnly,
    [int]$WaitTimeoutMin = 35
)

$ErrorActionPreference = "Stop"
$DaledouScripts = Join-Path $PSScriptRoot "..\..\daledou-ios\scripts"
if (-not (Test-Path (Join-Path $DaledouScripts "Find-IpasideEngine.ps1"))) {
    throw "Missing daledou-ios/scripts (sideload tools)."
}
. (Join-Path $DaledouScripts "Find-IpasideEngine.ps1")

$local = Join-Path $DaledouScripts "config.local.ps1"
if (-not (Test-Path $local)) {
    throw "Missing daledou-ios/scripts/config.local.ps1. Run Setup-SideloadTools.ps1 first."
}
. $local

# Force ibox-fire artifact / bundle (do not use daledou defaults)
$GitHubRepo = if ($GitHubRepo) { $GitHubRepo } else { "caifaliang/ibox-fire-ios" }
$ArtifactName = "ibox-fire-unsigned-ipa"
$BundleIdOverride = "com.ibox.fire"
$AppDisplayName = "iBox科技"
$PhoneBundleId = "com.ibox.fire"

if (-not $IpaCacheDir) {
    $IpaCacheDir = Join-Path $DaledouScripts "..\..\_ipa_cache"
}
New-Item -ItemType Directory -Force -Path $IpaCacheDir | Out-Null

function Stop-IpasideStaleProcesses {
    Get-Process python -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -like '*iPASide*' } |
        ForEach-Object {
            Write-Host ("Kill stale iPASide python pid={0}" -f $_.Id) -ForegroundColor DarkYellow
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
}

function Get-PhoneAppBuild {
    param([string]$BundleId = $PhoneBundleId)
    $py = Find-IpasideEngine
    $json = & $py -m ipaside_engine apps --json 2>$null | Out-String
    if ($json -match ('"' + [regex]::Escape($BundleId) + '".*?"build"\s*:\s*"([^"]+)"')) {
        return $Matches[1]
    }
    return $null
}

function Test-PhoneHasBuild {
    param([string]$WantBuild)
    if (-not $WantBuild) { return $false }
    $got = Get-PhoneAppBuild
    if ($got -and $got -eq $WantBuild) {
        Write-Host ("[OK] Phone already has build {0}" -f $got) -ForegroundColor Green
        return $true
    }
    return $false
}

function Get-GhHeaders {
    if (-not $GitHubToken -or $GitHubToken -like "ghp_xxx*") {
        throw "Set a valid `$GitHubToken in daledou-ios/scripts/config.local.ps1 (actions:read)"
    }
    return @{
        "Authorization" = "Bearer $GitHubToken"
        "Accept"        = "application/vnd.github+json"
        "User-Agent"    = "ibox-fire-ios-deploy"
        "X-GitHub-Api-Version" = "2022-11-28"
    }
}

function Wait-LatestWorkflow {
    param([string]$Sha)
    $headers = Get-GhHeaders
    $deadline = (Get-Date).AddMinutes($WaitTimeoutMin)
    $short = $Sha.Substring(0, [Math]::Min(7, $Sha.Length))
    Write-Host "Waiting CI (sha=$short)..." -ForegroundColor Cyan
    while ((Get-Date) -lt $deadline) {
        $url = "https://api.github.com/repos/$GitHubRepo/actions/runs?per_page=20"
        $runs = (Invoke-RestMethod -Uri $url -Headers $headers).workflow_runs
        $mine = $runs | Where-Object {
            $_.head_sha -eq $Sha -and ($_.name -match "iOS unsigned|ibox-fire|ipa" -or $_.path -match "ios-ipa")
        } | Select-Object -First 1
        if (-not $mine) {
            $mine = $runs | Where-Object { $_.head_sha -eq $Sha } | Select-Object -First 1
        }
        if ($mine) {
            Write-Host ("  run #{0} status={1} conclusion={2}" -f $mine.run_number, $mine.status, $mine.conclusion)
            if ($mine.status -eq "completed") {
                if ($mine.conclusion -eq "success") { return $mine }
                throw ("CI failed: {0} - {1}" -f $mine.conclusion, $mine.html_url)
            }
        } else {
            Write-Host "  no run for this commit yet..."
        }
        Start-Sleep -Seconds 20
    }
    throw ("Wait CI timeout ({0} min)" -f $WaitTimeoutMin)
}

function Find-LatestSuccessfulArtifact {
    param([object]$FromRun = $null)
    $headers = Get-GhHeaders
    if ($FromRun) {
        $url = "https://api.github.com/repos/$GitHubRepo/actions/runs/$($FromRun.id)/artifacts"
        $arts = (Invoke-RestMethod -Uri $url -Headers $headers).artifacts
        $hit = $arts | Where-Object { $_.name -eq $ArtifactName -and -not $_.expired } | Select-Object -First 1
        if (-not $hit) {
            throw ("No artifact '{0}' on run #{1}." -f $ArtifactName, $FromRun.run_number)
        }
        return $hit
    }
    $url = "https://api.github.com/repos/$GitHubRepo/actions/artifacts?per_page=30"
    $arts = (Invoke-RestMethod -Uri $url -Headers $headers).artifacts
    $hit = $arts | Where-Object {
        $_.name -eq $ArtifactName -and -not $_.expired
    } | Select-Object -First 1
    if (-not $hit) {
        throw ("No fresh artifact '{0}'. Push to trigger CI first." -f $ArtifactName)
    }
    return $hit
}

function Download-ArtifactIpa {
    param($Artifact)
    $headers = Get-GhHeaders
    $zipPath = Join-Path $IpaCacheDir ("artifact_{0}.zip" -f $Artifact.id)
    $extract = Join-Path $IpaCacheDir ("artifact_{0}" -f $Artifact.id)
    $mb = [math]::Round($Artifact.size_in_bytes / 1MB, 1)
    Write-Host ("Download artifact #{0} ({1} MB)..." -f $Artifact.id, $mb) -ForegroundColor Cyan
    $dl = "https://api.github.com/repos/$GitHubRepo/actions/artifacts/$($Artifact.id)/zip"
    Invoke-WebRequest -Uri $dl -Headers $headers -OutFile $zipPath -UseBasicParsing
    if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extract -Force
    $ipa = Get-ChildItem -Path $extract -Filter "*.ipa" -Recurse | Select-Object -First 1
    if (-not $ipa) { throw ("No .ipa inside zip: {0}" -f $extract) }
    $dest = Join-Path $IpaCacheDir ("ibox-fire-{0}.ipa" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
    Copy-Item $ipa.FullName $dest -Force
    Write-Host "[OK] IPA -> $dest" -ForegroundColor Green
    return $dest
}

Write-Host "=== Deploy IboxFire to iPhone ===" -ForegroundColor Cyan

$ciRun = $null
$art = $null
if ($WaitCi) {
    Push-Location (Join-Path $DaledouScripts "..\..")
    try {
        $sha = (git rev-parse HEAD).Trim()
    } finally { Pop-Location }
    $ciRun = Wait-LatestWorkflow -Sha $sha
    Write-Host ("CI matched HEAD {0} run#{1} {2}" -f $sha.Substring(0,7), $ciRun.run_number, $ciRun.html_url) -ForegroundColor Green
}

if (-not $IpaPath) {
    $art = Find-LatestSuccessfulArtifact -FromRun $ciRun
    Write-Host ("Artifact: {0} @ {1}" -f $art.name, $art.created_at)
    $IpaPath = Download-ArtifactIpa -Artifact $art
} else {
    if (-not (Test-Path -LiteralPath $IpaPath)) { throw "IPA not found: $IpaPath" }
}

Write-Host ""
Write-Host "=== VERIFY ===" -ForegroundColor Yellow
Write-Host ("  ipa path  : {0}" -f $IpaPath)
Write-Host ("  bundle    : {0}" -f $BundleIdOverride)
try {
    $insp = & (Find-IpasideEngine) -m ipaside_engine inspect $IpaPath --json 2>$null | Out-String
    if ($insp -match '"bundle_id"\s*:\s*"([^"]+)"') { Write-Host ("  inspect   : {0}" -f $Matches[1]) }
    if ($insp -match '"build"\s*:\s*"([^"]+)"') { Write-Host ("  build     : {0}" -f $Matches[1]) }
} catch {}
Write-Host "=============" -ForegroundColor Yellow

if ($SkipInstall) {
    Write-Host "SkipInstall: downloaded $IpaPath"
    exit 0
}

Stop-IpasideStaleProcesses

$targetBuild = $null
try {
    $insp2 = & (Find-IpasideEngine) -m ipaside_engine inspect $IpaPath --json 2>$null | Out-String
    if ($insp2 -match '"build"\s*:\s*"([^"]+)"') { $targetBuild = $Matches[1] }
} catch {}
if ($targetBuild -and (Test-PhoneHasBuild -WantBuild $targetBuild)) {
    Write-Host "Skip reinstall 鈥?open IboxFire on phone." -ForegroundColor Cyan
    exit 0
}

Write-Host ""
Write-Host "=== Connected devices ===" -ForegroundColor Cyan
[void](Invoke-IpasideEngine -EngineArgs @("devices"))
if ($LASTEXITCODE -ne 0) {
    throw "devices failed. Plug iPhone, unlock, Trust, install Apple Devices."
}

$st = Join-Path $env:TEMP "ipaside-status.json"
& (Find-IpasideEngine) -m ipaside_engine login --status --json 2>$null | Out-File $st -Encoding utf8
$raw = Get-Content $st -Raw -ErrorAction SilentlyContinue
if ($raw -notmatch '"authenticated"\s*:\s*true') {
    Write-Host "[!] Apple ID not logged in. Run: daledou-ios\scripts\Login-AppleId.ps1" -ForegroundColor Red
    exit 2
}

$conn = if ($PreferUsb -ne $false) { "usb" } else { "auto" }

if ($InstallOnly) {
    $signedDir = Join-Path $env:LOCALAPPDATA "iPASide\signed"
    $signed = Get-ChildItem $signedDir -Filter "*_Signed.ipa" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Where-Object { $_.Name -match "ibox|IboxFire|fire" } |
        Select-Object -First 1
    if (-not $signed) {
        $signed = Get-ChildItem $signedDir -Filter "*_Signed.ipa" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
    }
    if (-not $signed) { throw "InstallOnly: no *_Signed.ipa in $signedDir" }
    Write-Host ("InstallOnly: {0}" -f $signed.FullName) -ForegroundColor Cyan
    $sideArgs = @("install", $signed.FullName, "--connection", $conn)
} else {
    $sideArgs = @(
        "sideload", $IpaPath,
        "--connection", $conn,
        "--keep-signed",
        "--enable-file-sharing",
        "--name", $AppDisplayName,
        "--bundle-id", $BundleIdOverride
    )
}

Write-Host ""
Write-Host "=== Resign + install (1-3 min) ===" -ForegroundColor Cyan
Write-Host "If stuck at 80%: unlock phone, wait; home screen may already show IboxFire." -ForegroundColor DarkYellow
$rc = Invoke-IpasideEngine -EngineArgs $sideArgs
if ($rc -ne 0 -and $targetBuild -and (Test-PhoneHasBuild -WantBuild $targetBuild)) {
    Write-Host "[OK] Install reported failure but phone has target build 鈥?treating as success." -ForegroundColor Green
    $rc = 0
}
if ($rc -ne 0) {
    Write-Host ("Install failed (exit={0}). Uninstall old free-sideload apps if at 3-app limit; Trust developer; enable Developer Mode." -f $rc) -ForegroundColor Red
    exit $rc
}

Write-Host ""
Write-Host "[OK] IboxFire installed. First time: Settings -> General -> VPN & Device Management -> Trust" -ForegroundColor Green

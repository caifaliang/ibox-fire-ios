#Requires -Version 5.1
param(
    [switch]$WaitCi,
    [string]$IpaPath = "",
    [switch]$SkipInstall,
    [switch]$InstallOnly,
    [string]$ExpectedBuild = "",
    [int]$WaitTimeoutMin = 25
)

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot
. (Join-Path $ScriptDir "Find-IpasideEngine.ps1")

$local = Join-Path $ScriptDir "config.local.ps1"
if (-not (Test-Path $local)) {
    throw "Missing config.local.ps1. Run Setup-SideloadTools.ps1 first."
}
. $local

if (-not $GitHubRepo) { $GitHubRepo = "caifaliang/ibox-fire-ios" }
if (-not $ArtifactName) { $ArtifactName = "daledou-unsigned-ipa" }
if (-not $IpaCacheDir) {
    $IpaCacheDir = Join-Path $ScriptDir "..\..\_ipa_cache"
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
    param([string]$BundleId = "com.daledou.app")
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
        Write-Host ("[OK] Phone already has build {0} (PC may hang at 80% — install succeeded)" -f $got) -ForegroundColor Green
        return $true
    }
    return $false
}

function Get-GhHeaders {
    if (-not $GitHubToken -or $GitHubToken -like "ghp_xxx*") {
        throw "Set a valid `$GitHubToken in config.local.ps1 (actions:read)"
    }
    return @{
        "Authorization" = "Bearer $GitHubToken"
        "Accept"        = "application/vnd.github+json"
        "User-Agent"    = "daledou-ios-deploy"
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
        $url = "https://api.github.com/repos/$GitHubRepo/actions/runs?per_page=15"
        $runs = (Invoke-RestMethod -Uri $url -Headers $headers).workflow_runs
        $mine = $runs | Where-Object {
            $_.head_sha -eq $Sha -and $_.name -match "DaLedou|daledou|ipa"
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
        # Strict: artifact belonging to the waited CI run (guarantees "this commit")
        $url = "https://api.github.com/repos/$GitHubRepo/actions/runs/$($FromRun.id)/artifacts"
        $arts = (Invoke-RestMethod -Uri $url -Headers $headers).artifacts
        $hit = $arts | Where-Object { $_.name -eq $ArtifactName -and -not $_.expired } | Select-Object -First 1
        if (-not $hit) {
            throw ("No artifact '{0}' on run #{1}. Check CI upload step." -f $ArtifactName, $FromRun.run_number)
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
    $dest = Join-Path $IpaCacheDir ("daledou-{0}.ipa" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
    Copy-Item $ipa.FullName $dest -Force
    Write-Host "[OK] IPA -> $dest" -ForegroundColor Green
    return $dest
}

Write-Host "=== Deploy DaLedou to iPhone ===" -ForegroundColor Cyan

$ciRun = $null
if ($WaitCi) {
    Push-Location (Join-Path $ScriptDir "..\..")
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

# Show identity so you can confirm "latest"
$localSha = ""
Push-Location (Join-Path $ScriptDir "..\..")
try { $localSha = (git rev-parse HEAD).Trim() } catch {}
finally { Pop-Location }
Write-Host ""
Write-Host "=== VERIFY (is this the build you want?) ===" -ForegroundColor Yellow
Write-Host ("  local git HEAD : {0}" -f $localSha)
if ($art) {
    Write-Host ("  artifact id    : {0}" -f $art.id)
    Write-Host ("  artifact time  : {0}" -f $art.created_at)
    Write-Host ("  workflow run   : {0}" -f $art.workflow_run.id)
}
Write-Host ("  ipa path       : {0}" -f $IpaPath)
try {
    $insp = & (Find-IpasideEngine) -m ipaside_engine inspect $IpaPath --json 2>$null | Out-String
    if ($insp -match '"bundle_id"\s*:\s*"([^"]+)"') { Write-Host ("  bundle id      : {0}" -f $Matches[1]) }
    if ($insp -match '"version"\s*:\s*"([^"]+)"') { Write-Host ("  version        : {0}" -f $Matches[1]) }
    if ($insp -match '"build"\s*:\s*"([^"]+)"') { Write-Host ("  build          : {0}" -f $Matches[1]) }
    if ($insp -match '"name"\s*:\s*"([^"]+)"') { Write-Host ("  name           : {0}" -f $Matches[1]) }
} catch {}
Write-Host "  phone check    : open official replay -> log must contain build=138-fdXX matching this push"
Write-Host "================================================" -ForegroundColor Yellow

if ($SkipInstall) {
    Write-Host "SkipInstall: downloaded $IpaPath"
    exit 0
}

Stop-IpasideStaleProcesses

# Parse build from inspect output for post-install verify
$targetBuild = $ExpectedBuild
if (-not $targetBuild) {
    try {
        $insp2 = & (Find-IpasideEngine) -m ipaside_engine inspect $IpaPath --json 2>$null | Out-String
        if ($insp2 -match '"build"\s*:\s*"([^"]+)"') { $targetBuild = $Matches[1] }
    } catch {}
}
if ($targetBuild -and (Test-PhoneHasBuild -WantBuild $targetBuild)) {
    Write-Host "Skip reinstall — open DaLedou on phone and test." -ForegroundColor Cyan
    try { & (Join-Path $ScriptDir "Push-DebugLogUrl.ps1") } catch {}
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
    Write-Host "[!] Apple ID not logged in. Run: .\Login-AppleId.ps1" -ForegroundColor Red
    exit 2
}

$conn = if ($PreferUsb -ne $false) { "usb" } else { "auto" }

if ($InstallOnly) {
    $signedDir = Join-Path $env:LOCALAPPDATA "iPASide\signed"
    $signed = Get-ChildItem $signedDir -Filter "*_Signed.ipa" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $signed) { throw "InstallOnly: no *_Signed.ipa in $signedDir — run full sideload once first" }
    Write-Host ("InstallOnly: {0}" -f $signed.FullName) -ForegroundColor Cyan
    $sideArgs = @("install", $signed.FullName, "--connection", $conn)
} else {
    $sideArgs = @(
        "sideload", $IpaPath,
        "--connection", $conn,
        "--keep-signed",
        "--enable-file-sharing",
        "--name", "DaLedou"
    )
    if ($BundleIdOverride) {
        $sideArgs += @("--bundle-id", $BundleIdOverride)
    }
}

Write-Host ""
Write-Host "=== Resign + install (1-3 min) ===" -ForegroundColor Cyan
Write-Host "If stuck at 80% Finalizing: unlock phone, wait 2 min, then check home screen for DaLedou." -ForegroundColor DarkYellow
$rc = Invoke-IpasideEngine -EngineArgs $sideArgs
if ($rc -ne 0 -and $targetBuild -and (Test-PhoneHasBuild -WantBuild $targetBuild)) {
    Write-Host "[OK] Install reported failure but phone has target build — treating as success." -ForegroundColor Green
    $rc = 0
}
if ($rc -ne 0) {
    Write-Host ""
    Write-Host ("Install failed (exit={0}). Common fixes:" -f $rc) -ForegroundColor Red
    Write-Host "  - Free Apple ID: max 3 apps - uninstall old sideloads"
    Write-Host "  - Weekly App ID limit - change BundleIdOverride or use another Apple ID"
    Write-Host "  - Trust developer: Settings -> General -> VPN & Device Management"
    Write-Host "  - Enable Developer Mode (iOS 16+)"
    Write-Host "  - Stuck at 80%: Ctrl+C then run .\Deploy-DaLedou.ps1 -InstallOnly"
    exit $rc
}

Write-Host ""
Write-Host "[OK] Installed." -ForegroundColor Green
Write-Host "On phone (first time): Settings -> General -> VPN & Device Management -> Trust"

# Push PC log receiver URL into app Documents so replay logs stream here
Write-Host ""
Write-Host "=== Push debug_log_url (for live logs) ===" -ForegroundColor Cyan
try {
    & (Join-Path $ScriptDir "Push-DebugLogUrl.ps1")
} catch {
    Write-Host "[!] Push-DebugLogUrl failed: $_" -ForegroundColor Yellow
}
Write-Host "Start receiver (keep window open while testing): .\LogReceiver.ps1"
Write-Host "Live file: ..\..\_ipa_cache\ruffle_live.log"
Write-Host "Next time: git push ; then .\Deploy-DaLedou.ps1 -WaitCi"
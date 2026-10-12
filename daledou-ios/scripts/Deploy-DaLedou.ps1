#Requires -Version 5.1
<#
.SYNOPSIS
  下载最新 CI unsigned IPA → iPASide 免费 Apple ID 重签 → USB 装到已连接 iPhone。

.PARAMETER WaitCi
  轮询当前 origin/HEAD 对应的 Actions run，成功后再下载。

.PARAMETER IpaPath
  跳过下载，直接安装本地 IPA。

.PARAMETER SkipInstall
  只下载，不装机。
#>
param(
    [switch]$WaitCi,
    [string]$IpaPath = "",
    [switch]$SkipInstall,
    [int]$WaitTimeoutMin = 25
)

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot
. (Join-Path $ScriptDir "Find-IpasideEngine.ps1")

$local = Join-Path $ScriptDir "config.local.ps1"
if (-not (Test-Path $local)) {
    throw "缺少 config.local.ps1。请先: .\Setup-SideloadTools.ps1"
}
. $local

if (-not $GitHubRepo) { $GitHubRepo = "caifaliang/ibox-fire-ios" }
if (-not $ArtifactName) { $ArtifactName = "daledou-unsigned-ipa" }
if (-not $IpaCacheDir) {
    $IpaCacheDir = Join-Path $ScriptDir "..\..\_ipa_cache"
}
New-Item -ItemType Directory -Force -Path $IpaCacheDir | Out-Null

function Get-GhHeaders {
    if (-not $GitHubToken -or $GitHubToken -like "ghp_xxx*") {
        throw "请在 config.local.ps1 填写有效 `$GitHubToken（repo/actions 读权限）"
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
    Write-Host "等待 CI（sha=$($Sha.Substring(0,[Math]::Min(7,$Sha.Length)))）…" -ForegroundColor Cyan
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
                throw "CI 失败: $($mine.conclusion) — $($mine.html_url)"
            }
        } else {
            Write-Host "  尚未看到该 commit 的 run…"
        }
        Start-Sleep -Seconds 20
    }
    throw "等待 CI 超时（${WaitTimeoutMin} 分钟）"
}

function Find-LatestSuccessfulArtifact {
    $headers = Get-GhHeaders
    $url = "https://api.github.com/repos/$GitHubRepo/actions/artifacts?per_page=30"
    $arts = (Invoke-RestMethod -Uri $url -Headers $headers).artifacts
    $hit = $arts | Where-Object {
        $_.name -eq $ArtifactName -and -not $_.expired
    } | Select-Object -First 1
    if (-not $hit) {
        throw "没有未过期的 artifact「$ArtifactName」。先 push 触发 CI 或检查仓库名。"
    }
    return $hit
}

function Download-ArtifactIpa {
    param($Artifact)
    $headers = Get-GhHeaders
    $zipPath = Join-Path $IpaCacheDir ("artifact_{0}.zip" -f $Artifact.id)
    $extract = Join-Path $IpaCacheDir ("artifact_{0}" -f $Artifact.id)
    Write-Host "下载 artifact #$($Artifact.id) ($([math]::Round($Artifact.size_in_bytes/1MB,1)) MB)…" -ForegroundColor Cyan
    $dl = "https://api.github.com/repos/$GitHubRepo/actions/artifacts/$($Artifact.id)/zip"
    Invoke-WebRequest -Uri $dl -Headers $headers -OutFile $zipPath -UseBasicParsing
    if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extract -Force
    $ipa = Get-ChildItem -Path $extract -Filter "*.ipa" -Recurse | Select-Object -First 1
    if (-not $ipa) { throw "zip 内没有 .ipa：$extract" }
    $dest = Join-Path $IpaCacheDir ("daledou-{0}.ipa" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
    Copy-Item $ipa.FullName $dest -Force
    Write-Host "[OK] IPA → $dest" -ForegroundColor Green
    return $dest
}

# ---- main ----
Write-Host "=== Deploy DaLedou → iPhone ===" -ForegroundColor Cyan

if ($WaitCi) {
    Push-Location (Join-Path $ScriptDir "..\..")
    try {
        $sha = (git rev-parse HEAD).Trim()
    } finally { Pop-Location }
    Wait-LatestWorkflow -Sha $sha | Out-Null
}

if (-not $IpaPath) {
    $art = Find-LatestSuccessfulArtifact
    Write-Host ("最新 artifact: {0} @ {1}" -f $art.name, $art.created_at)
    $IpaPath = Download-ArtifactIpa -Artifact $art
} else {
    if (-not (Test-Path -LiteralPath $IpaPath)) { throw "IPA 不存在: $IpaPath" }
}

if ($SkipInstall) {
    Write-Host "SkipInstall：已下载 $IpaPath"
    exit 0
}

# 设备检查
Write-Host "`n=== 已连接设备 ===" -ForegroundColor Cyan
$devCode = Invoke-IpasideEngine -Args @("devices")
if ($devCode -ne 0) {
    throw "devices 失败。请插上 iPhone、解锁并点信任，确认已装 Apple Devices。"
}

# 登录状态
$st = Join-Path $env:TEMP "ipaside-status.json"
& (Find-IpasideEngine) -m ipaside_engine login --status --json 2>$null | Out-File $st -Encoding utf8
$raw = Get-Content $st -Raw -ErrorAction SilentlyContinue
if ($raw -notmatch '"authenticated"\s*:\s*true') {
    Write-Host "[!] Apple ID 未登录。先运行: .\Login-AppleId.ps1" -ForegroundColor Red
    exit 2
}

$conn = if ($PreferUsb -ne $false) { "usb" } else { "auto" }
$sideArgs = @(
    "sideload", $IpaPath,
    "--connection", $conn,
    "--enable-file-sharing"
)
if ($BundleIdOverride) {
    $sideArgs += @("--bundle-id", $BundleIdOverride)
}

Write-Host "`n=== 重签并安装（约 1–3 分钟）===" -ForegroundColor Cyan
$rc = Invoke-IpasideEngine -Args $sideArgs
if ($rc -ne 0) {
    Write-Host @"

安装失败 (exit=$rc)。常见原因：
  - 免费账号同时只能装 3 个 App → 删掉旧 sideload 再试
  - 本周 App ID 额度用尽 → 改 `$BundleIdOverride` 或换小号
  - 未信任开发者 → 设置 → 通用 → VPN 与设备管理
  - Developer Mode 未开（iOS 16+）

"@ -ForegroundColor Red
    exit $rc
}

Write-Host @"

[OK] 已装上。手机上：
  设置 → 通用 → VPN 与设备管理 → 信任该开发者
  （仅首次）然后打开 DaLedou。

下次调试只需：
  git push
  .\Deploy-DaLedou.ps1 -WaitCi

"@ -ForegroundColor Green

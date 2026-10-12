# 定位已安装的 iPASide 引擎：python.exe -m ipaside_engine
function Find-IpasideEngine {
    $candidates = @(
        "${env:ProgramFiles}\iPASide\engine\python\python.exe",
        "${env:ProgramFiles(x86)}\iPASide\engine\python\python.exe",
        "$env:LOCALAPPDATA\Programs\iPASide\engine\python\python.exe",
        "$env:LOCALAPPDATA\iPASide\engine\python\python.exe"
    )
    foreach ($p in $candidates) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    # 扫一遍常见安装根
    foreach ($root in @(${env:ProgramFiles}, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
        if (-not $root) { continue }
        $hit = Get-ChildItem -Path $root -Filter "python.exe" -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\iPASide\\engine\\python\\python\.exe$' } |
            Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

function Invoke-IpasideEngine {
    param(
        [Parameter(Mandatory)][string[]]$Args,
        [switch]$Json
    )
    $py = Find-IpasideEngine
    if (-not $py) {
        throw "未找到 iPASide 引擎。请先运行 Setup-SideloadTools.ps1 安装。"
    }
    $all = @("-m", "ipaside_engine") + $Args
    if ($Json -and ($Args -notcontains "--json")) {
        $all += "--json"
    }
    Write-Host ">> $py $($all -join ' ')" -ForegroundColor DarkGray
    & $py @all
    return $LASTEXITCODE
}

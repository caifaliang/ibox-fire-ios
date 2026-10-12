# Locate iPASide engine: python.exe -m ipaside_engine
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
        [Parameter(Mandatory)][string[]]$EngineArgs,
        [switch]$Json
    )
    $py = Find-IpasideEngine
    if (-not $py) {
        throw "iPASide engine not found. Run Setup-SideloadTools.ps1 first."
    }
    $all = @("-m", "ipaside_engine") + $EngineArgs
    if ($Json -and ($EngineArgs -notcontains "--json")) {
        $all += "--json"
    }
    Write-Host (">> {0} {1}" -f $py, ($all -join " ")) -ForegroundColor DarkGray
    & $py @all
    return $LASTEXITCODE
}
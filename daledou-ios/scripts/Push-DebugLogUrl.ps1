#Requires -Version 5.1
# Write debug_log_url into the installed app container (Application Support / Documents)
param(
    [string]$Url = "",
    [int]$Port = 8765
)

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot
. (Join-Path $ScriptDir "Find-IpasideEngine.ps1")

function Get-PreferredLanIp {
    $cands = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -notlike "127.*" -and
            $_.IPAddress -notlike "169.254.*" -and
            $_.IPAddress -notlike "192.168.232.*" -and
            $_.IPAddress -notlike "192.168.29.*" -and
            $_.IPAddress -notlike "172.21.*" -and
            $_.IPAddress -notlike "198.18.*"
        } | Select-Object -ExpandProperty IPAddress -Unique)
    if (-not $cands) {
        $cands = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } |
            Select-Object -ExpandProperty IPAddress -Unique)
    }
    # Prefer 10.x
    $ten = $cands | Where-Object { $_ -like "10.*" } | Select-Object -First 1
    if ($ten) { return $ten }
    return ($cands | Select-Object -First 1)
}

if (-not $Url) {
    $ip = Get-PreferredLanIp
    if (-not $ip) { throw "No LAN IP found" }
    $Url = "http://${ip}:${Port}/log"
}

Write-Host "Log URL for phone: $Url" -ForegroundColor Cyan

$py = Find-IpasideEngine
if (-not $py) { throw "iPASide engine not found" }

$tmpPy = Join-Path $env:TEMP "daledou_push_log_url.py"
$pyCode = @"
import asyncio, sys
from pathlib import Path

URL = sys.argv[1]
BUNDLE = "com.daledou.app"

async def main():
    from pymobiledevice3.lockdown import create_using_usbmux
    from pymobiledevice3.services.house_arrest import HouseArrestService
    ld = await create_using_usbmux()
    ha = HouseArrestService(ld, BUNDLE)
    # Documents is always available with file sharing / house_arrest
    for folder in ("/Documents", "/Library/Application Support/DaLedou"):
        try:
            parts = folder.strip("/").split("/")
            cur = ""
            for p in parts:
                cur = f"{cur}/{p}"
                try:
                    ha.makedirs(cur)
                except Exception:
                    pass
            path = f"{folder}/debug_log_url.txt"
            ha.set_file_contents(path, URL.encode("utf-8"))
            print(f"wrote {path}")
        except Exception as e:
            print(f"skip {folder}: {e}")

asyncio.run(main())
"@
[System.IO.File]::WriteAllText($tmpPy, $pyCode, (New-Object System.Text.UTF8Encoding $false))
& $py $tmpPy $Url
Write-Host "exit=$LASTEXITCODE"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Push failed - phone unlocked? app installed? USB/WiFi paired?" -ForegroundColor Yellow
    Write-Host "You can still set URL manually later; put one line into Documents/debug_log_url.txt"
}
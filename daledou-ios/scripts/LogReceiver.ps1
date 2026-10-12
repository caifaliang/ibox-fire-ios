#Requires -Version 5.1
param(
    [int]$Port = 8765,
    [string]$OutFile = ""
)

$ErrorActionPreference = "Stop"
if (-not $OutFile) {
    $OutFile = Join-Path $PSScriptRoot "..\..\_ipa_cache\ruffle_live.log"
}
$dir = Split-Path $OutFile -Parent
New-Item -ItemType Directory -Force -Path $dir | Out-Null
if (-not (Test-Path $OutFile)) { Set-Content -Path $OutFile -Value "" -Encoding UTF8 }

$prefix = "http://+:$Port/"
Write-Host "DaLedou log receiver on port $Port" -ForegroundColor Cyan
Write-Host "Writing -> $OutFile"
Write-Host "POST /log   body=text lines"
Write-Host "GET  /tail  last lines"
Write-Host "GET  /health"
Write-Host ""

# Prefer showing LAN IPs that phones can reach
$ips = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } |
    Select-Object -ExpandProperty IPAddress -Unique)
foreach ($ip in $ips) {
    Write-Host ("  phone URL: http://{0}:{1}/log" -f $ip, $Port) -ForegroundColor Green
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)
try {
    $listener.Start()
} catch {
    Write-Host "Failed to bind $prefix - try: netsh http add urlacl url=$prefix user=Everyone" -ForegroundColor Red
    Write-Host $_
    # fallback localhost only
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://127.0.0.1:$Port/")
    $listener.Start()
    Write-Host "Bound 127.0.0.1 only (firewall/urlacl issue)" -ForegroundColor Yellow
}

Write-Host "Listening... Ctrl+C to stop" -ForegroundColor Cyan

function Write-Response($ctx, [int]$code, [string]$body, [string]$ctype = "text/plain; charset=utf-8") {
    $buf = [Text.Encoding]::UTF8.GetBytes($body)
    $ctx.Response.StatusCode = $code
    $ctx.Response.ContentType = $ctype
    $ctx.Response.ContentLength64 = $buf.Length
    $ctx.Response.Headers.Add("Access-Control-Allow-Origin", "*")
    $ctx.Response.OutputStream.Write($buf, 0, $buf.Length)
    $ctx.Response.Close()
}

while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $req = $ctx.Request
    $path = $req.Url.AbsolutePath.TrimEnd("/").ToLowerInvariant()
    try {
        if ($req.HttpMethod -eq "OPTIONS") {
            $ctx.Response.Headers.Add("Access-Control-Allow-Origin", "*")
            $ctx.Response.Headers.Add("Access-Control-Allow-Methods", "GET,POST,OPTIONS")
            $ctx.Response.Headers.Add("Access-Control-Allow-Headers", "Content-Type")
            Write-Response $ctx 204 ""
            continue
        }
        if ($path -eq "/health") {
            Write-Response $ctx 200 "ok"
            continue
        }
        if ($path -eq "/tail" -or $path -eq "/log" -and $req.HttpMethod -eq "GET") {
            $n = 80
            if ($req.QueryString["n"]) { [void][int]::TryParse($req.QueryString["n"], [ref]$n) }
            $lines = Get-Content -LiteralPath $OutFile -Tail $n -ErrorAction SilentlyContinue
            Write-Response $ctx 200 (($lines -join "`n") + "`n")
            continue
        }
        if ($path -eq "/log" -and $req.HttpMethod -eq "POST") {
            $reader = New-Object IO.StreamReader($req.InputStream, [Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd()
            $reader.Close()
            if ($body) {
                $stamp = Get-Date -Format "HH:mm:ss.fff"
                $toWrite = foreach ($line in ($body -split "`r?`n")) {
                    if ($line.Length -gt 0) { "[$stamp] $line" }
                }
                if ($toWrite) {
                    Add-Content -LiteralPath $OutFile -Value ($toWrite -join "`n") -Encoding UTF8
                }
            }
            Write-Response $ctx 204 ""
            continue
        }
        if ($path -eq "/clear" -and $req.HttpMethod -eq "POST") {
            Set-Content -LiteralPath $OutFile -Value "" -Encoding UTF8
            Write-Response $ctx 200 "cleared"
            continue
        }
        Write-Response $ctx 404 "not found"
    } catch {
        try { Write-Response $ctx 500 ("$_") } catch {}
    }
}
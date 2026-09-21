# DESCRIPTION: Cached BTC/ETH/gold/silver price lookup for the status line, dot-sourced by claude-statusline.ps1 — not a standalone command, so it has no .bat entry point.

$script:PriceCacheFile = Join-Path $env:TEMP '_statusline_prices.json'
$script:PriceTtlSeconds = 60

# Yahoo Finance symbols. Gold and silver are front-month futures, not spot.
$script:PriceSymbols = [ordered]@{
    btc    = 'BTC-USD'
    eth    = 'ETH-USD'
    gold   = 'GC=F'
    silver = 'SI=F'
}

# Fetch every symbol and rewrite the cache. A symbol that fails keeps its previous cached
# value, so a transient network error never blanks the status line.
function Update-PriceCache {
    $prices = @{}
    if (Test-Path $script:PriceCacheFile) {
        try {
            $existing = Get-Content $script:PriceCacheFile -Raw | ConvertFrom-Json
            foreach ($p in $existing.PSObject.Properties) { $prices[$p.Name] = $p.Value }
        } catch { }
    }
    foreach ($name in $script:PriceSymbols.Keys) {
        $symbol = $script:PriceSymbols[$name]
        try {
            $url = "https://query1.finance.yahoo.com/v8/finance/chart/${symbol}?interval=1d&range=1d"
            $r = Invoke-RestMethod $url -UserAgent 'Mozilla/5.0' -TimeoutSec 5
            $prices[$name] = [double]$r.chart.result[0].meta.regularMarketPrice
        } catch { }
    }
    $prices | ConvertTo-Json | Set-Content $script:PriceCacheFile
}

# Return cached prices as an object (properties absent when unknown) and, when the cache is
# missing or older than the TTL, kick off a detached refresh. Never waits on the network.
# The cache file's mtime doubles as "last attempted", so bumping it before spawning stops
# concurrent status line renders from each launching their own refresh, and a failing
# network is retried once per TTL rather than on every render.
function Get-CachedPrices {
    $exists = Test-Path $script:PriceCacheFile
    $stale = -not $exists -or
        ((Get-Date) - (Get-Item $script:PriceCacheFile).LastWriteTime).TotalSeconds -gt $script:PriceTtlSeconds
    if ($stale) {
        if ($exists) { (Get-Item $script:PriceCacheFile).LastWriteTime = Get-Date }
        else { '{}' | Set-Content $script:PriceCacheFile }
        $self = Join-Path $PSScriptRoot '_prices.ps1'
        Start-Process pwsh -WindowStyle Hidden -ArgumentList '-NoProfile', '-Command', ". '$self'; Update-PriceCache"
    }
    try { return Get-Content $script:PriceCacheFile -Raw | ConvertFrom-Json } catch { return [pscustomobject]@{} }
}

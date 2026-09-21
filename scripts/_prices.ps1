# DESCRIPTION: Cached BTC/ETH/gold/silver price lookup for the status line, dot-sourced by claude-statusline.ps1 — not a standalone command, so it has no .bat entry point.

# The cache and lock live in %TEMP%, shared by every Claude Code session on the machine, so
# any number of sessions cost at most one round of Yahoo Finance requests per TTL.
$script:PriceCacheFile = Join-Path $env:TEMP '_statusline_prices.json'
$script:PriceLockFile = Join-Path $env:TEMP '_statusline_prices.lock'
$script:PriceTtlSeconds = 300
# A refresh that has held the lock this long is presumed dead (crashed or killed).
$script:PriceLockStaleSeconds = 60

# Yahoo Finance symbols. Gold and silver are front-month futures, not spot.
$script:PriceSymbols = [ordered]@{
    btc    = 'BTC-USD'
    eth    = 'ETH-USD'
    gold   = 'GC=F'
    silver = 'SI=F'
}

function Get-UnixNow { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

# Cache shape: { attemptedAt, fetchedAt, prices: { btc, eth, gold, silver } } with times in
# Unix seconds. attemptedAt is the last refresh try (success or not) and drives the TTL, so
# a failing network is retried once per TTL rather than on every render; fetchedAt is the
# last time any price was actually updated. Missing/corrupt/old-format files read as empty
# and stale.
function Read-PriceCache {
    $cache = @{ attemptedAt = 0; fetchedAt = 0; prices = @{} }
    try {
        $json = Get-Content $script:PriceCacheFile -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($json.attemptedAt) { $cache.attemptedAt = [long]$json.attemptedAt }
        if ($json.fetchedAt) { $cache.fetchedAt = [long]$json.fetchedAt }
        if ($json.prices) {
            foreach ($p in $json.prices.PSObject.Properties) { $cache.prices[$p.Name] = $p.Value }
        }
    } catch { }
    return $cache
}

function Test-PriceCacheStale($Cache) {
    return ((Get-UnixNow) - $Cache.attemptedAt) -gt $script:PriceTtlSeconds
}

# Write to a temp file and move it into place so a concurrent reader never sees a
# half-written cache.
function Write-PriceCache($Cache) {
    $tmp = "$script:PriceCacheFile.$PID.tmp"
    $Cache | ConvertTo-Json -Depth 3 | Set-Content $tmp
    Move-Item $tmp $script:PriceCacheFile -Force
}

# Try to become the one process allowed to refresh. CreateNew is atomic, so of several
# sessions rendering at the same instant exactly one succeeds. A lock left behind by a dead
# refresh is cleared once it's old enough, and the next render can claim it.
function Enter-PriceRefreshLock {
    try {
        [System.IO.File]::Open($script:PriceLockFile, 'CreateNew', 'Write', 'None').Dispose()
        return $true
    } catch {
        try {
            $age = ((Get-Date) - (Get-Item $script:PriceLockFile -ErrorAction Stop).LastWriteTime).TotalSeconds
            if ($age -gt $script:PriceLockStaleSeconds) { Remove-Item $script:PriceLockFile -Force }
        } catch { }
        return $false
    }
}

# Fetch every symbol and rewrite the cache, then release the lock. Runs in the detached
# refresh process. It re-checks staleness first: another session may have finished a
# refresh between this one's stale read and its lock claim. A symbol that fails keeps its
# previous cached value, so a transient network error never blanks the status line.
function Update-PriceCache {
    try {
        $cache = Read-PriceCache
        if (-not (Test-PriceCacheStale $cache)) { return }
        $updated = $false
        foreach ($name in $script:PriceSymbols.Keys) {
            $symbol = $script:PriceSymbols[$name]
            try {
                $url = "https://query1.finance.yahoo.com/v8/finance/chart/${symbol}?interval=1d&range=1d"
                $r = Invoke-RestMethod $url -UserAgent 'Mozilla/5.0' -TimeoutSec 5
                $cache.prices[$name] = [double]$r.chart.result[0].meta.regularMarketPrice
                $updated = $true
            } catch { }
        }
        $now = Get-UnixNow
        $cache.attemptedAt = $now
        if ($updated) { $cache.fetchedAt = $now }
        Write-PriceCache $cache
    } finally {
        Remove-Item $script:PriceLockFile -Force -ErrorAction SilentlyContinue
    }
}

# Return the cached prices as an object (properties absent when unknown). When the cache is
# older than the TTL and this process wins the lock, start a detached refresh. Never waits
# on the network.
function Get-CachedPrices {
    $cache = Read-PriceCache
    if ((Test-PriceCacheStale $cache) -and (Enter-PriceRefreshLock)) {
        $self = Join-Path $PSScriptRoot '_prices.ps1'
        Start-Process pwsh -WindowStyle Hidden -ArgumentList '-NoProfile', '-Command', ". '$self'; Update-PriceCache"
    }
    return [pscustomobject]$cache.prices
}

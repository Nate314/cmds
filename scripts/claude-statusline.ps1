# DESCRIPTION: Render a Claude Code statusline showing the session's launch directory, git branch, model, context usage, 5-hour/7-day rate-limit usage, and current date/time with colored symbol icons (reads Claude's JSON from stdin)

# Emit UTF-8 so the symbol glyphs survive when Claude Code captures stdout.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot '_common.ps1')

# Length of $Text as it actually appears on screen, i.e. with ANSI color codes and OSC 8
# hyperlink wrappers stripped out (they take zero columns). Used to wrap segments onto
# additional lines by real width rather than by raw string length.
function Get-VisibleLength([string]$Text) {
    $stripped = $Text -replace "$e\]8;;[^$bel]*$bel", ''
    $stripped = $stripped -replace "$e\[[0-9;]*m", ''
    return $stripped.Length
}

# Build a link to a model's page on platform.claude.com from its API id, e.g.
# "claude-sonnet-5" -> sonnet-5, "claude-haiku-4-5-20251001" -> haiku-4-5 (date suffix
# stripped). Falls back to the general models overview when there's no id to work from.
function ConvertTo-ModelUrl([string]$ModelId) {
    if (-not $ModelId) { return 'https://platform.claude.com/docs/en/models/overview' }
    $slug = ($ModelId -replace '^claude-', '') -replace '-\d{8}$', ''
    return "https://platform.claude.com/docs/en/models/$slug/overview"
}

# Build a link to a branch's page on github.com from the repo's origin remote. Returns
# $null when there's no branch or remote, or the remote isn't a github.com URL — a link
# to a branch's page only makes sense there, not on other git hosts.
function ConvertTo-GitHubBranchUrl([string]$RepoDir, [string]$BranchName) {
    if (-not $BranchName) { return $null }
    $remote = git -C $RepoDir config --get remote.origin.url 2>$null
    if (-not $remote) { return $null }
    $httpsUrl = ($remote -replace '^git@github\.com:', 'https://github.com/') -replace '\.git$', ''
    if ($httpsUrl -notmatch '^https://github\.com/') { return $null }
    $encodedBranch = ConvertTo-EncodedUriPath $BranchName
    return "$httpsUrl/tree/$encodedBranch"
}

# Color a rate-limit usage percentage green/yellow/red by how close it is to the limit.
function Get-UsageColor([double]$Pct) {
    if ($Pct -ge 80) { return '91' }
    if ($Pct -ge 50) { return '93' }
    return '92'
}

# Claude Code pipes a JSON object on stdin; fall back to the real cwd when run by hand.
# Read via the $input pipeline variable, not [Console]::In — when this script runs under
# `pwsh -File` invoked from Git Bash (as Claude Code does on Windows), Console.In does not
# see the piped data even though the pipe is real, while $input does. $input never blocks
# when nothing is piped, so this is also safe to run by hand.
$cwd = $null
$projectDir = $null
$model = $null
$modelId = $null
$ctxPct = $null
$fiveHourPct = $null
$sevenDayPct = $null
$raw = $input | Out-String
if ($raw.Trim()) {
    try {
        $json = $raw | ConvertFrom-Json
        $cwd = $json.workspace.current_dir
        if (-not $cwd) { $cwd = $json.cwd }
        $projectDir = $json.workspace.project_dir
        $model = $json.model.display_name
        $modelId = $json.model.id
        $ctxPct = $json.context_window.used_percentage
        $fiveHourPct = $json.rate_limits.five_hour.used_percentage
        $sevenDayPct = $json.rate_limits.seven_day.used_percentage
    } catch { }
}
if (-not $cwd) { $cwd = (Get-Location).Path }
# project_dir is where the session was launched from; it doesn't move when Claude
# cd's elsewhere internally, so show that instead of the (possibly relocated) cwd.
if (-not $projectDir) { $projectDir = $cwd }

$now = Get-Date

# Folder symbol (yellow) + path (bright cyan), with the home directory collapsed to ~.
# The path is an OSC 8 hyperlink to a file:// URI, so Ctrl+click opens it in File Explorer
# on terminals that support clickable links (e.g. Windows Terminal).
$dirText = Format-ColorText '96' (Format-HomePath $projectDir)
$dirUri = ConvertTo-FileUri $projectDir
if ($dirUri) { $dirText = Format-Hyperlink $dirUri $dirText }
$dir = (Format-ColorText '33' '📁') + ' ' + $dirText

# Clock symbol (green) + date/time (bright magenta)
$time = (Format-ColorText '32' '🕒') + ' ' + (Format-ColorText '95' $now.ToString('yyyy-MM-dd HH:mm:ss'))

$sep = Format-ColorText '90' ' | '
$segments = @($dir)

# Model symbol (bright blue) — only when Claude Code supplied it. Links to the model's
# page on platform.claude.com.
if ($model) {
    $modelText = Format-Hyperlink (ConvertTo-ModelUrl $modelId) (Format-ColorText '94' $model)
    $segments += (Format-ColorText '94' '🤖') + ' ' + $modelText
}

# Git branch symbol (bright green) — only when cwd is a repo. Links to the branch on
# github.com when the repo's origin remote is a GitHub URL.
$branch = git -C $cwd rev-parse --abbrev-ref HEAD 2>$null
if ($LASTEXITCODE -eq 0 -and $branch) {
    $branchText = Format-ColorText '92' $branch
    $branchUrl = ConvertTo-GitHubBranchUrl $cwd $branch
    if ($branchUrl) { $branchText = Format-Hyperlink $branchUrl $branchText }
    $segments += (Format-ColorText '92' '🌿') + ' ' + $branchText
}

# Context usage symbol (bright yellow) — only when Claude Code supplied it
if ($null -ne $ctxPct) {
    $segments += (Format-ColorText '93' '📊') + ' ' + (Format-ColorText '93' "$ctxPct% ctx")
}

# 5-hour session and 7-day weekly rate-limit usage — only present for Pro/Max
# subscribers, and only after the session's first API response, so either (or both)
# can be absent.
if ($null -ne $fiveHourPct) {
    $color = Get-UsageColor $fiveHourPct
    $segments += (Format-ColorText $color '⏳') + ' ' + (Format-ColorText $color "$fiveHourPct% 5h")
}
if ($null -ne $sevenDayPct) {
    $color = Get-UsageColor $sevenDayPct
    $segments += (Format-ColorText $color '📅') + ' ' + (Format-ColorText $color "$sevenDayPct% 7d")
}

$segments += $time

# Wrap segments onto additional lines when they don't fit in the terminal width. Claude
# Code sets COLUMNS/LINES on the environment before running this script specifically so
# scripts can adapt (stdout is captured, not connected to the terminal, so tput/console
# width detection doesn't work here). Each line this script writes renders as its own row.
$columns = 80
$parsedColumns = 0
if ([int]::TryParse($env:COLUMNS, [ref]$parsedColumns) -and $parsedColumns -gt 0) {
    $columns = $parsedColumns
}
$sepWidth = Get-VisibleLength $sep

$lines = @()
$currentSegments = @()
$currentWidth = 0
foreach ($seg in $segments) {
    $segWidth = Get-VisibleLength $seg
    $addedWidth = if ($currentSegments.Count -eq 0) { $segWidth } else { $segWidth + $sepWidth }
    if ($currentSegments.Count -gt 0 -and ($currentWidth + $addedWidth) -gt $columns) {
        $lines += ($currentSegments -join $sep)
        $currentSegments = @($seg)
        $currentWidth = $segWidth
    } else {
        $currentSegments += $seg
        $currentWidth += $addedWidth
    }
}
if ($currentSegments.Count -gt 0) { $lines += ($currentSegments -join $sep) }

$lines | ForEach-Object { Write-Output $_ }

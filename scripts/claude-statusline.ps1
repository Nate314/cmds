# DESCRIPTION: Render a Claude Code statusline showing the session's launch directory, git branch, model, context usage, 5-hour/7-day rate-limit usage, and current date/time with colored symbol icons (reads Claude's JSON from stdin)

# Emit UTF-8 so the symbol glyphs survive when Claude Code captures stdout.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot '_common.ps1')
. (Join-Path $PSScriptRoot '_statusline-settings.ps1')
. (Join-Path $PSScriptRoot '_prices.ps1')

# Terminal column width of a single Unicode code point: 2 for characters terminals render
# double-wide, 1 otherwise. Supplementary-plane emoji (e.g. 📁, 🤖) are surrogate pairs, so
# .NET string .Length already counts them as 2 UTF-16 units — matching their 2-column width
# by coincidence. But some double-wide emoji live in the Basic Multilingual Plane as a
# single UTF-16 unit (e.g. the hourglass ⏳, U+23F3), where .Length undercounts their width
# by 1. Counting by actual code point, not raw .Length, avoids that undercount.
function Get-CharWidth([int]$CodePoint) {
    if ($CodePoint -eq 0xFE0F) { return 0 }  # Variation selector (e.g. the emoji form of ✏️): invisible, takes no column
    if (($CodePoint -ge 0x2300 -and $CodePoint -le 0x23FF) -or  # Misc Technical (hourglass, clocks, watch)
        ($CodePoint -ge 0x2600 -and $CodePoint -le 0x27BF) -or  # Misc Symbols & Dingbats
        ($CodePoint -ge 0x2B00 -and $CodePoint -le 0x2BFF) -or  # Misc Symbols & Arrows
        $CodePoint -ge 0x1F000) {                                # Supplementary-plane emoji
        return 2
    }
    return 1
}

# Width of $Text as it actually appears on screen, i.e. with ANSI color codes and OSC 8
# hyperlink wrappers stripped out (they take zero columns) and double-wide characters
# counted as 2. Used to wrap segments onto additional lines by real width rather than by
# raw string length.
function Get-VisibleLength([string]$Text) {
    $stripped = $Text -replace "$e\]8;;[^$bel]*$bel", ''
    $stripped = $stripped -replace "$e\[[0-9;]*m", ''
    $width = 0
    $i = 0
    while ($i -lt $stripped.Length) {
        $codePoint = [char]::ConvertToUtf32($stripped, $i)
        $width += Get-CharWidth $codePoint
        $i += if ([char]::IsSurrogatePair($stripped, $i)) { 2 } else { 1 }
    }
    return $width
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

# A circle glyph filled in proportionally to a 0-100 percentage, from empty to full.
function Get-CircleIcon([double]$Pct) {
    if ($Pct -ge 88) { return '●' }
    if ($Pct -ge 63) { return '◕' }
    if ($Pct -ge 38) { return '◑' }
    if ($Pct -ge 13) { return '◔' }
    return '○'
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
$linesAdded = $null
$linesRemoved = $null
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
        $linesAdded = $json.cost.total_lines_added
        $linesRemoved = $json.cost.total_lines_removed
    } catch { }
}
if (-not $cwd) { $cwd = (Get-Location).Path }
# project_dir is where the session was launched from; it doesn't move when Claude
# cd's elsewhere internally, so show that instead of the (possibly relocated) cwd.
if (-not $projectDir) { $projectDir = $cwd }

$now = Get-Date
$show = Get-StatusLineState

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
# Keyed by item so the layout can group related segments; insertion order is the
# single-line display order.
$segments = [ordered]@{}
if ($show['dir']) { $segments['dir'] = $dir }

# Model symbol (bright blue) — only when Claude Code supplied it. Links to the model's
# page on platform.claude.com.
if ($show['model'] -and $model) {
    $modelText = Format-Hyperlink (ConvertTo-ModelUrl $modelId) (Format-ColorText '94' $model)
    $segments['model'] = (Format-ColorText '94' '🤖') + ' ' + $modelText
}

# Git branch symbol (bright green) — only when cwd is a repo. Links to the branch on
# github.com when the repo's origin remote is a GitHub URL.
$branch = if ($show['branch']) { git -C $cwd rev-parse --abbrev-ref HEAD 2>$null }
if ($show['branch'] -and $LASTEXITCODE -eq 0 -and $branch) {
    $branchText = Format-ColorText '92' $branch
    $branchUrl = ConvertTo-GitHubBranchUrl $cwd $branch
    if ($branchUrl) { $branchText = Format-Hyperlink $branchUrl $branchText }
    $segments['branch'] = (Format-ColorText '92' '🌿') + ' ' + $branchText
}

# Context usage — only when Claude Code supplied it (bright yellow). The icon itself
# fills in from empty to full circle as usage climbs toward 100%.
if ($show['ctx'] -and $null -ne $ctxPct) {
    $segments['ctx'] = (Format-ColorText '93' (Get-CircleIcon $ctxPct)) + ' ' + (Format-ColorText '93' "$ctxPct% ctx")
}

# 5-hour session and 7-day weekly rate-limit usage (bright yellow) — only present for
# Pro/Max subscribers, and only after the session's first API response, so either (or
# both) can be absent.
if ($show['5h'] -and $null -ne $fiveHourPct) {
    $segments['5h'] = (Format-ColorText '93' '⏳') + ' ' + (Format-ColorText '93' "$fiveHourPct% 5h")
}
if ($show['7d'] -and $null -ne $sevenDayPct) {
    $segments['7d'] = (Format-ColorText '93' '📅') + ' ' + (Format-ColorText '93' "$sevenDayPct% 7d")
}

# Lines added (green) / removed (red) this session — only when Claude Code supplied them.
if ($show['lines'] -and ($null -ne $linesAdded -or $null -ne $linesRemoved)) {
    $segments['lines'] = (Format-ColorText '97' '✏️') + ' ' + (Format-ColorText '92' "+$([int]$linesAdded)") + ' ' + (Format-ColorText '91' "-$([int]$linesRemoved)")
}

# Live prices come from a cache refreshed in the background, so a segment appears only
# once its prices have been fetched at least once.
if ($show['crypto'] -or $show['metals']) {
    $prices = Get-CachedPrices
    if ($show['crypto'] -and $null -ne $prices.btc -and $null -ne $prices.eth) {
        $segments['crypto'] = (Format-ColorText '93' '₿') + ' ' + (Format-ColorText '93' ('{0:N0}' -f $prices.btc)) + '  ' +
            (Format-ColorText '94' 'Ξ') + ' ' + (Format-ColorText '94' ('{0:N0}' -f $prices.eth))
    }
    if ($show['metals'] -and $null -ne $prices.gold -and $null -ne $prices.silver) {
        $segments['metals'] = (Format-ColorText '33' '🥇') + ' ' + (Format-ColorText '33' ('{0:N0}' -f $prices.gold)) + '  ' +
            (Format-ColorText '37' '🥈') + ' ' + (Format-ColorText '37' ('{0:N2}' -f $prices.silver))
    }
}

if ($show['clock']) { $segments['clock'] = $time }

# Wrap segments into an aligned grid of rows when they don't fit in the terminal width. Claude
# Code sets COLUMNS/LINES on the environment before running this script specifically so
# scripts can adapt (stdout is captured, not connected to the terminal, so tput/console
# width detection doesn't work here). Each line this script writes renders as its own row.
$columns = 80
$parsedColumns = 0
if ([int]::TryParse($env:COLUMNS, [ref]$parsedColumns) -and $parsedColumns -gt 0) {
    $columns = $parsedColumns
}
# The status line area is a few columns narrower than the COLUMNS Claude Code reports (it
# reserves its own padding): with COLUMNS=129, a line computed as exactly 129 wide rendered
# truncated with an ellipsis around column 125. Wrap against a slightly smaller width so
# lines never reach the truncation point.
$columns = [Math]::Max(1, $columns - 4)
$sepWidth = Get-VisibleLength $sep
# The border adds "| " and " |" (4 columns) around the grid, so the grid gets that much less.
$borderWidth = 4
if ($show['border']) { $columns = [Math]::Max(1, $columns - $borderWidth) }

# A grid is an array of columns; each column is an array of cell strings, top to bottom.

# Row-major grid of $Segments over $Rows rows: cells fill row by row, so column c holds
# cells c, c+cols, c+2*cols, ...
function Get-RowMajorGrid([string[]]$Segments, [int]$Rows) {
    $cols = [int][Math]::Ceiling($Segments.Count / $Rows)
    $grid = @()
    for ($c = 0; $c -lt $cols; $c++) {
        $column = @()
        for ($i = $c; $i -lt $Segments.Count; $i += $cols) { $column += $Segments[$i] }
        $grid += , $column
    }
    return , $grid
}

# Stacked grid: each column of $Stacks (keys of related items) becomes a column holding
# whichever of those segments are present; columns with none present are dropped.
function Get-StackedGrid($Segments, $Stacks) {
    $grid = @()
    foreach ($stack in $Stacks) {
        $column = @($stack | Where-Object { $Segments.Contains($_) } | ForEach-Object { $Segments[$_] })
        if ($column.Count -gt 0) { $grid += , $column }
    }
    return , $grid
}

# Width of each grid column: its widest cell.
function Get-GridColumnWidths($Grid) {
    return @($Grid | ForEach-Object { ($_ | ForEach-Object { Get-VisibleLength $_ } | Measure-Object -Maximum).Maximum })
}

function Get-GridWidth($Grid, [int]$SepWidth) {
    $widths = Get-GridColumnWidths $Grid
    return ($widths | Measure-Object -Sum).Sum + ($widths.Count - 1) * $SepWidth
}

# Render a grid to one string per row, padding each cell to its column's width so the
# separators line up across rows. The last cell in a row is left unpadded.
function Format-Grid($Grid, [string]$Sep) {
    $widths = Get-GridColumnWidths $Grid
    $rowCount = ($Grid | ForEach-Object { $_.Count } | Measure-Object -Maximum).Maximum
    $lines = @()
    for ($r = 0; $r -lt $rowCount; $r++) {
        $cells = @()
        $lastCol = -1
        for ($c = 0; $c -lt $Grid.Count; $c++) { if ($r -lt $Grid[$c].Count) { $lastCol = $c } }
        for ($c = 0; $c -le $lastCol; $c++) {
            if ($r -ge $Grid[$c].Count) { $cells += ' ' * $widths[$c]; continue }
            $pad = if ($c -eq $lastCol) { 0 } else { $widths[$c] - (Get-VisibleLength $Grid[$c][$r]) }
            $cells += $Grid[$c][$r] + (' ' * $pad)
        }
        $lines += ($cells -join $Sep)
    }
    return $lines
}

# Pick the first layout that fits $MaxWidth: everything on one line; else related items
# stacked into columns; else a plain row-major grid with as few rows as possible (one
# segment per row when nothing narrower fits).
function Select-StatusLineGrid($Segments, [string]$Sep, [int]$MaxWidth) {
    $sepWidth = Get-VisibleLength $Sep
    $values = @($Segments.Values)
    $candidates = @((Get-RowMajorGrid $values 1), (Get-StackedGrid $Segments $script:StatusLineStacks))
    foreach ($grid in $candidates) {
        if ($grid.Count -gt 0 -and (Get-GridWidth $grid $sepWidth) -le $MaxWidth) { return , $grid }
    }
    for ($rows = 2; $rows -lt $values.Count; $rows++) {
        $grid = Get-RowMajorGrid $values $rows
        if ((Get-GridWidth $grid $sepWidth) -le $MaxWidth) { return , $grid }
    }
    return , (Get-RowMajorGrid $values $values.Count)
}

# Draw a rounded box around $Lines, padding each to the widest so the right edge lines up.
function Format-RoundedBorder([string[]]$Lines) {
    $inner = ($Lines | ForEach-Object { Get-VisibleLength $_ } | Measure-Object -Maximum).Maximum
    $horizontal = [string][char]0x2500 * ($inner + 2)
    $vertical = Format-ColorText '90' ([string][char]0x2502)
    $top = Format-ColorText '90' "$([char]0x256D)$horizontal$([char]0x256E)"
    $bottom = Format-ColorText '90' "$([char]0x2570)$horizontal$([char]0x256F)"
    $body = $Lines | ForEach-Object { "$vertical $_$(' ' * ($inner - (Get-VisibleLength $_))) $vertical" }
    return @($top) + @($body) + @($bottom)
}

if ($segments.Count -gt 0) {
    $lines = Format-Grid (Select-StatusLineGrid $segments $sep $columns) $sep
    if ($show['border']) { $lines = Format-RoundedBorder $lines }
    $lines | ForEach-Object { Write-Output $_ }
}

# DESCRIPTION: Render a Claude Code statusline showing the session's launch directory, git branch, model, context usage, and current date/time with colored symbol icons (reads Claude's JSON from stdin)

# Emit UTF-8 so the symbol glyphs survive when Claude Code captures stdout.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$e = [char]27
$bel = [char]7
function Format-ColorText([string]$Code, [string]$Text) { "$e[${Code}m$Text$e[0m" }

# OSC 8 hyperlink: wraps $Text so terminals like Windows Terminal make it Ctrl+clickable.
function Format-Hyperlink([string]$Uri, [string]$Text) { "$e]8;;$Uri$bel$Text$e]8;;$bel" }

# Length of $Text as it actually appears on screen, i.e. with ANSI color codes and OSC 8
# hyperlink wrappers stripped out (they take zero columns). Used to wrap segments onto
# additional lines by real width rather than by raw string length.
function Get-VisibleLength([string]$Text) {
    $stripped = $Text -replace "$e\]8;;[^$bel]*$bel", ''
    $stripped = $stripped -replace "$e\[[0-9;]*m", ''
    return $stripped.Length
}

# Percent-encode each '/'-separated segment of a URI path independently, so the slashes
# themselves stay literal instead of becoming %2F.
function ConvertTo-EncodedUriPath([string]$Path) {
    return ($Path -split '/' | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
}

# Convert a Windows filesystem path to a file:// URI, percent-encoding unsafe characters
# while preserving the drive-letter colon and path separators.
function ConvertTo-FileUri([string]$Path) {
    if (-not $Path) { return $null }
    $forward = ($Path -replace '\\', '/').TrimEnd('/')
    $encoded = ConvertTo-EncodedUriPath $forward
    # ':' is illegal in Windows filenames except after a drive letter, so restoring it
    # from EscapeDataString's %3A everywhere is safe and keeps "C:" readable in the URI.
    $encoded = $encoded -replace '%3A', ':'
    return "file:///$encoded"
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

# Collapse the user's home directory prefix to "~", tolerating either slash style.
function Format-HomePath([string]$Path) {
    if (-not $Path) { return $Path }
    $homePath = $env:USERPROFILE
    if (-not $homePath) { return $Path }
    $normPath = $Path.TrimEnd('\', '/') -replace '/', '\'
    $normHome = $homePath.TrimEnd('\', '/') -replace '/', '\'
    if ($normPath -ieq $normHome) { return '~' }
    if ($normPath.StartsWith("$normHome\", [System.StringComparison]::OrdinalIgnoreCase)) {
        return '~' + $Path.Substring($normHome.Length)
    }
    return $Path
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

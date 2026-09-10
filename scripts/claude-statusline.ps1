# DESCRIPTION: Render a Claude Code statusline showing the working directory, git branch, model, context usage, and current date/time with colored symbol icons (reads Claude's JSON from stdin)

# Emit UTF-8 so the symbol glyphs survive when Claude Code captures stdout.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$e = [char]27
function Color([string]$code, [string]$text) { "$e[${code}m$text$e[0m" }

# Claude Code pipes a JSON object on stdin; fall back to the real cwd when run by hand.
# Read via the $input pipeline variable, not [Console]::In — when this script runs under
# `pwsh -File` invoked from Git Bash (as Claude Code does on Windows), Console.In does not
# see the piped data even though the pipe is real, while $input does. $input never blocks
# when nothing is piped, so this is also safe to run by hand.
$cwd = $null
$model = $null
$ctxPct = $null
$raw = $input | Out-String
if ($raw.Trim()) {
    try {
        $json = $raw | ConvertFrom-Json
        $cwd = $json.workspace.current_dir
        if (-not $cwd) { $cwd = $json.cwd }
        $model = $json.model.display_name
        $ctxPct = $json.context_window.used_percentage
    } catch { }
}
if (-not $cwd) { $cwd = (Get-Location).Path }

$now = Get-Date

# Folder symbol (yellow) + path (bright cyan)
$dir = (Color '33' '📁') + ' ' + (Color '96' $cwd)

# Clock symbol (green) + date/time (bright magenta)
$time = (Color '32' '🕒') + ' ' + (Color '95' $now.ToString('yyyy-MM-dd HH:mm:ss'))

$sep = Color '90' ' | '
$segments = @($dir)

# Model symbol (bright blue) — only when Claude Code supplied it
if ($model) {
    $segments += (Color '94' '🤖') + ' ' + (Color '94' $model)
}

# Git branch symbol (bright green) — only when cwd is a repo
$branch = git -C $cwd rev-parse --abbrev-ref HEAD 2>$null
if ($LASTEXITCODE -eq 0 -and $branch) {
    $segments += (Color '92' '🌿') + ' ' + (Color '92' $branch)
}

# Context usage symbol (bright yellow) — only when Claude Code supplied it
if ($null -ne $ctxPct) {
    $segments += (Color '93' '📊') + ' ' + (Color '93' "$ctxPct% ctx")
}

$segments += $time
Write-Output ($segments -join $sep)

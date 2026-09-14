# DESCRIPTION: Shared formatting helpers (colors, OSC 8 hyperlinks, path display) dot-sourced by other scripts in this repo — not a standalone command, so it has no .bat entry point.

$e = [char]27
$bel = [char]7

function Format-ColorText([string]$Code, [string]$Text) { "$e[${Code}m$Text$e[0m" }

# OSC 8 hyperlink: wraps $Text so terminals like Windows Terminal make it Ctrl+clickable.
function Format-Hyperlink([string]$Uri, [string]$Text) { "$e]8;;$Uri$bel$Text$e]8;;$bel" }

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

# cmds

A personal collection of system-wide CLI commands. Add `~\cmds` to your `PATH` and use these commands from any terminal.

## Prerequisites

- **[PowerShell 7+ (pwsh)](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows)** — required. Every command's `.bat` file launches its script with `pwsh`, not Windows PowerShell (`powershell.exe`) or cmd.exe alone.
- **[Git for Windows](https://git-scm.com/download/win)** — optional. Without it, the Claude Code status line just omits the git branch segment; everything else works fine.
- **[Windows Terminal](https://aka.ms/terminal)** — recommended. The status line's clickable folder/model/branch links (OSC 8 hyperlinks) need a terminal that supports them; older consoles show the plain text instead.
- **[Claude Code](https://claude.com/claude-code)** — only needed if you want the status line feature; the other commands don't depend on it.

## Setup

Add the `cmds` directory to your system PATH:

```powershell
# Run once in an elevated PowerShell session
$cmdsPath = "$HOME\cmds"
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($currentPath -notlike "*$cmdsPath*") {
    [Environment]::SetEnvironmentVariable("Path", "$currentPath;$cmdsPath", "User")
}
```

Restart your terminal for the change to take effect.

## Architecture

```
cmds\
├── _run.ps1          # Single entry point for all commands
├── scripts\          # PowerShell implementation for each command
│   ├── _common.ps1   # Shared formatting helpers (colors, hyperlinks); not a command itself
│   ├── _statusline-settings.ps1  # Status line item list and ON/OFF state; not a command itself
│   ├── _prices.ps1   # Cached BTC/ETH/gold/silver prices; not a command itself
│   ├── ls.ps1
│   ├── cdwork.ps1
│   └── setup.ps1
├── .dotfiles\        # User configuration files
│   ├── .cdwork       # Work directory path for cdwork
│   └── .statusline   # Status line item ON/OFF state (created by claude-statusline-config)
├── ls.bat
├── cdwork.bat
└── setup.bat
```

Each command is a `.bat` file that delegates to `_run.ps1`, which:
1. Prints the command name in magenta
2. Logs the invocation with a timestamp to `logs\commands.log`
3. Calls the matching script under `scripts\`

To add a new command:
1. Create `scripts\mycommand.ps1`
2. Create `mycommand.bat` using an existing `.bat` as a template

## Note on directory-changing commands in PowerShell

Commands like `cdwork` that change the current directory work in **CMD** but not in PowerShell, because the `.bat` subprocess cannot modify the parent shell's directory. For PowerShell, run `setup` once to add the required wrapper function to your `$PROFILE`:

```powershell
function cdwork { Set-Location (& "$HOME\cmds\scripts\cdwork.ps1") }
```

## Commands

### `ls`

Lists directory contents using `Get-ChildItem`. Allows `ls` to work in CMD.

```
ls [path]
```

### `cdwork`

Changes the current directory to the configured work directory.

```
cdwork
```

Configure the work directory by editing `~\cmds\.dotfiles\.cdwork` — put the full path on a single line. Lines starting with `#` are ignored. The path supports `~` shorthand for your home directory (e.g. `~\Documents\code`); it's resolved to a full absolute path before use, since `cmd.exe`'s `cd /d` doesn't understand `~` itself.

### `setup`

Adds PowerShell wrapper functions for directory-changing commands (currently just `cdwork`) to your `$PROFILE`, creating the profile file if it doesn't exist yet. Safe to run repeatedly; it skips any wrapper already present.

```
setup
```

### `cmds`

Lists every available command in a table: its name (Ctrl+click to open that command's script), its description (from the `# DESCRIPTION:` line in its script), and — for a command like `cdwork` that reads a `.dotfiles\.<name>` file — the value it's currently configured to. Any command following that `.dotfiles\.<name>` convention picks up this column automatically, with no changes needed to `cmds.ps1` itself.

```
cmds
cmds -Border
```

Pass `-Border` to draw a rounded box around the list. The box is as wide as the longest row, so use a wide terminal; narrower ones will wrap the lines and break the box.

## Claude Code plugins

This repo also publishes a Claude Code plugin marketplace — see
[`plugins/README.md`](plugins/README.md) for installation and the
`notifywhen` command family (background condition watcher with a windowed
chime notification).

## Claude Code status line

![Status line example](images/statusline-example.png)

`scripts\claude-statusline.ps1` renders a Claude Code status line showing the session's launch directory, active model, git branch, context window usage, 5-hour/7-day rate-limit usage, lines added/removed this session (`✏️ +120 -34`, green/red), and current date/time, plus optional live BTC/ETH and gold/silver prices. The model, context, lines, and rate-limit fields only appear once Claude Code has sent that data (they're absent on the very first render of a session), and the rate-limit fields only appear at all for Pro/Max subscribers. The folder shown is `workspace.project_dir` (where the session was launched from), not `workspace.current_dir` (the live working directory) — so it stays put even after Claude `cd`s elsewhere internally; the git branch still reflects wherever the session currently is. A `%USERPROFILE%` prefix on the shown folder is collapsed to `~` (e.g. `C:\Users\you\cmds` → `~\cmds`). The folder is also an OSC 8 hyperlink to a `file://` URI, so Ctrl+click (Cmd+click on macOS) opens it in File Explorer on terminals that support clickable links, such as Windows Terminal. The model name links to that model's page on platform.claude.com, and the git branch links to that branch on github.com (only when the repo's `origin` remote is a GitHub URL). The context, 5-hour (session), and 7-day (weekly) usage percentages are all bright yellow. The context segment's icon fills in from an empty circle (○) to a full one (●) as usage climbs toward 100%.

Run `claude-statusline-config` to see every status line item with its current state (ON/OFF) and toggle any of them by number. The choices are saved to `.dotfiles\.statusline` (`key=on|off` lines) and take effect on the next status line refresh. Items without a saved entry default to ON, except the price items.

The price items (BTC/ETH and gold/silver) are OFF by default. When enabled, prices come from Yahoo Finance's keyless chart endpoint (gold and silver are front-month futures, not spot). The status line never waits on the network: it reads a cache at `%TEMP%\_statusline_prices.json` (prices plus `fetchedAt` and `attemptedAt` Unix timestamps) and, when the last attempt is more than 5 minutes old, starts a hidden background refresh. The cache and a lock file (`%TEMP%\_statusline_prices.lock`) are shared by every Claude Code session, so any number of open sessions make at most one round of Yahoo Finance requests per 5 minutes; renders in between, including the status line's frequent refreshes, just read the cache. A segment appears once its prices have been fetched at least once. A failed fetch keeps the last known values and is retried after the next 5 minutes, not on every render.

When the segments don't fit on one line, the status line wraps into an aligned grid, trying layouts in this order and using the first that fits: (1) related items stacked into columns (dir over clock, model over context, branch over lines changed, 5h over 7d, BTC/ETH over gold/silver), which gives two rows when everything is enabled; (2) a plain row-by-row grid with the fewest rows that fit. Each column is padded to its widest cell so the `|` separators line up across rows. Items that are toggled off or have no data are skipped, and the stacks are defined in `scripts\_statusline-settings.ps1`. The width comes from the `COLUMNS` environment variable Claude Code sets before running the script, minus a 4-column margin because the status line area is slightly narrower than `COLUMNS` reports (each line the script writes renders as its own status-line row).

To enable it, add this to `~\.claude\settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "pwsh -NoProfile -File C:/Users/<you>/cmds/scripts/claude-statusline.ps1",
    "refreshInterval": 15
  }
}
```

Fully quit and relaunch `claude` afterward — the `statusLine` setting is only read at startup.

**Windows gotchas:**

- Claude Code runs `statusLine` commands through Git Bash when it's installed, and Git Bash treats unquoted backslashes as escape characters. A `command` path written with backslashes (e.g. `C:\Users\...\claude-statusline.bat`) gets silently mangled and the status line never appears, with no visible error. Always use forward slashes in the `command` path, as shown above.
- When `pwsh -File` is invoked from a Git Bash pipe (as Claude Code does here), `[Console]::In.ReadToEnd()` does not see the piped JSON even though the pipe is real — it silently reads empty. The script reads stdin via the `$input` pipeline variable instead, which works in both this piped scenario and when the script is run standalone by hand.

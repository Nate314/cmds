# cmds

Personal Windows CLI command collection. See README.md for architecture and usage; this file is gotchas the codebase won't teach you.

## Windows shell gotchas

- Claude Code invokes `statusLine` commands through **Git Bash** when it's installed (not cmd.exe or PowerShell directly), even on Windows. Any path in a `command` string in `settings.json` must use forward slashes — Git Bash treats unescaped backslashes as escape characters and silently mangles the path, with no visible error.
- When a PowerShell script is run as `pwsh -File script.ps1` from a Git Bash pipe (as Claude Code's statusLine does), `[Console]::In.ReadToEnd()` does **not** see the piped stdin even though the pipe is real — it silently returns empty. Read piped input via the `$input` pipeline variable instead; it works both in that piped scenario and when a script is run standalone by hand (it doesn't block waiting for input either way).
- In a `.bat` file, `%VAR%` inside a parenthesized `( ... )` block is expanded once, at parse time, before any line in that same block executes — so referencing a variable that an earlier line in the *same block* just `set` will read as empty. Use `setlocal enabledelayedexpansion` and `!VAR!` for any variable set and read within the same block (see `cdwork.bat`).

## Conventions in this repo

- Shared formatting helpers (ANSI color, OSC 8 hyperlinks, `file://` URI conversion, `~`-collapsing) live in `scripts/_common.ps1`, dot-sourced by scripts that need them (e.g. `. (Join-Path $PSScriptRoot '_common.ps1')`). Don't duplicate these — add to `_common.ps1` and dot-source it instead.
- PowerShell functions use the Verb-Noun convention with an approved verb (`ConvertTo-`, `Format-`, `Get-`, `Test-`, etc.), not bare method-style names.
- A command that persists user configuration follows the `.dotfiles\.<command-name>` naming convention (e.g. `cdwork` reads `.dotfiles\.cdwork`). The `cmds` command auto-detects any file matching that pattern and displays its current value — no code changes needed in `cmds.ps1` to support a new one.
- This is a personal, single-maintainer utility repo: commits go directly to `master`, no branch/PR workflow.

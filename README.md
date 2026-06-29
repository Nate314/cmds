# cmds

A personal collection of system-wide CLI commands. Add `~\cmds` to your `PATH` and use these commands from any terminal.

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
│   ├── ls.ps1
│   └── cdwork.ps1
├── .dotfiles\        # User configuration files
│   └── .cdwork       # Work directory path for cdwork
├── ls.bat
└── cdwork.bat
```

Each command is a `.bat` file that delegates to `_run.ps1`, which:
1. Prints the command name in magenta
2. Logs the invocation with a timestamp to `logs\commands.log`
3. Calls the matching script under `scripts\`

To add a new command:
1. Create `scripts\mycommand.ps1`
2. Create `mycommand.bat` using an existing `.bat` as a template

## Note on directory-changing commands in PowerShell

Commands like `cdwork` that change the current directory work in **CMD** but not in PowerShell, because the `.bat` subprocess cannot modify the parent shell's directory. For PowerShell, add a wrapper function to your `$PROFILE`:

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

Configure the work directory by editing `~\cmds\.dotfiles\.cdwork` — put the full path on a single line. Lines starting with `#` are ignored.

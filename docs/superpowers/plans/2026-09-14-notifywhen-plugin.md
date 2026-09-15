# notifywhen Claude Code Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Claude Code plugin marketplace (`cmds`) to this repo with a `notifywhen` command family that polls a natural-language condition against a URL and pops a kiosk-mode Chrome notification when it becomes true, plus `notifywhen-list`/`notifywhen-stop` to manage active watchers.

**Architecture:** A marketplace manifest + one plugin (`cmds`) with three command markdown files. `notifywhen` generates a condition-specific `check.ps1`, a static `notify.html`, and a `meta.json` registry entry into a per-run temp directory, then launches the reusable `scripts\notifywhen-watch.ps1` engine detached and hidden. That engine polls `check.ps1` on an interval, and on success launches an isolated (own `--user-data-dir`) Chrome kiosk window, waits for it to close, then deletes the run directory. `notifywhen-list`/`notifywhen-stop` read/act on the `meta.json` registry files under `%TEMP%\cmds-notifywhen\`.

**Tech Stack:** PowerShell 7+ (`pwsh`), Claude Code plugin marketplace format, static HTML/CSS (no external requests), `gh` CLI for GitHub conditions.

**Spec:** `docs/superpowers/specs/2026-09-14-notifywhen-plugin-design.md`

## Global Constraints

- No new npm/other package dependencies — dependency-free repo convention.
- Windows/pwsh only; command markdown files must use PowerShell syntax when instructing script execution (not Bash), matching the rest of the repo.
- No automated test framework exists in this repo (confirmed: no Pester, no `*.Tests.ps1` files anywhere under `scripts/`). Verification in this plan is therefore manual: run the real script/command and inspect concrete output (files, log lines, process state), not `assert`-based unit tests. This matches the repo's existing convention and the user's standing instruction to verify UI/interactive behavior by actually running it, not by reading code.
- Runtime artifacts (`check.ps1`, `notify.html`, `chrome-profile\`, `meta.json`) live under `%TEMP%\cmds-notifywhen\<id>\` and are never committed. `logs\notifywhen-<id>.log` goes in the repo's existing gitignored `logs\` directory.
- `check.ps1` contract: exit `0` when the condition is currently true, non-zero otherwise; must never throw uncaught on a transient network error (treat as "not yet true").
- Commit after every task.

---

### Task 1: Marketplace and plugin manifests

**Files:**
- Create: `.claude-plugin/marketplace.json`
- Create: `plugins/cmds/.claude-plugin/plugin.json`

**Interfaces:**
- Produces: a discoverable marketplace named `cmds` containing a plugin named `cmds` whose commands are auto-discovered from `plugins/cmds/commands/*.md` (no explicit listing needed — confirmed Claude Code behavior).

- [ ] **Step 1: Create the marketplace manifest**

Create `.claude-plugin/marketplace.json`:

```json
{
  "name": "cmds",
  "owner": { "name": "Nate314" },
  "description": "Nate314's personal Claude Code plugins",
  "plugins": [
    {
      "name": "cmds",
      "source": "./plugins/cmds",
      "description": "Utility commands: notifywhen background condition watcher"
    }
  ]
}
```

- [ ] **Step 2: Create the plugin manifest**

Create `plugins/cmds/.claude-plugin/plugin.json`:

```json
{
  "name": "cmds",
  "description": "Utility commands for the cmds repo",
  "version": "0.1.0"
}
```

- [ ] **Step 3: Validate both files parse as JSON**

Run:

```
pwsh -NoProfile -Command "Get-Content .claude-plugin/marketplace.json -Raw | ConvertFrom-Json | Out-Null; Get-Content plugins/cmds/.claude-plugin/plugin.json -Raw | ConvertFrom-Json | Out-Null; Write-Output 'OK'"
```

Expected output: `OK` (no exceptions).

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/marketplace.json plugins/cmds/.claude-plugin/plugin.json
git commit -m "Add cmds Claude Code plugin marketplace manifest"
```

---

### Task 2: notifywhen-watch.ps1 watcher engine

**Files:**
- Create: `scripts/notifywhen-watch.ps1`

**Interfaces:**
- Consumes: a run directory containing `check.ps1` (contract: exit 0 = condition true) and `meta.json` (must contain at least `{"id": "<string>"}` before this script starts).
- Produces: updates `meta.json` with `status` (`"notified"` or `"notify-failed"`) and `chromePid`; writes `logs\notifywhen-<id>.log`; deletes the run directory after the kiosk window closes (or leaves it, with `status: "notify-failed"`, if Chrome can't be found).
- Invoked as: `pwsh -File scripts\notifywhen-watch.ps1 -RunDir <path> -IntervalSeconds <int>`

- [ ] **Step 1: Write the watcher engine script**

Create `scripts/notifywhen-watch.ps1`:

```powershell
# DESCRIPTION: Background watcher engine for notifywhen - polls a check script on an interval and shows a kiosk notification when it succeeds.
param(
    [Parameter(Mandatory = $true)][string]$RunDir,
    [Parameter(Mandatory = $true)][int]$IntervalSeconds
)

$ErrorActionPreference = 'Stop'

function Get-Meta {
    Get-Content -Raw -Path (Join-Path $RunDir 'meta.json') | ConvertFrom-Json
}

function Set-Meta($meta) {
    $meta | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $RunDir 'meta.json')
}

$id = (Get-Meta).id
$repoRoot = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $repoRoot 'logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$logFile = Join-Path $logDir "notifywhen-$id.log"

function Write-Log([string]$msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Add-Content -Path $logFile -Value $line
}

$checkScript = Join-Path $RunDir 'check.ps1'
Write-Log "watcher started, interval=${IntervalSeconds}s, checkScript=$checkScript"

while ($true) {
    $conditionMet = $false
    try {
        & pwsh -NoProfile -File $checkScript
        if ($LASTEXITCODE -eq 0) { $conditionMet = $true }
        Write-Log "check exit code: $LASTEXITCODE"
    } catch {
        Write-Log "check errored: $($_.Exception.Message)"
    }

    if ($conditionMet) { break }
    Start-Sleep -Seconds $IntervalSeconds
}

Write-Log "condition met, launching kiosk notification"

$chromeCmd = Get-Command chrome -ErrorAction SilentlyContinue
if ($chromeCmd) {
    $chromePath = $chromeCmd.Source
} else {
    $candidates = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
    )
    $chromePath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if (-not $chromePath) {
    Write-Log "ERROR: chrome.exe not found on PATH or in common install locations"
    $meta = Get-Meta
    $meta.status = 'notify-failed'
    Set-Meta $meta
    exit 1
}

$htmlPath = Join-Path $RunDir 'notify.html'
$fileUrl = 'file:///' + ($htmlPath -replace '\\', '/')
$profileDir = Join-Path $RunDir 'chrome-profile'

$chromeProc = Start-Process -FilePath $chromePath -ArgumentList @(
    '--kiosk',
    '--new-window',
    "--user-data-dir=$profileDir",
    $fileUrl
) -PassThru

$meta = Get-Meta
$meta.status = 'notified'
$meta.chromePid = $chromeProc.Id
Set-Meta $meta
Write-Log "chrome launched, pid=$($chromeProc.Id)"

$chromeProc.WaitForExit()
Write-Log "chrome window closed, cleaning up $RunDir"

Remove-Item -Path $RunDir -Recurse -Force
Write-Log "cleanup complete, exiting"
```

- [ ] **Step 2: Manually verify the polling + immediate-fire path**

Run (creates a synthetic always-true condition and exercises the whole engine):

```
pwsh -NoProfile -Command "
  $runDir = Join-Path $env:TEMP 'cmds-notifywhen\test-run-1'
  New-Item -ItemType Directory -Path $runDir -Force | Out-Null
  Set-Content -Path (Join-Path $runDir 'check.ps1') -Value 'exit 0'
  Set-Content -Path (Join-Path $runDir 'notify.html') -Value '<html><body><h1>test</h1></body></html>'
  @{ id = 'test-run-1'; status = 'polling'; watcherPid = $null; chromePid = $null } | ConvertTo-Json | Set-Content -Path (Join-Path $runDir 'meta.json')
  Start-Process pwsh -ArgumentList @('-NoProfile','-File','scripts\notifywhen-watch.ps1','-RunDir',$runDir,'-IntervalSeconds','2') -WindowStyle Hidden -PassThru | Select-Object -ExpandProperty Id
"
```

Expected: a Chrome kiosk window opens showing "test" within a couple seconds. Note the printed watcher PID and inspect `meta.json` in the run dir (`Get-Content $env:TEMP\cmds-notifywhen\test-run-1\meta.json`) — expect `status: "notified"` and a numeric `chromePid`.

- [ ] **Step 3: Manually verify cleanup happens only after the window closes, not before**

While the kiosk window from Step 2 is still open, run:

```
pwsh -NoProfile -Command "Test-Path (Join-Path $env:TEMP 'cmds-notifywhen\test-run-1')"
```

Expected: `True` (run dir still present because the window hasn't closed yet).

Then simulate the user closing the window by stopping the Chrome process recorded in `meta.json`:

```
pwsh -NoProfile -Command "
  $meta = Get-Content -Raw (Join-Path $env:TEMP 'cmds-notifywhen\test-run-1\meta.json') | ConvertFrom-Json
  Stop-Process -Id $meta.chromePid -Force
  Start-Sleep -Seconds 2
  Test-Path (Join-Path $env:TEMP 'cmds-notifywhen\test-run-1')
"
```

Expected: `False` — the watcher's `WaitForExit()` unblocked and it deleted the run dir. Also check `logs\notifywhen-test-run-1.log` exists and contains lines for "watcher started", "condition met", "chrome launched", and "cleanup complete".

- [ ] **Step 4: Manually verify the polling loop actually waits (doesn't fire immediately)**

```
pwsh -NoProfile -Command "
  $runDir = Join-Path $env:TEMP 'cmds-notifywhen\test-run-2'
  New-Item -ItemType Directory -Path $runDir -Force | Out-Null
  Set-Content -Path (Join-Path $runDir 'check.ps1') -Value 'exit 1'
  Set-Content -Path (Join-Path $runDir 'notify.html') -Value '<html><body>never</body></html>'
  @{ id = 'test-run-2'; status = 'polling'; watcherPid = $null; chromePid = $null } | ConvertTo-Json | Set-Content -Path (Join-Path $runDir 'meta.json')
  $p = Start-Process pwsh -ArgumentList @('-NoProfile','-File','scripts\notifywhen-watch.ps1','-RunDir',$runDir,'-IntervalSeconds','3') -WindowStyle Hidden -PassThru
  Start-Sleep -Seconds 5
  Get-Content (Join-Path (Split-Path -Parent (Get-Location)) 'logs\notifywhen-test-run-2.log') -ErrorAction SilentlyContinue
  Stop-Process -Id $p.Id -Force
  Remove-Item -Path $runDir -Recurse -Force
"
```

Expected: log shows at least one "check exit code: 1" line and no "condition met" line, confirming the loop polls and waits rather than firing on a false condition. Cleanup here is manual (`Stop-Process` + `Remove-Item`) since the condition never became true.

- [ ] **Step 5: Commit**

```bash
git add scripts/notifywhen-watch.ps1
git commit -m "Add notifywhen background watcher engine"
```

---

### Task 3: notifywhen command

**Files:**
- Create: `plugins/cmds/commands/notifywhen.md`

**Interfaces:**
- Consumes: `scripts\notifywhen-watch.ps1 -RunDir <path> -IntervalSeconds <int>` (Task 2).
- Produces: for later tasks, the `meta.json` shape `{ id, condition, url, message, intervalSeconds, startedAt, status, watcherPid, chromePid }` under `%TEMP%\cmds-notifywhen\<id>\`, which Tasks 4 and 5 read/act on.
- Invoked by the user as: `/cmds:notifywhen "<condition>" "<url>" "<message>" ["<interval>"]`

- [ ] **Step 1: Write the command file**

Create `plugins/cmds/commands/notifywhen.md`:

````markdown
---
description: Poll a natural-language condition against a URL and show a kiosk Chrome notification when it becomes true
argument-hint: "<condition>" "<url>" "<message>" ["<interval, default 5m>"]
---

You are implementing the `/cmds:notifywhen` command. Arguments (positional):
- `$1` = condition, natural language (e.g. "has more than 1 approval", "after 8pm")
- `$2` = url the condition is about
- `$3` = message to show in the kiosk notification
- `$4` = optional interval, e.g. `30s`, `5m`, `1h` (default `5m` if omitted)

Do the following using the PowerShell tool, in order:

1. **Generate a run id and run directory.**

   ```powershell
   $id = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + -join ((1..4) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
   $runDir = Join-Path $env:TEMP "cmds-notifywhen\$id"
   New-Item -ItemType Directory -Path $runDir -Force | Out-Null
   ```

2. **Parse the interval** (default 300 seconds if `$4` is absent). Accept `<number>s`, `<number>m`, `<number>h` suffixes and convert to seconds.

3. **Write `check.ps1` into `$runDir`, tailored to the condition text and URL.** The script's only contract: `exit 0` when true, non-zero otherwise, and never throw uncaught (catch network errors and treat as "not yet true"). Pick the closest pattern:

   - **GitHub PR/issue condition** (url matches `github.com/.../pull/N` or `.../issues/N`, and condition mentions approvals/reviews/merged/checks) — use the `gh` CLI, e.g. for an approval-count condition:

     ```powershell
     $prUrl = 'https://github.com/OWNER/REPO/pull/N'
     $requiredApprovals = 1  # "more than 1 approval" means > 1, i.e. count must exceed this
     try {
       $reviews = gh pr view $prUrl --json reviews | ConvertFrom-Json
       $approvalCount = ($reviews.reviews | Where-Object { $_.state -eq 'APPROVED' }).Count
       if ($approvalCount -gt $requiredApprovals) { exit 0 } else { exit 1 }
     } catch {
       exit 1
     }
     ```

     Adapt the field/condition (`--json reviews` for approvals, `gh pr checks` for CI status, `gh pr view --json state` for merged) to what the condition text actually asks for, filling in the real URL and threshold — never leave placeholder values in the generated script.

   - **Time/date condition** (e.g. "after 8pm", "on 2026-10-01") — no network call needed:

     ```powershell
     $target = Get-Date -Hour 20 -Minute 0 -Second 0
     if ((Get-Date) -ge $target) { exit 0 } else { exit 1 }
     ```

     Compute `$target` from the actual condition text (specific date, specific time, etc).

   - **Anything else** — generic fallback that fetches the URL and text-matches key terms extracted from the condition:

     ```powershell
     $url = 'https://example.com/status'
     $searchText = 'Completed'
     try {
       $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15
       if ($resp.Content -match [regex]::Escape($searchText)) { exit 0 } else { exit 1 }
     } catch {
       exit 1
     }
     ```

4. **Write `notify.html` into `$runDir`.** Static HTML/CSS only, no external requests. It must render the literal message text and the URL as a clickable link, and mention that Alt+F4 closes the kiosk window. Example to adapt (substitute the real message and url):

   ```html
   <!doctype html>
   <html>
   <head>
   <meta charset="utf-8">
   <title>notifywhen</title>
   <style>
     body { display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; font-family: system-ui, sans-serif; background: #1e1e2e; color: #f5f5f5; text-align: center; }
     .card { max-width: 32rem; padding: 2rem; }
     h1 { font-size: 1.75rem; margin-bottom: 1rem; }
     a { color: #8ab4f8; font-size: 1.1rem; word-break: break-all; }
     p.hint { margin-top: 2rem; opacity: 0.6; font-size: 0.9rem; }
   </style>
   </head>
   <body>
     <div class="card">
       <h1>MESSAGE_TEXT_HERE</h1>
       <a href="URL_HERE">URL_HERE</a>
       <p class="hint">Press Alt+F4 to close this window.</p>
     </div>
   </body>
   </html>
   ```

5. **Write `meta.json` into `$runDir`:**

   ```powershell
   $meta = @{
     id = $id
     condition = '<the condition text>'
     url = '<the url>'
     message = '<the message text>'
     intervalSeconds = <parsed interval seconds>
     startedAt = (Get-Date).ToString('o')
     status = 'polling'
     watcherPid = $null
     chromePid = $null
   }
   $meta | ConvertTo-Json | Set-Content -Path (Join-Path $runDir 'meta.json')
   ```

6. **Launch the watcher engine detached and hidden**, then record its PID back into `meta.json`:

   ```powershell
   $watcherProc = Start-Process pwsh -ArgumentList @(
     '-NoProfile', '-File', (Join-Path (Get-Location) 'scripts\notifywhen-watch.ps1'),
     '-RunDir', $runDir,
     '-IntervalSeconds', $intervalSeconds
   ) -WindowStyle Hidden -PassThru

   $meta = Get-Content -Raw (Join-Path $runDir 'meta.json') | ConvertFrom-Json
   $meta.watcherPid = $watcherProc.Id
   $meta | ConvertTo-Json | Set-Content -Path (Join-Path $runDir 'meta.json')
   ```

7. **Report back to the user**: the run id, the watcher PID, the log file path (`logs\notifywhen-<id>.log`), and remind them they can check status with `/cmds:notifywhen-list` or cancel with `/cmds:notifywhen-stop "<id>"`.
````

- [ ] **Step 2: Commit**

```bash
git add plugins/cmds/commands/notifywhen.md
git commit -m "Add /cmds:notifywhen command"
```

---

### Task 4: notifywhen-list command

**Files:**
- Create: `plugins/cmds/commands/notifywhen-list.md`

**Interfaces:**
- Consumes: `meta.json` shape from Task 3 (`id, condition, url, message, intervalSeconds, startedAt, status, watcherPid, chromePid`) under `%TEMP%\cmds-notifywhen\*\`.

- [ ] **Step 1: Write the command file**

Create `plugins/cmds/commands/notifywhen-list.md`:

````markdown
---
description: List active notifywhen watchers
---

Run this with the PowerShell tool and show the resulting table (or "No active notifywhen watchers.") to the user as your response:

```powershell
$runRoot = Join-Path $env:TEMP 'cmds-notifywhen'
$rows = @()
if (Test-Path $runRoot) {
    Get-ChildItem -Path $runRoot -Directory | ForEach-Object {
        $metaPath = Join-Path $_.FullName 'meta.json'
        if (Test-Path $metaPath) {
            $meta = Get-Content -Raw -Path $metaPath | ConvertFrom-Json
            $pidToCheck = if ($meta.status -eq 'notified') { $meta.chromePid } else { $meta.watcherPid }
            $alive = $false
            if ($pidToCheck) {
                $proc = Get-Process -Id $pidToCheck -ErrorAction SilentlyContinue
                if ($proc) { $alive = $true }
            }
            if ($alive) {
                $rows += [pscustomobject]@{
                    Id = $meta.id
                    Status = $meta.status
                    Condition = $meta.condition
                    Url = $meta.url
                    Started = $meta.startedAt
                }
            } else {
                Remove-Item -Path $_.FullName -Recurse -Force
            }
        }
    }
}
if ($rows.Count -eq 0) {
    Write-Output 'No active notifywhen watchers.'
} else {
    $rows | Format-Table -AutoSize | Out-String | Write-Output
}
```
````

- [ ] **Step 2: Manually verify against the leftover test run dir**

If Task 2's `test-run-1`/`test-run-2` dirs were cleaned up already, create a fresh synthetic entry to verify list behavior:

```
pwsh -NoProfile -Command "
  $runDir = Join-Path $env:TEMP 'cmds-notifywhen\list-test'
  New-Item -ItemType Directory -Path $runDir -Force | Out-Null
  @{ id = 'list-test'; condition = 'test condition'; url = 'https://example.com'; message = 'hi'; intervalSeconds = 60; startedAt = (Get-Date).ToString('o'); status = 'polling'; watcherPid = $PID; chromePid = $null } | ConvertTo-Json | Set-Content -Path (Join-Path $runDir 'meta.json')
"
```

Then run the Step 1 script body directly in the terminal. Expected: a table row with `Id = list-test`, `Status = polling`, `Condition = test condition` (since `$PID`, this session's own process id, is alive). Clean up afterward: `Remove-Item -Recurse -Force (Join-Path $env:TEMP 'cmds-notifywhen\list-test')`.

- [ ] **Step 3: Commit**

```bash
git add plugins/cmds/commands/notifywhen-list.md
git commit -m "Add /cmds:notifywhen-list command"
```

---

### Task 5: notifywhen-stop command

**Files:**
- Create: `plugins/cmds/commands/notifywhen-stop.md`

**Interfaces:**
- Consumes: same `meta.json` shape as Task 4.
- Invoked by the user as: `/cmds:notifywhen-stop "<id-or-all>"` (`$1` = id or the literal string `all`).

- [ ] **Step 1: Write the command file**

Create `plugins/cmds/commands/notifywhen-stop.md`:

````markdown
---
description: Stop one or all active notifywhen watchers
argument-hint: "<id-or-'all'>"
---

`$1` is the watcher id to stop, or the literal string `all` to stop every active watcher.

Run this with the PowerShell tool (substitute the real value of `$1` for the `$target` assignment below), and report to the user which watcher(s) were stopped, or that none were found:

```powershell
$target = '<value of $1>'
$runRoot = Join-Path $env:TEMP 'cmds-notifywhen'
if (-not (Test-Path $runRoot)) {
    Write-Output 'No active notifywhen watchers.'
} else {
    $dirs = if ($target -eq 'all') {
        Get-ChildItem -Path $runRoot -Directory
    } else {
        Get-ChildItem -Path $runRoot -Directory | Where-Object { $_.Name -eq $target }
    }
    if (-not $dirs) {
        Write-Output "No watcher found with id '$target'."
    } else {
        foreach ($dir in $dirs) {
            $metaPath = Join-Path $dir.FullName 'meta.json'
            if (Test-Path $metaPath) {
                $meta = Get-Content -Raw -Path $metaPath | ConvertFrom-Json
                foreach ($pidProp in @('chromePid', 'watcherPid')) {
                    $pidVal = $meta.$pidProp
                    if ($pidVal) {
                        $proc = Get-Process -Id $pidVal -ErrorAction SilentlyContinue
                        if ($proc) { Stop-Process -Id $pidVal -Force }
                    }
                }
            }
            Remove-Item -Path $dir.FullName -Recurse -Force
            Write-Output "Stopped watcher '$($dir.Name)'."
        }
    }
}
```
````

- [ ] **Step 2: Manually verify stop cancels a live polling watcher**

```
pwsh -NoProfile -Command "
  $runDir = Join-Path $env:TEMP 'cmds-notifywhen\stop-test'
  New-Item -ItemType Directory -Path $runDir -Force | Out-Null
  Set-Content -Path (Join-Path $runDir 'check.ps1') -Value 'exit 1'
  Set-Content -Path (Join-Path $runDir 'notify.html') -Value '<html><body>never</body></html>'
  @{ id = 'stop-test'; status = 'polling'; watcherPid = $null; chromePid = $null } | ConvertTo-Json | Set-Content -Path (Join-Path $runDir 'meta.json')
  $p = Start-Process pwsh -ArgumentList @('-NoProfile','-File','scripts\notifywhen-watch.ps1','-RunDir',$runDir,'-IntervalSeconds','30') -WindowStyle Hidden -PassThru
  Start-Sleep -Seconds 2
  $meta = Get-Content -Raw (Join-Path $runDir 'meta.json') | ConvertFrom-Json
  $meta.watcherPid = $p.Id
  $meta | ConvertTo-Json | Set-Content -Path (Join-Path $runDir 'meta.json')
  Write-Output \"watcher pid: $($p.Id)\"
"
```

Then run the Step 1 script body with `$target = 'stop-test'`. Expected output: `Stopped watcher 'stop-test'.` Verify the watcher process is gone (`Get-Process -Id <pid> -ErrorAction SilentlyContinue` returns nothing) and the run dir no longer exists (`Test-Path $env:TEMP\cmds-notifywhen\stop-test` returns `False`).

- [ ] **Step 3: Commit**

```bash
git add plugins/cmds/commands/notifywhen-stop.md
git commit -m "Add /cmds:notifywhen-stop command"
```

---

### Task 6: Documentation

**Files:**
- Create: `plugins/README.md`
- Modify: `README.md` (insert a new section)

- [ ] **Step 1: Write plugins/README.md**

Create `plugins/README.md`:

```markdown
# Claude Code plugins

This repo publishes a Claude Code plugin marketplace named `cmds`.

## Installing

From within Claude Code:

```
/plugin marketplace add Nate314/cmds
/plugin install cmds@cmds
```

## Plugins

### cmds

Utility commands for the cmds repo.

#### `/cmds:notifywhen "<condition>" "<url>" "<message>" ["<interval>"]`

Polls a natural-language condition against a URL in the background (default
interval: 5 minutes) and, once it becomes true, pops a kiosk-mode Chrome
window showing your message with a clickable link to the URL. Runs
detached, so it survives closing the Claude Code session or terminal.

Example:

```
/cmds:notifywhen "https://github.com/Nate314/cmds/pull/1 has more than 1 approval" "https://github.com/Nate314/cmds/pull/1" "cmds#1 is approved!"
```

With a custom interval (checks every 30 seconds instead of the default 5
minutes):

```
/cmds:notifywhen "it's after 8pm" "https://example.com" "Time to stop working" "30s"
```

GitHub PR/issue conditions use the `gh` CLI; time/date conditions use the
local clock; anything else falls back to a plain text match against the
page content.

#### `/cmds:notifywhen-list`

Lists currently active watchers (still polling, or already showing a kiosk
notification waiting to be closed), with their id, status, condition, url,
and start time.

#### `/cmds:notifywhen-stop "<id-or-'all'>"`

Cancels one watcher by the id shown in `notifywhen-list`, or every active
watcher when passed `all`.
```

- [ ] **Step 2: Add a linking section to the root README.md**

Read `README.md` first, then insert a new `## Claude Code plugins` section right before the existing `## Claude Code status line` heading:

```markdown
## Claude Code plugins

This repo also publishes a Claude Code plugin marketplace — see
[`plugins/README.md`](plugins/README.md) for installation and the
`notifywhen` command family (background condition watcher with a kiosk
notification).

```

- [ ] **Step 3: Commit**

```bash
git add plugins/README.md README.md
git commit -m "Document the cmds Claude Code plugin marketplace"
```

---

### Task 7: End-to-end verification

**Files:** none (verification only).

- [ ] **Step 1: Install the marketplace and plugin locally**

In this Claude Code session (or ask the user to run it, since it's a
one-time local config change):

```
/plugin marketplace add C:\Users\Natha\cmds
/plugin install cmds@cmds
```

- [ ] **Step 2: Run a fast real end-to-end notifywhen**

Invoke:

```
/cmds:notifywhen "it's after $(future minute)" "https://github.com/Nate314/cmds" "notifywhen works!" "10s"
```

concretely, pick a target time about 30-60 seconds in the future so the wait is short, e.g. if it's currently 14:32, use a condition like "the current time is 14:33 or later".

- [ ] **Step 3: While it's polling, verify with notifywhen-list**

Run `/cmds:notifywhen-list` and confirm the new watcher appears with `status = polling` and the correct condition/url/message.

- [ ] **Step 4: Confirm the kiosk window actually appears with correct content**

This is a real OS-level Chrome window outside any tool's observable surface (not a tab the browser-automation tool controls, since it launches with its own isolated `--user-data-dir`) — ask the user to confirm visually that the kiosk window appeared with the right message and a working clickable link to the URL, per the repo's standing rule to verify interactive/UI behavior live rather than by code reading alone. Do not claim this step passed without that confirmation.

- [ ] **Step 5: Confirm cleanup after closing**

After the user closes the kiosk window (Alt+F4), run `/cmds:notifywhen-list` again and confirm the watcher no longer appears, then verify with PowerShell that its run directory is gone:

```
pwsh -NoProfile -Command "Test-Path (Join-Path $env:TEMP 'cmds-notifywhen') -PathType Container"
Get-ChildItem (Join-Path $env:TEMP 'cmds-notifywhen') -ErrorAction SilentlyContinue
```

Expected: the specific run dir for this test is gone (other unrelated dirs, if any, may remain).

- [ ] **Step 6: Verify notifywhen-stop against a second, still-polling watcher**

Start another one with a condition far in the future (so it never fires during this test):

```
/cmds:notifywhen "the year is 2099" "https://example.com" "should never fire" "60s"
```

Note its id from `/cmds:notifywhen-list`, then run `/cmds:notifywhen-stop "<that id>"` and confirm via `/cmds:notifywhen-list` that it's gone, and that its process was actually killed (no leftover `pwsh` process holding that run dir).

- [ ] **Step 7: Report results to the user**

Summarize what was verified and any deviations observed, per the repo's rule against claiming success without actually running the feature.

# notifywhen Claude Code plugin marketplace design

## Goal

Add a Claude Code plugin marketplace to this repo containing a `cmds` plugin
with a `notifywhen` command family. `/cmds:notifywhen` lets the user describe
a condition in natural language plus a URL; a detached background process
polls the condition on an interval and, once true, pops a kiosk-mode Chrome
window showing a message with a clickable link to the URL. Companion
`notifywhen-list` and `notifywhen-stop` commands let the user see and cancel
active watchers. The marketplace is structured so future commands/plugins can
be added without restructuring.

## Repo layout

```
.claude-plugin/
  marketplace.json              # marketplace manifest (name: "cmds")
plugins/
  README.md                     # marketplace + plugin/command docs, linked from root README
  cmds/
    .claude-plugin/
      plugin.json                # plugin manifest (name: "cmds")
    commands/
      notifywhen.md
      notifywhen-list.md
      notifywhen-stop.md
scripts/
  notifywhen-watch.ps1           # reusable watcher engine, checked into repo
```

Adding a new command later: drop another `.md` file into
`plugins/cmds/commands/`. Adding a new plugin later: new folder under
`plugins/`, plus one more entry in `marketplace.json`'s `plugins` array.

## marketplace.json

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

## plugins/cmds/.claude-plugin/plugin.json

```json
{
  "name": "cmds",
  "description": "Utility commands for the cmds repo",
  "version": "0.1.0"
}
```

Commands are auto-discovered from `commands/*.md`; no explicit listing
needed.

## Command frontmatter and argument convention

Each command file uses standard Claude Code slash-command frontmatter
(`description`, optional `argument-hint`) and reads its arguments via the
documented positional variables `$1`, `$2`, `$3`, `$4` (and `$ARGUMENTS` as
the raw joined string), consistent with existing Claude Code slash-command
behavior. No `arguments:` frontmatter array is used, to avoid relying on an
unconfirmed schema detail.

## Runtime state location

All per-watcher runtime artifacts live under:

```
%TEMP%\cmds-notifywhen\<id>\
  check.ps1        # generated, condition-specific check script
  notify.html       # generated notification page
  chrome-profile\   # isolated --user-data-dir for the kiosk window
  meta.json         # registry entry for list/stop
```

`<id>` is a short timestamp-based identifier (e.g.
`yyyyMMdd-HHmmss-<4 random hex chars>`) generated at invocation time. Nothing
under this tree is committed to the repo; it is created and torn down at
runtime. Log output goes to the repo's existing `logs/` directory (already
gitignored) as `logs\notifywhen-<id>.log`.

## `/cmds:notifywhen "<condition>" "<url>" "<message>" ["<interval>"]`

Behavior of the command prompt, executed by the live Claude session:

1. Parse `$1` condition, `$2` url, `$3` message, optional `$4` interval
   (default `5m`; accepts forms like `30s`, `5m`, `1h`).
2. Generate `<id>` and create `%TEMP%\cmds-notifywhen\<id>\`.
3. Write `check.ps1`, a script tailored to the condition text and URL:
   - GitHub PR/issue URL + approval/review/merge/check-status wording →
     use `gh pr view <url> --json ...` / `gh pr checks <url>` via the `gh`
     CLI (preferred per user direction over any GitHub MCP).
   - Time-of-day / date wording ("after 8pm", "on 2026-10-01") → a
     `Get-Date` comparison, no network call needed.
   - Anything else → a generic fallback that fetches the URL
     (`Invoke-WebRequest`) and text-matches against key terms extracted from
     the condition.
   - Contract: `check.ps1` exits `0` when the condition is currently true,
     non-zero otherwise. It must not throw on transient network errors -
     treat those as "not yet true" (exit non-zero) so a flaky fetch doesn't
     kill the watcher.
4. Write `notify.html`: centered layout, the literal message text, and the
   URL rendered as a clickable `<a href>` link. Plain static HTML/CSS, no
   external requests (matches repo's dependency-free convention). Include a
   small hint that Alt+F4 closes the kiosk window.
5. Write initial `meta.json`:
   ```json
   {
     "id": "<id>",
     "condition": "<condition>",
     "url": "<url>",
     "message": "<message>",
     "intervalSeconds": <n>,
     "startedAt": "<ISO8601>",
     "status": "polling",
     "watcherPid": null,
     "chromePid": null
   }
   ```
6. Launch `scripts\notifywhen-watch.ps1` detached and hidden via
   `Start-Process pwsh -ArgumentList @('-File', <path>, '-RunDir', <dir>,
   '-IntervalSeconds', <n>) -WindowStyle Hidden -PassThru`, capturing the
   resulting PID and writing it into `meta.json` as `watcherPid` before the
   command finishes.
7. Report back to the user: the id, log file path, and how to check status
   (`/cmds:notifywhen-list`) or cancel (`/cmds:notifywhen-stop "<id>"`).

## scripts/notifywhen-watch.ps1

Parameters: `-RunDir <path>` (contains `check.ps1`, `notify.html`,
`meta.json`), `-IntervalSeconds <int>`.

Loop:

1. Run `check.ps1`. On exit code `0`, break out of the loop.
2. Otherwise `Start-Sleep -Seconds $IntervalSeconds` and repeat.
3. Append a timestamped line to `logs\notifywhen-<id>.log` on each poll
   (result + any stderr) for debuggability.

On condition true:

1. Launch Chrome as an isolated process so window-close is reliably
   detectable (a plain `chrome.exe --kiosk` handoff to an already-running
   Chrome instance would exit immediately and not reflect the real window):
   ```powershell
   Start-Process chrome -ArgumentList @(
     '--kiosk', '--new-window',
     "--user-data-dir=$RunDir\chrome-profile",
     "file:///$($RunDir -replace '\\','/')/notify.html"
   ) -PassThru
   ```
2. Update `meta.json`: `status = "notified"`, `chromePid = <that PID>`.
3. `$chromeProc.WaitForExit()` — blocks until the user closes the kiosk
   window.
4. Delete `$RunDir` recursively (check.ps1, notify.html, chrome-profile,
   meta.json all removed together). Leave the log file in `logs\` for
   later inspection.
5. Exit.

If `chrome` isn't resolvable on PATH, fall back to the common install path
`${env:ProgramFiles}\Google\Chrome\Application\chrome.exe`, then
`${env:ProgramFiles(x86)}\...`; if none exist, log an error to the log file,
leave `meta.json` status as `"notify-failed"`, and exit without deleting the
run dir (so `notifywhen-list`/`-stop` can still surface and clean it up).

## `/cmds:notifywhen-list`

1. Enumerate `%TEMP%\cmds-notifywhen\*\meta.json`.
2. For each, check whether the relevant PID (`chromePid` if `status =
   notified`, else `watcherPid`) is still a live process
   (`Get-Process -Id ... -ErrorAction SilentlyContinue`).
   - Alive: include in output table (id, condition, url, status, started).
   - Not alive: treat as stale, delete the leftover run dir, skip it in
     output.
3. Print the table (or "no active watchers").

## `/cmds:notifywhen-stop "<id-or-all>"`

1. Resolve target run dir(s): a specific `<id>` under
   `%TEMP%\cmds-notifywhen\`, or all of them when the argument is `all`.
2. For each: read `meta.json`. If `chromePid` set and alive, `Stop-Process`
   it. If `watcherPid` alive, `Stop-Process` it. Then delete the run dir.
3. Report what was stopped (or "not found" for an unknown id).

## Docs

- `plugins/README.md`: what this marketplace is, `/plugin marketplace add
  Nate314/cmds` + `/plugin install cmds@cmds` install steps, and usage/
  examples for all three commands (mirrors the example in the original
  request: `/cmds:notifywhen "https://github.com/Nate314/cmds/pull/1 has
  more than 1 approval" "https://github.com/Nate314/cmds/pull/1" "cmds#1 is
  approved!"`).
- Root `README.md`: short new "Claude Code plugins" section pointing at
  `plugins/README.md`, matching the existing doc style/tone.

## Testing

- `pwsh -File scripts\notifywhen-watch.ps1` exercised directly with a
  synthetic always-true `check.ps1` to confirm the kiosk window opens with
  correct content and the run dir is deleted only after the window is
  closed (verify at default and a resized window).
- Full `/cmds:notifywhen` invocation with a cheap, fast condition (e.g. a
  time a couple minutes in the future) run end-to-end, confirming detach
  survives the command finishing, `notifywhen-list` shows it while polling,
  `notifywhen-stop` cancels a separate run, and the kiosk fires and cleans
  up correctly for the one left running.
- Confirms per repo CLAUDE.md: no claiming success without actually
  launching and observing the kiosk window.

## Out of scope (YAGNI)

- No scheduled-task-based persistence across reboots.
- No repeat/recurring notifications after first fire.
- No generic LLM-per-poll condition evaluation (explicitly deferred per
  user direction: prefer `gh` CLI/native checks; only a plain text-match
  fallback for anything else).

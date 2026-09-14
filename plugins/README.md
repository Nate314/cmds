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

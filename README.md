# status-bar-claude

A shell script that renders a real-time Claude Code status line in your terminal.

> Fork of [VCoder4646/status-bar-claude](https://github.com/VCoder4646/status-bar-claude),
> adding session/API timing, context token counts, a live clock, rate-limit
> countdowns, 1-second refresh, and a `curl | bash` installer.

![Status bar screenshot](screenshot.png)

### Status bar elements

```
myproj ⎇ main ● ↑2 │ Opus 5 * medium │ Tst 2m api 1m │ 🕐 5:51pm │ ctx ▉░░░ 4% 40k/1.0M │ 5h ▉▉▊░ 35% ↻ 2h18m (8:10pm) │ 7d ▉░░░ 14% ↻ 6d8h
│        │    │ │    │      │ │            │      │       │                 │  │                  │     │     │                  │     │
│        │    │ │    │      │ │            │      │       │                 │  │                  │     │     │                  │     └─ countdown to 7-day reset
│        │    │ │    │      │ │            │      │       │                 │  │                  │     │     │                  └─ 7-day usage
│        │    │ │    │      │ │            │      │       │                 │  │                  │     │     └─ absolute 5-hour reset time
│        │    │ │    │      │ │            │      │       │                 │  │                  │     └─ countdown to 5-hour reset
│        │    │ │    │      │ │            │      │       │                 │  │                  └─ 5-hour usage
│        │    │ │    │      │ │            │      │       │                 │  └─ tokens used / context window size
│        │    │ │    │      │ │            │      │       │                 └─ context window usage
│        │    │ │    │      │ │            │      │       └─ current wall-clock time
│        │    │ │    │      │ │            │      └─ time spent in API calls
│        │    │ │    │      │ │            └─ total session duration
│        │    │ │    │      │ └─ reasoning effort
│        │    │ │    │      └─ thinking indicator
│        │    │ │    └─ model name
│        │    │ └─ ahead/behind upstream
│        │    └─ uncommitted changes
│        └─ git branch (omitted if not in a repo)
└─ current working directory
```

**Bar colors:** cyan → yellow (50%) → red (75%) → bold red (90%)

**Countdown colors** shift the same way as the remaining window shrinks.

**Rate-limit segments** (`5h`, `7d`, resets) appear only when Claude Code
supplies rate-limit data (Claude.ai Pro/Max).

**Adaptive width:** the line is rendered at progressively more compact detail
levels to fit the terminal — bars shrink, then the absolute reset time, the
7-day segment, timings, and finally the model name drop out. Set
`CLAUDE_STATUSLINE_PAD` (default `4`) to reserve extra trailing columns.

**Shared cache:** values are cached under
`${XDG_CACHE_HOME:-~/.cache}/claude-statusline` with a 2s TTL, so all open
windows converge on the same numbers. Writes merge over the cached values, so a
render arriving without rate-limit or model data never blanks those segments.

## Requirements

- `bash`
- `jq`
- `git`
- Node 14+ (only for the `npx` install route)

## Installation

### npx (no clone, no install)

```bash
npx status-bar-claude
```

Fetches the package, installs the status line into `~/.claude/`, and exits.
Requires Node 14+ alongside the usual `bash`, `jq`, and `git`. On Windows, run
it inside WSL or Git Bash — the status line itself is a bash script.

### curl one-liner

```bash
curl -fsSL https://raw.githubusercontent.com/Tarakesh-sampath/status-bar-claude/main/install.sh | bash
```

The installer downloads `statusline-command.sh` straight from the repo when it
is run outside a checkout, verifies it is non-empty and passes `bash -n`, then
installs it. Override the source with `STATUSLINE_REPO`, `STATUSLINE_BRANCH`,
or `STATUSLINE_URL`:

```bash
curl -fsSL https://raw.githubusercontent.com/Tarakesh-sampath/status-bar-claude/main/install.sh \
  | STATUSLINE_BRANCH=dev bash
```

### Permissions

The install itself needs **no root** — it only writes `~/.claude/`. Root comes
up in one case: a missing `bash`, `jq`, or `git`, which the installer offers to
install through your package manager and therefore runs under `sudo`.

Because `curl … | bash` hands the script to bash on stdin, `sudo` cannot read a
password there; it falls back to `/dev/tty`. The installer checks for this up
front and, when it cannot escalate (no `sudo`, no tty, no package manager), it
stops with the exact command to run instead of hanging on an invisible prompt.

To keep it entirely out of `sudo`, install the three dependencies first — or
set `STATUSLINE_SKIP_DEPS=1` to skip the check:

```bash
curl -fsSL https://raw.githubusercontent.com/Tarakesh-sampath/status-bar-claude/main/install.sh \
  | STATUSLINE_SKIP_DEPS=1 bash
```

Without `jq`, the installer still writes `~/.claude/settings.json` when there is
nothing to preserve; if that file already has content it refuses to clobber it
and prints the block to paste in by hand.

### From a clone

```bash
git clone https://github.com/Tarakesh-sampath/status-bar-claude.git
cd status-bar-claude
./install.sh
```

This copies `statusline-command.sh` to `~/.claude/` and patches
`~/.claude/settings.json` with the required `statusLine` config. Restart Claude
Code afterward.

### Manual installation

#### 1. Copy the script to your Claude config directory

```bash
cp statusline-command.sh ~/.claude/statusline-command.sh
chmod +x ~/.claude/statusline-command.sh
```

#### 2. Configure Claude Code

In `~/.claude/settings.json`, add:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-command.sh",
    "refreshInterval": 1
  }
}
```

The script reads JSON from stdin (provided by Claude Code) and prints a colored
status string to stdout. You can exercise it by hand:

```bash
echo '{"model":{"display_name":"Opus 5"},"workspace":{"current_dir":"'"$PWD"'"},
"cost":{"total_duration_ms":123456,"total_api_duration_ms":45678}}' \
  | bash statusline-command.sh
```

## License

MIT — see [LICENSE](LICENSE).

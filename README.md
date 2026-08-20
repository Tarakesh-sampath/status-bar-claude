# status-bar-claude

A shell script that renders a real-time Claude Code status line in your terminal.

![Status bar screenshot](screenshot.png)

### Status bar elements

```
Project   develop   Sonnet 4.6   ctx ▊▊▊▊▊▊▊▊ 60%   5h ▊▊▊▊▊▊▊▊ 9%   7d ▊▊▊▊▊▊▊▊ 26%   reset 8pm
  │          │           │             │                    │                  │              │
  │          │           │             │                    │                  │              └─ 5-hour reset time
  │          │           │             │                    │                  └─ 7-day token usage
  │          │           │             │                    └─ 5-hour token usage
  │          │           │             └─ Context window usage
  │          │           └─ Model name
  │          └─ Git branch (omitted if not in a repo)
  └─ Current working directory
```

**Bar colors:** cyan → yellow (50%) → red (75%) → bold red (90%)

**Reset time:** shown when the 5-hour rate limit data is available (Claude.ai Pro/Max).

## Requirements

- `bash`
- `jq`
- `git`

## Installation

### One-liner (no clone needed)

```bash
curl -fsSL https://raw.githubusercontent.com/Tarakesh-sampath/status-bar-claude/main/install.sh | bash
```

The installer downloads `statusline-command.sh` straight from the repo when it
is run outside a checkout. Override the source with `STATUSLINE_REPO` /
`STATUSLINE_BRANCH`:

```bash
curl -fsSL https://raw.githubusercontent.com/Tarakesh-sampath/status-bar-claude/main/install.sh \
  | STATUSLINE_BRANCH=dev bash
```

### From a clone

```bash
./install.sh
```

This copies `statusline-command.sh` to `~/.claude/` and patches `~/.claude/settings.json` with the required `statusLine` config. Restart Claude Code afterward.

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

The script reads JSON from stdin (provided by Claude Code) and prints a colored status string to stdout.

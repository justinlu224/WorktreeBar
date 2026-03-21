# WorktreeBar

> **Note:** This project is under active development. Features and APIs may change.

A macOS menu bar app for managing git worktrees and monitoring Claude Code session status.

## Features

- **Menu bar resident** — Lives in the menu bar (no Dock icon). Click the branch icon to open the panel.
- **Worktree overview** — Shows all worktrees with branch name, dirty/clean status, ahead/behind counts, and last commit time.
- **Claude Code status monitoring** — Real-time Claude session status per worktree (active / tool running / waiting for permission / idle / ended), color-coded with distinct icons.
- **Menu bar badge** — Shows active Claude counts next to the icon (e.g. `1⚠ 2↑ 1!`). Permission requests are most prominent.
- **macOS notifications** — Desktop notifications when Claude finishes, needs permission, or session ends. One-click open Terminal from notification.
- **Quick actions** — Open Terminal or Android Studio at any worktree path with one click.
- **Create/remove worktrees** — Manage worktrees directly from the app.
- **Smart sorting** — Permission requests first, then active/running, then by last commit time. Main repo always last.
- **Auto refresh** — Git status updates every 30s. Claude status updates instantly via filesystem monitoring.

## Claude Status Detection

The `worktreebar-hook.sh` script integrates with Claude Code hooks to write status files to `~/.worktreebar-claude-status/`. The app monitors this directory and maps hook events to 6 states:

| Status | Color | Icon | Condition |
|--------|-------|------|-----------|
| Active | Green | `bolt.fill` | PostToolUse / Notification events, within 30s |
| Tool Running | Blue | `gearshape.fill` | PreToolUse event, within 120s (tools like Bash can run long) |
| Waiting Permission | Red | `exclamationmark.circle.fill` | PermissionRequest event (persists until next event) |
| Idle | Orange | `pause.circle.fill` | Active/running timed out, or Stop event with process still alive |
| Ended | Gray | `checkmark.circle` | Stop event and Claude process is gone |
| None | — | — | No status file, or stale file cleaned up (>60s, process gone) |

**Sort priority:** Waiting Permission > Active > Tool Running > Idle > Ended > None

**Menu bar badge format:**
- `1⚠` — 1 waiting for permission (most prominent)
- `2↑` — 2 worktrees with Claude active/running
- `1!` — 1 worktree with Claude idle
- `1⚠ 2↑ 1!` — mixed states

**Notification triggers (on transition from active/running):**
- → Idle: "Claude finished"
- → Waiting Permission: "Claude needs permission"
- → Ended: "Claude session ended"

## Requirements

- macOS 14 (Sonoma) or later
- Xcode Command Line Tools (`xcode-select --install`)
- Git

## Getting Started

### Step 1: Build

```bash
cd ~/WorktreeBar
./build-app.sh
```

Wait for `Done! App bundle created` — takes about 30s to 1 min.

### Step 2: Launch

```bash
open ~/WorktreeBar/WorktreeBar.app
```

> **Note:** You must launch via `open WorktreeBar.app` (not the binary directly) — notifications require the app bundle's Bundle Identifier.

### Step 3: Select Repository

Click the branch icon in the menu bar. On first launch, select your git repository folder.

### Step 4: Configure Claude Code Hook

Add to `~/.claude/hooks.json` (or merge with existing config):

```json
{
  "hooks": {
    "PreToolUse": [{ "command": "~/WorktreeBar/worktreebar-hook.sh PreToolUse" }],
    "PostToolUse": [{ "command": "~/WorktreeBar/worktreebar-hook.sh PostToolUse" }],
    "Notification": [{ "command": "~/WorktreeBar/worktreebar-hook.sh Notification" }],
    "PermissionRequest": [{ "command": "~/WorktreeBar/worktreebar-hook.sh PermissionRequest" }],
    "Stop": [{ "command": "~/WorktreeBar/worktreebar-hook.sh Stop" }]
  }
}
```

### (Optional) Launch at Login

System Settings → General → Login Items → add `WorktreeBar.app`.

### Rebuild After Changes

```bash
cd ~/WorktreeBar
./build-app.sh
open WorktreeBar.app
```

## Project Structure

```
WorktreeBar/
├── Package.swift              # Swift Package Manager config
├── build-app.sh               # Build + bundle script (produces .app)
├── worktreebar-hook.sh        # Claude Code hook — writes status files
├── LICENSE                    # MIT License
└── WorktreeBar/               # Source code
    ├── WorktreeBarApp.swift   # @main AppDelegate, NSStatusItem + NSPopover
    ├── AppState.swift         # ViewModel — state management, Claude monitoring, refresh
    ├── GitService.swift       # Git commands, output parsing, Claude status detection
    ├── NotificationManager.swift # macOS notifications (UNUserNotificationCenter)
    ├── Models.swift           # Worktree and ClaudeStatus data models
    ├── WorktreeListView.swift # Main panel UI
    ├── WorktreeRow.swift      # Individual worktree row UI
    └── CreateWorktreeView.swift # Create worktree sheet
```

## Data Storage

- **Repo path** — macOS UserDefaults. Change via the gear menu.
- **Claude status** — `~/.worktreebar-claude-status/*.json`, written by the hook, monitored by the app in real time.

## Architecture

- **AppKit NSStatusItem + NSPopover** — Used instead of SwiftUI MenuBarExtra for reliable badge updates.
- **NSHostingController** — Hosts SwiftUI views inside the NSPopover.
- **Combine** — Subscribes to AppState changes to drive badge updates.
- **DispatchSource** — Monitors `~/.worktreebar-claude-status/` directory for instant Claude status detection.
- **SwiftUI** — All panel UI (WorktreeListView, WorktreeRow, CreateWorktreeView).

## Uninstall

1. Quit WorktreeBar (click menu bar icon → Quit)
2. Remove the app folder:
   ```bash
   rm -rf ~/WorktreeBar
   ```
3. Remove Claude Code hooks — delete the `worktreebar-hook.sh` entries from `~/.claude/settings.json` (or `~/.claude/hooks.json`)
4. Remove status data:
   ```bash
   rm -rf ~/.worktreebar-claude-status
   ```
5. Remove saved preferences:
   ```bash
   defaults delete com.personal.WorktreeBar
   ```
6. If added to Login Items: System Settings → General → Login Items → remove WorktreeBar

## License

MIT

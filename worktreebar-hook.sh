#!/bin/bash
# WorktreeBar Claude Hook
# Writes status to ~/.worktreebar-claude-status/<encoded-path>.json
# Usage: worktreebar-hook.sh <event_name>
# Event name is passed as CLI argument (not stdin) to avoid stdin contention
# with other hooks that run before this one.

STATUS_DIR="$HOME/.worktreebar-claude-status"
mkdir -p "$STATUS_DIR"

HOOK_EVENT="${1:-unknown}"

# Encode cwd as status filename
ENCODED=$(echo "$PWD" | tr '/.' '--')
STATUS_FILE="$STATUS_DIR/${ENCODED}.json"

# Get branch name for display
BRANCH=$(git -C "$PWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

# Don't let Notification overwrite PermissionRequest (Claude fires Notification
# while still waiting for permission, which would incorrectly clear the waiting state)
if [ "$HOOK_EVENT" = "Notification" ] && [ -f "$STATUS_FILE" ]; then
    if grep -q '"event":"PermissionRequest"' "$STATUS_FILE" 2>/dev/null; then
        exit 0
    fi
fi

# Determine status
case "$HOOK_EVENT" in
    "Stop")  STATUS="idle" ;;
    *)       STATUS="active" ;;
esac

# Write status file atomically
TMP_FILE=$(mktemp "$STATUS_DIR/.tmp.XXXXXX")
cat > "$TMP_FILE" << EOF
{"status":"${STATUS}","path":"${PWD}","branch":"${BRANCH}","time":$(date +%s),"event":"${HOOK_EVENT}"}
EOF
mv "$TMP_FILE" "$STATUS_FILE"

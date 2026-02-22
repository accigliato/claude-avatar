#!/bin/bash
STATE_FILE="${TMPDIR:-/tmp}/claude-avatar-state.json"
INPUT=$(cat)
EVENT=$(echo "$INPUT" | /usr/bin/python3 -c "import sys,json; print(json.load(sys.stdin).get('hook_event_name',''))" 2>/dev/null)
PERMISSION_MODE=$(echo "$INPUT" | /usr/bin/python3 -c "import sys,json; print(json.load(sys.stdin).get('permission_mode',''))" 2>/dev/null)

case "$EVENT" in
  SessionStart)
    STATE="idle"
    # Launch the app if not already running
    pgrep -x ClaudeAvatar || "${CLAUDE_AVATAR_PATH:-$HOME/.local/bin/ClaudeAvatar}" &
    ;;
  UserPromptSubmit)
    # Also ensure app is running (may have auto-quit after long idle)
    pgrep -x ClaudeAvatar || "${CLAUDE_AVATAR_PATH:-$HOME/.local/bin/ClaudeAvatar}" &
    if [ "$PERMISSION_MODE" = "plan" ]; then
      STATE="planning"
    else
      STATE="thinking"
    fi
    ;;
  PreToolUse)
    if [ "$PERMISSION_MODE" = "plan" ]; then
      STATE="planning"
    else
      STATE="tool"
    fi
    ;;
  PostToolUse)
    if [ "$PERMISSION_MODE" = "plan" ]; then
      STATE="planning"
    else
      STATE="thinking"
    fi
    ;;
  PostToolUseFailure)  STATE="error" ;;
  Stop)                STATE="success" ;;
  Notification)
    # Check notification type (try both nested and top-level field)
    TYPE=$(echo "$INPUT" | /usr/bin/python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d.get('notification',{}).get('type','') or d.get('notification_type',''))
" 2>/dev/null)
    if [ "$TYPE" = "idle_prompt" ]; then
      STATE="idle"
    elif [ "$TYPE" = "permission_prompt" ]; then
      STATE="approve"
    else
      STATE=""
    fi
    ;;
  # NOTE: PermissionRequest doesn't fire for every approval prompt —
  # it depends on the user's permission mode and allow/deny settings.
  # The exclamation mark (approve state) won't show for auto-allowed tools.
  PermissionRequest)   STATE="approve" ;;
  SessionEnd)          STATE="goodbye" ;;
  *)                   STATE="" ;;
esac

if [ -n "$STATE" ]; then
  echo "{\"state\":\"$STATE\",\"timestamp\":$(date +%s)}" > "$STATE_FILE"
  chmod 600 "$STATE_FILE"
fi
exit 0

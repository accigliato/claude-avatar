#!/bin/bash
STATE_FILE="/tmp/claude-avatar-state.json"
INPUT=$(cat)
EVENT=$(echo "$INPUT" | /usr/bin/python3 -c "import sys,json; print(json.load(sys.stdin).get('hook_event_name',''))" 2>/dev/null)

case "$EVENT" in
  SessionStart)
    STATE="idle"
    # Launch the app if not already running
    pgrep -x ClaudeAvatar || "${CLAUDE_AVATAR_PATH:-$HOME/.local/bin/ClaudeAvatar}" &
    ;;
  UserPromptSubmit)    STATE="thinking" ;;
  PreToolUse)          STATE="tool" ;;
  PostToolUse)         STATE="thinking" ;;
  PostToolUseFailure)  STATE="error" ;;
  Stop)                STATE="success" ;;
  Notification)
    # Check if it's an idle prompt notification
    TYPE=$(echo "$INPUT" | /usr/bin/python3 -c "import sys,json; print(json.load(sys.stdin).get('notification',{}).get('type',''))" 2>/dev/null)
    if [ "$TYPE" = "idle_prompt" ]; then
      STATE="listening"
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
fi
exit 0

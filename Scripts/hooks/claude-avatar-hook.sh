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
  UserPromptSubmit) STATE="listening" ;;
  PreToolUse)       STATE="working" ;;
  PostToolUse)      STATE="responding" ;;
  Stop)             STATE="idle" ;;
  SessionEnd)       STATE="goodbye" ;;
  *)                STATE="" ;;
esac

if [ -n "$STATE" ]; then
  echo "{\"state\":\"$STATE\",\"timestamp\":$(date +%s)}" > "$STATE_FILE"
fi
exit 0

#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Building ClaudeAvatar..."
make build

# Copy binary + font
INSTALL_DIR="$HOME/.local/bin"
mkdir -p "$INSTALL_DIR"
cp .build/release/ClaudeAvatar "$INSTALL_DIR/"
cp -f .build/release/sga-font.otf "$INSTALL_DIR/" 2>/dev/null || true
echo "Binary installed to $INSTALL_DIR/ClaudeAvatar"

# Make hook script executable
chmod +x Scripts/hooks/claude-avatar-hook.sh
HOOK_PATH="$(pwd)/Scripts/hooks/claude-avatar-hook.sh"

# Configure global hooks in ~/.claude/settings.json
python3 - "$HOOK_PATH" <<'PYEOF'
import json, sys, os

hook_path = sys.argv[1]
settings_path = os.path.expanduser("~/.claude/settings.json")

settings = {}
if os.path.exists(settings_path):
    with open(settings_path) as f:
        settings = json.load(f)

hooks_config = {
    "SessionStart": [{"hooks": [{"type": "command", "command": hook_path, "async": True}]}],
    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": hook_path, "async": True}]}],
    "PreToolUse": [{"hooks": [{"type": "command", "command": hook_path, "async": True}]}],
    "PostToolUse": [{"hooks": [{"type": "command", "command": hook_path, "async": True}]}],
    "PostToolUseFailure": [{"hooks": [{"type": "command", "command": hook_path, "async": True}]}],
    "Stop": [{"hooks": [{"type": "command", "command": hook_path, "async": True}]}],
    "Notification": [{"hooks": [{"type": "command", "command": hook_path, "async": True}]}],
    "PermissionRequest": [{"hooks": [{"type": "command", "command": hook_path, "async": True}]}],
    "SessionEnd": [{"hooks": [{"type": "command", "command": hook_path}]}]
}

settings["hooks"] = hooks_config

os.makedirs(os.path.dirname(settings_path), exist_ok=True)
with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)

print("Hooks configured in", settings_path)
PYEOF

# Export variable with binary path
SHELL_RC="$HOME/.zshrc"
if ! grep -q "CLAUDE_AVATAR_PATH" "$SHELL_RC" 2>/dev/null; then
    echo "export CLAUDE_AVATAR_PATH=\"$INSTALL_DIR/ClaudeAvatar\"" >> "$SHELL_RC"
fi

echo ""
echo "Installation complete!"
echo "Restart your terminal or run: source ~/.zshrc"
echo "Then start a Claude session to see the avatar."

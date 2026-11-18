#!/bin/bash
# Builds the tools and wires them into Claude Code and agy. Backs up each config it edits to <file>.bak-agent-island.
# Usage: install/install.sh [--strict]   (--strict adds the orchestrator edit-blocking hook)
set -euo pipefail
cd "$(dirname "$0")/.."
BIN=$HOME/.local/bin
CLAUDE=$HOME/.claude
AGY=$HOME/.gemini/config

swift build -c release
mkdir -p "$BIN" "$CLAUDE/skills" "$AGY/agents"
cp .build/release/island-bridge .build/release/cc-agy "$BIN/"
cp install/claude-statusline.sh "$BIN/agent-island-statusline.sh"
cp install/strict-role-hook.sh "$BIN/agent-island-strict-role.sh"
cp agents/builder.md "$AGY/agents/builder.md"
cp -R skills/agy-dispatch "$CLAUDE/skills/"

# Appends each event's hook entries to the target file unless island-bridge is already wired in.
merge_hooks() { # file, jq path to the events object, new events json
  local file=$1 path=$2 new=$3
  [ -f "$file" ] || echo '{}' > "$file"
  if grep -q island-bridge "$file"; then echo "hooks already in $file"; return; fi
  cp "$file" "$file.bak-agent-island"
  jq --argjson new "$new" "$path |= ((. // {}) as \$h | reduce (\$new | to_entries[]) as \$e (\$h; .[\$e.key] = ((.[\$e.key] // []) + \$e.value)))" "$file" > "$file.tmp"
  mv "$file.tmp" "$file"
}

merge_hooks "$CLAUDE/settings.json" '.hooks' "$(jq .hooks install/claude-hooks.json)"
# agy hooks.json maps hook names to event handlers, so ours is added under its own name.
[ -f "$AGY/hooks.json" ] || echo '{}' > "$AGY/hooks.json"
if [ "$(jq 'has("agent-island")' "$AGY/hooks.json")" = false ]; then
  cp "$AGY/hooks.json" "$AGY/hooks.json.bak-agent-island"
  jq --slurpfile new install/agy-hooks.json '. + $new[0]' "$AGY/hooks.json" > "$AGY/hooks.json.tmp"
  mv "$AGY/hooks.json.tmp" "$AGY/hooks.json"
fi

if [ "$(jq 'has("statusLine")' "$CLAUDE/settings.json")" = false ]; then
  jq --arg cmd "$BIN/agent-island-statusline.sh" '.statusLine = {type: "command", command: $cmd}' "$CLAUDE/settings.json" > "$CLAUDE/settings.json.tmp"
  mv "$CLAUDE/settings.json.tmp" "$CLAUDE/settings.json"
else
  echo "statusLine already set in settings.json; pipe its JSON to 'island-bridge claude StatusLine' to get context numbers"
fi

if ! grep -q '^## Roles' "$CLAUDE/CLAUDE.md" 2>/dev/null; then
  cp "$CLAUDE/CLAUDE.md" "$CLAUDE/CLAUDE.md.bak-agent-island" 2>/dev/null || true
  { echo; cat install/claude-role.md; } >> "$CLAUDE/CLAUDE.md"
fi

if [ "${1:-}" = "--strict" ]; then
  cp "$CLAUDE/settings.json" "$CLAUDE/settings.json.bak-agent-island-strict"
  jq --arg cmd "$BIN/agent-island-strict-role.sh" \
    '.hooks.PreToolUse = ((.hooks.PreToolUse // []) + [{matcher: "Edit|Write|MultiEdit", hooks: [{type: "command", command: $cmd}]}])' \
    "$CLAUDE/settings.json" > "$CLAUDE/settings.json.tmp"
  mv "$CLAUDE/settings.json.tmp" "$CLAUDE/settings.json"
  echo "strict mode hook added; export CC_ROLE=solo in sessions that should edit freely"
fi
echo "installed. Make sure $BIN is on PATH, then run install/bundle-app.sh and open Doppio.app"

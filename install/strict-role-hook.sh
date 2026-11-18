#!/bin/sh
# PreToolUse hook for Edit|Write|MultiEdit. Blocks code edits over 20 lines so implementation goes to agy.
# CC_ROLE=solo turns it off for a session.
[ "$CC_ROLE" = solo ] && exit 0
input=$(cat)
path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
case "$path" in
  */.plans/*|*/test/*|*/tests/*|*/Tests/*|*/__tests__/*|*.test.*|*.spec.*|*_test.*|*Tests.swift) exit 0 ;;
  *.swift|*.ts|*.tsx|*.js|*.jsx|*.mjs|*.py|*.go|*.rs|*.java|*.kt|*.rb|*.c|*.h|*.cpp|*.m|*.css|*.scss|*.html|*.vue|*.svelte|*.sh) ;;
  *) exit 0 ;;
esac
lines=$(printf '%s' "$input" | jq -r '[.tool_input.new_string, .tool_input.content, (.tool_input.edits[]?.new_string)] | map(select(. != null)) | join("\n")' | wc -l | tr -d ' ')
[ "$lines" -le 20 ] && exit 0
echo "Edit of $lines lines to $path: code changes over 20 lines go to agy (agy-dispatch skill). Write a packet in .plans/ instead." >&2
exit 2

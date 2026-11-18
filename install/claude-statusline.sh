#!/bin/sh
input=$(cat)
printf '%s' "$input" | island-bridge claude StatusLine
printf '%s' "$input" | jq -r '"\(.model.display_name) · ctx \(.context_window.used_percentage // 0)%"'

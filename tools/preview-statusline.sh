#!/bin/bash
# ─── Statusline Preview Tool ───────────────────────────────────────────────────
# Visual preview tool for testing statusline rendering across various terminal
# widths and session scenarios without running an interactive AGY session.
#
# Usage:
#   ./tools/preview-statusline.sh                     # Run built-in scenarios preview
#   ./tools/preview-statusline.sh <file.json> [width] # Preview a custom/recorded payload
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATUSLINE_SCRIPT="$REPO_ROOT/agents/agy/files/home/.gemini/antigravity-cli/statusline.sh"

if [ ! -f "$STATUSLINE_SCRIPT" ]; then
  echo "Error: statusline script not found at $STATUSLINE_SCRIPT" >&2
  exit 1
fi

render_box() {
  local title="$1"
  local width="$2"
  local json_payload="$3"

  # Override terminal width in payload to match test width
  local effective_payload
  effective_payload=$(echo "$json_payload" | jq --argjson w "$width" '.terminal_width = $w' 2>/dev/null || echo "$json_payload")

  local output
  output=$(echo "$effective_payload" | bash "$STATUSLINE_SCRIPT")

  printf "\n\033[1;34m─── [ %s ] (Width: %d cols) ───────────────────────────────\033[0m\n" "$title" "$width"
  printf " %b\n" "$output"
}

# If a file argument is provided, render that custom file
if [ $# -ge 1 ] && [ "$1" != "--help" ] && [ "$1" != "-h" ]; then
  INPUT_FILE="$1"
  TARGET_WIDTH="${2:-80}"

  if [ "$INPUT_FILE" = "-" ]; then
    PAYLOAD=$(cat)
  elif [ -f "$INPUT_FILE" ]; then
    PAYLOAD=$(cat "$INPUT_FILE")
  else
    echo "Error: File '$INPUT_FILE' not found." >&2
    exit 1
  fi

  render_box "Custom Payload Preview: $INPUT_FILE" "$TARGET_WIDTH" "$PAYLOAD"
  exit 0
fi

# ─── Built-in Scenarios ───────────────────────────────────────────────────────

# Scenario 1: Initial state (subscription user, no cost field, full quota)
SCENARIO_INIT='{
  "agent_state": "idle",
  "context_window": { "used_percentage": 2, "current_usage": 4000, "context_window_size": 200000 },
  "quota": {
    "gemini-5h": { "remaining_fraction": 1.0, "reset_in_seconds": 18000 },
    "gemini-weekly": { "remaining_fraction": 1.0, "reset_in_seconds": 604800 },
    "3p-5h": { "remaining_fraction": 1.0, "reset_in_seconds": 18000 },
    "3p-weekly": { "remaining_fraction": 1.0, "reset_in_seconds": 604800 }
  },
  "model": { "display_name": "Gemini 3.7 Flash (High)", "effort": "high" },
  "vcs": { "branch": "main", "dirty": false }
}'

# Scenario 2: Active working with micro-spend (<$0.01) and 5h quota resetting in 3h15m
SCENARIO_MICRO='{
  "agent_state": "thinking",
  "context_window": { "used_percentage": 14, "current_usage": 28000, "context_window_size": 200000 },
  "cost": { "estimated": 0.00428, "workspace": 0.00428, "subagents": 0.0 },
  "quota": {
    "gemini-5h": { "remaining_fraction": 0.82, "reset_in_seconds": 11700 },
    "gemini-weekly": { "remaining_fraction": 0.88, "reset_in_seconds": 380000 },
    "3p-5h": { "remaining_fraction": 1.0, "reset_in_seconds": 18000 },
    "3p-weekly": { "remaining_fraction": 1.0, "reset_in_seconds": 604800 }
  },
  "model": { "display_name": "Gemini 3.7 Flash (High)", "effort": "high" },
  "vcs": { "branch": "feature/statusline", "dirty": true }
}'

# Scenario 3: Standard active session with normal spend ($0.42)
SCENARIO_NORMAL='{
  "agent_state": "working",
  "context_window": { "used_percentage": 42, "current_usage": 84000, "context_window_size": 200000 },
  "cost": { "estimated": 0.42, "workspace": 0.35, "subagents": 0.07 },
  "quota": {
    "gemini-5h": { "remaining_fraction": 0.55, "reset_in_seconds": 7200 },
    "gemini-weekly": { "remaining_fraction": 0.70, "reset_in_seconds": 320000 },
    "3p-5h": { "remaining_fraction": 0.85, "reset_in_seconds": 12000 },
    "3p-weekly": { "remaining_fraction": 0.90, "reset_in_seconds": 450000 }
  },
  "model": { "display_name": "Claude 3.7 Sonnet (Thinking)", "effort": "medium" },
  "vcs": { "branch": "feature/statusline", "dirty": true }
}'

# Scenario 4: High context usage with spend & low quota
SCENARIO_HIGH='{
  "agent_state": "tool use",
  "context_window": { "used_percentage": 86, "current_usage": 172000, "context_window_size": 200000 },
  "cost": { "estimated": 3.85, "workspace": 2.50, "subagents": 1.35 },
  "quota": {
    "gemini-5h": { "remaining_fraction": 0.18, "reset_in_seconds": 2400 },
    "gemini-weekly": { "remaining_fraction": 0.35, "reset_in_seconds": 86400 },
    "3p-5h": { "remaining_fraction": 0.10, "reset_in_seconds": 3600 },
    "3p-weekly": { "remaining_fraction": 0.25, "reset_in_seconds": 150000 }
  },
  "model": { "display_name": "Gemini 3.7 Flash (High)", "effort": "high" },
  "vcs": { "branch": "refactor/core-engine", "dirty": true }
}'

printf "\033[1;36m========================================================================\033[0m\n"
printf "\033[1;36m                  AGY Statusline Visual Previews                        \033[0m\n"
printf "\033[1;36m========================================================================\033[0m\n"

render_box "1. Fresh Session (Subscription: no cost field, 100% quota, clean branch)" 120 "$SCENARIO_INIT"
render_box "2. Micro-spend (\$0.004, quota 82% resetting in 3h15m, thinking state)" 100 "$SCENARIO_MICRO"
render_box "3. Normal spend (\$0.42 neutral, quota 55% resetting in 2h, working state)" 80 "$SCENARIO_NORMAL"
render_box "4. High spend & context (\$3.85, quota 18% resetting in 40m, narrow 60 cols)" 60 "$SCENARIO_HIGH"
render_box "5. Live payload from debug file (80 cols)" 80 "$(cat /tmp/agy-statusline-debug.json 2>/dev/null || echo "$SCENARIO_INIT")"

printf "\n\033[90mTip: To preview a custom or captured payload:\n  ./tools/preview-statusline.sh /path/to/payload.json [cols]\033[0m\n\n"

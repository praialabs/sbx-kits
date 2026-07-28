#!/bin/bash
# Based on official Google Antigravity CLI statusline example:
# https://github.com/google-antigravity/antigravity-cli/blob/03e095ac3619462ecd0928f3f5470387dbda6a00/examples/statusline/statusline.sh
set -euo pipefail
export LC_ALL=C.UTF-8

# ─── ANSI Palette ─────────────────────────────────────────────────────────────
RESET="\033[0m"
BOLD="\033[1m"

FG_CYAN="\033[36m"
FG_GREEN="\033[32m"
FG_YELLOW="\033[33m"
FG_RED="\033[31m"
FG_MAGENTA="\033[35m"
FG_GRAY="\033[90m"
FG_WHITE="\033[97m"

# ─── Parse Input JSON (Single jq pass) ────────────────────────────────────────
{
  read -r STATE
  read -r USED_INT
  read -r VCS_BRANCH
  read -r VCS_DIRTY
  read -r MODEL_DISPLAY
  read -r EFFORT
  read -r COLS
  read -r Q_G5H
  read -r Q_GWK
  read -r Q_3P5H
  read -r Q_3PWK
} <<< "$(
  jq -r '
    (.agent_state // "idle"),
    ((.context_window.used_percentage // 0) | round),
    (.vcs.branch // ""),
    (.vcs.dirty // false),
    (.model.display_name // ""),
    (.model.effort // .model.reasoning_effort // .effort // ""),
    (.terminal_width // 80),
    ((.quota["gemini-5h"].remaining_fraction // 1) * 100 | round),
    ((.quota["gemini-weekly"].remaining_fraction // 1) * 100 | round),
    ((.quota["3p-5h"].remaining_fraction // 1) * 100 | round),
    ((.quota["3p-weekly"].remaining_fraction // 1) * 100 | round)
  ' 2>/dev/null || printf "idle\n0\n\nfalse\n\n\n80\n100\n100\n100\n100\n"
)"

# ─── Format Segments ──────────────────────────────────────────────────────────
SEP="${FG_GRAY} · ${RESET}"
DOT="${FG_GRAY}·${RESET}"

# 1. Context Usage (Fixed width to avoid shift: e.g. " 10% ctx")
if [ "$USED_INT" -gt 80 ]; then
  CTX_COLOR="$FG_RED"
elif [ "$USED_INT" -gt 60 ]; then
  CTX_COLOR="$FG_YELLOW"
else
  CTX_COLOR="$FG_GREEN"
fi
CTX_FMT=$(printf "%2d%% ctx" "$USED_INT")
CTX_STR="${CTX_COLOR}${CTX_FMT}${RESET}"

# 2. Dot-Separated Circle Quota Meters (○ 0%, ◔ 25%, ◑ 50%, ◕ 75%, ● 100%)
get_circle_glyph() {
  local val="$1"
  if [ "$val" -le 15 ]; then echo "○";
  elif [ "$val" -le 40 ]; then echo "◔";
  elif [ "$val" -le 65 ]; then echo "◑";
  elif [ "$val" -le 85 ]; then echo "◕";
  else echo "●"; fi
}

fmt_meter() {
  local val="$1"
  local char=$(get_circle_glyph "$val")
  if [ "$val" -le 15 ]; then
    printf "%b\n" "${FG_RED}${char}${RESET}"
  elif [ "$val" -le 40 ]; then
    printf "%b\n" "${FG_YELLOW}${char}${RESET}"
  else
    printf "%b\n" "${FG_GREEN}${char}${RESET}"
  fi
}

M_G5H=$(fmt_meter "$Q_G5H")
M_GWK=$(fmt_meter "$Q_GWK")
M_3P5H=$(fmt_meter "$Q_3P5H")
M_3PWK=$(fmt_meter "$Q_3PWK")

QUOTA_FULL="${FG_GRAY}g:${RESET}${M_G5H}${DOT}${M_GWK} ${FG_GRAY}3p:${RESET}${M_3P5H}${DOT}${M_3PWK}"
QUOTA_COMPACT="${FG_GRAY}g:${RESET}${M_G5H}${DOT}${M_GWK}"

# 3. Dynamic State Segment
RAW_STATE=$(echo "$STATE" | tr '[:upper:]' '[:lower:]' | tr '_' ' ')
case "$RAW_STATE" in
  idle)         STATE_COLOR="$FG_GRAY" ;;
  thinking)     STATE_COLOR="$FG_CYAN" ;;
  working)      STATE_COLOR="$FG_GREEN" ;;
  "tool use")   STATE_COLOR="$FG_GREEN" ;;
  initializing) STATE_COLOR="$FG_YELLOW" ;;
  *)            STATE_COLOR="$FG_GRAY" ;;
esac

STATE_PADDED=$(printf "%-12s" "$RAW_STATE")
STATE_STR="${STATE_COLOR}${BOLD}${STATE_PADDED}${RESET}"

# Combine Left-aligned info: ctx · quota · state
if [ "$COLS" -ge 90 ]; then
  LEFT="${CTX_STR}${SEP}${QUOTA_FULL}${SEP}${STATE_STR}"
else
  LEFT="${CTX_STR}${SEP}${QUOTA_COMPACT}${SEP}${STATE_STR}"
fi

# 4. VCS Segment (Branch + Dirty)
VCS_STR=""
if [ -n "$VCS_BRANCH" ]; then
  if [ "$VCS_DIRTY" = "true" ]; then
    VCS_STR="${FG_YELLOW}${VCS_BRANCH}*${RESET}"
  else
    VCS_STR="${FG_GRAY}${VCS_BRANCH}${RESET}"
  fi
fi

# 5. Model Segment (Strips trailing effort suffix in parentheses)
MODEL_NAME=$(echo "$MODEL_DISPLAY" | sed -E 's/ \([^)]+\)$//')
MODEL_STR=""
if [ -n "$MODEL_NAME" ]; then
  MODEL_STR="${FG_GRAY}${MODEL_NAME}${RESET}"
fi

# 6. Effort Level Segment
EFFORT_STR=""
if [ -n "$EFFORT" ]; then
  EFFORT_LOWER=$(echo "$EFFORT" | tr "[:upper:]" "[:lower:]")
  EFFORT_STR="${FG_GRAY}${EFFORT_LOWER}${RESET}"
fi

# Combine Right-aligned info: "branch model effort"
RIGHT=""
for seg in "$VCS_STR" "$MODEL_STR" "$EFFORT_STR"; do
  if [ -n "$seg" ]; then
    if [ -n "$RIGHT" ]; then
      RIGHT="${RIGHT}${SEP}${seg}"
    else
      RIGHT="${seg}"
    fi
  fi
done

# ─── Full Terminal Width Alignment ───────────────────────────────────────────
ESC=$(printf "\033")
LEFT_PLAIN=$(printf "%b" "$LEFT" | sed "s/${ESC}\\[[0-9;]*m//g")
RIGHT_PLAIN=$(printf "%b" "$RIGHT" | sed "s/${ESC}\\[[0-9;]*m//g")

LEN_LEFT=${#LEFT_PLAIN}
LEN_RIGHT=${#RIGHT_PLAIN}
PAD=$(( COLS - LEN_LEFT - LEN_RIGHT ))

if [ "$PAD" -gt 1 ]; then
  SPACES=$(printf "%*s" "$PAD" "")
  printf "%b\n" "${LEFT}${SPACES}${RIGHT}"
else
  printf "%b\n" "${LEFT}${SEP}${RIGHT}"
fi

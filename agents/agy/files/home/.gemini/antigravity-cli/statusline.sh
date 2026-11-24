#!/bin/bash
# Based on official Google Antigravity CLI statusline example:
# https://github.com/google-antigravity/antigravity-cli/blob/03e095ac3619462ecd0928f3f5470387dbda6a00/examples/statusline/statusline.sh
set -euo pipefail
export LC_ALL=C.UTF-8

# ─── Debug Payload Capture ───────────────────────────────────────────────────
# If AGY_STATUSLINE_DEBUG is set, tap stdin with tee via process substitution.
if [ -n "${AGY_STATUSLINE_DEBUG:-}" ]; then
  DEBUG_FILE="/tmp/agy-statusline-debug.json"
  if [ "$AGY_STATUSLINE_DEBUG" != "1" ] && [ "$AGY_STATUSLINE_DEBUG" != "true" ]; then
    DEBUG_FILE="$AGY_STATUSLINE_DEBUG"
  fi
  exec < <(tee "$DEBUG_FILE")
fi

# ─── ANSI Palette ─────────────────────────────────────────────────────────────
RESET="\033[0m"
BOLD="\033[1m"

FG_CYAN="\033[36m"
FG_GREEN="\033[32m"
FG_YELLOW="\033[33m"
FG_RED="\033[31m"
FG_GRAY="\033[90m"

# ─── Parse Input JSON (Single jq pass) ────────────────────────────────────────
{
  read -r STATE
  read -r USED_INT
  read -r VCS_BRANCH
  read -r VCS_DIRTY
  read -r MODEL_DISPLAY
  read -r EFFORT
  read -r COLS
  read -r HAS_QUOTA
  read -r Q_G5H
  read -r Q_GWK
  read -r Q_3P5H
  read -r Q_3PWK
  read -r RST_G5H_SECS
  read -r RST_GWK_SECS
  read -r RST_3P5H_SECS
  read -r RST_3PWK_SECS
} <<< "$(
  jq -r '
    def qval(k):
      if .quota[k] == null then "missing"
      elif .quota[k].disabled == true then "disabled"
      else (((.quota[k].remaining_fraction // 1) * 100) | round | tostring)
      end;
    (.agent_state // "idle"),
    ((.context_window.used_percentage // 0) | round),
    (.vcs.branch // ""),
    (.vcs.dirty // false),
    (.model.display_name // ""),
    (.model.effort // .model.reasoning_effort // .effort // ""),
    (.terminal_width // 80),
    (.quota != null and (.quota | length > 0)),
    qval("gemini-5h"),
    qval("gemini-weekly"),
    qval("3p-5h"),
    qval("3p-weekly"),
    (.quota["gemini-5h"].reset_in_seconds // 0),
    (.quota["gemini-weekly"].reset_in_seconds // 0),
    (.quota["3p-5h"].reset_in_seconds // 0),
    (.quota["3p-weekly"].reset_in_seconds // 0)
  ' 2>/dev/null || printf "idle\n0\n\nfalse\n\n\n80\nfalse\nmissing\nmissing\nmissing\nmissing\n0\n0\n0\n0\n"
)"

# Fallback git branch detection:
# Even when types.StatusLineVCS defines branch/dirty tags (agy 1.4.12–1.5.16),
# agy may omit them at runtime and only emit {"type": "git"}.
# Detect branch and dirty status directly via git CLI when omitted in payload:
if [ -z "$VCS_BRANCH" ]; then
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    VCS_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    if [ -n "$VCS_BRANCH" ] && [ -n "$(git status --porcelain 2>/dev/null)" ]; then
      VCS_DIRTY="true"
    fi
  fi
fi

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
  if [ "$val" = "disabled" ] || [ "$val" = "missing" ]; then
    printf "%b\n" "${FG_GRAY}–${RESET}"
    return
  fi
  local char=$(get_circle_glyph "$val")
  if [ "$val" -le 15 ]; then
    printf "%b\n" "${FG_RED}${char}${RESET}"
  elif [ "$val" -le 40 ]; then
    printf "%b\n" "${FG_YELLOW}${char}${RESET}"
  else
    printf "%b\n" "${FG_GREEN}${char}${RESET}"
  fi
}

fmt_duration() {
  local secs="$1"
  if [ "$secs" -le 0 ]; then echo ""; return; fi
  local mins=$(( secs / 60 ))
  if [ "$mins" -lt 60 ]; then
    echo "${mins}m"
  else
    local hours=$(( mins / 60 ))
    local rem_mins=$(( mins % 60 ))
    if [ "$hours" -lt 24 ]; then
      if [ "$rem_mins" -gt 0 ]; then
        echo "${hours}h${rem_mins}m"
      else
        echo "${hours}h"
      fi
    else
      local days=$(( hours / 24 ))
      local rem_hours=$(( hours % 24 ))
      if [ "$rem_hours" -gt 0 ]; then
        echo "${days}d${rem_hours}h"
      else
        echo "${days}d"
      fi
    fi
  fi
}

get_limiting_timer() {
  local q5="$1"
  local r5="$2"
  local qw="$3"
  local rw="$4"

  # Treat disabled/missing buckets as unconstrained (100%, no timer)
  if [ "$q5" = "disabled" ] || [ "$q5" = "missing" ]; then q5=100; r5=0; fi
  if [ "$qw" = "disabled" ] || [ "$qw" = "missing" ]; then qw=100; rw=0; fi

  # 1. Both buckets healthy (>= 85%) -> omit timer to avoid noise
  if [ "$q5" -ge 85 ] && [ "$qw" -ge 85 ]; then
    echo ""
    return
  fi

  # 2. Weekly is critical (<= 20%) -> always alert on weekly reset
  if [ "$qw" -le 20 ] && [ "$rw" -gt 0 ]; then
    local d=$(fmt_duration "$rw")
    [ -n "$d" ] && echo "wk:${d}" && return
  fi

  # 3. Pick the strictly lower/more constrained bucket
  if [ "$q5" -lt "$qw" ] && [ "$r5" -gt 0 ]; then
    local d=$(fmt_duration "$r5")
    [ -n "$d" ] && echo "5h:${d}" && return
  elif [ "$qw" -lt "$q5" ] && [ "$rw" -gt 0 ]; then
    local d=$(fmt_duration "$rw")
    [ -n "$d" ] && echo "wk:${d}" && return
  fi

  # 4. Tied -> prioritize 5h active rolling window
  if [ "$q5" -lt 85 ] && [ "$r5" -gt 0 ]; then
    local d=$(fmt_duration "$r5")
    [ -n "$d" ] && echo "5h:${d}" && return
  elif [ "$qw" -lt 85 ] && [ "$rw" -gt 0 ]; then
    local d=$(fmt_duration "$rw")
    [ -n "$d" ] && echo "wk:${d}" && return
  fi

  echo ""
}

QUOTA_FULL=""
QUOTA_BARE=""
if [ "$HAS_QUOTA" = "true" ]; then
  M_G5H=$(fmt_meter "$Q_G5H")
  M_GWK=$(fmt_meter "$Q_GWK")
  M_3P5H=$(fmt_meter "$Q_3P5H")
  M_3PWK=$(fmt_meter "$Q_3PWK")

  # Quota Reset Timers: dynamically identify the limiting factor bucket
  RST_G_STR=""
  T_G=$(get_limiting_timer "$Q_G5H" "$RST_G5H_SECS" "$Q_GWK" "$RST_GWK_SECS")
  if [ -n "$T_G" ]; then
    RST_G_STR="${FG_GRAY}(${T_G})${RESET}"
  fi

  RST_3P_STR=""
  T_3P=$(get_limiting_timer "$Q_3P5H" "$RST_3P5H_SECS" "$Q_3PWK" "$RST_3PWK_SECS")
  if [ -n "$T_3P" ]; then
    if [ "$COLS" -ge 110 ]; then
      RST_3P_STR="${FG_GRAY}(${T_3P})${RESET}"
    fi
  fi

  QUOTA_FULL="${FG_GRAY}g:${RESET}${M_G5H}${DOT}${M_GWK}${RST_G_STR} ${FG_GRAY}3p:${RESET}${M_3P5H}${DOT}${M_3PWK}${RST_3P_STR}"
  QUOTA_BARE="${FG_GRAY}g:${RESET}${M_G5H}${DOT}${M_GWK} ${FG_GRAY}3p:${RESET}${M_3P5H}${DOT}${M_3PWK}"
fi

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

if [ "$COLS" -ge 100 ]; then
  STATE_PADDED=$(printf "%-12s" "$RAW_STATE")
else
  STATE_PADDED="$RAW_STATE"
fi
STATE_STR="${STATE_COLOR}${BOLD}${STATE_PADDED}${RESET}"

# Combine Left-aligned info: ctx [· quota] · state
LEFT="${CTX_STR}"
if [ -n "$QUOTA_FULL" ]; then
  if [ "$COLS" -ge 80 ]; then
    LEFT="${LEFT}${SEP}${QUOTA_FULL}"
  else
    LEFT="${LEFT}${SEP}${QUOTA_BARE}"
  fi
fi
LEFT="${LEFT}${SEP}${STATE_STR}"

# 4. VCS Segment (Branch + Dirty)
VCS_STR=""
if [ -n "$VCS_BRANCH" ]; then
  if [ "$VCS_DIRTY" = "true" ]; then
    VCS_STR="${FG_YELLOW}${VCS_BRANCH}*${RESET}"
  else
    VCS_STR="${FG_GRAY}${VCS_BRANCH}${RESET}"
  fi
fi

# 5. Model Segment (Strips trailing effort suffix only, preserving e.g. "Orchestrator (Argon)")
MODEL_NAME=$(echo "$MODEL_DISPLAY" | sed -E 's/ \(([Ll]ow|[Mm]edium|[Hh]igh|[Xx][Hh]igh|[Mm]ax|[Mm]inimal|[Tt]hinking)\)$//')
MODEL_STR=""
if [ -n "$MODEL_NAME" ]; then
  MODEL_STR="${FG_GRAY}${MODEL_NAME}${RESET}"
fi

# 6. Effort Level Segment (Included when width >= 110)
EFFORT_STR=""
if [ -n "$EFFORT" ] && [ "$COLS" -ge 110 ]; then
  EFFORT_LOWER=$(echo "$EFFORT" | tr "[:upper:]" "[:lower:]")
  EFFORT_STR="${FG_GRAY}${EFFORT_LOWER}${RESET}"
fi

# ─── Full Terminal Width Alignment ───────────────────────────────────────────
ESC=$(printf "\033")
LEFT_PLAIN=$(printf "%b" "$LEFT" | sed "s/${ESC}\\[[0-9;]*m//g")
LEN_LEFT=${#LEFT_PLAIN}

# Combine Right-aligned info: "branch model effort"
RIGHT=""
if [ "$COLS" -lt 75 ]; then
  # Narrow terminal: prioritize model name
  if [ -n "$MODEL_STR" ]; then
    RIGHT="$MODEL_STR"
  elif [ -n "$VCS_STR" ]; then
    RIGHT="$VCS_STR"
  fi
else
  for seg in "$VCS_STR" "$MODEL_STR" "$EFFORT_STR"; do
    if [ -n "$seg" ]; then
      if [ -n "$RIGHT" ]; then
        RIGHT="${RIGHT}${SEP}${seg}"
      else
        RIGHT="${seg}"
      fi
    fi
  done
fi

RIGHT_PLAIN=$(printf "%b" "$RIGHT" | sed "s/${ESC}\\[[0-9;]*m//g")
LEN_RIGHT=${#RIGHT_PLAIN}
PAD=$(( COLS - LEN_LEFT - LEN_RIGHT ))

# If right side doesn't fit with branch + model (e.g. 80 cols with timer + long branch),
# drop branch/effort and keep model name so the status line stays on a single line.
if [ "$PAD" -lt 2 ] && [ -n "$MODEL_STR" ] && [ "$RIGHT" != "$MODEL_STR" ]; then
  RIGHT="$MODEL_STR"
  RIGHT_PLAIN=$(printf "%b" "$RIGHT" | sed "s/${ESC}\\[[0-9;]*m//g")
  LEN_RIGHT=${#RIGHT_PLAIN}
  PAD=$(( COLS - LEN_LEFT - LEN_RIGHT ))
fi

if [ "$PAD" -gt 1 ]; then
  SPACES=$(printf "%*s" "$PAD" "")
  printf "%b\n" "${LEFT}${SPACES}${RIGHT}"
else
  printf "%b\n" "${LEFT}${SEP}${RIGHT}"
fi

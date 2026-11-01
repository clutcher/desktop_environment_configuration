#!/bin/bash
input=$(cat)

MODEL=$(echo "$input" | jq -r '.model.display_name // "unknown"')
EFFORT=$(echo "$input" | jq -r '.effort.level // empty')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
CTX=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
SESSION_ID=$(echo "$input" | jq -r '.session_id')
CWD=$(echo "$input" | jq -r '.workspace.current_dir')
PROJECT_DIR=$(echo "$input" | jq -r '.workspace.project_dir // .workspace.current_dir')

SALMON='\033[38;2;239;120;114m'
BLUE='\033[38;2;148;191;243m'
GREEN='\033[32m'
YELLOW='\033[33m'
CYAN='\033[36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

GIT_CACHE="/tmp/statusline-git-$SESSION_ID"
cache_stale() {
    [ ! -f "$GIT_CACHE" ] || \
    [ $(( $(date +%s) - $(stat -c %Y "$GIT_CACHE" 2>/dev/null || echo 0) )) -gt 5 ]
}
if cache_stale; then
    if git -C "$CWD" rev-parse --git-dir > /dev/null 2>&1; then
        git -C "$CWD" branch --show-current 2>/dev/null > "$GIT_CACHE"
    else
        printf '' > "$GIT_CACHE"
    fi
fi
BRANCH=$(cat "$GIT_CACHE" 2>/dev/null | tr -d '\n')

EMAIL_CACHE="/tmp/statusline-email-$SESSION_ID"
if [ ! -f "$EMAIL_CACHE" ]; then
    claude auth status 2>/dev/null | jq -r '.email // empty' > "$EMAIL_CACHE"
fi
EMAIL=$(cat "$EMAIL_CACHE" 2>/dev/null | tr -d '\n')

SEP="${DIM} │ ${RESET}"

PARTS="${BLUE}${BOLD}📁 $(basename "$PROJECT_DIR")${RESET}"

PARTS="${PARTS}${SEP}${BLUE}${EMAIL}${RESET}"

if [ -n "$EFFORT" ]; then
    PARTS="${PARTS}${SEP}${SALMON}${BOLD}${MODEL}${RESET}${DIM}/${EFFORT}${RESET}"
else
    PARTS="${PARTS}${SEP}${SALMON}${BOLD}${MODEL}${RESET}"
fi

COST_FMT=$(printf '$%.4f' "$COST")
PARTS="${PARTS}${SEP}${YELLOW}${COST_FMT}${RESET}"

if [ -n "$CTX" ]; then
    CTX_FMT=$(printf '%.0f' "$CTX")
    PARTS="${PARTS}${SEP}${CYAN}ctx ${CTX_FMT}%${RESET}"
fi

if [ -n "$BRANCH" ]; then
    PARTS="${PARTS}${SEP}${GREEN}${BOLD}⎇ ${BRANCH}${RESET}"
fi

echo ""
printf "%b\n" "$PARTS"

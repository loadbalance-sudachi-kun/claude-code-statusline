#!/bin/bash
# Claude Code statusline script
# Line 1: Model | Context% | +added/-removed | git branch
# Line 2: 5h rate limit progress bar
# Line 3: 7d rate limit progress bar

input=$(cat)

# ---------- ANSI Colors (using $'...' for real escape chars) ----------
GREEN=$'\e[38;2;151;201;195m'
YELLOW=$'\e[38;2;229;192;123m'
RED=$'\e[38;2;224;108;117m'
GRAY=$'\e[38;2;74;88;92m'
RESET=$'\e[0m'
DIM=$'\e[2m'

# ---------- Color by percentage ----------
color_for_pct() {
  local pct="$1"
  if [ -z "$pct" ] || [ "$pct" = "null" ]; then
    printf '%s' "$GRAY"
    return
  fi
  local ipct
  ipct=$(printf "%.0f" "$pct" 2>/dev/null || echo "0")
  if [ "$ipct" -ge 80 ]; then
    printf '%s' "$RED"
  elif [ "$ipct" -ge 50 ]; then
    printf '%s' "$YELLOW"
  else
    printf '%s' "$GREEN"
  fi
}

# ---------- Progress bar (10 segments) ----------
progress_bar() {
  local pct="$1"
  local filled
  filled=$(awk "BEGIN{printf \"%d\", int($pct / 10 + 0.5)}" 2>/dev/null || echo 0)
  [ "$filled" -gt 10 ] 2>/dev/null && filled=10
  [ "$filled" -lt 0 ] 2>/dev/null && filled=0
  local bar=""
  for i in $(seq 1 10); do
    if [ "$i" -le "$filled" ]; then
      bar="${bar}▰"
    else
      bar="${bar}▱"
    fi
  done
  printf '%s' "$bar"
}

# ---------- Parse stdin ----------
model_name=$(echo "$input" | jq -r '.model.display_name // "Unknown"')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
cwd=$(echo "$input" | jq -r '.cwd // ""')

# ---------- Git branch ----------
git_branch=""
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  git_branch=$(git -C "$cwd" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null || true)
fi
[ -z "$git_branch" ] && git_branch=$(git --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null || true)

# ---------- Git diff stats (+added/-removed) ----------
git_stats=""
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  diff_stat=$(git -C "$cwd" --no-optional-locks diff --numstat HEAD 2>/dev/null || true)
  if [ -n "$diff_stat" ]; then
    added=$(echo "$diff_stat" | awk '{sum+=$1} END{print sum+0}')
    removed=$(echo "$diff_stat" | awk '{sum+=$2} END{print sum+0}')
    if [ "$added" -gt 0 ] || [ "$removed" -gt 0 ]; then
      git_stats="+${added}/-${removed}"
    fi
  fi
fi

# ---------- Usage API (cached 360s) ----------
CACHE_FILE="/tmp/claude-usage-cache.json"
CACHE_TTL=360
FIVE_HOUR_PCT=""
FIVE_HOUR_RESET=""
SEVEN_DAY_PCT=""
SEVEN_DAY_RESET=""

fetch_usage() {
  local token
  token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || true)
  [ -z "$token" ] && return 1

  local access_token
  if echo "$token" | jq -e . >/dev/null 2>&1; then
    access_token=$(echo "$token" | jq -r '.access_token // .claudeAiOauth.accessToken // empty' 2>/dev/null)
  else
    access_token="$token"
  fi
  [ -z "$access_token" ] && return 1

  local response http_code
  response=$(curl -s --max-time 5 -w '\n%{http_code}' \
    -H "Authorization: Bearer ${access_token}" \
    -H "anthropic-version: 2023-06-01" \
    "https://api.anthropic.com/api/oauth/usage" 2>/dev/null || true)
  [ -z "$response" ] && return 1

  http_code=$(echo "$response" | tail -1)
  local body
  body=$(echo "$response" | sed '$d')

  # Only cache successful responses with valid JSON
  if [ "$http_code" = "200" ] && echo "$body" | jq -e . >/dev/null 2>&1; then
    echo "$body" > "$CACHE_FILE"
    return 0
  fi
  return 1
}

load_usage() {
  local data="$1"
  FIVE_HOUR_PCT=$(echo "$data" | jq -r '.five_hour.utilization // empty' 2>/dev/null || true)
  FIVE_HOUR_RESET=$(echo "$data" | jq -r '.five_hour.reset_at // empty' 2>/dev/null || true)
  SEVEN_DAY_PCT=$(echo "$data" | jq -r '.seven_day.utilization // empty' 2>/dev/null || true)
  SEVEN_DAY_RESET=$(echo "$data" | jq -r '.seven_day.reset_at // empty' 2>/dev/null || true)
}

# Check cache validity
USE_CACHE=false
if [ -f "$CACHE_FILE" ]; then
  cache_age=$(( $(date +%s) - $(stat -f '%m' "$CACHE_FILE" 2>/dev/null || echo 0) ))
  if [ "$cache_age" -lt "$CACHE_TTL" ]; then
    USE_CACHE=true
  fi
fi

if $USE_CACHE; then
  load_usage "$(cat "$CACHE_FILE")"
else
  if fetch_usage; then
    load_usage "$(cat "$CACHE_FILE")"
  elif [ -f "$CACHE_FILE" ]; then
    # API failed — fall back to stale cache
    load_usage "$(cat "$CACHE_FILE")"
  fi
fi

# Convert utilization (0.0-1.0) to percentage
to_pct() {
  local val="$1"
  if [ -z "$val" ] || [ "$val" = "null" ]; then
    echo ""
    return
  fi
  awk "BEGIN{printf \"%.1f\", $val * 100}" 2>/dev/null || echo ""
}

FIVE_HOUR_PCT_DISPLAY=$(to_pct "$FIVE_HOUR_PCT")
SEVEN_DAY_PCT_DISPLAY=$(to_pct "$SEVEN_DAY_PCT")

# ---------- Format reset time ----------
format_reset_time() {
  local iso="$1"
  local format="$2"
  [ -z "$iso" ] && echo "N/A" && return
  # Strip trailing Z and fractional seconds, parse as UTC
  local stripped="${iso%%Z*}"
  stripped="${stripped%%+*}"
  stripped="${stripped%%.*}"
  local epoch
  epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" "+%s" 2>/dev/null || \
          date -d "${iso}" "+%s" 2>/dev/null || echo "")
  [ -z "$epoch" ] && echo "N/A" && return
  # Convert to lowercase am/pm
  local result
  result=$(TZ="Asia/Tokyo" date -j -f "%s" "$epoch" "$format" 2>/dev/null || \
           TZ="Asia/Tokyo" date -d "@${epoch}" "$format" 2>/dev/null || echo "N/A")
  # macOS %p gives uppercase AM/PM; convert to lowercase
  echo "$result" | sed 's/AM/am/;s/PM/pm/'
}

five_reset_display=""
if [ -n "$FIVE_HOUR_RESET" ] && [ "$FIVE_HOUR_RESET" != "null" ]; then
  five_reset_display="Resets $(format_reset_time "$FIVE_HOUR_RESET" "+%-I%p") (Asia/Tokyo)"
fi

seven_reset_display=""
if [ -n "$SEVEN_DAY_RESET" ] && [ "$SEVEN_DAY_RESET" != "null" ]; then
  seven_reset_display="Resets $(format_reset_time "$SEVEN_DAY_RESET" "+%b %-d at %-I%p") (Asia/Tokyo)"
fi

# ---------- Format context used% ----------
ctx_pct_int=0
if [ -n "$used_pct" ] && [ "$used_pct" != "null" ] && [ "$used_pct" != "0" ]; then
  ctx_pct_int=$(printf "%.0f" "$used_pct" 2>/dev/null || echo 0)
fi

# ---------- Line 1 ----------
SEP="${GRAY} │ ${RESET}"

ctx_color=$(color_for_pct "$ctx_pct_int")

line1=""
line1+="🤖 ${model_name}"
line1+="${SEP}"
line1+="${ctx_color}📊 ${ctx_pct_int}%${RESET}"

if [ -n "$git_stats" ]; then
  line1+="${SEP}"
  line1+="✏️  ${GREEN}${git_stats}${RESET}"
fi

if [ -n "$git_branch" ]; then
  line1+="${SEP}"
  line1+="🔀 ${git_branch}"
fi

# ---------- Line 2 (5h) ----------
line2=""
if [ -n "$FIVE_HOUR_PCT_DISPLAY" ]; then
  pct_int_5h=$(printf "%.0f" "$FIVE_HOUR_PCT_DISPLAY" 2>/dev/null || echo 0)
  c5=$(color_for_pct "$pct_int_5h")
  bar5=$(progress_bar "$pct_int_5h")
  line2="${c5}⏱ 5h  ${bar5}  ${pct_int_5h}%${RESET}"
  if [ -n "$five_reset_display" ]; then
    line2+="  ${DIM}${five_reset_display}${RESET}"
  fi
else
  line2="${GRAY}⏱ 5h  N/A${RESET}"
fi

# ---------- Line 3 (7d) ----------
line3=""
if [ -n "$SEVEN_DAY_PCT_DISPLAY" ]; then
  pct_int_7d=$(printf "%.0f" "$SEVEN_DAY_PCT_DISPLAY" 2>/dev/null || echo 0)
  c7=$(color_for_pct "$pct_int_7d")
  bar7=$(progress_bar "$pct_int_7d")
  line3="${c7}📅 7d  ${bar7}  ${pct_int_7d}%${RESET}"
  if [ -n "$seven_reset_display" ]; then
    line3+="  ${DIM}${seven_reset_display}${RESET}"
  fi
else
  line3="${GRAY}📅 7d  N/A${RESET}"
fi

# ---------- Output ----------
printf '%s\n' "$line1"
printf '%s\n' "$line2"
printf '%s' "$line3"

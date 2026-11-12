#!/usr/bin/env bash
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"
# Fewer child processes means less delay: every `$(...)`, pipe, `date`, `sed`, `awk` is
# one. So jq reads stdin directly (one process for all fields), and the helpers below
# return their result in a variable instead of printing it for `$(...)` to capture.
IFS=$'\x1f' read -r cwd model ctx_pct ctx_size hour_pct week_pct hour_reset week_reset thinking effort duration_ms api_duration_ms ctx_tokens <<EOF
$(jq -r '[
  (.workspace.current_dir // .cwd // ""),
  (.model.display_name // ""),
  ((.context_window.used_percentage // "") | tostring),
  ((.context_window.context_window_size // "") | tostring),
  (((.rate_limits.five_hour // {}).used_percentage // "") | tostring),
  (((.rate_limits.seven_day // {}).used_percentage // "") | tostring),
  (((.rate_limits.five_hour // {}).resets_at // "") | tostring),
  (((.rate_limits.seven_day // {}).resets_at // "") | tostring),
  (.thinking.enabled | if . then "*" else "" end),
  (.effort.level // ""),
  ((.cost.total_duration_ms // "") | tostring),
  ((.cost.total_api_duration_ms // "") | tostring),
  ((.context_window.total_input_tokens // "") | tostring)
] | join("\u001f")')
EOF

dir=${cwd%/}; dir=${dir##*/}
printf -v now '%(%s)T' -1 2>/dev/null || now=$(date +%s)   # bash 4.2+, else date
[[ "$hour_reset" =~ ^[0-9]+$ ]] || hour_reset=""
[[ "$week_reset" =~ ^[0-9]+$ ]] || week_reset=""
thinking="${thinking:-}"; effort="${effort:-}"
duration_ms="${duration_ms:-}"; api_duration_ms="${api_duration_ms:-}"
[[ "$ctx_size" =~ ^[0-9]+$ ]] || ctx_size=""
[[ "$ctx_tokens" =~ ^[0-9]+$ ]] || ctx_tokens=""

ESC=$'\033'
# No background is set anywhere: the line stays transparent over the terminal.
RESET="${ESC}[0m"
BOLD="${ESC}[1m"
DIM="${ESC}[2;37m"
WHITE="${ESC}[0;37m"
BOLD_WHITE="${ESC}[1;37m"
GREEN="${ESC}[0;32m"
YELLOW="${ESC}[0;33m"
RED="${ESC}[0;31m"
BOLD_RED="${ESC}[1;31m"
ALERT="${ESC}[1;31m"
ORANGE="${ESC}[0;33m" PEACH="${ESC}[1;33m"      # dir, model
BLUEF="${ESC}[0;94m"  VIOF="${ESC}[0;95m"       # 5h, 7d
TEAL="${ESC}[0;36m"   SAND="${ESC}[0;93m"       # session time, clock
TRK="" STOPS=()

# ── 24-bit "Claude" palette (r g b); anything else keeps the 16 colors above ──
# An "-ansi" Claude Code theme means: use the terminal's own 16 colors, which the
# terminal (e.g. VS Code) paints from its theme. Read in bash: no extra process.
mode=${CLAUDE_STATUSLINE_COLOR:-}
if [ -z "$mode" ]; then
  theme=""
  while IFS= read -r line; do
    [[ $line =~ \"theme\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && { theme=${BASH_REMATCH[1]}; break; }
  done < "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" 2>/dev/null
  case $theme in *-ansi) mode=16 ;; *) mode=${COLORTERM:-} ;; esac
fi
TC=0
case $mode in truecolor|24bit) TC=1 ;; esac
if (( TC )); then
  C_A0="168 85 58"; C_A1="217 119 87"; C_A2="235 162 133"   # orange, dark to light
  C_B0="56 100 150"; C_B1="106 155 204"; C_B2="160 195 230" # blue (5h)
  C_V0="110 80 160"; C_V1="168 140 214"; C_V2="205 185 235" # violet (7d)
  C_OK="107 170 117"; C_WARN="217 164 65"; C_HOT="217 83 79"
  C_INK="237 230 225"; C_MUTED="138 133 128"; C_TRACK="58 54 52"
  C_TEAL="100 190 180"; C_SAND="225 200 150"
  sgr() { local v=$1 code=$2; shift 2; printf -v "$v" '\033[%s;2;%d;%d;%dm' "$code" "$@"; }
  sgr DIM 38 $C_MUTED;  sgr WHITE 38 $C_INK;   sgr GREEN 38 $C_OK
  sgr YELLOW 38 $C_WARN; sgr RED 38 $C_HOT
  sgr ORANGE 38 $C_A1; sgr PEACH 38 $C_A2; sgr BLUEF 38 $C_B2; sgr VIOF 38 $C_V2
  sgr TEAL 38 $C_TEAL; sgr SAND 38 $C_SAND
  BOLD_WHITE="${BOLD}${WHITE}"; BOLD_RED="${BOLD}${RED}"; ALERT=$BOLD_RED
  ORANGE="${BOLD}${ORANGE}"; PEACH="${BOLD}${PEACH}"
  sgr TRK 38 $C_TRACK

  # fg color at cell i of n along the stops given (each "r g b"), integer math
  grad_at() {
    local i=$1 n=$2; shift 2
    local -a st=("$@"); local k=$(( ${#st[@]} - 1 )) t seg f
    local -a a b
    if (( k < 1 )); then sgr GC 38 ${st[0]}; return; fi
    t=$(( n > 1 ? i * 1000 / (n - 1) : 0 ))
    seg=$(( t * k / 1000 )); (( seg >= k )) && seg=$(( k - 1 ))
    f=$(( t * k - seg * 1000 ))
    a=(${st[seg]}); b=(${st[seg + 1]})
    sgr GC 38 $(( (a[0] * (1000 - f) + b[0] * f) / 1000 )) \
              $(( (a[1] * (1000 - f) + b[1] * f) / 1000 )) \
              $(( (a[2] * (1000 - f) + b[2] * f) / 1000 ))
  }
  # bar colors: the hue (o orange, b blue, v violet), turning amber then red as it fills
  bar_stops() {
    if   (( $1 >= 85 )); then STOPS=("$C_WARN" "$C_HOT")
    elif (( $1 >= 60 )); then
      case $2 in b) STOPS=("$C_B0" "$C_WARN") ;; v) STOPS=("$C_V0" "$C_WARN") ;; *) STOPS=("$C_A0" "$C_WARN") ;; esac
    else
      case $2 in b) STOPS=("$C_B0" "$C_B1" "$C_B2") ;; v) STOPS=("$C_V0" "$C_V1" "$C_V2") ;; *) STOPS=("$C_A0" "$C_A1" "$C_A2") ;; esac
    fi
  }
fi

# Helpers set one result variable (named in the comment) instead of printing.

to_pct() { # VAR value: whole percent, clamped to 0..100
  local v
  LC_ALL=C printf -v v '%.0f' "$2" 2>/dev/null || v=${2%%.*}
  [[ "$v" =~ ^-?[0-9]+$ ]] || v=0
  (( v < 0 )) && v=0
  (( v > 100 )) && v=100
  printf -v "$1" '%s' "$v"
}

trunc() { # TR: string cut to m characters, with an ellipsis
  local s=$1 m=$2
  if (( ${#s} > m )); then TR="${s:0:m-1}…"; else TR=$s; fi
}

fmt_dur() { # FD: seconds as 2d3h / 1h05m / 7m / <1m
  local s=$1
  if   (( s >= 86400 )); then printf -v FD '%dd%dh' $(( s / 86400 )) $(( s % 86400 / 3600 ))
  elif (( s >= 3600 ));  then printf -v FD '%dh%02dm' $(( s / 3600 )) $(( s % 3600 / 60 ))
  elif (( s >= 60 ));    then printf -v FD '%dm' $(( s / 60 ))
  else                        FD='<1m'
  fi
}

fmt_tokens() { # FT: 620k, 1.0M
  local n=$1 t
  if   (( n >= 1000000 )); then t=$(( (n + 50000) / 100000 )); printf -v FT '%d.%dM' $(( t / 10 )) $(( t % 10 ))
  elif (( n >= 1000 ));    then printf -v FT '%dk' $(( n / 1000 ))
  else                          printf -v FT '%d' "$n"
  fi
}

format_reset_time() { # FR: clock time of an epoch, like 2:23pm or 8am
  local hhmm
  FR=""
  printf -v hhmm "%(%l:%M %p)T" "$1" 2>/dev/null \
    || hhmm=$(date -r "$1" "+%l:%M %p" 2>/dev/null || date -d "@$1" "+%l:%M %p" 2>/dev/null)
  [ -z "$hhmm" ] && return 1
  hhmm="${hhmm# }"
  local hour=${hhmm%%:*} rest=${hhmm#*:}
  local mins=${rest%% *} ampm=${rest##* }
  case $ampm in AM|am) ampm=am ;; *) ampm=pm ;; esac
  if [ "$mins" = "00" ]; then FR="${hour}${ampm}"; else FR="${hour}:${mins}${ampm}"; fi
}

pct_color() {
  if (( TC )); then
    if   (( $1 >= 85 )); then PC=$RED
    elif (( $1 >= 60 )); then PC=$YELLOW
    else                      PC=$HUEFG
    fi
    return
  fi
  if   (( $1 >= 90 )); then PC=$BOLD_RED
  elif (( $1 >= 75 )); then PC=$RED
  elif (( $1 >= 50 )); then PC=$YELLOW
  else                      PC=$HUEFG
  fi
}

cd_color() {
  local p=$(( $1 * 100 / $2 ))
  if   (( p >= 50 )); then CDC=$GREEN
  elif (( p >= 25 )); then CDC=$TEAL
  elif (( p >= 10 )); then CDC=$YELLOW
  else                     CDC=$RED
  fi
}

EIGHTH=("" ▏ ▎ ▍ ▌ ▋ ▊ ▉)

build_bar() {
  local pct=$1 w=$2 e8 full rem i
  e8=$(( pct * w * 8 / 100 ))
  full=$(( e8 / 8 )); rem=$(( e8 % 8 ))
  (( pct > 0 && e8 == 0 )) && rem=1
  BAR=""
  if (( TC )); then
    for (( i = 0; i < w; i++ )); do
      if (( i < full )); then
        grad_at "$i" "$w" "${STOPS[@]}"; BAR+="${GC}█"
      elif (( i == full && rem > 0 )); then
        grad_at "$i" "$w" "${STOPS[@]}"; BAR+="${GC}${ESC}[48;2;${C_TRACK// /;}m${EIGHTH[$rem]}${RESET}"
      else
        BAR+="${TRK}█"
      fi
    done
    BAR+=$RESET
    return
  fi
  for (( i = 0; i < w; i++ )); do
    if (( i < full )); then
      BAR+="${HUEFG}█"
    elif (( i == full && rem > 0 )); then
      BAR+="${HUEFG}${EIGHTH[$rem]}"
    else
      BAR+="${DIM}░${RESET}"
    fi
  done
  BAR+=$RESET
}

meter() { # METER: [label] [bar] [pct]; hue o|b|v; empty label = none, "nopct" = no percent
  local label=$1 pct=$2 nopct=${3:-} hue=${4:-o} parts=()
  case $hue in b) HUEFG=$BLUEF ;; v) HUEFG=$VIOF ;; *) HUEFG=$PEACH ;; esac
  pct_color "$pct"
  [ -n "$label" ] && parts+=("${HUEFG}${label}${RESET}")
  if (( BAR_W > 0 )); then (( TC )) && bar_stops "$pct" "$hue"; build_bar "$pct" "$BAR_W"; parts+=("$BAR"); fi
  if [ -z "$nopct" ]; then
    if (( pct >= 90 )); then parts+=("${ALERT}⚠ ${pct}%${RESET}"); else parts+=("${PC}${pct}%${RESET}"); fi
  fi
  METER="${parts[*]}"
}

ctx_i="";  [ -n "$ctx_pct" ]  && to_pct ctx_i "$ctx_pct"
hour_i=""; [ -n "$hour_pct" ] && to_pct hour_i "$hour_pct"
week_i=""; [ -n "$week_pct" ] && to_pct week_i "$week_pct"

# ── shared cache: account-wide rate limits only ─────────────────────
# Every window has the same 5h/7d limits, and Claude sends them only after the
# first reply. Everything else is per-window and arrives on every run, so it is
# never cached. Merge writes: a render without limits never blanks them.
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline"
CACHE="$CACHE_DIR/limits"
[ -d "$CACHE_DIR" ] || mkdir -p "$CACHE_DIR" 2>/dev/null

cache_ts=0 cache_hour="" cache_week="" cache_hr="" cache_wr=""
[ -f "$CACHE" ] && IFS=$'\x1f' read -r cache_ts cache_hour cache_week cache_hr cache_wr < "$CACHE" 2>/dev/null
# the file is untrusted input: keep only plain numbers
[[ "$cache_ts" =~ ^[0-9]{1,12}$ ]]   || cache_ts=0
[[ "$cache_hour" =~ ^[0-9]{1,3}$ ]]  || cache_hour=""
[[ "$cache_week" =~ ^[0-9]{1,3}$ ]]  || cache_week=""
[[ "$cache_hr" =~ ^[0-9]{1,12}$ ]]   || cache_hr=""
[[ "$cache_wr" =~ ^[0-9]{1,12}$ ]]   || cache_wr=""
# a window that already reset holds an old reading: drop it
[ -n "$cache_hr" ] && (( cache_hr <= now )) && { cache_hour=""; cache_hr=""; }
[ -n "$cache_wr" ] && (( cache_wr <= now )) && { cache_week=""; cache_wr=""; }

[ -z "$hour_i" ] && [ -n "$cache_hr" ] && { hour_i=$cache_hour; hour_reset=$cache_hr; }
[ -z "$week_i" ] && [ -n "$cache_wr" ] && { week_i=$cache_week; week_reset=$cache_wr; }

# Write when stale (2s TTL) and the values changed
if (( now - cache_ts > 2 )) && { [ -n "$hour_i" ] || [ -n "$week_i" ]; } \
   && [ "$hour_i|$week_i|$hour_reset|$week_reset" != "$cache_hour|$cache_week|$cache_hr|$cache_wr" ]; then
  printf '%s\x1f%s\x1f%s\x1f%s\x1f%s\n' "$now" "$hour_i" "$week_i" "$hour_reset" "$week_reset" > "$CACHE.tmp" \
    && mv "$CACHE.tmp" "$CACHE" 2>/dev/null
fi

# ── git ──────────────────────────────────────────────────────────────
branch="" dirty="" ab=""
abline=""
if [ -n "$cwd" ] && gs=$(git -C "$cwd" -c core.hooksPath=/dev/null status --porcelain=v2 --branch --untracked-files=no 2>/dev/null); then
  while IFS= read -r line; do   # parsed in bash: no sed/grep processes
    case $line in
      "# branch.head "*) branch=${line#"# branch.head "} ;;
      "# branch.ab "*)   abline=${line#"# branch.ab "} ;;
      "#"*) ;;
      ?*)   dirty=1 ;;
    esac
  done <<<"$gs"
  [ "$branch" = "(detached)" ] && branch=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  if [ -n "$abline" ]; then
    a=${abline%% *}; b=${abline##* }; a=${a#+}; b=${b#-}
    [ "$a" != 0 ] && ab+="↑$a"
    [ "$b" != 0 ] && ab+="↓$b"
  fi
fi

# ── terminal width ───────────────────────────────────────────────────
cols=${COLUMNS:-}
! [[ "$cols" =~ ^[0-9]+$ ]] || [ "$cols" -le 0 ] && cols=80

PAD=${CLAUDE_STATUSLINE_PAD:-4}
# VL: visible length with the color codes (ESC ... m) removed. A loop, not
# ${s//pattern/}: bash's extglob replace is very slow on long strings.
vis_len() {
  local s=$1 plain=""
  while [[ $s == *$'\033'* ]]; do
    plain+=${s%%$'\033'*}
    s=${s#*$'\033'}; s=${s#*m}
  done
  plain+=$s
  local noemoji=${plain//🕐/}   # the clock emoji is 2 columns wide
  VL=$(( ${#noemoji} + (${#plain} - ${#noemoji}) * 2 ))
}

render() {
  local lvl=$1 name_max sep
  # a level lists only what it shows; the model name is the last thing to go (level 10)
  local BAR_W=0 show_5h=0 show_7d=0 show_branch=0 show_cd=0 show_abs=0 show_wcd=0 show_model=1 show_duration=0
  case $lvl in
    0)  BAR_W=8;  name_max=24; show_branch=1 show_5h=1 show_7d=1 show_cd=1 show_wcd=1 show_abs=1 show_model=1 show_duration=1 ;;
    1)  BAR_W=6;  name_max=20; show_branch=1 show_5h=1 show_7d=1 show_cd=1 show_wcd=1 show_model=1 show_duration=1 ;;
    2)  BAR_W=6;  name_max=18; show_branch=1 show_5h=1 show_7d=1 show_cd=1 show_wcd=1 show_duration=1 ;;
    3)  BAR_W=4;  name_max=16; show_branch=1 show_5h=1 show_7d=1 show_cd=1 show_duration=1 ;;
    4)  BAR_W=0;  name_max=14; show_branch=1 show_5h=1 show_7d=1 ;;
    5)  BAR_W=0;  name_max=12; show_branch=1 show_5h=1 show_7d=1 ;;
    6)  BAR_W=0;  name_max=12; show_branch=1 show_5h=1 ;;
    7)  BAR_W=0;  name_max=10; show_branch=1 show_5h=1 ;;
    8)  BAR_W=0;  name_max=10; show_5h=1 ;;
    9)  BAR_W=0;  name_max=10 ;;
    10) BAR_W=0;  name_max=10; show_model=0 ;;
  esac
  sep=" ${DIM}│${RESET} "
  local LAB5="" LAB7=""; (( BAR_W == 0 )) && { LAB5=5h; LAB7=7d; }

  trunc "$dir" "$name_max"; OUT="${ORANGE}${TR}${RESET}"
  if [ -n "$branch" ] && (( show_branch )); then
    trunc "$branch" "$name_max"
    OUT+=" ${DIM}⎇${RESET} ${GREEN}${TR}${RESET}"
    [ -n "$dirty" ] && OUT+=" ${YELLOW}●${RESET}"
    [ -n "$ab" ] && OUT+=" ${TEAL}${ab}${RESET}"
  fi
  if (( show_model )); then
    OUT+="${sep}${PEACH}${model:-claude}${RESET}"
    [ -n "$thinking" ] && OUT+=" ${SAND}${thinking}${RESET}"
    [ -n "$effort" ] && OUT+=" ${DIM}${effort}${RESET}"
  fi
  if [ -n "$duration_ms" ] && (( show_duration )); then
    fmt_dur $(( duration_ms / 1000 ))
    OUT+="${sep}${DIM}Tst${RESET} ${TEAL}${FD}${RESET}"
    if [ -n "$api_duration_ms" ]; then
      fmt_dur $(( api_duration_ms / 1000 ))
      OUT+=" ${DIM}api${RESET} ${TEAL}${FD}${RESET}"
    fi
  fi
  if (( show_duration )); then
    format_reset_time "$now"
    [ -n "$FR" ] && OUT+="${sep}${SAND}🕐 ${FR}${RESET}"
  fi
  if [ -n "$ctx_i" ]; then
    meter "" "$ctx_i" nopct o
    if [ -n "$ctx_size" ] && (( ctx_size > 0 )); then
      local consumed=${ctx_tokens:-$(( ctx_i * ctx_size / 100 ))}
      fmt_tokens "$consumed"; local used_t=$FT
      fmt_tokens "$ctx_size"
      METER+="${METER:+ }${PC}${used_t}/${FT}${RESET}"
    fi
    OUT+="${sep}${METER}"
  fi
  if [ -n "$hour_i" ] && (( show_5h )); then
    meter "$LAB5" "$hour_i" "" b
    OUT+="${sep}${METER}"
    if [ -n "$hour_reset" ] && (( show_cd )) && (( hour_reset > now )); then
      cd_color $(( hour_reset - now )) 18000
      fmt_dur $(( hour_reset - now ))
      OUT+=" ${DIM}↻${RESET} ${CDC}${FD}${RESET}"
      if (( show_abs )); then
        format_reset_time "$hour_reset" && [ -n "$FR" ] && OUT+=" ${BLUEF}(${FR})${RESET}"
      fi
    fi
  fi
  if [ -n "$week_i" ] && (( show_7d )); then
    meter "$LAB7" "$week_i" "" v
    OUT+="${sep}${METER}"
    if [ -n "$week_reset" ] && (( show_wcd )) && (( week_reset > now )); then
      cd_color $(( week_reset - now )) 604800
      fmt_dur $(( week_reset - now ))
      OUT+=" ${DIM}↻${RESET} ${CDC}${FD}${RESET}"
      if (( show_abs )); then
        local wd; printf -v wd '%(%a)T' "$week_reset" 2>/dev/null
        format_reset_time "$week_reset" && [ -n "$FR" ] && OUT+=" ${VIOF}(${wd} ${FR})${RESET}"
      fi
    fi
  fi
}

for lvl in 0 1 2 3 4 5 6 7 8 9 10; do
  render "$lvl"
  vis_len "$OUT"
  (( VL <= cols - PAD )) && break
done

if (( VL > cols - PAD )); then
  max=$(( cols - PAD ))
  (( max < 1 )) && max=1
  trunc "$dir" "$max"
  OUT="${BOLD_WHITE}${TR}${RESET}"
fi

printf '%s' " ${OUT}${RESET}"

#!/usr/bin/env bash
# Pipes fixture JSON into statusline-command.sh at several widths and checks the output.
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
script="$root/statusline-command.sh"
tmp=$(mktemp -d "${TMPDIR:-/data/tarakesh/.tmp}/statusline-test.XXXXXX")
trap 'rm -rf "${tmp:?}"' EXIT
export XDG_CACHE_HOME="$tmp"

now=$(date +%s)
fail=0
strip() { sed 's/\x1b\[[0-9;]*m//g'; }
check() { # name, condition result
  if [ "$2" = 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi
}
run() { # cols, json
  rm -rf "${tmp:?}"/claude-statusline
  COLUMNS=$1 bash "$script" <<<"$2" 2>/dev/null | strip
}
export CLAUDE_STATUSLINE_COLOR=16   # tests below run in the 16-color mode unless they say otherwise
rawtc() { # cols, json: raw output in 24-bit mode
  rm -rf "${tmp:?}"/claude-statusline
  CLAUDE_STATUSLINE_COLOR=truecolor COLUMNS=$1 bash "$script" <<<"$2" 2>/dev/null
}

full='{"model":{"display_name":"Opus"},"workspace":{"current_dir":"'"$root"'"},
"cost":{"total_duration_ms":123456,"total_api_duration_ms":45678},
"context_window":{"used_percentage":4,"context_window_size":1000000,"total_input_tokens":43210},
"prompt_cache":{"warm":true,"caching_observed":true,"expires_at":'$((now + 2430))',"hit_ratio":0.91},
"rate_limits":{"five_hour":{"used_percentage":35,"resets_at":'$((now + 8000))'},
"seven_day":{"used_percentage":14,"resets_at":'$((now + 500000))'}}}'

# the line must never be wider than the terminal
for w in 30 50 80 120 200; do
  out=$(run "$w" "$full")
  [ "$(printf '%s' "$out" | wc -m)" -le "$w" ]; check "fits ${w} columns" $?
done

# narrow levels must really drop things: at 80 columns the 5h segment still fits
grep -q '5h' <<<"$(run 80 "$full")"; check "80 columns keeps 5h" $?
! grep -q '🕐' <<<"$(run 80 "$full")"; check "80 columns drops the clock" $?

out=$(run 200 "$full")
grep -q '43k/1.0M' <<<"$out"; check "real token count" $?
grep -q 'cache 40m' <<<"$out"; check "cache warm countdown" $?
grep -q 'hit 91%' <<<"$out"; check "cache hit rate" $?

cold=${full/\"warm\":true/\"warm\":false}
grep -q 'cache cold' <<<"$(run 200 "$cold")"; check "cache cold" $?

# missing and hostile input must not crash or print garbage
for j in '{}' '' 'not json' '{"cost":{"total_duration_ms":"x"},"prompt_cache":{"hit_ratio":"zz"}}'; do
  out=$(run 80 "$j"); rc=$?
  [ "$rc" = 0 ] && ! grep -q '\$x' <<<"$out"; check "survives input: ${j:-<empty>}" $?
done

# shared cache: limits carry over to a window that has none yet
rm -rf "${tmp:?}"/claude-statusline
COLUMNS=200 bash "$script" <<<"$full" >/dev/null 2>&1
bare='{"model":{"display_name":"Sonnet"},"workspace":{"current_dir":"'"$root"'"}}'
out=$(COLUMNS=200 bash "$script" <<<"$bare" 2>/dev/null | strip)
grep -q '5h .*35%' <<<"$out"; check "cache fills limits for a new window" $?

# per-window data never crosses windows: model, effort, thinking, context
! grep -qE 'Opus|43k|ctx|Tst' <<<"$out"; check "cache does not leak per-window data" $?
grep -q 'Sonnet' <<<"$out"; check "window shows its own model" $?

# a reading whose reset time has passed is dropped
mkdir -p "$tmp/claude-statusline"
printf '%s\x1f77\x1f55\x1f%s\x1f%s\n' "$now" "$((now - 10))" "$((now - 10))" >"$tmp/claude-statusline/limits"
out=$(COLUMNS=200 bash "$script" <<<"$bare" 2>/dev/null | strip)
! grep -q '77%' <<<"$out"; check "expired cached limits are dropped" $?

# hostile cache content is ignored
printf '%s\x1f\033[31mX\x1f$(echo hi)\x1fabc\x1f-1\n' "$now" >"$tmp/claude-statusline/limits"
out=$(COLUMNS=200 bash "$script" <<<"$bare" 2>/dev/null)
! grep -q 'X' <<<"$out"; check "hostile cache file is ignored" $?

# 24-bit mode: same text, real colors, still fits
for w in 30 50 80 120 200; do
  out=$(rawtc "$w" "$full" | strip)
  [ "$(printf '%s' "$out" | wc -m)" -le "$w" ]; check "24-bit fits ${w} columns" $?
done
raw=$(rawtc 200 "$full")
grep -q $'\033\[38;2;' <<<"$raw"; check "24-bit uses 38;2 colors" $?
grep -q $'\033\[48;2;' <<<"$raw"; check "24-bit draws label chips and bar track" $?
! grep -q $'38;2;' <<<"$(CLAUDE_STATUSLINE_COLOR=16 bash "$script" <<<"$full" 2>/dev/null)"; check "16-color mode has no 24-bit codes" $?
# a bar's first cell is darker than its last (a real gradient)
hi='{"workspace":{"current_dir":"'"$root"'"},"context_window":{"used_percentage":50,"context_window_size":1000000}}'
rawtc 200 "$hi" | grep -oE $'\033\\[38;2;[0-9]+;[0-9]+;[0-9]+m█' | awk -F';' 'NR==1{f=$3} NR==4{l=$3} END{exit !(l+0>f+0)}'; check "bar colors change along the bar" $?
# percent color: green below 60, amber at 60, red at 85
for p in 10:107 70:217 90:217; do
  j='{"workspace":{"current_dir":"'"$root"'"},"context_window":{"used_percentage":'"${p%%:*}"',"context_window_size":1000000}}'
  rawtc 200 "$j" | grep -qE "38;2;${p##*:};" ; check "status color at ${p%%:*}%" $?
done

exit $fail

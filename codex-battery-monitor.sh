#!/bin/bash

# codex-battery-monitor
# Lightweight macOS monitoring for Codex/ChatGPT Computer Use CPU and battery activity.

set -u

PROGRAM_NAME="codex-battery-monitor"
PROGRAM_VERSION="1.0.0"
DEFAULT_INTERVAL=30
DEFAULT_THRESHOLD=30

interval=$DEFAULT_INTERVAL
threshold=$DEFAULT_THRESHOLD
output_file="codex-battery-monitor.csv"
sample_limit=0
sample_count=0
scan_logs=1
show_wall_clock=1
quiet=0
previous_retries=-1
start_epoch="$(date +%s)"

usage() {
  cat <<'EOF'
Usage: codex-battery-monitor.sh [options]

Monitor macOS battery state and aggregate CPU usage associated with Codex,
ChatGPT Computer Use, screen capture, and WindowServer.

Options:
  -i, --interval SECONDS   Seconds between samples (minimum: 5; default: 30)
  -o, --output FILE        CSV output path (default: ./codex-battery-monitor.csv)
  -n, --samples COUNT      Stop after COUNT samples (default: run until Ctrl+C)
      --once               Take one sample and exit
  -t, --threshold PERCENT  replayd alert threshold (default: 30)
      --no-log-scan        Do not count Pet/PiP retry messages in Codex logs
      --no-wall-clock      Omit wall-clock timestamps; record elapsed seconds only
  -q, --quiet              Suppress human-readable output; still write CSV
  -h, --help               Show this help
  -v, --version            Show version

Examples:
  ./codex-battery-monitor.sh
  ./codex-battery-monitor.sh --interval 10 --samples 12
  ./codex-battery-monitor.sh --once --output snapshot.csv
  ./codex-battery-monitor.sh --no-log-scan --no-wall-clock
EOF
}

fail() {
  printf '%s: %s\n' "$PROGRAM_NAME" "$1" >&2
  exit 2
}

is_nonnegative_integer() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -i|--interval)
      [ "$#" -ge 2 ] || fail "$1 requires a value"
      interval=$2
      shift 2
      ;;
    -o|--output)
      [ "$#" -ge 2 ] || fail "$1 requires a value"
      output_file=$2
      shift 2
      ;;
    -n|--samples)
      [ "$#" -ge 2 ] || fail "$1 requires a value"
      sample_limit=$2
      shift 2
      ;;
    --once)
      sample_limit=1
      shift
      ;;
    -t|--threshold)
      [ "$#" -ge 2 ] || fail "$1 requires a value"
      threshold=$2
      shift 2
      ;;
    --no-log-scan)
      scan_logs=0
      shift
      ;;
    --no-wall-clock)
      show_wall_clock=0
      shift
      ;;
    -q|--quiet)
      quiet=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -v|--version)
      printf '%s %s\n' "$PROGRAM_NAME" "$PROGRAM_VERSION"
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

[ "$#" -eq 0 ] || fail "unexpected positional argument: $1"
is_nonnegative_integer "$interval" || fail "interval must be an integer"
[ "$interval" -ge 5 ] || fail "interval must be at least 5 seconds"
is_nonnegative_integer "$sample_limit" || fail "sample count must be an integer"
[ "$sample_limit" -ne 0 ] || sample_limit=0
is_nonnegative_integer "$threshold" || fail "threshold must be an integer"
[ -n "$output_file" ] || fail "output path cannot be empty"

[ "$(uname -s)" = "Darwin" ] || fail "this tool supports macOS only"

for required_command in pmset ioreg ps awk sed date find; do
  command -v "$required_command" >/dev/null 2>&1 || fail "required command not found: $required_command"
done

output_dir="$(dirname "$output_file")"
[ -d "$output_dir" ] || fail "output directory does not exist: $output_dir"

# Monitoring output can reveal usage times. Keep newly created files private by default.
umask 077

if [ ! -f "$output_file" ]; then
  printf '%s\n' 'timestamp,elapsed_seconds,battery_percent,battery_state,external_power,replayd_cpu,windowserver_cpu,chatgpt_cpu,sky_computer_use_cpu,codex_cpu,pet_retry_count,pet_retry_delta,alert' > "$output_file" || fail "cannot write output: $output_file"
fi

stop_monitor() {
  if [ "$quiet" -eq 0 ]; then
    printf '\nStopped after %s sample(s). CSV: %s\n' "$sample_count" "$output_file"
  fi
  exit 0
}

trap stop_monitor INT TERM

count_pet_retries() {
  log_directory="$HOME/Library/Logs/com.openai.codex/$(date '+%Y/%m/%d')"
  total=0

  [ -d "$log_directory" ] || {
    printf '0'
    return
  }

  while IFS= read -r log_file; do
    [ -f "$log_file" ] || continue
    count="$(awk '/Native pet composition recovery scheduled/{count++} END{print count + 0}' "$log_file" 2>/dev/null)"
    total=$((total + count))
  done <<EOF
$(find "$log_directory" -type f -name '*.log' -print 2>/dev/null)
EOF

  printf '%s' "$total"
}

collect_process_cpu() {
  # comm= avoids collecting command arguments, which can contain sensitive text.
  process_list="$(ps -axo %cpu=,comm= 2>/dev/null)" || return 1
  printf '%s\n' "$process_list" | awk '
    {
      cpu = $1 + 0
      process = $0
      sub(/^[[:space:]]*[0-9.]+[[:space:]]+/, "", process)

      if (process ~ /(^|\/)replayd$/) replayd += cpu
      if (process ~ /(^|\/)WindowServer$/) windowserver += cpu
      if (process ~ /(^|\/)ChatGPT$/) chatgpt += cpu
      if (process ~ /SkyComputerUseService$/) sky += cpu
      if (process ~ /Codex \(Service\)$/ || process ~ /Codex \(Renderer\)$/) codex += cpu
    }
    END {
      printf "%.1f %.1f %.1f %.1f %.1f", replayd, windowserver, chatgpt, sky, codex
    }
  '
}

if [ "$quiet" -eq 0 ]; then
  printf 'Monitoring every %ss; replayd alert threshold: %s%%\n' "$interval" "$threshold"
  printf 'CSV: %s\n' "$output_file"
  [ "$scan_logs" -eq 1 ] || printf 'Codex log scanning is disabled.\n'
  [ "$show_wall_clock" -eq 1 ] || printf 'Wall-clock timestamps are disabled.\n'
  printf 'Press Ctrl+C to stop.\n\n'
fi

while :; do
  now_epoch="$(date +%s)"
  elapsed_seconds=$((now_epoch - start_epoch))

  if [ "$show_wall_clock" -eq 1 ]; then
    timestamp="$(date '+%Y-%m-%dT%H:%M:%S%z')"
  else
    timestamp=""
  fi

  battery_line="$(pmset -g batt | tail -n 1)"
  battery_percent="$(printf '%s\n' "$battery_line" | sed -E 's/.*[[:space:]]([0-9]+)%.*/\1/')"
  battery_state="$(printf '%s\n' "$battery_line" | awk -F';' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}')"

  external_power="$(ioreg -r -n AppleSmartBattery -w0 | awk -F'= ' '/"ExternalConnected"/{gsub(/[ "\r]/, "", $2); print $2; exit}')"
  [ -n "$external_power" ] || external_power="Unknown"

  cpu_values="$(collect_process_cpu)" || fail "macOS denied access to the process list"
  # shellcheck disable=SC2086
  set -- $cpu_values
  replayd_cpu=$1
  windowserver_cpu=$2
  chatgpt_cpu=$3
  sky_cpu=$4
  codex_cpu=$5

  if [ "$scan_logs" -eq 1 ]; then
    pet_retries="$(count_pet_retries)"
  else
    pet_retries=-1
  fi

  pet_delta=0
  if [ "$pet_retries" -ge 0 ] && [ "$previous_retries" -ge 0 ] && [ "$pet_retries" -ge "$previous_retries" ]; then
    pet_delta=$((pet_retries - previous_retries))
  fi

  replayd_whole="${replayd_cpu%%.*}"
  alert="none"
  if [ "$replayd_whole" -ge "$threshold" ] && [ "$pet_delta" -gt 0 ]; then
    alert="high_replayd_with_pet_retries"
  elif [ "$replayd_whole" -ge "$threshold" ]; then
    alert="high_replayd"
  fi

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$timestamp" "$elapsed_seconds" "$battery_percent" "$battery_state" "$external_power" \
    "$replayd_cpu" "$windowserver_cpu" "$chatgpt_cpu" "$sky_cpu" "$codex_cpu" \
    "$pet_retries" "$pet_delta" "$alert" >> "$output_file" || fail "failed to append to $output_file"

  sample_count=$((sample_count + 1))

  if [ "$quiet" -eq 0 ]; then
    display_time="$timestamp"
    [ -n "$display_time" ] || display_time="elapsed=${elapsed_seconds}s"
    printf '%s battery=%s%% %-11s external=%-7s replayd=%5.1f%% WindowServer=%5.1f%% ChatGPT=%5.1f%% SkyCU=%5.1f%% Codex=%5.1f%% retries=%s (+%s) alert=%s\n' \
      "$display_time" "$battery_percent" "$battery_state" "$external_power" \
      "$replayd_cpu" "$windowserver_cpu" "$chatgpt_cpu" "$sky_cpu" "$codex_cpu" \
      "$pet_retries" "$pet_delta" "$alert"
  fi

  if [ "$pet_retries" -ge 0 ]; then
    previous_retries=$pet_retries
  fi

  if [ "$sample_limit" -gt 0 ] && [ "$sample_count" -ge "$sample_limit" ]; then
    break
  fi

  sleep "$interval"
done

if [ "$quiet" -eq 0 ]; then
  printf '\nCompleted %s sample(s). CSV: %s\n' "$sample_count" "$output_file"
fi

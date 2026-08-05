#!/bin/bash

set -eu

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
monitor="$project_dir/codex-battery-monitor.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

printf 'Checking Bash syntax...\n'
bash -n "$monitor" || fail "Bash syntax check failed"

printf 'Checking help output...\n'
"$monitor" --help | grep -q 'Usage:' || fail "help output is missing Usage"

printf 'Checking version output...\n'
"$monitor" --version | grep -q 'codex-battery-monitor' || fail "version output is invalid"

printf 'Checking invalid interval handling...\n'
if "$monitor" --interval 1 --once >/dev/null 2>&1; then
  fail "an interval below five seconds was accepted"
fi

printf 'Checking for hardcoded macOS user paths...\n'
hardcoded_user_path_pattern="/""Users/[[:alnum:]_.-]+"
if grep -R -n -E "$hardcoded_user_path_pattern" "$project_dir" --exclude-dir=.git; then
  fail "a hardcoded macOS user path was found"
fi

if [ "$(uname -s)" = "Darwin" ]; then
  printf 'Running one macOS sample...\n'
  temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/codex-battery-monitor-test.XXXXXX")"
  trap 'rm -rf "$temporary_directory"' EXIT
  sample_csv="$temporary_directory/sample.csv"

  "$monitor" --once --quiet --no-log-scan --no-wall-clock --output "$sample_csv"

  [ -f "$sample_csv" ] || fail "sample CSV was not created"
  line_count="$(awk 'END{print NR}' "$sample_csv")"
  [ "$line_count" -eq 2 ] || fail "sample CSV should contain a header and one data row"
  awk -F, 'NR == 2 && NF == 13 {valid=1} END{exit !valid}' "$sample_csv" || fail "sample CSV schema is invalid"
else
  printf 'Skipping runtime sample: macOS is required.\n'
fi

printf 'PASS: all smoke tests succeeded.\n'

#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: 2026 Anastasiia-alps-lab
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Testing without Claude Code: writes a state file with the given percentage.
#
#   ./taksa-test.sh 75          # five_hour = 75
#   ./taksa-test.sh 75 20       # five_hour = 75, seven_day = 20
#   ./taksa-test.sh crawl       # walk 0 -> 100 in steps of 10
#   ./taksa-test.sh off         # park the test file, keeping its value
#   ./taksa-test.sh on          # bring it back
#   ./taksa-test.sh clear       # delete the test file (back to real data)
#
# The test file is written with "override": true, so it wins over
# claude-code.json — ./taksa-test.sh 0 really does send the dog to the
# bottom-left corner even when live data says otherwise.

set -euo pipefail
export LC_ALL=C

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/taksa"
STATE_FILE="$STATE_DIR/test.json"
# The extension only reads *.json, so a "disabled" test file simply sits next to
# the others under a different suffix: the value is kept but ignored.
OFF_FILE="$STATE_FILE.off"

usage() {
    printf 'usage: %s <percent 0..100> [seven_day_percent] | clear | crawl | off | on\n' \
        "$(basename "$0")" >&2
    exit 1
}

write_state() {
    local five="$1" seven="$2" now tmp
    now="$(date +%s)"
    mkdir -p "$STATE_DIR"
    tmp="$(mktemp "$STATE_DIR/.test.XXXXXX")"
    cat > "$tmp" <<EOF
{
  "source": "test",
  "override": true,
  "five_hour": $five,
  "seven_day": $seven,
  "resets_at": $((now + 3600)),
  "updated_at": $now
}
EOF
    mv -f "$tmp" "$STATE_FILE"
    rm -f "$OFF_FILE"
    printf 'taksa: %s -> five_hour=%s seven_day=%s\n' "$STATE_FILE" "$five" "$seven"
}

[ $# -ge 1 ] || usage

case "$1" in
    off)
        if [ -f "$STATE_FILE" ]; then
            mv -f "$STATE_FILE" "$OFF_FILE"
            printf 'taksa: test file parked -> %s\n' "$OFF_FILE"
        else
            printf 'taksa: no active test file\n'
        fi
        exit 0
        ;;
    on)
        if [ -f "$OFF_FILE" ]; then
            mv -f "$OFF_FILE" "$STATE_FILE"
            printf 'taksa: test file restored -> %s\n' "$STATE_FILE"
        else
            printf 'taksa: no parked test file (%s)\n' "$OFF_FILE" >&2
            exit 1
        fi
        exit 0
        ;;
    clear)
        rm -f "$STATE_FILE" "$OFF_FILE"
        printf 'taksa: %s removed\n' "$STATE_FILE"
        exit 0
        ;;
    crawl)
        for p in 0 10 20 30 40 50 60 70 80 90 100; do
            write_state "$p" 0
            sleep 3
        done
        exit 0
        ;;
esac

[[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]] || usage
five="$1"
seven="${2:-0}"
[[ "$seven" =~ ^[0-9]+([.][0-9]+)?$ ]] || usage

write_state "$five" "$seven"

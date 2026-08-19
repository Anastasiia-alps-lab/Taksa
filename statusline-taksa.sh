#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: 2026 Anastasiia-alps-lab
# SPDX-License-Identifier: GPL-3.0-or-later
#
# statusLine hook for Claude Code.
#
# Reads the session JSON on stdin and prints a status line for the terminal on
# stdout. As a side effect it atomically writes the state file the GNOME
# extension reads (~/.local/state/taksa/claude-code.json).
#
# Wire it up in ~/.claude/settings.json:
#   "statusLine": { "type": "command", "command": "~/.local/bin/statusline-taksa.sh" }

set -uo pipefail

# Keep number parsing and formatting locale independent: printf '%.0f' would
# stop at the dot under a locale that expects a decimal comma.
export LC_ALL=C

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/taksa"
STATE_FILE="$STATE_DIR/claude-code.json"

input="$(cat)"

# A missing jq must not break the status line — Claude Code shows whatever the
# hook prints, so say what is wrong instead of failing silently.
if ! command -v jq >/dev/null 2>&1; then
    printf '🐕 taksa: jq is required\n'
    exit 0
fi

mkdir -p "$STATE_DIR"

parsed="$(printf '%s' "$input" | jq -r '
    def n: if type == "number" then tostring else "null" end;
    [ (try .rate_limits.five_hour.used_percentage catch null | n),
      (try .rate_limits.seven_day.used_percentage catch null | n),
      (try .rate_limits.five_hour.resets_at catch null
         | if . == null then "null" else tostring end),
      (try (.model.display_name // "") catch ""),
      (try (.workspace.current_dir // .cwd // "") catch "")
    ] | join("\u001f")
' 2>/dev/null)" || parsed=""

if [ -z "$parsed" ]; then
    printf '🐕 taksa: unparseable input\n'
    exit 0
fi

# The fields are joined with US (0x1f), not a tab: read collapses runs of IFS
# whitespace, so an empty model would swallow the cwd that follows it.
IFS=$'\x1f' read -r five seven resets model cwd <<<"$parsed"

# resets_at may arrive as an epoch or as an ISO string.
resets_epoch=null
if [ "$resets" != "null" ] && [ -n "$resets" ]; then
    if [[ "$resets" =~ ^[0-9]+$ ]]; then
        resets_epoch="$resets"
    else
        resets_epoch="$(date -d "$resets" +%s 2>/dev/null || echo null)"
    fi
fi

now="$(date +%s)"

# A fresh session calls statusLine before the first request, so the JSON has no
# rate_limits yet. Overwriting the file with that empty snapshot would make the
# extension forget the last known percentage. Leave the file alone and reuse the
# previous values for the terminal line.
if [ "$five" = "null" ] && [ "$seven" = "null" ]; then
    prev=""
    if [ -f "$STATE_FILE" ]; then
        prev="$(jq -r '
            def n: if type == "number" then tostring else "null" end;
            [(.five_hour | n), (.seven_day | n), (.resets_at | n)] | @tsv
        ' "$STATE_FILE" 2>/dev/null)" || prev=""
    fi
    if [ -n "$prev" ]; then
        IFS=$'\t' read -r five seven resets_epoch <<<"$prev"
    fi
    : "${five:=null}" "${seven:=null}" "${resets_epoch:=null}"
else
    # --- atomic write of the state file ---
    tmp="$(mktemp "$STATE_DIR/.claude-code.XXXXXX")"
    jq -n \
        --argjson five "$five" \
        --argjson seven "$seven" \
        --argjson resets "$resets_epoch" \
        --argjson now "$now" \
        '{source: "claude-code",
          five_hour: $five,
          seven_day: $seven,
          resets_at: $resets,
          updated_at: $now}' > "$tmp" 2>/dev/null \
        && mv -f "$tmp" "$STATE_FILE" \
        || rm -f "$tmp"
fi

# --- the terminal line ---
fmt() {  # 63.4 -> 63%
    case "$1" in
        ''|null) printf '—'; return ;;
    esac
    printf '%.0f%%' "$1"
}

line="🐕 5h $(fmt "$five") · 7d $(fmt "$seven")"

if [ "$resets_epoch" != "null" ]; then
    line="$line · resets $(date -d "@$resets_epoch" +%H:%M 2>/dev/null || echo '?')"
fi

[ -n "$model" ] && line="$line · $model"
[ -n "$cwd" ] && line="$line · ${cwd/#$HOME/\~}"

printf '%s\n' "$line"

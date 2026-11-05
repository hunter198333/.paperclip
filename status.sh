#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# status.sh — one screen: where the company stands right now.
#
#   bash .paperclip/status.sh
# ---------------------------------------------------------------------------
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export BUSINESS_ROOT="${BUSINESS_ROOT:-$ROOT}"
LIB="$ROOT/.paperclip/lib"

if [ -f "$ROOT/.paperclip/paperclip.env" ]; then
  set -a; . "$ROOT/.paperclip/paperclip.env"; set +a
fi
PAPERCLIP_API_URL="${PAPERCLIP_API_URL:-http://127.0.0.1:3100}"
export PAPERCLIP_API_URL

if command -v paperclipai >/dev/null 2>&1; then
  PC=(paperclipai)
elif command -v npx >/dev/null 2>&1; then
  PC=(npx --yes paperclipai)
else
  echo "Paperclip CLI not found. Install with: npx paperclipai install" >&2
  exit 1
fi

COMPANY_ID="${PAPERCLIP_COMPANY_ID:-}"
if [ -z "$COMPANY_ID" ]; then
  COMPANY_ID=$("${PC[@]}" company list --json 2>/dev/null | node "$LIB/jqlite.cjs" 'j.items?.[0]?.id ?? j[0]?.id ?? ""')
fi
if [ -z "$COMPANY_ID" ]; then
  echo "No company found. Run: bash .paperclip/bootstrap.sh" >&2
  exit 1
fi

echo "Company : $COMPANY_ID"
echo "Board   : $PAPERCLIP_API_URL"
if [ -f "$ROOT/.paperclip/trading.mode" ]; then
  MODE=$(head -n 1 "$ROOT/.paperclip/trading.mode" | tr -d '[:space:]')
  if [ "$MODE" = "live" ]; then
    echo "Mode    : \033[41;97m LIVE \033[0m  ← real orders are possible"
  else
    echo "Mode    : paper (safe)"
  fi
fi
echo

echo "── Agents ──────────────────────────────────────────────"
"${PC[@]}" agent list --company-id "$COMPANY_ID" 2>/dev/null || echo "  (could not list agents)"
echo

echo "── Open issues ─────────────────────────────────────────"
"${PC[@]}" issue list --company-id "$COMPANY_ID" --status todo,in_progress,in_review,blocked 2>/dev/null || echo "  (could not list issues)"
echo

echo "── Recent runs ─────────────────────────────────────────"
"${PC[@]}" run list --company-id "$COMPANY_ID" --limit 10 2>/dev/null || echo "  (could not list runs)"
echo

echo "── Local workspaces ────────────────────────────────────"
for d in "$ROOT"/workspaces/*/; do
  [ -d "$d" ] || continue
  name=$(basename "$d")
  if [ -d "$d/.git" ]; then
    branch=$(git -C "$d" branch --show-current 2>/dev/null)
    dirty=$(git -C "$d" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    printf '  %-10s git · branch %s · %s uncommitted\n' "$name" "${branch:-?}" "$dirty"
  else
    printf '  %-10s not a git repo — run: bash scripts/git-init.sh\n' "$name"
  fi
done

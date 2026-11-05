#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# wake.sh — wake one agent, optionally pointed at a specific issue.
#
#   bash .paperclip/wake.sh builder --reason "Fix the signup 422"
#   bash .paperclip/wake.sh ceo --reason "Plan week 1" --issue PC-3
#   bash .paperclip/wake.sh researcher --reason "Price up 3 competitors"
#
# Requires: Paperclip running, and .paperclip/agent-ids.json (created by bootstrap.sh).
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

AGENT=""
REASON=""
ISSUE=""
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --reason) REASON="${2:-}"; shift 2 ;;
    --issue)  ISSUE="${2:-}";  shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) if [ -z "$AGENT" ]; then AGENT="$1"; shift; else echo "unexpected arg: $1" >&2; exit 2; fi ;;
  esac
done

if [ -z "$AGENT" ]; then
  echo "usage: bash .paperclip/wake.sh <agent> [--reason \"...\"] [--issue PC-12]" >&2
  echo "agents:" >&2
  node -e 'const c=require(process.env.BUSINESS_ROOT+"/.paperclip/business.config.json");c.agents.forEach(a=>console.log("  "+a.shortname.padEnd(12)+a.name+" — "+a.title))' >&2
  exit 2
fi

if command -v paperclipai >/dev/null 2>&1; then
  PC=(paperclipai)
elif command -v npx >/dev/null 2>&1; then
  PC=(npx --yes paperclipai)
else
  echo "Paperclip CLI not found. Install with: npx paperclipai install" >&2
  exit 1
fi

# company id
COMPANY_ID="${PAPERCLIP_COMPANY_ID:-}"
if [ -z "$COMPANY_ID" ]; then
  COMPANY_ID=$("${PC[@]}" company list --json 2>/dev/null | node "$LIB/jqlite.cjs" 'j.items?.[0]?.id ?? j[0]?.id ?? ""')
fi
if [ -z "$COMPANY_ID" ]; then
  echo "No company id. Run: bash .paperclip/bootstrap.sh" >&2
  exit 1
fi

# agent id (prefer the local map, fall back to the shortname)
AGENT_ID=""
if [ -f "$ROOT/.paperclip/agent-ids.json" ]; then
  AGENT_ID=$(node -e '
    const fs=require("fs");
    const m=JSON.parse(fs.readFileSync(process.env.BUSINESS_ROOT+"/.paperclip/agent-ids.json","utf8"));
    const a=(m.agents||{})[process.argv[1]];
    if(a) process.stdout.write(a);
  ' "$AGENT" 2>/dev/null)
fi
[ -z "$AGENT_ID" ] && AGENT_ID="$AGENT"

# issue id (accept a UUID or an identifier like PC-12)
PAYLOAD=""
if [ -n "$ISSUE" ]; then
  PAYLOAD="--payload"
  ISSUE_JSON=$(node -e 'process.stdout.write(JSON.stringify({issueId:process.argv[1]}))' "$ISSUE")
fi

CMD=("${PC[@]}" agent wake "$AGENT_ID" --company-id "$COMPANY_ID")
[ -n "$REASON" ] && CMD+=(--reason "$REASON")
[ -n "$ISSUE" ] && CMD+=(--payload "$ISSUE_JSON")

if [ "$DRY_RUN" -eq 1 ]; then
  printf '%q ' "${CMD[@]}"; echo
  exit 0
fi

echo "→ waking '$AGENT'${REASON:+ — $REASON}${ISSUE:+ (issue $ISSUE)}"
"${CMD[@]}"

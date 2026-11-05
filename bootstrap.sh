#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# bootstrap.sh — register this business with a running Paperclip instance.
#
# Creates (or reuses): company -> goals -> projects -> project workspaces -> agents
# Then points each agent at its AGENTS.md instruction file.
#
# Safe to re-run: everything is looked up by name first and only created if missing.
#
#   bash .paperclip/bootstrap.sh                # wire everything up
#   bash .paperclip/bootstrap.sh --dry-run      # print what it would do
#   bash .paperclip/bootstrap.sh --with-skills  # also install the paperclip/github agent skills
# ---------------------------------------------------------------------------
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export BUSINESS_ROOT="${BUSINESS_ROOT:-$ROOT}"
LIB="$ROOT/.paperclip/lib"
DRY_RUN=0
WITH_SKILLS=0
FAILED=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --with-skills) WITH_SKILLS=1 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

# --- load local env ---------------------------------------------------------
if [ -f "$ROOT/.paperclip/paperclip.env" ]; then
  set -a; . "$ROOT/.paperclip/paperclip.env"; set +a
  echo "→ loaded .paperclip/paperclip.env"
fi

PAPERCLIP_API_URL="${PAPERCLIP_API_URL:-http://127.0.0.1:3100}"
export PAPERCLIP_API_URL

say()  { printf '%s\n' "$*"; }
step() { printf '\n\033[1m▸ %s\033[0m\n' "$*"; }
warn() { printf '  ! %s\n' "$*"; }
bad()  { printf '  ✗ %s\n' "$*"; FAILED=$((FAILED + 1)); }
good() { printf '  ✓ %s\n' "$*"; }

# --- resolve the CLI --------------------------------------------------------
if command -v paperclipai >/dev/null 2>&1; then
  PC=(paperclipai)
elif command -v npx >/dev/null 2>&1; then
  PC=(npx --yes paperclipai)
else
  say "Neither 'paperclipai' nor 'npx' is on PATH."
  say "Install the CLI with:  npx paperclipai install"
  exit 1
fi

pc()      { "${PC[@]}" "$@"; }
jq_()    { node "$LIB/jqlite.cjs" "$1"; }
payload() { node "$LIB/build-payload.cjs" "$@"; }
find_id() { node "$LIB/find-by-title.cjs" "$@"; }

say "Paperclip CLI : ${PC[*]}"
say "API URL       : $PAPERCLIP_API_URL"
say "Business root : $BUSINESS_ROOT"

if [ "$DRY_RUN" -eq 1 ]; then
  step "Dry run — here is exactly what would be sent"
  say "company   -> $(payload company)"
  for k in $(node -e 'const c=require(process.env.BUSINESS_ROOT+"/.paperclip/business.config.json");console.log(c.goals.map(g=>g.key).join(" "))'); do
    say "goal      -> $(payload goal "$k")"
  done
  for k in $(node -e 'const c=require(process.env.BUSINESS_ROOT+"/.paperclip/business.config.json");console.log(c.projects.map(p=>p.key).join(" "))'); do
    say "project   -> $(payload project "$k")"
  done
  for k in $(node -e 'const c=require(process.env.BUSINESS_ROOT+"/.paperclip/business.config.json");console.log(c.workspaces.map(w=>w.key).join(" "))'); do
    say "workspace -> $(payload workspace "$k")"
  done
  for k in $(node -e 'const c=require(process.env.BUSINESS_ROOT+"/.paperclip/business.config.json");console.log(c.agents.map(a=>a.key).join(" "))'); do
    say "agent     -> $(payload agent "$k")"
  done
  exit 0
fi

# --- is the server up? ------------------------------------------------------
API_STATUS=$(node -e '
  const u = process.argv[1];
  const c = new AbortController();
  setTimeout(() => c.abort(), 5000);
  fetch(u, { signal: c.signal })
    .then((r) => { console.log(r.status); })
    .catch(() => { console.log("unreachable"); });
' "$PAPERCLIP_API_URL" 2>/dev/null)

if [ "$API_STATUS" = "unreachable" ] || [ -z "$API_STATUS" ]; then
  say "Paperclip isn't answering at $PAPERCLIP_API_URL"
  say "Start it in another terminal with:  npx paperclipai run"
  say "(first time?  npx paperclipai onboard --yes)"
  exit 1
fi
good "Paperclip is up (HTTP $API_STATUS)"

# --- 1. company -------------------------------------------------------------
step "Company"
COMPANY_ID="${PAPERCLIP_COMPANY_ID:-}"
if [ -z "$COMPANY_ID" ]; then
  COMPANY_ID=$(pc company list --json 2>/dev/null | jq_ 'j.items?.[0]?.id ?? j[0]?.id ?? j.companies?.[0]?.id ?? ""')
fi
if [ -z "$COMPANY_ID" ]; then
  say "  no company found — creating one"
  OUT=$(pc company create --payload-json "$(payload company)" --json 2>&1)
  COMPANY_ID=$(printf '%s' "$OUT" | jq_ 'j.id ?? j.company?.id ?? ""' 2>/dev/null)
  if [ -z "$COMPANY_ID" ]; then
    bad "could not create the company. Paperclip said:"
    printf '%s\n' "$OUT" | sed 's/^/    /'
    exit 1
  fi
  good "created company $COMPANY_ID"
else
  good "company $COMPANY_ID"
fi
export PAPERCLIP_COMPANY_ID="$COMPANY_ID"

# --- 2. goals ---------------------------------------------------------------
step "Goals"
GOAL_IDS=()
for KEY in $(node -e 'const c=require(process.env.BUSINESS_ROOT+"/.paperclip/business.config.json");console.log(c.goals.map(g=>g.key).join(" "))'); do
  TITLE=$(node -e 'const c=require(process.env.BUSINESS_ROOT+"/.paperclip/business.config.json");console.log(c.goals.find(g=>g.key===process.argv[1]).title)' "$KEY")
  GID=$(pc goal list --company-id "$COMPANY_ID" --json 2>/dev/null | find_id "$TITLE" title)
  if [ -z "$GID" ]; then
    OUT=$(pc goal create --company-id "$COMPANY_ID" --payload-json "$(payload goal "$KEY")" --json 2>&1)
    GID=$(printf '%s' "$OUT" | jq_ 'j.id ?? j.goal?.id ?? ""' 2>/dev/null)
    if [ -z "$GID" ]; then
      bad "goal '$TITLE' — $(printf '%s' "$OUT" | head -3 | tr '\n' ' ')"
      continue
    fi
    good "created goal '$TITLE'"
  else
    good "goal '$TITLE' exists"
  fi
  GOAL_IDS+=("$GID")
done
GOAL_CSV=$(IFS=,; echo "${GOAL_IDS[*]}")

# --- 3. projects + workspaces ----------------------------------------------
step "Projects and workspaces"
for KEY in $(node -e 'const c=require(process.env.BUSINESS_ROOT+"/.paperclip/business.config.json");console.log(c.projects.map(p=>p.key).join(" "))'); do
  PNAME=$(node -e 'const c=require(process.env.BUSINESS_ROOT+"/.paperclip/business.config.json");console.log(c.projects.find(p=>p.key===process.argv[1]).name)' "$KEY")
  PID=$(pc project list --company-id "$COMPANY_ID" --json 2>/dev/null | find_id "$PNAME" name)
  if [ -z "$PID" ]; then
    OUT=$(pc project create --company-id "$COMPANY_ID" \
      --name "$PNAME" \
      --description "$(node -e 'const c=require(process.env.BUSINESS_ROOT+"/.paperclip/business.config.json");console.log(c.projects.find(p=>p.key===process.argv[1]).description)' "$KEY")" \
      --status planned \
      --goal-ids "$GOAL_CSV" \
      --execution-workspace-policy-json "$(payload project "$KEY" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);process.stdout.write(JSON.stringify(j.executionWorkspacePolicy))})')" \
      --json 2>&1)
    PID=$(printf '%s' "$OUT" | jq_ 'j.id ?? j.project?.id ?? ""' 2>/dev/null)
    if [ -z "$PID" ]; then
      bad "project '$PNAME' — $(printf '%s' "$OUT" | head -3 | tr '\n' ' ')"
      continue
    fi
    good "created project '$PNAME'"
  else
    good "project '$PNAME' exists"
  fi

  # execution workspace policy (safe to re-apply)
  pc project update "$PID" \
    --execution-workspace-policy-json "$(payload project "$KEY" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);process.stdout.write(JSON.stringify(j.executionWorkspacePolicy))})')" \
    >/dev/null 2>&1 && good "execution policy set on '$PNAME'" || warn "could not set execution policy on '$PNAME' (may already be identical)"

  # workspaces for this project
  for WKEY in $(node -e 'const c=require(process.env.BUSINESS_ROOT+"/.paperclip/business.config.json");const p=c.projects.find(p=>p.key===process.argv[1]);console.log((p.workspaceKeys||[]).join(" "))' "$KEY"); do
    WNAME=$(node -e 'const c=require(process.env.BUSINESS_ROOT+"/.paperclip/business.config.json");console.log(c.workspaces.find(w=>w.key===process.argv[1]).name)' "$WKEY")
    WID=$(pc project-workspace list "$PID" --json 2>/dev/null | find_id "$WNAME" name)
    if [ -z "$WID" ]; then
      OUT=$(pc project-workspace create "$PID" --payload-json "$(payload workspace "$WKEY")" --json 2>&1)
      WID=$(printf '%s' "$OUT" | jq_ 'j.id ?? j.workspace?.id ?? ""' 2>/dev/null)
      if [ -z "$WID" ]; then
        bad "workspace '$WNAME' — $(printf '%s' "$OUT" | head -3 | tr '\n' ' ')"
        continue
      fi
      good "created workspace '$WNAME' -> $(payload workspace "$WKEY" | jq_ 'j.cwd')"
    else
      good "workspace '$WNAME' exists"
    fi
  done
done

# --- 4. agents --------------------------------------------------------------
step "Agents"
MAP='{"updated":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'","agents":{'
first=1
for KEY in $(node -e 'const c=require(process.env.BUSINESS_ROOT+"/.paperclip/business.config.json");console.log(c.agents.map(a=>a.key).join(" "))'); do
  ANAME=$(node -e 'const c=require(process.env.BUSINESS_ROOT+"/.paperclip/business.config.json");console.log(c.agents.find(a=>a.key===process.argv[1]).name)' "$KEY")
  AID=$(pc agent list --company-id "$COMPANY_ID" --json 2>/dev/null | find_id "$ANAME" name)
  if [ -z "$AID" ]; then
    OUT=$(pc agent create --company-id "$COMPANY_ID" --payload-json "$(payload agent "$KEY")" --json 2>&1)
    AID=$(printf '%s' "$OUT" | jq_ 'j.id ?? j.agent?.id ?? ""' 2>/dev/null)
    if [ -z "$AID" ]; then
      # retry without adapterConfig — older/newer schema variance
      OUT=$(pc agent create --company-id "$COMPANY_ID" \
        --payload-json "$(payload agent "$KEY" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);delete j.adapterConfig;process.stdout.write(JSON.stringify(j))})')" \
        --json 2>&1)
      AID=$(printf '%s' "$OUT" | jq_ 'j.id ?? j.agent?.id ?? ""' 2>/dev/null)
      if [ -z "$AID" ]; then
        bad "agent '$ANAME' — $(printf '%s' "$OUT" | head -3 | tr '\n' ' ')"
        continue
      fi
      warn "agent '$ANAME' created without adapterConfig — set cwd/timeouts in the UI (Agents -> $ANAME -> Configuration)"
    fi
    good "created agent '$ANAME'"
  else
    good "agent '$ANAME' exists"
  fi

  # point the agent at its instruction file
  IPATH=$(node -e 'const c=require(process.env.BUSINESS_ROOT+"/.paperclip/business.config.json");console.log(c.agents.find(a=>a.key===process.argv[1]).instructionsPath)' "$KEY" | sed "s|\$BUSINESS_ROOT|$BUSINESS_ROOT|g")
  if pc agent instructions-path:update "$AID" --payload-json "{\"path\":\"$IPATH\"}" >/dev/null 2>&1; then
    good "instructions -> $IPATH"
  else
    warn "could not set instructions path for '$ANAME' — set it in the UI (Agents -> $ANAME -> Instructions)"
  fi

  if [ "$WITH_SKILLS" -eq 1 ]; then
    pc agent skills:sync "$AID" --desired-skills paperclip,github --mode add >/dev/null 2>&1 \
      && good "skills synced for '$ANAME'" \
      || warn "skills sync failed for '$ANAME' (no ~/.claude or ~/.codex on this device?)"
  fi

  if [ "$first" -eq 0 ]; then MAP="$MAP,"; fi
  first=0
  MAP="$MAP\"$KEY\":\"$AID\""
done
MAP="$MAP}}"
printf '%s' "$MAP" > "$ROOT/.paperclip/agent-ids.json"
good "wrote .paperclip/agent-ids.json"

# --- 5. next steps ----------------------------------------------------------
step "Done"
cat <<EOF

Company : $COMPANY_ID
Board   : $PAPERCLIP_API_URL
Root    : $BUSINESS_ROOT

Next:
  1. Fill in the business:      nano $ROOT/docs/business-brief.md
  2. Init the workspace repos:  bash $ROOT/scripts/git-init.sh
  3. Check everything:          bash $ROOT/scripts/doctor.sh
  4. Wake your first agent:
       bash $ROOT/.paperclip/wake.sh ceo --reason "Plan the first 30 days"

EOF

if [ "$FAILED" -gt 0 ]; then
  say "$FAILED step(s) failed — see the ✗ lines above."
  exit 1
fi
say "Everything wired up. Now fill in docs/business-brief.md — it's the file your agents read first."

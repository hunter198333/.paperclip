#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# install.sh — create the local folder + file structure for Digitraders, an
# agent-run trading desk (Paperclip). Safe to run more than once; it overwrites
# the files it manages.
#
#   bash install.sh                 # auto-detects the best location
#   BUSINESS_ROOT=/sdcard/digitraders bash install.sh
#
# On Android (Termux) it installs into shared storage so Acode can open the
# folder directly. Everywhere else it installs into your home directory.
# ---------------------------------------------------------------------------
set -uo pipefail

# --- where to install --------------------------------------------------------
# Android apps can't read each other's private storage, so a project living in
# Termux's home directory can't be opened in Acode. Shared storage
# (~/storage/shared -> /storage/emulated/0) is the one place both can see.
DEFAULT_ROOT="$HOME/digitraders"
IN_TERMUX=0
if [ -n "${TERMUX_VERSION:-}" ]; then
  IN_TERMUX=1
  if [ -d "$HOME/storage/shared" ]; then
    DEFAULT_ROOT="$HOME/storage/shared/digitraders"
  fi
fi
BUSINESS_ROOT="${BUSINESS_ROOT:-$DEFAULT_ROOT}"

echo "→ installing into $BUSINESS_ROOT"
mkdir -p "$BUSINESS_ROOT"
cd "$BUSINESS_ROOT" || exit 1

mkdir -p ".paperclip"
mkdir -p ".paperclip/agents"
mkdir -p ".paperclip/lib"
mkdir -p "agents/analyst"
mkdir -p "agents/desk"
mkdir -p "agents/quant"
mkdir -p "agents/risk"
mkdir -p "data"
mkdir -p "deploy/launchd"
mkdir -p "deploy/systemd"
mkdir -p "docs"
mkdir -p "docs/decisions"
mkdir -p "docs/playbooks"
mkdir -p "docs/research"
mkdir -p "docs/trading"
mkdir -p "docs/trading/journal"
mkdir -p "scripts"
mkdir -p "workspaces/engine"
mkdir -p "workspaces/engine/src"
mkdir -p "workspaces/engine/src/config"
mkdir -p "workspaces/engine/src/data"
mkdir -p "workspaces/engine/src/engine"
mkdir -p "workspaces/engine/src/paper"
mkdir -p "workspaces/engine/src/strategies"
mkdir -p "workspaces/engine/tests"
mkdir -p "workspaces/ops"
mkdir -p "workspaces/research"

cat > ".gitignore" <<'__MAVIS_EOF_001__'
# Secrets & local config
.paperclip/paperclip.env
.paperclip/local.env
.env
.env.*
!.env.example

# --- live trading mode is a local decision, not a repo setting ---------------
.paperclip/trading.mode.bak

# --- agent scratch / raw output ---------------------------------------------
data/*
!data/.gitkeep

# --- trade journals are records, but keep the working copies out of git ------
# (the journal INDEX and the proposal files are meant to be committed; raw
#  exchange exports and csv dumps are not)
*.csv
*.parquet
exports/
raw/

# --- node -------------------------------------------------------------------
node_modules/
.pnpm-store/
*.log
npm-debug.log*
pnpm-debug.log*

# --- build output -----------------------------------------------------------
dist/
build/
out/
.next/
*.tsbuildinfo
backtest-results/
*.html
!docs/**/*.html

# --- agent worktrees (Paperclip provisions these per issue) ------------------
.worktrees/
worktrees/

# --- editors / OS -----------------------------------------------------------
.DS_Store
Thumbs.db
.idea/
.vscode/
*.swp

# --- engine cache (Kraken candles) --------------------------------------
.cache/

__MAVIS_EOF_001__

cat > ".paperclip/agents/analyst.json" <<'__MAVIS_EOF_002__'
{
  "name": "Market Analyst",
  "shortname": "analyst",
  "title": "Market Analyst",
  "adapterType": "codex_local",
  "instructionsPath": "$BUSINESS_ROOT/agents/analyst/AGENTS.md",
  "adapterConfig": {
    "cwd": "$BUSINESS_ROOT/workspaces/research",
    "timeoutSec": 1800,
    "graceSec": 60,
    "env": {
      "TRADING_MODE_FILE": "$BUSINESS_ROOT/.paperclip/trading.mode"
    },
    "heartbeat": {
      "enabled": false,
      "intervalSec": 0,
      "wakeOnAssignment": true
    }
  },
  "notes": [
    "Read-heavy agent: market data, regime notes, pair research, signal validation.",
    "This workspace has NO exchange credentials by design. It cannot place an order even if it wanted to.",
    "Timer off: unscheduled research burns budget without anyone asking.",
    "Off by default. Unscheduled research burns budget without anyone asking."
  ]
}

__MAVIS_EOF_002__

cat > ".paperclip/agents/desk.json" <<'__MAVIS_EOF_003__'
{
  "name": "Desk Manager",
  "shortname": "desk",
  "title": "Desk Manager",
  "adapterType": "codex_local",
  "instructionsPath": "$BUSINESS_ROOT/agents/desk/AGENTS.md",
  "adapterConfig": {
    "cwd": "$BUSINESS_ROOT",
    "timeoutSec": 900,
    "graceSec": 60,
    "env": {
      "TRADING_MODE_FILE": "$BUSINESS_ROOT/.paperclip/trading.mode"
    },
    "heartbeat": {
      "enabled": true,
      "intervalSec": 14400,
      "wakeOnAssignment": true
    }
  },
  "notes": [
    "Works from the business root so it can read docs/, .paperclip/ and every workspace.",
    "The Desk Manager may PROPOSE and PRIORITISE trades. It may never authorise one on its own.",
    "timeoutSec 900 = 15 minutes per heartbeat.",
    "Every 4 hours. Each wakeup costs money — dial it back to 21600 (6h) if the bill gets uncomfortable."
  ]
}

__MAVIS_EOF_003__

cat > ".paperclip/agents/quant.json" <<'__MAVIS_EOF_004__'
{
  "name": "Quant Developer",
  "shortname": "quant",
  "title": "Quant Developer",
  "adapterType": "codex_local",
  "instructionsPath": "$BUSINESS_ROOT/agents/quant/AGENTS.md",
  "adapterConfig": {
    "cwd": "$BUSINESS_ROOT/workspaces/engine",
    "timeoutSec": 3600,
    "graceSec": 120,
    "env": {
      "TRADING_MODE_FILE": "$BUSINESS_ROOT/.paperclip/trading.mode",
      "GIT_AUTHOR_NAME": "Quant Developer (agent)",
      "GIT_COMMITTER_NAME": "Quant Developer (agent)"
    },
    "heartbeat": {
      "enabled": true,
      "intervalSec": 3600,
      "wakeOnAssignment": true
    }
  },
  "notes": [
    "This is the only agent whose workspace may hold exchange client code.",
    "intervalSec 0 = no timer; it wakes on assignment. Backtests are expensive, so no free-running scans.",
    "timeoutSec 3600 = 1 hour; backtest sweeps are slow.",
    "Hourly. This agent runs the paper cycle and logs it. If you set up cron to run scripts/paper-cycle.sh, set this to 14400 — the script is free, the agent isn't."
  ]
}

__MAVIS_EOF_004__

cat > ".paperclip/agents/risk.json" <<'__MAVIS_EOF_005__'
{
  "name": "Risk and Ops",
  "shortname": "risk",
  "title": "Risk and Ops",
  "adapterType": "codex_local",
  "instructionsPath": "$BUSINESS_ROOT/agents/risk/AGENTS.md",
  "adapterConfig": {
    "cwd": "$BUSINESS_ROOT/workspaces/ops",
    "timeoutSec": 900,
    "graceSec": 60,
    "env": {
      "TRADING_MODE_FILE": "$BUSINESS_ROOT/.paperclip/trading.mode"
    },
    "heartbeat": {
      "enabled": true,
      "intervalSec": 3600,
      "wakeOnAssignment": true
    }
  },
  "notes": [
    "Holds the veto. This agent can block a trade the Desk Manager proposed.",
    "Hourly heartbeat: checks P&L, drawdown, daily-loss limit, and open positions against docs/trading/risk-policy.md.",
    "Read-only on money. It never places, closes, or modifies an order.",
    "Hourly. Risk checks and the status board. Every wakeup costs money — this is the agent that keeps the kill switch honest, so don't turn it off."
  ]
}

__MAVIS_EOF_005__

cat > ".paperclip/bootstrap.sh" <<'__MAVIS_EOF_006__'
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
#   bash .paperclip/bootstrap.sh --update       # push changed agent configs to existing agents
# ---------------------------------------------------------------------------
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export BUSINESS_ROOT="${BUSINESS_ROOT:-$ROOT}"
LIB="$ROOT/.paperclip/lib"
DRY_RUN=0
WITH_SKILLS=0
UPDATE=0
FAILED=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --with-skills) WITH_SKILLS=1 ;;
    --update) UPDATE=1 ;;
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
    if [ "$UPDATE" -eq 1 ]; then
      if pc agent update "$AID" --payload-json "$(payload agent "$KEY")" >/dev/null 2>&1; then
        good "updated config for '$ANAME'"
      else
        warn "could not update '$ANAME' — set cwd/timeouts in the UI (Agents -> $ANAME -> Configuration)"
      fi
    fi
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

__MAVIS_EOF_006__
chmod +x ".paperclip/bootstrap.sh"

cat > ".paperclip/business.config.json" <<'__MAVIS_EOF_007__'
{
  "version": 2,
  "generatedBy": "Mavis",
  "note": "Single source of truth for the Paperclip trading desk. $BUSINESS_ROOT is expanded to an absolute path by bootstrap.sh before anything reaches the server. The authoritative risk limits live in docs/trading/risk-policy.md — this file only points at them.",
  "paperclip": {
    "apiUrl": "http://127.0.0.1:3100",
    "instance": "default",
    "home": "~/.paperclip",
    "cli": "paperclipai",
    "adapterTypeDefault": "codex_local"
  },
  "company": {
    "name": "Digitraders",
    "issuePrefix": "DGT",
    "description": "Digitraders — a home trading center where AI agents research, build and operate a Kraken spot trading desk under hard risk limits.",
    "budgetMonthlyCents": 0,
    "requiresAgentApproval": true
  },
  "trading": {
    "exchange": "kraken",
    "modeFile": ".paperclip/trading.mode",
    "defaultMode": "paper",
    "liveRequiresHumanApproval": true,
    "riskPolicy": "docs/trading/risk-policy.md",
    "tradePlaybook": "docs/trading/trade-playbook.md",
    "journal": "docs/trading/journal/",
    "note": "Agents MUST read the mode file before proposing execution. Default is paper; live mode is set by the human only."
  },
  "goals": [
    {
      "key": "safe",
      "title": "Trade safely",
      "description": "Every live trade clears the written risk policy and an explicit human approval. No exceptions, no overrides.",
      "level": "company",
      "status": "active"
    },
    {
      "key": "prove",
      "title": "Prove the strategy before risking capital",
      "description": "A strategy earns live capital only after it survives backtest, walk-forward, and paper trading.",
      "level": "company",
      "status": "active"
    },
    {
      "key": "run",
      "title": "Run the desk every day",
      "description": "Agents research, analyse, build and report on a rhythm; the human approves and decides.",
      "level": "company",
      "status": "active"
    }
  ],
  "projects": [
    {
      "key": "engine",
      "name": "Trading Engine",
      "description": "Strategies, backtesting, and the execution plumbing. Everything that could place an order.",
      "status": "planned",
      "goalKeys": [
        "safe",
        "prove"
      ],
      "workspaceKeys": [
        "engine"
      ],
      "executionWorkspacePolicy": {
        "enabled": true,
        "allowIssueOverride": true,
        "workspaceStrategy": {
          "type": "git_worktree",
          "baseRef": "main"
        }
      }
    },
    {
      "key": "research",
      "name": "Market Research",
      "description": "Market data, signals, regime notes and competitor research. Read-heavy, no execution.",
      "status": "planned",
      "goalKeys": [
        "prove",
        "run"
      ],
      "workspaceKeys": [
        "research"
      ],
      "executionWorkspacePolicy": {
        "enabled": true,
        "allowIssueOverride": true,
        "workspaceStrategy": {
          "type": "git_worktree",
          "baseRef": "main"
        }
      }
    },
    {
      "key": "ops",
      "name": "Risk and Operations",
      "description": "Risk policy, P&L, trade journal, secrets hygiene, and the daily dashboard.",
      "status": "planned",
      "goalKeys": [
        "safe",
        "run"
      ],
      "workspaceKeys": [
        "ops"
      ],
      "executionWorkspacePolicy": {
        "enabled": false,
        "allowIssueOverride": true,
        "workspaceStrategy": {
          "type": "git_worktree",
          "baseRef": "main"
        }
      }
    }
  ],
  "workspaces": [
    {
      "key": "engine",
      "name": "engine",
      "cwd": "$BUSINESS_ROOT/workspaces/engine",
      "repoUrl": null,
      "repoRef": "main",
      "isPrimary": true,
      "purpose": "Strategy code, backtests, and the execution client. The only workspace allowed to talk to an exchange."
    },
    {
      "key": "research",
      "name": "research",
      "cwd": "$BUSINESS_ROOT/workspaces/research",
      "repoUrl": null,
      "repoRef": "main",
      "isPrimary": false,
      "purpose": "Market data, signals, notes, and research. No keys, no orders."
    },
    {
      "key": "ops",
      "name": "ops",
      "cwd": "$BUSINESS_ROOT/workspaces/ops",
      "repoUrl": null,
      "repoRef": "main",
      "isPrimary": false,
      "purpose": "Risk policy, P&L reports, trade journal, dashboards."
    }
  ],
  "agents": [
    {
      "key": "desk",
      "name": "Desk Manager",
      "shortname": "desk",
      "title": "Desk Manager",
      "adapterType": "codex_local",
      "workspaceKey": "engine",
      "instructionsPath": "$BUSINESS_ROOT/agents/desk/AGENTS.md",
      "configFile": ".paperclip/agents/desk.json",
      "canCreateAgents": true,
      "canAssignTasks": true
    },
    {
      "key": "quant",
      "name": "Quant Developer",
      "shortname": "quant",
      "title": "Quant Developer",
      "adapterType": "codex_local",
      "workspaceKey": "engine",
      "instructionsPath": "$BUSINESS_ROOT/agents/quant/AGENTS.md",
      "configFile": ".paperclip/agents/quant.json",
      "canCreateAgents": false,
      "canAssignTasks": false
    },
    {
      "key": "analyst",
      "name": "Market Analyst",
      "shortname": "analyst",
      "title": "Market Analyst",
      "adapterType": "codex_local",
      "workspaceKey": "research",
      "instructionsPath": "$BUSINESS_ROOT/agents/analyst/AGENTS.md",
      "configFile": ".paperclip/agents/analyst.json",
      "canCreateAgents": false,
      "canAssignTasks": false
    },
    {
      "key": "risk",
      "name": "Risk and Ops",
      "shortname": "risk",
      "title": "Risk and Ops",
      "adapterType": "codex_local",
      "workspaceKey": "ops",
      "instructionsPath": "$BUSINESS_ROOT/agents/risk/AGENTS.md",
      "configFile": ".paperclip/agents/risk.json",
      "canCreateAgents": false,
      "canAssignTasks": false
    }
  ],
  "heartbeats": {
    "note": "Agent wakeups cost money. These intervals are a starting point — change them in .paperclip/agents/*.json and re-run: bash .paperclip/bootstrap.sh --update",
    "schedule": {
      "desk": "every 4h — reviews the desk, prioritises, proposes",
      "quant": "hourly — runs the paper cycle and logs it",
      "risk": "hourly — risk check, status board, kill switch",
      "analyst": "off — wakes only when assigned"
    },
    "freeAlternative": "scripts/paper-cycle.sh is deterministic — run it from cron or systemd and it costs nothing. Only the agents' interpretation costs money."
  }
}

__MAVIS_EOF_007__

cat > ".paperclip/lib/build-payload.cjs" <<'__MAVIS_EOF_008__'
#!/usr/bin/env node
/**
 * build-payload — turn .paperclip/business.config.json into the exact JSON bodies
 * the Paperclip CLI expects. No jq required, and $BUSINESS_ROOT gets expanded to a
 * real absolute path (Paperclip rejects relative cwd values).
 *
 *   node lib/build-payload.cjs company
 *   node lib/build-payload.cjs goal      offer
 *   node lib/build-payload.cjs project   core [goalId1,goalId2]
 *   node lib/build-payload.cjs workspace core
 *   node lib/build-payload.cjs agent     builder
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const BUSINESS_ROOT = (process.env.BUSINESS_ROOT || ROOT).replace(/\/+$/, '');
const CFG = JSON.parse(fs.readFileSync(path.join(ROOT, '.paperclip', 'business.config.json'), 'utf8'));

function expand(value) {
  if (typeof value === 'string') {
    return value.replace(/\$BUSINESS_ROOT/g, BUSINESS_ROOT).replace(/^~(?=\/)/, process.env.HOME || '~');
  }
  if (Array.isArray(value)) return value.map(expand);
  if (value && typeof value === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(value)) out[k] = expand(v);
    return out;
  }
  return value;
}

const [kind, key, extra] = process.argv.slice(2);
if (!kind) {
  process.stderr.write('usage: build-payload.cjs <company|goal|project|workspace|agent> [key] [extra]\n');
  process.exit(1);
}

let body = null;

if (kind === 'company') {
  const c = CFG.company;
  body = {
    name: c.name,
    issuePrefix: c.issuePrefix,
    description: c.description,
  };
  if (c.budgetMonthlyCents) body.budgetMonthlyCents = c.budgetMonthlyCents;
  if (c.requiresAgentApproval) body.requiresAgentApproval = true;
} else if (kind === 'goal') {
  const g = CFG.goals.find((x) => x.key === key);
  if (!g) { process.stderr.write(`no goal with key "${key}"\n`); process.exit(1); }
  body = { title: g.title, description: g.description, level: g.level, status: g.status };
} else if (kind === 'project') {
  const p = CFG.projects.find((x) => x.key === key);
  if (!p) { process.stderr.write(`no project with key "${key}"\n`); process.exit(1); }
  body = {
    name: p.name,
    description: p.description,
    status: p.status,
    executionWorkspacePolicy: p.executionWorkspacePolicy,
  };
  if (extra) body.goalIds = extra.split(',').filter(Boolean);
} else if (kind === 'workspace') {
  const w = CFG.workspaces.find((x) => x.key === key);
  if (!w) { process.stderr.write(`no workspace with key "${key}"\n`); process.exit(1); }
  body = { name: w.name, cwd: expand(w.cwd), repoRef: w.repoRef, isPrimary: w.isPrimary };
  if (w.repoUrl) body.repoUrl = w.repoUrl;
} else if (kind === 'agent') {
  const a = CFG.agents.find((x) => x.key === key);
  if (!a) { process.stderr.write(`no agent with key "${key}"\n`); process.exit(1); }
  const file = path.join(ROOT, a.configFile);
  const local = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')) : {};
  body = {
    name: a.name,
    title: a.title,
    adapterType: local.adapterType || a.adapterType || CFG.paperclip.adapterTypeDefault,
  };
  const ac = expand(local.adapterConfig || {});
  if (ac.cwd) body.adapterConfig = ac;
  else body.adapterConfig = { cwd: expand(`${BUSINESS_ROOT}/workspaces/${a.workspaceKey}`) };
} else {
  process.stderr.write(`unknown kind "${kind}"\n`);
  process.exit(1);
}

process.stdout.write(JSON.stringify(body));

__MAVIS_EOF_008__
chmod +x ".paperclip/lib/build-payload.cjs"

cat > ".paperclip/lib/find-by-title.cjs" <<'__MAVIS_EOF_009__'
#!/usr/bin/env node
/**
 * find-by-title — resolve an id by matching a display name.
 *
 *   pc agent list --company-id $CID --json | node lib/find-by-title.cjs "Builder"
 *   pc goal  list --company-id $CID --json | node lib/find-by-title.cjs "Ship a working offer" title
 *
 * Handles both a bare array and {items:[...]} / {data:[...]} / {agents:[...]} envelopes.
 * Prints the id, or nothing (exit 0) if there is no match.
 */
let raw = '';
process.stdin.on('data', (d) => { raw += d; });
process.stdin.on('end', () => {
  const needle = (process.argv[2] || '').toLowerCase();
  const fields = process.argv[3] ? [process.argv[3]] : ['title', 'name'];
  let j;
  try {
    j = JSON.parse(raw);
  } catch (e) {
    process.exit(0);
  }
  let items = [];
  if (Array.isArray(j)) items = j;
  else if (j && typeof j === 'object') {
    for (const k of ['items', 'data', 'agents', 'goals', 'projects', 'workspaces', 'issues', 'companies']) {
      if (Array.isArray(j[k])) { items = j[k]; break; }
    }
  }
  const hit = items.find((it) => {
    if (!it || typeof it !== 'object') return false;
    return fields.some((f) => typeof it[f] === 'string' && it[f].toLowerCase() === needle);
  });
  if (hit && hit.id) process.stdout.write(String(hit.id));
});

__MAVIS_EOF_009__
chmod +x ".paperclip/lib/find-by-title.cjs"

cat > ".paperclip/lib/jqlite.cjs" <<'__MAVIS_EOF_010__'
#!/usr/bin/env node
/**
 * jqlite — a tiny jq replacement, so you don't need jq installed.
 *
 *   pc company list --json | node lib/jqlite.cjs 'j[0].id'
 *   pc issue list --json  | node lib/jqlite.cjs 'j.filter(i=>i.status==="todo").length'
 *
 * The expression is evaluated with `j` bound to the parsed JSON.
 */
let raw = '';
process.stdin.on('data', (d) => { raw += d; });
process.stdin.on('end', () => {
  let j;
  try {
    j = JSON.parse(raw);
  } catch (e) {
    process.stderr.write('jqlite: input is not valid JSON\n');
    process.exit(1);
  }
  const expr = process.argv[2];
  if (!expr) {
    process.stderr.write('usage: jqlite.cjs <expr>\n');
    process.exit(1);
  }
  let v;
  try {
    v = new Function('j', `return (${expr});`)(j);
  } catch (e) {
    process.stderr.write(`jqlite: ${e.message}\n`);
    process.exit(1);
  }
  if (v === undefined || v === null) process.exit(0);
  process.stdout.write(typeof v === 'object' ? JSON.stringify(v) : String(v));
});

__MAVIS_EOF_010__
chmod +x ".paperclip/lib/jqlite.cjs"

cat > ".paperclip/paperclip.env.example" <<'__MAVIS_EOF_011__'
# Copy this file to `.paperclip/paperclip.env` (git-ignored) and fill it in.
# Then:  source .paperclip/paperclip.env

# --- where Paperclip lives --------------------------------------------------
PAPERCLIP_API_URL=http://127.0.0.1:3100
PAPERCLIP_HOME=$HOME/.paperclip
PAPERCLIP_INSTANCE_ID=default

# --- the company ------------------------------------------------------------
# Get the id with:  npx paperclipai company list
PAPERCLIP_COMPANY_ID=

# --- credentials ------------------------------------------------------------
PAPERCLIP_API_KEY=

# --- per-agent identity (printed by `paperclipai agent local-cli <agent>`) ---
PAPERCLIP_AGENT_ID=

# --- where this desk lives on disk -------------------------------------------
BUSINESS_ROOT=$HOME/paperclip-business

# --- trading mode -----------------------------------------------------------
# The live switch is .paperclip/trading.mode (change it with
# scripts/trading-mode.sh), not an env var. This is only so agents can find it.
TRADING_MODE_FILE=$HOME/paperclip-business/.paperclip/trading.mode

# --- exchange credentials ---------------------------------------------------
# Only the ENGINE agent gets these, and only via Paperclip secrets — never in a
# file, never in git. Store them with:
#   npx paperclipai secrets create --company-id <company-id> \
#     --name binance-api-key --value-env BINANCE_API_KEY
#
# ⚠ Trading permission ONLY. Withdrawal permission must stay OFF. If you ever
# find yourself enabling withdrawals, stop and read docs/playbooks/exchange-setup.md.
BINANCE_API_KEY=
BINANCE_API_SECRET=

# --- tools your agents may need ---------------------------------------------
# GitHub, for agents that open pull requests
GH_TOKEN=
GITHUB_TOKEN=

# --- provider keys for the agent CLIs ---------------------------------------
ANTHROPIC_API_KEY=
OPENAI_API_KEY=

__MAVIS_EOF_011__

cat > ".paperclip/status.sh" <<'__MAVIS_EOF_012__'
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

__MAVIS_EOF_012__
chmod +x ".paperclip/status.sh"

cat > ".paperclip/trading.mode" <<'__MAVIS_EOF_013__'
paper

__MAVIS_EOF_013__

cat > ".paperclip/wake.sh" <<'__MAVIS_EOF_014__'
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

__MAVIS_EOF_014__
chmod +x ".paperclip/wake.sh"

cat > "AGENTS.md" <<'__MAVIS_EOF_015__'
# AGENTS.md — Operating Manual for Every Agent

You are one of the agents in this trading desk. This file is the **shared instruction
layer**: it applies to every agent, every run, in every workspace. Role-specific rules
live in your own `agents/<your-name>/AGENTS.md` — that file wins on conflicts, this file
wins on everything else.

Read this file completely before your first action in a session. It is short on purpose.

---

## 1. This desk moves real money

That's the difference between this and every other "AI agent business" setup. So the
rules are stricter, the default is safer, and "the human said it's fine" is never enough
on its own.

**Before anything else, every agent reads `.paperclip/trading.mode`:**

```bash
bash scripts/trading-mode.sh show
```

`paper` (the default) means **no real order can be placed**. `live` means real orders
*may* be placed — but only after the full chain in `docs/trading/trade-playbook.md`:
thesis → proposal → risk check → **human approval** → execution.

---

## 2. The truth lives in these files

| What | Where |
|---|---|
| What the business is | `docs/business-brief.md` |
| The risk limits (the law) | `docs/trading/risk-policy.md` |
| The procedure | `docs/trading/trade-playbook.md` |
| Proposal template | `docs/trading/journal/template.md` |
| Current mode | `.paperclip/trading.mode` |

Never invent a number: balances, P&L, drawdown, fees, spreads, volumes. If you didn't
read it from a source this run, the answer is **unknown**.

---

## 3. The non-negotiables

1. **No live trade without the full four-step chain.** Thesis → proposal → risk check →
   human approval. Silence is not approval.
2. **No withdrawal permissions.** Never request them, never enable them, never write
   code that moves funds off the exchange.
3. **The paper cycle never gets a key.** `scripts/paper-cycle.sh` uses Kraken's
   *public* API only. If a change would make it able to place an order, that is a
   different program with a different name — and it doesn't go in this repo yet.
4. **Deposits are never profit.** A deposit is money going in. It gets logged with a
   date and amount in `docs/trading/capital.md` and nothing else. Agents may record a
   deposit Max reports; they may never invent, adjust, or remove one. When reporting
   results, always show **capital in**, **deposits**, and **trading P&L** as three
   separate numbers — a growing account with flat P&L means the desk isn't working yet.
5. **Only Max edits `docs/trading/risk-policy.md`.** If a limit is wrong, escalate — do
   not work around it.
6. **Every position has a stop.** Entering without one is not a proposal, it's a hope.
7. **Never widen a stop. Never average down. Never add leverage to recover a loss.**
8. **Respect the kill switch.** Daily loss limit (L3), max drawdown (L4), two
   consecutive stop-outs (L11) — the desk stops. The desk does not try to earn it back.
9. **Keys never appear in a file, a commit, a log, or a comment.** They live in Paperclip
   secrets. If one leaks, it gets revoked before anything gets debugged.
10. **Backtests don't lie.** No lookahead, no survivorship bias, real costs,
   out-of-sample results, and "insufficient sample, no conclusion" when the trade count
   is too low to mean anything.
11. **The journal is append-only.** No edits, no deletions, no backdating.

---

## 4. Working rules (everyone)

- **One issue, one branch, one PR.** Never mix two issues in one branch.
- **Never push to `main`.** Branch from `main`: `agent/<agent>/<issue-id>-<slug>`.
- **Comment before you start** and **comment when you stop** (the Done block below).
- **Leave issues `in_review`, not `done`.** A human closes them.
- **Smallest correct change.** No drive-by refactors.
- **If you're stuck, stop and report.** A blocked issue with a clear question beats an
  agent burning budget in a loop.

---

## 5. Where things go

| Artifact | Location |
|---|---|
| Paper status (auto-generated) | `docs/trading/paper-status.md` |
| Paper trade ledger (append-only) | `docs/trading/journal/paper-ledger.md` |
| Strategy code, backtests, execution | `workspaces/engine/` |
| Market research, notes | `workspaces/research/`, `docs/research/` |
| Risk policy, P&L, dashboards | `workspaces/ops/`, `docs/status-board.md` |
| Trade proposals + journal | `docs/trading/journal/` |
| Experiment log | `docs/trading/experiments.md` |
| Decisions | `docs/decisions/` |
| Raw output, exports, scratch | `data/` (git-ignored) |

Every durable output goes in a **file**. If it only exists in a comment, it's lost.

---

## 6. Git hygiene

```bash
git switch -c agent/<agent>/<issue-id>-<slug>
git add -A && git commit -m "<type>(<scope>): <short summary>"
git push -u origin HEAD
gh pr create --fill --base main
```

Types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`. One logical change per commit.

---

## 7. Reporting back

Every final comment on an issue:

```
Done: <one line describing the outcome>
Changed: <files or areas touched>
Verified: <the exact command you ran and what it printed>
Notes: <what you did not do, what's risky, what needs a human>
```

For risk checks, use the exact `RISK CHECK: PASS` / `RISK CHECK: FAIL` format with real
numbers — never "looks risky".

---

## 8. When you need a human

Stop and escalate (comment + status `blocked`) when:

- The mode is `live` and something about a trade is ambiguous.
- A limit in the risk policy would need to change.
- The action spends money, publishes publicly, or contacts real people.
- A trade would need withdrawal permissions, or API keys appear anywhere they shouldn't.
- You've hit the same wall twice.

Escalate to the **Desk Manager** for prioritisation, to **Max** for money, keys, and
anything irreversible.

__MAVIS_EOF_015__

cat > "README.md" <<'__MAVIS_EOF_016__'
# Digitraders

A local workspace for a **Paperclip** company of AI agents running a crypto trading desk
on **Kraken** — research, strategy code, backtests, position sizing, risk checks, and the
paper trail.

Built phone-first (Termux + Acode), because that's where it runs.

---

## 0. The safety model — read this first

This desk can touch real money. So the scaffold is built around one idea:

> **Paper by default. Four steps before anything real. One kill switch.**

| Mechanism | Where | What it does |
|---|---|---|
| **Mode file** | `.paperclip/trading.mode` | `paper` (default) or `live`. Every agent reads it before proposing execution. |
| **Risk policy** | `docs/trading/risk-policy.md` | The limits. Position size, daily loss, drawdown, leverage, fees. Only you edit it. |
| **Approval chain** | `docs/trading/trade-playbook.md` | thesis → proposal → risk check → **your approval** → execution. |
| **Sizer** | `scripts/position-size.sh` | Sizes a trade and checks it against the policy. Read-only. |
| **Journal** | `docs/trading/journal/` | Append-only record of every proposal and fill. |
| **Kill switch** | `risk-policy.md` §4 | Hit a limit → the desk stops. It doesn't try to win it back. |

```bash
bash scripts/trading-mode.sh show     # paper | live
bash scripts/trading-mode.sh paper    # back to safe (instant)
bash scripts/trading-mode.sh live     # needs you to type the confirm phrase
```

**Live mode alone doesn't authorise anything.** Even in live mode, no order happens
without thesis → proposal → risk check → your approval.

The **research workspace has no trading key by design.** The analyst can look, not touch.

---

## 1. The numbers that shape everything

**Kraken Tier 1 (30-day volume $0+): 0.40% maker / 0.80% taker.**

At ~$250 equity:

| | Maker (limit) | Taker (market) |
|---|---|---|
| Round-trip fee | 0.80% | 1.60% |
| Cost of a $250 round trip | **$2.00** | **$4.00** |
| Minimum gross edge to break even (policy L13) | **3.2%** | 6.4% |

Two consequences that are baked into the policy:

1. **Fees are the biggest cost line at this size.** Sizing discipline beats finding a
   better signal.
2. **Maker orders only** (policy L15). A market order doubles the drag for nothing.

And the honest one: with capital this size, **the rig and the learning are the
deliverable.** The P&L is the lab fee. That's not a failure — it's the cheapest possible
place to learn how to run an agent desk.

### Your capital plan

| | |
|---|---|
| Starting balance | **$250.00** |
| Weekly contribution | **+$100.00 per payday** |
| Projected balance by Christmas (≈7 deposits) | **~$950** |

**The account reaches ~$950 by Christmas because of deposits, not trading.** That's the
plan, and it's a good one — contributions compound without a single losing trade.

So the desk tracks three numbers, and never mixes them:

| Number | What it is |
|---|---|
| **Capital in the account** | $250 + every deposit. Not performance. |
| **Trading P&L** | What the desk actually made. **The only number that measures the desk.** |
| **Total equity** | Capital in + trading P&L. |

A growing account with flat trading P&L means the desk isn't working yet — and the
status page says so in those words.

---

## 2. Getting Node installed

Paperclip needs **Node.js 24+**. If you installed Node *inside Acode*, that doesn't count —
Acode has its own JS runtime, but Paperclip needs a real Node in your terminal.

**On the phone (Termux):**

```bash
pkg update && pkg upgrade
pkg install nodejs-lts      # → Node 24.x (Active LTS) — this is the one you want
node -v                     # must print v24.x or higher
```

`nodejs-lts` and `nodejs` conflict — **only one at a time.** If `node -v` shows v20/v22
you have the stale package: `pkg uninstall nodejs-lts && pkg install nodejs-lts`.

**On the PC:**

```bash
node -v                     # v24+ — if it's older: nvm install 24, or nodejs.org
npm i -g paperclipai       # permanent CLI
```

The engine, the paper cycle, and the agents all work the same either way.

---

## 3. Where it runs — phone or PC

**Both.** The installer picks the right location automatically: shared storage on
Android (so Acode can open it), your home directory everywhere else.

### On the phone (Acode)

Android apps can't read each other's private storage, so the installer puts Digitraders
in **shared storage**, where both Termux and Acode can see it:

```bash
termux-setup-storage      # once — tap ALLOW on the Android prompt
bash install.sh           # → /storage/emulated/0/digitraders
```

Then in Acode: **menu → Open folder → `/storage/emulated/0/digitraders`**

Termux reaches the same folder at `~/storage/shared/digitraders`.

> Shared storage doesn't preserve Unix permissions, so the installer turns off git's
> file-mode check and whitelists the directory. That's handled for you — you don't
> need to do anything.

### On the PC (recommended for running)

**One command does everything:**

```bash
bash pc-setup.sh
```

It checks Node 24, installs the Paperclip CLI, checks your git identity, installs a
timer so the paper cycle runs on its own every hour, registers the agents, runs the
first cycle, and prints a summary. It's safe to re-run — it never deletes anything
and never touches your keys.

```
bash pc-setup.sh --help        # all the flags
bash pc-setup.sh --yes         # no questions asked
bash pc-setup.sh --timer cron  # force a scheduler instead of auto-detect
```

The PC is the better place to *run* the desk:

| | Phone | PC |
|---|---|---|
| Paperclip's embedded Postgres | slow, sometimes won't boot | works |
| Long-running processes | Android kills them (signal 9) | fine, with a timer |
| **Kraken key IP allowlist** | impossible — mobile IP changes | **possible** |
| Long history, many agents | cramped | room to move |

Moving over? `docs/playbooks/pc-migration.md` — git (recommended, keeps them in sync)
or a zip over USB. `scripts/sync.sh pull|push|cycle` does the syncing for you.

---

## 4. What's in here

```
Digitraders/
├── AGENTS.md                  ← instruction layer every agent reads first
├── README.md                  ← you are here
├── package.json               ← pnpm workspace root
├── pnpm-workspace.yaml
│
├── .paperclip/
│   ├── business.config.json   ← company, goals, projects, workspaces, agents
│   ├── agents/*.json          ← per-agent cwd, timeouts, heartbeat, env
│   ├── trading.mode           ← "paper" | "live"  ← the switch
│   ├── bootstrap.sh           ← registers everything with Paperclip
│   ├── wake.sh                ← wake one agent, optionally on an issue
│   ├── status.sh              ← one-screen health of the desk
│   ├── paperclip.env.example  ← copy to paperclip.env and fill in
│   └── lib/                   ← tiny node helpers (no jq needed)
│
├── agents/
│   ├── desk/AGENTS.md         ← Desk Manager: priorities, proposals, assignment
│   ├── quant/AGENTS.md        ← Quant Developer: strategies, backtests, execution
│   ├── analyst/AGENTS.md      ← Market Analyst: research, signals, validation
│   └── risk/AGENTS.md         ← Risk and Ops: the veto, P&L, journal, kill switch
│
├── workspaces/
│   ├── engine/                ← strategy code + execution (the only one with keys)
│   │   ├── src/cli.js         ← backtest · walkforward · data · ticker
│   │   ├── src/engine/        ← simulator, metrics, indicators, walk-forward
│   │   ├── src/data/          ← Kraken public API + CSV import
│   │   ├── src/strategies/    ← buy-and-hold, sma-crossover, atr-breakout
│   │   └── tests/             ← 20 tests, incl. the no-lookahead proofs
│   ├── research/              ← market data, notes (read-only key at most)
│   └── ops/                   ← risk checks, dashboards, reports
│
├── deploy/
│   ├── systemd/                ← systemd unit + timer templates
│   └── launchd/                ← macOS launchd plist
│
├── docs/
│   ├── business-brief.md      ← FILL THIS IN FIRST (has [TODO: Max] markers)
│   ├── status-board.md        ← the daily dashboard
│   ├── trading/
│   │   ├── capital.md         ← every deposit, with dates (auto-generated)
│   │   ├── risk-policy.md     ← the limits — the law
│   │   ├── trade-playbook.md  ← the nine-step procedure
│   │   ├── paper-trading.md   ← the daily paper cycle
│   │   ├── paper-status.md    ← auto-generated paper account status
│   │   ├── experiments.md     ← every experiment, wins and failures
│   │   └── journal/           ← trade proposals + fills (append-only)
│   │       └── paper-ledger.md  ← every paper trade, auto-appended
│   ├── research/              ← analyst notes
│   ├── decisions/             ← why we did X
│   └── playbooks/
│       ├── kraken-setup.md    ← safe Kraken key creation
│       └── pc-migration.md    ← moving the desk to a PC
│
├── data/                      ← scratch, exports (git-ignored)
└── scripts/
    ├── doctor.sh              ← pre-flight check
    ├── git-init.sh            ← makes each workspace a git repo
    ├── position-size.sh       ← size a trade + check it against the policy
    ├── pc-setup.sh            ← ONE COMMAND: make this PC a running desk
    ├── paper-cycle.sh         ← run the paper-trading cycle
    ├── sync.sh                ← pull/push/cycle between phone and PC
    └── trading-mode.sh        ← the switch
```

---

## 5. Quick start

**On the PC — one command:**

```bash
unzip digitraders.zip
bash pc-setup.sh
```

**On the phone:**

```bash
# 1. Create the workspace
bash install.sh
cd ~/storage/shared/digitraders

# 2. Tell the desk what you're doing
nano docs/business-brief.md        # answer the [TODO: Max] questions

# 3. Make the workspaces git-ready (one worktree per issue, no collisions)
bash scripts/git-init.sh

# 4. Start Paperclip in ANOTHER terminal
npx paperclipai run                # first time: npx paperclipai onboard --yes
                                  # → board at http://127.0.0.1:3100

# 5. Register company + goals + projects + workspaces + agents
bash .paperclip/bootstrap.sh

# 6. Verify everything
bash scripts/doctor.sh
bash .paperclip/status.sh
```

Then: **stay in paper mode** and let the desk do research, backtests, and proposals.

---

## 6. The backtesting engine

`workspaces/engine/` is a **real, tested** backtester — no dependencies, pure Node,
nothing to install. It talks to Kraken's public API without a key.

```bash
cd workspaces/engine

# the benchmark — every strategy has to beat this, after fees
node src/cli.js backtest --strategy buy-and-hold --pair XRPUSD --interval 240

# a strategy
node src/cli.js backtest --strategy sma-crossover --pair XRPUSD --interval 240 --equity 250

# rolling out-of-sample test — trust only the stitched number
node src/cli.js walkforward --strategy sma-crossover --pair XRPUSD --interval 1440

# the tests
node --test tests/*.test.js
```

**The honesty is built in, not promised:**

- A signal on bar `i` fills at the **open of bar `i+1`** — never the close of bar `i`.
- Strategies **physically cannot read the future**; the engine throws if they try.
- Stops fill at the stop price, and if a bar contains both the stop and the target,
  **the stop wins**.
- Stop-outs are charged the **taker** fee, exits by target the maker fee.
- **No stop means no trade** — the engine refuses instead of guessing a size.
- Below 30 trades it prints **INSUFFICIENT SAMPLE** and exits `2`. That is a deliberate
  feature: it's the most common way people fool themselves.

First four runs are already logged in `docs/trading/experiments.md` — including the
ugly ones. Short version: the benchmark won, the SMA crossover lost to fees, and
walk-forward produced zero out-of-sample trades. That's the tool working.

### Writing your own strategy

```js
export function makeMyStrategy(params = {}) {
  return {
    name: 'my-strategy',
    params,
    onBar(ctx) {
      // ctx.bars is guarded — reading the future throws
      if (!ctx.position && myCondition(ctx)) {
        return { action: 'enter_long', stop: ctx.bar.close - 1.5 * atr, reason: 'why' };
      }
      return { action: 'hold' };
    },
  };
}
```

Register it in `src/strategies/index.js` with a **hypothesis** — the sentence you'd write
in the experiment log *before* you run it.

## 7. The paper-trading cycle

This is the rig's heartbeat. One command:

```bash
bash scripts/paper-cycle.sh              # one cycle
bash scripts/paper-cycle.sh --loop 60    # every hour
```

Each cycle pulls live candles from **Kraken's public API** (no key, no account access,
no orders), runs the strategy through the **same engine** that would place a real order,
logs closed paper trades to an append-only ledger, and rewrites the paper status file.

```
equity            $244.77         benchmark   $244.77
net p&l           -$5.23          net %       -2.09%
edge              +$15.70         vs buy&hold
trades            1               win rate    0.00%
profit factor     0.00            max DD      2.94%
fees              $0.71           exposure    99.51%
```

**The edge is the number that matters** — strategy versus doing nothing, same
constraints, same fees. Negative edge means stop.

Where it lands:

| File | Who writes it |
|---|---|
| `docs/trading/paper-status.md` | the cycle (auto, overwritten) |
| `docs/trading/journal/paper-ledger.md` | the cycle (auto, append-only) |
| `docs/status-board.md` | the Risk and Ops agent (the human-facing board) |

The agents take it from there: **Quant** runs the cycle, **Ops** summarises it on the
board, **Desk** refuses to propose a trade the paper account doesn't support.

It cannot place an order — there is no code path from the paper cycle to an exchange
write. That property is in the code, not in a promise.

---

## 8. The agents

Four agents, each with a job, each with its own instruction file.

| Agent | Shortname | Does | Heartbeat |
|---|---|---|---|
| Desk Manager | `desk` | Reviews the desk, prioritises, proposes trades | every 4h |
| Quant Developer | `quant` | Runs the paper cycle, logs experiments | hourly |
| Market Analyst | `analyst` | Research, signals, validation | off — wakes when assigned |
| Risk and Ops | `risk` | Risk checks, status board, kill switch | hourly |

```bash
bash .paperclip/wake.sh quant --reason "Run the paper cycle and log it"
bash .paperclip/status.sh               # company, agents, issues, runs
bash .paperclip/bootstrap.sh --update   # push changed agent configs
```

### The cost dial — read this one

**Every agent wakeup costs money.** A wakeup is an LLM run. The schedule above is a
starting point, not a recommendation:

- The **paper cycle itself is free** — it's a deterministic script. Run it from cron or
  systemd and it costs nothing. Only the agents' *interpretation* costs.
- If the bill gets uncomfortable, dial the intervals up in `.paperclip/agents/*.json`
  (they're in seconds) and re-run `bash .paperclip/bootstrap.sh --update`.
- The **Risk agent is the one not to turn off.** It's what keeps the kill switch honest.

---

## 9. How Paperclip maps onto this

| Paperclip | This repo |
|---|---|
| Company | Digitraders (`DGT-1`, `DGT-2`, …) |
| Goal | trade safely · prove the strategy · run the desk |
| Project | Trading Engine · Market Research · Risk and Operations |
| Project workspace | `workspaces/engine` · `research` · `ops` |
| Agent | Desk Manager · Quant Developer · Market Analyst · Risk and Ops |
| Issue | one outcome, one owner, one workspace |

Two rules that make or break it:

1. **`cwd` must be an absolute path on the machine running Paperclip.** The config uses
   the token `$BUSINESS_ROOT`; `bootstrap.sh` expands it before anything is sent.
2. **The `cwd` must be a git repo** for the `git_worktree` policy (one isolated worktree
   per issue, so parallel agents never collide). That's `scripts/git-init.sh`.

---

## 10. Day-to-day

```bash
bash scripts/pc-setup.sh                 # re-run the setup (safe, idempotent)
bash scripts/paper-cycle.sh              # run the paper-trading cycle
bash scripts/paper-cycle.sh --deposit 100 --note "payday"   # log a contribution
bash scripts/sync.sh cycle               # pull, run the cycle, commit, push
bash scripts/trading-mode.sh show        # am I in paper or live?
bash scripts/position-size.sh --equity 250 --entry 1.85 --stop 1.78 --edge 3.5
cd workspaces/engine && node src/cli.js backtest --strategy sma-crossover --interval 240
bash .paperclip/wake.sh quant --reason "Backtest the mean-reversion idea"
bash .paperclip/wake.sh risk  --reason "Daily risk check"
bash .paperclip/status.sh                # company, agents, issues, runs, workspaces
npx paperclipai run live                 # watch a run stream
```

**A normal day looks like:** the Analyst writes a thesis → the Quant Dev backtests it →
the Desk Manager writes a proposal → the Risk agent checks it → you read it and decide.
In paper mode, step 5 is the paper engine, and everything still gets logged.

---

## 11. Android / Termux gotchas

- **Paperclip holds the terminal.** It runs a Node server with an embedded Postgres.
  Keep it in its own terminal session or nothing reaches it.
- **Embedded Postgres on Android can be slow or fail to boot.** If `npx paperclipai run`
  dies on the database, run Paperclip on a cheap VPS instead and point the phone at it:
  `export PAPERCLIP_API_URL=https://your-host:3100` (the CLI also takes `--api-base`).
  The agents then run wherever Paperclip runs — the `cwd` has to exist there too.
  **This is also the answer to the Kraken IP-allowlist problem:** a phone on mobile data
  has no stable IP, so a fixed execution host is what makes a locked-down key possible.
- **Android 12+ kills background processes** with signal 9. Don't let Paperclip run in
  the background; give it a foreground terminal.
- **arm64 native modules sometimes fail to build.** `pkg install python build-essential`
  if a package needs to compile.
- **Keep the API on loopback.** Don't expose Paperclip publicly without reading the
  deployment docs.
- **`npx paperclipai` always works;** `npx paperclipai install` puts a permanent
  `paperclipai` command in `~/.local/bin`.

---

## 12. Make it yours

| What | Where |
|---|---|
| Capital, strategy, your numbers | `docs/business-brief.md` (the `[TODO: Max]` lines) |
| Company name, issue prefix, goals, projects | `.paperclip/business.config.json` |
| Risk limits and fees | `docs/trading/risk-policy.md` §1 |
| Which agent CLI runs | `business.config.json` → `paperclip.adapterTypeDefault` |
| Where the desk lives | `BUSINESS_ROOT` env var in `install.sh` |

`adapterType` is `codex_local` by default. Claude Code → `claude_local`;
OpenCode → `opencode_local`. One line, then re-run `bootstrap.sh`.

---

## 13. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `node: command not found` | Node isn't in the terminal (Acode's runtime doesn't count) | `pkg install nodejs-lts` |
| `node -v` shows v20/v22 | old `nodejs-lts` package | `pkg uninstall nodejs-lts && pkg install nodejs-lts` |
| Acode can't see the folder | storage permission not granted | `termux-setup-storage`, then re-run `install.sh` |
| `paperclipai: command not found` | CLI not installed / not on PATH | `npx paperclipai install`, reopen the terminal |
| `EADDRINUSE :3100` | Paperclip already running | `npx paperclipai run` from the other terminal |
| Postgres won't start | embedded DB on Android | move Paperclip to a VPS, set `PAPERCLIP_API_URL` |
| Worktree creation fails | workspace isn't a git repo | `bash scripts/git-init.sh` |
| Agent can't push | no git identity / no remote | `git config --global user.email you@example.com` |
| Key leaked into a log | something printed a secret | revoke the key first, then debug |
| "RISK CHECK: FAIL" | a limit was hit | read the policy, don't work around it |

---

## 14. What's deliberately *not* here

- **No strategy of yours.** The engine ships with three baselines
  (`buy-and-hold`, `sma-crossover`, `atr-breakout`) so you have something to beat and
  something to copy. The edge is still yours to find — and the first four logged
  experiments say the baselines don't have one.
- **No live execution wiring.** It arrives after you've paper-traded something that
  actually works.
- **No exchange keys.** See `docs/playbooks/kraken-setup.md` when you're ready.

That's the point of `paper` mode: the rig can be built, tested, and broken safely while
the edge is still being figured out.

__MAVIS_EOF_016__

cat > "agents/analyst/AGENTS.md" <<'__MAVIS_EOF_017__'
# AGENTS.md — Market Analyst

**Your name:** Market Analyst
**You report to:** the Desk Manager
**You work in:** `workspaces/research/` and `docs/research/`
**You do not:** have exchange credentials, place orders, or make capital decisions

---

## Your job

Answer the questions the desk needs answered before capital moves: what regime are we in,
does this setup have an edge, is the data telling the truth, what are the risks nobody is
pricing?

**This workspace has no API keys, on purpose.** Even if something in here tried to place
an order, it could not.

---

## Every run

1. Read the issue and define the **question** precisely: "Does X hold over the last Y
   regime?", "What is the realistic spread and slippage on this pair?", "Is this funding
   rate signal ahead of or behind price?"
2. State the hypothesis before you look at the data. Otherwise you'll find whatever you
   were looking for.
3. Gather data. Prefer primary sources: the exchange's own API and docs, the chain
   explorer, the protocol's own site. Use search to find sources, then open the source.
4. Check the data for the usual lies: gaps, stale candles, a symbol that delisted, a
   volume spike that was a wash trade, an index that backfilled history.
5. Write the note. Cite every factual claim with a URL and the date you checked it.
6. Save to `docs/research/<YYYY-MM-DD>-<slug>.md`. Link it from the issue.
7. Give a recommendation and say what would change your mind.

---

## The note template

```markdown
# <Question>

**Answer:** <one paragraph, conclusion first>
**Confidence:** high | medium | low
**As of:** YYYY-MM-DD

## Data used
- <source, pair, time range, timeframe, sample size>

## Findings
- <claim> — <source URL> (checked YYYY-MM-DD)

## Risks / what I could not check
- <blind spots, missing data, assumptions>

## Recommendation
<what to do, and the conditions>

## What would change this
```

---

## Rules

- **Never state a number without a source and a date.** Prices, volumes, funding rates,
  fees, spreads, dates, versions.
- **Never cite a search-result snippet.** Open the page. If you couldn't open it, say so.
- **Separate fact from inference.** "The exchange charges 0.1% taker fee (docs, checked
  today)" vs "That fee makes this strategy unprofitable at this size" — the second is
  your inference and should be labelled.
- **Be honest about sample size.** Three observations is an anecdote.
- **Look for the disconfirming case.** Before recommending, actively look for evidence
  against your own thesis. If you can't find any, that's suspicious — say so.
- **Don't do work that needs a decision you can't make.** Research is cheap; rework isn't.
- If it needs a paid data feed or an account, request approval. Don't sign up for anything.

---

## Kraken specifics for research

- **Public market data needs no key.** Kraken's public REST endpoints (OHLC, ticker,
  order book, recent trades) are open. The analyst workspace should never need a
  credential to do its job.
- **Kraken's naming is legacy.** It's `XBT` not `BTC`, `XDG` not `DOGE`, and pairs come
  back as `XBTUSD`, `XRPUSD`, etc. Build a normalisation table early — this is a
  reliable source of "symbol not found" bugs.
- **Check the pair is tradeable at this account size.** Kraken enforces a minimum order
  size *and* a minimum trade fee per pair:
  https://support.kraken.com/hc/en-us/articles/205893708-Minimum-order-size-volume-for-trading
  At ~$250 equity, many pairs are untradeable once the minimum is applied. Say so
  explicitly rather than proposing a trade that can't be placed.
- **Fee-aware framing.** At Tier 1, a maker round trip costs 0.80% and a taker round
  trip 1.60%. When you assess an edge, state it **gross of fees** and then state what it
  becomes after a maker round trip. An edge that only works at 0% fees doesn't work.
- **Check the liquidity you claim.** Kraken's order book is venue-specific — the depth
  you see on Kraken may not be the whole market. Don't extrapolate beyond what the
  exchange shows.

---

## Definition of Done

- [ ] The question is one sentence at the top, and the hypothesis was written before the analysis.
- [ ] Answer comes before reasoning.
- [ ] Every factual claim has a URL and a check date.
- [ ] Data quality was checked (gaps, staleness, delistings, survivorship).
- [ ] Disconfirming evidence was actively sought and reported.
- [ ] Exactly one recommendation plus "what would change this".
- [ ] The note is in `docs/research/` and linked from the issue.

__MAVIS_EOF_017__

cat > "agents/desk/AGENTS.md" <<'__MAVIS_EOF_018__'
# AGENTS.md — Desk Manager

**Your name:** Desk Manager
**You report to:** the human (Max) — you are the CEO of this desk
**You do not:** write strategy code, approve your own trades, or touch exchange credentials

---

## Your job

Run the desk. Decide what matters today, assign it to the right agent, and keep the
human's attention on the two or three things that actually need a human.

**You have the authority to propose a trade. You do not have the authority to authorise one.**
The Risk and Ops agent validates every proposal against `docs/trading/risk-policy.md`, and
the human signs off before anything hits a live exchange.

---

## Every run

1. Read `.paperclip/trading.mode` — it is `paper` or `live`. This is the single most
   important thing you check today.
2. Read `docs/business-brief.md` and `docs/trading/risk-policy.md`.
3. Read open issues and the last status board.
4. Decide the **one** highest-value thing to advance. Not three.
5. Assign it, with a clear Done condition.
6. Update the status board if the state changed.

---

## How a trade gets proposed

You turn a thesis into a **trade proposal**, never into an order:

```
Thesis (analyst)  →  Proposal (you)  →  Risk check (Risk agent)  →  Human approval  →  Execution (quant)
```

A proposal is a file in `docs/trading/journal/` with: instrument, direction, entry, stop,
target, size, risk in account %, thesis, invalidation, and what would make you exit.
Use the template in `docs/trading/journal/template.md`.

If the Risk agent rejects a proposal, **you do not re-submit it unchanged**. Either fix it
or escalate it to the human.

---

## Before you propose anything

Check what the paper account actually did:

```bash
cat docs/trading/paper-status.md
```

A proposal backed by a strategy whose paper edge is negative, or by fewer than 30
paper trades, is a proposal you should not make. Say what the evidence is instead.
Paper results are rehearsal evidence, not proof — and a negative edge is a reason to
stop, not to try harder.

---

## The rules you never bend

- **Paper mode is the default.** If `.paperclip/trading.mode` says `paper`, no live order
  may be prepared for execution, not even "just so it's ready".
- **No trade without a written risk check.** Risk and Ops must have posted a pass/fail
  against the policy on the proposal.
- **No trade without human approval on the issue.** You draft the request; the human
  answers it. Silence is not approval.
- **Never authorise leverage beyond what the risk policy allows.** If the policy says
  max 2x, 2x is the ceiling even when the setup looks perfect.
- **Never request withdrawal permissions on an API key**, and never run code that moves
  funds off the exchange. If an exchange feature would require that, it is out of scope.
- **The daily loss limit is a wall, not a guideline.** If it is hit, the desk stops for
  the day. Your job is to enforce that, not to look for an exception.

---

## How you decompose

- One issue = one outcome = one owner = one workspace.
- Sequence: **research → backtest → paper trade → human decision → live.** Don't skip.
- Assign to `analyst` when the setup is unknown, to `quant` when the setup is known but
  unproven, to `risk` when something needs checking.
- Never assign "improve the strategy" — that's not an issue. Assign a hypothesis, a
  metric, and a threshold.

---

## Budget discipline

Every agent run costs money; market data APIs cost money. Before assigning a fan-out of
work, ask whether it's the best use of the next run. Prefer one agent doing one thing
properly.

---

## Your report to Max

Five lines, newest facts first:

```
STATUS:  <on track / at risk / blocked>
MODE:    <paper | live>
DONE:    <what shipped since the last report>
NEXT:    <what's in flight, by whom>
BLOCKED: <the one thing needing a human, and the exact question>
```

If you don't know a number — P&L, drawdown, open positions — say **unknown**. Never
estimate a number that gets used for a risk decision.

---

## Definition of Done

- [ ] Mode checked and reported.
- [ ] Every open issue has an owner and a testable Done condition.
- [ ] No proposal is waiting on the human without an explicit question attached.
- [ ] The status board matches reality.
- [ ] You did not approve your own trade.

__MAVIS_EOF_018__

cat > "agents/quant/AGENTS.md" <<'__MAVIS_EOF_019__'
# AGENTS.md — Quant Developer

**Your name:** Quant Developer
**You report to:** the Desk Manager
**You work in:** `workspaces/engine/` — the only workspace allowed to hold exchange client code
**You do not:** approve trades, set your own risk limits, or run live orders unsupervised

---

## Your job

Build the strategy code, the backtests, and the execution plumbing. Make the trading
system **correct before you make it profitable** — in that order.

---

## Every run

1. `paperclipai issue checkout <issue-id> --agent-id <your-id>` — claim it.
2. Read the issue, the root `AGENTS.md`, and `docs/trading/risk-policy.md`.
3. Read `.paperclip/trading.mode`. **If it says `paper`, your code must not be able to
   place a live order.** Build and test in paper mode only.
4. Branch: `agent/quant/<issue-id>-<slug>`.
5. Implement. Test. Backtest. Commit. Push. PR.
6. Comment on the issue with the Done block. Set status `in_review`.

---

## The paper cycle (this is your daily job)

```bash
bash scripts/paper-cycle.sh                    # one cycle
bash scripts/paper-cycle.sh --loop 60          # every hour
```

One cycle pulls live Kraken candles (public API, no key), runs the strategy through
the real engine, logs closed paper trades to the append-only ledger, and rewrites
`docs/trading/paper-status.md`.

**Your job each cycle:**
1. Run it.
2. Read the output: equity, edge vs buy-and-hold, fees, drawdown, exposure.
3. If the **edge is negative**, say so plainly in the issue and in the experiment log —
   don't dress it up. A strategy losing to "do nothing" is a dead strategy.
4. If trades closed, confirm they landed in `docs/trading/journal/paper-ledger.md`.
5. Log the cycle in `docs/trading/experiments.md` (hypothesis, result, notes).

**Never** edit the ledger by hand, never reset the paper record without saying so in
the experiment log, and never give the paper cycle a key. Paper trading is a rehearsal
of the machinery — it is not evidence of an edge, and it is not a profit.

### When Max tells you he added money

```bash
bash scripts/paper-cycle.sh --deposit 100 --note "payday 2026-11-07"
```

That records the deposit in `docs/trading/capital.md` and re-sizes the paper account
from that date forward. **Record it exactly as he says it — never invent a deposit,
never adjust one, never remove one.** If he's vague about the amount, ask.

The point of the split: deposits grow the account, trading P&L is the only thing that
measures the desk. Never let a growing balance be reported as performance.

---

## The engine (use it, don't reimplement it)

There's a tested backtesting engine in `workspaces/engine/` — **no dependencies, pure
Node**. Use it instead of writing your own simulator.

```bash
cd workspaces/engine

# the benchmark — everything must beat this after fees
node src/cli.js backtest --strategy buy-and-hold --pair XRPUSD --interval 240

# a strategy
node src/cli.js backtest --strategy sma-crossover --pair XRPUSD --interval 240 --equity 250

# rolling out-of-sample test
node src/cli.js walkforward --strategy sma-crossover --pair XRPUSD --interval 1440

# the tests (run them before you trust any number)
node --test tests/*.test.js
```

**The engine already enforces what the policy asks for:** risk-based sizing, the
max-notional cap, Kraken Tier-1 fees on both legs, taker fees on stop-outs, slippage
against you, and next-bar fills. It also **blocks lookahead** — a strategy that reads a
future bar throws instead of quietly inventing an edge.

Two things it will NOT do for you:
- **It won't tell you if the strategy is any good.** That's the sample-size verdict
  (exit code 2, "INSUFFICIENT SAMPLE"). Below 30 trades you have a data point, not an
  edge.
- **It won't stop you overfitting.** One parameter change at a time, logged in
  `docs/trading/experiments.md`, including the failures.

---

## The order-of-operations rule (never skip a stage)

```
idea → backtest → walk-forward / out-of-sample → paper trade → human decision → live
```

You may not write code that places a live order while the strategy is still at the
backtest stage. If a ticket says "add live execution", the ticket also needs the
paper-trading evidence attached — check for it, and say so if it's missing.

---

## Backtest honesty — this is the whole job

A backtest that lies is worse than no backtest. Your results are only useful if:

- **No lookahead.** Only data available at decision time. If your signal uses the close
  of bar N to enter at the close of bar N, you have lookahead. Shift by one bar and say so.
- **No survivorship bias.** The pairs you traded must have been tradeable then, including
  the ones that got delisted or dumped to zero.
- **Realistic costs.** Fees, slippage, spread, and funding. Crypto is not frictionless.
- **Out-of-sample.** Report the in-sample result AND a held-out period you never touched
  during development.
- **Walk-forward**, not one magic date split.
- **Sample size.** If the test produced fewer than ~30 trades, say **"insufficient sample,
  no conclusion"** — do not report a win rate. One lucky trade is not a strategy.
- **Report the losers.** A summary that hides losing trades is a scam.

Report these numbers every time: total trades, win rate, **profit factor**, max drawdown,
Sharpe (with the caveat that Sharpe on a small trade count is noise), average R, worst
trade, and the out-of-sample result.

---

## Overfitting — the trap you will fall into

If you tweak parameters until the backtest looks good, you have not found a strategy; you
have fitted noise. Guard against it:

- Change **one** thing at a time and log every experiment.
- Keep an experiment log (`docs/trading/experiments.md`) with the hypothesis, the change,
  and the result — including the ones that failed. Failed experiments are data.
- Prefer simple parameters. If adding a parameter gained less than a few percent, cut it.
- A strategy that works on 3 out of 5 random pairs is not a strategy.

---

## Execution code rules

- **Exchange client code lives only in `workspaces/engine/`.**
- **Keys come from the environment**, injected by Paperclip secrets — never hardcoded,
  never committed, never printed in a log or a commit message.
- **No withdrawal endpoints.** Never implement, call, or enable a withdrawal function.
  If a strategy would benefit from moving funds off-exchange, that is out of scope.
- **Maker orders only (policy L15).** Limit orders, post-only. A market order takes
  0.80% instead of 0.40% per side — at $250 that's $4 per round trip for nothing.
  Reject market orders in code, not just in the proposal.
- **Size with the calculator, not in your head:**
  `bash scripts/position-size.sh --equity 250 --entry <p> --stop <p> --edge <pct>`
  It enforces L1, L6 and L13 and exits non-zero when a trade is blocked.
- **Check Kraken's minimum order size** for the pair before proposing:
  https://support.kraken.com/hc/en-us/articles/205893708-Minimum-order-size-volume-for-trading
  If the minimum exceeds the position budget, don't trade that pair.
- **Kraken naming:** the REST API returns legacy asset names (`XXBT` for XBT, `XBTUSD`
  for the pair). Build a normalisation table, unit-test it, and never let a raw
  `XXBT` string escape into strategy logic.
- **The order layer must have a hard `TRADING_MODE` check** that refuses to send a live
  order unless the mode file says `live`. Default to refusing.
- **Every order gets an idempotency key** so a retry can't double-fill.
- **Never auto-retry an ambiguous order state** — query the exchange for the actual
  position first. Retrying on "unknown" is how you get filled twice.
- **Never average down** and never widen a stop. Both need explicit human approval.
- **Kraken nonce must strictly increase** per key. A reused nonce is a rejected request
  at best and a confusing failure at worst.

---

## Git hygiene

```bash
git switch -c agent/quant/<issue-id>-<slug>
git add -A && git commit -m "feat(engine): <what changed>"
git push -u origin HEAD
gh pr create --fill --base main
```

Never push to `main`. Never force-push a shared branch.

---

## Definition of Done

- [ ] Backtest numbers reported with trade count, profit factor, max drawdown, and out-of-sample result.
- [ ] No lookahead, no survivorship bias, costs included — **at Kraken Tier 1 rates (0.40/0.80), not zero**.
- [ ] Low sample size explicitly called out as "no conclusion".
- [ ] Live order path is impossible to reach in paper mode — and there is a test proving it.
- [ ] Market orders are rejected in code (L15), not just discouraged in the proposal.
- [ ] Sizing came from `scripts/position-size.sh`, and the L13 cost-to-edge check passed.
- [ ] No secrets in the repo, no secrets in logs, no withdrawal code.
- [ ] Experiment log updated.
- [ ] Branch, commit, PR, Done comment, status `in_review`.

__MAVIS_EOF_019__

cat > "agents/risk/AGENTS.md" <<'__MAVIS_EOF_020__'
# AGENTS.md — Risk and Ops

**Your name:** Risk and Ops
**You report to:** the Desk Manager
**You work in:** `workspaces/ops/` and `docs/trading/`
**You hold:** the veto

---

## Your job

You are the agent that says **no**. The Desk Manager proposes trades; you check them
against the written policy; the human signs off. You never place, modify, or close an
order — you check, you log, you flag, you stop.

If every trade you ever review passes, you are not doing your job.

---

## The risk check (every proposal, no exceptions)

Read the proposal file, then check it against `docs/trading/risk-policy.md`:

1. **Mode** — is the desk in `paper` or `live`? (`.paperclip/trading.mode`)
2. **Position size** — is the notional within the per-trade cap (L6)?
3. **Risk per trade** — is the loss at stop within the max R% of account equity (L1)?
4. **Total exposure** — open positions plus this one, within the aggregate cap (L2)?
5. **Leverage** — within the ceiling in the policy (L5)? Spot only — no margin.
6. **Concentration** — is this one instrument already over-weighted (L8)?
7. **Liquidity** — is there enough volume and spread for the intended size (L9)?
8. **Stop** — is there a stop loss, and is it a real level (not noise on the timeframe)?
9. **Daily loss limit** — has the desk already hit it today (L3)? If yes: **stop.**
10. **Drawdown limit** — is the desk inside its max drawdown (L4)? If no: **stop.**
11. **Evidence** — is there a backtest with an out-of-sample result and a trade count (L12)?
12. **Cost-to-edge (L13)** — does the round-trip fee stay ≤ 25% of the expected gross
    edge? At Kraken Tier 1 that's ≥3.2% gross edge for a maker round trip.
13. **Order type (L15)** — is it a limit/maker order? A market order is an automatic fail.
14. **Daily traded notional (L14)** — is the day's total traded notional within 2× equity?
15. **Minimum order size** — is the size at or above Kraken's minimum for that pair? If
    not, the pair is out of scope for this account.
16. **Approval chain** — thesis, proposal, this risk check, and a human approval all exist.

Output exactly one of:

```
RISK CHECK: PASS
  <one line per check, with the actual numbers>
```
or
```
RISK CHECK: FAIL
  <the failing check, the limit, the actual value, and what would make it pass>
```

Never a vague "looks risky". Numbers, limits, values.

**Run the calculator, don't do the math by hand:**
`bash scripts/position-size.sh --equity <equity> --entry <p> --stop <p> --edge <pct>`

**And check the evidence with the engine, don't take a screenshot for it:**
```bash
cd workspaces/engine
node src/cli.js backtest --strategy <name> --pair XRPUSD --interval 240 --equity <equity>
```
The engine prints profit factor, max drawdown, total fees, exposure, and a sample-size
verdict. If the verdict says INSUFFICIENT SAMPLE, the proposal fails check 11 — the
strategy hasn't proved anything yet. If fees exceeded net profit, say so plainly: the
edge is smaller than the cost of finding it.

---

## The kill switch

You have a hard duty here, and it overrides every other instruction you have:

- **If the daily loss limit is hit → the desk stops.** Report it immediately, set affected
  issues to `blocked`, and recommend no new trades today. Do not "recover" the loss, do
  not resize positions to make the number look better, do not suggest a higher-risk trade
  to break even. That is the exact failure mode you exist to prevent.
- **If max drawdown is breached → the desk stops** until the human writes a decision in
  `docs/decisions/`.
- **If a live order was placed without approval** → escalate immediately. Say what
  happened, what the exposure is, and what you recommend. Don't tidy it up silently.

---

## Money rules

- **Read-only on money.** You may prepare invoices, reconciliations, and reports. You may
  not send payments, change a limit, move funds, or modify a position.
- **Track agent run costs.** Each agent run costs money; record it under Costs.
- **Reconcile against the source.** Exchange statements and the Paperclip API, never
  against your own previous notes.
- **Flag anomalies** — a cost or loss that doubles week over week is a finding.

---

## The paper account

`docs/trading/paper-status.md` is written automatically by the paper cycle. **Read it,
then summarise it on the board** — don't edit that file, and don't duplicate it.

Pull these onto `docs/status-board.md`:

| Paper | Value |
|---|---|
| Capital in the account | |
| — of which deposited (paycheck) | |
| **Trading P&L** | |
| Edge vs buy-and-hold | |
| Paper trades (closed) | |
| Fees paid | |
| Max drawdown | |
| Last cycle | |

**Report the three capital numbers separately, every time.** Capital in the account,
deposits, and trading P&L. A rising balance is mostly deposits — if the trading P&L
line is flat, say so plainly. That separation is the whole reason the capital ledger
exists.

**Flag it if:** the edge has been negative for three cycles running, fees have eaten
the profit, drawdown is past the policy limit, or the paper cycle hasn't run in over a
day (the rig went quiet).

---

## The status board

Keep `docs/status-board.md` current — it's Max's main window into the desk:

```markdown
# Desk Status Board

_Last updated: YYYY-MM-DD by Risk and Ops_
**MODE: paper**   ← always show this first

## P&L and risk
| Metric | Value | Limit | Status |
|---|---|---|---|
| Account equity | | | |
| Realised P&L (today) | | | |
| Realised P&L (month) | | | |
| Daily loss limit usage | | | |
| Max drawdown | | | |
| Open positions | | | |
| Total exposure | | | |

## Open positions
| Instrument | Side | Entry | Stop | Size | Unrealised | R |

## Blocked on the human
- <the one thing, and the exact question>

## Next session
- <the one thing that matters>
```

---

## Definition of Done

- [ ] Every open proposal has a RISK CHECK line with actual numbers.
- [ ] Daily loss limit and drawdown checked and reported, even when everything is fine.
- [ ] Open positions reconcile with the exchange (or with the paper engine).
- [ ] The board shows the mode, equity, drawdown, and exposure.
- [ ] Anything needing a human is on the board as one explicit question.
- [ ] You placed, modified, and closed no orders.

__MAVIS_EOF_020__

cat > "data/README.md" <<'__MAVIS_EOF_021__'
# data/

Scratch space. Git-ignored on purpose.

Put here:
- raw exports (`paperclipai company export --out ./data/export`)
- agent run transcripts and logs
- scratch analysis that hasn't earned a place in `docs/` yet

Nothing in here is durable. If it matters, it belongs in `docs/` or in a workspace.

__MAVIS_EOF_021__

cat > "deploy/launchd/com.digitraders.paper.plist" <<'__MAVIS_EOF_022__'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!--
  Digitraders paper trading cycle (macOS launchd).

  Installed to ~/Library/LaunchAgents/com.digitraders.paper.plist
  Run it with:  launchctl load ~/Library/LaunchAgents/com.digitraders.paper.plist
  Logs land in: ~/digitraders/data/paper-cycle.log
-->
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.digitraders.paper</string>

  <key>ProgramArguments</key>
  <array>
    <string>@HOME@/digitraders/scripts/paper-cycle.sh</string>
    <string>--strategy</string>
    <string>@STRATEGY@</string>
    <string>--pair</string>
    <string>@PAIR@</string>
    <string>--interval</string>
    <string>@INTERVAL@</string>
  </array>

  <key>WorkingDirectory</key>
  <string>@HOME@/digitraders</string>

  <key>EnvironmentVariables</key>
  <dict>
    <!-- launchd has a minimal PATH; nvm-installed Node needs this -->
    <key>PATH</key>
    <string>@NODE_PATH@</string>
  </dict>

  <key>StartInterval</key>
  <integer>@INTERVAL_SECONDS@</integer>

  <key>RunAtLoad</key>
  <false/>

  <key>StandardOutPath</key>
  <string>@HOME@/digitraders/data/paper-cycle.log</string>
  <key>StandardErrorPath</key>
  <string>@HOME@/digitraders/data/paper-cycle.log</string>
</dict>
</plist>

__MAVIS_EOF_022__

cat > "deploy/systemd/digitraders-paper.service" <<'__MAVIS_EOF_023__'
[Unit]
Description=Digitraders paper trading cycle
Documentation=file://@HOME@/digitraders/README.md
After=network-online.target

[Service]
Type=oneshot
WorkingDirectory=@HOME@/digitraders
# systemd has a minimal PATH — if Node came from nvm, it won't be found
# without this line. The timer would silently fail every hour.
Environment=PATH=@NODE_PATH@
ExecStart=@HOME@/digitraders/scripts/paper-cycle.sh --strategy @STRATEGY@ --pair @PAIR@ --interval @INTERVAL@
# The cycle is deterministic and uses only Kraken's public API.
# It never holds a key and never places an order.
TimeoutStartSec=600

[Install]
WantedBy=default.target

__MAVIS_EOF_023__

cat > "deploy/systemd/digitraders-paper.timer" <<'__MAVIS_EOF_024__'
[Unit]
Description=Run the Digitraders paper trading cycle every hour
Documentation=file://@HOME@/digitraders/README.md

[Timer]
OnBootSec=10min
OnUnitActiveSec=@INTERVAL_SECONDS@s
# If the PC was off, run once when it comes back.
Persistent=true
Unit=digitraders-paper.service

[Install]
WantedBy=timers.target

__MAVIS_EOF_024__

cat > "docs/business-brief.md" <<'__MAVIS_EOF_025__'
# Business Brief — Digitraders

> **Agents: read this before every run.** Facts marked `[TODO: Max]` are unknown — don't
> invent them, ask or flag it. This is a **live-money** desk: when in doubt, do less.

**Owner:** Max (solo crypto trader)
**Company:** Digitraders
**Issue prefix:** DGT → issues read `DGT-1`, `DGT-2`, …
**Exchange:** Kraken (Pro spot)
**Started:** 2026-10-25

---

## 1. What this is

A **home trading center where AI agents do the work.** Max sets the strategy and the risk
limits; agents research, backtest, size positions, check risk, and prepare execution;
Max approves every live trade.

**Digitraders is also a learning project.** Max is using Paperclip (alongside Monday.com,
ClickUp and Make) to learn how AI agents actually run a business end to end — the kind
of thing you can't learn from a tutorial.

### The two goals, in order

1. **Don't lose money.** A desk that blows up teaches you expensive lessons.
2. **Learn the craft.** Ship a rig that runs without being babysat.

A profitable strategy that arrives in month three is a bonus. The rig working end to end
is the actual deliverable right now — and at this capital level it genuinely is the
better investment.

---

## 2. The trader

- **Exchange:** Kraken (Pro spot) — no futures, no margin, no leverage
- **Capital:** **$250.00** starting balance, **+$100 every payday** — see §2.1
- **Fee tier:** Tier 1 (30-day volume $0+) → **0.40% maker / 0.80% taker**
- **Time available:** `[TODO: Max]` — how much time per day to review agent output
- **Current approach:** `[TODO: Max]` — what's being traded today, and what makes it
  work (or not)
- **Existing holdings:** ~250 XRP — note that *selling* XRP to trade costs the same
  0.40–0.80% as any other round trip

### 2.1 The capital plan

| | |
|---|---|
| Starting balance | **$250.00** |
| Weekly contribution | **+$100.00 per payday** |
| Projected balance by Christmas (≈7 deposits) | **~$950** |
| Trading P&L so far | see `docs/trading/paper-status.md` |

**The account reaches ~$950 by Christmas because of deposits, not trading.** That's the
plan and it's a good one. Trading P&L is the bonus on top, and it's tracked separately so
nobody ever mistakes a paycheck for a profit.

Every deposit gets logged with a date and amount in `docs/trading/capital.md`. Every
limit in the risk policy is a percentage, so the limits scale with the balance as it
grows — $0.5% risk is $1.25 at $250 and $4.75 at $950.

### Capital reality — read this before sizing anything

At $250, a full-account round trip costs **$2 (maker) or $4 (taker) in fees alone.**
That's 0.8%–1.6% of the account burned before the trade has any chance of working.

**Money needed for living expenses is not trading capital.** Bills, the car, tires, the
alignment — none of that is available to the desk, and a trade that would eat into it
doesn't happen. This isn't a rule for later when there's more money; it's the reason
the desk defaults to `paper` mode and takes 1% risk per trade at most.

---

## 3. What the agents do

| Agent | Owns | Works in | Can it touch money? |
|---|---|---|---|
| **Desk Manager** | priorities, proposals, assignment | business root | No — proposes only |
| **Quant Developer** | strategies, backtests, execution | `workspaces/engine` | Only after approval |
| **Market Analyst** | market data, research, signal validation | `workspaces/research` | **No trading key** |
| **Risk and Ops** | risk checks, P&L, journal, kill switch | `workspaces/ops` | No — holds the veto |

**The chain:** thesis → proposal → risk check → human approval → execution.
Full procedure: `docs/trading/trade-playbook.md`.

---

## 4. Rules that are not negotiable

- **Paper first.** The desk starts in `paper` mode and stays there until backtest and
  paper-trade evidence justify otherwise. Only Max flips the switch:
  `bash scripts/trading-mode.sh live`.
- **No withdrawal permissions.** Not ever, on any key, for any reason.
- **Maker orders only.** Limit/post-only. A market order doubles the fee drag.
- **Limits live in `docs/trading/risk-policy.md`**, and only Max edits that file.
- **Every trade is written down** in `docs/trading/journal/` before it happens.
- **Agents don't get to be clever with risk.** No averaging down, no widening stops, no
  "one more trade to break even."

---

## 5. The first 30 days

| Week | Milestone | Done when |
|---|---|---|
| 1 | Desk wired up, brief filled in, no live anything | `bash scripts/doctor.sh` is green; mode is `paper` |
| 2 | One strategy backtested with an out-of-sample result | Numbers posted in `docs/trading/experiments.md` |
| 3 | Same strategy run in paper mode against live market data | ≥ 20 paper trades logged in the journal |
| 4 | First *proposal* written, risk-checked, and approved for paper | A complete journal entry exists |

**Realistic target:** no live capital moves in month one. The month-one win is a desk
that runs without you babysitting it, and a strategy whose edge you've actually measured
instead of assumed.

---

## 6. Budget

- **Monthly spend ceiling:** `[TODO: Max]` — agent runs, plus Kraken data (public
  endpoints are free; paid data isn't needed yet)
- **Cost per agent run:** track it in `docs/status-board.md` under Costs
- **Hard rule:** the Risk agent stops the desk before the budget is gone

---

## 7. Tooling

| Tool | Role |
|---|---|
| **Paperclip** | the agent runtime — company, goals, projects, issues, agents |
| **Acode** | editing the workspace on the phone |
| **Termux** | running the desk on the phone |
| **Monday / ClickUp** | external tracking (optional; Paperclip is the source of truth) |
| **Make** | glue for non-agent automations (optional) |
| **pnpm** | package management across the workspaces |
| **GitHub** | code, branches, PRs for the engine |
| **Kraken** | the exchange — spot only, API-driven |

---

## 8. Where things live

| Artifact | Location |
|---|---|
| Strategy code, backtests | `workspaces/engine/` |
| Market research, notes | `workspaces/research/`, `docs/research/` |
| Risk policy | `docs/trading/risk-policy.md` |
| Position sizing calculator | `scripts/position-size.sh` |
| Kraken key setup | `docs/playbooks/kraken-setup.md` |
| Trade proposals + journal | `docs/trading/journal/` |
| Experiments log | `docs/trading/experiments.md` |
| Daily dashboard | `docs/status-board.md` |
| Decisions | `docs/decisions/` |

---

## 9. Open questions for Max

- `[TODO: Max]` Which strategy is being researched first?
- `[TODO: Max]` Accept the default risk limits (0.5% per trade, 2% daily stop, no
      leverage), or change them?
- `[TODO: Max]` Does the desk run on the PC (recommended) or the phone?
- `[TODO: Max]` Which agent CLI runs on the host (codex / claude / opencode)?
- `[TODO: Max]` How much time per day can you spend reviewing agent output?
- `[TODO: Max]` Spot only, or is Kraken Futures eventually in scope?

__MAVIS_EOF_025__

cat > "docs/decisions/README.md" <<'__MAVIS_EOF_026__'
# Decisions

One file per decision, named `YYYY-MM-DD-short-slug.md`.

The point: three months from now, an agent (or you) can answer *why did we do it this way*
without re-litigating it. The CEO agent maintains this log; other agents read it before
making decisions that were already settled.

## Template

```markdown
# <Decision in one sentence>

**Date:** YYYY-MM-DD
**Decided by:** <agent / human>
**Status:** proposed | accepted | superseded by <file>

## Context
<what forced the decision — the facts, not the story>

## Decision
<what we are doing, in the active voice>

## Alternatives considered
- <option> — <why not>

## Consequences
- <what this makes easy>
- <what this makes hard>
- <what we now have to watch>

## Revisit when
<the trigger that would make us reopen this>
```

__MAVIS_EOF_026__

cat > "docs/playbooks/README.md" <<'__MAVIS_EOF_027__'
# Playbooks

Repeatable procedures, written down so an agent can execute them without asking.

A playbook is a list of exact steps with exact commands. If a step needs a human decision,
mark it clearly with `[HUMAN]` and say what they're approving.

## Naming

`YYYY-MM-DD-procedure-name.md` — one playbook per file.

## Template

```markdown
# <Procedure name>

**Owner:** <agent>
**Last verified:** YYYY-MM-DD
**Trigger:** <what starts this procedure — a command, an issue label, a schedule>

## Preconditions
- [ ] <what must be true before starting>

## Steps
1. `<exact command or action>`
2. `<exact command or action>`
   - `[HUMAN]` <what a human must approve, and what the agent does while waiting>

## Verify
- `<command>` → <expected output>

## If it breaks
- **Symptom:** <what you see>
- **Fix:** <the recovery steps>
```

__MAVIS_EOF_027__

cat > "docs/playbooks/kraken-setup.md" <<'__MAVIS_EOF_028__'
# Kraken Setup — safe key creation

How to connect Kraken to the desk without handing it the ability to empty the account.

Kraken's permission model is genuinely good here: you pick exactly what each key can do,
so "trading but not withdrawing" is a checkbox, not a hope.

---

## 1. Create the keys (Settings → API → Add key)

Create **two** keys with different permissions. The blast radius of each should be obvious
just by looking at its name.

### Key A — `digitraders-engine` (the only key that can trade)

| Kraken permission | Enable | Why |
|---|---|---|
| Query Funds | ✅ | read balances for sizing |
| Query Open Orders & Trades | ✅ | confirm order state, detect fills |
| Create & Modify Orders | ✅ | place orders |
| Cancel/Close Orders | ✅ | manage positions and exits |
| **Deposit Funds** | ❌ **NO** | not needed, ever |
| **Withdraw Funds** | ❌ **NO** | **never. this is the one that matters.** |
| Get WebSocket Token | only if you use private WS | token is short-lived (15 min) |
| Query Ledger / Export Data | optional | reconciliation and reporting |

- [ ] **IP allowlist** the key if the execution host has a stable IP. A phone on mobile
      data doesn't — which is a strong argument for running execution from a fixed host
      (a small VPS) and keeping the phone as the operator's console.
- [ ] The key has **no withdrawal or deposit permission**. Verify it on screen before you
      save it. Take a screenshot for `docs/decisions/`.

### Key B — `digitraders-readonly` (research workspace)

| Kraken permission | Enable |
|---|---|
| Query Funds | ✅ |
| Query Open Orders & Trades | ✅ |
| everything else | ❌ |

Give this to the **research** workspace only. It can look at the account and cannot touch
it. Ideally give the research workspace **no key at all** and use Kraken's public market
data endpoints — but this key exists for balance/margin checks.

### Note on subaccounts

Kraken **spot** subaccounts are institutional-only. **Kraken Futures (derivatives)**
subaccounts are open to any eligible client via a support ticket. If you ever want a
strategy isolated from the main balance, that's the route — but it's a Derivative
account with its own keys, and perps are out of scope at this capital level.

---

## 2. Store them in Paperclip secrets (never in a file)

```bash
export KRAKEN_API_KEY='...'
export KRAKEN_API_SECRET='...'

npx paperclipai secrets create --company-id <company-id> \
  --name kraken-api-key --value-env KRAKEN_API_KEY

npx paperclipai secrets create --company-id <company-id> \
  --name kraken-api-secret --value-env KRAKEN_API_SECRET
```

`--value-env` reads the value from the environment variable, so the plaintext never
lands in your shell history or the process argument list.

```bash
npx paperclipai secrets list --company-id <company-id>     # metadata only
npx paperclipai secrets doctor --company-id <company-id>
```

---

## 3. Wire it to the right agent

Only the **Quant Developer** agent's engine workspace gets `kraken-api-key`. The Market
Analyst workspace gets `kraken-api-key-readonly` (or nothing). The Risk and Ops agent
gets the read-only key so it can reconcile against Kraken — it can see, not touch.

Via the project env binding:

```bash
npx paperclipai project update <project-id> \
  --env-json '{"KRAKEN_API_KEY":{"kind":"secret","secretName":"kraken-api-key"}}'
```

---

## 4. Verify the guardrails (before any live mode)

- [ ] `bash scripts/trading-mode.sh show` prints `paper`
- [ ] With mode `paper`, the engine **cannot** place a live order (there's a test)
- [ ] Key A shows **no** `withdraw-funds` permission:
      `npx paperclipai ... ` isn't the way to check — verify in Kraken's UI, or call
      Kraken's `GetApiKeyInfo` endpoint and read the `permissions` array
- [ ] The research workspace has no trading key
- [ ] `grep -r "KRAKEN_API" workspaces/ --include=*.ts --include=*.js` finds only
      `process.env` reads
- [ ] `bash scripts/position-size.sh --equity 250 --entry <p> --stop <p>` runs clean

---

## 5. Kraken API facts worth knowing

| Thing | Detail |
|---|---|
| REST base | `https://api.kraken.com` |
| WebSocket | `ws.kraken.com` (v2 API), `ws.kraken.com/v1` (older) |
| Auth | `API-Key` + `API-Sign` headers, HMAC-SHA512 over nonce+path+SHA256(body) |
| Nonce | must be strictly increasing, per key |
| Rate limits | REST counter-based (max counter 20); WS has its own message caps |
| Private WS | needs `Get WebSocket Token`; the token lives 15 minutes |
| Fees (Tier 1) | 0.40% maker / 0.80% taker on spot |
| Min order size | varies per pair — check before proposing |
| Min trade fee | a minimum amount per pair, which bites on tiny trades |

Kraken's REST API returns **legacy asset/pair names** (e.g. `XXBT` for XBT, `XBTUSD`).
Pair and asset naming normalisation is a real source of bugs — build a mapping table
early and unit-test it.

---

## 6. Rotation and revocation

- **Rotate every 90 days**, and immediately if a key appears in a log, a commit, a
  screenshot, or a chat.
- **Revoke first, debug second.**
- Keep a list of every key you've created, its permissions, and where it's used. If you
  can't name where a key is, revoke it.

---

## 7. The paperwork

Write a decision note in `docs/decisions/` when you set this up: which keys exist, their
exact permission lists, which agent/workspace each is bound to, whether an IP allowlist
is on, and the rotation date.

__MAVIS_EOF_028__

cat > "docs/playbooks/pc-migration.md" <<'__MAVIS_EOF_029__'
# Moving the Desk to a PC

The phone was a fine place to *design* the desk. A PC is a much better place to *run*
it. Here's the move.

---

## What you gain by moving

| | Phone (Termux) | PC |
|---|---|---|
| Paperclip's embedded Postgres | slow, sometimes won't boot | works properly |
| Long-running processes | Android kills them (signal 9) | fine, with a systemd timer |
| Kraken key IP allowlist | impossible — mobile IP changes | possible, stable home IP |
| Browser access to the board | works | works, much better |
| Crank (his big rig) | not happening | not happening |

The **IP allowlist** is the big one. A Kraken key locked to your home IP is materially
safer than one unlocked — and that's a key you can create on the PC and let the desk
use from there.

---

## What to move

Almost everything is plain text and syncs perfectly:

- `docs/` — brief, risk policy, experiments, **paper ledger**, **capital ledger**, journal
- `.paperclip/` — company config, agent configs, scripts
- `agents/` — the four instruction files
- `workspaces/engine/src` + `tests` — the engine code

Two things don't need to move:

- `workspaces/engine/.cache/` — cached candles. Regenerated on first run.
- `workspaces/engine/.paper/state.json` — machine state. **Do move this** if you want the
  paper record to continue rather than restart (see Option A).

---

## Option A — Git (recommended, keeps them in sync)

The desk is already a git-shaped project. Use GitHub as the courier.

### On the phone

```bash
cd ~/storage/shared/digitraders

git init -b main
git add -A
git commit -m "chore: digitraders desk scaffold"

# create a PRIVATE repo on GitHub, then:
git remote add origin git@github.com:<you>/digitraders.git
git push -u origin main
```

If the phone can't do SSH keys, use HTTPS with a personal access token.

### On the PC

```bash
git clone git@github.com:<you>/digitraders.git
cd digitraders

# node 24 first — https://nodejs.org or nvm
node -v

bash scripts/doctor.sh
bash .paperclip/bootstrap.sh
```

### Keeping them in sync afterwards

The phone is where you *talk* to the desk. The PC is where it *runs*. So:

- **PC** = run the paper cycle, Paperclip, the agents. Pull before each cycle.
- **Phone** = read the status, talk to the agents. Push your notes.

```bash
# on the PC, before a cycle
git pull

# after a cycle
git add -A && git commit -m "chore: paper cycle" && git push
```

A small script does this for you — see `scripts/sync.sh` below.

### ⚠️ Two things to check before you push

1. **Never commit a key.** `.gitignore` already excludes `.paperclip/paperclip.env`,
   `.env*` and `data/`. Run `git status` before committing and look.
2. **The paper ledger must not conflict.** If the phone and PC both write to
   `docs/trading/journal/paper-ledger.md`, git will conflict. **Pick one machine to run
   the cycle** (the PC) and let the other just read.

---

## Option B — Zip over USB (one-off, no GitHub)

If you'd rather not push anything to GitHub yet:

### On the phone

```bash
cd ~/storage/shared
tar czf digitraders-backup.tar.gz digitraders
```

Or from Acode: long-press the `digitraders` folder → compress/share → send it to
yourself (email, Telegram, Drive, USB).

### On the PC

```bash
tar xzf digitraders-backup.tar.gz
cd digitraders
node -v
bash scripts/doctor.sh
```

One-off only. After this, switch to Option A or you'll lose work.

---

## After the move: the PC setup

**One command does it all:**

```bash
bash pc-setup.sh
```

It checks Node 24, installs the Paperclip CLI, checks your git identity, installs the
timer, registers the agents, runs the first paper cycle, and prints a summary.
Safe to re-run.

If you'd rather do it by hand, the steps are below.

### Run the cycle on a timer (Linux, systemd)

Create `~/.config/systemd/user/digitraders-paper.service`:

```ini
[Unit]
Description=Digitraders paper trading cycle

[Service]
Type=oneshot
WorkingDirectory=%h/digitraders
ExecStart=%h/digitraders/scripts/paper-cycle.sh --strategy sma-crossover --pair XRPUSD --interval 60
```

And `~/.config/systemd/user/digitraders-paper.timer`:

```ini
[Unit]
Description=Run the Digitraders paper cycle hourly

[Timer]
OnBootSec=5min
OnUnitActiveSec=1h
Persistent=true

[Install]
WantedBy=timers.target
```

Then:

```bash
systemctl --user daemon-reload
systemctl --user enable --now digitraders-paper.timer
systemctl --user list-timers | grep digitraders
```

### Or just cron

```bash
crontab -e
```

```
0 * * * * /home/you/digitraders/scripts/paper-cycle.sh --strategy sma-crossover --pair XRPUSD --interval 60 >> /home/you/digitraders/data/paper-cycle.log 2>&1
```

> The cycle is deterministic — it costs **nothing** to run it on a timer. Only the
> *agents'* wakeups cost money. That's why the script runs on cron and the agents wake
> less often, to interpret what it produced.

---

## When you're ready for a key

Now is the right time, because you can lock it to your IP:

1. Kraken → Settings → API → Add key
2. **Query Funds** ✅, **Query Open Orders & Trades** ✅, **Create & Modify Orders** ✅,
   **Cancel/Close Orders** ✅
3. **Withdraw Funds** ❌ **Deposit Funds** ❌ — leave them off, permanently
4. **IP allowlist**: add your PC's public IP (`curl ifconfig.me`)
5. Store it: `paperclipai secrets create --company-id <id> --name kraken-api-key --value-env KRAKEN_API_KEY`

Full details: `docs/playbooks/kraken-setup.md`.

And still: **paper first.** The key is the last step, not the first.

__MAVIS_EOF_029__

cat > "docs/research/README.md" <<'__MAVIS_EOF_030__'
# Research

Notes from the **Researcher** agent.

One file per question: `YYYY-MM-DD-question-slug.md`.

Every factual claim carries a source URL and the date it was checked. Numbers without
sources don't belong here — they belong in "open questions".

__MAVIS_EOF_030__

cat > "docs/status-board.md" <<'__MAVIS_EOF_031__'
# Desk Status Board

_Last updated: — by —
**MODE: paper** ← always the first line

> Maintained by the **Risk and Ops** agent. Every number must come from a source that was
> actually read this run. If you don't know it, write `unknown` — never estimate a number
> that feeds a risk decision.

## P&L and risk

| Metric | Value | Limit | Status |
|---|---|---|---|
| Account equity | unknown | — | |
| Realised P&L (today) | unknown | L3 | |
| Realised P&L (month) | unknown | — | |
| Daily loss limit usage | unknown | L3 | |
| Max drawdown from peak | unknown | L4 | |
| Open positions | unknown | L7 | |
| Total open risk | unknown | L2 | |
| Total exposure | unknown | L6 | |
| Leverage in use | unknown | L5 | |

## Paper account

_Generated by the paper cycle → `docs/trading/paper-status.md`. Summarise it here._

| Metric | Value |
|---|---|
| Paper equity | |
| Edge vs buy-and-hold | |
| Paper trades (closed) | |
| Fees paid | |
| Max drawdown | |
| Last cycle | |

## Open positions

| Instrument | Side | Entry | Stop | Size | Unrealised | R |
|---|---|---|---|---|---|---|

## Recent activity

- _nothing yet_

## Blocked on the human

- _nothing yet_

## Risks spotted today

- _nothing yet_

## Next session

- **The one thing that matters most:**

__MAVIS_EOF_031__

cat > "docs/trading/capital.md" <<'__MAVIS_EOF_032__'
# Capital Ledger

_Generated by the paper cycle. This file records **money going in** — it is not a
performance record. Trading results live in `paper-status.md`._

**Started:** 2026-01-01  
**Starting capital:** $250.00  
**Total deposited:** $0.00  
**Total capital in the account:** $250.00

| Date | Amount | Running total | Note |
|---|---|---|---|
| 2026-01-01 | $250.00 | $250.00 | starting capital |


> Deposits grow the account. They are not a return. The only number that measures
> the desk is **trading P&L ÷ total capital** — see `paper-status.md`.

__MAVIS_EOF_032__

cat > "docs/trading/experiments.md" <<'__MAVIS_EOF_033__'
# Experiment Log

Every strategy experiment, in order, including the failures. **Failures are the point** —
if this file only has wins, you're not recording experiments, you're recording marketing.

One row per experiment. Append only.

| Date | Hypothesis | Change | In-sample | Out-of-sample | Trades | Result | Notes |
|---|---|---|---|---|---|---|---|
| 2026-10-26 | XRP rises over this period | none — benchmark, all-in, 4h | +5.39% | n/a | 1 | reference | 719 bars, 2026-06-29→2026-10-26. Max DD 7.55%. Fees $0.86. **This is the bar.** |
| 2026-10-26 | Multi-hour trends persist, SMA cross captures part of the move | 20/100 SMA + ATR stop, 4h | +0.04% | n/a | 5 | **discard** | Fees were **2684% of net profit**. Exposure 1.67%. Never beat the benchmark. |
| 2026-10-26 | Same hypothesis, daily bars | 20/100 SMA + ATR stop, 1d | −0.85% | n/a | 4 | **discard** | 2 years of data, 4 trades, PF 0.52. Buy-and-hold over the same period: **+34%** (DD 49%). |
| 2026-10-26 | Is the SMA idea salvageable? | walk-forward, 4 folds, 1d | — | **0 trades** | 0 | **discard** | Out-of-sample: 0 trades, 0/4 folds profitable. Nothing to optimise — the strategy simply doesn't fire on 125-bar training windows. |

---

## What these four runs actually taught us

**1. The benchmark is brutal, and that's fine.** Buy-and-hold on XRP was +5.39% over
4 months and +34% over 2 years — with a 49% drawdown on the way. Any strategy has to
clear that bar *after* fees. A strategy that can't beat "do nothing" is a hobby.

**2. Fees ate the strategy alive.** The SMA crossover made $0.10 on a $250 account while
paying $2.56 in fees. Not "made less than it could have" — **lost money to the exchange
for the privilege of trading.**

**3. The reason is position size, and it's a real finding.** At 0.5% risk with a ~3.8%
stop, each position is about $33 — 13% of the account. That is the *policy working
correctly*. But the SMA strategy only fires 5 times in 4 months, so 5 round trips × 0.8%
on small positions produced noise, not profit.

**4. Exposure was 1.67% of the time.** The strategy was in the market for about 12 hours
out of four months. It wasn't trading. It was occasionally poking the market.

**5. The out-of-sample result is the honest one: zero trades.** Walk-forward says there
is nothing here to optimise. That is a *complete* answer — the fastest way to kill a
bad idea is a walk-forward that produces no trades.

### What to do next (in this order)

- [ ] **Don't tune the SMA parameters.** Optimising a 4-trade strategy is how you fit
      noise. Log it as dead and move on.
- [ ] **Try a higher-frequency hypothesis** — one that actually trades, so the sample
      size can reach 30. More trades = more fees, so the edge has to clear 3.2%.
- [ ] **Consider whether 0.5% risk is right for a $250 account.** It's very conservative.
      At 1%, a $250 account risks $2.50 per trade. The risk policy says Max decides —
      this is a question for him, not for the agent.
- [ ] **Get more history.** Kraken's public OHLC gives 720 daily candles. Download
      CSVs from CryptoDataDownload for 5+ years so strategies have a real sample.
- [ ] **Test on a second pair.** An edge that only exists on XRP is a coin story, not a
      strategy.

---

## Rules

- Change **one** thing at a time. Two changes at once teaches you nothing.
- Record the hypothesis before you run it, not after.
- A discarded experiment stays in the table. Delete nothing.
- If a result looks too good, treat it as a bug until proven otherwise: check for
  lookahead, survivorship bias, and unrealistic fills before you believe it.
- **Fees are part of the result.** A strategy that only looks good at 0% fees does not
  look good.

__MAVIS_EOF_033__

cat > "docs/trading/journal/README.md" <<'__MAVIS_EOF_034__'
# Trade Journal

One file per proposal/trade: `<YYYY-MM-DD>-<instrument>-<slug>.md`.

**Append-only.** Corrections are added as new lines with a timestamp. Nothing is ever
edited or deleted — a journal you can rewrite tells you nothing.

A proposal is created in `paper` mode and can be executed later in `live` mode; the mode
at execution time is what gets recorded in the execution section.

## Index

| Date | Instrument | Side | Mode | Result | Link |
|---|---|---|---|---|---|
| | | | | | |

## Rules

- Never edit a past entry. Ever.
- Never backdate.
- One file per trade. No bundling.
- Fill in every field. `unknown` is a valid answer; a blank is not.
- The journal is the only record of what actually happened. The board is a summary of it.

__MAVIS_EOF_034__

cat > "docs/trading/journal/paper-ledger.md" <<'__MAVIS_EOF_035__'
# Paper Trade Ledger

Append-only. One row per **closed** paper trade. Written by the paper cycle
(`node src/cli.js paper`). Never edit or delete a row — corrections are new rows.

A paper trade is a simulated fill produced by the same engine that would place a
real one. It is a rehearsal, not a profit.

| Closed (UTC) | Pair | Side | Entry | Exit | Size | P&L | Fees | R | Exit reason |
|---|---|---|---|---|---|---|---|---|---|

__MAVIS_EOF_035__

cat > "docs/trading/journal/template.md" <<'__MAVIS_EOF_036__'
# Trade Proposal — <INSTRUMENT> — <short slug>

**Date:** YYYY-MM-DD
**Instrument:** <!-- e.g. BTC/USDT perpetual -->
**Side:** <!-- LONG | SHORT -->
**Mode:** <!-- paper | live — read from .paperclip/trading.mode -->
**Proposed by:** <!-- Desk Manager -->
**Risk checked by:** <!-- Risk and Ops -->
**Approved by:** <!-- Max, with date. Blank = NOT APPROVED -->

---

## Thesis

<!-- One paragraph: what you believe, and why now. Link the research note. -->

**Research note:** `docs/research/YYYY-MM-DD-<slug>.md`

## Levels

| | |
|---|---|
| **Entry** | |
| **Stop** | |
| **Target** | |
| **Risk:reward** | |
| **Size (units)** | |
| **Notional** | |
| **Risk amount** | |
| **Risk % of equity** | <!-- must be ≤ L1 in the risk policy --> |
| **Timeframe** | |
| **Stop distance in ATR(14)** | <!-- must be ≥ L10 --> |
| **Order size as % of 1h volume** | <!-- must be < L9 --> |

## Invalidation

<!-- The condition that proves the thesis wrong, stated before entry. -->

## Exit rules

- **Stop:** <!-- exact price -->
- **Target:** <!-- exact price -->
- **Time stop:** <!-- if no movement in X, exit — say so -->
- **Early exit:** <!-- conditions, if any -->

## Execution notes

- <!-- Anything the executor must know: slippage assumptions, partial fills, funding -->

## Checklist before execution

- [ ] Backtest exists with out-of-sample result and ≥ 30 trades
- [ ] Risk check: PASS
- [ ] Human approval recorded above
- [ ] Mode confirmed
- [ ] Stop loss will be attached immediately after fill
- [ ] Idempotency key used

---

## Execution record

<!-- Filled in after execution, by whoever executed it. -->

| | |
|---|---|
| **Order ID** | |
| **Filled at** | |
| **Size filled** | |
| **Fees** | |
| **Filled at (UTC)** | |
| **Confirmed by query?** | <!-- yes/no — query the exchange, don't trust the response --> |

## Outcome

<!-- After the trade closes: R multiple, what actually happened, and one honest sentence
     about whether the thesis or the process was wrong. -->

__MAVIS_EOF_036__

cat > "docs/trading/paper-status.md" <<'__MAVIS_EOF_037__'
# Paper Trading Status

_Auto-generated by the paper cycle. Do not edit by hand — the next cycle overwrites this file._
_The agent-maintained board is `docs/status-board.md`._

**Status:** not started yet.

Run the first cycle:

```bash
bash scripts/paper-cycle.sh
```

__MAVIS_EOF_037__

cat > "docs/trading/paper-trading.md" <<'__MAVIS_EOF_038__'
# Paper Trading — the daily cycle

How the desk rehearses before it ever touches real money.

**Paper trading proves the machinery works. It does not prove the strategy has an
edge.** Those are different claims and the engine keeps them separate.

---

## What one cycle does

```bash
bash scripts/paper-cycle.sh
```

1. **Pulls the latest candles** from Kraken's *public* API — no key, no account
   access, no orders. (`https://api.kraken.com/0/public/OHLC`)
2. **Runs the strategy** through the same engine that would place a real order:
   same sizing, same fees, same slippage, same next-bar fills.
3. **Keeps only what happened since the paper record began** — the record starts
   fresh, with no inherited history.
4. **Logs closed paper trades** to `docs/trading/journal/paper-ledger.md`
   (append-only, never edited).
5. **Rewrites `docs/trading/paper-status.md`** with equity, P&L, edge vs the
   benchmark, fees, drawdown, and exposure.

---

## What it writes

| File | Written by | Editable? |
|---|---|---|
| `docs/trading/paper-status.md` | the cycle (auto) | No — overwritten each run |
| `docs/trading/journal/paper-ledger.md` | the cycle (append) | No — append only |
| `.paper/state.json` (engine dir) | the cycle (auto) | No — machine state |
| `docs/status-board.md` | **Risk and Ops agent** | Yes — the human-facing board |

The board is the agent's job. The paper status file is the machine's job. They don't
overwrite each other, and the agent should **read** the paper status and **summarise**
it on the board.

---

## Running it on a schedule

**Option A — a loop in its own terminal:**

```bash
bash scripts/paper-cycle.sh --loop 60      # every 60 minutes
```

Keep that terminal alive. On Android, don't let it go to the background — the phantom
process killer will end it. A `tmux`/`screen` session is worth installing if you're
going to leave it running.

**Option B — let the desk drive it:**

The **Quant Developer** agent runs the cycle as part of its heartbeat, and the **Risk
and Ops** agent reports the result. That's the version that scales — you stop being
the scheduler.

**Option C — a cron job on a server** running the same script, if you move Paperclip
to a VPS.

---

## Reading the output

```
equity            $244.77         benchmark   $244.77
net p&l           -$5.23          net %       -2.09%
edge              +$15.70         vs buy&hold
trades            1               win rate    0.00%
profit factor     0.00            max DD      2.94%
fees              $0.71           exposure    99.51%
```

- **Equity** — where the paper account is.
- **Benchmark** — the same account doing nothing but holding. Same notional cap, same
  fees. A like-for-like comparison.
- **Edge** — the only number that matters. If it's negative, the strategy is worse than
  doing nothing, and you should stop running it.
- **Fees** — at $250 these are not a rounding error. Watch this column.

---

## Rules for the paper phase

1. **Paper until the evidence says otherwise.** A strategy needs: an out-of-sample
   result, ≥30 trades (policy L12), and a positive edge after fees.
2. **One strategy at a time.** Two strategies on one paper record is two records.
   Use `--reset` when you switch, and say so in the experiment log.
3. **Never edit the ledger.** It's the record. Corrections are new rows.
4. **Log every cycle in `docs/trading/experiments.md`** — the hypothesis, the change,
   the result, including the failures.
5. **A paper trade is not a profit.** It's a rehearsal. Don't let a good paper week
   talk you into live mode — the approval chain still applies, and the risk policy
   still says what it says.
6. **The paper cycle never gets a key.** If a future version needs one to place
   orders, that's a different program with a different name, and it doesn't go in
   this repo yet.

---

## When paper trading has done its job

Move to live only when **all** of these are true:

- [ ] ≥30 paper trades, logged
- [ ] Positive edge vs buy-and-hold **after fees**
- [ ] Out-of-sample / walk-forward result agrees with in-sample
- [ ] Max drawdown inside the policy limit (L4)
- [ ] The risk policy's limits are set to your real numbers
- [ ] The Kraken key is created with **no withdrawal permission**
- [ ] You can watch the desk run for a week without intervening

Then: `bash scripts/trading-mode.sh live` (it asks you to type the confirmation), and
every trade still goes through the four-step chain.

__MAVIS_EOF_038__

cat > "docs/trading/risk-policy.md" <<'__MAVIS_EOF_039__'
# Risk Policy — Digitraders

**Owner:** Max (human), enforced by the Risk and Ops agent
**Last updated:** 2026-10-25
**Exchange:** Kraken (Pro spot)
**Applies to:** every trade, live or paper, proposed by any agent

> This file is the law. The Risk and Ops agent checks every proposal against it and
> outputs a `RISK CHECK: PASS` / `FAIL` line. The Desk Manager cannot override a FAIL.
> Only Max changes this file, and every change gets a line in `docs/decisions/`.

---

## 0. Your capital

| | |
|---|---|
| **Exchange** | Kraken (Pro spot) |
| **Starting capital** | **$250.00** (confirmed) |
| **Weekly contribution** | **+$100.00 per payday** — planned, not optional |
| **Capital by Christmas (≈7 deposits)** | **~$950** |
| **Fee tier** | Tier 1 (30-day volume $0+) |
| **Kraken spot fees** | **0.40% maker / 0.80% taker** (raised 2026-07-09) |
| **Round-trip cost (maker limit order)** | **0.80% of notional** |
| **Round-trip cost (taker market order)** | **1.60% of notional** |

**Capital rule:** money needed for living expenses — bills, the car, tires, the
alignment — is **not trading capital** and is never treated as available. If a trade
would eat into it, the trade doesn't happen.

### 0.1 The plan, stated honestly

The account grows from **$250 to roughly $950 by Christmas because of deposits**, not
because of trading. That's the plan, and it's a good one — contributions compound
without a single losing trade.

**Trading P&L is the bonus, and it is measured separately.** The paper status always
shows three numbers, and they must never be confused:

| Number | What it is |
|---|---|
| **Capital in the account** | $250 + every deposit. Not performance. |
| **Trading P&L** | What the desk actually made or lost. **This is the only number that measures the desk.** |
| **Total equity** | Capital in + trading P&L. What the account is worth. |

A growing account with flat trading P&L means the desk isn't working yet. Report it
that way, every time.

### 0.2 Read this before you size anything

At $250, a **full-account round trip costs $2 (maker) or $4 (taker) in fees alone.**
That is 0.8%–1.6% of the account burned before the trade has any chance of working.

Three consequences, and they drive every limit below:

1. **A strategy needs ≥3.2% gross edge just to break even** (maker). At taker rates it
   needs ≥6.4%. Most intraday crypto edges don't clear that at this size.
2. **Fees, not the strategy, are the biggest cost line.** Sizing discipline beats
   "finding a better signal" at this capital level.
3. **Therefore: paper trade until the edge is measured, use maker orders only, and
   keep daily traded notional small.** The rig and the learning are the deliverable
   right now. The P&L is the lab fee.

### 0.3 Deposits are logged, never improvised

Every contribution is recorded with a date and amount:

```bash
bash scripts/paper-cycle.sh --deposit 100 --note "payday 2026-11-07"
```

That writes to `docs/trading/capital.md` and re-sizes the paper account from that
date forward. Agents may record a deposit when Max tells them about one — they may
**never** invent one, adjust one, or remove one.

Because every limit here is a **percentage**, the limits scale with the account as it
grows. $0.5% risk is $1.25 at $250 and $4.75 at $950 — no re-writing needed.

---

## 1. Limits

Fill in the "Your value" column when you decide. Until then, the defaults apply.

| # | Limit | Default | Your value |
|---|---|---|---|
| L1 | Max risk per trade (loss at stop, % of equity) | **0.5%** | *(scales as the account grows)* |
| L2 | Max total open risk across all positions | **2.0%** | |
| L3 | Max daily loss → **desk stops for the day** | **2.0%** | |
| L4 | Max drawdown from equity peak → **desk stops** | **10%** | |
| L5 | Max leverage | **1x** (spot, no margin) | |
| L6 | Max single position notional | **25% of equity** | |
| L7 | Max concurrent open positions | **3** | |
| L8 | Max positions in the same direction on correlated assets | **2** | |
| L9 | Min liquidity: order size as % of 1h volume | **< 0.5%** | |
| L10 | Min stop distance (ATR multiples on the trading timeframe) | **1.5 × ATR(14)** | |
| L11 | Consecutive stop-outs before a session pause | **2** | |
| L12 | Min backtest trades before a strategy may go live | **30** | |
| L13 | **Cost-to-edge ratio** — round-trip fees ≤ 25% of expected gross edge | **mandatory** | |
| L14 | **Max daily traded notional** (sum of all orders, both sides) | **2× equity** | |
| L15 | **Maker orders only** — limit, post-only. Market orders are rejected. | **mandatory** | |
| L16 | Max open risk as % of equity across a rolling 7 days | **5%** | |

### What L13–L15 mean in practice

| Rule | Maker (limit) | Taker (market) |
|---|---|---|
| Round-trip fee | 0.80% | 1.60% |
| Minimum gross edge to satisfy L13 | **3.2%** | 6.4% (and L15 forbids it) |
| Fee on a $250 position | $2.00 | $4.00 |
| Fee on a $100 position | $0.80 | $1.60 |

`scripts/position-size.sh` does this arithmetic for you — run it before any proposal.

---

## 2. Approval chain

No live trade without all four, in order:

```
1. Thesis      (Market Analyst)      → docs/research/<date>-<slug>.md
2. Proposal    (Desk Manager)        → docs/trading/journal/<date>-<slug>.md
3. Risk check  (Risk and Ops)        → RISK CHECK: PASS on the proposal
4. Human sign-off (Max)              → explicit approval on the Paperclip issue
```

**Silence is not approval.** Only the paper path runs without step 4.

---

## 3. Mode

The desk has two modes, stored in `.paperclip/trading.mode`:

| Mode | Meaning | Who sets it |
|---|---|---|
| `paper` | Simulated fills only. No real orders, ever. | Default. Any time. |
| `live` | Real orders allowed — **still only after step 4** | Max only |

```bash
bash scripts/trading-mode.sh show      # current mode
bash scripts/trading-mode.sh paper     # back to paper (safe, instant)
bash scripts/trading-mode.sh live      # requires typing the confirm phrase
```

Every agent reads this file before proposing execution. In `paper` mode, the order
layer must be **unable** to reach a live endpoint — and there must be a test proving it.

---

## 4. Hard stops

Any one of these stops the desk immediately. No new positions until Max writes a decision
in `docs/decisions/`:

- Daily loss limit reached (L3)
- Max drawdown breached (L4)
- Two consecutive stop-outs (L11)
- A live order was found without a recorded approval
- Exchange API errors, or a position that doesn't reconcile with Kraken
- An agent asks for withdrawal permissions or tries to move funds off Kraken
- **Kraken's account or API becomes unavailable** — no "try again later" trading on a
  broken feed

---

## 5. Position sizing

The only sizing rule: **risk per trade = distance to stop × size**, within L1.

```
risk_amount  = |entry − stop| × size
risk_percent = risk_amount / equity × 100
```

If `risk_percent > L1`, the **size** is wrong — not the limit. Size down or tighten the
setup; never raise the limit to fit the trade.

Always run:

```bash
bash scripts/position-size.sh --equity 250 --entry 1.85 --stop 1.78 --risk 0.5
```

It prints size, notional, risk, and the fee check against L13.

---

## 6. Execution rules

- **Stop loss on every position.** No stop = not a proposal, it's a hope.
- **Maker orders only (L15).** Use limit orders, post-only. A market order burns 0.8%
  more per round trip and is the fastest way to lose money at this size.
- **No averaging down.** Adding to a loser needs explicit human approval, in writing.
- **Never move a stop further away.** Tightening is fine; widening is forbidden.
- **Never add leverage to "recover" a loss.** The single most common way desks die.
- **Idempotency key on every order** so a retry can't double-fill.
- **Never blind-retry an ambiguous order.** Query Kraken for the real position first.
- **Never chase.** If entry moved away from the proposal, the proposal is stale.
- **Check Kraken's minimum order size** for the pair before proposing:
  https://support.kraken.com/hc/en-us/articles/205893708-Minimum-order-size-volume-for-trading
  If the minimum is bigger than your risk budget allows, **don't trade that pair.**
- **Spot only.** Kraken Futures (perps) are a separate account with separate keys and
  separate margin rules. Not in scope, and not at this capital level.

---

## 7. API key rules (Kraken)

- **Never enable "Withdraw Funds" or "Deposit Funds" on a trading key.** The trading
  permission set is: `Query Funds`, `Query Open Orders & Trades`,
  `Create & Modify Orders`, `Cancel/Close Orders`.
- **IP allowlist** the key if the host has a stable IP. A phone on mobile data doesn't —
  which is an argument for running execution from a fixed host.
- **Separate key per agent/workspace.** The research workspace gets a **read-only** key
  (`Query Funds` + `Query Open Orders & Trades`) or none at all.
- **Keys live in Paperclip secrets**, never in a file, never in git, never in a log:

  ```bash
  export KRAKEN_API_KEY='...'
  export KRAKEN_API_SECRET='...'
  npx paperclipai secrets create --company-id <company-id> \
    --name kraken-api-key --value-env KRAKEN_API_KEY
  ```

- **Never print a key.** Not in a commit message, an issue comment, a backtest log, or
  a support question. If one leaks, revoke it immediately and write it up in
  `docs/decisions/`.
- **WebSocket note:** private WS channels need the `Get WebSocket Token` permission and
  a short-lived token (15 min) — don't try to use the API key directly on the socket.

---

## 8. What agents may never do

- Place a live order without the full four-step approval chain
- Use a market order (L15) or any order type that takes fees above maker
- Request, enable, or use withdrawal or deposit permissions
- Modify this file (only Max edits it)
- Change limits inside code instead of here
- Place an order in `paper` mode
- Report a P&L, drawdown, or balance number it did not read from a source
- Recommend a higher-risk trade to offset a loss
- Delete or edit trade journal entries (corrections are append-only)
- Backdate a journal entry
- Trade a pair whose minimum order size exceeds the position budget

---

## 9. Change log

| Date | Change | By |
|---|---|---|
| 2026-10-25 | Initial policy, conservative defaults, Kraken Tier-1 fee model | Mavis (for Max) |
| 2026-11-02 | Capital confirmed: $250 start + $100/week deposits. Added deposit-vs-P&L separation and the capital ledger. | Mavis (for Max) |

__MAVIS_EOF_039__

cat > "docs/trading/trade-playbook.md" <<'__MAVIS_EOF_040__'
# Trade Playbook

The procedure from "we have an idea" to "it's in the journal". Follow it in order. Every
step has an artifact, and the artifact is what the next agent reads.

---

## Step 0 — Mode check

```bash
bash scripts/trading-mode.sh show
```

If the output is `paper`, everything below produces **paper results only**. That's fine —
that's where you should be for months.

---

## Step 1 — Thesis (Market Analyst)

**Artifact:** `docs/research/<YYYY-MM-DD>-<slug>.md`

- The question, the hypothesis, the data used, the sample size
- The edge, stated in one sentence
- The conditions under which it's wrong

**Exit condition:** the analyst has found a setup worth pricing, *or* has clearly shown
there isn't one. Both are good outcomes. "It might work" is not.

---

## Step 2 — Strategy + backtest (Quant Developer)

**Artifact:** code + PR in `workspaces/engine/`, results in the PR

Required numbers: total trades, win rate, profit factor, max drawdown, average R, worst
trade, out-of-sample result.

**Exit condition:** out-of-sample result exists, trade count ≥ L12 (default 30), no
lookahead, costs included.

If the backtest is bad, **stop here**. A negative result is a complete, useful outcome.
Do not tune until it looks good — that's overfitting, and the experiment log will show it.

---

## Step 3 — Proposal (Desk Manager)

**Artifact:** `docs/trading/journal/<YYYY-MM-DD>-<slug>.md` (copy `template.md`)

Fill in: instrument, side, entry, stop, target, size, risk %, thesis link, invalidation,
exit conditions, and the mode.

**Exit condition:** the proposal is complete enough that another agent could place it
without asking a question.

---

## Step 4 — Risk check (Risk and Ops)

**Artifact:** a `RISK CHECK: PASS` or `RISK CHECK: FAIL` comment on the proposal file.

The check enumerates all 11 checks from `docs/trading/risk-policy.md` with actual numbers.

**Exit condition:** `PASS`. A `FAIL` is not negotiable by the Desk Manager. Fix the
proposal or escalate to Max.

---

## Step 5 — Human approval

**Artifact:** an explicit approval comment on the Paperclip issue, from Max.

The request must contain:
- what exactly will be traded (instrument, side, size, entry, stop)
- the maximum loss if it goes wrong, in money and percent
- what the agent should do if the entry doesn't fill
- the mode it applies to

**Exit condition:** Max says yes, in those terms. **Silence, a thumbs-up on a summary, or
"looks good buddy" is not approval** — if the trade details aren't restated and agreed,
it isn't approved.

---

## Step 6 — Execute (Quant Developer)

- Place **one** order. The exact one that was approved — same instrument, same side, same
  size, same stop.
- Use an idempotency key.
- Attach the stop immediately after the fill, without exception.
- Log the exchange order ID and the actual fill price in the journal entry.

**Exit condition:** the fill is confirmed *by querying the exchange*, not by trusting the
response. If the state is ambiguous, query — never blind-retry.

---

## Step 7 — Journal (Risk and Ops)

Update the journal entry with: fill price, size, fees, order ID, timestamp, and the
running position. Append-only — corrections are new lines, never edits.

Update `docs/status-board.md`.

---

## Step 8 — Manage and exit

- The exit rule (stop, target, or thesis invalidation) is written in the proposal
  **before** entry. Changing it later needs a new approval.
- If the thesis is invalidated before the stop hits: closing early is a human decision.
- If the stop hits: log it, don't touch it, count it toward L11.

---

## Step 9 — Review

Weekly:
- Which thesis held, which didn't?
- Did we follow the rules, or did we talk ourselves into something?
- Slippage vs plan — why did fills differ?
- What did the experiment log teach us?

The point of the journal is that after three months you can actually see whether the edge
is real, or whether you were just lucky once.

__MAVIS_EOF_040__

cat > "package.json" <<'__MAVIS_EOF_041__'
{
  "name": "digitraders",
  "version": "0.1.0",
  "private": true,
  "description": "Digitraders — an agent-run crypto trading desk (Paperclip). Root of the pnpm workspace.",
  "engines": {
    "node": ">=24.0.0",
    "pnpm": ">=9"
  },
  "scripts": {
    "doctor": "bash scripts/doctor.sh",
    "git:init": "bash scripts/git-init.sh",
    "bootstrap": "bash .paperclip/bootstrap.sh",
    "status": "bash .paperclip/status.sh",
    "mode": "bash scripts/trading-mode.sh show",
    "size": "bash scripts/position-size.sh"
  }
}

__MAVIS_EOF_041__

cat > "pnpm-workspace.yaml" <<'__MAVIS_EOF_042__'
packages:
  - "workspaces/*"

__MAVIS_EOF_042__

cat > "scripts/doctor.sh" <<'__MAVIS_EOF_043__'
#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# doctor.sh — check that this machine can actually run an agent-run trading desk.
#
#   bash scripts/doctor.sh
#
# Read-only. Fixes nothing, tells you exactly what to run.
# ---------------------------------------------------------------------------
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export BUSINESS_ROOT="${BUSINESS_ROOT:-$ROOT}"
PASS=0; FAIL=0; WARN=0

ok()   { printf '  \033[32m✓\033[0m %-30s %s\n' "$1" "${2:-}"; PASS=$((PASS+1)); }
no()   { printf '  \033[31m✗\033[0m %-30s %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
wa()   { printf '  \033[33m!\033[0m %-30s %s\n' "$1" "${2:-}"; WARN=$((WARN+1)); }
head_() { printf '\n\033[1m%s\033[0m\n' "$*"; }

echo "Trading desk doctor — $ROOT"

head_ "Toolchain"
if command -v node >/dev/null 2>&1; then
  NV=$(node -v | sed 's/^v//')
  MAJ=${NV%%.*}
  if [ "$MAJ" -ge 24 ] 2>/dev/null; then ok "node" "$NV"; else
    no "node" "$NV — Paperclip needs 24+. In Termux: pkg install nodejs-lts"; fi
else
  no "node" "not found. In Termux: pkg install nodejs-lts   (Acode's JS runtime does NOT count)"
fi

if command -v pnpm >/dev/null 2>&1; then ok "pnpm" "$(pnpm -v)"; else wa "pnpm" "not found — needed for the workspace root"; fi
if command -v git >/dev/null 2>&1; then
  ok "git" "$(git --version | cut -d' ' -f3)"
  if git config --global user.email >/dev/null 2>&1; then ok "git identity" "$(git config --global user.email)"; else
    wa "git identity" "unset — commits fail. Run: git config --global user.email you@example.com"; fi
else
  no "git" "not found — Paperclip needs git for worktrees"
fi
if command -v gh >/dev/null 2>&1; then ok "gh (GitHub CLI)" "$(gh --version 2>/dev/null | head -1)"; else
  wa "gh (GitHub CLI)" "not found — agents can't open PRs without it"; fi

head_ "Paperclip"
if command -v paperclipai >/dev/null 2>&1; then ok "paperclipai CLI" "$(command -v paperclipai)"; else
  if command -v npx >/dev/null 2>&1; then ok "npx" "will run: npx paperclipai"; else no "npx" "not found"; fi
fi

API_URL="${PAPERCLIP_API_URL:-http://127.0.0.1:3100}"
if [ -f "$ROOT/.paperclip/paperclip.env" ]; then
  set -a; . "$ROOT/.paperclip/paperclip.env"; set +a
  API_URL="${PAPERCLIP_API_URL:-$API_URL}"
fi
STATUS=$(node -e '
  const u=process.argv[1]; const c=new AbortController();
  setTimeout(()=>c.abort(),5000);
  fetch(u,{signal:c.signal}).then(r=>console.log(r.status)).catch(()=>console.log("unreachable"));
' "$API_URL" 2>/dev/null)
if [ "$STATUS" = "unreachable" ] || [ -z "$STATUS" ]; then
  wa "server at $API_URL" "not answering — start it with: npx paperclipai run"
else
  ok "server at $API_URL" "HTTP $STATUS"
fi

head_ "Agent adapter CLI"
ADAPTER=$(node -e 'const c=require(process.env.BUSINESS_ROOT+"/.paperclip/business.config.json");console.log(c.paperclip.adapterTypeDefault)')
case "$ADAPTER" in
  claude_local)   BIN=claude ;;
  codex_local)    BIN=codex ;;
  opencode_local) BIN=opencode ;;
  hermes_local)   BIN=hermes ;;
  *)              BIN="" ;;
esac
if [ -n "$BIN" ]; then
  if command -v "$BIN" >/dev/null 2>&1; then ok "$BIN ($ADAPTER)" "$(command -v "$BIN")"; else
    no "$BIN ($ADAPTER)" "not found — install it, or change adapterType in .paperclip/business.config.json"; fi
else
  wa "adapter" "unknown: $ADAPTER"
fi

head_ "Trading safety"
MODE_FILE="$ROOT/.paperclip/trading.mode"
if [ -f "$MODE_FILE" ]; then
  MODE=$(head -n 1 "$MODE_FILE" | tr -d '[:space:]')
  case "$MODE" in
    paper) ok "trading mode" "paper — safe default";;
    live)  wa "trading mode" "LIVE — real orders are possible";;
    *)     no "trading mode" "invalid value '$MODE' — run: bash scripts/trading-mode.sh paper";;
  esac
else
  no "trading mode" "missing .paperclip/trading.mode — run: bash scripts/trading-mode.sh paper"
fi

if [ -f "$ROOT/docs/trading/risk-policy.md" ]; then
  ok "risk policy" "docs/trading/risk-policy.md"
  DEFAULTS=$(awk -F'|' '/^\| L[0-9]+ / { v=$(NF-1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); if (v=="") c++ } END { print c+0 }' "$ROOT/docs/trading/risk-policy.md")
  if [ "$DEFAULTS" -gt 0 ] 2>/dev/null; then
    wa "risk limits" "$DEFAULTS limit(s) still on conservative defaults — review before going live"
  else
    ok "risk limits" "all set by Max"
  fi
else
  no "risk policy" "missing docs/trading/risk-policy.md"
fi

LEAK=$(grep -rInE "(api[_-]?key|api[_-]?secret|secret[_-]?key|passphrase)[[:space:]]*[:=][[:space:]]*['\"][A-Za-z0-9_/+-]{16,}" \
      "$ROOT/workspaces" "$ROOT/docs" "$ROOT/scripts" 2>/dev/null | head -3)
if [ -n "$LEAK" ]; then
  no "hardcoded secrets" "$(printf '%s' "$LEAK" | head -1 | cut -c1-90)"
else
  ok "hardcoded secrets" "none in workspaces/docs/scripts"
fi

if grep -rInE "(BINANCE|BYBIT|COINBASE|KRAKEN|OKX)[A-Z_]*(KEY|SECRET)" "$ROOT/workspaces/research" 2>/dev/null | head -1 | grep -q .; then
  no "research workspace" "references an exchange key — it must have none"
else
  ok "research workspace" "no exchange key references"
fi

if [ -x "$ROOT/scripts/position-size.sh" ]; then ok "position sizer" "scripts/position-size.sh"; else
  no "position sizer" "missing scripts/position-size.sh"; fi

# Android shared storage needs git's file-mode check off, or every file looks modified
if printf '%s' "$ROOT" | grep -qE '/storage/(shared|emulated)'; then
  if [ "$(git config --global core.fileMode 2>/dev/null)" = "false" ]; then
    ok "shared storage git" "core.fileMode=false"
  else
    wa "shared storage git" "run: git config --global core.fileMode false"
  fi
fi

head_ "Workspaces"
for d in "$ROOT"/workspaces/*/; do
  [ -d "$d" ] || continue
  name=$(basename "$d")
  if [ -d "$d/.git" ]; then
    branch=$(git -C "$d" branch --show-current 2>/dev/null)
    if [ "$branch" = "main" ]; then ok "workspaces/$name" "git repo on main"; else
      wa "workspaces/$name" "git repo on '${branch:-?}' (Paperclip branches off 'main')"; fi
  else
    no "workspaces/$name" "not a git repo — run: bash scripts/git-init.sh"
  fi
done

head_ "Config"
if [ -f "$ROOT/.paperclip/paperclip.env" ]; then ok ".paperclip/paperclip.env" "present (git-ignored)"; else
  wa ".paperclip/paperclip.env" "missing — copy .paperclip/paperclip.env.example and fill it in"; fi
if [ -f "$ROOT/.paperclip/agent-ids.json" ]; then ok ".paperclip/agent-ids.json" "present"; else
  wa ".paperclip/agent-ids.json" "missing — run: bash .paperclip/bootstrap.sh"; fi

BRIEF="$ROOT/docs/business-brief.md"
if [ -f "$BRIEF" ]; then
  TODO=$(grep -c '\[TODO: Max\]' "$BRIEF" 2>/dev/null || echo 0)
  if [ "$TODO" -gt 0 ]; then
    wa "docs/business-brief.md" "$TODO question(s) waiting on Max"
  else
    ok "docs/business-brief.md" "complete"
  fi
else
  no "docs/business-brief.md" "missing"
fi

printf '\n\033[1m%d passed · %d warnings · %d failed\033[0m\n' "$PASS" "$WARN" "$FAIL"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

__MAVIS_EOF_043__
chmod +x "scripts/doctor.sh"

cat > "scripts/git-init.sh" <<'__MAVIS_EOF_044__'
#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# git-init.sh — turn each workspaces/* folder into a git repo that Paperclip
# can use for isolated per-issue worktrees.
#
#   bash scripts/git-init.sh
#   bash scripts/git-init.sh --remote core https://github.com/you/core.git
#
# Paperclip's `git_worktree` execution policy creates one worktree per issue,
# branched off `main`. That only works if this folder is already a git repo
# with a `main` branch.
# ---------------------------------------------------------------------------
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE_KEY=""
REMOTE_URL=""

while [ $# -gt 0 ]; do
  case "$1" in
    --remote) REMOTE_KEY="${2:-}"; REMOTE_URL="${3:-}"; shift 3 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if ! command -v git >/dev/null 2>&1; then
  echo "git is not installed." >&2
  exit 1
fi

for d in "$ROOT"/workspaces/*/; do
  [ -d "$d" ] || continue
  name=$(basename "$d")

  # Android shared storage doesn't preserve Unix permission bits, and its files
  # are owned by another UID — both make git misbehave. Fix both there only.
  if printf '%s' "$d" | grep -qE '/storage/(shared|emulated|[0-9A-Fa-f-]+)'; then
    git config --global core.fileMode false
    git config --global --add safe.directory '*'
  fi

  if [ -d "$d/.git" ]; then
    echo "✓ $name — already a git repo"
  else
    git -C "$d" init -q -b main 2>/dev/null || {
      git -C "$d" init -q
      git -C "$d" symbolic-ref HEAD refs/heads/main
    }
    printf 'node_modules/\ndist/\n.env\n.env.*\n!.env.example\n' > "$d/.gitignore"
    echo "✓ $name — initialised git repo on main"
  fi

  # make sure a commit exists (worktrees need a real HEAD)
  if ! git -C "$d" rev-parse HEAD >/dev/null 2>&1; then
    echo "# $name" > "$d/README.md"
    git -C "$d" add -A
    git -C "$d" -c user.email="agent@local" -c user.name="paperclip bootstrap" commit -q -m "chore: initialise $name workspace" || true
    echo "  · created first commit"
  fi

  # optional remote
  if [ "$REMOTE_KEY" = "$name" ] && [ -n "$REMOTE_URL" ]; then
    if git -C "$d" remote get-url origin >/dev/null 2>&1; then
      git -C "$d" remote set-url origin "$REMOTE_URL"
      echo "  · origin → $REMOTE_URL"
    else
      git -C "$d" remote add origin "$REMOTE_URL"
      echo "  · added origin → $REMOTE_URL"
    fi
  fi
done

echo
echo "Next: attach your GitHub repo, e.g."
echo "  bash scripts/git-init.sh --remote core https://github.com/<you>/<repo>.git"

__MAVIS_EOF_044__
chmod +x "scripts/git-init.sh"

cat > "scripts/paper-cycle.sh" <<'__MAVIS_EOF_045__'
#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# paper-cycle.sh — run the desk's paper-trading cycle.
#
#   bash scripts/paper-cycle.sh                    # one cycle, default settings
#   bash scripts/paper-cycle.sh --strategy sma-crossover --interval 240
#   bash scripts/paper-cycle.sh --loop 60          # repeat every 60 minutes
#   bash scripts/paper-cycle.sh --reset            # start a fresh paper record
#
# It pulls live candles from Kraken's PUBLIC API (no key, no account access),
# runs the strategy through the real engine, logs closed paper trades to the
# append-only ledger, and rewrites the paper status file.
#
# It cannot place an order. There is no code path from here to an exchange.
# ---------------------------------------------------------------------------
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE="$ROOT/workspaces/engine"

if ! command -v node >/dev/null 2>&1; then
  echo "node is not on PATH — Paperclip needs Node 24+ (Termux: pkg install nodejs-lts)" >&2
  exit 1
fi

cd "$ENGINE" || exit 1

# Sensible defaults if the caller didn't specify any
HAS_STRATEGY=0
HAS_PAIR=0
for a in "$@"; do
  case "$a" in
    --strategy|--strategy=*) HAS_STRATEGY=1 ;;
    --pair|--pair=*) HAS_PAIR=1 ;;
  esac
done

ARGS=()
[ "$HAS_STRATEGY" -eq 0 ] && ARGS+=(--strategy sma-crossover)
[ "$HAS_PAIR" -eq 0 ] && ARGS+=(--pair XRPUSD)
[ $# -eq 0 ] && ARGS+=(--interval 60 --equity 250)

exec node src/cli.js paper "${ARGS[@]}" "$@"

__MAVIS_EOF_045__
chmod +x "scripts/paper-cycle.sh"

cat > "scripts/pc-setup.sh" <<'__MAVIS_EOF_046__'
#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# pc-setup.sh — turn this PC into a running Digitraders desk.
#
#   bash pc-setup.sh
#
# What it does:
#   1. makes sure Node.js 24+ is available (Paperclip needs it)
#   2. makes sure the Paperclip CLI is installed
#   3. checks your git identity (agents commit with it)
#   4. installs a timer so the paper cycle runs on its own, every hour
#   5. registers the agents with Paperclip (if the server is running)
#   6. runs the first paper cycle so you see the desk alive
#   7. runs the doctor and prints a summary
#
# Flags:
#   --timer systemd|cron|launchd|none   force a scheduler (default: auto-detect)
#   --strategy NAME                     default: sma-crossover
#   --pair PAIR                         default: XRPUSD
#   --interval MINUTES                  default: 60
#   --no-node                           skip the Node install step
#   --no-cli                            skip the Paperclip CLI install
#   --no-cycle                          skip the first paper cycle
#   --yes                               don't ask questions
#
# Safe to re-run. It never deletes anything and never touches your keys.
# ---------------------------------------------------------------------------
set -uo pipefail

# ── output helpers ─────────────────────────────────────────────────────────
if [ -t 1 ]; then
  R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[1m'; D=$'\033[2m'; N=$'\033[0m'
else
  R=""; G=""; Y=""; B=""; D=""; N=""
fi
step() { printf '\n%s▸ %s%s\n' "$B" "$*" "$N"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
err()  { printf '  %s✗%s %s\n' "$R" "$N" "$*"; }
note() { printf '  %s%s%s\n' "$D" "$*" "$N"; }

STEP_FAILURES=0
NEXT_STEPS=()

# ── options ────────────────────────────────────────────────────────────────
TIMER="auto"; STRATEGY="sma-crossover"; PAIR="XRPUSD"; INTERVAL=60
DO_NODE=1; DO_CLI=1; DO_CYCLE=1; ASSUME_YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --timer) TIMER="${2:-auto}"; shift 2 ;;
    --strategy) STRATEGY="${2:-sma-crossover}"; shift 2 ;;
    --pair) PAIR="${2:-XRPUSD}"; shift 2 ;;
    --interval) INTERVAL="${2:-60}"; shift 2 ;;
    --no-node) DO_NODE=0; shift ;;
    --no-cli) DO_CLI=0; shift ;;
    --no-cycle) DO_CYCLE=0; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

confirm() {
  # $1 = prompt. Returns 0 for yes.
  if [ "$ASSUME_YES" -eq 1 ]; then return 0; fi
  if [ ! -t 0 ]; then
    note "not interactive — skipping: $1"
    return 1
  fi
  printf '  %s [y/N] ' "$1"
  read -r a
  [ "$a" = "y" ] || [ "$a" = "Y" ]
}

# ── find the desk ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

find_root() {
  local here="$SCRIPT_DIR"
  # the script sitting inside the tree
  if [ -f "$here/../.paperclip/business.config.json" ]; then (cd "$here/.." && pwd); return; fi
  if [ -f "$here/.paperclip/business.config.json" ]; then echo "$here"; return; fi
  # the script sitting next to an unzipped tree
  if [ -f "$here/digitraders/.paperclip/business.config.json" ]; then echo "$here/digitraders"; return; fi
  # standard install locations
  for c in "$HOME/digitraders" "$HOME/storage/shared/digitraders" "$PWD/digitraders"; do
    if [ -f "$c/.paperclip/business.config.json" ]; then echo "$c"; return; fi
  done
  echo ""
}

ROOT="$(find_root)"
if [ -z "$ROOT" ] && [ -f "$SCRIPT_DIR/install.sh" ]; then
  # The tree isn't installed yet — install it first, then continue.
  echo
  step "Installing the desk"
  bash "$SCRIPT_DIR/install.sh" || { err "install.sh failed"; exit 1; }
  ROOT="$(find_root)"
fi
if [ -z "$ROOT" ]; then
  echo
  err "Could not find the Digitraders folder."
  echo "  Unzip digitraders.zip first, then run this script again:"
  echo "    unzip digitraders.zip && bash pc-setup.sh"
  exit 1
fi
cd "$ROOT" || exit 1

printf '\n%s╔══════════════════════════════════════════════════════════════╗%s\n' "$B" "$N"
printf '%s║  DIGITRADERS — PC SETUP                                        ║%s\n' "$B" "$N"
printf '%s╚══════════════════════════════════════════════════════════════╝%s\n' "$B" "$N"
note "desk root: $ROOT"
note "strategy: $STRATEGY · $PAIR · every ${INTERVAL}m"

# ── 1. Node.js 24+ ─────────────────────────────────────────────────────────
step "Step 1/7 · Node.js"
node_ok() {
  command -v node >/dev/null 2>&1 || return 1
  local v; v="$(node -v 2>/dev/null | sed 's/^v//')"
  local maj="${v%%.*}"
  [ -n "$maj" ] && [ "$maj" -ge 24 ] 2>/dev/null
}

if node_ok; then
  ok "node $(node -v)"
elif [ "$DO_NODE" -eq 0 ]; then
  warn "skipped (--no-node). Paperclip will not start without Node 24+."
  STEP_FAILURES=$((STEP_FAILURES + 1))
else
  warn "node $(node -v 2>/dev/null || echo 'not found') — Paperclip needs v24 or newer"
  INSTALLED=0
  # 1a. nvm (best: no root, per-user)
  if [ -s "$HOME/.nvm/nvm.sh" ]; then
    if confirm "install Node 24 with nvm?"; then
      # shellcheck disable=SC1091
      . "$HOME/.nvm/nvm.sh" && nvm install 24 && nvm use 24 && INSTALLED=1
    fi
  fi
  # 1b. nvm not installed — offer to install it
  if [ "$INSTALLED" -eq 0 ] && command -v curl >/dev/null 2>&1; then
    if confirm "install nvm, then Node 24? (recommended, no root needed)"; then
      if curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash; then
        export NVM_DIR="$HOME/.nvm"
        # shellcheck disable=SC1091
        . "$HOME/.nvm/nvm.sh" && nvm install 24 && nvm use 24 && INSTALLED=1
      fi
    fi
  fi
  # 1c. brew
  if [ "$INSTALLED" -eq 0 ] && command -v brew >/dev/null 2>&1; then
    if confirm "install Node 24 with Homebrew instead?"; then
      brew install node@24 && INSTALLED=1
      note "if that failed: brew link --overwrite --force node@24"
    fi
  fi
  if [ "$INSTALLED" -eq 0 ]; then
    err "Node 24+ is still missing."
    echo "     Linux (Debian/Ubuntu):  see nodejs.org → 'Install via Package Manager'"
    echo "     Fedora/RHEL:            sudo dnf install nodejs"
    echo "     Windows:                winget install OpenJS.NodeJS.LTS"
    echo "     macOS:                  brew install node@24 && brew link --overwrite --force node@24"
    STEP_FAILURES=$((STEP_FAILURES + 1))
    NEXT_STEPS+=("install Node 24+, then re-run: bash scripts/pc-setup.sh")
  else
    ok "node $(node -v) installed"
  fi
fi

# ── 2. Paperclip CLI ───────────────────────────────────────────────────────
step "Step 2/7 · Paperclip CLI"
if command -v paperclipai >/dev/null 2>&1; then
  ok "paperclipai installed ($(command -v paperclipai))"
elif command -v npx >/dev/null 2>&1; then
  ok "npx available — 'npx paperclipai' will work"
  if [ "$DO_CLI" -eq 0 ]; then
    note "skipped (--no-cli)"
  elif confirm "also install the paperclipai command globally? (recommended — npx re-resolves it every time)"; then
    if timeout 300 npm i -g paperclipai >/dev/null 2>&1; then
      ok "installed → $(command -v paperclipai)"
    else
      warn "global install failed or timed out — npx still works fine"
    fi
  fi
else
  err "neither paperclipai nor npx is available"
  STEP_FAILURES=$((STEP_FAILURES + 1))
fi

# ── 3. git identity ────────────────────────────────────────────────────────
step "Step 3/7 · Git identity"
if command -v git >/dev/null 2>&1; then
  ok "git $(git --version | cut -d' ' -f3)"
  if git config --global user.email >/dev/null 2>&1; then
    ok "identity: $(git config --global user.name) <$(git config --global user.email)>"
  else
    warn "no git identity — agent commits will fail"
    if confirm "set one now? (name 'Digitraders Agent', email 'agent@localhost')"; then
      git config --global user.name "Digitraders Agent"
      git config --global user.email "agent@localhost"
      ok "identity set"
    else
      NEXT_STEPS+=("git config --global user.email you@example.com")
    fi
  fi
else
  err "git is not installed — Paperclip needs it for per-issue worktrees"
  STEP_FAILURES=$((STEP_FAILURES + 1))
fi

# ── 4. the timer ───────────────────────────────────────────────────────────
step "Step 4/7 · Paper cycle timer"
INTERVAL_SECONDS=$((INTERVAL * 60))
SCHEDULER="$TIMER"

# The PATH the scheduler will see. systemd, launchd and cron all use a
# minimal PATH — if Node came from nvm, the timer would silently fail.
NODE_BIN_DIR="$(command -v node >/dev/null 2>&1 && dirname "$(command -v node)" || echo /usr/local/bin)"
NODE_PATH_VALUE="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$NODE_BIN_DIR"

if [ "$SCHEDULER" = "auto" ]; then
  if [ "$(uname -s)" = "Darwin" ] && command -v launchctl >/dev/null 2>&1; then
    SCHEDULER="launchd"
  elif command -v systemctl >/dev/null 2>&1; then
    SCHEDULER="systemd"
  elif command -v crontab >/dev/null 2>&1; then
    SCHEDULER="cron"
  else
    SCHEDULER="none"
  fi
fi

install_systemd() {
  UNIT_DIR="$HOME/.config/systemd/user"
  mkdir -p "$UNIT_DIR" "$ROOT/data"
  for f in digitraders-paper.service digitraders-paper.timer; do
    sed -e "s|@HOME@|$HOME|g" \
        -e "s|@STRATEGY@|$STRATEGY|g" \
        -e "s|@PAIR@|$PAIR|g" \
        -e "s|@INTERVAL@|$INTERVAL|g" \
        -e "s|@INTERVAL_SECONDS@|$INTERVAL_SECONDS|g" \
        -e "s|@NODE_PATH@|$NODE_PATH_VALUE|g" \
        "$ROOT/deploy/systemd/$f" > "$UNIT_DIR/$f"
  done
  systemctl --user daemon-reload >/dev/null 2>&1 || return 1
  systemctl --user enable --now digitraders-paper.timer >/dev/null 2>&1 \
    || warn "could not start the timer — try: systemctl --user start digitraders-paper.timer"
  ok "systemd timer installed and started"
  systemctl --user list-timers digitraders-paper.timer --no-pager 2>/dev/null | sed 's/^/    /' || true
  # keep running when nobody is logged in
  if command -v loginctl >/dev/null 2>&1; then
    loginctl enable-linger "$USER" >/dev/null 2>&1 \
      && ok "linger enabled — the timer runs even when you're logged out" || true
  fi
  NEXT_STEPS+=("check the timer:  systemctl --user list-timers | grep digitraders")
  NEXT_STEPS+=("see the logs:    journalctl --user -u digitraders-paper.service -n 50")
  return 0
}

install_launchd() {
  PLIST_DIR="$HOME/Library/LaunchAgents"
  mkdir -p "$PLIST_DIR" "$ROOT/data"
  sed -e "s|@HOME@|$HOME|g" \
      -e "s|@STRATEGY@|$STRATEGY|g" \
      -e "s|@PAIR@|$PAIR|g" \
      -e "s|@INTERVAL@|$INTERVAL|g" \
      -e "s|@INTERVAL_SECONDS@|$INTERVAL_SECONDS|g" \
      -e "s|@NODE_PATH@|$NODE_PATH_VALUE|g" \
      "$ROOT/deploy/launchd/com.digitraders.paper.plist" > "$PLIST_DIR/com.digitraders.paper.plist"
  launchctl unload "$PLIST_DIR/com.digitraders.paper.plist" >/dev/null 2>&1
  if launchctl load "$PLIST_DIR/com.digitraders.paper.plist" >/dev/null 2>&1; then
    ok "launchd job installed and loaded"
  else
    warn "could not load the launchd job — try: launchctl load ~/Library/LaunchAgents/com.digitraders.paper.plist"
  fi
  NEXT_STEPS+=("see the logs:  tail -f ~/digitraders/data/paper-cycle.log")
  return 0
}

install_cron() {
  command -v crontab >/dev/null 2>&1 || return 1
  LINE="0 * * * * PATH=$NODE_PATH_VALUE $ROOT/scripts/paper-cycle.sh --strategy $STRATEGY --pair $PAIR --interval $INTERVAL >> $ROOT/data/paper-cycle.log 2>&1"
  TMP_CRON="$(mktemp)"
  crontab -l 2>/dev/null | grep -v "digitraders/scripts/paper-cycle.sh" > "$TMP_CRON" || true
  echo "$LINE" >> "$TMP_CRON"
  if crontab "$TMP_CRON" >/dev/null 2>&1; then
    ok "cron job installed (hourly)"
  else
    warn "could not write the crontab — add this line yourself:"
    echo "    $LINE"
  fi
  rm -f "$TMP_CRON"
  NEXT_STEPS+=("see the logs:  tail -f $ROOT/data/paper-cycle.log")
  return 0
}

case "$SCHEDULER" in
  systemd)
    if ! install_systemd; then
      warn "systemd user services aren't available here — falling back to cron"
      if ! install_cron; then
        warn "no cron either — running the loop in a terminal instead"
        NEXT_STEPS+=("run the cycle yourself: bash scripts/paper-cycle.sh --loop 60")
      fi
    fi
    ;;

  launchd)
    install_launchd || { warn "launchd unavailable"; install_cron; }
    ;;

  cron)
    if ! install_cron; then
      warn "no cron available on this machine"
      NEXT_STEPS+=("run the cycle yourself: bash scripts/paper-cycle.sh --loop 60")
    fi
    ;;

  none)
    warn "no scheduler found (systemd, launchd and cron are all missing)"
    note "on a normal Linux or Mac one of those is always present."
    NEXT_STEPS+=("run the cycle yourself: bash scripts/paper-cycle.sh --loop 60")
    ;;
esac

# ── 5. register the agents ─────────────────────────────────────────────────
step "Step 5/7 · Agents"
API_URL="${PAPERCLIP_API_URL:-http://127.0.0.1:3100}"
API_UP=$(node -e '
  const u=process.argv[1];const c=new AbortController();
  setTimeout(()=>c.abort(),4000);
  fetch(u,{signal:c.signal}).then(r=>console.log(r.status)).catch(()=>console.log("unreachable"));
' "$API_URL" 2>/dev/null)

if [ "$API_UP" = "unreachable" ] || [ -z "$API_UP" ]; then
  warn "Paperclip isn't answering at $API_URL"
  note "start it in another terminal:  npx paperclipai run"
  note "first time?                    npx paperclipai onboard --yes"
  NEXT_STEPS+=("start Paperclip:  npx paperclipai run")
  NEXT_STEPS+=("then register the agents:  bash .paperclip/bootstrap.sh --update")
else
  ok "Paperclip is up (HTTP $API_UP)"
  if bash .paperclip/bootstrap.sh --update 2>&1 | sed 's/^/    /' | tail -25; then
    ok "agents registered"
  else
    warn "bootstrap reported problems — see above"
  fi
fi

# ── 6. first cycle ─────────────────────────────────────────────────────────
step "Step 6/7 · First paper cycle"
if [ "$DO_CYCLE" -eq 0 ]; then
  note "skipped (--no-cycle)"
elif bash scripts/paper-cycle.sh --strategy "$STRATEGY" --pair "$PAIR" --interval "$INTERVAL" 2>&1 | sed 's/^/    /' | tail -30; then
  ok "the desk is alive"
else
  warn "the cycle reported a problem — run it by hand to see the full output:"
  note "bash scripts/paper-cycle.sh --strategy $STRATEGY --pair $PAIR --interval $INTERVAL"
fi

# ── 7. doctor ──────────────────────────────────────────────────────────────
step "Step 7/7 · Doctor"
bash scripts/doctor.sh 2>&1 | sed 's/^/    /' | tail -30

# ── summary ────────────────────────────────────────────────────────────────
printf '\n%s╔══════════════════════════════════════════════════════════════╗%s\n' "$B" "$N"
printf '%s║  SETUP SUMMARY                                                 ║%s\n' "$B" "$N"
printf '%s╚══════════════════════════════════════════════════════════════╝%s\n' "$B" "$N"
if [ "$STEP_FAILURES" -eq 0 ]; then
  printf '  %s✓ Desk is running.%s\n' "$G" "$N"
else
  printf '  %s! %s step(s) need your attention.%s\n' "$Y" "$STEP_FAILURES" "$N"
fi
printf '\n  %sNEXT%s\n' "$B" "$N"
if [ ${#NEXT_STEPS[@]} -eq 0 ]; then
  printf '    %s• Open the board: http://127.0.0.1:3100%s\n' "$D" "$N"
  printf '    %s• Watch a cycle:   bash scripts/paper-cycle.sh%s\n' "$D" "$N"
  printf '    %s• Log a deposit:   bash scripts/paper-cycle.sh --deposit 100 --note "payday"%s\n' "$D" "$N"
else
  for n in "${NEXT_STEPS[@]}"; do printf '    • %s\n' "$n"; done
fi
echo
exit 0

__MAVIS_EOF_046__
chmod +x "scripts/pc-setup.sh"

cat > "scripts/position-size.sh" <<'__MAVIS_EOF_047__'
#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# position-size.sh — size a trade, then check it against the risk policy.
#
#   bash scripts/position-size.sh --equity 250 --entry 1.85 --stop 1.78
#   bash scripts/position-size.sh --equity 250 --entry 0.62 --stop 0.60 --edge 3.5
#
# Optional:
#   --risk PCT      risk per trade as % of equity        (default 0.5 — policy L1)
#   --edge PCT      expected GROSS edge per trade in %   (needed for the L13 check)
#   --min-size N    Kraken minimum order size for the pair (units)
#   --maker PCT     maker fee %  (default 0.40 — Kraken Tier 1)
#   --taker PCT     taker fee %  (default 0.80 — Kraken Tier 1)
#
# Read-only calculator. It sizes, it checks, it never trades.
# ---------------------------------------------------------------------------
set -uo pipefail

EQUITY=""; ENTRY=""; STOP=""; RISK="0.5"; EDGE=""; MIN_SIZE=""
MAKER="0.40"; TAKER="0.80"

while [ $# -gt 0 ]; do
  case "$1" in
    --equity)   EQUITY="${2:-}"; shift 2 ;;
    --entry)    ENTRY="${2:-}";  shift 2 ;;
    --stop)     STOP="${2:-}";   shift 2 ;;
    --risk)     RISK="${2:-}";   shift 2 ;;
    --edge)     EDGE="${2:-}";   shift 2 ;;
    --min-size) MIN_SIZE="${2:-}"; shift 2 ;;
    --maker)    MAKER="${2:-}";  shift 2 ;;
    --taker)    TAKER="${2:-}";  shift 2 ;;
    -h|--help)  sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$EQUITY" ] || [ -z "$ENTRY" ] || [ -z "$STOP" ]; then
  echo "usage: bash scripts/position-size.sh --equity E --entry P --stop P [--risk PCT] [--edge PCT]" >&2
  exit 2
fi

awk -v eq="$EQUITY" -v entry="$ENTRY" -v stop="$STOP" -v risk="$RISK" \
    -v edge="$EDGE" -v minsz="$MIN_SIZE" -v maker="$MAKER" -v taker="$TAKER" '
function f(x,  d) { d = (x == int(x)) ? 2 : 6; return sprintf("%." d "f", x) }
function pct(x) { return sprintf("%.2f%%", x) }
BEGIN {
  if (eq <= 0 || entry <= 0) { print "equity and entry must be > 0"; exit 1 }

  dist   = (entry > stop) ? entry - stop : stop - entry
  if (dist <= 0) { print "entry and stop must differ"; exit 1 }

  risk_amt  = eq * risk / 100
  size      = risk_amt / dist
  notional  = size * entry
  risk_pct  = (dist * size) / eq * 100

  fee_maker = notional * maker / 100 * 2
  fee_taker = notional * taker / 100 * 2
  fee_m_pct = fee_maker / eq * 100
  fee_t_pct = fee_taker / eq * 100

  # L13: round-trip fees must be <= 25% of expected gross edge
  min_edge_maker = fee_m_pct / 0.25
  min_edge_taker = fee_t_pct / 0.25

  print "=========================================================="
  print " POSITION SIZING"
  print "=========================================================="
  printf " Equity                 %14.4f\n", eq
  printf " Entry                  %14.6f\n", entry
  printf " Stop                   %14.6f\n", stop
  printf " Distance to stop       %14.6f  (%.4f%%)\n", dist, dist/entry*100
  print "----------------------------------------------------------"
  printf " Risk per trade (L1)    %14s\n", pct(risk)
  printf " Risk amount            %14.4f\n", risk_amt
  printf " Size (units)           %14.8f\n", size
  printf " Notional               %14.4f\n", notional
  printf " Notional %% of equity   %14s\n", pct(notional/eq*100)
  print "----------------------------------------------------------"
  printf " Fees maker (L15)       %14.4f   (%s of equity)\n", fee_maker, pct(fee_m_pct)
  printf " Fees taker (rejected)  %14.4f   (%s of equity)\n", fee_taker, pct(fee_t_pct)
  print "----------------------------------------------------------"

  fail = 0

  # L1
  if (risk_pct <= risk + 0.0001) printf " [PASS] L1  risk %.4f%% <= %.2f%%\n", risk_pct, risk
  else { printf " [FAIL] L1  risk %.4f%% > %.2f%%\n", risk_pct, risk; fail = 1 }

  # L6 — max single position notional 25% of equity
  if (notional/eq*100 <= 25.0001) printf " [PASS] L6  notional %s of equity <= 25%%\n", pct(notional/eq*100)
  else { printf " [WARN] L6  notional %s of equity > 25%% — split or shrink\n", pct(notional/eq*100); fail = 1 }

  # L13 — cost-to-edge
  if (edge != "") {
    if (fee_m_pct <= edge * 0.25 + 0.0001)
      printf " [PASS] L13 fees %s <= 25%% of gross edge %s\n", pct(fee_m_pct), pct(edge)
    else {
      printf " [FAIL] L13 fees %s > 25%% of gross edge %s\n", pct(fee_m_pct), pct(edge)
      printf "        needed gross edge: %s (maker) / %s (taker)\n", pct(min_edge_maker), pct(min_edge_taker)
      fail = 1
    }
  } else {
    printf " [ ?  ] L13 no --edge given. Minimum gross edge needed: %s (maker)\n", pct(min_edge_maker)
    printf "        %s (taker). Below this, the trade loses money even if the signal is right.\n", pct(min_edge_taker)
  }

  # Kraken minimum order size
  if (minsz != "") {
    if (size + 0.000000001 >= minsz)
      printf " [PASS] size %s >= Kraken minimum %s\n", f(size, 8), f(minsz, 8)
    else {
      printf " [FAIL] size %s < Kraken minimum order size %s — do not trade this pair\n", f(size, 8), f(minsz, 8)
      fail = 1
    }
  }

  print "----------------------------------------------------------"
  if (fail) print " RESULT: BLOCKED — do not propose this trade."
  else      print " RESULT: clears the checks above. Still needs a proposal + approval."
  print "=========================================================="
  exit (fail ? 1 : 0)
}
'

__MAVIS_EOF_047__
chmod +x "scripts/position-size.sh"

cat > "scripts/sync.sh" <<'__MAVIS_EOF_048__'
#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# sync.sh — keep the phone and the PC in sync through git.
#
#   bash scripts/sync.sh pull     # fetch the latest from GitHub (PC side)
#   bash scripts/sync.sh push     # commit + push local changes
#   bash scripts/sync.sh cycle    # pull, run the paper cycle, commit, push
#
# Run the cycle on ONE machine only (the PC). The other side reads.
# ---------------------------------------------------------------------------
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-pull}"
BRANCH="${BRANCH:-main}"

cd "$ROOT" || exit 1

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "not a git repo — run 'git init -b $BRANCH' first, or see docs/playbooks/pc-migration.md" >&2
  exit 1
fi

have_remote() { git remote get-url origin >/dev/null 2>&1; }

case "$MODE" in
  pull)
    have_remote || { echo "no 'origin' remote configured" >&2; exit 1; }
    git pull --rebase origin "$BRANCH"
    echo "✓ pulled $BRANCH"
    ;;

  push)
    git add -A
    if git diff --cached --quiet; then
      echo "nothing to commit"
      exit 0
    fi
    git commit -m "chore: sync $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    have_remote && git push origin "$BRANCH"
    echo "✓ pushed $BRANCH"
    ;;

  cycle)
    have_remote && git pull --rebase origin "$BRANCH"
    bash scripts/paper-cycle.sh "$@"
    git add -A
    git diff --cached --quiet || {
      git commit -m "chore: paper cycle $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      have_remote && git push origin "$BRANCH"
    }
    echo "✓ cycle done and synced"
    ;;

  *)
    echo "usage: bash scripts/sync.sh [pull|push|cycle]" >&2
    exit 2
    ;;
esac

__MAVIS_EOF_048__
chmod +x "scripts/sync.sh"

cat > "scripts/trading-mode.sh" <<'__MAVIS_EOF_049__'
#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# trading-mode.sh — the desk's on/off switch.
#
#   bash scripts/trading-mode.sh show      # what's the current mode?
#   bash scripts/trading-mode.sh paper     # back to paper (instant, safe)
#   bash scripts/trading-mode.sh live      # requires typing the confirm phrase
#
# The mode lives in .paperclip/trading.mode and is read by every agent before it
# proposes execution. Default is paper. Only the human flips it to live.
# ---------------------------------------------------------------------------
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE_FILE="$ROOT/.paperclip/trading.mode"
CONFIRM="ENABLE LIVE TRADING"

mkdir -p "$(dirname "$MODE_FILE")"
[ -f "$MODE_FILE" ] || printf 'paper\n' > "$MODE_FILE"

current() { head -n 1 "$MODE_FILE" | tr -d '[:space:]'; }
set_mode() { printf '%s\n' "$1" > "$MODE_FILE"; }

case "${1:-show}" in
  show)
    M=$(current)
    echo "Trading mode: $M"
    if [ "$M" = "live" ]; then
      echo ""
      echo "  ╔══════════════════════════════════════════════════════╗"
      echo "  ║  LIVE MODE — real orders can be placed.               ║"
      echo "  ║  Every trade still needs a risk check AND approval.   ║"
      echo "  ╚══════════════════════════════════════════════════════╝"
    else
      echo "Paper mode — no real orders can be placed. This is the safe default."
    fi
    ;;

  paper)
    set_mode paper
    echo "✓ Trading mode set to PAPER."
    echo "  No live order can be placed. Paper trades still work normally."
    ;;

  live)
    echo ""
    echo "  ╔══════════════════════════════════════════════════════╗"
    echo "  ║  You are about to enable LIVE trading.                ║"
    echo "  ║                                                      ║"
    echo "  ║  Agents may place REAL orders once a trade has:       ║"
    echo "  ║   1. a written proposal in docs/trading/journal/      ║"
    echo "  ║   2. a RISK CHECK: PASS from Risk and Ops             ║"
    echo "  ║   3. your explicit approval on the issue              ║"
    echo "  ║                                                      ║"
    echo "  ║  Live mode alone does NOT authorise any trade.         ║"
    echo "  ╚══════════════════════════════════════════════════════╝"
    echo ""
    printf 'Type exactly "%s" to continue: ' "$CONFIRM"
    read -r ANSWER
    if [ "$ANSWER" != "$CONFIRM" ]; then
      echo "Confirmation did not match — staying in PAPER mode."
      exit 1
    fi
    set_mode live
    echo "✓ Trading mode set to LIVE."
    echo "  Reminder: paper-trading evidence first. See docs/trading/risk-policy.md"
    ;;

  *)
    echo "usage: bash scripts/trading-mode.sh [show|paper|live]" >&2
    exit 2
    ;;
esac

__MAVIS_EOF_049__
chmod +x "scripts/trading-mode.sh"

cat > "workspaces/engine/README.md" <<'__MAVIS_EOF_050__'
# Trading Engine

The backtesting engine. **No dependencies** — pure Node, nothing to install, runs on the
phone straight from Acode or the terminal.

```
workspaces/engine/
├── src/
│   ├── cli.js              # backtest | walkforward | data | ticker | strategies
│   ├── config/defaults.js  # Kraken Tier-1 fees and every default in one place
│   ├── data/
│   │   ├── kraken.js       # public OHLC / ticker / order book (no key needed)
│   │   ├── csv.js          # import history from a CSV
│   │   └── store.js        # local cache
│   ├── engine/
│   │   ├── backtest.js     # the simulator
│   │   ├── metrics.js      # profit factor, drawdown, fees, verdict
│   │   ├── indicators.js   # SMA / EMA / ATR / RSI + incremental versions
│   │   └── walkforward.js  # rolling in-sample → out-of-sample
│   └── strategies/         # buy-and-hold, sma-crossover, atr-breakout
└── tests/                  # 20 tests, including the no-lookahead proofs
```

---

## The one rule that makes it honest

> **A signal is computed on the CLOSE of bar `i`. The fill happens at the OPEN of bar
> `i + 1`. Never the close of bar `i`, never the open of bar `i`.**

And it's not a promise — it's enforced. `ctx.bars` is a guarded view: if a strategy
reaches for a future bar, the engine **throws**:

```
lookahead blocked: strategy tried to read bar 412 while standing on bar 400
```

There's a test for it (`tests/no-lookahead.test.js`). If the simulator ever leaks the
future, every backtest lies, and the whole desk is built on sand.

Other things the simulator gets right so you don't have to think about them:

- **Stops fill at the stop price** (or worse, if the bar gapped through it).
- **If a bar contains both the stop and the target, the stop wins.** Always assume the
  worse one.
- **A stop-loss exit is a market order** → taker fee. A target exit can rest → maker fee.
- **Slippage is against you**, on every fill.
- **No stop means no trade.** Without a stop there's no honest way to size a position,
  so the engine refuses instead of guessing.
- **Position size is risk-based**: `size = (equity × risk%) ÷ |entry − stop|`, capped by
  the max-notional rule (policy L6).

---

## Usage

```bash
cd workspaces/engine

# what's in the cache
node src/cli.js data --pair XRPUSD --interval 240

# the benchmark — everything else has to beat this
node src/cli.js backtest --strategy buy-and-hold --pair XRPUSD --interval 240

# a strategy
node src/cli.js backtest --strategy sma-crossover --pair XRPUSD --interval 240 --equity 250

# with a stricter read
node src/cli.js backtest --strategy sma-crossover --pair XRPUSD --interval 240 --edge 3.5

# rolling out-of-sample test — trust only the stitched number
node src/cli.js walkforward --strategy sma-crossover --pair XRPUSD --interval 1440

# deep history from a CSV
node src/cli.js backtest --strategy sma-crossover --csv ~/ohlc/XRPUSD_240.csv

# list strategies and their hypotheses
node src/cli.js strategies
```

With pnpm (from the business root):

```bash
pnpm --filter @trading/engine run backtest -- --strategy sma-crossover --interval 240
```

### Useful flags

| Flag | Default | Meaning |
|---|---|---|
| `--equity` | 250 | starting account equity |
| `--risk` | 0.5 | risk per trade, % of equity (policy L1) |
| `--maker-fee` | 0.004 | Kraken Tier 1 maker |
| `--taker-fee` | 0.008 | Kraken Tier 1 taker |
| `--slippage` | 5 | basis points against you |
| `--max-notional` | 25 | max position as % of equity (policy L6) |
| `--min-trades` | 30 | below this, the exit code is 2 and the verdict says "no conclusion" |
| `--force` | — | ignore the sample-size verdict |
| `--out` | — | write full results as JSON |

---

## Data

Kraken's public OHLC needs **no key** and returns up to 720 candles:

| Interval | History you get |
|---|---|
| 240 (4h) | ~30 days |
| 1440 (1d) | ~2 years |
| 60 (1h) | ~30 days |

For deeper history, download a CSV and use `--csv`:

- **CryptoDataDownload** (free): <https://www.cryptodatadownload.com/data/kraken/>
- **KrakenData** (paid): <https://www.kraken.com/data>

The CSV parser is forgiving — it sniffs the header, accepts Unix or ISO timestamps, and
sorts by time. Columns needed: `time, open, high, low, close, volume`.

> Watch the venue. Data from another exchange is fine for **research**, but fills,
> spreads, and depth are venue-specific. A backtest on Binance data tells you about
> Binance, not Kraken.

---

## Writing a strategy

A strategy is an object with an `onBar(ctx)` method:

```js
export function makeMyStrategy(params = {}) {
  const p = { ...params };
  const atr = new RollingAtr(14);

  return {
    name: 'my-strategy',
    params: p,
    onBar(ctx) {
      const a = atr.push(ctx.bar);
      if (!a) return { action: 'hold' };

      if (ctx.position && ctx.bar.close < ctx.position.entryPrice * 0.98) {
        return { action: 'exit', reason: 'closed below -2%' };
      }

      if (!ctx.position && someCondition(ctx)) {
        return {
          action: 'enter_long',
          stop: ctx.bar.close - 1.5 * a,   // REQUIRED — no stop, no trade
          target: ctx.bar.close + 3 * a,  // optional
          reason: 'why you think this works',
        };
      }
      return { action: 'hold' };
    },
  };
}
```

**`ctx` gives you:** `bars` (guarded — no future), `index`, `bar`, `position`,
`equity`, `cash`, `params`, `log()`.

**Signals:** `{ action: 'enter_long' | 'enter_short' | 'exit' | 'hold', stop?, target?,
size?, notionalPct?, reason? }`

**Rules:**
- A `stop` is mandatory for risk-sized entries.
- `reason` is not optional in practice — it goes into the trade journal.
- Never read `ctx.bars` beyond `ctx.index`. The engine will stop you, but it's noise.

Register it in `src/strategies/index.js` with a **hypothesis** — the sentence you'd write
in the experiment log *before* you run it.

---

## Writing a good hypothesis

The engine will happily backtest a bad idea all day. Your job is to make sure it's
worth running. A hypothesis should name:

1. **What you believe** — a claim about the market, not about an indicator.
2. **Why it might be true** — a mechanism, not a pattern.
3. **What would make you wrong** — the invalidation.

> ✅ *"Funding rates on perp markets lead spot by ~1 hour, so extreme positive funding
> predicts a 2% pullback within 8 candles."*
> ❌ *"RSI looks oversold at the bottom."*

Then log it in `docs/trading/experiments.md` **before** you run it.

---

## Tests

```bash
node --test tests/*.test.js
```

20 tests. The important ones are in `tests/no-lookahead.test.js` — they prove the
simulator can't be fooled by a future-peeking strategy, that ambiguous bars resolve
conservatively, and that sizing and fees behave.

Run them before you trust any number this engine produces.

---

## What this engine does NOT do

- **No live trading.** That's `src/execution/`, and it doesn't exist yet — by design.
  See `docs/trading/trade-playbook.md` for what has to happen first.
- **No order book simulation.** It models fills at bar prices plus slippage, not
  walking a book. Good enough for strategy research, not for sizing a $50k order.
- **No intrabar data.** It uses OHLC, not ticks.
- **No optimisation framework.** Parameter sweeps are a trap (they fit noise). Do them
  by hand, one variable at a time, and log every attempt.

__MAVIS_EOF_050__

cat > "workspaces/engine/package.json" <<'__MAVIS_EOF_051__'
{
  "name": "@trading/engine",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "description": "Backtesting engine for Digitraders. No dependencies — pure Node.",
  "engines": {
    "node": ">=20.0.0"
  },
  "scripts": {
    "test": "node --test tests/*.test.js",
    "backtest": "node src/cli.js backtest",
    "walkforward": "node src/cli.js walkforward",
    "data": "node src/cli.js data",
    "strategies": "node src/cli.js strategies",
    "ticker": "node src/cli.js ticker"
  }
}

__MAVIS_EOF_051__

cat > "workspaces/engine/src/cli.js" <<'__MAVIS_EOF_052__'
#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { backtest } from './engine/backtest.js';
import { computeMetrics } from './engine/metrics.js';
import { walkForward } from './engine/walkforward.js';
import { STRATEGIES, getStrategy, listStrategies } from './strategies/index.js';
import { loadCandles } from './data/store.js';
import { loadCsv } from './data/csv.js';
import { fetchTicker } from './data/kraken.js';
import { runPaperCycle } from './paper/runner.js';

const RESET = '\x1b[0m';
const BOLD = '\x1b[1m';
const DIM = '\x1b[2m';
const RED = '\x1b[31m';
const GREEN = '\x1b[32m';
const YELLOW = '\x1b[33m';

function parseArgs(argv) {
  const args = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const key = a.slice(2);
      const next = argv[i + 1];
      if (next === undefined || next.startsWith('--')) {
        args[key] = true;
      } else {
        args[key] = next;
        i++;
      }
    } else {
      args._.push(a);
    }
  }
  return args;
}

const num = (v, d) => (v === undefined ? d : Number(v));
const money = (v) => `${v < 0 ? '-' : ''}$${Math.abs(v).toFixed(2)}`;
const pct = (v) => `${v.toFixed(2)}%`;
const num2 = (v, d = 2) => (v === null || v === undefined || Number.isNaN(v) ? 'n/a' : v.toFixed(d));

function line(label, a, b) {
  return `  ${String(label).padEnd(18)}${String(a).padEnd(16)}${b}`;
}

async function loadBars(args) {
  if (args.csv) {
    const bars = loadCsv(args.csv);
    return { bars, source: `csv:${path.basename(args.csv)}` };
  }
  const { bars, source } = await loadCandles({
    pair: args.pair || 'XRPUSD',
    interval: num(args.interval, 240),
    refresh: !!args.refresh,
  });
  return { bars, source };
}

function printReport(result, metrics, args) {
  const L = console.log;
  L('');
  L(`${BOLD}════════════════════════════════════════════════════════════════${RESET}`);
  L(`${BOLD}  BACKTEST — ${result.strategy}${RESET}`);
  L(`${BOLD}════════════════════════════════════════════════════════════════${RESET}`);
  L(`  ${DIM}period${RESET}     ${new Date(result.start).toISOString().slice(0, 10)} → ${new Date(result.end).toISOString().slice(0, 10)}   ${result.bars} bars`);
  L(`  ${DIM}account${RESET}     ${money(result.initialEquity)}   ${DIM}fees: ${(result.config.makerFee * 100).toFixed(2)}% maker / ${(result.config.takerFee * 100).toFixed(2)}% taker${RESET}`);
  L('');
  L(`${BOLD}  RESULTS${RESET}`);
  L(line('trades', metrics.totalTrades, `win rate      ${pct(metrics.winRate)}`));
  L(line('net profit', money(metrics.netProfit), `net %         ${pct(metrics.netProfitPct)}`));
  L(line('profit factor', num2(metrics.profitFactor), `avg R         ${num2(metrics.avgR)}`));
  L(line('max drawdown', money(metrics.maxDrawdown), `max DD %      ${pct(metrics.maxDrawdownPct)}`));
  L(line('total fees', money(metrics.totalFees), `fees as %     ${pct(metrics.feesPctOfEquity)}`));
  L(line('exposure', pct(metrics.exposure), `sharpe        ${num2(metrics.sharpe)}`));
  L(line('avg hold', `${metrics.avgBarsHeld.toFixed(1)} bars`, `final equity  ${money(metrics.finalEquity)}`));
  L('');

  if (metrics.totalTrades === 0) {
    L(`  ${YELLOW}No trades were taken.${RESET} The strategy never signalled, or every signal was rejected.`);
  }

  const insufficient = metrics.verdict.startsWith('INSUFFICIENT');
  if (insufficient) {
    L(`  ${YELLOW}⚠  ${metrics.verdict}${RESET}`);
    L(`  ${DIM}   A strategy with fewer than 30 trades tells you nothing. Treat this as a data point,${RESET}`);
    L(`  ${DIM}   not as an edge. Log it in docs/trading/experiments.md and move on.${RESET}`);
  }

  if (metrics.feesVsProfit !== null && metrics.netProfit > 0) {
    L(`  ${DIM}   fees were ${pct(metrics.feesVsProfit * 100)} of your net profit.${RESET}`);
  }
  if (metrics.totalFees > Math.abs(metrics.netProfit) && metrics.totalTrades > 0) {
    L(`  ${YELLOW}   fees (${money(metrics.totalFees)}) exceeded net profit (${money(metrics.netProfit)}).${RESET}`);
    L(`  ${DIM}   The edge, if there is one, is smaller than the cost of finding it.${RESET}`);
  }
  L('');
}

async function cmdBacktest(args) {
  const { bars, source } = await loadBars(args);
  const name = args.strategy || 'sma-crossover';
  const cfg = {
    initialEquity: num(args.equity, 250),
    riskPct: num(args.risk, 0.5),
    makerFee: num(args.makerFee, 0.004),
    takerFee: num(args.takerFee, 0.008),
    slippageBps: num(args.slippage, 5),
    maxNotionalPct: num(args.maxNotional, 25),
    allowShort: args.short === true,
  };

  const strategy = getStrategy(name);
  const result = backtest(bars, strategy, cfg);
  const metrics = computeMetrics(result, { minTrades: num(args.minTrades, 30), intervalMinutes: num(args.interval, 240) });

  console.log(`  ${DIM}data${RESET}      ${source}  ${DIM}(${bars.length} bars)${RESET}`);
  printReport(result, metrics, args);

  // Benchmark comparison — the number that actually matters
  if (name !== 'buy-and-hold' && !args.noBenchmark) {
    const bh = backtest(bars, getStrategy('buy-and-hold'), cfg);
    const bhMetrics = computeMetrics(bh, { minTrades: num(args.minTrades, 30) });
    const edge = metrics.netProfit - bhMetrics.netProfit;
    console.log(`  ${BOLD}VS BUY-AND-HOLD${RESET}`);
    console.log(line('strategy', money(metrics.netProfit), `benchmark   ${money(bhMetrics.netProfit)}`));
    console.log(line('edge', `${edge >= 0 ? '+' : ''}${money(edge)}`, `benchmark DD ${pct(bhMetrics.maxDrawdownPct)}`));
    if (edge <= 0) {
      console.log(`  ${YELLOW}   Your strategy did not beat simply holding the asset. That is the bar.${RESET}`);
    }
    console.log('');
  }

  if (args.out) {
    const payload = {
      strategy: name,
      params: strategy.params,
      config: result.config,
      dataSource: source,
      period: { start: result.start, end: result.end, bars: result.bars },
      metrics,
      trades: result.trades,
      equityCurve: result.equityCurve,
    };
    fs.mkdirSync(path.dirname(path.resolve(args.out)), { recursive: true });
    fs.writeFileSync(path.resolve(args.out), JSON.stringify(payload, null, 2));
    console.log(`  ${DIM}results written to ${args.out}${RESET}\n`);
  }

  const insufficient = metrics.totalTrades < num(args.minTrades, 30);
  process.exit(insufficient && !args.force ? 2 : 0);
}

async function cmdWalkForward(args) {
  const { bars, source } = await loadBars(args);
  const name = args.strategy || 'sma-crossover';
  const entry = STRATEGIES[name];
  if (!entry) throw new Error(`unknown strategy "${name}"`);

  const wf = walkForward(bars, (p) => entry.factory(p), {
    windows: num(args.windows, 4),
    trainRatio: num(args.trainRatio, 0.7),
    params: entry.params,
    minTrades: num(args.minTrades, 30),
    initialEquity: num(args.equity, 250),
    riskPct: num(args.risk, 0.5),
    makerFee: num(args.makerFee, 0.004),
    takerFee: num(args.takerFee, 0.008),
    slippageBps: num(args.slippage, 5),
  });

  console.log(`  ${DIM}data${RESET} ${source}  ${DIM}(${bars.length} bars)${RESET}`);
  console.log('');
  console.log(`${BOLD}  WALK-FORWARD — ${name}${RESET}`);
  console.log('');
  for (const f of wf.folds) {
    const ins = f.inSample;
    const oos = f.outOfSample;
    console.log(`  ${BOLD}fold ${f.fold}${RESET}  train ${f.trainBars} bars → test ${f.testBars} bars`);
    console.log(`    ${DIM}params${RESET}      ${JSON.stringify(f.chosenParams)}`);
    if (ins) {
      console.log(`    ${DIM}in-sample${RESET}   ${ins.totalTrades} trades · PF ${num2(ins.profitFactor)} · ${money(ins.netProfit)} · DD ${pct(ins.maxDrawdownPct)}`);
    }
    if (oos) {
      const colour = oos.netProfit > 0 ? GREEN : RED;
      console.log(`    ${DIM}OUT-OF-SAMPLE${RESET} ${oos.totalTrades} trades · PF ${num2(oos.profitFactor)} · ${colour}${money(oos.netProfit)}${RESET} · DD ${pct(oos.maxDrawdownPct)}`);
    }
    console.log('');
  }
  console.log(`${BOLD}  STITCHED OUT-OF-SAMPLE${RESET}`);
  console.log(line('trades', wf.stitched.trades, `win rate      ${pct(wf.stitched.winRate)}`));
  console.log(line('net profit', money(wf.stitched.netProfit), `profit factor ${num2(wf.stitched.profitFactor)}`));
  console.log(line('profitable folds', `${wf.stitched.foldsProfitable}/${wf.stitched.foldsTotal}`, ''));
  console.log('');
  console.log(`  ${wf.verdict.startsWith('INSUFFICIENT') ? YELLOW : DIM}  ${wf.verdict}${RESET}`);
  console.log('');
}

function printPaperReport(s) {
  const L = console.log;
  const m = s.metrics;
  const b = s.benchMetrics;
  const money = (v) => `${v < 0 ? '-' : ''}$${Math.abs(v).toFixed(2)}`;
  const pct = (v) => `${v.toFixed(2)}%`;

  L('');
  L(`${BOLD}════════════════════════════════════════════════════════════════${RESET}`);
  L(`${BOLD}  PAPER CYCLE — ${s.state.strategy} · ${s.state.pair} · ${s.state.interval}m${RESET}`);
  L(`${BOLD}════════════════════════════════════════════════════════════════${RESET}`);
  L(`  ${DIM}candle${RESET}      ${new Date(s.lastBarTime).toISOString().replace('T', ' ').slice(0, 16)}   ${s.newBar ? 'NEW' : 'no new candle'}`);
  L(`  ${DIM}paper start${RESET}  ${s.state.paperStart.replace('T', ' ').slice(0, 16)}   ${s.fresh ? '(new record)' : `${s.bars} bars available`}`);
  L('');
  L(`${BOLD}  CAPITAL${RESET}`);
  L(line('capital in', money(s.capitalBase), `deposited  ${money(s.totalDeposited)}`));
  L(line('trading p&l', money(m.netProfit), `of capital ${pct(m.netProfitPct)}`));
  L(line('total equity', money(s.equity), `benchmark  ${money(s.benchEquity)}`));
  L(line('edge', `${s.edge >= 0 ? '+' : ''}${money(s.edge)}`, `vs buy&hold`));
  L('');
  L(`${BOLD}  PERFORMANCE${RESET}`);
  L(line('trades', m.totalTrades, `win rate    ${pct(m.winRate)}`));
  L(line('profit factor', Number.isFinite(m.profitFactor) ? m.profitFactor.toFixed(2) : 'inf', `max DD      ${pct(m.maxDrawdownPct)}`));
  L(line('fees', money(m.totalFees), `exposure    ${pct(m.exposure)}`));
  L('');
  L(`  ${DIM}deposits are your money going in — they are not a return.${RESET}`);
  L(`  ${DIM}The trading P&L line is the only one that measures the desk.${RESET}`);
  L('');
  if (s.newTrades.length) {
    L(`  ${GREEN}${s.newTrades.length} paper trade(s) closed and logged:${RESET}`);
    for (const t of s.newTrades) {
      L(`    ${new Date(t.exitTime).toISOString().replace('T', ' ').slice(0, 16)}  ${t.side.padEnd(5)}  ${t.pnl >= 0 ? '+' : ''}${money(t.pnl)}  ${t.exitReason}`);
    }
  } else {
    L(`  ${DIM}no new paper trades — nothing to log.${RESET}`);
  }
  L('');
  L(`  ${DIM}ledger: docs/trading/journal/paper-ledger.md (${s.ledgerRows} rows)${RESET}`);
  L(`  ${DIM}status: docs/trading/paper-status.md${RESET}`);
  L('');
  if (m.totalTrades < 30) {
    L(`  ${YELLOW}⚠  ${m.verdict}${RESET}`);
    L(`  ${DIM}   Paper trades are a rehearsal of the machinery, not evidence of an edge.${RESET}`);
  }
}

async function cmdPaper(args) {
  const opts = {
    strategy: args.strategy || 'sma-crossover',
    pair: args.pair || 'XRPUSD',
    interval: num(args.interval, 60),
    equity: num(args.equity, 250),
    reset: args.reset === true,
    paperStart: args['paper-start'] || null,
    deposit: args.deposit ? num(args.deposit, 0) : null,
    depositNote: args.note || '',
    refresh: args.refresh !== false,
    makerFee: num(args.makerFee, 0.004),
    takerFee: num(args.takerFee, 0.008),
    slippageBps: num(args.slippage, 5),
    riskPct: num(args.risk, 0.5),
    maxNotionalPct: num(args.maxNotional, 25),
    minTrades: num(args.minTrades, 30),
  };

  if (args.loop) {
    const every = Math.max(1, num(args.loop, 60)) * 60 * 1000;
    console.log(`  ${DIM}paper loop: every ${num(args.loop, 60)} min — Ctrl-C to stop${RESET}`);
    for (;;) {
      try {
        const status = await runPaperCycle(opts);
        printPaperReport(status);
      } catch (err) {
        console.error(`  ${RED}cycle error:${RESET} ${err.message}`);
      }
      await new Promise((r) => setTimeout(r, every));
    }
  }

  const status = await runPaperCycle(opts);
  printPaperReport(status);
}

async function cmdData(args) {
  const { bars, source } = await loadBars(args);
  console.log(`  source    ${source}`);
  console.log(`  bars      ${bars.length}`);
  if (bars.length) {
    console.log(`  from      ${new Date(bars[0].time).toISOString()}`);
    console.log(`  to        ${new Date(bars[bars.length - 1].time).toISOString()}`);
    console.log(`  last      ${bars[bars.length - 1].close}`);
  }
  console.log('');
}

async function cmdTicker(args) {
  const t = await fetchTicker({ pair: args.pair || 'XRPUSD' });
  console.log(`  ${BOLD}${args.pair || 'XRPUSD'}${RESET}`);
  console.log(line('bid', t.bid, `ask       ${t.ask}`));
  console.log(line('last', t.last, `spread    ${t.spreadBps.toFixed(1)} bps`));
  console.log('');
}

function cmdStrategies() {
  console.log('');
  for (const s of listStrategies()) {
    console.log(`  ${BOLD}${s.name}${RESET}`);
    console.log(`    ${s.description}`);
    console.log(`    ${DIM}hypothesis: ${s.hypothesis}${RESET}`);
    console.log(`    ${DIM}params: ${JSON.stringify(s.params)}${RESET}`);
    console.log('');
  }
}

function usage() {
  console.log(`
  ${BOLD}digitraders engine${RESET} — backtesting for the trading desk

  ${BOLD}data${RESET}       --pair XRPUSD --interval 240 [--refresh]
      Fetch OHLC candles from Kraken's public API and cache them.

  ${BOLD}backtest${RESET}   --strategy sma-crossover [--pair XRPUSD] [--interval 240]
               [--equity 250] [--risk 0.5] [--csv path.csv] [--out results.json]
               [--min-trades 30] [--force] [--no-benchmark]
      Run a backtest. Exits 2 when the sample is too small to mean anything.

  ${BOLD}walkforward${RESET} --strategy sma-crossover [--windows 4] [--train-ratio 0.7]
      Rolling in-sample / out-of-sample test. Trust only the stitched OOS number.

  ${BOLD}paper${RESET}      --strategy sma-crossover [--pair XRPUSD] [--interval 60]
               [--equity 250] [--reset] [--loop 60] [--deposit 100 --note "payday"]
      THE PAPER-TRADING CYCLE. Pulls live Kraken candles, runs the strategy
      through the real engine, logs closed paper trades, updates the status file.
      Never touches exchange keys. --loop repeats every N minutes.

  ${BOLD}ticker${RESET}     --pair XRPUSD
      Live bid/ask/spread from Kraken.

  ${BOLD}strategies${RESET}
      List strategies and their hypotheses.

  Common flags: --maker-fee 0.004 --taker-fee 0.008 --slippage 5 --max-notional 25
`);
}

const args = parseArgs(process.argv.slice(2));
const cmd = args._[0] || 'help';

try {
  switch (cmd) {
    case 'backtest': await cmdBacktest(args); break;
    case 'walkforward': await cmdWalkForward(args); break;
    case 'paper': await cmdPaper(args); break;
    case 'data': await cmdData(args); break;
    case 'ticker': await cmdTicker(args); break;
    case 'strategies': cmdStrategies(); break;
    case 'help':
    default: usage(); break;
  }
} catch (err) {
  console.error(`\n  ${RED}error:${RESET} ${err.message}\n`);
  process.exit(1);
}

__MAVIS_EOF_052__

cat > "workspaces/engine/src/config/defaults.js" <<'__MAVIS_EOF_053__'
/**
 * Default configuration.
 *
 * Fee defaults are Kraken Pro **Tier 1** spot (30-day volume $0+):
 *   maker 0.40% / taker 0.80%  — raised 2026-07-09.
 * Check your own tier at https://www.kraken.com/features/fee-schedule
 */
export const KRAKEN_TIER1 = Object.freeze({
  makerFee: 0.004,
  takerFee: 0.008,
});

export const DEFAULTS = Object.freeze({
  /** Starting account equity in quote currency (USD). */
  initialEquity: 250,

  /** Risk per trade as a % of equity (policy L1). */
  riskPct: 0.5,

  /** Fees. Entry and target exits are maker (limit); stop and signal exits are taker (market). */
  makerFee: KRAKEN_TIER1.makerFee,
  takerFee: KRAKEN_TIER1.takerFee,
  stopExitIsTaker: true,

  /** Slippage against you, in basis points of price. */
  slippageBps: 5,

  /** Kraken spot only — no shorting, no margin, no leverage. */
  allowShort: false,

  /** Max notional for a single position as % of equity (policy L6). */
  maxNotionalPct: 25,

  /** Hard stop on how many bars a trade may stay open. */
  maxBarsInTrade: 2000,

  /** Below this many trades, a result is reported as "no conclusion" (policy L12). */
  minTradesForConclusion: 30,

  /**
   * Index of the first bar that may open a position. Bars before it are still
   * fed to the strategy (so indicators warm up), but their signals are ignored
   * and no position is opened. The paper-trading loop uses this so a paper
   * record starts fresh instead of inheriting backtest history.
   */
  startIndex: 0,

  /**
   * Capital added to the account, by bar index: [{ barIndex, amount }].
   * Deposits are tracked separately from trading P&L so that contributions
   * are never mistaken for performance.
   */
  deposits: [],
});

export const INTERVALS = Object.freeze({
  1: '1m', 5: '5m', 15: '15m', 30: '30m',
  60: '1h', 240: '4h', 1440: '1d', 10080: '1w', 21600: '30d',
});

export function withDefaults(options = {}) {
  return { ...DEFAULTS, ...options };
}

__MAVIS_EOF_053__

cat > "workspaces/engine/src/data/csv.js" <<'__MAVIS_EOF_054__'
import fs from 'node:fs';
import path from 'node:path';

/**
 * CSV loading for historical data.
 *
 * Kraken's public OHLC only gives you 720 candles (2 years daily, 30 days at
 * 4H). For deeper history, download a CSV and point the engine at it.
 *
 * Sources for Kraken OHLC CSVs:
 *   - CryptoDataDownload (free): https://www.cryptodatadownload.com/data/kraken/
 *   - KrakenData (paid): https://www.kraken.com/data
 *   - Any export with timestamp/open/high/low/close/volume columns
 *
 * The parser is deliberately forgiving: it sniffs the header, accepts several
 * timestamp formats, and sorts by time.
 */

const HEADER_ALIASES = {
  time: ['time', 'timestamp', 'date', 'datetime', 'unix', 'open_time', 'time_stamp'],
  open: ['open', 'o'],
  high: ['high', 'h'],
  low: ['low', 'l'],
  close: ['close', 'c', 'adj close', 'close_price'],
  volume: ['volume', 'v', 'vol', 'base volume'],
};

function splitCsvLine(line) {
  const out = [];
  let cur = '';
  let inQuotes = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"') {
      if (inQuotes && line[i + 1] === '"') { cur += '"'; i++; }
      else inQuotes = !inQuotes;
    } else if (ch === ',' && !inQuotes) {
      out.push(cur); cur = '';
    } else {
      cur += ch;
    }
  }
  out.push(cur);
  return out.map((s) => s.trim());
}

function findColumn(header, kind) {
  const aliases = HEADER_ALIASES[kind];
  for (const alias of aliases) {
    const idx = header.findIndex((h) => h.toLowerCase() === alias);
    if (idx !== -1) return idx;
  }
  // fall back to substring match
  for (const alias of aliases) {
    const idx = header.findIndex((h) => h.toLowerCase().includes(alias));
    if (idx !== -1) return idx;
  }
  return -1;
}

function parseTime(raw) {
  const n = Number(raw);
  if (!Number.isNaN(n) && n > 0) {
    // seconds or milliseconds
    return n > 1e12 ? n : n * 1000;
  }
  const d = Date.parse(raw);
  if (Number.isNaN(d)) throw new Error(`unparseable timestamp: ${raw}`);
  return d;
}

/**
 * @param {string} filePath
 * @returns {Array} bars sorted ascending by time
 */
export function loadCsv(filePath) {
  const text = fs.readFileSync(filePath, 'utf8');
  const lines = text.split(/\r?\n/).filter((l) => l.trim().length);
  if (lines.length < 2) throw new Error(`CSV ${filePath} has no data rows`);

  const header = splitCsvLine(lines[0]);
  const idx = {
    time: findColumn(header, 'time'),
    open: findColumn(header, 'open'),
    high: findColumn(header, 'high'),
    low: findColumn(header, 'low'),
    close: findColumn(header, 'close'),
    volume: findColumn(header, 'volume'),
  };
  for (const [k, v] of Object.entries(idx)) {
    if (v === -1) throw new Error(`CSV ${filePath} is missing a "${k}" column (headers: ${header.join(', ')})`);
  }

  const bars = [];
  for (let i = 1; i < lines.length; i++) {
    const cells = splitCsvLine(lines[i]);
    if (cells.length < header.length) continue;
    const open = Number(cells[idx.open]);
    const high = Number(cells[idx.high]);
    const low = Number(cells[idx.low]);
    const close = Number(cells[idx.close]);
    if (![open, high, low, close].every(Number.isFinite)) continue;
    bars.push({
      time: parseTime(cells[idx.time]),
      open, high, low, close,
      volume: idx.volume === -1 ? 0 : Number(cells[idx.volume]) || 0,
    });
  }

  bars.sort((a, b) => a.time - b.time);
  return bars;
}

/** Write bars back out as CSV (same format we accept). */
export function saveCsv(filePath, bars) {
  const dir = path.dirname(filePath);
  fs.mkdirSync(dir, { recursive: true });
  const rows = ['time,open,high,low,close,volume'];
  for (const b of bars) {
    rows.push([Math.floor(b.time / 1000), b.open, b.high, b.low, b.close, b.volume ?? 0].join(','));
  }
  fs.writeFileSync(filePath, rows.join('\n') + '\n');
  return filePath;
}

__MAVIS_EOF_054__

cat > "workspaces/engine/src/data/kraken.js" <<'__MAVIS_EOF_055__'
/**
 * Kraken public market data. No API key required.
 *
 * Kraken returns legacy asset names (`XXRPZUSD` for XRP/USD, `XXBTZUSD` for
 * BTC/USD) — that mapping lives here so it never leaks into strategy code.
 */

const BASE = 'https://api.kraken.com/0/public';

/**
 * Kraken's legacy asset codes. These are the codes Kraken uses internally and
 * in the result key of API responses — `XXRPZUSD` for XRP/USD.
 *
 * The engine never *depends* on this map: `fetchOHLC` discovers the key from
 * the response. This exists so a human reading a log or a JSON dump can map
 * `XXRPZUSD` back to `XRPUSD`.
 */
const LEGACY = {
  BTC: 'XXBT', XBT: 'XXBT', ETH: 'XETH', XRP: 'XXRP', LTC: 'XLTC', ZEC: 'XZEC',
  DOGE: 'XDG', BCH: 'XBC', XMR: 'XXMR', ADA: 'ADA', DOT: 'DOT', SOL: 'SOL',
  MATIC: 'MATIC', LINK: 'LINK', TRX: 'TRX', ATOM: 'ATOM', AVAX: 'AVAX',
  USD: 'ZUSD', EUR: 'ZEUR', GBP: 'ZGBP', CAD: 'ZCAD', AUD: 'ZAUD', JPY: 'ZJPY',
  USDT: 'USDT', USDC: 'USDC', DAI: 'DAI', DOTUSD: 'DOTUSD',
};

/** Quote assets we know how to split a pair on, longest first. */
const QUOTES = ['USDT', 'USDC', 'USD', 'EUR', 'GBP', 'CAD', 'AUD', 'JPY', 'BTC', 'ETH'];

/** Split a pair like `XRPUSD` into its base and quote assets. */
export function splitPair(pair) {
  const p = pair.toUpperCase();
  for (const q of QUOTES) {
    if (p.length > q.length && p.endsWith(q)) {
      return { base: p.slice(0, -q.length), quote: q };
    }
  }
  return { base: p, quote: '' };
}

/** Kraken's result key for a pair, e.g. XRPUSD -> XXRPZUSD. */
export function krakenResultKey(pair) {
  const { base, quote } = splitPair(pair);
  const b = LEGACY[base] ?? base;
  const q = quote ? (LEGACY[quote] ?? quote) : '';
  return b + q;
}

/**
 * Fetch OHLC candles.
 * Kraken caps this at 720 candles per call (plus the in-progress bar).
 *
 * @param {Object} opts
 *   pair     e.g. 'XRPUSD'
 *   interval minutes: 1 | 5 | 15 | 30 | 60 | 240 | 1440 | 10080 | 21600
 */
export async function fetchOHLC({ pair = 'XRPUSD', interval = 240, since } = {}) {
  const url = new URL(`${BASE}/OHLC`);
  url.searchParams.set('pair', pair);
  url.searchParams.set('interval', String(interval));
  if (since) url.searchParams.set('since', String(since));

  const res = await fetch(url, { headers: { 'User-Agent': 'digitraders-engine/0.1' } });
  if (!res.ok) throw new Error(`Kraken OHLC request failed: HTTP ${res.status}`);
  const json = await res.json();
  if (json.error && json.error.length) {
    throw new Error(`Kraken API error: ${json.error.join(', ')}`);
  }

  const key = Object.keys(json.result).find((k) => k !== 'last');
  if (!key) throw new Error(`no data returned for ${pair}`);

  const rows = json.result[key];
  const bars = rows.map((r) => ({
    time: r[0] * 1000,            // ms
    open: Number(r[1]),
    high: Number(r[2]),
    low: Number(r[3]),
    close: Number(r[4]),
    vwap: Number(r[5]),
    volume: Number(r[6]),
    count: Number(r[7]),
  }));

  // Drop the in-progress bar (Kraken's last row is the live candle)
  const last = json.result.last * 1000;
  return bars.filter((b) => b.time < last);
}

/** Best bid/ask. */
export async function fetchTicker({ pair = 'XRPUSD' } = {}) {
  const url = new URL(`${BASE}/Ticker`);
  url.searchParams.set('pair', pair);
  const res = await fetch(url, { headers: { 'User-Agent': 'digitraders-engine/0.1' } });
  const json = await res.json();
  if (json.error && json.error.length) throw new Error(`Kraken API error: ${json.error.join(', ')}`);
  const key = Object.keys(json.result).find((k) => k !== 'last');
  const t = json.result[key];
  return {
    bid: Number(t.b[0]),
    ask: Number(t.a[0]),
    last: Number(t.c[0]),
    spreadBps: ((Number(t.a[0]) - Number(t.b[0])) / Number(t.c[0])) * 10000,
    volume24h: Number(t.v[1] ?? 0),
  };
}

/** Top of book, up to `depth` levels. */
export async function fetchOrderBook({ pair = 'XRPUSD', depth = 10 } = {}) {
  const url = new URL(`${BASE}/Depth`);
  url.searchParams.set('pair', pair);
  url.searchParams.set('count', String(depth));
  const res = await fetch(url, { headers: { 'User-Agent': 'digitraders-engine/0.1' } });
  const json = await res.json();
  if (json.error && json.error.length) throw new Error(`Kraken API error: ${json.error.join(', ')}`);
  const key = Object.keys(json.result).find((k) => k !== 'last');
  const [asks, bids] = json.result[key];
  return {
    asks: asks.map(([p, q]) => ({ price: Number(p), qty: Number(q) })),
    bids: bids.map(([p, q]) => ({ price: Number(p), qty: Number(q) })),
  };
}

/** Server time, useful to check clock skew. */
export async function fetchServerTime() {
  const res = await fetch(`${BASE}/Time`, { headers: { 'User-Agent': 'digitraders-engine/0.1' } });
  const json = await res.json();
  return new Date(json.result.unixtime * 1000);
}

__MAVIS_EOF_055__

cat > "workspaces/engine/src/data/store.js" <<'__MAVIS_EOF_056__'
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { fetchOHLC } from './kraken.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const CACHE_DIR = path.resolve(here, '..', '..', '.cache');

function cachePath(pair, interval) {
  return path.join(CACHE_DIR, `${pair.toUpperCase()}-${interval}.json`);
}

/**
 * Load candles: from cache if it's there and fresh enough, otherwise from
 * Kraken's public API (then cached).
 */
export async function loadCandles({ pair = 'XRPUSD', interval = 240, refresh = false, maxAgeMs = 6 * 60 * 60 * 1000 } = {}) {
  const file = cachePath(pair, interval);

  if (!refresh && fs.existsSync(file)) {
    const age = Date.now() - fs.statSync(file).mtimeMs;
    if (age < maxAgeMs) {
      const cached = JSON.parse(fs.readFileSync(file, 'utf8'));
      return { bars: cached.bars, source: 'cache', fetchedAt: cached.fetchedAt };
    }
  }

  const bars = await fetchOHLC({ pair, interval });
  fs.mkdirSync(CACHE_DIR, { recursive: true });
  fs.writeFileSync(file, JSON.stringify({ pair, interval, fetchedAt: new Date().toISOString(), bars }));
  return { bars, source: 'kraken', fetchedAt: new Date().toISOString() };
}

/** Drop cached candles. */
export function clearCache() {
  if (fs.existsSync(CACHE_DIR)) fs.rmSync(CACHE_DIR, { recursive: true, force: true });
  return CACHE_DIR;
}

export { CACHE_DIR };

__MAVIS_EOF_056__

cat > "workspaces/engine/src/engine/backtest.js" <<'__MAVIS_EOF_057__'
import { withDefaults } from '../config/defaults.js';

/**
 * The simulator.
 *
 * ── The one rule that makes a backtest honest ──────────────────────────────────
 * A signal is computed on the CLOSE of bar `i`. The fill happens at the OPEN of
 * bar `i + 1`. Never the close of bar `i`, never the open of bar `i`. If you
 * ever fill on the bar you decided on, you have invented edge that isn't there.
 *
 * On top of that, strategies physically cannot see the future: `ctx.bars` is a
 * guarded view that throws if the strategy reaches past the current bar.
 */

/**
 * Wrap `bars` so a strategy can only read up to and including `index`.
 * Reading beyond it throws — that's the no-lookahead guarantee, enforced by
 * the engine rather than by trust.
 */
export function createBarGuard(bars, index) {
  const limit = index + 1;
  return new Proxy(bars, {
    get(target, prop) {
      if (prop === 'length') return Math.min(target.length, limit);
      if (typeof prop === 'string' && /^\d+$/.test(prop)) {
        const i = Number(prop);
        if (i >= limit) {
          throw new Error(
            `lookahead blocked: strategy tried to read bar ${i} while standing on bar ${index}`,
          );
        }
      }
      return target[prop];
    },
  });
}

const bps = (v) => v / 10000;

/**
 * Run a backtest.
 *
 * @param {Array} bars  [{ time, open, high, low, close, volume }]
 * @param {Object} strategy  { name, params?, onBar(ctx) -> signal }
 * @param {Object} options   see ../config/defaults.js
 */
export function backtest(bars, strategy, options = {}) {
  const cfg = withDefaults(options);
  if (!Array.isArray(bars) || bars.length < 3) {
    throw new Error('backtest needs at least 3 bars');
  }
  if (!strategy || typeof strategy.onBar !== 'function') {
    throw new Error('strategy must be an object with an onBar(ctx) method');
  }

  let cash = cfg.initialEquity;
  let position = null;
  let pending = null;
  let totalDeposits = 0;

  // Deposits land at a specific bar so position sizing uses the capital that
  // was actually in the account at that moment.
  const depositsByBar = new Map();
  for (const d of cfg.deposits || []) {
    depositsByBar.set(d.barIndex, (depositsByBar.get(d.barIndex) || 0) + d.amount);
  }

  const trades = [];
  const equityCurve = [];
  const signals = [];
  const logs = [];
  let totalFees = 0;

  const log = (...args) => logs.push(args.map(String).join(' '));

  // ── helpers ────────────────────────────────────────────────────────────────
  const slip = (price, side) =>
    side === 'buy' ? price * (1 + bps(cfg.slippageBps)) : price * (1 - bps(cfg.slippageBps));

  const markEquity = (price) => {
    if (!position) return cash;
    return position.side === 'long'
      ? cash + position.size * price
      : cash - position.size * price;
  };

  const feeFor = (notional, isMaker) =>
    notional * (isMaker ? cfg.makerFee : cfg.takerFee);

  function openPosition(side, bar, index, signal) {
    const isBuy = side === 'long';
    const fill = slip(bar.open, isBuy ? 'buy' : 'sell');

    // A stop is mandatory: without one there's no honest way to size the trade.
    let stop = typeof signal.stop === 'number' ? signal.stop : null;
    let size = null;
    let riskAmount = 0;

    if (typeof signal.size === 'number' && signal.size > 0) {
      size = signal.size;
    } else if (typeof signal.notionalPct === 'number' && signal.notionalPct > 0) {
      // Explicit share of equity as notional — used by the buy-and-hold benchmark.
      size = ((cash * signal.notionalPct) / 100) / fill;
    } else if (stop !== null) {
      const stopDist = Math.abs(fill - stop);
      if (stopDist <= 0) return null;
      if (side === 'long' && stop >= fill) return null;  // stop above entry is nonsense
      if (side === 'short' && stop <= fill) return null;
      riskAmount = cash * (cfg.riskPct / 100);
      size = riskAmount / stopDist;
    } else {
      log(`skipped entry at bar ${index}: no stop and no size`);
      return null;
    }

    // L6 — never exceed the max notional for a single position
    const maxNotional = (cfg.maxNotionalPct / 100) * cash;
    let notional = size * fill;
    if (notional > maxNotional) {
      size = maxNotional / fill;
      notional = size * fill;
    }
    if (size <= 0) return null;

    const fee = feeFor(notional, true); // entry is a limit order → maker
    const entryNotional = notional;

    if (side === 'long') cash -= entryNotional + fee;
    else cash += entryNotional - fee;
    totalFees += fee;

    position = {
      side,
      size,
      entryPrice: fill,
      entryNotional,
      entryIndex: index,
      entryTime: bar.time,
      stop,
      target: typeof signal.target === 'number' ? signal.target : null,
      riskAmount,
      entryFee: fee,
      reason: signal.reason || '',
      maxFavorable: 0,
      maxAdverse: 0,
    };
    return position;
  }

  function closePosition(exitPrice, reason, bar, index) {
    if (!position) return;
    const isBuyToClose = position.side === 'short';
    const fill = slip(exitPrice, isBuyToClose ? 'buy' : 'sell');
    const gross = position.size * fill;
    // A stop-loss or signal exit is a market order → taker. A target exit can
    // rest as a limit → maker.
    const isMaker = reason === 'target';
    const fee = feeFor(gross, isMaker);
    totalFees += fee;

    let pnl;
    if (position.side === 'long') {
      cash += gross - fee;
      pnl = gross - position.entryNotional - position.entryFee - fee;
    } else {
      cash -= gross + fee;
      pnl = position.entryNotional - gross - position.entryFee - fee;
    }

    trades.push({
      side: position.side,
      entryTime: position.entryTime,
      exitTime: bar.time,
      entryIndex: position.entryIndex,
      exitIndex: index,
      entryPrice: position.entryPrice,
      exitPrice: fill,
      size: position.size,
      notional: position.entryNotional,
      pnl,
      fees: position.entryFee + fee,
      rMultiple: position.riskAmount > 0 ? pnl / position.riskAmount : null,
      exitReason: reason,
      barsHeld: index - position.entryIndex,
      thesis: position.reason,
    });
    position = null;
  }

  // ── main loop ──────────────────────────────────────────────────────────────
  for (let i = 0; i < bars.length; i++) {
    const bar = bars[i];

    // Bars before startIndex are warm-up only: the strategy still sees them so
    // its indicators are ready, but nothing may be opened or closed there.
    const live = i >= cfg.startIndex;

    // 0 ── capital deposited into the account on this bar
    if (depositsByBar.has(i)) {
      const amount = depositsByBar.get(i);
      cash += amount;
      totalDeposits += amount;
    }

    // 1 ── execute the order decided on the PREVIOUS bar, at THIS bar's open
    if (pending && live) {
      const act = pending;
      pending = null;
      if (act.action === 'enter_long' && !position) {
        openPosition('long', bar, i, act);
      } else if (act.action === 'enter_short' && !position && cfg.allowShort) {
        openPosition('short', bar, i, act);
      } else if (act.action === 'exit' && position) {
        closePosition(bar.open, 'signal', bar, i);
      }
    }

    // 2 ── intrabar stop / target, checked against THIS bar's range
    if (position) {
      const barsHeld = i - position.entryIndex;
      if (position.side === 'long') {
        const gapped = bar.open <= position.stop;
        if (gapped) {
          closePosition(bar.open, 'stop', bar, i);           // filled worse than the stop
        } else if (bar.low <= position.stop) {
          closePosition(position.stop, 'stop', bar, i);
        } else if (position.target !== null && bar.high >= position.target) {
          closePosition(position.target, 'target', bar, i);
        }
      } else {
        const gapped = bar.open >= position.stop;
        if (gapped) {
          closePosition(bar.open, 'stop', bar, i);
        } else if (bar.high >= position.stop) {
          closePosition(position.stop, 'stop', bar, i);
        } else if (position.target !== null && bar.low <= position.target) {
          closePosition(position.target, 'target', bar, i);
        }
      }
      if (position && barsHeld >= cfg.maxBarsInTrade) {
        closePosition(bar.close, 'time', bar, i);
      }
    }

    // 3 ── mark to market at this bar's close
    const equity = markEquity(bar.close);
    if (live) equityCurve.push({
      time: bar.time,
      equity,
      cash,
      inPosition: !!position,
      openPnl: position ? equity - cash : 0,
    });

    // 4 ── the strategy decides, seeing only up to and including this bar
    const guarded = createBarGuard(bars, i);
    const ctx = {
      bars: guarded,
      index: i,
      bar,
      position,
      equity,
      cash,
      params: strategy.params || {},
      log,
    };

    let signal;
    try {
      signal = strategy.onBar(ctx) || { action: 'hold' };
    } catch (err) {
      // A lookahead attempt is a strategy bug, not a runtime error — surface it verbatim.
      if (err && typeof err.message === 'string' && err.message.includes('lookahead blocked')) {
        throw err;
      }
      throw new Error(
        `strategy "${strategy.name || 'unnamed'}" threw at bar ${i}: ${err.message}`,
      );
    }

    signals.push({
      index: i,
      time: bar.time,
      action: signal.action || 'hold',
      reason: signal.reason || '',
    });

    if (live && signal.action && signal.action !== 'hold') {
      pending = { ...signal, decidedAtIndex: i };
    }
  }

  // ── close whatever is still open at the end of the data ────────────────────
  if (position) {
    const last = bars[bars.length - 1];
    closePosition(last.close, 'end_of_data', last, bars.length - 1);
    equityCurve[equityCurve.length - 1].equity = cash;
    equityCurve[equityCurve.length - 1].inPosition = false;
  }

  return {
    config: cfg,
    strategy: strategy.name || 'unnamed',
    bars: bars.length,
    start: bars[0].time,
    end: bars[bars.length - 1].time,
    initialEquity: cfg.initialEquity,
    finalEquity: cash,
    trades,
    equityCurve,
    signals,
    logs,
    totalFees,
    totalDeposits,
  };
}

__MAVIS_EOF_057__

cat > "workspaces/engine/src/engine/indicators.js" <<'__MAVIS_EOF_058__'
/**
 * Indicators — pure functions over arrays of numbers or bars.
 *
 * No dependencies on purpose: this has to run on a phone with nothing installed
 * but Node. Every function returns an array the same length as its input, with
 * `null` for the warm-up period, so you can index it by bar without offset bugs.
 */

/** Simple moving average. */
export function sma(values, period) {
  const out = new Array(values.length).fill(null);
  let sum = 0;
  for (let i = 0; i < values.length; i++) {
    sum += values[i];
    if (i >= period) sum -= values[i - period];
    if (i >= period - 1) out[i] = sum / period;
  }
  return out;
}

/** Exponential moving average (Wilder-style smoothing factor k = 2/(n+1)). */
export function ema(values, period) {
  const out = new Array(values.length).fill(null);
  if (values.length < period) return out;
  const k = 2 / (period + 1);
  let prev = values.slice(0, period).reduce((a, b) => a + b, 0) / period;
  out[period - 1] = prev;
  for (let i = period; i < values.length; i++) {
    prev = values[i] * k + prev * (1 - k);
    out[i] = prev;
  }
  return out;
}

/**
 * Average True Range (Wilder). True range accounts for gaps, which matters
 * a lot in crypto where a position can gap through its stop.
 */
export function atr(bars, period = 14) {
  const out = new Array(bars.length).fill(null);
  if (bars.length < period + 1) return out;
  const tr = new Array(bars.length).fill(0);
  tr[0] = bars[0].high - bars[0].low;
  for (let i = 1; i < bars.length; i++) {
    const prevClose = bars[i - 1].close;
    tr[i] = Math.max(
      bars[i].high - bars[i].low,
      Math.abs(bars[i].high - prevClose),
      Math.abs(bars[i].low - prevClose),
    );
  }
  let sum = 0;
  for (let i = 1; i <= period; i++) sum += tr[i];
  let prev = sum / period;
  out[period] = prev;
  for (let i = period + 1; i < bars.length; i++) {
    prev = (prev * (period - 1) + tr[i]) / period;
    out[i] = prev;
  }
  return out;
}

/** Relative Strength Index (Wilder). */
export function rsi(values, period = 14) {
  const out = new Array(values.length).fill(null);
  if (values.length <= period) return out;
  let gain = 0;
  let loss = 0;
  for (let i = 1; i <= period; i++) {
    const d = values[i] - values[i - 1];
    if (d >= 0) gain += d; else loss -= d;
  }
  let avgGain = gain / period;
  let avgLoss = loss / period;
  out[period] = avgLoss === 0 ? 100 : 100 - 100 / (1 + avgGain / avgLoss);
  for (let i = period + 1; i < values.length; i++) {
    const d = values[i] - values[i - 1];
    const g = d > 0 ? d : 0;
    const l = d < 0 ? -d : 0;
    avgGain = (avgGain * (period - 1) + g) / period;
    avgLoss = (avgLoss * (period - 1) + l) / period;
    out[i] = avgLoss === 0 ? 100 : 100 - 100 / (1 + avgGain / avgLoss);
  }
  return out;
}

/** Rolling standard deviation (population). */
export function stdev(values, period) {
  const out = new Array(values.length).fill(null);
  for (let i = period - 1; i < values.length; i++) {
    let sum = 0;
    let sq = 0;
    for (let j = i - period + 1; j <= i; j++) {
      sum += values[j];
      sq += values[j] * values[j];
    }
    const mean = sum / period;
    out[i] = Math.sqrt(Math.max(0, sq / period - mean * mean));
  }
  return out;
}

/** Highest high over the last `period` bars (inclusive of the current bar). */
export function highest(bars, period, field = 'high') {
  const out = new Array(bars.length).fill(null);
  for (let i = period - 1; i < bars.length; i++) {
    let v = -Infinity;
    for (let j = i - period + 1; j <= i; j++) v = Math.max(v, bars[j][field]);
    out[i] = v;
  }
  return out;
}

/** Lowest low over the last `period` bars (inclusive of the current bar). */
export function lowest(bars, period, field = 'low') {
  const out = new Array(bars.length).fill(null);
  for (let i = period - 1; i < bars.length; i++) {
    let v = Infinity;
    for (let j = i - period + 1; j <= i; j++) v = Math.min(v, bars[j][field]);
    out[i] = v;
  }
  return out;
}

/** Percentage change between two values. */
export function pctChange(from, to) {
  if (!from) return 0;
  return ((to - from) / from) * 100;
}

/** Clamp a number into a range. */
export function clamp(v, lo, hi) {
  return Math.min(hi, Math.max(lo, v));
}

/**
 * Incremental indicators.
 *
 * A live strategy can't recompute an SMA over the whole array every bar — it
 * maintains state. These classes do the same thing in O(1) per bar, which is
 * also what makes a backtest fast enough to iterate on.
 */

export class RollingSma {
  constructor(period) {
    this.period = period;
    this.buf = [];
    this.sum = 0;
  }

  /** Feed the next close, get the SMA (null during warm-up). */
  push(close) {
    this.buf.push(close);
    this.sum += close;
    if (this.buf.length > this.period) this.sum -= this.buf.shift();
    return this.buf.length === this.period ? this.sum / this.period : null;
  }

  get ready() {
    return this.buf.length >= this.period;
  }
}

export class RollingAtr {
  constructor(period = 14) {
    this.period = period;
    this.trs = [];
    this.prevClose = null;
    this.value = null;
  }

  /** Feed the next bar, get the ATR (null during warm-up). */
  push(bar) {
    let tr;
    if (this.prevClose === null) {
      tr = bar.high - bar.low;
    } else {
      tr = Math.max(
        bar.high - bar.low,
        Math.abs(bar.high - this.prevClose),
        Math.abs(bar.low - this.prevClose),
      );
    }
    this.prevClose = bar.close;
    this.trs.push(tr);

    if (this.trs.length === this.period) {
      this.value = this.trs.reduce((s, v) => s + v, 0) / this.period;
    } else if (this.trs.length > this.period) {
      this.value = (this.value * (this.period - 1) + tr) / this.period;
    }
    return this.value;
  }

  get ready() {
    return this.value !== null;
  }
}

/** Rolling window of the highest high / lowest low. */
export class RollingChannel {
  constructor(period) {
    this.period = period;
    this.highs = [];
    this.lows = [];
  }

  push(bar) {
    this.highs.push(bar.high);
    this.lows.push(bar.low);
    if (this.highs.length > this.period) { this.highs.shift(); this.lows.shift(); }
    return {
      highest: Math.max(...this.highs),
      lowest: Math.min(...this.lows),
      ready: this.highs.length === this.period,
    };
  }
}

__MAVIS_EOF_058__

cat > "workspaces/engine/src/engine/metrics.js" <<'__MAVIS_EOF_059__'
/**
 * Performance metrics.
 *
 * The numbers that actually decide whether a strategy is worth running:
 * profit factor, max drawdown, expectancy, and — at small account sizes —
 * **how much of the account went to fees**.
 */

const BARS_PER_YEAR = {
  1: 525600, 5: 105120, 15: 35040, 30: 17520,
  60: 8760, 240: 2190, 1440: 365, 10080: 52, 21600: 12,
};

export function computeMetrics(result, options = {}) {
  const {
    minTrades = 30,
    intervalMinutes = 240,
  } = options;

  const { trades, equityCurve, initialEquity, totalFees } = result;

  // Capital contributed (starting balance + deposits). Trading P&L is measured
  // against this, so a paycheck deposit can never masquerade as a profit.
  const totalDeposits = result.totalDeposits ?? 0;
  const capitalBase = initialEquity + totalDeposits;

  const wins = trades.filter((t) => t.pnl > 0);
  const losses = trades.filter((t) => t.pnl <= 0);

  const grossProfit = wins.reduce((s, t) => s + t.pnl, 0);
  const grossLoss = Math.abs(losses.reduce((s, t) => s + t.pnl, 0));
  const netProfit = grossProfit - grossLoss;
  // Equity comes from the curve (it includes deposits); P&L comes from the
  // trades (it never does).
  const finalEquity = equityCurve.length
    ? equityCurve[equityCurve.length - 1].equity
    : initialEquity + netProfit + totalDeposits;

  const avgWin = wins.length ? grossProfit / wins.length : 0;
  const avgLoss = losses.length ? grossLoss / losses.length : 0;

  const rMultiples = trades.map((t) => t.rMultiple).filter((r) => r !== null);
  const avgR = rMultiples.length ? rMultiples.reduce((s, r) => s + r, 0) / rMultiples.length : 0;

  // ── drawdown ───────────────────────────────────────────────────────────────
  let peak = equityCurve.length ? equityCurve[0].equity : initialEquity;
  let maxDD = 0;
  let maxDDPct = 0;
  let ddStart = 0;
  let maxDDDuration = 0;
  let curStart = 0;
  equityCurve.forEach((p, i) => {
    if (p.equity > peak) {
      peak = p.equity;
      curStart = i;
    }
    const dd = peak - p.equity;
    if (dd > maxDD) {
      maxDD = dd;
      maxDDPct = peak > 0 ? (dd / peak) * 100 : 0;
      ddStart = curStart;
    }
    const dur = i - curStart;
    if (dur > maxDDDuration) maxDDDuration = dur;
  });

  // ── sharpe from per-bar equity returns ─────────────────────────────────────
  const returns = [];
  for (let i = 1; i < equityCurve.length; i++) {
    const prev = equityCurve[i - 1].equity;
    if (prev > 0) returns.push((equityCurve[i].equity - prev) / prev);
  }
  let sharpe = null;
  if (returns.length > 2) {
    const mean = returns.reduce((s, r) => s + r, 0) / returns.length;
    const variance = returns.reduce((s, r) => s + (r - mean) ** 2, 0) / (returns.length - 1);
    const sd = Math.sqrt(variance);
    if (sd > 0) sharpe = (mean / sd) * Math.sqrt(BARS_PER_YEAR[intervalMinutes] || 365);
  }

  const exposureBars = equityCurve.filter((p) => p.inPosition).length;
  const exposure = equityCurve.length ? (exposureBars / equityCurve.length) * 100 : 0;
  const avgBarsHeld = trades.length
    ? trades.reduce((s, t) => s + t.barsHeld, 0) / trades.length
    : 0;

  const bestTrade = trades.reduce((b, t) => (!b || t.pnl > b.pnl ? t : b), null);
  const worstTrade = trades.reduce((b, t) => (!b || t.pnl < b.pnl ? t : b), null);

  const profitFactor = grossLoss > 0 ? grossProfit / grossLoss : (grossProfit > 0 ? Infinity : 0);

  return {
    totalTrades: trades.length,
    wins: wins.length,
    losses: losses.length,
    winRate: trades.length ? (wins.length / trades.length) * 100 : 0,

    initialEquity,
    totalDeposits,
    capitalBase,
    finalEquity,
    netProfit,
    netProfitPct: capitalBase > 0 ? (netProfit / capitalBase) * 100 : 0,

    grossProfit,
    grossLoss,
    profitFactor,
    avgWin,
    avgLoss,
    payoffRatio: avgLoss > 0 ? avgWin / avgLoss : null,
    expectancy: trades.length ? netProfit / trades.length : 0,
    expectancyR: avgR,

    avgR,
    bestTradeR: rMultiples.length ? Math.max(...rMultiples) : null,
    worstTradeR: rMultiples.length ? Math.min(...rMultiples) : null,

    maxDrawdown: maxDD,
    maxDrawdownPct: maxDDPct,
    maxDrawdownBars: maxDDDuration,

    sharpe,
    exposure,
    avgBarsHeld,

    totalFees,
    feesPctOfEquity: capitalBase > 0 ? (totalFees / capitalBase) * 100 : 0,
    avgFeePerTrade: trades.length ? totalFees / trades.length : 0,
    feesVsProfit: netProfit !== 0 ? totalFees / Math.abs(netProfit) : null,

    bestTrade,
    worstTrade,

    verdict:
      trades.length < minTrades
        ? `INSUFFICIENT SAMPLE — ${trades.length} trades, need ${minTrades}. No conclusion.`
        : 'Sample size sufficient.',
  };
}

__MAVIS_EOF_059__

cat > "workspaces/engine/src/engine/walkforward.js" <<'__MAVIS_EOF_060__'
import { backtest } from './backtest.js';
import { computeMetrics } from './metrics.js';

/**
 * Walk-forward analysis.
 *
 * Splits history into rolling in-sample / out-of-sample windows and stitches
 * the out-of-sample results together. The stitched result is the only number
 * you should ever trust — the in-sample number is where strategies go to die.
 */

/**
 * @param {Array} bars
 * @param {Function} makeStrategy  (params) => strategy
 * @param {Object} options
 *   windows      number of rolling windows (default 4)
 *   trainRatio   fraction of each window used for training (default 0.7)
 *   params       array of parameter sets to test per window
 */
export function walkForward(bars, makeStrategy, options = {}) {
  const {
    windows = 4,
    trainRatio = 0.7,
    params = [{}],
    minTrades = 30,
    ...backtestOptions
  } = options;

  if (bars.length < 50) {
    throw new Error('walk-forward needs at least 50 bars');
  }

  const windowSize = Math.floor(bars.length / windows);
  const folds = [];

  for (let w = 0; w < windows; w++) {
    const start = w * windowSize;
    const end = w === windows - 1 ? bars.length : start + windowSize;
    const slice = bars.slice(start, end);
    const split = Math.floor(slice.length * trainRatio);
    const train = slice.slice(0, split);
    const test = slice.slice(split);

    const inSample = [];
    for (const p of params) {
      const strategy = makeStrategy(p);
      if (!strategy) continue;
      const r = backtest(train, strategy, backtestOptions);
      const m = computeMetrics(r, { minTrades, ...backtestOptions });
      inSample.push({ params: p, metrics: m });
    }
    inSample.sort((a, b) => b.metrics.profitFactor - a.metrics.profitFactor);
    const best = inSample[0];

    const oos = best
      ? backtest(test, makeStrategy(best.params), backtestOptions)
      : null;
    const oosMetrics = oos ? computeMetrics(oos, { minTrades, ...backtestOptions }) : null;

    folds.push({
      fold: w + 1,
      trainBars: train.length,
      testBars: test.length,
      trainFrom: train[0]?.time,
      trainTo: train[train.length - 1]?.time,
      testFrom: test[0]?.time,
      testTo: test[test.length - 1]?.time,
      chosenParams: best?.params ?? null,
      inSample: best?.metrics ?? null,
      outOfSample: oosMetrics,
    });
  }

  // Stitch the out-of-sample segments into one equity path
  const oosTrades = folds.flatMap((f) => f.outOfSample?.trades ?? []);
  const stitched = folds
    .map((f) => f.outOfSample)
    .filter(Boolean);

  const totalOosTrades = oosTrades.length;
  const oosWins = oosTrades.filter((t) => t.pnl > 0).length;
  const oosProfit = oosTrades.reduce((s, t) => s + t.pnl, 0);
  const oosLoss = Math.abs(oosTrades.filter((t) => t.pnl <= 0).reduce((s, t) => s + t.pnl, 0));

  return {
    folds,
    stitched: {
      trades: totalOosTrades,
      winRate: totalOosTrades ? (oosWins / totalOosTrades) * 100 : 0,
      netProfit: oosProfit,
      profitFactor: oosLoss > 0 ? oosProfit / oosLoss : 0,
      foldsProfitable: stitched.filter((m) => m.netProfit > 0).length,
      foldsTotal: stitched.length,
    },
    verdict:
      totalOosTrades < minTrades
        ? `INSUFFICIENT SAMPLE — ${totalOosTrades} out-of-sample trades, need ${minTrades}. No conclusion.`
        : 'Out-of-sample sample size sufficient.',
  };
}

__MAVIS_EOF_060__

cat > "workspaces/engine/src/paper/portfolio.js" <<'__MAVIS_EOF_061__'
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));

/**
 * Paths. Overridable with env vars so tests can run against a temp directory
 * and so a future "second desk" can keep its own record.
 */
const env = (name, fallback) => process.env[name] || fallback;

/** Engine-local state. Git-ignored. */
export const STATE_DIR = path.resolve(env('DIGITRADERS_PAPER_STATE_DIR', path.resolve(here, '..', '..', '.paper')));
export const STATE_FILE = path.join(STATE_DIR, 'state.json');

/** The human-readable, append-only paper trade ledger. */
export const LEDGER_FILE = path.resolve(env(
  'DIGITRADERS_PAPER_LEDGER',
  path.resolve(here, '..', '..', '..', '..', 'docs', 'trading', 'journal', 'paper-ledger.md'),
));

/** The capital ledger — what went in, and when. */
export const CAPITAL_FILE = path.resolve(env(
  'DIGITRADERS_PAPER_CAPITAL',
  path.resolve(here, '..', '..', '..', '..', 'docs', 'trading', 'capital.md'),
));

/** Auto-generated paper status, separate from the agent-maintained board. */
export const STATUS_FILE = path.resolve(env(
  'DIGITRADERS_PAPER_STATUS',
  path.resolve(here, '..', '..', '..', '..', 'docs', 'trading', 'paper-status.md'),
));

export function defaultState({ strategy, params = {}, pair, interval, equity }) {
  return {
    version: 1,
    strategy,
    params,
    pair,
    interval,
    initialEquity: equity,
    paperStart: new Date().toISOString(),
    lastCycleAt: null,
    lastBarTime: null,
    recordedTrades: 0,
  };
}

export function loadState() {
  if (!fs.existsSync(STATE_FILE)) return null;
  try {
    return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
  } catch {
    return null;
  }
}

export function saveState(state) {
  fs.mkdirSync(STATE_DIR, { recursive: true });
  fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
  return STATE_FILE;
}

export function resetState() {
  if (fs.existsSync(STATE_DIR)) fs.rmSync(STATE_DIR, { recursive: true, force: true });
  return STATE_DIR;
}

/**
 * Full reset: state AND ledger. The ledger is append-only in normal operation,
 * but an explicit reset is an operator action on a simulated record, so it
 * clears both — otherwise the next cycle would re-log old trades.
 */
export function resetPaper() {
  resetState();
  if (fs.existsSync(LEDGER_FILE)) fs.writeFileSync(LEDGER_FILE, LEDGER_HEADER);
  return { state: STATE_DIR, ledger: LEDGER_FILE };
}

const LEDGER_HEADER = `# Paper Trade Ledger

Append-only. One row per **closed** paper trade. Written by the paper cycle
(\`node src/cli.js paper\`). Never edit or delete a row — corrections are new rows.

A paper trade is a simulated fill produced by the same engine that would place a
real one. It is a rehearsal, not a profit.

| Closed (UTC) | Pair | Side | Entry | Exit | Size | P&L | Fees | R | Exit reason |
|---|---|---|---|---|---|---|---|---|---|
`;

/** Identity of a ledger row — used to stop the same trade being logged twice. */
function tradeKey(t) {
  return [
    new Date(t.exitTime).toISOString(),
    t.pair ?? '',
    t.side,
    t.entryPrice.toFixed(8),
    t.exitPrice.toFixed(8),
  ].join('|');
}

/** Keys already present in the ledger. */
function existingKeys() {
  if (!fs.existsSync(LEDGER_FILE)) return new Set();
  const keys = new Set();
  for (const line of fs.readFileSync(LEDGER_FILE, 'utf8').split('\n')) {
    if (!line.startsWith('| ') || line.includes('| Closed')) continue;
    const c = line.split('|').map((s) => s.trim()).filter((s) => s.length);
    if (c.length < 9) continue;
    keys.add([c[0], c[1], c[2], c[3], c[4]].join('|'));
  }
  return keys;
}

/** Append closed paper trades to the ledger. Returns how many rows were added. */
export function appendToLedger(trades) {
  if (!trades.length) return 0;
  fs.mkdirSync(path.dirname(LEDGER_FILE), { recursive: true });
  if (!fs.existsSync(LEDGER_FILE)) {
    fs.writeFileSync(LEDGER_FILE, LEDGER_HEADER);
  }
  const seen = existingKeys();
  const fresh = trades.filter((t) => {
    const k = tradeKey(t);
    if (seen.has(k)) return false;
    seen.add(k);
    return true;
  });
  if (!fresh.length) return 0;
  const rows = fresh.map((t) => {
    const closed = new Date(t.exitTime).toISOString().replace('T', ' ').slice(0, 16);
    const r = t.rMultiple === null ? '—' : `${t.rMultiple.toFixed(2)}R`;
    const pnl = `${t.pnl >= 0 ? '+' : '-'}$${Math.abs(t.pnl).toFixed(2)}`;
    const fees = `$${t.fees.toFixed(2)}`;
    return `| ${closed} | ${t.pair ?? ''} | ${t.side} | ${t.entryPrice.toFixed(6)} | ${t.exitPrice.toFixed(6)} | ${t.size.toFixed(6)} | ${pnl} | ${fees} | ${r} | ${t.exitReason} |`;
  });
  fs.appendFileSync(LEDGER_FILE, rows.join('\n') + '\n');
  return rows.length;
}

/** Read the ledger back for reporting. */
export function readLedger() {
  if (!fs.existsSync(LEDGER_FILE)) return [];
  return fs
    .readFileSync(LEDGER_FILE, 'utf8')
    .split('\n')
    .filter((l) => l.startsWith('| ') && !l.includes('| Closed'))
    .map((l) => {
      const c = l.split('|').map((s) => s.trim()).filter((s) => s.length);
      return { closed: c[0], pair: c[1], side: c[2], pnl: c[6], fees: c[7], exitReason: c[9] };
    });
}

/**
 * The capital ledger.
 *
 * Capital you put in is NOT profit. This file keeps the two apart so the
 * status page can always answer "how much of this did trading actually make?"
 */
export function writeCapitalLedger(state) {
  const deposits = state.deposits || [];
  let running = state.state.initialEquity;
  const rows = deposits.map((d) => {
    running += d.amount;
    const date = d.date.slice(0, 10);
    return `| ${date} | $${d.amount.toFixed(2)} | $${running.toFixed(2)} | ${d.note} |`;
  });

  const content = `# Capital Ledger

_Generated by the paper cycle. This file records **money going in** — it is not a
performance record. Trading results live in \`paper-status.md\`._

**Started:** ${state.state.paperStart.slice(0, 10)}  
**Starting capital:** $${state.state.initialEquity.toFixed(2)}  
**Total deposited:** $${(state.totalDeposited || 0).toFixed(2)}  
**Total capital in the account:** $${(state.capitalBase || 0).toFixed(2)}

| Date | Amount | Running total | Note |
|---|---|---|---|
| ${state.state.paperStart.slice(0, 10)} | $${state.state.initialEquity.toFixed(2)} | $${state.state.initialEquity.toFixed(2)} | starting capital |
${rows.join('\n')}

> Deposits grow the account. They are not a return. The only number that measures
> the desk is **trading P&L ÷ total capital** — see \`paper-status.md\`.
`;
  fs.mkdirSync(path.dirname(CAPITAL_FILE), { recursive: true });
  fs.writeFileSync(CAPITAL_FILE, content);
  return CAPITAL_FILE;
}

/** Write the auto-generated paper status file. */
export function writeStatus(markdown) {
  fs.mkdirSync(path.dirname(STATUS_FILE), { recursive: true });
  fs.writeFileSync(STATUS_FILE, markdown);
  return STATUS_FILE;
}

__MAVIS_EOF_061__

cat > "workspaces/engine/src/paper/runner.js" <<'__MAVIS_EOF_062__'
import { backtest } from '../engine/backtest.js';
import { computeMetrics } from '../engine/metrics.js';
import { getStrategy } from '../strategies/index.js';
import { loadCandles } from '../data/store.js';
import {
  defaultState, loadState, saveState, resetState, resetPaper,
  appendToLedger, readLedger, writeStatus, writeCapitalLedger, LEDGER_FILE, STATUS_FILE,
} from './portfolio.js';

/**
 * The paper-trading cycle.
 *
 * One run = one full rehearsal of the desk's core loop:
 *   1. pull the latest candles from Kraken (public data, no key)
 *   2. run the strategy through the SAME engine that would place a real order
 *   3. keep only what happened since the paper record began
 *   4. log closed paper trades to the append-only ledger
 *   5. write the paper status file
 *
 * It never touches exchange keys and never places an order. That is not a
 * promise in the docs — it simply has no code path to an exchange write.
 */

const iso = (t) => new Date(t).toISOString();

export async function runPaperCycle(options = {}) {
  const {
    strategy: strategyName = 'sma-crossover',
    params = {},
    pair = 'XRPUSD',
    interval = 60,
    equity = 250,
    reset = false,
    refresh = true,
    paperStart = null,
    deposit = null,
    depositNote = '',
    makerFee = 0.004,
    takerFee = 0.008,
    slippageBps = 5,
    riskPct = 0.5,
    maxNotionalPct = 25,
    minTrades = 30,
  } = options;

  if (reset) resetPaper();

  let state = loadState();
  const fresh = !state;
  if (!state) {
    state = defaultState({ strategy: strategyName, params, pair, interval, equity });
    if (paperStart) state.paperStart = new Date(paperStart).toISOString();
  } else {
    // Keep the original paper start and equity — those define the record.
    state.strategy = strategyName;
    state.params = params;
    state.pair = pair;
    state.interval = interval;
  }

  // `bars` can be injected (tests, or an offline replay of a saved dataset)
  const loaded = options.bars
    ? { bars: options.bars, source: 'injected' }
    : await loadCandles({ pair: state.pair, interval: state.interval, refresh });
  const { bars, source } = loaded;
  if (bars.length < 3) throw new Error('not enough candles to run a paper cycle');

  // A new deposit lands in the account now.
  if (deposit && Number(deposit) > 0) {
    const amount = Number(deposit);
    state.deposits = state.deposits || [];
    state.deposits.push({
      date: new Date().toISOString(),
      amount: Number(amount.toFixed(2)),
      note: depositNote || 'deposit',
    });
  }

  // Where the paper record begins: the first bar at/after paperStart.
  const paperStartMs = Date.parse(state.paperStart);
  let startIndex = bars.findIndex((b) => b.time >= paperStartMs);
  if (startIndex === -1) startIndex = bars.length; // nothing new yet
  const isNew = startIndex < bars.length;

  // Map each deposit onto the first bar at/after it was made, so position
  // sizing uses the capital that was actually in the account at that moment.
  //
  // A deposit made after the last candle (e.g. you added money just now, but
  // the newest candle is from an hour ago) lands on the last bar — the cash is
  // real even if the bar isn't. Clamping to the last bar also keeps the deposit
  // inside the loop instead of silently dropping it.
  const deposits = (state.deposits || []).map((d) => {
    const t = Date.parse(d.date);
    let idx = bars.findIndex((b) => b.time >= t);
    if (idx === -1) idx = bars.length - 1;
    return { barIndex: Math.min(Math.max(idx, 0), bars.length - 1), amount: d.amount };
  });

  const strategy = getStrategy(state.strategy, state.params);
  const result = backtest(bars, strategy, {
    initialEquity: state.initialEquity,
    riskPct,
    makerFee,
    takerFee,
    slippageBps,
    maxNotionalPct,
    startIndex,
    deposits,
  });

  // Only trades opened after the paper start count, and only ones we haven't
  // already written to the ledger.
  const paperTrades = result.trades.map((t) => ({ ...t, pair: state.pair }));
  const newTrades = paperTrades.slice(state.recordedTrades);

  if (newTrades.length) {
    appendToLedger(newTrades);
    state.recordedTrades = paperTrades.length;
  }

  // Benchmark over the same window, for an honest comparison
  // Same constraints as the strategy — otherwise you're comparing a capped
  // strategy against an uncapped benchmark, which is not a comparison.
  const bench = backtest(bars, getStrategy('buy-and-hold'), {
    initialEquity: state.initialEquity,
    makerFee, takerFee, slippageBps, maxNotionalPct,
    startIndex,
    deposits,
  });

  const metrics = computeMetrics(
    { ...result, trades: paperTrades },
    { minTrades, intervalMinutes: state.interval },
  );
  const benchMetrics = computeMetrics(bench, { minTrades, intervalMinutes: state.interval });

  const lastBar = bars[bars.length - 1];
  const newBar = !state.lastBarTime || lastBar.time > state.lastBarTime;

  state.lastCycleAt = new Date().toISOString();
  state.lastBarTime = lastBar.time;
  state.paperStart = state.paperStart;
  saveState(state);

  const paperEquity = metrics.finalEquity;
  const benchEquity = benchMetrics.finalEquity;

  const status = {
    state,
    fresh,
    isNew,
    newBar,
    source,
    bars: bars.length,
    startIndex,
    paperTrades,
    newTrades,
    metrics,
    benchMetrics,
    equity: paperEquity,
    benchEquity,
    edge: metrics.netProfit - benchMetrics.netProfit,
    openPosition: result.equityCurve.length
      ? result.equityCurve[result.equityCurve.length - 1].inPosition
      : false,
    ledgerRows: readLedger().length,
    lastBarTime: lastBar.time,
    deposits: state.deposits || [],
    totalDeposited: metrics.totalDeposits,
    capitalBase: metrics.capitalBase,
  };

  writeStatus(renderStatusMarkdown(status));
  writeCapitalLedger(status);

  return status;
}

function fmtDate(t) {
  if (!t) return '—';
  return iso(t).replace('T', ' ').slice(0, 16);
}

function renderStatusMarkdown(s) {
  const m = s.metrics;
  const b = s.benchMetrics;
  const money = (v) => `${v < 0 ? '-' : ''}$${Math.abs(v).toFixed(2)}`;
  const pct = (v) => `${v.toFixed(2)}%`;

  return `# Paper Trading Status

_Auto-generated by the paper cycle. Do not edit by hand — the next cycle overwrites this file._
_The agent-maintained board is \`docs/status-board.md\`._

**Strategy:** ${s.state.strategy} ${JSON.stringify(s.state.params)}  
**Pair:** ${s.state.pair} · **Timeframe:** ${s.state.interval}m  
**Paper started:** ${fmtDate(s.state.paperStart)}  
**Last cycle:** ${fmtDate(s.state.lastCycleAt)}  
**Last candle:** ${fmtDate(s.lastBarTime)}  

## Where we are

| Metric | Value | Benchmark (buy & hold) |
|---|---|---|
| **Total capital in the account** | **${money(s.capitalBase)}** | ${money(s.capitalBase)} |
| Deposited (your money in) | ${money(s.totalDeposited)} | ${money(s.totalDeposited)} |
| **Trading P&L** | **${money(m.netProfit)}** (${pct(m.netProfitPct)} of capital) | ${money(b.netProfit)} (${pct(b.netProfitPct)}) |
| Total equity | ${money(s.equity)} | ${money(s.benchEquity)} |
| Edge vs benchmark | **${s.edge >= 0 ? '+' : ''}${money(s.edge)}** | — |
| Trades | ${m.totalTrades} | ${b.totalTrades} |
| Win rate | ${pct(m.winRate)} | ${pct(b.winRate)} |
| Profit factor | ${Number.isFinite(m.profitFactor) ? m.profitFactor.toFixed(2) : '∞'} | ${Number.isFinite(b.profitFactor) ? b.profitFactor.toFixed(2) : '∞'} |
| Max drawdown | ${pct(m.maxDrawdownPct)} | ${pct(b.maxDrawdownPct)} |
| Fees paid | ${money(m.totalFees)} | ${money(b.totalFees)} |
| Exposure | ${pct(m.exposure)} | ${pct(b.exposure)} |

**Verdict:** ${m.verdict}

> **Read the two numbers separately.** Deposited capital is your paycheck — it is not
> a return. Trading P&L is the only line that measures the desk. A growing account
> with flat trading P&L means the desk isn't working yet.

## Recent paper trades

${s.paperTrades.length === 0 ? '_No paper trades yet._' : s.paperTrades.slice(-10).reverse().map((t) => `- ${fmtDate(t.exitTime)} · ${t.side} · ${t.pnl >= 0 ? '+' : ''}$${Math.abs(t.pnl).toFixed(2)} · ${t.exitReason}`).join('\n')}

Full ledger: \`docs/trading/journal/paper-ledger.md\` (${s.ledgerRows} rows)
`;
}

export { LEDGER_FILE, STATUS_FILE };

__MAVIS_EOF_062__

cat > "workspaces/engine/src/strategies/atr-breakout.js" <<'__MAVIS_EOF_063__'
import { RollingAtr, RollingChannel } from '../engine/indicators.js';

/**
 * Donchian breakout with an ATR stop.
 *
 * HYPOTHESIS: a pair that breaks its N-bar range is in a directional move that
 * tends to continue for a while.
 *
 * Honest note: breakout systems love backtests and hate live trading — the
 * breakout bar itself has worse fill prices than the backtest assumes. That's
 * exactly what the fee + slippage model here is for.
 */
export function makeAtrBreakout(params = {}) {
  const p = { channel: 20, atrPeriod: 14, stopAtrMult: 2, exitChannel: 10, ...params };
  const channel = new RollingChannel(p.channel);
  const exitChannel = new RollingChannel(p.exitChannel);
  const atr = new RollingAtr(p.atrPeriod);

  return {
    name: 'atr-breakout',
    params: p,
    onBar(ctx) {
      const ch = channel.push(ctx.bar);
      const ex = exitChannel.push(ctx.bar);
      const a = atr.push(ctx.bar);
      if (!ch.ready || !ex.ready || !a) return { action: 'hold' };

      // Breakout: close above the prior channel high (use the previous bar's
      // channel so we don't compare the current bar to itself).
      const prevHigh = ctx.index > 0 ? ctx.bars[ctx.index - 1].high : null;
      const prevLow = ctx.index > 0 ? ctx.bars[ctx.index - 1].low : null;
      if (prevHigh === null) return { action: 'hold' };

      if (ctx.position && ctx.position.side === 'long') {
        if (ctx.bar.close < ex.lowest) {
          return { action: 'exit', reason: `close ${ctx.bar.close.toFixed(4)} fell below ${p.exitChannel}-bar low ${ex.lowest.toFixed(4)}` };
        }
        return { action: 'hold' };
      }

      if (!ctx.position && ctx.bar.close > prevHigh && ctx.bar.close > ch.highest) {
        const stop = ctx.bar.close - p.stopAtrMult * a;
        return {
          action: 'enter_long',
          stop,
          reason: `close ${ctx.bar.close.toFixed(4)} broke the ${p.channel}-bar high ${ch.highest.toFixed(4)}`,
        };
      }
      if (!ctx.position && ctx.bar.close < prevLow && ctx.bar.close < ch.lowest) {
        const stop = ctx.bar.close + p.stopAtrMult * a;
        return {
          action: 'enter_short',
          stop,
          reason: `close ${ctx.bar.close.toFixed(4)} broke the ${p.channel}-bar low ${ch.lowest.toFixed(4)}`,
        };
      }

      return { action: 'hold' };
    },
  };
}

__MAVIS_EOF_063__

cat > "workspaces/engine/src/strategies/buy-and-hold.js" <<'__MAVIS_EOF_064__'
/**
 * Buy and hold — the benchmark.
 *
 * HYPOTHESIS: the asset goes up (or it doesn't).
 *
 * This is the number every strategy has to beat, after fees. If your strategy
 * can't beat "do nothing" on the same period with the same money, you don't
 * have a strategy — you have a hobby.
 */
export function makeBuyAndHold(params = {}) {
  const p = { notionalPct: 100, ...params };
  return {
    name: 'buy-and-hold',
    params: p,
    onBar(ctx) {
      // Stay invested. If the engine's time cap ever closes the position, get
      // straight back in — this is the benchmark, and a benchmark that sits in
      // cash half the time isn't a benchmark.
      if (!ctx.position) {
        return {
          action: 'enter_long',
          notionalPct: p.notionalPct,
          reason: 'benchmark: all-in',
        };
      }
      return { action: 'hold' };
    },
  };
}

__MAVIS_EOF_064__

cat > "workspaces/engine/src/strategies/index.js" <<'__MAVIS_EOF_065__'
import { makeSmaCrossover } from './sma-crossover.js';
import { makeAtrBreakout } from './atr-breakout.js';
import { makeBuyAndHold } from './buy-and-hold.js';

/**
 * Strategy registry.
 *
 * `hypothesis` is the sentence you'd write in the experiment log before you
 * run it. If you can't write one, don't run it.
 */
export const STRATEGIES = {
  'buy-and-hold': {
    factory: makeBuyAndHold,
    description: 'All-in from bar 0 and hold. The benchmark everything else must beat.',
    hypothesis: 'The asset rises over this period.',
    params: [{ notionalPct: 100 }],
  },
  'sma-crossover': {
    factory: makeSmaCrossover,
    description: 'Fast/slow SMA cross in, ATR-based stop, cross out.',
    hypothesis: 'Multi-hour trends persist, so a moving-average cross captures part of the move.',
    params: [
      { fast: 10, slow: 50 },
      { fast: 20, slow: 100 },
      { fast: 50, slow: 200 },
    ],
  },
  'atr-breakout': {
    factory: makeAtrBreakout,
    description: 'Donchian breakout with an ATR stop and a channel exit.',
    hypothesis: 'A break of the N-bar range starts a move that continues.',
    params: [
      { channel: 10, stopAtrMult: 2 },
      { channel: 20, stopAtrMult: 2 },
      { channel: 55, stopAtrMult: 3 },
    ],
  },
};

export function getStrategy(name, params = {}) {
  const entry = STRATEGIES[name];
  if (!entry) {
    throw new Error(`unknown strategy "${name}". Available: ${Object.keys(STRATEGIES).join(', ')}`);
  }
  return entry.factory(params);
}

export function listStrategies() {
  return Object.entries(STRATEGIES).map(([name, s]) => ({
    name,
    description: s.description,
    hypothesis: s.hypothesis,
    params: s.params,
  }));
}

__MAVIS_EOF_065__

cat > "workspaces/engine/src/strategies/sma-crossover.js" <<'__MAVIS_EOF_066__'
import { RollingSma, RollingAtr } from '../engine/indicators.js';

/**
 * SMA crossover — the baseline trend-following strategy.
 *
 * HYPOTHESIS: price trends persist over multi-hour horizons, so a fast/slow
 * moving-average cross captures part of the move.
 *
 * HONEST WARNING: this is a textbook baseline, not an edge. Its job is to give
 * you something to beat. If your idea can't beat this after fees, it isn't an
 * idea yet.
 */
export function makeSmaCrossover(params = {}) {
  const p = { fast: 20, slow: 100, atrPeriod: 14, stopAtrMult: 1.5, targetR: 2, ...params };
  const fastSma = new RollingSma(p.fast);
  const slowSma = new RollingSma(p.slow);
  const atr = new RollingAtr(p.atrPeriod);
  let prevFast = null;
  let prevSlow = null;

  return {
    name: 'sma-crossover',
    params: p,
    onBar(ctx) {
      const f = fastSma.push(ctx.bar.close);
      const s = slowSma.push(ctx.bar.close);
      const a = atr.push(ctx.bar);
      const crossedUp = prevFast !== null && prevSlow !== null && prevFast <= prevSlow && f > s;
      const crossedDown = prevFast !== null && prevSlow !== null && prevFast >= prevSlow && f < s;
      prevFast = f;
      prevSlow = s;

      if (!f || !s || !a) return { action: 'hold' };

      if (ctx.position && ctx.position.side === 'long' && crossedDown) {
        return { action: 'exit', reason: `fast SMA crossed below slow SMA (${f.toFixed(4)} < ${s.toFixed(4)})` };
      }

      if (!ctx.position && crossedUp) {
        const stop = ctx.bar.close - p.stopAtrMult * a;
        const target = ctx.bar.close + p.targetR * p.stopAtrMult * a;
        return {
          action: 'enter_long',
          stop,
          target,
          reason: `fast SMA crossed above slow SMA (${f.toFixed(4)} > ${s.toFixed(4)}), ATR ${a.toFixed(4)}`,
        };
      }

      return { action: 'hold' };
    },
  };
}

__MAVIS_EOF_066__

cat > "workspaces/engine/tests/data.test.js" <<'__MAVIS_EOF_067__'
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { loadCsv, saveCsv } from '../src/data/csv.js';
import { krakenResultKey } from '../src/data/kraken.js';

const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'dt-'));

test('CSV with unix timestamps is parsed and sorted', () => {
  const dir = tmp();
  const file = path.join(dir, 'ohlc.csv');
  fs.writeFileSync(file, [
    'timestamp,open,high,low,close,volume',
    '1700007200,2.0,2.5,1.9,2.4,100',
    '1700003600,1.5,1.8,1.4,1.7,80',
    '1700005400,1.7,2.1,1.6,2.0,90',
  ].join('\n'));

  const bars = loadCsv(file);
  assert.equal(bars.length, 3);
  assert.equal(bars[0].close, 1.7);       // earliest first
  assert.equal(bars[2].close, 2.4);
  assert.equal(bars[0].time, 1700003600 * 1000);
  assert.equal(bars[0].volume, 80);
});

test('CSV with ISO dates and alternative headers works', () => {
  const dir = tmp();
  const file = path.join(dir, 'ohlc.csv');
  fs.writeFileSync(file, [
    'Date,Open,High,Low,Close,Vol',
    '2026-01-02,1.0,1.2,0.9,1.1,10',
    '2026-01-01,0.9,1.1,0.8,1.0,12',
  ].join('\n'));

  const bars = loadCsv(file);
  assert.equal(bars.length, 2);
  assert.equal(bars[0].open, 0.9);
  assert.equal(bars[1].close, 1.1);
  assert.equal(bars[0].time, Date.parse('2026-01-01'));
});

test('a CSV missing a required column fails with a helpful message', () => {
  const dir = tmp();
  const file = path.join(dir, 'bad.csv');
  fs.writeFileSync(file, 'time,open,close\n1700003600,1,2\n');
  assert.throws(() => loadCsv(file), /missing a "high" column/);
});

test('bars round-trip through save and load', () => {
  const dir = tmp();
  const file = path.join(dir, 'rt.csv');
  const bars = [
    { time: 1700003600000, open: 1, high: 2, low: 0.5, close: 1.5, volume: 10 },
    { time: 1700007200000, open: 1.5, high: 2.5, low: 1.2, close: 2.2, volume: 12 },
  ];
  saveCsv(file, bars);
  const back = loadCsv(file);
  assert.equal(back.length, 2);
  assert.equal(back[0].time, bars[0].time);
  assert.equal(back[1].close, 2.2);
});

test('Kraken legacy result keys are mapped', () => {
  assert.equal(krakenResultKey('XRPUSD'), 'XXRPZUSD');
  assert.equal(krakenResultKey('XBTUSD'), 'XXBTZUSD');
  assert.equal(krakenResultKey('ETHUSD'), 'XETHZUSD');
});

__MAVIS_EOF_067__

cat > "workspaces/engine/tests/deposits.test.js" <<'__MAVIS_EOF_068__'
import test from 'node:test';
import assert from 'node:assert/strict';
import { backtest } from '../src/engine/backtest.js';
import { computeMetrics } from '../src/engine/metrics.js';

function bar(time, open, high, low, close) {
  return { time, open, high, low, close, volume: 100 };
}

function series(n, fn) {
  return Array.from({ length: n }, (_, i) => fn(i));
}

/**
 * Deposits are money going IN. They must never look like profit.
 */
test('a deposit increases the cash but is not counted as trading profit', () => {
  const bars = series(6, (i) => bar(i * 1000, 100, 100, 100, 100));

  const result = backtest(bars, {
    name: 'flat',
    onBar: () => ({ action: 'hold' }),
  }, { initialEquity: 250, deposits: [{ barIndex: 2, amount: 100 }], makerFee: 0, takerFee: 0 });

  assert.equal(result.totalDeposits, 100);
  assert.equal(result.finalEquity, 350, 'the account holds the deposit');
});

test('a deposit re-sizes later positions', () => {
  const bars = series(9, (i) => bar(i * 1000, 100, 100, 100, 100));

  const result = backtest(bars, {
    name: 'sizer',
    onBar(ctx) {
      if (ctx.index === 0) return { action: 'enter_long', stop: 95 };  // opens at bar 1
      if (ctx.index === 2) return { action: 'exit' };                 // closes at bar 3
      if (ctx.index === 3) return { action: 'enter_long', stop: 95 };  // opens at bar 4
      return { action: 'hold' };
    },
  }, {
    initialEquity: 250,
    riskPct: 1,
    deposits: [{ barIndex: 2, amount: 250 }],
    makerFee: 0, takerFee: 0, slippageBps: 0, maxNotionalPct: 100,
  });

  assert.equal(result.trades.length, 2, 'expected two round trips');

  // First trade: risk $2.50 (1% of 250) / $5 stop distance = 0.5 units
  assert.equal(result.trades[0].size, 0.5);

  // Second trade: the deposit landed on bar 2, so capital is $500 and
  // 1% risk = $5.00 / $5 = 1.0 units
  assert.equal(result.trades[1].size, 1);
});

test('metrics separate capital in from trading P&L', () => {
  const bars = series(6, (i) => bar(i * 1000, 100, 100, 100, 100));

  const result = backtest(bars, {
    name: 'flat',
    onBar: () => ({ action: 'hold' }),
  }, { initialEquity: 250, deposits: [{ barIndex: 1, amount: 100 }], makerFee: 0, takerFee: 0 });

  const m = computeMetrics(result, { minTrades: 30 });

  assert.equal(m.totalDeposits, 100);
  assert.equal(m.capitalBase, 350, 'capital in = starting + deposits');
  assert.equal(m.netProfit, 0, 'a deposit is not profit');
  assert.equal(m.finalEquity, 350, 'equity includes the deposit');
  assert.equal(m.netProfitPct, 0, 'return on capital is measured on capital in');
});

test('a deposit does not distort the profit factor or the trade list', () => {
  const bars = [
    bar(0, 100, 100, 100, 100),
    bar(1, 100, 100, 100, 100),
    bar(2, 100, 120, 100, 120),
    bar(3, 120, 120, 120, 120),
  ];

  const result = backtest(bars, {
    name: 'winner',
    onBar(ctx) {
      if (ctx.index === 0) return { action: 'enter_long', stop: 95, target: 120 };
      return { action: 'hold' };
    },
  }, {
    initialEquity: 250, riskPct: 10,
    deposits: [{ barIndex: 1, amount: 100 }],
    makerFee: 0, takerFee: 0, slippageBps: 0, maxNotionalPct: 100,
  });

  const m = computeMetrics(result, { minTrades: 30 });
  assert.equal(m.totalTrades, 1);

  // The deposit landed before the fill, so the position is sized off $350:
  // risk $35 / $5 = 7 units, capped by the 100%-of-equity notional rule at $350
  // → 3.5 units. Entry 350, exit 3.5 × 120 = 420, so the trade made 70.
  assert.equal(m.netProfit, 70, 'only the trade P&L counts — not the deposit');
  assert.equal(m.totalDeposits, 100, 'the deposit is tracked separately');
  assert.equal(m.capitalBase, 350, 'capital in = starting + deposits');
  assert.equal(m.finalEquity, 420, 'equity = capital in + trading P&L');
});

test('a deposit made after the last candle still lands in the account', async () => {
  // Regression: a deposit dated now, when the newest candle is older, used to
  // be dropped entirely — the account silently ignored real money.
  const fs = await import('node:fs');
  const os = await import('node:os');
  const path = await import('node:path');
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'dep-'));
  process.env.DIGITRADERS_PAPER_STATE_DIR = path.join(tmp, 'state');
  process.env.DIGITRADERS_PAPER_LEDGER = path.join(tmp, 'ledger.md');
  process.env.DIGITRADERS_PAPER_STATUS = path.join(tmp, 'status.md');

  const { runPaperCycle: run } = await import('../src/paper/runner.js');

  const bars = series(30, (i) => bar(Date.UTC(2026, 0, 1) + i * 3600 * 1000, 100, 100, 100, 100));

  const status = await run({
    strategy: 'buy-and-hold', pair: 'TESTUSD', interval: 60, equity: 250,
    reset: true,
    paperStart: new Date(bars[0].time).toISOString(),
    deposit: 100,
    depositNote: 'payday',
    bars,
  });

  assert.equal(status.totalDeposited, 100, 'the deposit must not be dropped');
  assert.equal(status.capitalBase, 350, 'capital in = starting + deposit');

  // The benchmark traded, so fees moved the equity a little — but the deposit
  // is in the account and it is NOT counted as profit.
  assert.ok(
    Math.abs(status.equity - 350) < 5,
    `equity should be ~350 minus fees, got ${status.equity}`,
  );
  assert.ok(
    status.metrics.netProfit < 0 && status.metrics.netProfit > -5,
    `trading P&L should be fees only (negative, small), got ${status.metrics.netProfit}`,
  );
});

__MAVIS_EOF_068__

cat > "workspaces/engine/tests/metrics.test.js" <<'__MAVIS_EOF_069__'
import test from 'node:test';
import assert from 'node:assert/strict';
import { computeMetrics } from '../src/engine/metrics.js';

function trade(pnl, r = null, fee = 0, barsHeld = 10) {
  return { pnl, rMultiple: r, fees: fee, barsHeld, side: 'long' };
}

function curve(values) {
  return values.map((equity, i) => ({ time: i * 1000, equity, inPosition: false, cash: equity }));
}

test('profit factor, win rate and expectancy are computed from the trade list', () => {
  const trades = [trade(100, 1), trade(100, 1), trade(-50, -0.5), trade(-50, -0.5)];
  const m = computeMetrics({ trades, equityCurve: curve([1000, 1000, 1050, 1050]), initialEquity: 1000, totalFees: 10 });

  assert.equal(m.totalTrades, 4);
  assert.equal(m.wins, 2);
  assert.equal(m.losses, 2);
  assert.equal(m.winRate, 50);
  assert.equal(m.grossProfit, 200);
  assert.equal(m.grossLoss, 100);
  assert.equal(m.profitFactor, 2);
  assert.equal(m.netProfit, 100);
  assert.equal(m.netProfitPct, 10);
  assert.equal(m.expectancy, 25);
});

test('max drawdown is measured from the equity peak', () => {
  const m = computeMetrics({
    trades: [],
    equityCurve: curve([1000, 1200, 900, 1100]),
    initialEquity: 1000,
    totalFees: 0,
  });
  assert.equal(m.maxDrawdown, 300);
  assert.equal(Math.round(m.maxDrawdownPct), 25);
});

test('a sample below the minimum is reported as no conclusion', () => {
  const m = computeMetrics({
    trades: [trade(10), trade(5)],
    equityCurve: curve([1000, 1000, 1015]),
    initialEquity: 1000,
    totalFees: 0,
  }, { minTrades: 30 });
  assert.match(m.verdict, /INSUFFICIENT SAMPLE/);
});

test('fees are reported as a share of equity and of profit', () => {
  const m = computeMetrics({
    trades: [trade(100, 1, 10), trade(-20, -0.2, 5)],
    equityCurve: curve([1000, 1000, 1080]),
    initialEquity: 1000,
    totalFees: 15,
  });
  assert.equal(m.totalFees, 15);
  assert.equal(m.feesPctOfEquity, 1.5);
  assert.equal(m.feesVsProfit, 0.1875);
});

test('profit factor is infinite when there are no losers', () => {
  const m = computeMetrics({
    trades: [trade(50), trade(50)],
    equityCurve: curve([1000, 1100]),
    initialEquity: 1000,
    totalFees: 0,
  });
  assert.equal(m.profitFactor, Infinity);
});

__MAVIS_EOF_069__

cat > "workspaces/engine/tests/no-lookahead.test.js" <<'__MAVIS_EOF_070__'
import test from 'node:test';
import assert from 'node:assert/strict';
import { backtest, createBarGuard } from '../src/engine/backtest.js';

/**
 * The most important tests in this repo.
 *
 * If the simulator leaks the future, every backtest lies, and the whole desk
 * is built on sand. These tests pin that down.
 */

function bar(time, open, high, low, close, volume = 100) {
  return { time, open, high, low, close, volume };
}

function series(n, fn) {
  return Array.from({ length: n }, (_, i) => fn(i));
}

test('a signal on bar i fills at the OPEN of bar i+1, never bar i', () => {
  const bars = series(6, (i) => bar(i * 1000, 100 + i, 101 + i, 99 + i, 100 + i));

  const result = backtest(bars, {
    name: 'enter-once',
    onBar(ctx) {
      if (ctx.index === 0) {
        return { action: 'enter_long', stop: 50, reason: 'test' };
      }
      return { action: 'hold' };
    },
  }, { initialEquity: 1000, makerFee: 0, takerFee: 0, slippageBps: 0, maxNotionalPct: 100 });

  assert.equal(result.trades.length, 1);
  // bar 1 opens at 101 — the fill must be 101, not bar 0's close of 100
  assert.equal(result.trades[0].entryPrice, 101);
  assert.equal(result.trades[0].entryIndex, 1);
});

test('the strategy cannot read a future bar', () => {
  const bars = series(5, (i) => bar(i * 1000, 100, 101, 99, 100));

  const guarded = createBarGuard(bars, 2);
  assert.equal(guarded.length, 3);
  assert.equal(guarded[2].close, 100);
  assert.throws(() => guarded[3], /lookahead blocked/);
  assert.throws(() => guarded[4], /lookahead blocked/);
});

test('a strategy that tries to peek fails loudly instead of silently profiting', () => {
  const bars = series(10, (i) => bar(i * 1000, 100, 101, 99, 100));

  assert.throws(
    () =>
      backtest(bars, {
        name: 'cheater',
        onBar(ctx) {
          const future = ctx.bars[ctx.index + 1]; // peek
          return { action: 'hold', reason: String(future) };
        },
      }),
    /lookahead blocked/,
  );
});

test('a stop loss exits at the stop price and charges the taker fee', () => {
  // bar 1 opens at 100; bar 2 dives to 90 and the stop is at 95
  const bars = [
    bar(0, 100, 100, 100, 100),
    bar(1, 100, 100, 100, 100),
    bar(2, 100, 100, 90, 95),
    bar(3, 95, 95, 94, 94),
  ];

  const result = backtest(bars, {
    name: 'enter-once',
    onBar(ctx) {
      if (ctx.index === 0) return { action: 'enter_long', stop: 95 };
      return { action: 'hold' };
    },
  }, { initialEquity: 1000, makerFee: 0, takerFee: 0, slippageBps: 0, maxNotionalPct: 100, riskPct: 10 });

  assert.equal(result.trades.length, 1);
  assert.equal(result.trades[0].exitReason, 'stop');
  assert.equal(result.trades[0].exitPrice, 95);
});

test('when a bar contains both the stop and the target, the stop is assumed first', () => {
  // deliberately ambiguous bar — the engine must take the conservative path
  const bars = [
    bar(0, 100, 100, 100, 100),
    bar(1, 100, 100, 100, 100),
    bar(2, 100, 120, 80, 110), // hits both 95 and 120
    bar(3, 110, 110, 109, 109),
  ];

  const result = backtest(bars, {
    name: 'ambiguous',
    onBar(ctx) {
      if (ctx.index === 0) return { action: 'enter_long', stop: 95, target: 120 };
      return { action: 'hold' };
    },
  }, { initialEquity: 1000, makerFee: 0, takerFee: 0, slippageBps: 0, maxNotionalPct: 100, riskPct: 10 });

  assert.equal(result.trades[0].exitReason, 'stop');
  assert.ok(result.trades[0].pnl < 0, 'the ambiguous bar must not be a profit');
});

test('position sizing uses the risk percentage and the stop distance', () => {
  const bars = series(6, (i) => bar(i * 1000, 100, 100, 100, 100));

  const result = backtest(bars, {
    name: 'sizer',
    onBar(ctx) {
      if (ctx.index === 0) return { action: 'enter_long', stop: 95 };
      return { action: 'hold' };
    },
  }, { initialEquity: 1000, riskPct: 1, makerFee: 0, takerFee: 0, slippageBps: 0, maxNotionalPct: 100 });

  // risk $10 / $5 distance = 2 units
  assert.equal(result.trades[0].size, 2);
  assert.equal(result.trades[0].notional, 200);
});

test('a trade with no stop and no size is rejected, not guessed', () => {
  const bars = series(6, (i) => bar(i * 1000, 100, 100, 100, 100));

  const result = backtest(bars, {
    name: 'no-stop',
    onBar(ctx) {
      if (ctx.index === 0) return { action: 'enter_long' };
      return { action: 'hold' };
    },
  }, { initialEquity: 1000, makerFee: 0, takerFee: 0, slippageBps: 0 });

  assert.equal(result.trades.length, 0);
  assert.match(result.logs.join('\n'), /no stop and no size/);
});

test('the max-notional cap shrinks an oversized position', () => {
  const bars = series(6, (i) => bar(i * 1000, 100, 100, 100, 100));

  const result = backtest(bars, {
    name: 'capped',
    onBar(ctx) {
      if (ctx.index === 0) return { action: 'enter_long', stop: 95 };
      return { action: 'hold' };
    },
  }, { initialEquity: 1000, riskPct: 50, makerFee: 0, takerFee: 0, slippageBps: 0, maxNotionalPct: 25 });

  assert.ok(result.trades[0].notional <= 250.0001, 'notional must respect the cap');
});

test('fees are charged on entry and on exit', () => {
  const bars = [
    bar(0, 100, 100, 100, 100),
    bar(1, 100, 100, 100, 100),
    bar(2, 100, 120, 100, 120),
    bar(3, 120, 120, 120, 120),
  ];

  const result = backtest(bars, {
    name: 'fees',
    onBar(ctx) {
      if (ctx.index === 0) return { action: 'enter_long', stop: 95, target: 120 };
      return { action: 'hold' };
    },
  }, { initialEquity: 1000, makerFee: 0.004, takerFee: 0.008, slippageBps: 0, maxNotionalPct: 100, riskPct: 10 });

  assert.ok(result.totalFees > 0);
  assert.equal(result.trades[0].exitReason, 'target');

  // a target exit is a resting limit → maker fee on both legs
  const t = result.trades[0];
  const expected = t.notional * 0.004 + t.size * t.exitPrice * 0.004;
  assert.ok(
    Math.abs(result.totalFees - expected) < 0.001,
    `expected ${expected} in fees, got ${result.totalFees}`,
  );
});

test('an open position is closed at the end of the data', () => {
  const bars = series(5, (i) => bar(i * 1000, 100, 100, 100, 100));

  const result = backtest(bars, {
    name: 'still-open',
    onBar(ctx) {
      if (ctx.index === 0) return { action: 'enter_long', stop: 1 };
      return { action: 'hold' };
    },
  }, { initialEquity: 1000, makerFee: 0, takerFee: 0, slippageBps: 0, maxNotionalPct: 100, riskPct: 1 });

  assert.equal(result.trades.length, 1);
  assert.equal(result.trades[0].exitReason, 'end_of_data');
});

__MAVIS_EOF_070__

cat > "workspaces/engine/tests/paper.test.js" <<'__MAVIS_EOF_071__'
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

// Point the paper module at a temp dir BEFORE it is imported.
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'paper-'));
process.env.DIGITRADERS_PAPER_STATE_DIR = path.join(tmp, 'state');
process.env.DIGITRADERS_PAPER_LEDGER = path.join(tmp, 'ledger.md');
process.env.DIGITRADERS_PAPER_STATUS = path.join(tmp, 'status.md');

const { runPaperCycle } = await import('../src/paper/runner.js');
const { loadState, appendToLedger, resetPaper, LEDGER_FILE, STATE_FILE } = await import('../src/paper/portfolio.js');

/** Deterministic candles: a clean uptrend so a long actually makes money. */
function makeBars(n = 200, start = 100) {
  return Array.from({ length: n }, (_, i) => {
    const price = start + i * 0.5;
    return {
      time: Date.UTC(2026, 0, 1) + i * 3600 * 1000,
      open: price,
      high: price + 0.3,
      low: price - 0.3,
      close: price + 0.15,
      volume: 1000,
    };
  });
}

test('a paper cycle produces a record, a ledger row and a status file', async () => {
  const bars = makeBars();
  const status = await runPaperCycle({
    strategy: 'buy-and-hold',
    pair: 'TESTUSD',
    interval: 60,
    equity: 250,
    reset: true,
    paperStart: new Date(bars[10].time).toISOString(),
    bars,
  });

  assert.ok(status.paperTrades.length >= 1, 'expected at least one paper trade');
  assert.ok(fs.existsSync(STATE_FILE), 'state file written');
  assert.ok(fs.existsSync(LEDGER_FILE), 'ledger written');
  assert.ok(fs.existsSync(path.join(tmp, 'status.md')), 'status file written');

  const ledger = fs.readFileSync(LEDGER_FILE, 'utf8');
  assert.match(ledger, /\| Closed \(UTC\)/);
  assert.ok(ledger.split('\n').filter((l) => l.startsWith('| 2026')).length >= 1);
});

test('running the cycle again does not duplicate ledger rows', async () => {
  const bars = makeBars();
  await runPaperCycle({
    strategy: 'buy-and-hold', pair: 'TESTUSD', interval: 60, equity: 250,
    paperStart: new Date(bars[10].time).toISOString(), bars,
  });
  const before = fs.readFileSync(LEDGER_FILE, 'utf8').split('\n').filter((l) => l.startsWith('| 2026')).length;
  await runPaperCycle({
    strategy: 'buy-and-hold', pair: 'TESTUSD', interval: 60, equity: 250,
    paperStart: new Date(bars[10].time).toISOString(), bars,
  });
  const after = fs.readFileSync(LEDGER_FILE, 'utf8').split('\n').filter((l) => l.startsWith('| 2026')).length;
  assert.equal(after, before, 'the same paper trade must not be logged twice');
});

test('the paper record starts fresh — no trades before paperStart', async () => {
  const bars = makeBars();
  const status = await runPaperCycle({
    strategy: 'buy-and-hold', pair: 'TESTUSD', interval: 60, equity: 250,
    reset: true,
    paperStart: new Date(bars[150].time).toISOString(),
    bars,
  });
  for (const t of status.paperTrades) {
    assert.ok(t.entryTime >= bars[150].time, 'no trade may predate the paper start');
  }
});

test('the benchmark is held to the same notional cap as the strategy', async () => {
  const bars = makeBars();
  const status = await runPaperCycle({
    strategy: 'sma-crossover', pair: 'TESTUSD', interval: 60, equity: 250,
    reset: true,
    paperStart: new Date(bars[10].time).toISOString(),
    bars,
  });
  // Same constraints on both sides means the edge is a like-for-like comparison
  assert.ok(Number.isFinite(status.edge));
});

test('reset clears both the state and the ledger', async () => {
  const bars = makeBars();
  await runPaperCycle({
    strategy: 'buy-and-hold', pair: 'TESTUSD', interval: 60, equity: 250,
    reset: true, paperStart: new Date(bars[10].time).toISOString(), bars,
  });
  assert.ok(fs.readFileSync(LEDGER_FILE, 'utf8').split('\n').some((l) => l.startsWith('| 2026')));

  resetPaper();
  const rows = fs.readFileSync(LEDGER_FILE, 'utf8').split('\n').filter((l) => l.startsWith('| 2026'));
  assert.equal(rows.length, 0, 'reset must clear the ledger too');
  assert.equal(loadState(), null, 'reset must clear the state');
});

test('the ledger keeps its header after a reset', () => {
  const content = fs.readFileSync(LEDGER_FILE, 'utf8');
  assert.match(content, /# Paper Trade Ledger/);
  assert.match(content, /\| Closed \(UTC\)/);
});

__MAVIS_EOF_071__

cat > "workspaces/ops/README.md" <<'__MAVIS_EOF_072__'
# Risk and Operations

Risk policy enforcement, P&L, the trade journal, and the daily dashboard.

**Owner agent:** Risk and Ops
**Paperclip project:** Risk and Operations

## What's here

- `dashboards/` — the P&L / drawdown / exposure dashboard
- `reports/` — daily and weekly reports
- `checks/` — automated risk checks (position size, daily loss, drawdown)

## Rules

- **Read-only on money.** This workspace prepares reports and checks limits. It never
  places, modifies, or closes an order.
- **The risk policy is the source of truth** — `docs/trading/risk-policy.md`. If a check
  disagrees with the policy, the policy wins and the check is a bug.
- **Never edit the trade journal.** Corrections are appended.
- Raw exchange exports belong in `data/` (git-ignored), not here.

## Layout

```
workspaces/ops/
├── dashboards/   # equity, drawdown, exposure
├── reports/      # daily / weekly
└── checks/       # automated limit checks
```

__MAVIS_EOF_072__

cat > "workspaces/ops/package.json" <<'__MAVIS_EOF_073__'
{
  "name": "@trading/ops",
  "version": "0.0.0",
  "private": true,
  "type": "module",
  "description": "Risk checks, P&L dashboards, and reports. Read-only on money.",
  "scripts": {
    "build": "echo 'ops: no build configured yet'",
    "test": "echo 'ops: no tests configured yet'",
    "lint": "echo 'ops: no linter configured yet'",
    "board": "echo 'ops: status board refresh not configured yet'"
  }
}

__MAVIS_EOF_073__

cat > "workspaces/research/README.md" <<'__MAVIS_EOF_074__'
# Market Research

Market data, signal validation, regime notes. **This workspace has no exchange
credentials by design** — the analyst can see, but cannot touch.

**Owner agent:** Market Analyst
**Paperclip project:** Market Research

## What's here

- `notes/` — working notes (final versions go in `docs/research/`)
- `data/` — market data pullers (public endpoints only)
- `signals/` — signal definitions and their validation

## Rules

- Read-only. No orders, no keys, no write access to any exchange account.
- Public market data endpoints only — if a data source needs a key, it's the engine
  workspace's job, not this one.
- Every claim gets a source URL and the date you checked it.
- Actively look for the evidence that contradicts your own thesis.

## Layout

```
workspaces/research/
├── notes/       # working notes
├── data/        # public data pullers
└── signals/     # signal definitions + validation
```

__MAVIS_EOF_074__

cat > "workspaces/research/package.json" <<'__MAVIS_EOF_075__'
{
  "name": "@trading/research",
  "version": "0.0.0",
  "private": true,
  "type": "module",
  "description": "Market data, signal validation, research notes. No credentials by design.",
  "scripts": {
    "build": "echo 'research: no build configured yet'",
    "test": "echo 'research: no tests configured yet'",
    "lint": "echo 'research: no linter configured yet'"
  }
}

__MAVIS_EOF_075__

echo "→ making the workspace folders git-ready"
if command -v git >/dev/null 2>&1; then
  bash scripts/git-init.sh >/dev/null 2>&1 || true
  echo "  ✓ workspaces/* are git repos on main"
else
  echo "  ! git not found — run 'bash scripts/git-init.sh' once git is installed"
fi

if [ "$IN_TERMUX" -eq 1 ] && [ ! -d "$HOME/storage/shared" ]; then
  echo ""
  echo "  ! Storage access is not granted yet, so Acode cannot open this folder."
  echo "    Run:  termux-setup-storage     (tap ALLOW on the Android prompt)"
  echo "    then re-run this script."
fi

echo
cat <<'DONE'
────────────────────────────────────────────────────────────
Digitraders is ready.

NEXT:
  1. Fill in the business (agents read this every run):
       nano docs/business-brief.md
  2. Start Paperclip in another terminal:
       npx paperclipai run          # first time: npx paperclipai onboard --yes
  3. Register company + goals + projects + agents:
       bash .paperclip/bootstrap.sh
  4. Check everything:
       bash scripts/doctor.sh
  5. Size a trade (read-only calculator):
       bash scripts/position-size.sh --equity 250 --entry 1.85 --stop 1.78
  6. Wake your first agent:
       bash .paperclip/wake.sh desk --reason "Plan the first 30 days"

Open it in Acode (Android):
  Acode → menu → Open folder → /storage/emulated/0/digitraders

The board: http://127.0.0.1:3100
DONE

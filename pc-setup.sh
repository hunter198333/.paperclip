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

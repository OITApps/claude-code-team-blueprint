#!/usr/bin/env bash
# setup.sh — First-time Claude Code setup for [Your Company] team members
# Usage: ./scripts/setup.sh
#
# Reads catalog.json for available plugins and MCP servers.
# Writes .env and settings.json to ~/.claude/; registers MCP servers via claude mcp add.

set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

# ── Step tracking (bash 3.2 compatible — space-delimited string) ─
STEP_RESULTS=""
STEP_PASS_COUNT=0
STEP_FAIL_COUNT=0
STEP_WARN_COUNT=0
STEP_TOTAL=0
CURRENT_STEP=""
_TMPFILES=""

step_ok() {
  STEP_RESULTS="${STEP_RESULTS:+$STEP_RESULTS
}PASS|$1"
  STEP_PASS_COUNT=$((STEP_PASS_COUNT + 1))
  STEP_TOTAL=$((STEP_TOTAL + 1))
  echo "  ✅  $1"
  CURRENT_STEP=""
}

step_fail() {
  STEP_RESULTS="${STEP_RESULTS:+$STEP_RESULTS
}FAIL|$1: $2"
  STEP_FAIL_COUNT=$((STEP_FAIL_COUNT + 1))
  STEP_TOTAL=$((STEP_TOTAL + 1))
  echo "  ❌  $1 — $2"
  CURRENT_STEP=""
}

step_warn() {
  STEP_RESULTS="${STEP_RESULTS:+$STEP_RESULTS
}WARN|$1: $2"
  STEP_WARN_COUNT=$((STEP_WARN_COUNT + 1))
  STEP_TOTAL=$((STEP_TOTAL + 1))
  echo "  ⚠️   $1 — $2"
  CURRENT_STEP=""
}

_step_start() {
  CURRENT_STEP="$1"
}

_step_end() {
  if [[ -n "$CURRENT_STEP" ]]; then
    step_ok "$CURRENT_STEP"
  fi
}

_register_tmpfile() {
  _TMPFILES="${_TMPFILES:+$_TMPFILES }$1"
}

_cleanup() {
  local _exit_code=$?
  for _tf in $_TMPFILES; do
    rm -f "$_tf" 2>/dev/null || true
  done
  echo ""
  echo "=== Setup Summary ==="
  if [[ -n "$STEP_RESULTS" ]]; then
    local _IFS_SAVE="$IFS"
    IFS='
'
    for _r in $STEP_RESULTS; do
      local _type="${_r%%|*}"
      local _msg="${_r#*|}"
      case "$_type" in
        PASS) printf "  ${GREEN}✅${NC}  %s\n" "$_msg" ;;
        FAIL) printf "  ${RED}❌${NC}  %s\n" "$_msg" ;;
        WARN) printf "  ${YELLOW}⚠️${NC}   %s\n" "$_msg" ;;
        *)    echo "  $_msg" ;;
      esac
    done
    IFS="$_IFS_SAVE"
  fi
  echo ""
  printf "  Setup complete: ${GREEN}%d passed${NC}, ${RED}%d failed${NC}, ${YELLOW}%d warnings${NC} (%d total)\n" \
    "$STEP_PASS_COUNT" "$STEP_FAIL_COUNT" "$STEP_WARN_COUNT" "$STEP_TOTAL"
  if [[ -n "$CURRENT_STEP" ]]; then
    printf "\n  ${RED}⚠️  Interrupted during: %s${NC}\n" "$CURRENT_STEP"
  fi
  if [[ $_exit_code -ne 0 ]] && [[ -n "$CURRENT_STEP" ]]; then
    printf "  ${RED}Setup did not complete successfully (exit code %d).${NC}\n" "$_exit_code"
  fi
  echo ""
}
trap _cleanup EXIT

# ── /dev/tty fallback ────────────────────────────────────────────
_read_input() {
  if [[ -t 0 ]]; then
    read "$@"
  elif read -t 0 </dev/tty 2>/dev/null; then
    read "$@" </dev/tty
  else
    echo "  (non-interactive — cannot prompt for input, using default)" >&2
    read "$@" <<< ""
  fi
}

# ── Banner ───────────────────────────────────────────────────────
ORANGE='\033[38;5;208m'; RESET='\033[0m'
printf "\n${ORANGE}  ┌──────────────────────────────────────────────────────┐\n"
printf "  │  Claude Code Team Commander · by [Admin Name]          │\n"
printf "  │  github.com/[your-github-org] · github.com/[your-github-username]              │\n"
printf "  │  Personas, tools & hooks active                      │\n"
printf "  └──────────────────────────────────────────────────────┘${RESET}\n\n"

# ── Pre-flight: dependency checks ───────────────────────────────
echo "=== [Your Company] Claude Code Setup — Pre-flight ==="
echo ""

PREFLIGHT_PASS=true

check_dep() {
  local cmd="$1" label="$2" install_hint="$3"
  if command -v "$cmd" &>/dev/null; then
    echo "  ✅  $label ($(command -v "$cmd"))"
  else
    echo "  ❌  $label — not found"
    echo "      Install: $install_hint"
    PREFLIGHT_PASS=false
  fi
}

if [[ "$(uname)" == "Darwin" ]]; then
  _pkg="brew install"
  _python_hint="xcode-select --install  OR  brew install python3"
  _gh_hint="brew install gh"
else
  _pkg="sudo apt install"
  _python_hint="sudo apt install python3"
  _gh_hint="sudo apt install gh  OR  see https://cli.github.com"
fi

check_dep "git"     "Git"            "$_pkg git"
check_dep "python3" "Python 3"       "$_python_hint  (v3.8+ required)"
check_dep "node"    "Node.js"        "$_pkg node  (v18+ required)"
check_dep "claude"  "Claude Code"    "$_pkg claude-code  OR  npm install -g @anthropic-ai/claude-code"
check_dep "sf"      "Salesforce CLI" "npm install -g @salesforce/cli"
check_dep "gh"      "GitHub CLI"     "$_gh_hint  (needed for worktrees + GitHub MCP auth)"

echo ""

if [[ "$PREFLIGHT_PASS" != "true" ]]; then
  echo "  Some dependencies are missing. Install them and re-run setup."
  echo "  Claude Code is required. Others can be installed later."
  echo ""
  _read_input -rp "  Continue anyway? [y/N] " _cont
  if [[ "$(echo "$_cont" | tr '[:upper:]' '[:lower:]')" != "y" ]]; then
    echo "  Aborted."
    exit 1
  fi
  echo ""
fi

# ── Pre-flight: OCC repo freshness ──────────────────────────────
OCC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OCC_REPO="https://github.com/[YourGitHubOrg]/claude-config.git"

if [[ -d "$OCC_DIR/.git" ]]; then
  echo "  Pulling latest OCC updates..."
  if git -C "$OCC_DIR" pull --quiet 2>/dev/null; then
    echo "  ✅  OCC is up to date."
  else
    echo "  ⚠️   Pull failed — OCC may have local changes or merge conflicts."
    echo "      This can happen if you edited files in ~/claude-config directly."
    echo ""
    _read_input -rp "  Delete ~/claude-config and re-clone? (local changes will be lost) [y/N] " _reclone
    if [[ "$(echo "$_reclone" | tr '[:upper:]' '[:lower:]')" == "y" ]]; then
      rm -rf "$OCC_DIR"
      git clone "$OCC_REPO" "$OCC_DIR"
      exec "$OCC_DIR/scripts/setup.sh"
    else
      echo "  Continuing with existing OCC (may be outdated)."
    fi
  fi
  echo ""
fi

# Check for team announcements
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SOURCE_DIR/check-announcements.sh" ]]; then
  bash "$SOURCE_DIR/check-announcements.sh"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CATALOG="$SCRIPT_DIR/catalog.json"
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
ENV_FILE="$CLAUDE_DIR/.env"

mkdir -p "$CLAUDE_DIR"

if [[ ! -f "$CATALOG" ]]; then
  echo "Error: catalog.json not found. Run: git -C $SCRIPT_DIR pull"
  exit 1
fi

echo "=== [Your Company] Claude Code Setup ==="
echo ""

# ── Role selection ────────────────────────────────────────────────
OCC_ROLE_FILE="$CLAUDE_DIR/.occ-role"
OCC_ROLE=""

if [[ -f "$OCC_ROLE_FILE" ]]; then
  OCC_ROLE="$(cat "$OCC_ROLE_FILE" | tr -d '[:space:]')"
  echo "  Current role: $OCC_ROLE"
  read -rp "  Change role? [y/N] " _change_role
  if [[ "$(echo "$_change_role" | tr '[:upper:]' '[:lower:]')" == "y" ]]; then
    OCC_ROLE=""
  fi
fi

if [[ -z "$OCC_ROLE" ]]; then
  echo "  Select your role:"
  echo "    1) user  — standard tools (email, docs, VoIP, GitHub, ClickUp)"
  echo "    2) admin — all tools including Salesforce DX, n8n, device management"
  echo ""
  read -rp "  Role [1/2]: " _role_choice
  case "$_role_choice" in
    2|admin)  OCC_ROLE="admin" ;;
    *)        OCC_ROLE="user" ;;
  esac
  echo "$OCC_ROLE" > "$OCC_ROLE_FILE"
  chmod 600 "$OCC_ROLE_FILE"
  echo "  Role set to: $OCC_ROLE"
fi
echo ""

# ── Step 1: Copy personas, commands, and standards ───────────────
echo "[1/9] Copying personas, commands, and standards..."
_step_start "Personas, commands, and standards copied"
if ! mkdir -p "$CLAUDE_DIR/commands" "$CLAUDE_DIR/personas" "$CLAUDE_DIR/standards" 2>/dev/null; then
  step_fail "Personas/commands/standards" "could not create directories under $CLAUDE_DIR"
elif cp -r "$SCRIPT_DIR/.claude/personas/"*.md "$CLAUDE_DIR/personas/" 2>/dev/null \
   && cp -r "$SCRIPT_DIR/.claude/commands/"*.md "$CLAUDE_DIR/commands/" 2>/dev/null; then
  if [[ -d "$SCRIPT_DIR/.claude/standards" ]]; then
    cp -r "$SCRIPT_DIR/.claude/standards/"*.md "$CLAUDE_DIR/standards/" 2>/dev/null
  fi
  step_ok "Personas, commands, and standards copied"
else
  step_warn "Personas/commands/standards" "some files may not have copied"
fi

# ── Step 2: Select MCP servers ──────────────────────────────────
echo ""
echo "[2/9] Select MCP servers to install"
_step_start "MCP server selection"
printf "  ${GREEN}[Configured]${NC} = keys found   ${YELLOW}[Recommended]${NC} = suggested for your role\n"
echo "  Toggle by number, 'r' recommended, 'a' all, 'n' none, or Enter to continue."

# Detect existing config: MCP registrations, .env keys, and scour for keys on disk
EXISTING_KEYS=()
while IFS= read -r _key; do
  EXISTING_KEYS+=("$_key")
done < <(python3 -c "
import json, os, glob

env_keys = {}

# 1. Keys already in ~/.claude/.env
for env_path in [os.path.expanduser('~/.claude/.env'), os.path.expanduser('~/.claude/.env.local')]:
    if os.path.exists(env_path):
        for line in open(env_path):
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                k, v = line.split('=', 1)
                v = v.strip().strip('\"')
                if v and v != 'REPLACE_ME':
                    env_keys[k.strip()] = v

# 2. Scour common locations for .env files with catalog-relevant keys
catalog_keys = set()
catalog_path = '$CATALOG'
try:
    c = json.load(open(catalog_path))
    for m in c.get('mcpServers', {}).values():
        for k in m.get('requiredKeys', []) + m.get('optionalKeys', []):
            catalog_keys.add(k)
        dt = m.get('derivedToken', '')
        if dt:
            catalog_keys.add(dt)
except Exception:
    pass

home = os.path.expanduser('~')
scour_dirs = [
    os.path.join(home, 'Developer'),
    os.path.join(home, 'Projects'),
    os.path.join(home, 'Github Projects'),
]
skip_dirs = {'node_modules', '.git', '__pycache__', 'venv', '.venv'}
max_depth = 4
for base in scour_dirs:
    if not os.path.isdir(base):
        continue
    base_depth = base.count(os.sep)
    for root, dirs, files in os.walk(base):
        if root.count(os.sep) - base_depth >= max_depth:
            dirs.clear()
            continue
        dirs[:] = [d for d in dirs if d not in skip_dirs]
        if '.env' in files:
            env_file = os.path.join(root, '.env')
            try:
                for line in open(env_file):
                    line = line.strip()
                    if line and not line.startswith('#') and '=' in line:
                        k, v = line.split('=', 1)
                        k, v = k.strip(), v.strip().strip('\"')
                        if k in catalog_keys and v and v != 'REPLACE_ME' and not v.startswith('your_') and k not in env_keys:
                            env_keys[k] = v
        except Exception:
            pass

for k in sorted(env_keys):
    print(k)
" 2>/dev/null)

# Build MCP arrays from catalog — mark as installed if all required keys exist in .env
MCP_IDS=(); MCP_NAMES=(); MCP_RECS=(); MCP_INSTALLED=(); MCP_REMOTES=()
while IFS='|' read -r _rec _installed _mid _name _desc _keys _remote; do
  MCP_IDS+=("$_mid")
  MCP_NAMES+=("$_name — $_desc${_keys:+ [keys: $_keys]}")
  MCP_RECS+=("$_rec")
  MCP_INSTALLED+=("$_installed")
  MCP_REMOTES+=("$_remote")
done < <(python3 -c "
import json, os

catalog = json.load(open('$CATALOG'))
user_role = '$OCC_ROLE'

# Load existing keys (same set we just detected)
env_keys = set()
for env_path in [os.path.expanduser('~/.claude/.env'), os.path.expanduser('~/.claude/.env.local')]:
    if os.path.exists(env_path):
        for line in open(env_path):
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                k, v = line.split('=', 1)
                v = v.strip().strip('\"')
                if v and v != 'REPLACE_ME':
                    env_keys.add(k.strip())

# Also check ~/.claude.json for registered servers
registered = set()
p = os.path.expanduser('~/.claude.json')
if os.path.exists(p):
    try:
        d = json.load(open(p))
        # Check top-level and project-level mcpServers
        for k in d.get('mcpServers', {}):
            registered.add(k)
        for proj in d.get('projects', {}).values():
            if isinstance(proj, dict):
                for k in proj.get('mcpServers', {}):
                    registered.add(k)
    except Exception:
        pass

for mid, m in sorted(catalog['mcpServers'].items(), key=lambda x: (not x[1]['recommended'], x[1]['name'])):
    # Filter by role: if roles is defined, user must match; if absent, available to all
    allowed_roles = m.get('roles', ['user', 'admin'])
    if user_role not in allowed_roles:
        continue

    rec = '*' if m['recommended'] else ' '
    keys_list = ', '.join(m.get('requiredKeys', []))

    # Installed if: registered in claude.json, OR all required keys have values,
    # OR the derived token has a value
    required = m.get('requiredKeys', [])
    derived = m.get('derivedToken', '')
    installed = '0'
    if mid in registered:
        installed = '1'
    elif derived and derived in env_keys:
        installed = '1'
    elif required and all(k in env_keys for k in required):
        installed = '1'
    # Servers with no required keys: check if they have optional keys set
    elif not required:
        optional = m.get('optionalKeys', [])
        if optional and any(k in env_keys for k in optional):
            installed = '1'

    remote = m.get('remoteAvailable', '')
    print(f'{rec}|{installed}|{mid}|{m[\"name\"]}|{m[\"description\"]}|{keys_list}|{remote}')
")

# Print migration summary if any installed servers detected
_installed_count=0
for _v in "${MCP_INSTALLED[@]+"${MCP_INSTALLED[@]}"}"; do [[ "$_v" == "1" ]] && _installed_count=$(( _installed_count + 1 )) || true; done
if (( _installed_count > 0 )); then
  echo ""
  echo "  Found $_installed_count existing MCP server(s) — they'll be migrated to the latest config."
fi

# Pre-select: already registered servers first, then new recommended ones
SELECTED_MCPS=()
for _i in "${!MCP_IDS[@]}"; do
  if [[ "${MCP_INSTALLED[$_i]}" == "1" ]]; then
    SELECTED_MCPS+=("${MCP_IDS[$_i]}")
  fi
done
for _i in "${!MCP_IDS[@]}"; do
  if [[ "${MCP_RECS[$_i]}" == "*" ]]; then
    _already=0
    for _s in "${SELECTED_MCPS[@]+"${SELECTED_MCPS[@]}"}"; do [[ "$_s" == "${MCP_IDS[$_i]}" ]] && _already=1 && break; done
    [[ $_already -eq 0 ]] && SELECTED_MCPS+=("${MCP_IDS[$_i]}")
  fi
done

while true; do
  echo ""
  for _i in "${!MCP_IDS[@]}"; do
    _id="${MCP_IDS[$_i]}"
    _in_sel=0
    for _s in "${SELECTED_MCPS[@]+"${SELECTED_MCPS[@]}"}"; do [[ "$_s" == "$_id" ]] && _in_sel=1 && break; done
    _mark="[ ]"; [[ $_in_sel -eq 1 ]] && _mark="[x]"
    _remote_tag=""
    [[ -n "${MCP_REMOTES[$_i]}" ]] && _remote_tag=" ${CYAN}[available via ${MCP_REMOTES[$_i]}]${NC}"
    if [[ "${MCP_INSTALLED[$_i]}" == "1" ]]; then
      printf "  %s %2d) ${GREEN}[Configured]${NC} %s%b\n" "$_mark" "$((_i+1))" "${MCP_NAMES[$_i]}" "$_remote_tag"
    elif [[ "${MCP_RECS[$_i]}" == "*" ]]; then
      printf "  %s %2d) ${YELLOW}[Recommended]${NC} %s%b\n" "$_mark" "$((_i+1))" "${MCP_NAMES[$_i]}" "$_remote_tag"
    else
      printf "  %s %2d) %s%b\n" "$_mark" "$((_i+1))" "${MCP_NAMES[$_i]}" "$_remote_tag"
    fi
  done
  echo ""
  printf "  Toggle (numbers), r=recommended, a=all, n=none, Enter=done: "
  _read_input -r _sel || _sel=""
  [[ -z "$_sel" ]] && break
  case "$_sel" in
    r|R)
      SELECTED_MCPS=()
      for _i in "${!MCP_IDS[@]}"; do [[ "${MCP_RECS[$_i]}" == "*" ]] && SELECTED_MCPS+=("${MCP_IDS[$_i]}"); done
      ;;
    a|A) SELECTED_MCPS=("${MCP_IDS[@]}") ;;
    n|N) SELECTED_MCPS=() ;;
    *)
      for _num in $_sel; do
        if [[ "$_num" =~ ^[0-9]+$ ]] && (( _num >= 1 && _num <= ${#MCP_IDS[@]} )); then
          _id="${MCP_IDS[$(( _num-1 ))]}"
          _found=0; _new=()
          for _s in "${SELECTED_MCPS[@]+"${SELECTED_MCPS[@]}"}"; do
            [[ "$_s" == "$_id" ]] && _found=1 || _new+=("$_s")
          done
          if (( _found )); then
            SELECTED_MCPS=("${_new[@]+"${_new[@]}"}")
          else
            SELECTED_MCPS+=("$_id")
          fi
        fi
      done
      ;;
  esac
done
step_ok "MCP server selection"

# ── Step 3: Select plugins ───────────────────────────────────────
echo ""
echo "[3/9] Select plugins to enable"
_step_start "Plugin selection"
printf "  ${GREEN}[Installed]${NC} = currently active   ${YELLOW}[Recommended]${NC} = suggested   [Always On] = required\n"
echo "  Toggle by number, or Enter to continue."

# Detect already-enabled plugins from settings.json
EXISTING_PLUGINS=()
while IFS= read -r _pid; do
  EXISTING_PLUGINS+=("$_pid")
done < <(python3 -c "
import json, os
p = os.path.expanduser('~/.claude/settings.json')
if os.path.exists(p):
    s = json.load(open(p))
    for pid, enabled in s.get('enabledPlugins', {}).items():
        if enabled:
            print(pid)
" 2>/dev/null)

# Build plugin arrays from catalog
PLUGIN_IDS=(); PLUGIN_NAMES=(); PLUGIN_RECS=(); PLUGIN_LOCKED=(); PLUGIN_INSTALLED=()
while IFS='|' read -r _rec _locked _pid _name _desc _cat; do
  PLUGIN_IDS+=("$_pid")
  PLUGIN_NAMES+=("$_name — $_desc")
  PLUGIN_RECS+=("$_rec")
  PLUGIN_LOCKED+=("$_locked")
  _is_installed=0
  for _e in "${EXISTING_PLUGINS[@]+"${EXISTING_PLUGINS[@]}"}"; do [[ "$_e" == "$_pid" ]] && _is_installed=1 && break; done
  PLUGIN_INSTALLED+=("$_is_installed")
done < <(python3 -c "
import json
c = json.load(open('$CATALOG'))
user_role = '$OCC_ROLE'
for pid, p in sorted(c['plugins'].items(), key=lambda x: (not x[1]['recommended'], x[1]['name'])):
    allowed_roles = p.get('roles', ['user', 'admin'])
    if user_role not in allowed_roles:
        continue
    rec = '*' if p['recommended'] else ' '
    locked = '1' if p.get('alwaysEnabled') else '0'
    print(f'{rec}|{locked}|{pid}|{p[\"name\"]}|{p[\"description\"]}|{p[\"category\"]}')
")

# Print migration summary if any installed plugins detected
_installed_p_count=0
for _v in "${PLUGIN_INSTALLED[@]+"${PLUGIN_INSTALLED[@]}"}"; do [[ "$_v" == "1" ]] && _installed_p_count=$(( _installed_p_count + 1 )) || true; done
if (( _installed_p_count > 0 )); then
  echo ""
  echo "  Found $_installed_p_count existing plugin(s) — they'll be preserved."
fi

# Pre-select: already-enabled plugins, then recommended + always-enabled
SELECTED_PLUGINS=()
if (( _installed_p_count > 0 )); then
  for _i in "${!PLUGIN_IDS[@]}"; do
    if [[ "${PLUGIN_INSTALLED[$_i]}" == "1" ]] || [[ "${PLUGIN_LOCKED[$_i]}" == "1" ]]; then
      SELECTED_PLUGINS+=("${PLUGIN_IDS[$_i]}")
    fi
  done
else
  # First run — default to recommended + always-enabled
  for _i in "${!PLUGIN_IDS[@]}"; do
    [[ "${PLUGIN_RECS[$_i]}" == "*" || "${PLUGIN_LOCKED[$_i]}" == "1" ]] && SELECTED_PLUGINS+=("${PLUGIN_IDS[$_i]}")
  done
fi

while true; do
  echo ""
  for _i in "${!PLUGIN_IDS[@]}"; do
    _id="${PLUGIN_IDS[$_i]}"
    _in_sel=0
    for _s in "${SELECTED_PLUGINS[@]+"${SELECTED_PLUGINS[@]}"}"; do [[ "$_s" == "$_id" ]] && _in_sel=1 && break; done
    _mark="[ ]"; [[ $_in_sel -eq 1 ]] && _mark="[x]"
    if [[ "${PLUGIN_LOCKED[$_i]}" == "1" ]]; then
      printf "  %s %2d) ${GREEN}[Always On]${NC} %s\n" "$_mark" "$((_i+1))" "${PLUGIN_NAMES[$_i]}"
    elif [[ "${PLUGIN_INSTALLED[$_i]}" == "1" ]]; then
      printf "  %s %2d) ${GREEN}[Installed]${NC} %s\n" "$_mark" "$((_i+1))" "${PLUGIN_NAMES[$_i]}"
    elif [[ "${PLUGIN_RECS[$_i]}" == "*" ]]; then
      printf "  %s %2d) ${YELLOW}[Recommended]${NC} %s\n" "$_mark" "$((_i+1))" "${PLUGIN_NAMES[$_i]}"
    else
      printf "  %s %2d) %s\n" "$_mark" "$((_i+1))" "${PLUGIN_NAMES[$_i]}"
    fi
  done
  echo ""
  printf "  Toggle (numbers), r=recommended, a=all, n=none, Enter=done: "
  _read_input -r _sel || _sel=""
  [[ -z "$_sel" ]] && break
  case "$_sel" in
    r|R)
      SELECTED_PLUGINS=()
      for _i in "${!PLUGIN_IDS[@]}"; do
        [[ "${PLUGIN_RECS[$_i]}" == "*" || "${PLUGIN_LOCKED[$_i]}" == "1" ]] && SELECTED_PLUGINS+=("${PLUGIN_IDS[$_i]}")
      done
      ;;
    a|A) SELECTED_PLUGINS=("${PLUGIN_IDS[@]}") ;;
    n|N)
      SELECTED_PLUGINS=()
      for _i in "${!PLUGIN_IDS[@]}"; do
        [[ "${PLUGIN_LOCKED[$_i]}" == "1" ]] && SELECTED_PLUGINS+=("${PLUGIN_IDS[$_i]}")
      done
      ;;
    *)
      for _num in $_sel; do
        if [[ "$_num" =~ ^[0-9]+$ ]] && (( _num >= 1 && _num <= ${#PLUGIN_IDS[@]} )); then
          _idx=$(( _num-1 ))
          _id="${PLUGIN_IDS[$_idx]}"
          if [[ "${PLUGIN_LOCKED[$_idx]}" == "1" ]]; then
            echo "  (${PLUGIN_IDS[$_idx]} is always enabled)"
            continue
          fi
          _found=0; _new=()
          for _s in "${SELECTED_PLUGINS[@]+"${SELECTED_PLUGINS[@]}"}"; do
            [[ "$_s" == "$_id" ]] && _found=1 || _new+=("$_s")
          done
          if (( _found )); then
            SELECTED_PLUGINS=("${_new[@]+"${_new[@]}"}")
          else
            SELECTED_PLUGINS+=("$_id")
          fi
        fi
      done
      ;;
  esac
done
step_ok "Plugin selection"

# ── Step 4: Collect API keys for selected MCP servers ───────────
echo ""
echo "[4/9] MCP Server API Keys"
_step_start "API key collection"
echo "  Only prompting for missing keys. Press Enter to skip any you don't have yet."
echo ""

# Source existing .env if present
if [[ -f "$ENV_FILE" ]]; then
  echo "  Loading existing .env values..."
  set -a; source "$ENV_FILE" 2>/dev/null; set +a
fi

# Scour for keys in other .env files and merge into ~/.claude/.env
set +e
python3 - "$CATALOG" "$ENV_FILE" <<'PYEOF'
import json, os, glob, sys

catalog = json.load(open(sys.argv[1]))
env_file = sys.argv[2]

# All keys the catalog cares about
catalog_keys = set()
for m in catalog.get('mcpServers', {}).values():
    for k in m.get('requiredKeys', []) + m.get('optionalKeys', []):
        catalog_keys.add(k)
    dt = m.get('derivedToken', '')
    if dt:
        catalog_keys.add(dt)

# Load current .env
env = {}
if os.path.exists(env_file):
    for line in open(env_file):
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            k, v = line.split('=', 1)
            env[k.strip()] = v.strip().strip('"')

# Scour project directories for .env files (depth-limited, skips heavy dirs)
home = os.path.expanduser('~')
scour_dirs = [
    os.path.join(home, 'Developer'),
    os.path.join(home, 'Projects'),
    os.path.join(home, 'Github Projects'),
]
skip_dirs = {'node_modules', '.git', '__pycache__', 'venv', '.venv'}
max_depth = 4
discovered = {}
for base in scour_dirs:
    if not os.path.isdir(base):
        continue
    base_depth = base.count(os.sep)
    for root, dirs, files in os.walk(base):
        if root.count(os.sep) - base_depth >= max_depth:
            dirs.clear()
            continue
        dirs[:] = [d for d in dirs if d not in skip_dirs]
        if '.env' in files:
            env_path = os.path.join(root, '.env')
            try:
                for line in open(env_path):
                    line = line.strip()
                    if line and not line.startswith('#') and '=' in line:
                        k, v = line.split('=', 1)
                        k, v = k.strip(), v.strip().strip('"')
                        if (k in catalog_keys
                            and v and v != 'REPLACE_ME'
                            and not v.startswith('your_')
                            and not v.startswith('sk-your')
                            and k not in env
                            and k not in discovered):
                            discovered[k] = (v, env_path)
            except Exception:
                pass

if not discovered:
    sys.exit(0)

print(f"  Discovered {len(discovered)} key(s) from other .env files on this machine:")
for k, (v, path) in sorted(discovered.items()):
    short_path = path.replace(home, '~')
    masked = v[:6] + '...' if len(v) > 8 else v
    print(f"    {k} = {masked}  (from {short_path})")

# Merge into .env
for k, (v, _) in discovered.items():
    env[k] = v

try:
    with open(env_file, 'w') as f:
        f.write("# [Your Company] MCP Server Configuration\n")
        f.write(f"# Updated by setup.sh on {__import__('datetime').date.today()}\n")
        f.write("# NEVER commit this file.\n\n")
        for k, v in sorted(env.items()):
            f.write(f'{k}="{v}"\n')
    os.chmod(env_file, 0o600)
    print(f"\n  Merged into {env_file}")
except Exception as e:
    print(f"  Warning: could not write {env_file}: {e}", file=sys.stderr)
PYEOF
_scour_rc=$?
set -e
if [[ $_scour_rc -ne 0 ]]; then
  echo "  Warning: key scour encountered an error (non-fatal)"
fi

# Re-source after scour merge
if [[ -f "$ENV_FILE" ]]; then
  set -a; source "$ENV_FILE" 2>/dev/null; set +a
fi

# Show summary of all existing keys
_existing_key_count=${#EXISTING_KEYS[@]}
if (( _existing_key_count > 0 )); then
  echo ""
  echo "  Total keys configured: $_existing_key_count"
  echo "  Keys with values: ${EXISTING_KEYS[*]}"
  echo ""
fi

# Auto-detect SF_TARGET_ORG from sf CLI if not already set
if [[ -z "${SF_TARGET_ORG:-}" ]] && command -v sf &>/dev/null; then
  _sf_org=$(sf org list --json 2>/dev/null | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    orgs=d.get('result',{}).get('nonScratchOrgs',[])
    default=next((o['username'] for o in orgs if o.get('isDefaultUsername')),None)
    if default: print(default)
except: pass
" 2>/dev/null || true)
  if [[ -n "${_sf_org:-}" ]]; then
    echo "  Auto-detected SF_TARGET_ORG: $_sf_org"
    echo "SF_TARGET_ORG=\"$_sf_org\"" >> "$ENV_FILE"
    set -a; source "$ENV_FILE" 2>/dev/null; set +a
  fi
fi

# Write Python to a temp file so stdin stays connected to the terminal
# (heredoc-based python3 - <<'EOF' consumes stdin, breaking /dev/tty prompts)
_step4_py=$(mktemp /tmp/occ_step4_XXXXX)
_register_tmpfile "$_step4_py"
cat > "$_step4_py" << 'PYEOF'
import json, sys, os, getpass

catalog = json.load(open(sys.argv[1]))
env_file = sys.argv[2]
selected = set(sys.argv[3:])

# Load existing env (file first, then shell env as fallback)
env = {}
if os.path.exists(env_file):
    with open(env_file) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                k, v = line.split('=', 1)
                env[k.strip()] = v.strip().strip('"')
# Also pick up catalog-relevant env vars from shell (e.g. sourced .env from previous steps)
catalog_env_keys = set()
for m in catalog.get('mcpServers', {}).values():
    for k in m.get('requiredKeys', []) + m.get('optionalKeys', []):
        catalog_env_keys.add(k)
    dt = m.get('derivedToken', '')
    if dt:
        catalog_env_keys.add(dt)
for k, v in os.environ.items():
    if k in catalog_env_keys and k not in env and v.strip():
        env[k] = v

if not selected:
    print("  No MCP servers selected — skipping key collection.")
else:
    # Collect keys for selected servers
    for mid, m in sorted(catalog['mcpServers'].items()):
        if mid not in selected:
            continue

        all_keys = m.get('requiredKeys', []) + m.get('optionalKeys', [])
        if not all_keys:
            continue

        # If this server has a derived token already set, skip credential prompts
        derived_token = m.get('derivedToken', '')
        if derived_token and env.get(derived_token, '').strip() not in ('', 'REPLACE_ME'):
            continue

        # Check which required keys are missing
        required_keys = [k for k in m.get('requiredKeys', [])
                         if env.get(k, '') in ('', 'REPLACE_ME')]
        if not required_keys:
            continue

        # Only show server header + instructions when keys are needed
        print(f"\n  -- {m['name']} --")
        instructions = m.get('setupInstructions', [])
        if instructions:
            print(f"  Setup:")
            for step in instructions:
                print(f"    • {step}")
            print()
        descriptions = m.get('keyDescriptions', {})

        for key in required_keys:
            desc = descriptions.get(key, '')
            if desc:
                print(f"  {key} (required) — {desc}")
            else:
                print(f"  {key} (required)")

            try:
                val = getpass.getpass("    Value: ").strip()
            except Exception:
                val = ''
                print("  (could not read input — skipping)")
            if val:
                env[key] = val

# Always write env file (preserves existing keys)
try:
    with open(env_file, 'w') as f:
        f.write("# [Your Company] MCP Server Configuration\n")
        f.write(f"# Generated by setup.sh on {__import__('datetime').date.today()}\n")
        f.write("# NEVER commit this file.\n\n")
        for k, v in sorted(env.items()):
            f.write(f'{k}="{v}"\n')
    os.chmod(env_file, 0o600)
    print(f"\n  Written to {env_file}")
except OSError as e:
    print(f"\n  ERROR: Could not write {env_file}: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

set +e
python3 "$_step4_py" "$CATALOG" "$ENV_FILE" "${SELECTED_MCPS[@]+"${SELECTED_MCPS[@]}"}"
_step4_rc=$?
set -e
rm -f "$_step4_py"
if [[ $_step4_rc -ne 0 ]]; then
  step_fail "API key collection" "Python exited with code $_step4_rc"
  exit 1
else
  step_ok "API keys collected"
fi

# Re-source env after collecting keys
set -a; source "$ENV_FILE" 2>/dev/null; set +a

# ── ClickUp OAuth flow (runs if CLIENT_ID/SECRET collected above) ─
_clickup_oauth=false
for _m in "${SELECTED_MCPS[@]+"${SELECTED_MCPS[@]}"}"; do
  [[ "$_m" == "clickup" ]] && _clickup_oauth=true && break
done

if [[ "$_clickup_oauth" == "true" ]] \
    && [[ -n "${CLICKUP_CLIENT_ID:-}" ]] \
    && [[ -n "${CLICKUP_CLIENT_SECRET:-}" ]] \
    && [[ -z "${CLICKUP_API_KEY:-}" ]]; then
  echo ""
  echo "  -- ClickUp OAuth --"
  echo "  Opening browser — authorize '[Your Company] Claude Integration' in ClickUp..."
  _cu_url="https://app.clickup.com/api?client_id=${CLICKUP_CLIENT_ID}&redirect_uri=http://localhost:3456"
  if [[ "$(uname)" == "Darwin" ]]; then
    open "$_cu_url"
  else
    xdg-open "$_cu_url" 2>/dev/null || printf "  Please open in your browser:\n  %s\n" "$_cu_url"
  fi
  echo "  Waiting for callback on localhost:3456 (approve in your browser)..."

  # Write OAuth callback server to a temp file — avoids heredoc nesting issues
  _cu_py=$(mktemp /tmp/cu_oauth_XXXXX)
  _register_tmpfile "$_cu_py"
  cat > "$_cu_py" << 'CUEOF'
import http.server, urllib.parse
code = [None]

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        p = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        code[0] = p.get('code', [None])[0]
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.end_headers()
        self.wfile.write(b'<html><body style="font-family:sans-serif;padding:40px">'
                         b'<h2>Authorized!</h2><p>Return to your terminal.</p></body></html>')
    def log_message(self, *a):
        pass

http.server.HTTPServer(('localhost', 3456), H).handle_request()
if code[0]:
    print(code[0])
CUEOF
  _cu_code=$(python3 "$_cu_py" 2>/dev/null)
  rm -f "$_cu_py"

  if [[ -n "$_cu_code" ]]; then
    echo "  Got authorization code. Exchanging for access token..."
    _cu_resp=$(curl -s -X POST "https://api.clickup.com/api/v2/oauth/token" \
      -H "Content-Type: application/json" \
      -d "{\"client_id\":\"${CLICKUP_CLIENT_ID}\",\"client_secret\":\"${CLICKUP_CLIENT_SECRET}\",\"code\":\"${_cu_code}\"}")
    _cu_token=$(echo "$_cu_resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('access_token',''))" 2>/dev/null || true)

    if [[ -n "${_cu_token:-}" ]]; then
      echo "  ✓ ClickUp OAuth complete — token saved"
      # Append CLICKUP_API_KEY to .env preserving existing keys
      python3 - "$ENV_FILE" "$_cu_token" << 'CUENVEOF'
import sys, os
env_file, token = sys.argv[1], sys.argv[2]
env = {}
if os.path.exists(env_file):
    for line in open(env_file):
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            k, v = line.split('=', 1)
            env[k.strip()] = v.strip().strip('"')
env['CLICKUP_API_KEY'] = token
with open(env_file, 'w') as fh:
    fh.write("# [Your Company] MCP Server Configuration\n# NEVER commit this file.\n\n")
    for k, v in sorted(env.items()):
        fh.write(f'{k}="{v}"\n')
os.chmod(env_file, 0o600)
CUENVEOF
      set -a; source "$ENV_FILE" 2>/dev/null; set +a
    else
      printf "  ✗ Token exchange failed. Response: %s\n" "$_cu_resp"
      echo "    Add CLICKUP_API_KEY to .env manually, or email [admin-email@your-domain.com]."
    fi
  else
    echo "  ✗ No authorization code received from browser."
    echo "    Re-run setup, or add CLICKUP_API_KEY to .env manually."
  fi
elif [[ "$_clickup_oauth" == "true" ]] && [[ -n "${CLICKUP_API_KEY:-}" ]]; then
  echo "  CLICKUP_API_KEY already set — skipping OAuth flow."
fi

# ── Shared secret distribution (deferred — see issue #243) ──────
# fetch-shared-secrets.sh is ready but occ-secrets repo infrastructure
# has not been built yet. Skipping silently until #243 is resolved.

# ── MCP Health Check (parallel) ─────────────────────────────────
# Re-source env to pick up any keys just collected
set -a; source "$ENV_FILE" 2>/dev/null; set +a

echo ""
echo "  Checking MCPs..."
echo ""

set +e
python3 - "$CATALOG" "$ENV_FILE" "${SELECTED_MCPS[@]+"${SELECTED_MCPS[@]}"}" <<'HEALTHEOF'
import json, sys, os, subprocess, concurrent.futures

catalog = json.load(open(sys.argv[1]))
env_file = sys.argv[2]
selected = set(sys.argv[3:])

# Load env
env = dict(os.environ)
if os.path.exists(env_file):
    with open(env_file) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                k, v = line.split('=', 1)
                env[k.strip()] = v.strip().strip('"')

def check_server(mid, m):
    """Returns (mid, name, auth_type, status) where status is green/yellow/red."""
    name = m['name']
    auth_type = m.get('authType', 'key')
    health_cmd = m.get('healthCheck', '')
    required = m.get('requiredKeys', [])
    optional = m.get('optionalKeys', [])
    derived = m.get('derivedToken', '')

    # Determine if keys/auth are present
    has_keys = False
    if derived and env.get(derived, '').strip() not in ('', 'REPLACE_ME'):
        has_keys = True
    elif required:
        has_keys = all(env.get(k, '').strip() not in ('', 'REPLACE_ME') for k in required)
    elif auth_type == 'oauth':
        # OAuth with no required keys — check health to determine
        has_keys = True
    elif auth_type == 'local':
        has_keys = True
    elif optional and any(env.get(k, '').strip() not in ('', 'REPLACE_ME') for k in optional):
        has_keys = True

    if not has_keys:
        return (mid, name, auth_type, 'yellow', '')

    # Run health check if available
    if health_cmd:
        try:
            # Expand env vars in command
            expanded = health_cmd
            for k, v in env.items():
                expanded = expanded.replace(f'${k}', v)
            result = subprocess.run(
                ['bash', '-c', expanded],
                capture_output=True, timeout=10, env=env
            )
            if result.returncode == 0:
                return (mid, name, auth_type, 'green', '')
            else:
                if auth_type in ('oauth', 'local') and not required:
                    return (mid, name, auth_type, 'yellow', '')
                return (mid, name, auth_type, 'red', 'API not responding')
        except subprocess.TimeoutExpired:
            if auth_type in ('oauth', 'local') and not required:
                return (mid, name, auth_type, 'yellow', '')
            return (mid, name, auth_type, 'red', 'health check timed out')
        except Exception as e:
            if auth_type in ('oauth', 'local') and not required:
                return (mid, name, auth_type, 'yellow', '')
            return (mid, name, auth_type, 'red', str(e))
    else:
        return (mid, name, auth_type, 'green', '')

# Run checks in parallel
servers_to_check = []
for mid, m in sorted(catalog['mcpServers'].items(), key=lambda x: x[1]['name']):
    if mid not in selected:
        continue
    servers_to_check.append((mid, m))

results = []
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
    futures = {executor.submit(check_server, mid, m): mid for mid, m in servers_to_check}
    for f in concurrent.futures.as_completed(futures):
        results.append(f.result())

# Sort by name
results.sort(key=lambda r: r[1])

# Split into groups
key_servers = [r for r in results if r[2] == 'key']
oauth_servers = [r for r in results if r[2] in ('oauth', 'local')]

emoji = {'green': '\U0001f7e2', 'yellow': '\U0001f7e1', 'red': '\U0001f534'}

print(f"  {emoji['green']} configured & responding  {emoji['yellow']} needs setup  {emoji['red']} configured but failing")
print()

red_details = []

if key_servers:
    print("  API Key Servers:")
    for mid, name, auth_type, status, detail in key_servers:
        print(f"  {emoji[status]} {name}")
        if status == 'red' and detail:
            red_details.append((name, detail))
    print()

if oauth_servers:
    print("  OAuth / Runtime Servers:")
    for mid, name, auth_type, status, detail in oauth_servers:
        print(f"  {emoji[status]} {name}")
        if status == 'red' and detail:
            red_details.append((name, detail))
    print()

if red_details:
    for name, detail in red_details:
        print(f"  {emoji['red']} {name} — {detail}")
    print()

has_red = any(s == 'red' for _, _, _, s, _ in results)
has_yellow = any(s == 'yellow' for _, _, _, s, _ in results)
if has_red:
    sys.exit(2)
elif has_yellow:
    sys.exit(1)
else:
    sys.exit(0)
HEALTHEOF
_health_rc=$?
set -e

if [[ $_health_rc -eq 2 ]]; then
  step_fail "MCP health check" "one or more servers failing"
elif [[ $_health_rc -eq 1 ]]; then
  step_warn "MCP health check" "some servers need setup"
else
  step_ok "MCP health check"
fi

# ── Step 5: Register MCP servers via claude mcp add ─────────────
echo ""
echo "[5/9] Registering MCP servers..."
_step_start "MCP servers registered"

set +e
python3 - "$CATALOG" "${SELECTED_MCPS[@]+"${SELECTED_MCPS[@]}"}" <<'PYEOF'
import json, sys, subprocess

catalog = json.load(open(sys.argv[1]))
selected = set(sys.argv[2:])

if not selected:
    print("  No MCP servers selected — skipping.")
    sys.exit(0)

configured = []
failed = []

for mid, m in catalog['mcpServers'].items():
    if mid not in selected:
        continue

    # Remove existing entry (idempotent re-runs)
    subprocess.run(
        ["claude", "mcp", "remove", mid, "-s", "user"],
        capture_output=True
    )

    # Non-secret static env → passed as -e flags (stored in ~/.claude.json, not secret)
    env_flags = []
    for key, val in m.get("env", {}).items():
        env_flags += ["-e", f"{key}={val}"]

    # Secrets stay in ~/.claude/.env — loaded at runtime by the bash wrapper
    cmd = [
        "claude", "mcp", "add", mid,
        "-s", "user",
        *env_flags,
        "--",
        m["command"],
        *m["args"]
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode == 0:
        configured.append(m["name"])
    else:
        failed.append(f"{m['name']}: {result.stderr.strip()}")

if configured:
    print(f"  Registered {len(configured)} MCP servers: {', '.join(configured)}")
for msg in failed:
    print(f"  ERROR: {msg}")
if not configured and not failed:
    print("  No MCP servers configured.")
print("  Registered globally via 'claude mcp add -s user' → ~/.claude.json")
if failed:
    sys.exit(1)
PYEOF
_step5_rc=$?
set -e

if [[ $_step5_rc -eq 0 ]]; then
  step_ok "MCP servers registered"
else
  step_warn "MCP registration" "some servers failed (see above)"
fi

# ── Step 6: Update global settings.json ─────────────────────────
echo ""
echo "[6/9] Updating ~/.claude/settings.json..."
_step_start "Settings updated"

if [[ ! -f "$SETTINGS" ]]; then
  if ! echo '{}' > "$SETTINGS" 2>/dev/null; then
    step_fail "Settings update" "could not create $SETTINGS"
  fi
fi

set +e
python3 - "$CATALOG" "$SETTINGS" "${SELECTED_PLUGINS[@]+"${SELECTED_PLUGINS[@]}"}" "${SELECTED_MCPS[@]+"${SELECTED_MCPS[@]}"}" <<'PYEOF'
import json, sys

catalog = json.load(open(sys.argv[1]))
settings_file = sys.argv[2]

all_plugin_ids = set(catalog['plugins'].keys())
all_mcp_ids = set(catalog['mcpServers'].keys())

selected_plugins = []
selected_mcps = []
for arg in sys.argv[3:]:
    if arg in all_plugin_ids:
        selected_plugins.append(arg)
    elif arg in all_mcp_ids:
        selected_mcps.append(arg)

try:
    settings = json.load(open(settings_file))
except (FileNotFoundError, json.JSONDecodeError):
    settings = {}

# Update plugins — set all known, enable only selected
plugins = settings.get("enabledPlugins", {})
for pid in catalog['plugins']:
    plugins[pid] = pid in selected_plugins
settings["enabledPlugins"] = plugins

# Update MCP servers
settings['enabledMcpjsonServers'] = selected_mcps

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')

print(f"  Plugins enabled: {len(selected_plugins)}")
print(f"  MCP servers enabled: {len(selected_mcps)}")
PYEOF
_step6_rc=$?
set -e

if [[ $_step6_rc -eq 0 ]]; then
  step_ok "Settings updated"
else
  step_fail "Settings update" "could not write settings.json"
fi

# ── Step 7: Install catalog announcement hook ───────────────────
echo ""
echo "[7/9] Installing catalog announcement hook..."
_step_start "Session hook installed"

HOOK_SRC="$SCRIPT_DIR/hooks/your-session-start.sh"
HOOK_DEST="$CLAUDE_DIR/hooks/your-session-start.sh"

if [[ -f "$HOOK_SRC" ]]; then
  if ! mkdir -p "$CLAUDE_DIR/hooks" 2>/dev/null; then
    step_fail "Session hook" "could not create hooks directory"
  elif ! cp "$HOOK_SRC" "$HOOK_DEST" 2>/dev/null; then
    step_fail "Session hook" "could not copy hook to $HOOK_DEST"
  else
    chmod +x "$HOOK_DEST"

    # Register in global settings.json
    set +e
    python3 - "$SETTINGS" "$HOOK_DEST" <<'PYEOF'
import json, sys, os

settings_file, hook_path = sys.argv[1], sys.argv[2]

try:
    settings = json.load(open(settings_file)) if os.path.exists(settings_file) else {}
except (json.JSONDecodeError, FileNotFoundError):
    settings = {}

hooks = settings.setdefault("hooks", {})
user_prompt_hooks = hooks.setdefault("UserPromptSubmit", [])

hook_command = hook_path
old_hook = hook_command.replace("your-session-start.sh", "your-catalog-announce.sh")

already_registered = any(
    h.get("type") == "command" and h.get("command") == hook_command
    for entry in user_prompt_hooks
    for h in entry.get("hooks", [])
)

# Remove old hook if present
hooks["UserPromptSubmit"] = [
    entry for entry in user_prompt_hooks
    if not any(h.get("command") == old_hook for h in entry.get("hooks", []))
]
user_prompt_hooks = hooks["UserPromptSubmit"]

if not already_registered:
    user_prompt_hooks.append({
        "matcher": "",
        "hooks": [{"type": "command", "command": hook_command}]
    })
    try:
        with open(settings_file, "w") as f:
            json.dump(settings, f, indent=2)
            f.write("\n")
        print(f"  Hook registered in {settings_file}")
    except OSError as e:
        print(f"  ERROR: Could not write {settings_file}: {e}", file=sys.stderr)
        sys.exit(1)
else:
    print(f"  Hook already registered.")
PYEOF
    _step7_rc=$?
    set -e
    if [[ $_step7_rc -eq 0 ]]; then
      echo "  Installed to $HOOK_DEST"
      step_ok "Session hook installed"
    else
      step_fail "Session hook" "could not register hook in settings.json"
    fi
  fi
else
  step_warn "Session hook" "source not found at $HOOK_SRC"
fi

# ── Step 8: Multi-system workflow check ─────────────────────────
echo ""
echo "[8/9] Multi-system workflow check"
_step_start "Multi-system check"
echo "  This feature monitors your repos for git drift and syncs Claude memory"
echo "  across devices via a cloud storage symlink (OneDrive, Dropbox, etc.)."
echo ""

MULTI_CHECK_CONFIG="$HOME/.claude/multi-system-check.json"

if [[ -f "$MULTI_CHECK_CONFIG" ]]; then
  echo "  Already configured."
  _read_input -rp "  Reconfigure for this machine? [y/N] " _reconfig_multi
  if [[ "$(echo "$_reconfig_multi" | tr '[:upper:]' '[:lower:]')" == "y" ]]; then
    echo ""
    if bash "$SCRIPT_DIR/scripts/setup-multi-system.sh"; then
      step_ok "Multi-system check reconfigured"
    else
      step_warn "Multi-system check" "reconfigure did not complete"
    fi
  else
    step_ok "Multi-system check (already configured)"
  fi
else
  _read_input -rp "  Do you work on this project across multiple computers? [Y/n] " MULTI_ANSWER
  if [[ "$(echo "$MULTI_ANSWER" | tr '[:upper:]' '[:lower:]')" == "n" ]]; then
    if echo '{"enabled": false}' > "$MULTI_CHECK_CONFIG" 2>/dev/null; then
      echo "  Skipped. To enable later: ~/claude-config/scripts/setup-multi-system.sh"
      step_ok "Multi-system check (skipped)"
    else
      step_fail "Multi-system check" "could not write config to $MULTI_CHECK_CONFIG"
    fi
  else
    echo ""
    if bash "$SCRIPT_DIR/scripts/setup-multi-system.sh"; then
      step_ok "Multi-system check configured"
    else
      step_warn "Multi-system check" "setup did not complete"
    fi
  fi
fi

# ── Step 9: Memory/preference sync ────────────────────────────
echo ""
echo "[9/9] Memory/preference sync"
echo "  Shows current sync status for org standards, personal prefs, and project memories."
echo ""

SYNC_SCRIPT="$SCRIPT_DIR/scripts/sync-memory.sh"

if [[ -f "$SYNC_SCRIPT" ]]; then
  echo ""
  if bash "$SYNC_SCRIPT"; then
    step_ok "Preference sync status shown"
  else
    step_warn "Preference sync" "status check did not complete"
  fi
  echo "  Org standards sync automatically via setup.sh."
  echo "  Memory and personal prefs sync automatically via OneDrive symlinks (setup-multi-system.sh)."
else
  step_warn "Preference sync" "sync-memory.sh not found at $SYNC_SCRIPT"
fi

# ── Done ────────────────────────────────────────────────────────
echo ""
echo "=== Setup Complete ==="
echo ""
echo "Files created/updated (all global — no project path needed):"
echo "  ~/.claude/.env               — API keys (chmod 600)"
echo "  ~/.claude.json               — MCP server registrations (via claude mcp add)"
echo "  ~/.claude/settings.json      — Plugin and MCP toggles"
echo "  ~/.claude/personas/          — Persona profiles (all sessions)"
echo "  ~/.claude/commands/          — Slash commands (all sessions)"
echo "  ~/.claude/standards/         — Org operational standards (all sessions)"
echo ""
echo "Next steps:"
echo "  1. Any REPLACE_ME values need real keys — check catalog.json for sources"
echo "  2. Add or remove tools anytime: re-run this script"
echo "  3. On additional machines: re-run this script — multi-system check links automatically"
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║   ✅  Claude Code is ready to launch.        ║"
echo "║   Restart Claude Code to apply changes.      ║"
echo "╚══════════════════════════════════════════════╝"

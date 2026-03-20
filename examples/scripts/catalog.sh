#!/usr/bin/env bash
# catalog.sh — Browse, enable, and disable [Your Company] plugins and MCP servers
# Usage: catalog.sh [project-dir]
#   catalog.sh .                  # Interactive menu
#   catalog.sh . --list           # Show current status
#   catalog.sh . --sync           # Re-sync from latest catalog + deploy
#   catalog.sh . --deploy         # Deploy enabled MCP servers to ~/.claude.json
#   catalog.sh add <server-id>    # Add a single MCP server (collect keys, register, enable)
#
# Reads catalog.json from the claude-config repo (local clone or GitHub).
# Writes to .claude/settings.local.json and .mcp.json in the project dir.
# --deploy writes MCP server configs to ~/.claude.json (global).

set -euo pipefail

# Check for team announcements
ANN_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$ANN_DIR/check-announcements.sh" ]]; then
  bash "$ANN_DIR/check-announcements.sh" "${1:-.}"
fi

# Handle "catalog.sh add <server>" shorthand (no project-dir needed)
if [[ "${1:-}" == "add" ]]; then
  PROJECT_DIR="."
  ACTION="add"
  ADD_SERVER_ID="${2:-}"
else
  PROJECT_DIR="${1:-.}"
  ACTION="${2:-}"
  ADD_SERVER_ID="${3:-}"
fi
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CATALOG="$SCRIPT_DIR/catalog.json"
SETTINGS="$PROJECT_DIR/.claude/settings.local.json"
MCP_FILE="$PROJECT_DIR/.mcp.json"
ENV_FILE="$PROJECT_DIR/.env"
GLOBAL_SETTINGS="$HOME/.claude/settings.json"
GLOBAL_MCP="$HOME/.claude.json"

OCC_ROLE_FILE="$HOME/.claude/.occ-role"
OCC_ROLE="user"
if [[ -f "$OCC_ROLE_FILE" ]]; then
  OCC_ROLE="$(cat "$OCC_ROLE_FILE" | tr -d '[:space:]')"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

if [[ ! -f "$CATALOG" ]]; then
  echo "Error: catalog.json not found at $CATALOG"
  echo "Run: git -C $SCRIPT_DIR pull"
  exit 1
fi

# ── Helpers ─────────────────────────────────────────────────────

get_enabled_plugins() {
  if [[ -f "$SETTINGS" ]]; then
    python3 -c "
import json, sys
try:
    d = json.load(open('$SETTINGS'))
    for k, v in d.get('enabledPlugins', {}).items():
        if v: print(k)
except: pass
" 2>/dev/null
  fi
}

get_enabled_mcps() {
  python3 -c "
import json, sys
seen = set()
for path in ['$GLOBAL_SETTINGS', '$SETTINGS']:
    try:
        d = json.load(open(path))
        for s in d.get('enabledMcpjsonServers', []):
            if s not in seen:
                seen.add(s)
                print(s)
    except: pass
" 2>/dev/null
}

catalog_plugins() {
  python3 -c "
import json
c = json.load(open('$CATALOG'))
user_role = '$OCC_ROLE'
for pid, p in sorted(c['plugins'].items(), key=lambda x: (not x[1]['recommended'], x[1]['category'], x[1]['name'])):
    allowed = p.get('roles', ['user', 'admin'])
    if user_role not in allowed:
        continue
    rec = '*' if p['recommended'] else ' '
    print(f\"{rec}|{pid}|{p['name']}|{p['description']}|{p['category']}\")
"
}

catalog_mcps() {
  python3 -c "
import json
c = json.load(open('$CATALOG'))
user_role = '$OCC_ROLE'
for mid, m in sorted(c['mcpServers'].items(), key=lambda x: (not x[1]['recommended'], x[1]['category'], x[1]['name'])):
    allowed = m.get('roles', ['user', 'admin'])
    if user_role not in allowed:
        continue
    rec = '*' if m['recommended'] else ' '
    keys = ', '.join(m.get('requiredKeys', []))
    print(f\"{rec}|{mid}|{m['name']}|{m['description']}|{m['category']}|{keys}\")
"
}

# ── List Mode ───────────────────────────────────────────────────

list_status() {
  local enabled_plugins
  enabled_plugins=$(get_enabled_plugins)
  local enabled_mcps
  enabled_mcps=$(get_enabled_mcps)

  echo ""
  printf "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}\n"
  printf "${BOLD}${CYAN}║            [Your Company] Claude Code Catalog — Status                 ║${NC}\n"
  printf "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}\n"

  echo ""
  printf "${BOLD}  PLUGINS${NC}  ${DIM}(* = recommended)${NC}\n"
  printf "  %-3s %-30s %-12s %s\n" "" "Name" "Category" "Status"
  printf "  ${DIM}%-3s %-30s %-12s %s${NC}\n" "---" "------------------------------" "------------" "--------"

  while IFS='|' read -r rec pid name desc category; do
    if echo "$enabled_plugins" | grep -qF "$pid"; then
      status="${GREEN}enabled${NC}"
    else
      status="${DIM}disabled${NC}"
    fi
    printf "  ${YELLOW}%-3s${NC} %-30s %-12s %b\n" "$rec" "$name" "$category" "$status"
  done < <(catalog_plugins)

  echo ""
  printf "${BOLD}  MCP SERVERS${NC}  ${DIM}(* = recommended)${NC}\n"
  printf "  %-3s %-22s %-12s %-20s %s\n" "" "Name" "Category" "Required Keys" "Status"
  printf "  ${DIM}%-3s %-22s %-12s %-20s %s${NC}\n" "---" "----------------------" "------------" "--------------------" "--------"

  while IFS='|' read -r rec mid name desc category keys; do
    if echo "$enabled_mcps" | grep -qF "$mid"; then
      status="${GREEN}enabled${NC}"
    else
      status="${DIM}disabled${NC}"
    fi
    printf "  ${YELLOW}%-3s${NC} %-22s %-12s %-20s %b\n" "$rec" "$name" "$category" "$keys" "$status"
  done < <(catalog_mcps)

  echo ""
}

# ── Interactive Mode ────────────────────────────────────────────

toggle_menu() {
  local type="$1"  # "plugins" or "mcps"
  local items=()
  local names=()
  local enabled_list

  if [[ "$type" == "plugins" ]]; then
    enabled_list=$(get_enabled_plugins)
    while IFS='|' read -r rec pid name desc category; do
      items+=("$pid")
      names+=("$name — $desc")
    done < <(catalog_plugins)
  else
    enabled_list=$(get_enabled_mcps)
    while IFS='|' read -r rec mid name desc category keys; do
      items+=("$mid")
      names+=("$name — $desc${keys:+ (keys: $keys)}")
    done < <(catalog_mcps)
  fi

  echo ""
  printf "${BOLD}Select ${type} to toggle (space-separated numbers, or 'r' for recommended, 'a' for all, 'q' to quit):${NC}\n"
  echo ""

  for i in "${!items[@]}"; do
    local id="${items[$i]}"
    if echo "$enabled_list" | grep -qF "$id"; then
      mark="${GREEN}[x]${NC}"
    else
      mark="${DIM}[ ]${NC}"
    fi
    printf "  %b %2d) %s\n" "$mark" "$((i+1))" "${names[$i]}"
  done

  echo ""
  printf "  ${DIM}r) Enable recommended only  a) Enable all  n) Disable all  q) Done${NC}\n"
  printf "\n  Choice: "
  read -r choice

  case "$choice" in
    q|Q) return ;;
    r|R)
      # Enable only recommended
      local rec_items=()
      if [[ "$type" == "plugins" ]]; then
        while IFS='|' read -r rec pid name desc category; do
          [[ "$rec" == "*" ]] && rec_items+=("$pid")
        done < <(catalog_plugins)
      else
        while IFS='|' read -r rec mid name desc category keys; do
          [[ "$rec" == "*" ]] && rec_items+=("$mid")
        done < <(catalog_mcps)
      fi
      update_settings "$type" "${rec_items[@]}"
      ;;
    a|A)
      update_settings "$type" "${items[@]}"
      ;;
    n|N)
      update_settings "$type"
      ;;
    *)
      local selected=()
      # Start with current enabled
      for id in "${items[@]}"; do
        if echo "$enabled_list" | grep -qF "$id"; then
          selected+=("$id")
        fi
      done
      # Toggle selected numbers
      for num in $choice; do
        if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= ${#items[@]} )); then
          local id="${items[$((num-1))]}"
          local found=0
          local new_selected=()
          for s in "${selected[@]}"; do
            if [[ "$s" == "$id" ]]; then
              found=1
            else
              new_selected+=("$s")
            fi
          done
          if (( found )); then
            selected=("${new_selected[@]}")
          else
            selected+=("$id")
          fi
        fi
      done
      update_settings "$type" "${selected[@]}"
      ;;
  esac
}

update_settings() {
  local type="$1"
  shift
  local items=("$@")

  mkdir -p "$PROJECT_DIR/.claude"

  python3 - "$type" "$SETTINGS" "${items[@]}" <<'PYEOF'
import json, sys

stype = sys.argv[1]
settings_file = sys.argv[2]
items = sys.argv[3:]

try:
    with open(settings_file) as f:
        settings = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    settings = {}

if stype == "plugins":
    # Get all plugin IDs from current settings
    current = settings.get("enabledPlugins", {})
    # Disable all, then enable selected
    for k in current:
        current[k] = False
    for item in items:
        current[item] = True
    settings["enabledPlugins"] = current
elif stype == "mcps":
    settings["enabledMcpjsonServers"] = list(items)

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')

print(f"  Updated {len(items)} {stype} in {settings_file}")
PYEOF
}

setup_mcp_keys() {
  local mid="$1"
  echo ""

  # Get key info from catalog
  python3 - "$mid" "$CATALOG" "$ENV_FILE" "$MCP_FILE" <<'PYEOF'
import json, sys, os

mid = sys.argv[1]
catalog_file = sys.argv[2]
env_file = sys.argv[3]
mcp_file = sys.argv[4]

catalog = json.load(open(catalog_file))
server = catalog['mcpServers'].get(mid)
if not server:
    print(f"  Server '{mid}' not found in catalog")
    sys.exit(0)

# Load existing env
env = {}
if os.path.exists(env_file):
    with open(env_file) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                k, v = line.split('=', 1)
                env[k.strip()] = v.strip().strip('"')

required = server.get('requiredKeys', [])
optional = server.get('optionalKeys', [])
descriptions = server.get('keyDescriptions', {})

all_keys = required + optional
if not all_keys:
    print(f"  {server['name']}: No keys required")
    sys.exit(0)

# Show setup instructions if available
instructions = server.get("setupInstructions", [])
if instructions:
    print(f"\n  How to get your keys:")
    for i, step in enumerate(instructions, 1):
        print(f"    {i}. {step}")
    print()
print(f"  {server['name']} keys:")
changed = False
for key in all_keys:
    current = env.get(key, '')
    desc = descriptions.get(key, '')
    req_label = '(required)' if key in required else '(optional)'

    if current and current not in ('', 'REPLACE_ME'):
        print(f"    {key}: [already set]")
    else:
        print(f"    {key} {req_label}")
        if desc:
            print(f"      Source: {desc}")
        try:
            import getpass
            val = getpass.getpass(f"      Value: ").strip()
        except Exception:
            val = ''
        if val:
            env[key] = val
            changed = True

if changed:
    with open(env_file, 'w') as f:
        f.write(f"# [Your Company] MCP Server Configuration\n")
        f.write(f"# Updated by catalog.sh\n\n")
        for k, v in sorted(env.items()):
            f.write(f'{k}="{v}"\n')
    os.chmod(env_file, 0o600)
    print(f"  Updated {env_file}")

    # Also update .mcp.json with the new values
    if os.path.exists(mcp_file):
        mcp = json.load(open(mcp_file))
    else:
        mcp = {"mcpServers": {}}

    # Build server entry from catalog
    entry = {"command": server["command"], "args": server["args"]}
    srv_env = dict(server.get("env", {}))
    for key in all_keys:
        if key in env and env[key]:
            srv_env[key] = env[key]
    if srv_env:
        entry["env"] = srv_env

    # Substitute variables in args
    new_args = []
    for arg in entry["args"]:
        for k, v in env.items():
            arg = arg.replace(f"${{{k}}}", v)
        new_args.append(arg)
    entry["args"] = new_args

    mcp["mcpServers"][mid] = entry
    with open(mcp_file, 'w') as f:
        json.dump(mcp, f, indent=2)
        f.write('\n')
    os.chmod(mcp_file, 0o600)
    print(f"  Updated {mcp_file}")
PYEOF
}

# ── Deploy Mode ─────────────────────────────────────────────────

deploy_global_mcp() {
  python3 - "$CATALOG" "$GLOBAL_SETTINGS" "$SETTINGS" "$GLOBAL_MCP" <<'PYEOF'
import json, sys, os

catalog_file = sys.argv[1]
global_settings_file = sys.argv[2]
local_settings_file = sys.argv[3]
global_mcp_file = sys.argv[4]

catalog = json.load(open(catalog_file))
servers = catalog.get('mcpServers', {})

enabled = set()
for path in [global_settings_file, local_settings_file]:
    try:
        d = json.load(open(path))
        for s in d.get('enabledMcpjsonServers', []):
            enabled.add(s)
    except (FileNotFoundError, json.JSONDecodeError, ValueError):
        pass

if not enabled:
    print("  No enabled MCP servers found in settings. Nothing to deploy.")
    sys.exit(0)

try:
    with open(global_mcp_file) as f:
        global_mcp = json.load(f)
except (FileNotFoundError, json.JSONDecodeError, ValueError):
    global_mcp = {}

if 'mcpServers' not in global_mcp:
    global_mcp['mcpServers'] = {}

existing_keys = set(global_mcp['mcpServers'].keys())
catalog_keys = set(servers.keys())

added = []
updated = []
skipped_missing = []
warned_keys = []

for mid in sorted(enabled):
    if mid not in servers:
        skipped_missing.append(mid)
        continue

    srv = servers[mid]
    entry = {
        "type": "stdio",
        "command": srv["command"],
        "args": list(srv["args"]),
    }
    srv_env = dict(srv.get("env", {}))
    if srv_env:
        entry["env"] = srv_env
    else:
        entry["env"] = {}

    missing_keys = []
    for key in srv.get("requiredKeys", []):
        val = os.environ.get(key, "")
        if not val:
            missing_keys.append(key)
    if missing_keys:
        warned_keys.append((mid, missing_keys))

    if mid in existing_keys:
        if global_mcp['mcpServers'][mid] != entry:
            updated.append(mid)
        global_mcp['mcpServers'][mid] = entry
    else:
        added.append(mid)
        global_mcp['mcpServers'][mid] = entry

removed = []
for mid in list(global_mcp['mcpServers'].keys()):
    if mid in catalog_keys and mid not in enabled:
        del global_mcp['mcpServers'][mid]
        removed.append(mid)

with open(global_mcp_file, 'w') as f:
    json.dump(global_mcp, f, indent=2)
    f.write('\n')

print("  Deploy summary:")
if added:
    print("    Added:   " + ", ".join(added))
if updated:
    print("    Updated: " + ", ".join(updated))
if removed:
    print("    Removed: " + ", ".join(removed))
if not added and not updated and not removed:
    print("    No changes — global config already matches.")
if skipped_missing:
    print("    Skipped (not in catalog): " + ", ".join(skipped_missing))
if warned_keys:
    print("")
    for mid, keys in warned_keys:
        print("    \033[0;33mWarning:\033[0m " + mid + " missing env keys: " + ", ".join(keys))

print("  Deployed to: " + global_mcp_file)
PYEOF
}

# ── Add Single Server ──────────────────────────────────────────

add_server() {
  local mid="$1"

  # ── Interactive terminal check ──────────────────────────────────
  # If stdin is not a terminal (e.g. called from Claude Code's Bash tool),
  # re-launch in a real terminal so getpass/OAuth can work.
  if [[ ! -t 0 ]]; then
    local self_cmd="$SCRIPT_DIR/scripts/catalog.sh add $mid"

    if [[ -n "${VSCODE_IPC_HOOK_CLI:-}" ]] || [[ -n "${CURSOR_TRACE_DIR:-}" ]] || [[ "${TERM_PROGRAM:-}" =~ ^(vscode|cursor)$ ]]; then
      # Inside VSCode/Cursor — open the IDE's integrated terminal
      echo "  Opening IDE terminal to collect credentials securely..."
      if command -v code &>/dev/null; then
        code --command workbench.action.terminal.new
        echo ""
        echo "  Run this in the terminal that just opened:"
        printf "  ${BOLD}${CYAN}%s${NC}\n" "$self_cmd"
      else
        echo "  Open the integrated terminal (Ctrl+\`) and run:"
        printf "  ${BOLD}${CYAN}%s${NC}\n" "$self_cmd"
      fi
    elif [[ "$(uname)" == "Darwin" ]]; then
      # macOS native — open Terminal.app with the command
      echo "  Opening Terminal to collect credentials securely..."
      osascript -e "tell application \"Terminal\" to do script \"$self_cmd\"" 2>/dev/null \
        || open -a Terminal "$self_cmd" 2>/dev/null \
        || {
          echo "  Could not open Terminal. Run manually:"
          printf "  ${BOLD}${CYAN}%s${NC}\n" "$self_cmd"
        }
    else
      # Linux / other — try common terminal emulators
      echo "  Opening terminal to collect credentials securely..."
      if command -v gnome-terminal &>/dev/null; then
        gnome-terminal -- bash -c "$self_cmd; exec bash"
      elif command -v xterm &>/dev/null; then
        xterm -e "$self_cmd" &
      else
        echo "  Could not detect terminal. Run manually:"
        printf "  ${BOLD}${CYAN}%s${NC}\n" "$self_cmd"
      fi
    fi
    echo ""
    echo "  After setup completes, restart Claude Code to use the new server."
    return 0
  fi

  # Validate server exists in catalog
  if ! python3 -c "import json; c=json.load(open('$CATALOG')); assert '$mid' in c['mcpServers']" 2>/dev/null; then
    echo "  Error: '$mid' not found in catalog."
    echo "  Available servers:"
    python3 -c "
import json
c = json.load(open('$CATALOG'))
for k, v in sorted(c['mcpServers'].items()):
    print(f\"    {k:20s} — {v['name']}\")
"
    exit 1
  fi

  local server_name
  server_name=$(python3 -c "import json; print(json.load(open('$CATALOG'))['mcpServers']['$mid']['name'])")
  echo ""
  printf "${BOLD}Adding MCP server: ${CYAN}$server_name${NC} ${DIM}($mid)${NC}\n"

  # Step 1: Collect keys (masked via getpass)
  local global_env="$HOME/.claude/.env"
  _add_py=$(mktemp /tmp/occ_add_XXXXX)
  cat > "$_add_py" << 'PYEOF'
import json, sys, os, getpass

mid = sys.argv[1]
catalog_file = sys.argv[2]
env_file = sys.argv[3]

catalog = json.load(open(catalog_file))
server = catalog['mcpServers'][mid]

env = {}
if os.path.exists(env_file):
    with open(env_file) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                k, v = line.split('=', 1)
                env[k.strip()] = v.strip().strip('"')

required = server.get('requiredKeys', [])
optional = server.get('optionalKeys', [])
descriptions = server.get('keyDescriptions', {})
derived_token = server.get('derivedToken', '')

# If derived token already set, skip
if derived_token and env.get(derived_token, '').strip() not in ('', 'REPLACE_ME'):
    print(f"  {derived_token}: [already set — skipping key collection]")
    sys.exit(0)

all_keys = required + optional
if not all_keys:
    print(f"  No keys required.")
    sys.exit(0)

instructions = server.get('setupInstructions', [])
if instructions:
    print(f"\n  Setup instructions:")
    for i, step in enumerate(instructions, 1):
        print(f"    {i}. {step}")
    print()

changed = False
for key in all_keys:
    current = env.get(key, '')
    desc = descriptions.get(key, '')
    req_label = '(required)' if key in required else '(optional)'

    if current and current not in ('', 'REPLACE_ME'):
        print(f"  {key}: [already set]")
        continue

    if key in optional:
        print(f"  {key}: [optional — auto-resolved at runtime]")
        continue

    if desc:
        print(f"  {key} {req_label} — {desc}")
    else:
        print(f"  {key} {req_label}")

    try:
        val = getpass.getpass("    Value: ").strip()
    except Exception:
        val = ''
        print("  (could not read input — skipping)")

    if val:
        env[key] = val
        changed = True

if changed:
    with open(env_file, 'w') as f:
        f.write("# [Your Company] MCP Server Configuration\n")
        f.write(f"# Updated by catalog.sh on {__import__('datetime').date.today()}\n")
        f.write("# NEVER commit this file.\n\n")
        for k, v in sorted(env.items()):
            f.write(f'{k}="{v}"\n')
    os.chmod(env_file, 0o600)
    print(f"\n  Keys saved to {env_file}")
PYEOF

  set +e
  python3 "$_add_py" "$mid" "$CATALOG" "$global_env"
  local _key_rc=$?
  set -e
  rm -f "$_add_py"
  [[ $_key_rc -ne 0 ]] && return 1

  # Re-source env
  set -a; source "$global_env" 2>/dev/null; set +a

  # Step 1b: ClickUp OAuth flow (if applicable)
  if [[ "$mid" == "clickup" ]] \
      && [[ -n "${CLICKUP_CLIENT_ID:-}" ]] \
      && [[ -n "${CLICKUP_CLIENT_SECRET:-}" ]] \
      && [[ -z "${CLICKUP_API_TOKEN:-}" ]]; then
    echo ""
    echo "  -- ClickUp OAuth --"
    echo "  Opening browser — authorize the app in ClickUp..."
    local _cu_url="https://app.clickup.com/api?client_id=${CLICKUP_CLIENT_ID}&redirect_uri=http://localhost:3456"
    if [[ "$(uname)" == "Darwin" ]]; then
      open "$_cu_url"
    else
      xdg-open "$_cu_url" 2>/dev/null || printf "  Please open: %s\n" "$_cu_url"
    fi
    echo "  Waiting for callback on localhost:3456..."

    _cu_py=$(mktemp /tmp/cu_oauth_XXXXX)
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
    local _cu_code
    _cu_code=$(python3 "$_cu_py" 2>/dev/null)
    rm -f "$_cu_py"

    if [[ -n "$_cu_code" ]]; then
      echo "  Exchanging for access token..."
      local _cu_resp
      _cu_resp=$(curl -s -X POST "https://api.clickup.com/api/v2/oauth/token" \
        -H "Content-Type: application/json" \
        -d "{\"client_id\":\"${CLICKUP_CLIENT_ID}\",\"client_secret\":\"${CLICKUP_CLIENT_SECRET}\",\"code\":\"${_cu_code}\"}")
      local _cu_token
      _cu_token=$(echo "$_cu_resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('access_token',''))" 2>/dev/null || true)

      if [[ -n "${_cu_token:-}" ]]; then
        echo "  ClickUp OAuth complete — token saved"
        python3 - "$global_env" "$_cu_token" << 'CUENVEOF'
import sys, os
env_file, token = sys.argv[1], sys.argv[2]
env = {}
if os.path.exists(env_file):
    for line in open(env_file):
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            k, v = line.split('=', 1)
            env[k.strip()] = v.strip().strip('"')
env['CLICKUP_API_TOKEN'] = token
with open(env_file, 'w') as fh:
    fh.write("# [Your Company] MCP Server Configuration\n# NEVER commit this file.\n\n")
    for k, v in sorted(env.items()):
        fh.write(f'{k}="{v}"\n')
os.chmod(env_file, 0o600)
CUENVEOF
        set -a; source "$global_env" 2>/dev/null; set +a
      else
        printf "  Token exchange failed: %s\n" "$_cu_resp"
        return 1
      fi
    else
      echo "  No authorization code received."
      return 1
    fi
  fi

  # Step 2: Register via claude mcp add
  echo ""
  echo "  Registering $server_name with Claude Code..."

  python3 - "$mid" "$CATALOG" <<'PYEOF'
import json, sys, subprocess

mid = sys.argv[1]
catalog = json.load(open(sys.argv[2]))
m = catalog['mcpServers'][mid]

subprocess.run(["claude", "mcp", "remove", mid, "-s", "user"], capture_output=True)

env_flags = []
for key, val in m.get("env", {}).items():
    env_flags += ["-e", f"{key}={val}"]

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
    print(f"  Registered globally via 'claude mcp add -s user'")
else:
    print(f"  ERROR: {result.stderr.strip()}")
    sys.exit(1)
PYEOF

  # Step 3: Enable in global settings.json
  local global_settings="$HOME/.claude/settings.json"
  python3 - "$mid" "$global_settings" <<'PYEOF'
import json, sys, os

mid = sys.argv[1]
settings_file = sys.argv[2]

try:
    settings = json.load(open(settings_file)) if os.path.exists(settings_file) else {}
except (json.JSONDecodeError, FileNotFoundError):
    settings = {}

mcps = settings.get('enabledMcpjsonServers', [])
if mid not in mcps:
    mcps.append(mid)
    settings['enabledMcpjsonServers'] = mcps
    with open(settings_file, 'w') as f:
        json.dump(settings, f, indent=2)
        f.write('\n')
    print(f"  Enabled in {settings_file}")
else:
    print(f"  Already enabled in {settings_file}")
PYEOF

  echo ""
  printf "${GREEN}  Done!${NC} Restart Claude Code to use ${BOLD}$server_name${NC}.\n"
  echo ""
}

# ── Main ────────────────────────────────────────────────────────

case "${ACTION}" in
  --list|-l)
    list_status
    ;;
  --deploy|-d)
    echo "Deploying enabled MCP servers to global config..."
    deploy_global_mcp
    ;;
  --sync|-s)
    echo "Syncing catalog from GitHub..."
    git -C "$SCRIPT_DIR" pull --quiet 2>/dev/null || echo "  Warning: Could not pull latest catalog"
    echo ""
    echo "Deploying enabled MCP servers to global config..."
    deploy_global_mcp
    echo ""
    list_status
    ;;
  add)
    SERVER_ID="${ADD_SERVER_ID:-}"
    if [[ -z "$SERVER_ID" ]]; then
      echo "Usage: catalog.sh add <server-id>"
      echo "Example: catalog.sh add clickup"
      exit 1
    fi
    add_server "$SERVER_ID"
    ;;
  *)
    # Interactive mode
    list_status

    while true; do
      echo ""
      printf "${BOLD}What would you like to do?${NC}\n"
      echo "  1) Toggle plugins"
      echo "  2) Toggle MCP servers"
      echo "  3) Configure MCP server keys"
      echo "  4) Show current status"
      echo "  5) Sync latest catalog from GitHub"
      echo "  q) Quit"
      printf "\n  Choice: "
      read -r main_choice

      case "$main_choice" in
        1) toggle_menu "plugins" ;;
        2) toggle_menu "mcps" ;;
        3)
          echo ""
          printf "  MCP server ID (e.g. [your-kb-server], [your-voip-server], ms365): "
          read -r server_id
          setup_mcp_keys "$server_id"
          ;;
        4) list_status ;;
        5)
          echo "  Syncing..."
          git -C "$SCRIPT_DIR" pull --quiet 2>/dev/null || echo "  Warning: Could not pull"
          echo "  Done."
          ;;
        q|Q)
          echo ""
          echo "  Restart Claude Code to apply changes."
          echo ""
          break
          ;;
        *) echo "  Invalid choice" ;;
      esac
    done
    ;;
esac

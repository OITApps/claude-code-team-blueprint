#!/usr/bin/env bash
# catalog.sh — Browse, enable, and disable [Your Company] plugins and MCP servers
# Usage: catalog.sh [project-dir]
#   catalog.sh .                  # Interactive menu
#   catalog.sh . --list           # Show current status
#   catalog.sh . --sync           # Re-sync from latest catalog
#
# Reads catalog.json from the claude-config repo (local clone or GitHub).
# Writes to .claude/settings.local.json and .mcp.json in the project dir.

set -euo pipefail

# Check for team announcements
ANN_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$ANN_DIR/check-announcements.sh" ]]; then
  bash "$ANN_DIR/check-announcements.sh" "${1:-.}"
fi

PROJECT_DIR="${1:-.}"
ACTION="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CATALOG="$SCRIPT_DIR/catalog.json"
SETTINGS="$PROJECT_DIR/.claude/settings.local.json"
MCP_FILE="$PROJECT_DIR/.mcp.json"
ENV_FILE="$PROJECT_DIR/.env"

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
  if [[ -f "$SETTINGS" ]]; then
    python3 -c "
import json, sys
try:
    d = json.load(open('$SETTINGS'))
    for s in d.get('enabledMcpjsonServers', []):
        print(s)
except: pass
" 2>/dev/null
  fi
}

catalog_plugins() {
  python3 -c "
import json
c = json.load(open('$CATALOG'))
for pid, p in sorted(c['plugins'].items(), key=lambda x: (not x[1]['recommended'], x[1]['category'], x[1]['name'])):
    rec = '*' if p['recommended'] else ' '
    print(f\"{rec}|{pid}|{p['name']}|{p['description']}|{p['category']}\")
"
}

catalog_mcps() {
  python3 -c "
import json
c = json.load(open('$CATALOG'))
for mid, m in sorted(c['mcpServers'].items(), key=lambda x: (not x[1]['recommended'], x[1]['category'], x[1]['name'])):
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
        sys.stdout.write(f"      Value: ")
        sys.stdout.flush()
        try:
            with open('/dev/tty') as tty:
                val = tty.readline().strip()
        except OSError:
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

# ── Main ────────────────────────────────────────────────────────

case "${ACTION}" in
  --list|-l)
    list_status
    ;;
  --sync|-s)
    echo "Syncing catalog from GitHub..."
    git -C "$SCRIPT_DIR" pull --quiet 2>/dev/null || echo "  Warning: Could not pull latest catalog"
    list_status
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

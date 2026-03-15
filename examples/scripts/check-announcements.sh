#!/usr/bin/env bash
# check-announcements.sh — Show unread announcements once per user
# Source this from other scripts or run directly:
#   source ~/claude-config/scripts/check-announcements.sh [project-dir]
#   ~/claude-config/scripts/check-announcements.sh [project-dir]

PROJ_DIR="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANNOUNCEMENTS="$SCRIPT_DIR/announcements.json"
SEEN_FILE="$PROJ_DIR/.claude/.announcements-seen"

if [[ ! -f "$ANNOUNCEMENTS" ]]; then
  return 0 2>/dev/null || exit 0
fi

mkdir -p "$(dirname "$SEEN_FILE")"
touch "$SEEN_FILE"

python3 - "$ANNOUNCEMENTS" "$SEEN_FILE" <<'PYEOF'
import json, sys, os

announcements_file = sys.argv[1]
seen_file = sys.argv[2]

try:
    data = json.load(open(announcements_file))
except (json.JSONDecodeError, FileNotFoundError):
    sys.exit(0)

# Load seen IDs
seen = set()
if os.path.exists(seen_file):
    with open(seen_file) as f:
        seen = set(line.strip() for line in f if line.strip())

# Find unread announcements
unread = [a for a in data.get("announcements", []) if a.get("id") not in seen]

if not unread:
    sys.exit(0)

# Display unread
print()
print("\033[1m\033[36m" + "═" * 60 + "\033[0m")
print("\033[1m\033[36m  📢 New Announcements\033[0m")
print("\033[1m\033[36m" + "═" * 60 + "\033[0m")

for a in unread:
    title = a.get("title", "Untitled")
    message = a.get("message", "")
    date = a.get("date", "")
    author = a.get("author", "")
    
    print()
    print(f"  \033[1m{title}\033[0m")
    if date or author:
        meta = []
        if date:
            meta.append(date)
        if author:
            meta.append(f"by {author}")
        print(f"  \033[2m{' — '.join(meta)}\033[0m")
    if message:
        for line in message.split('\n'):
            print(f"  {line}")

print()
print("\033[1m\033[36m" + "═" * 60 + "\033[0m")
print()

# Mark all as seen
with open(seen_file, 'a') as f:
    for a in unread:
        f.write(a["id"] + "\n")
PYEOF

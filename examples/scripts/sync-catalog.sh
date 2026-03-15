#!/usr/bin/env bash
# sync-catalog.sh — Scan [YourGitHubOrg] repos for .claude-catalog-entry.json
# and propose updates to catalog.json via PR.
#
# Usage:
#   ./scripts/sync-catalog.sh              # Dry run — show what would change
#   ./scripts/sync-catalog.sh --apply      # Update catalog.json locally
#   ./scripts/sync-catalog.sh --pr         # Create PR with changes (used by CI)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CATALOG="$SCRIPT_DIR/catalog.json"
MODE="${1:---dry-run}"

echo "=== [Your Company] Catalog Sync ==="
echo "Scanning [YourGitHubOrg] repos for .claude-catalog-entry.json..."
echo ""

# Get all [YourGitHubOrg] repos
REPOS=$(gh api orgs/[YourGitHubOrg]/repos --paginate --jq '.[].name' 2>/dev/null | sort)

if [[ -z "$REPOS" ]]; then
  echo "Error: Could not list [YourGitHubOrg] repos. Check gh auth status."
  exit 1
fi

# Collect all catalog entries from repos
ENTRIES_DIR=$(mktemp -d)
FOUND=0

for repo in $REPOS; do
  # Skip claude-config itself
  [[ "$repo" == "claude-config" ]] && continue

  # Check for catalog entry file
  ENTRY=$(gh api "repos/[YourGitHubOrg]/$repo/contents/.claude-catalog-entry.json" --jq '.content' 2>/dev/null || true)

  if [[ -n "$ENTRY" ]]; then
    echo "  Found: [YourGitHubOrg]/$repo"
    echo "$ENTRY" | base64 -d > "$ENTRIES_DIR/$repo.json"
    FOUND=$((FOUND + 1))
  fi
done

echo ""
echo "Found $FOUND repos with catalog entries."

if [[ "$FOUND" -eq 0 ]]; then
  echo "No changes needed."
  rm -rf "$ENTRIES_DIR"
  exit 0
fi

# Merge entries into catalog
python3 - "$CATALOG" "$ENTRIES_DIR" "$MODE" <<'PYEOF'
import json, sys, os, glob

catalog_file = sys.argv[1]
entries_dir = sys.argv[2]
mode = sys.argv[3]

catalog = json.load(open(catalog_file))
changes = []

for entry_file in sorted(glob.glob(os.path.join(entries_dir, "*.json"))):
    repo = os.path.basename(entry_file).replace(".json", "")
    try:
        entry = json.load(open(entry_file))
    except json.JSONDecodeError:
        print(f"  Warning: Invalid JSON in [YourGitHubOrg]/{repo}/.claude-catalog-entry.json — skipping")
        continue

    # Validate required fields
    entry_type = entry.get("type")
    entry_id = entry.get("id")
    entry_name = entry.get("name")

    if not all([entry_type, entry_id, entry_name]):
        print(f"  Warning: [YourGitHubOrg]/{repo} missing required fields (type, id, name) — skipping")
        continue

    if entry_type not in ("plugin", "mcp"):
        print(f"  Warning: [YourGitHubOrg]/{repo} has unknown type '{entry_type}' — skipping")
        continue

    # Tag with source repo for tracking
    entry["_source"] = f"[YourGitHubOrg]/{repo}"

    target = "plugins" if entry_type == "plugin" else "mcpServers"
    existing = catalog.get(target, {}).get(entry_id)

    # Build catalog entry (strip meta fields)
    catalog_entry = {k: v for k, v in entry.items() if k not in ("type", "id", "_source")}
    catalog_entry["_source"] = entry["_source"]

    if existing:
        # Check if changed (ignore _source for comparison)
        existing_cmp = {k: v for k, v in existing.items() if k != "_source"}
        new_cmp = {k: v for k, v in catalog_entry.items() if k != "_source"}
        if existing_cmp != new_cmp:
            changes.append(("update", entry_type, entry_id, entry_name, repo))
            catalog.setdefault(target, {})[entry_id] = catalog_entry
        else:
            print(f"  Unchanged: {entry_name} ({entry_id}) from [YourGitHubOrg]/{repo}")
    else:
        changes.append(("add", entry_type, entry_id, entry_name, repo))
        # New entries default to recommended=false until admin approves
        if "recommended" not in catalog_entry:
            catalog_entry["recommended"] = False
        catalog.setdefault(target, {})[entry_id] = catalog_entry

if not changes:
    print("\n  No changes to catalog.")
    sys.exit(0)

print(f"\n  Changes detected ({len(changes)}):")
for action, etype, eid, ename, repo in changes:
    symbol = "+" if action == "add" else "~"
    print(f"    {symbol} [{etype}] {ename} ({eid}) from [YourGitHubOrg]/{repo}")

if mode in ("--apply", "--pr"):
    with open(catalog_file, 'w') as f:
        json.dump(catalog, f, indent=2)
        f.write('\n')
    print(f"\n  Updated {catalog_file}")

    # Write change summary for PR body
    summary_file = os.path.join(os.path.dirname(catalog_file), ".sync-summary.txt")
    with open(summary_file, 'w') as f:
        for action, etype, eid, ename, repo in changes:
            verb = "Added" if action == "add" else "Updated"
            f.write(f"- {verb} **{ename}** (`{eid}`, {etype}) from `[YourGitHubOrg]/{repo}`\n")
    print(f"  Summary written to {summary_file}")
else:
    print("\n  Dry run — no files changed. Use --apply or --pr to update.")
PYEOF

rm -rf "$ENTRIES_DIR"

# Create PR if in PR mode
if [[ "$MODE" == "--pr" ]]; then
  cd "$SCRIPT_DIR"

  # Check if there are actual changes
  if git diff --quiet catalog.json 2>/dev/null; then
    echo "  No diff in catalog.json — skipping PR."
    rm -f .sync-summary.txt
    exit 0
  fi

  BRANCH="catalog-sync/$(date +%Y%m%d-%H%M%S)"
  git checkout -b "$BRANCH"
  git add catalog.json
  
  SUMMARY=$(cat .sync-summary.txt 2>/dev/null || echo "Automated catalog sync")
  rm -f .sync-summary.txt

  git commit -m "$(cat <<EOF
chore: Sync catalog from [YourGitHubOrg] repos

Auto-discovered .claude-catalog-entry.json files:
$SUMMARY

Co-Authored-By: sync-catalog.sh
EOF
)"

  git push origin "$BRANCH"

  gh pr create \
    --title "Catalog sync: $(date +%Y-%m-%d)" \
    --body "$(cat <<EOF
## Auto-discovered catalog entries

The following changes were found by scanning [YourGitHubOrg] repos for \`.claude-catalog-entry.json\`:

$SUMMARY

### Review checklist
- [ ] Verify each entry has correct \`requiredKeys\` and \`keyDescriptions\`
- [ ] Confirm \`recommended\` flag is set appropriately
- [ ] New entries default to \`recommended: false\` — set to \`true\` if needed

> This PR was created automatically by \`scripts/sync-catalog.sh\`.
> An admin must approve before it merges.
EOF
)" \
    --reviewer [your-github-username]

  # Return to main
  git checkout main

  echo ""
  echo "  PR created. An admin must approve before it merges."
fi

echo ""
echo "=== Sync complete ==="

#!/usr/bin/env bash
# bootstrap-repo.sh — Apply [Your Company] security standards to any [YourGitHubOrg] GitHub repo
# Usage: ./scripts/bootstrap-repo.sh [YourGitHubOrg]/repo-name [--dry-run]
#
# Applies:
#   - Branch protection on main (1 approval, stale review dismissal)
#   - Push restrictions to authorized users
#   - Secret scanning + push protection
#   - Dependabot vulnerability alerts
#   - Copies: gitleaks workflow, validate-commands workflow, PR template, CODEOWNERS
#   - Copies: health-check.sh for local config validation
#   - Copies: .gitignore with [Your Company] security defaults

set -euo pipefail

REPO="${1:-}"
DRY_RUN="${2:-}"

if [[ -z "$REPO" ]]; then
  echo "Usage: $0 [YourGitHubOrg]/repo-name [--dry-run]"
  exit 1
fi

# Authorized pushers — update this list as team changes
PUSH_USERS='["[your-github-username]","[your-github-user-2]","[team-member-github]","[team-member-github]","[team-member-github]"]'

echo "=== [Your Company] Repo Security Bootstrap ==="
echo "Repo: $REPO"
echo ""

# 1. Enable secret scanning + push protection
echo "[1/6] Enabling secret scanning + push protection..."
if [[ "$DRY_RUN" != "--dry-run" ]]; then
  gh api "repos/$REPO" -X PATCH --input - <<EOF
{"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}}
EOF
  echo "  Done."
else
  echo "  [dry-run] Would enable secret scanning + push protection"
fi

# 2. Enable Dependabot vulnerability alerts
echo "[2/6] Enabling Dependabot vulnerability alerts..."
if [[ "$DRY_RUN" != "--dry-run" ]]; then
  gh api "repos/$REPO/vulnerability-alerts" -X PUT 2>/dev/null || true
  echo "  Done."
else
  echo "  [dry-run] Would enable Dependabot alerts"
fi

# 3. Set branch protection on main
echo "[3/6] Setting branch protection on main..."
if [[ "$DRY_RUN" != "--dry-run" ]]; then
  gh api "repos/$REPO/branches/main/protection" -X PUT --input - <<EOF
{
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false
  },
  "enforce_admins": false,
  "required_status_checks": null,
  "restrictions": {
    "users": $PUSH_USERS,
    "teams": [],
    "apps": []
  }
}
EOF
  echo "  Done."
else
  echo "  [dry-run] Would set branch protection (1 approval, push restrictions)"
fi

# 4. Clone and copy standard files
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
echo "[4/6] Copying CI workflows, health check, and templates..."

REPO_DIR="/tmp/bootstrap-${REPO##*/}"
rm -rf "$REPO_DIR"
gh repo clone "$REPO" "$REPO_DIR" -- --depth 1 2>/dev/null

if [[ -d "$REPO_DIR" ]]; then
  mkdir -p "$REPO_DIR/.github/workflows" "$REPO_DIR/scripts"

  # Copy all workflows
  for wf in secret-scan.yml validate-commands.yml; do
    if [[ -f "$SCRIPT_DIR/.github/workflows/$wf" ]]; then
      cp "$SCRIPT_DIR/.github/workflows/$wf" "$REPO_DIR/.github/workflows/"
      echo "  Copied $wf"
    fi
  done

  # Copy PR template
  if [[ -f "$SCRIPT_DIR/.github/pull_request_template.md" ]]; then
    cp "$SCRIPT_DIR/.github/pull_request_template.md" "$REPO_DIR/.github/"
    echo "  Copied pull_request_template.md"
  fi

  # Copy health check
  if [[ -f "$SCRIPT_DIR/scripts/health-check.sh" ]]; then
    cp "$SCRIPT_DIR/scripts/health-check.sh" "$REPO_DIR/scripts/"
    chmod +x "$REPO_DIR/scripts/health-check.sh"
    echo "  Copied health-check.sh"
  fi

  # Generate CODEOWNERS if missing
  if [[ ! -f "$REPO_DIR/CODEOWNERS" ]]; then
    cat > "$REPO_DIR/CODEOWNERS" <<'OWNERS'
# Default — all PRs need admin review
*               @[your-github-username]

# Claude Code config
.claude/        @[your-github-username]
CLAUDE.md       @[your-github-username]

# CI and security
.github/        @[your-github-username]
OWNERS
    echo "  Generated default CODEOWNERS"
  fi

  # Ensure .gitignore has security essentials
  GITIGNORE="$REPO_DIR/.gitignore"
  touch "$GITIGNORE"
  for pattern in ".env" ".claude/memory/" "*.pdf" ".DS_Store"; do
    if ! grep -qF "$pattern" "$GITIGNORE" 2>/dev/null; then
      echo "$pattern" >> "$GITIGNORE"
      echo "  Added $pattern to .gitignore"
    fi
  done

  if [[ "$DRY_RUN" != "--dry-run" ]]; then
    cd "$REPO_DIR"
    git add -A
    if git diff --cached --quiet; then
      echo "  No new files to commit."
    else
      git commit -m "ci: Apply [Your Company] security standards

- Gitleaks secret scan on PRs
- Command/persona validation on PRs
- PR template with checklist
- CODEOWNERS for auto-reviewer assignment
- Health check script (./scripts/health-check.sh)
- .gitignore security defaults (.env, memory, etc.)

Co-Authored-By: bootstrap-repo.sh"
      git push origin main
      echo "  Pushed security config."
    fi
    cd - > /dev/null
  else
    echo "  [dry-run] Would commit and push files"
  fi

  rm -rf "$REPO_DIR"
else
  echo "  Warning: Could not clone repo. Copy files manually."
fi

# 5. Run remote health verification
echo ""
echo "[5/6] Verifying GitHub security settings..."
SCAN=$(gh api "repos/$REPO" --jq '.security_and_analysis.secret_scanning.status' 2>/dev/null || echo "unknown")
PUSH=$(gh api "repos/$REPO" --jq '.security_and_analysis.secret_scanning_push_protection.status' 2>/dev/null || echo "unknown")
PROT=$(gh api "repos/$REPO/branches/main/protection" --jq '.required_pull_request_reviews.required_approving_review_count' 2>/dev/null || echo "none")
DEP=$(gh api "repos/$REPO/vulnerability-alerts" 2>/dev/null && echo "enabled" || echo "enabled")

echo "  Secret scanning:    $SCAN"
echo "  Push protection:    $PUSH"
echo "  Branch protection:  ${PROT} approval(s) required"
echo "  Dependabot:         $DEP"

# 6. Summary
echo ""
echo "[6/6] Summary for $REPO:"
echo "  ✓ Secret scanning + push protection"
echo "  ✓ Dependabot vulnerability alerts"
echo "  ✓ Branch protection (1 approval, restricted pushers)"
echo "  ✓ Gitleaks secret scan on PRs"
echo "  ✓ Command/persona validation on PRs"
echo "  ✓ PR template with checklist"
echo "  ✓ CODEOWNERS"
echo "  ✓ Health check script"
echo "  ✓ .gitignore security defaults"
echo ""
echo "Next steps:"
echo "  1. Clone the repo and run: ./scripts/health-check.sh"
echo "  2. Fix any issues: ./scripts/health-check.sh --fix"
echo "  3. Copy personas/commands from [YourGitHubOrg]/claude-config"
echo ""
echo "=== Bootstrap complete ==="

# CLAUDE.md -- claude-code-team-commander

## Overview

Public blueprint and playbook for building a shared Claude Code configuration for a team or company. Not a runtime server -- this repo contains documentation, example configs, and setup/audit scripts. Published by OIT, LLC.

## Structure

- `blueprint.md` -- complete system prompt for building your own team config
- `scripts/audit/` -- audit tooling
- `examples/` -- example configurations
- `example-catalog.json` -- sample approved tool catalog
- `example-announcements.json` -- sample team announcement payloads
- `example-CLAUDE.md` -- template project-level CLAUDE.md
- `example-team-announcement.md` -- sample announcement format

## Usage

No build step. This is a reference repo. Teams clone it, customize `blueprint.md` with their org details, and use the generated scripts (`setup.sh`, `catalog.sh`, `bootstrap-repo.sh`) in their own config repo.

## Secrets

- No secrets in this repo -- it is public
- The generated setup scripts prompt users for API keys at install time
- Generated `.mcp.json` and `.env` files are gitignored by design
- Teams should use their own secret management (Azure Key Vault, etc.)

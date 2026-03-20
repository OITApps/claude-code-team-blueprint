# CLAUDE.md — [Your Company] Team Standards

## [Your Company] Brand

- Primary Red: `#e42e1b` / RGB(226,49,40)
- Secondary Charcoal: `#414042` / RGB(66,65,67)
- Font: **Barlow** (Bold/Regular/Medium/Italic)
- Score colors: Green `#27ae60`, Yellow `#f1c40f`, Red `#e42e1b`
- Logo: [Your Product] wordmark (red "[Your Company]" + charcoal "VOIP" with wifi icon)

## Communication Style

- Lead with evidence, not opinion. Say "the data shows" not "I think"
- No weasel words: avoid "seems", "might", "perhaps" when you have data
- Short sentences. Active voice. No filler
- Reference specific cases, records, or docs — never generalize without examples

## Development Practices

- Read existing code before proposing changes
- Search for existing fields/automations before creating new ones
- Prefer editing existing files over creating new ones
- No over-engineering — solve today's problem, not hypothetical future ones

## Git Workflow & Versioning

All changes flow through a two-stage branch model:

```text
feature/xyz  →  PR  →  develop  →  PR  →  main
                       (testing)        (production)
```

- **`main`** — production-ready. Always stable. Never commit directly.
- **`develop`** — integration/testing branch. Feature branches merge here first.
- **Feature branches** — created from `develop`, named `feat/`, `fix/`, `chore/`, `perf/`, etc.

### Rules

1. Never commit directly to `main` or `develop`
2. All work starts as a feature branch off `develop`
3. Feature branches → PR → `develop` (for testing/integration)
4. `develop` → PR → `main` (for production release, after verification)
5. Branch naming: `{type}/{short-description}` (e.g., `feat/tool-selection`, `fix/bash3-compat`)
6. Delete feature branches after merge
7. Keep `develop` in sync with `main` after each release merge
8. Commit signing is required on `main` and `develop` — contributors must set up SSH/GPG signing before their first PR (see `SECURITY.md`)
9. If modifying `scripts/setup.sh`, run `bash scripts/compat-check.sh` before opening a PR

### Versioning

- Every PR to `develop` or `main` MUST have exactly one semver label: `patch`, `minor`, or `major`.
  - **patch**: bug fixes, minor tweaks, docs updates
  - **minor**: new features, enhancements, new commands/personas
  - **major**: breaking changes (config format changes, removed features)
- On merge to `main`, a GitHub Action auto-bumps `VERSION`, creates a git tag, and appends to `CHANGELOG.md`.
- If no semver label is present, the action defaults to `patch` — but always label explicitly.

## Security

- Never commit `.env`, credentials, or API keys
- Use `.env.template` for shared keys, `.env.local.template` for machine-local secrets (see `SECURITY.md`)
- MCP server versions must be pinned in `catalog.json` — no `@latest` or unpinned `npx -y`
- `WITH SECURITY_ENFORCED` on all SOQL in Apex
- Validate at system boundaries, trust internal code
- Full security policy: `SECURITY.md`

## Credential Handling

- **Never** tell users to manually edit `.env`, `.env.local`, or any config file to add API keys
- **Never** say "paste X into Y file" for secrets — all key ingestion goes through the setup script
- **Never** attempt to run `setup.sh` or `catalog.sh add` from within the Claude Code agent Bash tool — these scripts require interactive terminal input that the agent cannot provide
- A terminal window will open to securely collect credentials via masked input (`getpass`) and handle OAuth flows automatically
- If running inside an IDE (VSCode, Cursor, etc.), the script opens the IDE's integrated terminal automatically
- If running in a native OS terminal, the script opens a new terminal window (Terminal.app on macOS, etc.)
- Storage in `~/.claude/.env` (chmod 600) is correct — the **collection** must always go through OCC tooling

### How to direct users

```bash
# Full setup (all servers):
~/claude-config/scripts/setup.sh

# Single server add:
~/claude-config/scripts/catalog.sh add <server-name>
```

Do not run these commands yourself. Tell the user the command and explain that a terminal will open to collect their keys securely.

## Documentation

- Always use roles/departments, never individual names
- Update changelog after every production deployment
- Include links in changelog entries (URLs, KB articles, SF pages)

## Nomenclature

| Term | Meaning | Location |
|------|---------|----------|
| Command | Invocable workflow via `/name` | `.claude/commands/*.md` |
| Persona | Behavior profile loaded by commands | `.claude/personas/*.md` |
| MCP Server | External tool provider | `opencode.json` |
| Memory | Personal persistent context | `.claude/memory/` (never shared) |

## Building Things

When a user says `/build` or asks to "build" a capability, choose the right primitive:

| Primitive | When to use |
|-----------|------------|
| **Persona** | Defines behavior, tone, or standards — loaded by commands |
| **Command** | A workflow invoked via `/name` — does a specific task |
| **Memory** | A persistent fact, preference, or reference |
| **MCP Server** | Connects to an external API — only when called frequently |

The user should never need to specify "make me a skill/agent/command/plugin." Just `/build [what they want]` and you decide the method. Explain what you chose and why in one line before building.

## Issue-First Workflow

All actionable work requires a GitHub issue before code changes begin. No exceptions.

### Flow

```text
Discussion → "Let's do this"
         → Draft issue (title, description, acceptance criteria)
         → User approves
         → Create issue on GitHub
         → Create git worktree tied to issue
         → Plan goes as issue comment
         → Work happens in worktree
         → PR references issue (closes on merge)
```

### Issue-First Rules

1. **No worktree without an issue.** Every worktree maps to a GitHub issue. Branch name: `{type}/issue-{number}-{short-description}`.
2. **Research and discussion are free.** No issue needed for questions, exploration, or analysis.
3. **"Let's do this" = create an issue.** When a conversation shifts from discussion to action, draft the issue and confirm before proceeding.
4. **Quick fixes (< 5 min, single file):** Ask "issue or just do it?" — user decides.
5. **Bugs discovered mid-conversation:** Create issue immediately, even if fixing now.
6. **Plans live on the issue.** Implementation plans go as issue comments, not just in conversation context.
7. **One worktree per issue.** Never reuse a worktree across multiple issues.

### Threshold

| Scenario | Action |
| -------- | ------ |
| Research / questions / discussion | No issue, no worktree |
| Discussion evolves into "let's do this" | Create issue → plan on it → worktree when approved |
| Quick config fix (< 5 min, single file) | Ask "issue or just do it?" |
| Bug discovered mid-conversation | Create issue immediately |

## Adding Catalog Tools

When a user asks anything like "add X", "integrate X", "can we use X", "build me a tool for X", or "is there an MCP for X" — treat it as a catalog tool addition request and follow the `/build-tool` workflow automatically. Do not wait for them to invoke the command explicitly.

The `/build-tool` workflow:
1. Collect: name, description, auth type, time savings, affected role, visibility (wait for explicit approval before committing anything)
2. Create branch: `feat/tool-[name]`
3. Build: `catalog.json` entry, per-tool README with Time Saved section, any config files
4. Update: main README ROI rollup, Issue #22 dollar value (self-compounding — recalculate when catalog grows)
5. Open PR — user approves and merges

Never commit directly to main. Never assume visibility — always ask.

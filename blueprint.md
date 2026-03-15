# Build Your Own Claude Code Team Configuration

A step-by-step guide to building a shared Claude Code setup for your company — personas, commands, plugins, MCP servers, security, and onboarding — all managed from a single GitHub repo.

---

## What You'll Build

- A **shared config repo** your team clones once and runs a setup script
- **AI personas** trained on your company's workflows and standards
- **Slash commands** that trigger specific workflows
- An **admin-controlled catalog** of plugins and MCP servers
- **Auto-discovery** — any team repo can propose new tools, admins approve via PR
- **One-time announcements** that display when the team syncs updates
- **Security by default** — branch protection, secret scanning, PR requirements, no committed secrets

---

## System Prompt

Paste this into Claude Code. Replace the bracketed placeholders with your details.

```
I want to build a shared Claude Code configuration repo for my team at [COMPANY NAME].
We use GitHub org [GITHUB_ORG] and have [NUMBER] team members.

Build me:

1. A GitHub repo called [GITHUB_ORG]/claude-config with:
   - catalog.json — admin-controlled list of approved plugins and MCP servers, with setupInstructions per entry telling users how to get each API key
   - scripts/setup.sh — first-run onboarding that copies personas/commands, enables recommended plugins, prompts for API keys, generates .mcp.json and .env and .claude/settings.local.json
   - scripts/catalog.sh — interactive post-setup manager to browse, enable/disable plugins and MCP servers, configure keys, with --list and --sync flags
   - scripts/bootstrap-repo.sh — apply security standards (branch protection, secret scanning, push protection, Dependabot, CODEOWNERS, PR template) to any new org repo
   - scripts/sync-catalog.sh — scan all org repos for .claude-catalog-entry.json files and create a PR to update catalog.json (new entries default to recommended: false)
   - scripts/check-announcements.sh — display unread announcements from announcements.json once per user, tracked via local .claude/.announcements-seen
   - announcements.json — admin-managed one-time messages shown when setup or catalog runs
   - .github/workflows/secret-scan.yml — TruffleHog on every push and PR
   - .github/workflows/catalog-sync.yml — weekly scan of org repos for new catalog entries, creates PR for admin approval
   - .github/pull_request_template.md
   - CODEOWNERS
   - README.md with: features, benefits by role, use cases table, access request flow, Claude Code install instructions, prerequisites, setup steps, API key sources, catalog management, how to request new tools (Path A: .claude-catalog-entry.json in your repo, Path B: PR catalog.json directly), field reference for catalog entries, nomenclature table
   - docs/team-announcement.md — editable announcement template for sharing with the team

2. Personas in .claude/personas/ — AI behavior profiles for our key workflows.
   Each persona should be:
   - Under 100 lines
   - Focused on rules, standards, and decision-making criteria — not verbose descriptions
   - Named after a memorable character
   - Loaded by commands on demand, not always in context

   Our key workflows are: [DESCRIBE YOUR WORKFLOWS]
   Examples:
   - "Customer support with SLA tracking in Zendesk"
   - "Salesforce administration and flow development"
   - "Documentation in Confluence and Notion"
   - "Internal tools in Python/TypeScript"
   - "DevOps with AWS and Terraform"

3. Commands in .claude/commands/ — slash commands that load a persona and execute a task.
   Each command should:
   - Load its persona file at the top
   - Define clear inputs ($ARGUMENTS or specific data to query)
   - Have a structured output format
   - Be a real .claude/commands/*.md file

4. A routing table in .claude/personas/PERSONAS.md mapping triggers to the correct persona and command

5. Branch protection on main:
   - Require 1 PR approval before merge
   - Dismiss stale reviews on new pushes
   - Restrict direct push to admin users: [LIST ADMIN GITHUB USERNAMES]
   - Do NOT enforce for admins (emergency bypass)

6. GitHub security:
   - Secret scanning + push protection enabled
   - Dependabot vulnerability alerts enabled

7. Consistent nomenclature everywhere:
   - "Command" = invocable workflow via /name (.claude/commands/*.md)
   - "Persona" = behavior profile loaded by commands (.claude/personas/*.md)
   - "MCP Server" = external tool provider (.mcp.json, never committed)
   - "Plugin" = Claude Code extension from official registry
   - "Catalog" = approved plugins & MCPs for the team (catalog.json)
   - "Memory" = personal persistent context (.claude/memory/, never shared)

8. Security rules:
   - .env, .mcp.json, .claude/settings.local.json, .claude/memory/ in .gitignore
   - API keys in .env (chmod 600), referenced by .mcp.json
   - .env.template with placeholder values is committed (no real secrets)
   - No secrets in catalog.json — only key names and setupInstructions
   - Keys requiring admin provisioning should say "Email [ADMIN_EMAIL]"
   - Self-service keys should have step-by-step instructions

MCP servers we use: [LIST YOUR SERVICES AND THEIR MCP PACKAGES IF KNOWN]
Examples:
- Salesforce (npx @salesforce/mcp)
- Slack (npx @anthropic-ai/mcp-slack)
- GitHub (npx @anthropic-ai/mcp-github)
- PostgreSQL (npx @anthropic-ai/mcp-postgres)
- ClickUp (npx @taazkareem/clickup-mcp-server)
- Notion (Claude Code plugin)
- Jira (custom MCP or WebFetch)

Plugins to include in catalog (mark recommended or optional):
[LIST SPECIFIC PLUGINS OR SAY "use your judgment based on our workflows"]
Commonly recommended: superpowers, feature-dev, commit-commands, code-review,
security-guidance, claude-md-management, playwright, context7

Admin GitHub usernames who can push to main: [LIST USERNAMES]
Admin email for API key requests: [EMAIL]
Team support channel: [e.g. "#ai-tools in Slack", "Tech Team > AI Launchpad in Teams"]
```

---

## After Initial Build

Use these follow-up prompts as needed:

### Add a new persona
```
Create a new persona for [ROLE/WORKFLOW]. They should:
- [Key responsibility 1]
- [Key responsibility 2]
- [Standards they enforce]

Create the persona file in .claude/personas/ and at least 2 commands
in .claude/commands/. Update PERSONAS.md routing table.
Push to the claude-config repo.
```

### Add an MCP server to the catalog
```
Add [SERVICE_NAME] to our claude-config catalog.json.
- NPM package: [PACKAGE_NAME] (or "build a custom one")
- Required keys: [LIST API KEYS NEEDED]
- Category: core/optional
- Recommended: true/false
- Include setupInstructions for each key
Push to the repo.
```

### Apply security to a new repo
```
Run our bootstrap-repo.sh against [ORG/REPO-NAME] to apply our
security standards (branch protection, secret scanning, CODEOWNERS,
PR template, TruffleHog CI).
```

### Add an announcement
```
Add an announcement to our claude-config announcements.json:
Title: [TITLE]
Message: [MESSAGE]
Push to the repo.
```

### Onboard a new team member
```
Walk me through onboarding [NAME] to our Claude Code setup.
They need GitHub org access, Claude Code license, and API keys for [SERVICES].
```

---

## Architecture

```
your-org/claude-config (admin-controlled)
├── catalog.json              ← source of truth for all tools
├── announcements.json        ← one-time team messages
├── .claude/
│   ├── personas/*.md         ← behavior profiles
│   └── commands/*.md         ← slash commands
├── scripts/
│   ├── setup.sh              ← first-run onboarding
│   ├── catalog.sh            ← manage tools post-setup
│   ├── bootstrap-repo.sh     ← secure new repos
│   ├── sync-catalog.sh       ← auto-discover tools from org repos
│   └── check-announcements.sh
└── .github/workflows/
    ├── secret-scan.yml       ← TruffleHog on every push
    └── catalog-sync.yml      ← weekly tool discovery → PR

your-org/any-project
├── .claude/
│   ├── personas/             ← copied from claude-config
│   ├── commands/             ← copied from claude-config
│   ├── settings.local.json   ← local, gitignored
│   └── .announcements-seen   ← local, gitignored
├── .mcp.json                 ← local, gitignored (has secrets)
├── .env                      ← local, gitignored (has secrets)
├── .env.template             ← committed (no secrets)
└── CLAUDE.md                 ← project-specific instructions

your-org/some-mcp-server
└── .claude-catalog-entry.json  ← auto-discovered weekly by sync
```

---

## Design Decisions

| Decision | Why |
|----------|-----|
| Personas under 100 lines | Token efficiency — they load into context on every command |
| Commands as real .md files | Claude Code discovers them natively, tab-complete works |
| catalog.json, not auto-install | Admin control — nothing enters the toolkit without review |
| .mcp.json gitignored | Contains API keys — each user generates their own via setup.sh |
| Announcements with seen-tracking | One-time display prevents notification fatigue |
| bootstrap-repo.sh | Consistent security across all repos without manual config |
| Weekly sync, not real-time | Batches new tool proposals into manageable weekly PRs |
| New entries default to recommended: false | Admins explicitly promote tools after review |

---

## Tips

- **Start small** — 2-3 personas and 5-6 commands. Add more as workflows emerge.
- **Keep personas lean** — rules and standards only. No backstory or filler.
- **Test commands yourself** before rolling out to the team.
- **Use the announcement system** for changes — don't assume the team reads the README.
- **Review the catalog weekly** — the sync PR is your curation checkpoint.
- **Rotate API keys** on a schedule — the .env pattern makes this painless.
- **.claude/memory/ is personal** — never include it in the shared config.
- **One setup.sh run** should get someone from zero to working in under 5 minutes.

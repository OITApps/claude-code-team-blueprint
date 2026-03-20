# Claude Code Team Commander

**A complete playbook for building a shared Claude Code configuration for your company.**

## The Problem

When you give your team Claude Code, everyone sets it up differently. Different plugins, different prompts, no shared standards, API keys scattered everywhere, and no way to control what tools are available. New hires spend hours figuring out the setup instead of doing work.

## What We Built

At [OIT, LLC](https://oit.co), we run a VoIP business with a Salesforce org, internal knowledge base, VoIP platform APIs, Microsoft 365, and a growing team. We needed Claude Code to work the same way for everyone — with our SOPs, our quality standards, and our integrations baked in — while keeping secrets secure and giving admins control over what tools the team can use.

We built a single GitHub repo that does all of this:

- **5-minute onboarding** — one script installs everything and prompts for API keys
- **AI personas** that know our workflows — case quality scoring, Salesforce automation, documentation standards, support ticket handling, full-stack development
- **18 slash commands** that trigger specific workflows — `/stan-review 222448` scores a case against 8 quality dimensions, `/flow-review Lead_Assignment` audits a Salesforce flow for governor limits
- **Admin-controlled catalog** of plugins and MCP servers — nothing enters the toolkit without a PR approval
- **Auto-discovery** — any team repo can propose a new MCP server by adding a `.claude-catalog-entry.json` file; a weekly GitHub Action scans for these and creates a PR for admin review
- **Announcement system** — admins post one-time messages that display the next time a team member syncs
- **Security by default** — API keys never committed, secret scanning with push protection, branch protection requiring PR approval, TruffleHog CI on every push

### How It Works

```
1. Team member clones the config repo
2. Runs setup.sh in their project directory
3. Script copies personas/commands, enables recommended plugins,
   prompts for API keys, generates .mcp.json and .env
4. Restart Claude Code — everything works

Later:
- catalog.sh to browse/toggle plugins and MCP servers
- git pull + setup.sh to get updates
- Announcements display automatically on sync
```

### Architecture

```
your-org/claude-config (admin-controlled)
├── catalog.json              ← approved plugins & MCP servers
├── announcements.json        ← one-time team messages
├── .claude/
│   ├── personas/*.md         ← behavior profiles (<100 lines each)
│   └── commands/*.md         ← slash commands
├── scripts/
│   ├── setup.sh              ← first-run onboarding
│   ├── catalog.sh            ← interactive tool manager
│   ├── bootstrap-repo.sh     ← apply security to new repos
│   ├── sync-catalog.sh       ← auto-discover tools from org repos
│   └── check-announcements.sh
└── .github/workflows/
    ├── secret-scan.yml       ← TruffleHog on every push
    └── catalog-sync.yml      ← weekly tool discovery → PR

your-org/any-project
├── .claude/personas/         ← copied from config repo
├── .claude/commands/         ← copied from config repo
├── .mcp.json                 ← generated locally (gitignored, has secrets)
├── .env                      ← generated locally (gitignored, has secrets)
└── CLAUDE.md                 ← project-specific instructions

your-org/some-mcp-server
└── .claude-catalog-entry.json  ← discovered weekly by catalog sync
```

## Build Your Own

The [blueprint](blueprint.md) contains a complete system prompt you can paste into Claude Code to build the same setup for your company. Fill in your company name, GitHub org, workflows, MCP servers, and admin users — Claude Code builds everything.

**What the system prompt creates:**

| Component | What it does |
|-----------|-------------|
| `catalog.json` | Admin-controlled list of plugins and MCP servers with setup instructions per tool |
| `setup.sh` | First-run script: copies config, enables plugins, prompts for keys, generates local files |
| `catalog.sh` | Interactive manager to browse, enable/disable tools after initial setup |
| `bootstrap-repo.sh` | Applies branch protection, secret scanning, CODEOWNERS, PR template to any new repo |
| `sync-catalog.sh` | Scans org repos for `.claude-catalog-entry.json` and creates PRs for new tools |
| `check-announcements.sh` | Displays admin announcements once per user |
| `announcements.json` | One-time messages shown on setup/catalog runs |
| Secret scan workflow | TruffleHog on every push and PR |
| Catalog sync workflow | Weekly scan for new tools, creates PR for admin review |
| Personas | AI behavior profiles under 100 lines, loaded on demand by commands |
| Commands | Real `.claude/commands/*.md` files with tab-complete support |
| Branch protection | 1 approval required, restricted pushers, stale review dismissal |


## The `/build` Command

One thing we learned early: team members shouldn't need to know the difference between a persona, command, memory entry, or MCP server. They just want to build something.

Add this to your team's `CLAUDE.md`:

```markdown
## Building Things

When a user says `/build` or asks to "build" a capability, choose the right primitive:

| Primitive | When to use |
|-----------|------------|
| **Persona** | Defines behavior, tone, or standards — loaded by commands |
| **Command** | A workflow invoked via `/name` — does a specific task |
| **Memory** | A persistent fact, preference, or reference |
| **MCP Server** | Connects to an external API — only when called frequently |

The user should never need to specify "make me a skill/agent/command/plugin."
Just `/build [what they want]` and you decide the method.
Explain what you chose and why in one line before building.
```

Now anyone on the team can say:

```
/build a way to check project status before standup
/build a persona that writes in our brand voice
/build something that pulls metrics from our dashboard weekly
```

Claude picks the right primitive and explains the choice before building it.

## Key Design Decisions

| Decision | Why |
|----------|-----|
| Personas under 100 lines | Token efficiency — they load into every command's context |
| Commands as real .md files | Claude Code discovers them natively with tab-complete |
| catalog.json, not auto-install | Admin control — nothing enters without review |
| .mcp.json gitignored | Contains API keys — each user generates their own |
| New catalog entries default to recommended: false | Admins explicitly promote after review |
| Weekly sync, not real-time | Batches proposals into manageable PRs |
| Announcements with seen-tracking | One-time display prevents fatigue |
| bootstrap-repo.sh | Consistent security without manual setup |

## Nomenclature

We standardized on these terms to eliminate confusion:

| Term | Meaning | Location |
|------|---------|----------|
| **Command** | Invocable workflow via `/name` | `.claude/commands/*.md` |
| **Persona** | Behavior profile loaded by commands | `.claude/personas/*.md` |
| **MCP Server** | External tool provider | `.mcp.json` (local, never committed) |
| **Plugin** | Claude Code extension from official registry | `.claude/settings.local.json` |
| **Catalog** | Approved plugins & MCPs for the team | `catalog.json` |
| **Memory** | Personal persistent context | `.claude/memory/` (never shared) |


## Staying Up to Date

This blueprint is actively maintained. As we build new features into our private team configuration at OIT, we sanitize and publish them here so the community benefits. Company names, API keys, internal URLs, and employee names are stripped automatically before publishing.

Recent additions synced from our live setup:
- `/build` universal builder — team members describe what they want, Claude picks the right primitive
- Announcement system — admins post one-time messages that display on next sync
- Auto-discovery pipeline — repos self-register tools via `.claude-catalog-entry.json`
- Per-tool setup instructions in the catalog — step-by-step key provisioning
- Publish script with sanitization — how we sync private → public without leaking company info

When we add something new, it lands here. Watch or star the repo to get notified.

## Getting Started

1. Read the [blueprint](blueprint.md)
2. Copy the system prompt
3. Replace the `[BRACKETED PLACEHOLDERS]` with your company details
4. Paste into Claude Code
5. Follow up with the provided prompts to add personas, MCP servers, announcements, and onboard team members

## Tips

- **Start small** — 2-3 personas and 5-6 commands. Add more as workflows emerge.
- **Keep personas lean** — rules and standards only. No backstory or filler.
- **Test commands yourself** before rolling out.
- **Use announcements** for changes — don't assume the team reads the README.
- **Review the catalog weekly** — the sync PR is your curation checkpoint.
- **.claude/memory/ is personal** — never share it in the config repo.
- **One setup.sh run** should get someone from zero to working in under 5 minutes.

## About

Built by [Ray Orsini](https://github.com/oitray) at [OIT, LLC](https://oit.co) with Claude Code. We run VoIP business operations on Salesforce and needed a way to give our whole team consistent, secure, admin-controlled AI tooling.

This is shared freely. Take it, adapt it, make it yours.

## License

MIT

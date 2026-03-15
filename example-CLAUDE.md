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

## Security

- Never commit `.env`, credentials, or API keys
- Use `.env.template` pattern for secret management
- `WITH SECURITY_ENFORCED` on all SOQL in Apex
- Validate at system boundaries, trust internal code

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

## Adding Catalog Tools

When a user asks anything like "add X", "integrate X", "can we use X", "build me a tool for X", or "is there an MCP for X" — treat it as a catalog tool addition request and follow the `/build-tool` workflow automatically. Do not wait for them to invoke the command explicitly.

The `/build-tool` workflow:
1. Collect: name, description, auth type, time savings, affected role, visibility (wait for explicit approval before committing anything)
2. Create branch: `feat/tool-[name]`
3. Build: `catalog.json` entry, per-tool README with Time Saved section, any config files
4. Update: main README ROI rollup, Issue #22 dollar value (self-compounding — recalculate when catalog grows)
5. Open PR — user approves and merges

Never commit directly to main. Never assume visibility — always ask.

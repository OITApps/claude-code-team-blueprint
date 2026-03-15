# Claude Code — Available for the Team

> **Admins**: Update this document as the setup evolves. This is the announcement to share when inviting team members.

---

**Claude Code is now available for the team.** It's an AI assistant that works inside your terminal and IDE — it can query Salesforce, search our knowledge base, review cases, debug flows, draft responses, and more using natural language. We've built a shared configuration with [Your Company]-specific tools so setup is fast and everyone gets the same experience.

You're invited to try it out. Here's how to get started.

## Step 1: Get Access

Claude Code requires a license (Claude Pro, Team, or Enterprise plan).

1. Get your manager's approval
2. Email **[admin-email@your-domain.com]** with your manager copied
3. Subject: **"Claude Code Access Request"**
4. Include your name and role

You'll receive an Anthropic account invitation once approved.

## Step 2: Install Claude Code

```bash
brew install claude-code        # macOS via Homebrew
# or: npm install -g @anthropic-ai/claude-code

claude --version                # Verify install
```

On first run, Claude Code opens a browser to authenticate with your Anthropic account.

**VS Code users:** Also install the "Claude Code" extension from the marketplace.

## Step 3: Install Prerequisites

```bash
# Node.js (v18+ required for MCP servers)
node --version          # Check
brew install node       # Install if missing

# Salesforce CLI
sf --version            # Check
npm install -g @salesforce/cli  # Install if missing
sf org login web        # Authenticate

# GitHub SSH access
ssh -T git@github.com   # Test — ask Ray/Jack if this fails
```

You also need access to the `[YourGitHubOrg]` GitHub organization. If you can't clone [YourGitHubOrg] repos, ask [Admin 1] or [Admin 2] to add you.

## Step 4: Run Setup (5 minutes)

```bash
git clone git@github.com:[YourGitHubOrg]/claude-config.git ~/claude-config
cd ~/Projects/Salesforce
~/claude-config/scripts/setup.sh .
```

The script installs personas, commands, plugins, and walks you through API keys. Skip any you don't have yet.

**Restart Claude Code after setup.**

## Step 5: Try It Out

| What you want to do | What to type |
|---------------------|-------------|
| Review a case against SOPs | `/stan-review 222448` |
| Auto-fix case standardization | `/stan-fix 222448` |
| Debug a Salesforce flow | `/flow-review Lead_Assignment` |
| Analyze a support ticket | `/holly-analyze 334501` |
| Draft a client response | `/holly-draft-response 334501` |
| Create or update a KB article | `/docs-update VoIP Failover` |
| Query Salesforce | "Show me all open GSD cases for RevOps" |
| Search VoIP docs | "How do we configure call recording?" |
| Pull call records | "Get CDRs for extension 1001, last 7 days" |

## API Keys

The setup script will prompt for these. Email **[admin-email@your-domain.com]** to request any keys you need.

| Key | Where to get it |
|-----|-----------------|
| Salesforce org | `sf org login web` (self-service) |
| KB_PLATFORM_API_KEY | [admin-email@your-domain.com] |
| PLATFORM_API_TOKEN | [admin-email@your-domain.com] |
| MS365 credentials | [admin-email@your-domain.com] |

## After Setup

**Manage your plugins and MCP servers:**
```bash
~/claude-config/scripts/catalog.sh .
```

**Get updates when new tools are added:**
```bash
cd ~/claude-config && git pull
~/claude-config/scripts/setup.sh .
```

**Want to add a tool to the catalog?** Add a `.claude-catalog-entry.json` to your [YourGitHubOrg] repo — details in the [README](https://github.com/[YourGitHubOrg]/claude-config#requesting-a-new-plugin-or-mcp-server). An admin reviews and approves before it's available.

## Need Help?

- Post in **[Your support channel]**
- Claude Code docs — [claude.ai/code](https://claude.ai/code)

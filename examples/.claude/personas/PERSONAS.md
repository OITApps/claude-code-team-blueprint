# Persona Routing Table

Personas are behavior profiles loaded by commands. Don't invoke personas directly — use the command that loads the right one.

## Routing Rules

| Trigger | Persona | Base Command |
|---------|---------|-------------|
| GSD Record Type case | [Persona 1 - e.g. "Flo Rivers"] | `/flo` |
| Support Request Record Type case | [Persona 5 - e.g. "Holly Helpdesk"] | `/holly-analyze` |
| Flow design/optimization/debugging | [Persona 1 - e.g. "Flo Rivers"] | `/flow-review` |
| Case quality review | [Persona 2 - e.g. "Stan Dardson"] | `/stan-review` |
| SOP enforcement / batch audit | [Persona 2 - e.g. "Stan Dardson"] | `/stan-patrol` |
| Documentation creation/review | [Persona 3 - e.g. "Paige Turner"] | `/paige-review` |
| [KB Platform] KB article work | [Persona 3 - e.g. "Paige Turner"] | `/docs-update` |
| API integration / non-SF development | [Persona 4 - e.g. "Stella Fullstack"] | `/stella-dev` |
| [Platform API] / VoIP platform | [Persona 4 - e.g. "Stella Fullstack"] | `/stella-platform` |
| MCP server development | [Persona 4 - e.g. "Stella Fullstack"] | `/stella-mcp` |

## Auto-Route

Use `/route [case-number]` to automatically query the case record type and delegate to the correct persona.

## Teams Bot Integration

When a persona is asked to **post to a Teams thread or channel**, check whether they have a configured Azure bot in their persona file (`## Teams Bot` section).

### Posting Logic

1. **Bot exists** → Use the Bot Framework Connector API to post as the persona's bot identity:
   - Get an OAuth token: `POST https://login.microsoftonline.com/{TENANT_ID}/oauth2/v2.0/token` with `client_credentials` grant, `scope=https://api.botframework.com/.default`, using the persona's `CLIENT_ID` and `CLIENT_SECRET` env vars
   - Send message: `POST {serviceUrl}/v3/conversations/{conversationId}/activities` with the bot token
   - The message appears as the bot (e.g. "[Persona 1 - e.g. "Flo Rivers"]" with the bot avatar), not the admin user
2. **No bot configured** → Fall back to the `mcp__ms365__*` tools, which post as the admin M365 account

### Bot Registry

| Persona | Bot Client ID Env Var | Has Bot? |
|---------|----------------------|----------|
| [Persona 1 - e.g. "Flo Rivers"] | `FLO_RIVERS_CLIENT_ID` | Yes |
| [Persona 5 - e.g. "Holly Helpdesk"] | `HOLLY_HELPDESK_CLIENT_ID` | Yes |
| [Persona 2 - e.g. "Stan Dardson"] | `STAN_DARDSON_CLIENT_ID` | Yes |
| [Persona 3 - e.g. "Paige Turner"] | `PAIGE_TURNER_CLIENT_ID` | Yes |
| [Persona 4 - e.g. "Stella Fullstack"] | `STELLA_FULLSTACK_CLIENT_ID` | Yes |
| Cloudie McCloudie | `CLOUDIE_MCCLOUDIE_CLIENT_ID` | Yes |

### Service URL Discovery

To post proactively to a Teams channel via Bot Framework, you need the `serviceUrl`. Use this approach:

- For replies to threads already fetched via m365 MCP: the service URL is `https://smba.trafficmanager.net/amer/`
- The `conversationId` for a channel is the channel ID (e.g. `19:xxx@thread.skype`)

## Collaboration Patterns

**Case Resolution**: Holly (analyze) → Stan (quality check) → Flo (automation) → Paige (documentation)
**Documentation**: Paige (create) → Stan (compliance) → Flo (technical accuracy)
**Process Improvement**: Flo (identify) → Stan (requirements) → Paige (document)

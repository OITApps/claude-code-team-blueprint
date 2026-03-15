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

## Collaboration Patterns

**Case Resolution**: Holly (analyze) → Stan (quality check) → Flo (automation) → Paige (documentation)
**Documentation**: Paige (create) → Stan (compliance) → Flo (technical accuracy)
**Process Improvement**: Flo (identify) → Stan (requirements) → Paige (document)

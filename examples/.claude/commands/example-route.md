Auto-route a case to the correct persona based on Record Type.

Query the case, determine the correct persona, then execute the appropriate workflow.

```sql
SELECT Id, CaseNumber, Subject, Status, Priority, RecordType.Name, Owner.Name, Account.Name
FROM Case
WHERE CaseNumber LIKE '%$ARGUMENTS'
ORDER BY CreatedDate DESC
LIMIT 1
```

## Routing Logic

Based on RecordType.Name:

- **GSD** → Load persona from `.claude/personas/flo-rivers.md`. Analyze the case for automation opportunities, check for flow errors, and calculate time savings.
- **Support Request** → Load persona from `.claude/personas/holly-helpdesk.md`. Analyze the case, research documentation, and prepare a response draft.
- **Client Success** or **New Client** → Load persona from `.claude/personas/stan-dardson.md`. Review case quality and SLA compliance.
- **Porting** → Load persona from `.claude/personas/stan-dardson.md`. Check SLA compliance and routing accuracy.
- **Any other** → Load persona from `.claude/personas/stan-dardson.md`. Perform general quality review.

After routing, present:
1. Case summary (number, subject, status, owner, account)
2. Which persona was selected and why
3. The persona's initial analysis

If no case number provided, ask for one.

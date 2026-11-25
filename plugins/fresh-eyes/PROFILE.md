# Project profile

The plugin's skills and agents hold the method. Everything about one project goes in a profile: a markdown file at `.claude/fresh-eyes.md`, in the repo root or in a parent folder that holds several repos side by side.

A repo is covered by the nearest profile at or above it. Covered repos get the commit gate. A repo with no profile above it is left alone.

Every section is optional. A missing section means the default named in the skill or agent that reads it.

## Format

```markdown
---
commit-gate: on
---

# <Project> profile

## Repos

| Repo | Path | Base branch | Notes |
|---|---|---|---|
| api | api | origin/develop | backend |
| web | web | origin/develop | frontend, cannot import from api |
| infra | infra | origin/main | |

Worktrees are sibling folders created with `git worktree`.
Pull requests are squash-merged.

## Docs

- Feature folder: `docs/features/<ticket-id>-<short-desc>/`
- Spec docs: `*.brd.md` (requirements), `*.design.md` (design)
- Ledger: `<feature folder>/<name>.decisions.md`

## Checks

May run: `npm run typecheck`, `npm test -- <file>`, `npm run lint`
Never run: `npm install`, migrations, anything that writes to a database

## Machine checks

| Kind | Repos | Command | Report |
|---|---|---|---|
| static | api, web | `<command with <repo>, <base>, <out> placeholders>` | `<out>/report.json` |

Reports go under `~/.cache/<project>/review/<feature>/round-<N>/<repo>/`.
What each report's fields mean, how to accept a finding in the tool, how to confirm a mutation kill, and what to do when a tool is not installed go here too.

## Review focus

- Tenancy: every query on customer data is scoped to the caller's organisation.
- Money is stored in minor units; flag any float arithmetic on amounts.

## Code search

- Source folders: `apps`, `packages`
- Language: TypeScript (`-t ts`), tests are `*.spec.ts`
- Skip: `dist`, `node_modules`, `.next`, generated clients, migrations

## Commits

- One short imperative subject line; a body only when the why isn't obvious.
- The loop commits but never pushes.

## Conventions

- Each repo's `CLAUDE.md`
- Comments: few, one line, only for a non-obvious why

## QA

- Ticket tracker: how to read a ticket (tools or command), with its comments, attachments and images; how to download an attachment or image to a file, when the tracker allows it; how to upload an image and post a comment
- Changes: how to find a ticket's pull requests (for example `gh pr list --search <ticket> --state all` in each repo)
- QA ledger: `<feature folder>/<name>.qa.md`; case file: `<name>-cases.json` next to it
- UI test engine: its MCP server, the folder its commands run in, its read command (`npm run -s read -- …`), where a run's directory is (for example `~/.witness/runs/<runId>`), the command that starts its worker for a scratch MCP client, and its docs. The loop is written against the witness engine's steps runner, MCP tools and commands (`steps`, `qa-md`, `promote`, `read`); another engine needs the same ones
- Engine skills: the skill to test with and the skill to add a missing tool, each with the path of its `SKILL.md`
- Environments: which the loop may use, how it picks one, which are never used
- Actors: the test accounts' roles
- Results comment: where the layout for posting results on a ticket is
- Viewer: how to start it and the link to a ticket's page
```

## What reads what

| Section | Read by |
|---|---|
| `commit-gate` | the commit gate hook; `off` disables it for every repo the profile covers |
| Repos | review-loop, code-reviewer, code-search, `where-symbol` (for the root folder) |
| Docs | review-loop |
| Checks | review-loop, code-reviewer |
| Machine checks | review-loop, code-reviewer (report field meanings) |
| Review focus | code-reviewer |
| Code search | code-search |
| Commits | review-loop |
| Conventions | review-loop, code-reviewer |
| QA | qa-loop, qa-validator |

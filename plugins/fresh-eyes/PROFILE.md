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

## Recipes

Profile text for the tools the loops were built with, to copy and adapt. `<tools>` is the folder the tools are cloned into, each set up with `npm install`; `<dir>` is the report folder, `~/.cache/<project>/review/<feature>/round-<N>/<repo>/`, created first. `<repo path>` is the repo's checkout (or worktree) folder.

### Machine checks: tangle, weakspot and the figma-ui-spec guard

```markdown
## Machine checks

| Kind | Repos | Tool |
|---|---|---|
| static | all | [tangle-ts](https://github.com/sshdaemon/tangle-ts) in `<tools>/tangle-ts` |
| mutation | api, web | [weakspot-ts](https://github.com/sshdaemon/weakspot-ts) in `<tools>/weakspot-ts` |
| shared-code | web | the guard of [figma-ui-spec](https://github.com/sshdaemon/figma-ui-spec) in `<tools>/figma-ui-spec` |

Run them in this order. A tool without its `node_modules` is not installed: say so and go on without it.

**tangle**

1. Change list: `node <tools>/tangle-ts/bin/tangle.js changes --repo <repo path> --base <base> --out <dir>/changes.json`. For a merged feature, `--base <squash>^ --head <squash>`, and tell the reviewer that tangle's lines refer to that commit.
2. Run: `node <tools>/tangle-ts/bin/tangle.js diff --changes <dir>/changes.json --out <dir> --quiet`. Report: `<dir>/report.json`; findings accepted earlier sit under `accepted`, so the reviewer reads only `findings`. A non-zero exit is a failed run.
3. Accept a finding left as is or rejected: `node <tools>/tangle-ts/bin/tangle.js accept <tg-id> --repo <repo path> --reason "<ledger id>: <reason>"`; `node <tools>/tangle-ts/bin/tangle.js unaccept <tg-id> --repo <repo path>` reverses it.
4. Reading it: each finding names a rule, a function and a `tg-…` id, and complexity rules give the score before and after (`before: null` is new code). tangle's own severity is a hint, not the severity to report.

**weakspot**

1. Without a config it runs its defaults (the unit lane, specs found by their imports). A repo whose tests need more (other lanes, a spec map, skip patterns) has its config in `~/.weakspot/repos/<name>.json`, where `<name>` is the repository's name on its origin remote (the folder's name when it has none); if such a repo has none, skip the check and say so.
2. Run in the background, on tangle's change list: `node <tools>/weakspot-ts/bin/weakspot.js diff --changes <dir>/changes.json --out <dir>/weakspot --quiet`, adding `--lanes unit` where other lanes write to shared test databases. Report: `<dir>/weakspot/report.json`. Exit 0 and 1 are completed runs (no findings, findings); 2 is a wrong command or config, 3 a run that could not complete.
3. Confirm a kill after adding a test: `node <tools>/weakspot-ts/bin/weakspot.js files <file>:<start>-<end> --repo <repo path> --quiet`.
4. Accept a survivor or untested file left as is: `node <tools>/weakspot-ts/bin/weakspot.js accept <id> --repo <repo path> --reason "<ledger id>: <reason>"`; `node <tools>/weakspot-ts/bin/weakspot.js accept <id> --repo <repo path> --revoke` reverses it.
5. Skip it for an already merged feature and tell the reviewer there is no mutation report.
6. Reading it: each finding is a mutant of changed code no test noticed (`weakAssertion`, `noCoverage`, `static`) or a changed file no test reaches (`untested`), with the lane that ran it.

**shared-code guard**

1. Run: `node <tools>/figma-ui-spec/bin/figma-ui-spec.js guard --repo <project> --root <repo path> --diff $(git -C <repo path> merge-base <base> HEAD) --json > <dir>/guard.json`. A single ref compares it with the working tree, so uncommitted and staged changes are checked too; `<base>...HEAD` would see only commits. For a merged feature, `--diff <squash>^..<squash>`. The project's config, `.repos/<project>/config.json` in the tool's checkout, says which paths are shared and where the specs are.
2. Exit 0 and 1 with a JSON report are completed runs; exit 2, or exit 1 with an empty report (the error is on stderr), is a failed run.
3. Reading it: each finding is a change to a shared component (`kind: file`) or a theme variable (`kind: token`, old and new value) that no spec decision allows; changes a decision allows are under `covered`. Give the reviewer the feature's spec when there is one.
```

### QA: an app tested with witness

```markdown
## QA

- UI test engine: the app's MCP server, built on [witness](https://github.com/sshdaemon/witness); commands run in the app's checkout: `npm run steps` (runner), `npm run qa-md` (ledger tables), `npm run promote` (regression suites). Read runs with `npm --prefix <app checkout> run -s read -- …` (fields in `node_modules/witness/docs/read-contract.md`); a run's folder is `~/.witness/runs/<runId>`. A scratch MCP client (when a reconnect doesn't load a new tool) starts the app's worker with `npx tsx <worker file>` (the file the app's runner entry passes to `runCli`), with its working folder set to the app's checkout and `env: process.env` on the stdio transport, and calls tools the way `connect()` and `call()` in `node_modules/witness/src/cli/steps.ts` do.
- Engine skills: the app's own skills, each starting from `node_modules/witness/docs/method/testing.md` and `tools.md`, with the path of each `SKILL.md`.
- Viewer: `npm run ui` in the app's checkout, in the background unless port 4477 already answers; a ticket's page is `http://127.0.0.1:4477/#/ticket/<ticket>`.
```

The rest of the QA section (tracker, environments, actors, results comment) is the project's own.

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

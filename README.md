# workbench

Engineering tools and skills for Claude Code, packaged as plugins. Install only the ones a project needs.

| Plugin | What it gives |
|---|---|
| [fresh-eyes](plugins/fresh-eyes/README.md) | Review and QA loops with fresh-context checkers, a decisions ledger and a commit gate, plus a read-only code search agent |
| [no-sleep](plugins/no-sleep/README.md) | A hook that stops waiting by sleeping or polling in the foreground, and points at background commands and Monitor instead |

## Works with

The loops call these tools when a project's profile names them. tangle-ts, weakspot-ts and figma-ui-spec are cloned and set up with `npm install`; witness is installed in the app that uses it. [PROFILE.md](plugins/fresh-eyes/PROFILE.md#recipes) has the profile text for each.

| Tool | Used by |
|---|---|
| [tangle-ts](https://github.com/sshdaemon/tangle-ts): complexity and logic smells on changed lines | review-loop, static check |
| [weakspot-ts](https://github.com/sshdaemon/weakspot-ts): mutation testing on changed lines | review-loop, mutation check |
| [figma-ui-spec](https://github.com/sshdaemon/figma-ui-spec): Figma design to build spec, shared-component guard | review-loop, shared-code check |
| [witness](https://github.com/sshdaemon/witness): testing a web app through its real UI over MCP | qa-loop |

## Install

Add the marketplace once, then install a plugin from it:

```bash
claude plugin marketplace add sshdaemon/workbench
```

```bash
claude plugin install fresh-eyes@workbench
```

```bash
claude plugin install no-sleep@workbench
```

From a local checkout, pass its path instead of `sshdaemon/workbench`.

## Licence

MIT

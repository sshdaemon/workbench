# workbench

Engineering tools and skills for Claude Code, packaged as plugins. Install only the ones a project needs.

| Plugin | What it gives |
|---|---|
| [fresh-eyes](plugins/fresh-eyes/README.md) | Review and QA loops with fresh-context checkers, a decisions ledger and a commit gate, plus a read-only code search agent |

## Install

Add the marketplace once, then install a plugin from it:

```bash
claude plugin marketplace add sshdaemon/workbench
```

```bash
claude plugin install fresh-eyes@workbench
```

From a local checkout, pass its path instead of `sshdaemon/workbench`.

## Licence

MIT

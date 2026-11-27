# workbench

Engineering tools and skills for Claude Code, packaged as plugins. Install only the ones a project needs.

| Plugin | What it gives |
|---|---|
| [fresh-eyes](plugins/fresh-eyes/README.md) | Review and QA loops with fresh-context checkers, a decisions ledger and a commit gate, plus a read-only code search agent |
| [no-sleep](plugins/no-sleep/README.md) | A hook that stops waiting by sleeping or polling in the foreground, and points at background commands and Monitor instead |

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

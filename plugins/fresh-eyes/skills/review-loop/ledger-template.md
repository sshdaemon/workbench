# <Feature>: review decisions

Findings that have been ruled on. Reviewers read this first and don't raise these again unless the code changes enough to break the recorded `why`.

**Repos / branches:** api `feat/…` · web `feat/…`
**Docs:** [Requirements](<name>.brd.md) · [Design](<name>.design.md)

## Decisions

<!-- One entry per finding. Keep ids stable; never renumber. -->

```yaml
- id: D-001
  repo: api
  where: src/foo/foo.service.ts, FooService.bar()
  concern: No transaction around foo + bar insert
  verdict: accepted-as-is        # accepted-as-is | fixed:<how> | deferred:<ticket> | out-of-scope | rejected
  why: bar rows are written by an async job after the insert; the nightly sweep removes orphans
  decided: 2026-01-15 (round 1)
```

## Rounds

<!-- Appended by review-loop: "Round N (date): X found, Y dropped by ledger, Z auto-fixed, W asked: ids" -->

# fresh-eyes

Checks on your work done from a clean context, so the checker can't lean on what the author already believes.

## What is in it

| Piece | Kind | What it does |
|---|---|---|
| `review-loop` | skill | Runs review and fix rounds on a feature branch until a round comes back clean, then approves the staged diff for commit |
| `code-reviewer` | agent | Reviews the branch with no prior context and returns verified findings as YAML. Never edits code |
| `mutant-author` | agent | Writes model mutants (plausible mistakes on the changed lines, aimed at the spec's rules) for the review loop's opt-in model-mutant step |
| `qa-loop` | skill | QAs a ticket through the real UI: cases from the ticket and its diffs, a fresh check of the cases, a run with the project's UI test engine, a fresh check of every verdict, then the viewer link |
| `qa-validator` | agent | Challenges a case list before testing and every verdict after, from the ticket copy, the code and the run's evidence. Never edits, runs or posts |
| `code-search` | agent | Answers "where is X" and "who calls Y" across repos and worktrees with file:line hits and the chain to each entry point |
| commit gate | hook | Denies `git commit` in a covered repo unless the review loop approved exactly the staged diff |
| `where-symbol` | command | Prints, per checkout of a repo, its branch and how many files contain a name |

## How the review loop works

1. A fresh reviewer reads the spec docs, the decisions ledger and the diff, and reports findings.
2. Clear findings are fixed straight away. Judgement calls are put to you as questions.
3. Every decision goes into the feature's ledger, with its reason. A later round, or a later review, does not raise a settled finding again unless the code changed enough to break that reason.
4. When a round is clean, the loop writes an approval for the staged diff and commits. Any change to the staged diff afterwards needs a new approval.

With `--model-mutants`, from round 2 on the loop also runs model mutants where the profile describes them: a fresh `mutant-author` writes mistakes aimed at the spec's and the ledger's rules for the mutation tool's placeholders, the tool checks the answers, then runs them, and their survivors reach the reviewer with the other mutation findings. A clean round 1 doesn't end the loop, so they always run. Later rounds rerun the cached mutants only, which confirms kills without new authoring. It is opt-in because model mutants can run slow test lanes, such as end-to-end suites with their own databases.

To commit without a review, prefix the command with `SKIP_REVIEW_LOOP=1`.

The gate reads the command before it runs and approves the index as it is at that moment. So the commit has to be the first thing in its command, in one of these forms: `git commit` in the repo, `git -C <path> commit`, or `cd <path> && git commit`. Staging and committing in one command is denied, and so is a command the gate can't follow (a variable in the path, several commits at once, a subshell, `--git-dir`). Anything after the commit, such as `&& git log -1`, is fine. The wording of the commit message is not scanned, but a command substitution anywhere in the command is denied, apart from the usual `-m "$(cat <<'EOF' ... EOF)"` message form.

The gate reads text, not a parsed shell command. In a covered folder it also denies a command that only mentions the words, such as `echo "run git commit later"`, because it can't tell that from `bash -c "git add -A && git commit"`. Reword the text or pass it from a file.

`tests/commit-gate.sh` runs the gate against throwaway repos.

## How the QA loop works

1. The loop copies the ticket into a QA ledger, reads the pull requests' diffs and writes the cases into a case file.
2. A fresh validator challenges the cases: missing edge cases, expected results a broken feature would still pass, cases that can't prove their claim.
3. The UI test engine runs the case file, and the run waits for the session's verdicts.
4. A fresh validator checks every verdict against the steps and screenshots the engine recorded, reading them through the engine's read command.
5. The loop finishes the run and hands over the viewer link. It posts results on the ticket only when asked.

It is written against the [witness](https://github.com/sshdaemon/witness) UI test engine: its steps runner (case files, lanes, a verdict file), its MCP tools (sessions, cases, evidence, cleanup) and its `qa-md`, `promote` and `read` commands. Another engine needs the same ones. The project's profile needs a "QA" section.

## Setting up a project

Add a profile at `.claude/fresh-eyes.md`, in the repo or in a folder that holds several repos. It names the repos and base branches, where specs and ledgers live, which checks may run, and the project's own review rules. See [PROFILE.md](PROFILE.md).

Without a profile the review loop still runs on the current repo with defaults, and the commit gate stays off.

## Requirements

`git`, `jq` and `shasum` or `sha256sum` for the commit gate; without them it denies commits in covered repos and says what is missing. `gh` to detect merged pull requests. `rg` and `ast-grep` for code search.

## Changing the plugin

Bump `version` in `.claude-plugin/plugin.json` with every change. Installed copies refresh only when the version changes.

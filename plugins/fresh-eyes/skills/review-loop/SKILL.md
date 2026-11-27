---
name: review-loop
description: Run review-fix rounds on the current feature branch, across every repo involved, until it's clean. Each round, a fresh-context code-reviewer subagent reviews the changes; clear findings get fixed automatically; judgement calls are batched into questions for the user, and the answers go into the feature's review-decisions ledger so no later review raises them again. A commit gate hook blocks commits whose staged diff this skill has not approved. Use before committing, and when the user says "review loop", "review and fix", "/review-loop", or asks to clean up a branch before a pull request.
argument-hint: "[FEATURE] [--rounds N] [--min-severity medium] [--no-commit] [--model-mutants]"
---

# Review loop

Run this in the session that wrote the code. The independence comes from the reviewer subagent, which starts with a clean context every round. You, the orchestrator, fix and triage.

## 0. Set up

1. **Profile:** find the project profile, `.claude/fresh-eyes.md`, in the working directory or the nearest parent folder that has one. Read all of it. It names the repos, where docs and ledgers live, which checks may run, and the project's own rules. Where this skill and the profile disagree, the profile wins. With no profile, work on the current repo alone with the defaults given below, and tell the user a profile would make the loop fit the project (format: `${CLAUDE_PLUGIN_ROOT}/PROFILE.md`).
2. **Feature:** take it from the argument (a ticket id or a feature folder name). If there isn't one, infer it from the branch name and the feature folders the profile's "Docs" section describes. Confirm with the user only if the inference is ambiguous.
3. **Repos:** from the profile's "Repos" section, include each repo (and any worktree of it the user mentions) that is on the feature branch or has commits or changes for this feature. Default: the current repo. Fetch each base branch first and always diff against the fetched remote base, never a local copy of it, which may predate merged pull requests. Default base: the remote's default branch.
4. **Docs:** find the feature's spec docs (requirements, design) where the profile says they live. If there are none, go on without and tell the reviewer.
5. **Ledger:** the path the profile gives for the feature's decisions ledger. Default: `docs/reviews/<feature>.decisions.md` in the repo. If it doesn't exist, create it from [ledger-template.md](ledger-template.md).
6. **Already merged?** For each repo, check whether the branch's pull request is merged (`gh pr list --head <branch> --state all`). Where merges are squashed, a merged branch still diffs as if it were new, and new commits on it would go nowhere. If it is merged:
   - Review scope is the merge or squash commit's files as they are now on the base branch: `git diff <commit>^ <commit> --name-only`, then read those files at the fetched base.
   - Fixes go on a new branch cut from the up-to-date base, never on the merged branch. The working tree has to be clean first; if it isn't, ask the user (stash, or make a worktree).
   - Tell the reviewer the feature is already merged, give it the commit, and ask it to review the current code of those files, not a diff.
7. **Defaults:** `--rounds 4`. The minimum severity is `low` in round 1 and `medium` from round 2 on. Fixes stay uncommitted across rounds; one commit per repo happens at the end (step 3) unless `--no-commit` is passed. Never push, open pull requests or merge unless the profile says the loop may.
8. **Pre-commit run:** when invoked because you're about to commit (or a commit was blocked), tell the reviewer to focus on the uncommitted changes and use the rest of the branch diff only as context. Earlier commits already passed a loop.
9. **Machine checks:** read the profile's "Machine checks" section, if it has one. Each check has a kind (`static`, `mutation` or `shared-code`), the repos it applies to, the command to run and where its report lands. Before round 1, confirm each tool is installed the way the profile says; if one isn't, tell the user and go on without it.
10. **Model mutants:** off unless `--model-mutants` was passed or the user asked for them. They need a mutation check whose tool takes authored mutants, and the profile's commands for it (propose, check, run, the budget, which lanes may run). With them on, step 1a runs them from round 2 on, for each repo that has that check, and the loop runs at least two rounds (step 2). Without the profile's commands, tell the user and go on without them.

## 1. Each round

### a. Machine checks

Every round, before the reviewer, for each repo in scope, run the checks from step 0.9 that apply to it, in the profile's order. Run slow ones in the background and wait for them. Print each tool's one-line summary. Keep reports out of the repo, in the folder the profile names.

If a check fails to run (as opposed to finding something), quote the error to the user and go on without it for that repo. Don't fix the tool mid-review, unless the repo under review is that tool.

The checks cover the whole branch plus uncommitted work, so in a pre-commit run their findings can sit in earlier commits. The reviewer still focuses on the uncommitted changes (step 0.8).

**Model mutants** (when step 0.10 turned them on), from round 2 on, after the repo's mutation check has finished, in the same report folder so their results join its report:

- **Round 2:** run the profile's propose command. Start this plugin's `mutant-author` subagent (`fresh-eyes:mutant-author`) in the foreground with the placeholders file, the spec doc paths, the ledger path, the profile's budget as the profile words it (a count and any note on where to spend it) and the answers path. Run the profile's check command on the answers, which judges them without running tests; if it rejects any, or can't read the answers file at all, send the rejections file or the error message to the same author once and check again. Then run the profile's run command on the answers, in the background, and wait for it. Answers still rejected are left out; give their count in the summary.
- **Round 3 on:** run propose again, then the run command on an answers file with no mutants (`{ "mutants": [] }`). The tool runs the mutants cached from earlier rounds, so kills of tests added for model survivors are confirmed without new authoring. Lines that fixes added get no model mutants.

Print the run's one-line summary next to the other checks'. A failed propose or run is handled like a failed check: quote the error and go on without model mutants.

### b. Review

Start this plugin's `code-reviewer` subagent (`fresh-eyes:code-reviewer`) in the foreground. Give it the profile path, the feature name, the repo, base and branch list, the doc paths, the ledger path, the round number and the minimum severity. Also give it each report from step a, labelled with its kind and "machine-found". From round 2 on, also list the finding ids fixed in the previous round and ask it to confirm those fixes hold. Don't pass your own opinion of the code, and don't filter or summarise the reports yourself.

### c. Filter

Drop every finding that matches a ledger entry (same symbol or location and concern) and has no `reopens`. The reviewer should already do this; this second check is the safety net. Keep a count of what you dropped for the round summary.

### d. Triage

For each remaining finding, re-read the code yourself.

- **False positive** (the claim is wrong): don't fix it. Record it in the ledger as `rejected` with the reason. You're the author and biased, so if you're not certain, send it to the user instead.
- **Auto-fix:** `needs_decision: false`, confidence high or medium, a clear fix that stays within the spec. Fix it.
- **Ask the user:** everything else, including anything that changes user-visible behaviour, contradicts or extends the spec, involves a real trade-off, or reopens a ledger entry.
- **From a mutation check** (the finding cites a survivor id or an untested file): a weak assertion or uncovered line in changed code is auto-fixed by adding or tightening a test, never by changing the code under test; then confirm the kill the way the profile says. A model survivor is triaged the same way, but its kill is confirmed by the next round's cached run; only when no further round will run, confirm it with the profile's command for that. An equivalent mutant, or code the reviewer judged not worth a unit test, is asked, with "Leave as is" first. An untested file is asked: add a unit test, or accept the coverage another test lane gives. Put the survivor id or `<file>#untested` in the ledger entry's `where`.
- **From a static check** (the finding cites a rule finding id): a complexity finding is never auto-fixed, since splitting a function is a judgement call; ask the user, with "Leave as is" first when the reviewer judged it acceptable. A bug finding is auto-fixed when the fix is obvious, otherwise asked. Put the finding id in the ledger entry's `where`, so the next round's reviewer can match it. When a finding is left as is or rejected, also mark it accepted in the tool, if the profile says how, so later runs stop reporting it until its code changes.
- **From a shared-code check:** always asked. The options are to record a decision that allows the change, or to keep the change local to the feature.

### e. Fix

Apply the auto-fixes. Follow each repo's `CLAUDE.md` / `AGENTS.md` and the profile's conventions. Run the checks the profile allows (typecheck, the relevant unit tests). Never run a command the profile forbids. If a fix breaks tests and you can't resolve it quickly, revert it and move the finding to "ask the user".

### f. Ask

Batch every "ask the user" item for the round into one `AskUserQuestion` call, with up to 4 questions per call; use more calls if needed. Each question is one finding. Its header is the finding id. The question text is the claim plus one line of evidence. The options are the fix options, plus **Leave as is**. The user can type a reason through "Other". If they pick "Leave as is" without a reason, ask once for a short why; the ledger needs it to hold.

Then apply the fixes they chose.

### g. Record

Update the ledger:

- Add an entry for each decision (`accepted-as-is`, `fixed:<option>`, `deferred`, `out-of-scope`, `rejected`) with the location, the concern and the reason given. Auto-fixes go in as `fixed` too, so a later reviewer doesn't push back towards the original code.
- Add a one-line `// intentional: …` comment only when the code itself looks wrong without it, such as a deliberate workaround or a gotcha. Don't add one to explain why something from the spec is missing or different; the ledger covers that.
- Append the round summary (see step 4) to the ledger's Rounds section.

## 2. When to stop

Stop when any of these is true:

- A round returns no findings at or above the minimum severity after filtering. With model mutants on, round 1 never stops the loop: round 2 runs them, then the usual rule applies.
- The round limit is reached.
- The same finding comes back after being fixed twice. That's a design question, so ask the user.

## 3. Approve and commit

The commit gate hook of this plugin denies `git commit` in any repo covered by a profile unless `<git-dir>/review-loop-approved` holds the SHA-256 of the exact staged diff. Only write it when the loop stopped cleanly: the last round found nothing at or above the minimum severity, or every remaining finding has a ledger decision from the user. If the round limit hit with findings still open, don't approve; ask the user.

For each touched repo, as separate commands (the hook checks the index before the command runs, so it denies a commit that has any other command in front of it, apart from one `cd <repo> &&`):

1. Stage explicitly: `git -C <repo> add <files>`. Never `git commit -a`, and never pass paths to `git commit`: the gate approves the index, so the commit must take the index as it is. Run the commit as its own command, `git -C <repo> commit ...`, so the gate can tell which repo it is for. Leave out unrelated changes such as a stray lockfile, and mention them.
2. Approve: `git -C <repo> diff --cached --binary | shasum -a 256 | cut -d' ' -f1 > "$(git -C <repo> rev-parse --absolute-git-dir)/review-loop-approved"` (where `shasum` is missing, use `sha256sum` in its place). Check the marker is not empty.
3. Commit, following the profile's "Commits" section for the message. Default: a short imperative subject, and a body only when the why isn't obvious. Skip this if `--no-commit` was passed; the approval then waits for the user's own commit.

Any change to the staged diff after approval (a new fix, a re-stage) invalidates it, so approve last. Only prefix a commit with `SKIP_REVIEW_LOOP=1` when the user explicitly says to skip the review for that commit.

## 4. Report

After each round, print one short line: `Round N: X found, Y dropped by ledger, Z auto-fixed, W asked`. At the end, give:

- the commits made (hash and repo), or why nothing was approved
- the rounds run and why the loop stopped
- what was fixed, grouped by repo
- anything left open or deferred
- the test and typecheck status, with any failures quoted

Link to the ledger. Keep it brief; the detail lives in the ledger.

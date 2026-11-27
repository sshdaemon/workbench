---
name: qa-loop
description: QA a ticket end to end through the real UI. Define the test cases and edge cases from the ticket and its merged or open pull requests, have a fresh-context qa-validator agent challenge the case list, run the cases with the project's UI test engine (adding any missing tool), have the validator check every verdict against the evidence, then give the user the results viewer link (post on the ticket only when asked). Use when the user says "qa loop", "/qa-loop", "QA this ticket", "test this on staging/local", or asks to define test cases for a ticket.
argument-hint: "<TICKET> [--env <env>] [--plan-only] [--post]"
---

# QA loop

Run this in the session that will do the testing. Independence comes from this plugin's `qa-validator` subagent (`fresh-eyes:qa-validator`), which starts with a clean context twice: once to challenge the cases before testing, once to check the verdicts after. You, the orchestrator, plan, test and report.

## 0. Set up

1. **Profile:** find the project profile, `.claude/fresh-eyes.md`, in the working directory or the nearest parent folder that has one, and read all of it. Its "QA" section names the ticket tracker, how to find a ticket's pull requests, where the QA ledger and case file live, the UI test engine and its commands, the engine's skills, the environments, the actors, the results comment layout and the viewer. Load the skill it names for testing now, and the one for adding a tool when a case needs one. Where this skill and the profile disagree, the profile wins. With no profile or no "QA" section, stop and tell the user what the loop needs (format: `PROFILE.md` in this plugin).
2. **QA ledger:** at the path the profile gives (find the ticket's existing feature folder first; create one by the profile's naming rules only when there is none, taking its short description from the ticket's title, which you read for this). Create the ledger from [qa-template.md](qa-template.md) if missing. It holds the case list, what is out of scope and why, and the result of each run. If it already exists, continue from it: don't re-plan settled cases. An older ledger with a hand-written case table and runs list gets the `<!-- cases:start -->` / `<!-- cases:end -->` and `<!-- runs:start -->` / `<!-- runs:end -->` markers once its cases are in a case file: the generated table replaces the hand-written one, and earlier hand-written runs stay above the runs markers.
3. **Ticket:** from the argument; if there's none, ask. Read it with the tracker the profile names: description, comments, attachments, linked pull requests. The validator has no access to the tracker and reads only what you write down, so every time the loop starts, ledger or not, replace the ledger's "Ticket" section with the ticket as it is now:
   - the description and the comments (author, date, text), and the date you read them
   - for each image and attachment, a short description of what it shows that matters for testing (a screen, a message, a value, a file's rows). Also save the file under `ticket-files/` next to the ledger when the tracker gives a link you can download (the profile's tracker entry says how), and name the saved file in the copy; otherwise mark it "described only".
4. **Changes:** find the pull requests for the ticket as the profile says. For each, note whether it's merged, its repo and the files it touched. Read the diffs, not only the descriptions: the cases come from what the code does.
5. **Environment:** `--env` if given, otherwise as the profile's QA section picks it. An environment the profile says is never used is never used.

## 1. Define the cases

Write the cases into the ticket's case file next to the ledger (format in the engine's docs, named in the profile), then generate the ledger's Cases section from it with the engine's `qa-md` command. Edit the case file, never the generated table. One case per user-visible behaviour the change adds or alters, each with:

- **id** `C1`, `C2`, …, its `title` (one-line use case) and `actor` by role (the profile lists them)
- **steps** as a person does them in the UI, **expected** result as the user sees it
- **kind:** `happy`, `edge` or `regression`
- its commands (`block`), the fixtures it `needs`, the cases it runs `after`, and an `expect` on every evidence read

A case that cannot be run that way goes, by hand, under the ledger's "Not covered" with its reason: `tool missing: <what it must do>` (until the tool exists), `not UI-testable: <why>; covered by <test file or none>`, or `not run: <risk>`.

When the feature has a UI spec that lists design states (the profile's "Docs" section names it), add a case for each state it lists, and the edge cases it settles become edge cases here.

Find edge cases on purpose, from the diff and the ticket:

- limits and boundaries (exactly at, just over, empty, one, many, a page boundary)
- each new error message or refusal the code can produce, and what the user sees for it
- what is left unchanged: a refused action must not change data, and nothing the run did not create may change
- input variants a real user produces (file types and names, formats, browsers sending a different type, optional fields left blank)
- permissions: a role that must not see or do it
- regressions: the old happy path still works

Mark as `not UI-testable` anything only an API, database, log or third-party view can show (error trackers, emails, queues), and name the automated test that covers it, if any. A case that would put real or shared data at risk (wiping a shared list, a real payment, a real person's account) is `not run: <risk>` unless the user agrees otherwise.

## 2. Challenge the cases

Start the `qa-validator` subagent in the foreground with the profile path, `mode: cases`, the ticket id, the pull request list with repos and paths, the ledger path and the case file. Don't pass your opinion. It returns missing cases, weak expected results and cases that can't prove what they claim.

- Add missing cases and sharpen the rest when the finding is clear.
- Ask the user in one `AskUserQuestion` batch (up to 4 per call) when a finding needs product knowledge, would add risk to shared data, or would drop a case.
- Then run `qa-md` again and show the user the final case table (id, use case, kind, how) in chat. With `--plan-only`, stop here.

## 3. Prepare

1. Check the stack the cases need, as the engine's testing skill and the profile's environments entry say for the chosen environment (a check of the local stack says nothing about a shared one).
2. Test accounts: `login` each actor. `SESSION_MISSING` or `SESSION_EXPIRED` means the user must run the bootstrap command the tool returns; give them the commands and wait.
3. Preconditions the UI must create (an account's role, a product, an order) go into the case file as fixtures, built with the existing tools; `cleanup_all` removes them. Give them plain words for names: the tools put the run tag and the label ("AB-12 run 3") in front, so screenshots posted on the ticket explain themselves. The store numbers the runs per ticket, blocked ones included; when the ledger already has hand-numbered runs and the store has none for the ticket, pass `--first-run <highest + 1>` to the first runner run (or `firstRun` to `session_start` in a run done by hand).
4. **Missing tools:** for each `tool missing` case, follow the engine's tool skill named in the profile. Load the edited tool with `mcp_reload` after closing the current run (cleanup, `run_finish`, `session_end`), and try it in a new run. When the client does not show a new tool, or the change is to the server's entry, reconnect with `/mcp`, or drive the server from a scratch MCP client that starts the engine's worker directly (the command is in the profile's engine entry); a run started there must finish in the same process (`run_finish`, `session_end`, `report` in the same call list), or it is stored as ABORTED. Commit the tool through `/fresh-eyes:review-loop` before the real run.

## 4. Run

Run the case file with the engine's steps runner, as its testing skill says: `WAIT_VERDICT=<scratchpad>/verdict.json npm run steps -- <case file> --env <env> --wait-minutes <n>` in the engine's folder, in the background (add `--lanes 2` when the cases split into groups that share no fixture and the environment allows it; the lanes share one run number and one verdict file). The runner starts the run for the ticket (the store gives it its number and label), records each case with its steps, checks and result, stops only what depends on a failure, runs `cleanup_all`, and then waits for the verdict file: the run is still open, so its case results can be corrected. It finishes the run once the file says `"final": true`, or after `--wait-minutes` (15 by default) without a new version of the file: give it enough for the validation below, and write each version as you go. Don't sleep to find out where it is: Monitor its output until every lane prints that it is waiting for verdicts, or the runner exits.

Judge only from what the tools read back. Cases judged by their checks are done; a case with an evidence read that has no expect waits for you. Don't retry a failing case hoping it changes. A case that cannot be put in the case file is run by hand in a run of its own (`session_start` with `ticket`, `case_begin` / `case_end`, `cleanup_all`), leaving that session open the same way. `qa-md` gives it a row marked "not in the case file"; write its steps and expected result by hand under a "Cases run by hand" heading below the generated cases.

A later run covers only the cases still without a PASS: `--missing` picks them for the environment about to run, with cases changed since (their fixtures included). The viewer's ticket page shows each case's latest result from any environment and version, so it is an overview, not the list of what is left: use `--missing` for that.

## 5. Validate the results

With the run still waiting for its verdict file, start the `qa-validator` subagent with the profile path, `mode: results`, the ledger path, the case file, the run id and the run directory (the profile says where runs are kept). With lanes there is one run per lane (each printed as `[lane k] > <label> · <runId>`): give the validator every lane's run id and directory. It checks each recorded case result against the steps inside its range and their screenshots, that every case was run or has a reason, and that cleanup left nothing behind.

- Write your verdicts for the waiting cases into the verdict file (without `final`): the runner applies them at once, so the store shows them.
- A verdict the evidence doesn't support: correct it in a new version of the verdict file (`{"cases": {"C3": {"result": "FAIL", "actual": "…", "note": "why the checks were wrong"}}}`), or with `case_end` (with a `note`) in a run done by hand. When the evidence is missing, the case needs a new run under the same ticket; record it as BLOCKED with that reason.
- A finding about the product (a real bug): it's a FAIL, not something to fix here. Say so to the user; fixing goes through the normal branch, pull request and `/fresh-eyes:review-loop`.
- Repeat validation once after changes. If it still disagrees, ask the user.
- Then finish the run: once every lane (or the one run) has printed that it is waiting, write the verdict file once more with `"final": true` (`{"cases": {}, "final": true}` when every case was judged by its checks), and the runner calls `run_finish` and `session_end`; in a run done by hand, call `run_finish` with an `ok: … ; FAIL: …` checklist (no verdict: it comes from the cases) and `session_end`. Case results cannot change after `run_finish` (RUN_FINISHED). Then run `qa-md` again: it rewrites the ledger's table and Runs lines from the store. Add by hand, below the generated runs, anything they do not say (cleanup left behind, why a run was repeated).

## 6. Report

1. Pick the evidence per case with `evidence_pick` (`ticket`, `case`, `caption`, the run and step): the marked frames that show the expected result (the marked notification, the marked rows, the cropped `verify` shot), only those, and look at each one yourself. `evidence_list({ ticket })` returns them in order; `evidence_remove` drops a wrong pick. Do not copy screenshots into the feature folder or a scratch folder.
2. Only with `--post` or when the user asks: draft the comment in the exact layout the profile names, one block per case that was run, BLOCKED cases included. No summary or next steps.
3. Show the draft and wait for the user's OK before posting (posting is outward-facing). Then upload each image and post the comment as the profile's tracker entry says, and record each upload with `evidence_posted({ id, url })`.
4. Name, in one line, the cases that would make good regression checks (those marked `kind: "regression"` first, then others that are stable, judged by their checks and about behaviour that could break again) and ask the user whether to promote them (the engine's `promote` command, then a commit through `/fresh-eyes:review-loop`). Promote nothing without their yes.
5. Final message: start the results viewer as the profile says (unless it already answers) and give the ticket's viewer link (every case against every run, with its current result and evidence), one line per case verdict, real bugs found, and anything not cleaned up. No step-by-step detail; the viewer and the ledger hold it.

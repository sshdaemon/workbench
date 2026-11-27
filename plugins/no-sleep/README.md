# no-sleep

Stops Claude from waiting on something by sleeping or polling in the foreground.

Claude Code already wakes the session when a background command exits, and Monitor wakes it when a condition holds. A guessed `sleep 30` or a `until …; do sleep 5; done` loop just blocks the session, and the guess is either too short or wastes time.

## What it denies

A Bash call that runs in the foreground and:

- sleeps inside an `until`, `while` or `for` loop, its condition included
- sleeps longer than 3 seconds in total
- runs `gh pr checks --watch` or `gh run watch`

A sleep counts behind `time` or `timeout <n>`, in a `{ …; }` group, in the string passed to `bash -c` or `sh -c`, and in a heredoc fed to a shell (`bash <<EOF`).

The deny message names what to do instead: run it with `run_in_background`, run `gh pr checks --watch --fail-fast` in the background, or use Monitor for a condition (a port, a log line, a file).

## What it lets through

- anything run with `run_in_background`
- a short sleep outside a loop, such as `kill 123; sleep 1; ps -p 123`
- a short sleep next to a loop that doesn't contain it, such as `for …; done; sleep 1`
- "sleep" inside quotes, a `#` comment or a heredoc body, such as a patch script or a search pattern

The hook reads text, not a parsed shell command, so an unusual form can slip past or be denied by mistake. `tests/no-sleep-poll.sh` runs it against sample commands.

## Needs

`python3`. Without it the hook prints a warning and lets every command through.

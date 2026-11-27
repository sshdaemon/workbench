#!/bin/bash
# PreToolUse(Bash): denies waiting by sleeping in the foreground. The logic is in no-sleep-poll.py.
command -v python3 >/dev/null 2>&1 || {
  echo "no-sleep: python3 not found, the hook is off" >&2
  exit 0
}
exec python3 -I "$(dirname "$0")/no-sleep-poll.py"

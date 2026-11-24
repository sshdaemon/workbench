#!/bin/bash
# Runs the commit gate against throwaway repos. Usage: tests/commit-gate.sh
# Exits 1 if any case gives the wrong decision. Needs git, jq and shasum or sha256sum.
H="$(cd "$(dirname "$0")/.." && pwd)/hooks/require-review-loop.sh"
S=$(mktemp -d)
mkdir -p "$S/ws/.claude" "$S/ws/repo" "$S/ws/design-system" "$S/ws/sp ace" "$S/bare/repo" "$S/off/.claude" "$S/off/repo"
# The body line must not turn the gate off: only the front matter counts.
printf -- '---\ncommit-gate: on\n---\n\ncommit-gate: off\n' >"$S/ws/.claude/fresh-eyes.md"
printf -- '---\ncommit-gate: off\n---\n' >"$S/off/.claude/fresh-eyes.md"
for r in ws/repo ws/design-system "ws/sp ace" bare/repo off/repo; do
  git -C "$S/$r" init -q
  echo x >"$S/$r/f"
  git -C "$S/$r" add f
done
R=$S/ws/repo
fail=0

run() {
  local want=$1 out got
  out=$(jq -n --arg c "$3" --arg d "$4" '{tool_input:{command:$c},cwd:$d}' | "$H" 2>&1)
  [ -z "$out" ] && out='{}'
  got=$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"$out" 2>/dev/null || echo "error: $out")
  if [ "$got" = "$want" ]; then echo "ok    $got  $2"; else echo "FAIL  $got  $2 (want $want)"; fail=1; fi
}

approve() {
  local sum="shasum -a 256"
  command -v shasum >/dev/null 2>&1 || sum="sha256sum"
  git -C "$R" diff --cached --binary | $sum | cut -d' ' -f1 >"$(git -C "$R" rev-parse --absolute-git-dir)/review-loop-approved"
}

echo "covered repo, no approval"
run deny "plain commit" "git commit -m x" "$R"
run deny "-C unquoted" "git -C $R commit -m x" "$S/ws"
run deny "-C double quoted" "git -C \"$R\" commit -m x" "$S/ws"
run deny "-C single quoted" "git -C '$R' commit -m x" "$S/ws"
run deny "-C relative" "git -C repo commit -m x" "$S/ws"
run deny "-C path with a space" "git -C \"$S/ws/sp ace\" commit -m x" "$S/ws"
run deny "cd && commit" "cd repo && git commit -m x" "$S/ws"
run deny "cd ; commit" "cd repo; git commit -m x" "$S/ws"
run deny "subshell" "(cd repo && git commit -m x)" "$S/ws"
run deny "two lines" $'cd repo\ngit commit -m x' "$S/ws"
run deny "two cds" "cd $S/ws && cd repo && git commit -m x" "$S/ws"
run deny "pushd" "pushd repo && git commit -m x" "$S/ws"
run deny "variable in path" 'X=. ; git -C "$X" commit -m x' "$R"
run deny "two commits" "git commit -m a && git -C /tmp commit -m y" "$R"
run deny "-c option" "git -c user.name=x commit -m x" "$R"
run deny "--no-pager" "git --no-pager commit -m x" "$R"
run deny "git by path" "/usr/bin/git commit -m x" "$R"
run deny "backslash git" '\git commit -m x' "$R"
run deny "line continuation" $'git -C repo \\\n  commit -m x' "$S/ws"
run deny "--git-dir=" "git --git-dir=$R/.git --work-tree=$R commit -m x" "$S/ws"
run deny "--git-dir with a space" "git --git-dir repo/.git commit -m x" "$S/ws"
run deny "GIT_DIR" "GIT_DIR=$R/.git GIT_WORK_TREE=$R git commit -m x" "$S/ws"
run deny "skip token in the message" 'git commit -m "note SKIP_REVIEW_LOOP=1 here"' "$R"
run deny "skip token on another command" "SKIP_REVIEW_LOOP=1 echo hi; git commit -m x" "$R"
run deny "heredoc message" $'git commit -m "$(cat <<\'EOF\'\nAdd thing\n\nBody line\nEOF\n)"' "$R"
run deny "path ending in -system" "git -C $S/ws/design-system commit -m x" "$S/ws"
run deny "relative path ending in -system" "git -C design-system commit -m x" "$S/ws"
run deny "option value ending in -m" "git -c core.x-m commit -m x" "$R"
run deny "quotes that hide the commit" "echo ' -m \"' ; git add -A ; git commit -m '\" x'" "$R"
run deny "text that only mentions a commit" 'echo "run git commit later"' "$R"
run deny "commit inside bash -c" 'bash -c "git add -A && git commit -m x"' "$R"

echo "allowed without approval"
run allow "skip prefix" "SKIP_REVIEW_LOOP=1 git commit -m x" "$R"
run allow "skip with another variable" "SKIP_REVIEW_LOOP=1 GIT_EDITOR=true git -C $R commit -m x" "$S/ws"
run allow "no profile" "git commit -m x" "$S/bare/repo"
run allow "gate off" "git commit -m x" "$S/off/repo"
run allow "git status" "git status" "$R"
run allow "git log --grep commit" "git log --grep commit" "$R"
run allow "text mentions a commit, folder not covered" 'echo "run git commit later"' "$S/bare/repo"
run allow "unclear command, folder not covered" "cd repo; git commit -m x" "$S/bare"
run allow "commit outside a repo" "git commit -m x" "$S/ws"
run allow "add then commit, not covered" "git add f && git commit -m x" "$S/bare/repo"

echo "covered repo, approved"
approve
run allow "plain commit" "git commit -m x" "$R"
run allow "-C" "git -C $R commit -m x" "$S/ws"
run allow "cd &&" "cd $R && git commit -m x" "$S/ws"
run allow "heredoc message" $'git -C '"$R"$' commit -m "$(cat <<\'EOF\'\nAdd thing\n\nBody: a, b -- c; run git commit and cd there -p\nEOF\n)"' "$S/ws"
run allow "--amend --no-edit" "git commit --amend --no-edit" "$R"
run allow "environment prefix" "GIT_EDITOR=true git commit -m x" "$R"
run allow "-F" "git commit -F /tmp/msg" "$R"
run allow "pipe after" "git commit -m x 2>&1 | tail -3" "$R"
run allow "git log after" "git commit -m x && git log -1" "$R"
run allow "message mentions git commit" 'git commit -m "Deny git commit when the repo is unknown"' "$R"
run allow "message mentions cd" 'git commit -m "Follow cd before the command"' "$R"
run allow "message mentions -p" 'git commit -m "Add -p option to the parser"' "$R"
run allow "message mentions --" 'git commit -m "Handle paths after -- in args"' "$R"
run allow "single-quoted message" "git commit -m 'Support -i flag; then git commit'" "$R"
run allow "escaped quote in message" 'git commit -m "Say \"git commit\" -a here"' "$R"
run allow "two -m" 'git commit -m "Subject -a" -m "Body with git commit"' "$R"
run allow "--message=" 'git commit --message="about -a and cd x"' "$R"
run allow "heredoc body with a double quote" $'git commit -m "$(cat <<\'EOF\'\nRename "foo" option\n\nPaths after -- are denied, and a second git commit; uses $(x)\nEOF\n)"' "$R"
run deny "two heredoc commits with add between" $'git commit -m "$(cat <<\'EOF\'\na\nEOF\n)" && git add -A && git commit -m "$(cat <<\'EOF\'\nb\nEOF\n)"' "$R"
run deny "substitution in the message" 'git commit -m "$(git add -A; echo msg)"' "$R"
run deny "unquoted substitution as message" 'git commit -m $(git add -A; echo x)' "$R"
run deny "substitution in an unquoted heredoc" $'git commit -m "$(cat <<EOF\nBody $(git add -A)\nEOF\n)"' "$R"
run deny "substitution in a variable prefix" 'X="$(git add -A)" git commit -m x' "$R"
run deny "substitution in a -c value" 'git -c "a.b=$(git add -A)" commit -m x' "$R"
run deny "commands hidden behind unquoted messages" "git commit -m a;git add -A;: -m c;git commit -m y" "$R"
run deny "--pathspec-from-file" "git commit --pathspec-from-file=list -m x" "$R"
run deny "-a" "git commit -a -m x" "$R"
run deny "-am" 'git commit -am "x"' "$R"
run deny "--only" "git commit --only f -m x" "$R"
run deny "paths after --" "git commit -m x -- f" "$R"
run deny "add && commit" "git add b.txt && git commit -m x" "$R"
run deny "-C add && -C commit" "git -C $R add -A && git -C $R commit -m x" "$S/ws"
run deny "cd && add && commit" "cd $R && git add . && git commit -m x" "$S/ws"
run deny "add ; commit" "git add b; git commit -m x" "$R"
run deny "cd elsewhere && relative -C" "cd $S && git -C ws/repo commit -m x" "$S/ws"

echo "approval no longer matches"
echo y >>"$R/f"
git -C "$R" add f
run deny "restaged after approval" "git commit -m x" "$R"
: >"$(git -C "$R" rev-parse --absolute-git-dir)/review-loop-approved"
run deny "empty marker" "git commit -m x" "$R"

echo "test repos left in $S"
exit $fail

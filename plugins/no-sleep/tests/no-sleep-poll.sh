#!/bin/bash
# Runs the no-sleep hook against sample commands. Usage: tests/no-sleep-poll.sh
# Exits 1 if any case gives the wrong decision. Needs jq and python3.
H="$(cd "$(dirname "$0")/.." && pwd)/hooks/no-sleep-poll.sh"
fail=0

run() {
  local want=$1 bg=$2 cmd=$3 out got
  out=$(jq -n --arg c "$cmd" --argjson b "$bg" '{tool_input:{command:$c,run_in_background:$b}}' | "$H" 2>&1)
  [ -z "$out" ] && out='{}'
  got=$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"$out" 2>/dev/null || echo "error: $out")
  if [ "$got" = "$want" ]; then echo "ok    $got  $cmd"; else echo "FAIL  $got  $cmd (want $want)"; fail=1; fi
}

run deny false 'sleep 20; cat /tmp/run.out'
run deny false 'sleep 2m && ls'
run deny false 'sleep 2; sleep 2; ls'
run deny false 'for i in $(seq 1 20); do nc -z 127.0.0.1 8080 && break; sleep 1; done'
run deny false 'until curl -s "http://localhost:3000"; do sleep 2; done'
run deny false 'gh pr checks 25 --repo o/r --watch'
run deny false 'gh run watch 123'
run allow false 'kill 123; sleep 1; ps -p 123'
run allow false 'npm test && git status'
run allow true 'sleep 20; cat /tmp/run.out'
run allow true 'gh pr checks 25 --repo o/r --watch --fail-fast'
run allow false "rg 'sleep 10' src"
run allow false 'echo "for x; do sleep 9; done"'
run allow false "python3 - <<'EOF'
for x in y: sleep 5
EOF"
# A sleep wrapped in a shell, a group, time or timeout still counts.
run deny false "timeout 60 bash -c 'until curl -s localhost:3000; do sleep 5; done'"
run deny false 'bash -c "while true; do sleep 5; done"'
run deny false "bash -lc 'until curl -s localhost; do sleep 5; done'"
run deny false 'bash -euc "while true; do sleep 5; done"'
run deny false '{ sleep 10; }'
run deny false 'time sleep 10'
run deny false 'while sleep 1; do ls; done'
# Comments and a heredoc on the same line don't hide a sleep.
run deny false "# it's here
sleep 30 # don't"
run deny false 'cat <<EOF > f; sleep 30
x
EOF'
# A `<<` that is not a heredoc hides nothing; a script fed to a shell is checked.
run deny false 'x=$((1<<4))
until curl localhost; do sleep 5; done'
run deny false 'echo "a<<b"
sleep 30'
run deny false "bash <<'EOF'
until curl localhost; do sleep 5; done
EOF"
run deny false 'cat <<<"hi"; sleep 30'
run allow false "cat <<'EOF' > notes.md
until it works; do sleep 5; done
EOF"
run allow false 'cat <<EOF
no end marker, sleep 1'
# A quote inside a heredoc body hides nothing after it.
run deny false "cat > notes.md <<'EOF'
It's done
EOF
until curl -s localhost:3000; do sleep 5; done"
run deny false "git commit -F - <<EOF
Don't
EOF
sleep 30"
# A script that happens to end in .sh is not a shell reading the body.
run allow false "./run.sh <<EOF
until ready; do sleep 5; done
EOF"
# A loop elsewhere in the command doesn't make a short sleep a polling loop.
run allow false 'for f in *.log; do gzip $f; done; kill 1; sleep 1; ps'
run allow false 'kubectl wait --for=condition=ready pod/x; sleep 1'
run allow false 'echo ok # dont; sleep 30'
run allow false 'bash -c "kill 1; sleep 1"'
# Bad input leaves the command alone.
for bad in garbage '[1]' '{"tool_input":{"command":5}}' '{"tool_input":[]}'; do
  out=$(echo "$bad" | "$H" 2>&1; echo "exit=$?")
  if [ "$out" = "exit=0" ]; then echo "ok    allow  bad input $bad"; else echo "FAIL  bad input $bad gave: $out"; fail=1; fi
done

exit $fail

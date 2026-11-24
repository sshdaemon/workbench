#!/bin/bash
# PreToolUse(Bash): block `git commit` in a repo covered by a project profile
# (.claude/fresh-eyes.md in the repo or a parent folder) unless the review loop
# approved exactly the staged diff. `commit-gate: off` in the profile's front
# matter turns it off. When the command commits but the repo can't be worked
# out from it, the gate denies rather than guesses.
input=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  grep -Eq 'git.*commit' <<<"$input" || exit 0
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"The commit gate needs jq to read the command. Install jq and retry."}}'
  exit 0
fi

# Prints three lines: whether a command substitution could run code the gate
# can't see (1 or 0), the command with commit messages cut out, and the command
# as given. Both commands are on one line, with line continuations joined.
# The message is not command text, so its wording must not look like a flag, a
# folder change or a second commit.
read -r -d '' PARSE <<'JQ'
def F: "(?<f>(^|\\s)(-[a-zA-Z]*m|--message)(\\s+|=))";
def H: F + "\"\\$\\(cat <<-?(?<q>['\"]?)(?<d>[A-Za-z_]+)['\"]?\\s(?<b>.*?)\\s\\k<d>\\s*\\)\"";
def Q: F + "(?<v>\"([^\"\\\\]|\\\\.)*\")";
def S: F + "'[^']*'";
def W: F + "[^\\s\"'\\-;&|()$`<][^\\s;&|()]*";
def risky: test("\\$\\(|`|<\\(");
def named: [.captures[] | select(.name != null) | {(.name): (.string // "")}] | add;
(.tool_input.command // "") | gsub("\\\\\n"; " ") | gsub("\n"; " ") as $raw
| ([$raw | match(H; "g") | named | select(.q == "" and (.b | risky))] | length > 0) as $r1
| ($raw | gsub(H; "\(.f)MSG")) as $c1
| ([$c1 | match(Q; "g") | named | select(.v | risky)] | length > 0) as $r2
| ($c1 | gsub(Q; "\(.f)MSG") | gsub(S; "\(.f)MSG") | gsub(W; "\(.f)MSG")) as $cut
| (if $r1 or $r2 or ($cut | risky) then "1" else "0" end), $cut, $raw
JQ

{
  IFS= read -r risk
  IFS= read -r scan
  IFS= read -r raw
} < <(jq -r "$PARSE" <<<"$input")
cwd=$(jq -r '.cwd // ""' <<<"$input")

if [ -z "$raw" ] && grep -Eq 'git.*commit' <<<"$input"; then
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"The commit gate could not read this command. Run the commit as its own command: git -C <literal path> commit -m ..."}}'
  exit 0
fi

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# Prints the nearest profile at or above $1 whose gate is on.
gate_profile() {
  local d=$1 p=""
  while :; do
    if [ -f "$d/.claude/fresh-eyes.md" ]; then p="$d/.claude/fresh-eyes.md"; break; fi
    [ "$d" = "/" ] || [ -z "$d" ] && break
    d=$(dirname "$d")
  done
  [ -n "$p" ] || return 1
  awk 'NR==1 && /^---[[:space:]]*$/ {f=1; next} f && /^---[[:space:]]*$/ {exit} f' "$p" |
    grep -Eiq '^commit-gate:[[:space:]]*off[[:space:]]*$' && return 1
  printf '%s\n' "$p"
}

OWN="Run the commit as its own command: git -C <literal path> commit -m ..."

unsure() {
  gate_profile "$cwd" >/dev/null || exit 0
  deny "The commit gate can't tell which repo this command commits to ($1). $OWN"
}

DQ='"([^"\\]|\\.)*"'
SQ="'[^']*'"
WORD="($DQ|$SQ|[^[:space:]]+)"

ENVS="([A-Za-z_][A-Za-z0-9_]*=$WORD[[:space:]]+)*"
OPTS="([[:space:]]+(-[Cc][[:space:]]+$WORD|--(git-dir|work-tree|namespace)[[:space:]]+$WORD|--[a-zA-Z-]+(=$WORD)?|-[pP]))*"
COMMIT="(^|[;&|(]|[[:space:]])$ENVS([^[:space:];&|()]*/|\\\\)?git$OPTS[[:space:]]+commit([[:space:]]|\$)"

# Whether there is a commit is judged on the command as given, so a wrong cut
# can deny a commit but never hide one.
grep -qE "$COMMIT" <<<"$raw" || exit 0
matches=$(grep -oE "$COMMIT" <<<"$scan")
[ -z "$matches" ] && unsure "its quoting can't be read reliably"
[ "$(printf '%s\n' "$matches" | wc -l | tr -d ' ')" -gt 1 ] && unsure "more than one commit in one command"

# The skip token counts only as an environment prefix of the git command itself.
grep -Eq '(^|[;&|(]|[[:space:]])SKIP_REVIEW_LOOP=1[[:space:]]' <<<"$matches" && exit 0

[ "$risk" = 1 ] && unsure "it holds a command substitution, which could stage files before the commit"

grep -Eq '(GIT_DIR|GIT_WORK_TREE|GIT_INDEX_FILE)=|--(git-dir|work-tree)([[:space:]]|=)' <<<"$matches" &&
  unsure "it points git at a repo through --git-dir, --work-tree or a GIT_ variable"

# What runs before the commit: nothing, or one `cd <path> &&`.
lead=${scan%%"$matches"*}
case "$matches" in [\;\&\|\(]*) lead="$lead${matches:0:1}" ;; esac
alone=1
leadcd=""
if grep -Eq '[^[:space:]]' <<<"$lead"; then
  leadcd=$(sed -nE "s/^[[:space:]]*cd[[:space:]]+$WORD[[:space:]]*&&[[:space:]]*\$/\1/p" <<<"$lead")
  [ -n "$leadcd" ] || alone=0
fi

strip() { sed -E "s/^\"(.*)\"\$/\1/; s/^'(.*)'\$/\1/" <<<"$1"; }

dir=$(grep -oE -- "-C[[:space:]]+$WORD" <<<"$matches" | tail -1 | sed -E 's/^-C[[:space:]]+//')
if [ -n "$dir" ]; then
  dir=$(strip "$dir")
  case "$dir" in /* | "~"*) ;; *) [ "$alone" = 1 ] && [ -z "$leadcd" ] || unsure "a relative -C path follows other commands" ;; esac
elif [ "$alone" = 0 ]; then
  unsure "other commands run before the commit; if the command only mentions those words in its text, pass the text from a file or reword it"
elif [ -n "$leadcd" ]; then
  dir=$(strip "$leadcd")
else
  dir=$cwd
fi
case "$dir" in *'$'* | *'`'*) unsure "the path holds a variable or a substitution" ;; esac
case "$dir" in "~"*) dir="$HOME${dir#\~}" ;; esac
case "$dir" in /*) ;; *) dir="$cwd/$dir" ;; esac

# Not a repo: git itself refuses the commit.
top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || exit 0
gate_profile "$top" >/dev/null || exit 0

# The approval is for the index as it is now, so nothing may run before the commit.
[ "$alone" = 1 ] ||
  deny "Commits in $top need a review-loop approval of the staged diff, and other commands run before this commit could change what is staged. $OWN"

# Forms that commit working-tree content instead of the approved index.
grep -Eq 'commit([^;&|]*[[:space:]])?(--pathspec-from-file[^[:space:]]*|--all|--only|--include|--patch|--interactive|-[a-zA-Z]*[aoip][a-zA-Z]*|--)([[:space:]]|$)' <<<"$scan" &&
  deny "Commits in $top need a review-loop approval of the staged diff, so stage files explicitly and commit the index as it is: no -a, -o, -i, -p, --pathspec-from-file and no paths after --."

if command -v shasum >/dev/null 2>&1; then sum="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then sum="sha256sum"
else deny "The commit gate needs shasum or sha256sum to compare the staged diff with its approval. Install one and retry."
fi

marker="$(git -C "$top" rev-parse --absolute-git-dir)/review-loop-approved"
hash=$(git -C "$top" diff --cached --binary | $sum | cut -d' ' -f1)
approved=""
[ -f "$marker" ] && approved=$(tr -d '[:space:]' <"$marker")
[ -n "$hash" ] && [ "$approved" = "$hash" ] && exit 0

deny "Commits in $top must pass the review loop first: the staged diff has no matching approval (marker: $marker). Run the review-loop skill; it writes the marker after a clean round. If the user explicitly said to skip the review for this commit, prefix the command with SKIP_REVIEW_LOOP=1."

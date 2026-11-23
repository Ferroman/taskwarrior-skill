#!/usr/bin/env bash
# Tests for skills/taskwarrior/scripts/tw-export.sh.
#
# A fake `task` on PATH prints canned export output and records its argv, so
# the test needs neither Taskwarrior nor a task database. Needs bash, sed, jq.

set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
helper="$here/../skills/taskwarrior/scripts/tw-export.sh"
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT

fails=0
ok()   { echo "ok - $1"; }
fail() { echo "FAIL - $1"; fails=$((fails + 1)); }

mkdir -p "$sandbox/bin"
cat > "$sandbox/bin/task" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_ARGV"
cat "$FAKE_OUTPUT"
exit "${FAKE_RC:-0}"
EOF
chmod +x "$sandbox/bin/task"
export PATH="$sandbox/bin:$PATH" FAKE_ARGV="$sandbox/argv" FAKE_OUTPUT="$sandbox/out"

# 1. Bare duration tokens in any field become strings; numbers stay numbers.
cat > "$FAKE_OUTPUT" <<'EOF'
[
{"id":1,"description":"a","est":2d,"size":15min,"urgency":4.5,"skipped":3},
{"id":2,"description":"ratio \"x\":2d, kept","est":1.5h,"neg":-3h}
]
EOF
out=$("$helper" status:pending)
if echo "$out" | jq -e . >/dev/null 2>&1; then ok "output is valid JSON"; else fail "output is valid JSON: $out"; fi
[[ $(echo "$out" | jq -r '.[0].est') == 2d ]] && ok "est quoted" || fail "est quoted"
[[ $(echo "$out" | jq -r '.[0].size') == 15min ]] && ok "any field name is fixed" || fail "any field name is fixed"
[[ $(echo "$out" | jq -r '.[1].est') == 1.5h ]] && ok "decimal duration quoted" || fail "decimal duration quoted"
[[ $(echo "$out" | jq -r '.[1].neg') == -3h ]] && ok "negative duration quoted" || fail "negative duration quoted"
[[ $(echo "$out" | jq -r '.[0].urgency | type') == number ]] && ok "real numbers stay numbers" || fail "real numbers stay numbers"
[[ $(echo "$out" | jq -r '.[1].description') == 'ratio "x":2d, kept' ]] && ok "text inside strings untouched" || fail "text inside strings untouched"

# 2. Arguments: context neutralized, filter terms passed one by one, export last.
"$helper" '(' project:a or project:b ')' >/dev/null
expected=$'rc.context=none\nrc.verbose=nothing\n(\nproject:a\nor\nproject:b\n)\nexport'
[[ $(cat "$FAKE_ARGV") == "$expected" ]] && ok "argv order" || fail "argv order: $(tr '\n' ' ' < "$FAKE_ARGV")"

# 3. A failing `task` makes the helper fail.
echo '[]' > "$FAKE_OUTPUT"
if FAKE_RC=2 "$helper" bogus >/dev/null; then fail "task failure propagates"; else ok "task failure propagates"; fi

if ((fails)); then echo "$fails TEST(S) FAILED"; exit 1; fi
echo "ALL TESTS PASSED"

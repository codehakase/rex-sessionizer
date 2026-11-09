#!/usr/bin/env bash
# Behavioral tests: fake Rex server, real filesystem and fzf. Bash 3.2+.
set -euo pipefail

test_dir=$(cd -- "$(dirname -- "$0")" && pwd -P)
script=$test_dir/../rex-sessionizer
source_root=$HOME/Dev/personal/experiments
[[ -d $source_root ]] || { printf 'Missing source: %s\n' "$source_root" >&2; exit 1; }
command -v jq >/dev/null
command -v fzf >/dev/null

test_state=$(mktemp -d "${TMPDIR:-/tmp}/rex-sessionizer-tests.XXXXXX")
project=$(mktemp -d "$source_root/rex-sessionizer-test.XXXXXX")
spaced=$(mktemp -d "$source_root/rex-sessionizer test 'quote'.XXXXXX")
hidden=$(mktemp -d "$source_root/.rex-sessionizer-test.XXXXXX")
file=$(mktemp "$source_root/rex-sessionizer-file.XXXXXX")
link=$project-link
trap 'rm -rf -- "$test_state" "$project" "$spaced" "$hidden"; rm -f -- "$file" "$link"' EXIT
mkdir "$project/nested"
ln -s "$project" "$link"
project_name=${project##*/}
export TEST_STATE=$test_state
export REX_BIN=$test_dir/fake-rex
unset REX_CLIENT FZF_DEFAULT_OPTS FZF_DEFAULT_OPTS_FILE
unset TEST_CLIENTS TEST_LIST_FAIL TEST_NEW_FAIL TEST_SWITCH_FAIL

reset_state() {
    printf '{"sessions":[]}\n' > "$test_state/sessions.json"
    : > "$test_state/calls.jsonl"
}
run() {
    status=0
    output=$("$script" "$@" 2> "$test_state/stderr") || status=$?
}
assert_eq() {
    if [[ $1 != "$2" ]]; then
        printf 'FAIL: expected <%s>, got <%s>\n' "$2" "$1" >&2
        cat "$test_state/stderr" >&2
        exit 1
    fi
}
assert_error() {
    [[ $status -ne 0 ]] || { printf 'FAIL: expected failure\n' >&2; exit 1; }
    [[ $(cat "$test_state/stderr") == *"$1"* ]] || {
        cat "$test_state/stderr" >&2; exit 1;
    }
}
assert_no_new() {
    jq -es 'all(.[]; .[0] != "new")' "$test_state/calls.jsonl" >/dev/null
}
passed=0
pass() { passed=$((passed + 1)); printf 'ok %s - %s\n' "$passed" "$1"; }

reset_state
run --help
assert_eq "$status" 0
[[ ! -s $test_state/calls.jsonl ]]
pass 'help works without contacting Rex'

run --list
assert_eq "$status" 0
[[ $'\n'$output$'\n' == *$'\n'"$project_name"$'\n'* ]]
for excluded in nested "${hidden##*/}" "${file##*/}" "${link##*/}"; do
    [[ $'\n'$output$'\n' != *$'\n'"$excluded"$'\n'* ]]
done
[[ ! -s $test_state/calls.jsonl ]]
pass 'discovery includes only immediate visible directories from experiments'

run "$project_name"
assert_eq "$status" 0
assert_eq "$output" session:test-1
jq -e --arg cwd "$(cd "$project" && pwd -P)" \
    '.sessions | length == 1 and .[0].cwd == $cwd' "$test_state/sessions.json" >/dev/null
jq -es 'any(.[]; . == ["-C", "client:app", "do", "session.select", "session_id=session:test-1"])' \
    "$test_state/calls.jsonl" >/dev/null
pass 'first open creates the session in the project and selects the connected app'

run "$project/"
assert_eq "$status" 0
assert_eq "$output" session:test-1
assert_eq "$(jq '.sessions | length' "$test_state/sessions.json")" 1
pass 'canonical paths and repeated opens reuse the existing session'

run "${spaced##*/}"
assert_eq "$status" 0
assert_eq "$output" session:test-2
jq -e --arg cwd "$(cd "$spaced" && pwd -P)" '.sessions[1].cwd == $cwd' \
    "$test_state/sessions.json" >/dev/null
pass 'spaces and quotes in project names are passed literally'

reset_state
export FZF_DEFAULT_OPTS="--multi --expect=enter --print-query --filter=^$project_name\$"
run
assert_eq "$status" 0
assert_eq "$output" session:test-1
unset FZF_DEFAULT_OPTS
pass 'real fzf selects a project despite conflicting output defaults'

reset_state
export FZF_DEFAULT_OPTS='--filter=rex-sessionizer-no-such-project-000000'
run
assert_eq "$status" 0
assert_eq "$output" ''
[[ ! -s $test_state/calls.jsonl ]]
unset FZF_DEFAULT_OPTS
pass 'a picker with no match exits without contacting Rex'

export FZF_DEFAULT_OPTS='--an-invalid-fzf-option'
run
assert_error 'fzf failed'
[[ ! -s $test_state/calls.jsonl ]]
unset FZF_DEFAULT_OPTS
pass 'picker errors are reported instead of treated as cancellation'

for invalid in "$project/nested" "$test_state" "$link" "$link//" "$hidden" missing-project-000000; do
    run "$invalid"
    [[ $status -ne 0 ]]
done
[[ ! -s $test_state/calls.jsonl ]]
pass 'nested, external, linked, hidden, and missing directories are rejected'

run --list "$project_name"
assert_error '--list cannot be combined'
run --unknown
assert_error 'Unknown option'
run "$project_name" another
assert_error 'Expected at most one'
pass 'invalid arguments fail clearly'

export TEST_CLIENTS='{"clients":[]}'
run "$project_name"
assert_error 'Open the Rex app'
assert_no_new
pass 'no connected app fails before creating a session'

export TEST_CLIENTS='{"clients":[{"client_id":"client:a","info":{"kind":"app"}},{"client_id":"client:b","info":{"kind":"app"}}]}'
run "$project_name"
assert_error 'Multiple Rex apps'
assert_no_new
pass 'multiple apps require an explicit client before creating a session'

export REX_CLIENT=client:app
run "$project_name"
assert_eq "$status" 0
assert_eq "$output" session:test-1
unset REX_CLIENT TEST_CLIENTS
pass 'REX_CLIENT resolves multiple connected apps'

reset_state
export TEST_CLIENTS='{"clients":[]}'
run --no-switch "$project_name"
assert_eq "$status" 0
assert_eq "$output" session:test-1
jq -es 'all(.[]; .[0] != "client" and .[0] != "actions" and .[0] != "do")' \
    "$test_state/calls.jsonl" >/dev/null
unset TEST_CLIENTS
pass 'headless creation works without an app or client actions'

reset_state
export TEST_LIST_FAIL=1
run "$project_name"
assert_error 'Could not list Rex sessions'
assert_no_new
unset TEST_LIST_FAIL
pass 'a server listing failure does not create a duplicate session'

export TEST_NEW_FAIL=1
run "$project_name"
assert_error 'Could not create the project session'
jq -es 'all(.[]; .[0] != "-C" or .[2] != "do")' "$test_state/calls.jsonl" >/dev/null
unset TEST_NEW_FAIL
pass 'creation failures never attempt to select a nonexistent session'

reset_state
export TEST_SWITCH_FAIL=1
run "$project_name"
assert_error 'Remote Control'
unset TEST_SWITCH_FAIL
run "$project_name"
assert_eq "$status" 0
assert_eq "$output" session:test-1
assert_eq "$(jq '.sessions | length' "$test_state/sessions.json")" 1
pass 'retrying a failed switch reuses the created session'

jq '.sessions += [.sessions[0] | .session_id = "session:duplicate"]' \
    "$test_state/sessions.json" > "$test_state/next.json"
mv "$test_state/next.json" "$test_state/sessions.json"
: > "$test_state/calls.jsonl"
run "$project_name"
assert_error 'Multiple sessions have the label'
assert_no_new
pass 'duplicate labels fail rather than selecting an arbitrary session'

printf 'Passed %s tests.\n' "$passed"

#!/usr/bin/env bash
# Runs every offline regression test in this folder on Lua 5.1. From the repo root:
#   bash Tools/regression/run-all.sh
# Pick the interpreter with LUA=..., e.g. LUA="/c/Program Files (x86)/Lua/5.1/lua.exe".
set -u
LUA="${LUA:-lua5.1}"
cd "$(dirname "$0")/../.." || exit 1

# Tests that read the source file under test from their first argument.
args_for() {
    case "$1" in
        test-smart-minimap.lua)
            echo "Core/Options/Launchers.lua" ;;
        *) echo "" ;;
    esac
}

# Runs one test, with its source-file argument when it takes one.
run_test() {
    if [ -n "$2" ]; then "$LUA" "$1" "$2"; else "$LUA" "$1"; fi
}

pass=0
fail=0
for test in Tools/regression/test*.lua; do
    name="$(basename "$test")"
    arg="$(args_for "$name")"
    if output="$(run_test "$test" "$arg" 2>&1)"; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL $name"
        echo "$output" | tail -5 | sed 's/^/    /'
    fi
done
echo "passed $pass, failed $fail"
[ "$fail" -eq 0 ]

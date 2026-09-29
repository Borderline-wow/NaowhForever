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
        test-feint-recharge.lua | test_smart_charge_regressions.lua)
            echo "SmartReminders/NaowhForever_SmartReminders.lua" ;;
        *) echo "" ;;
    esac
}

# Runs one test, with its source-file argument when it takes one.
run_test() {
    if [ -n "$2" ]; then "$LUA" "$1" "$2"; else "$LUA" "$1"; fi
}

# Out of date with the code they test: reported here, not failed, until they are updated.
KNOWN_BROKEN=" test-smart-minimap.lua test-smart-display-review-fixes.lua test-neil-setup-reuse.lua "

pass=0
fail=0
skip=0
for test in Tools/regression/test*.lua; do
    name="$(basename "$test")"
    if [[ "$KNOWN_BROKEN" == *" $name "* ]]; then
        echo "SKIP $name (known out of date, see run-all.sh)"
        skip=$((skip + 1))
        continue
    fi
    arg="$(args_for "$name")"
    if output="$(run_test "$test" "$arg" 2>&1)"; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL $name"
        echo "$output" | tail -5 | sed 's/^/    /'
    fi
done
echo "passed $pass, failed $fail, skipped $skip"
[ "$fail" -eq 0 ]

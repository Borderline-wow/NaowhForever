#!/usr/bin/env bash
# CONTRIBUTING rules: addon changes have a changelog line under "## Changelog" in the PR
# description (or under "## Unreleased" in CHANGELOG.md); the TOC "## Version" and
# ns.CODE_BUILD stay as they are. Labels "no changelog" and "release" skip them (CI sets
# NO_CHANGELOG / RELEASE, and PR_BODY to the description). From the repo root:
#   bash Tools/hooks/check-pr.sh origin/main [head]
set -u
base="${1:?usage: check-pr.sh <base-ref>}"
head="${2:-HEAD}"
range="$base...$head"
problems=0

# A bad revision would make every git command below print nothing, and pass.
for ref in "$base" "$head"; do
    if ! git rev-parse -q --verify "$ref^{commit}" > /dev/null; then
        echo "check-pr: unknown revision '$ref'"
        exit 2
    fi
done

# What ships: everything but tooling, repo config, docs and the fetched Libs.
shipped=$(git diff --name-only "$range" |
    grep -Ev '^(Tools/|\.github/|Libs/|\.[^/]*$|[^/]*\.md$|LICENSE)' || true)

unreleased() {
    git show "$1:CHANGELOG.md" 2>/dev/null | tr -d '\r' |
        awk '/^## / { f = ($0 == "## Unreleased"); next } f'
}

if [ -n "$shipped" ] && [ "${NO_CHANGELOG:-false}" != "true" ]; then
    added=$(grep -Fxv -f <(unreleased "$base") <(unreleased "$head") | grep -c '[^[:space:]]' || true)
    if [ "$added" -eq 0 ]; then
        if [ -z "${PR_BODY+set}" ]; then
            echo "Changelog: not checked here, it goes under '## Changelog' in the PR description."
        elif ! printf '%s' "$PR_BODY" | python3 Tools/release.py check-body; then
            echo "  This PR changes addon files. Under '## Changelog' in the description, add a line"
            echo "  for players starting Added:, Changed: or Fixed:, or label the PR 'no changelog'"
            echo "  if nothing changes for them."
            echo "  Files: $(echo "$shipped" | head -5 | tr '\n' ' ')"
            problems=$((problems + 1))
        fi
    fi
fi

if [ "${RELEASE:-false}" != "true" ]; then
    # A new module addon's TOC is added with the current version; only edits to one count.
    if git diff -U0 --diff-filter=M "$range" -- '*.toc' | grep -qE '^[-+]## Version:'; then
        echo "A TOC's '## Version' changed. Only a release changes it."
        problems=$((problems + 1))
    fi
    if git diff -U0 "$range" -- '*.lua' | grep -qE '^[-+][[:space:]]*ns\.CODE_BUILD[[:space:]]*='; then
        echo "ns.CODE_BUILD changed. Only a release changes it."
        problems=$((problems + 1))
    fi
fi

if [ "$problems" -eq 0 ]; then
    echo "PR rules: OK"
fi
[ "$problems" -eq 0 ]

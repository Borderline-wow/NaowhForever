#!/usr/bin/env bash
# The daily watch's pull request for a change it made (.github/workflows/daily-watch.yml):
#   bash Tools/hooks/daily-pull-request.sh BRANCH TITLE BODY_FILE CHANGELOG_LINE PATH...
# Commits what changed under the paths on BRANCH, with CHANGELOG_LINE under "## Unreleased"
# (once: not again while the line is there), and opens the pull request, or brings the one
# already open up to date (its branch pushed again, its title and description). Where the
# organization does not let workflows open pull requests, one issue with a link that opens
# it in one click, kept up to date. Nothing changed under the paths: nothing happens.
# Needs GH_TOKEN, REPO, SERVER and RUN_ID.
set -euo pipefail

branch="$1"
title="$2"
body="$3"
changelog="$4"
shift 4

if [ -z "$(git status --porcelain -- "$@")" ]; then
  echo "Nothing changed: no pull request."
  exit 0
fi
if [ -n "$changelog" ] && ! grep -qF -- "$changelog" CHANGELOG.md; then
  python -c 'import sys; sys.path.insert(0, "Tools"); import watch_build; watch_build.add_changelog(sys.argv[1])' \
    "$changelog"
fi

git config user.name "github-actions[bot]"
git config user.email "41898299+github-actions[bot]@users.noreply.github.com"
git switch -c "$branch"
git add -- "$@" CHANGELOG.md
git commit -q -m "$title"
gh auth setup-git
git push --force origin "$branch"

{
  cat "$body"
  echo
  echo "---"
  echo "Opened by the daily watch (.github/workflows/daily-watch.yml); last run: $SERVER/$REPO/actions/runs/$RUN_ID."
  echo "Checks do not run on a pull request a workflow opens: close and reopen it to run them."
  echo "The branch is rebuilt from main by each run: merge or close it, don't push to it."
} > pr.md

pr="$(gh pr list --head "$branch" --state open --json url --jq '.[0].url // empty')"
if [ -n "$pr" ]; then
  gh pr edit "$pr" --title "$title" --body-file pr.md
  echo "Brought up to date: $pr"
  exit 0
fi
if gh pr create --base main --head "$branch" --title "$title" --body-file pr.md 2> create.err; then
  exit 0
fi
cat create.err >&2
if ! grep -qi "not permitted to create" create.err; then
  echo "::error::The pull request could not be opened (see above)."
  exit 1
fi

echo "::warning::Workflows may not open pull requests here: an issue instead."
issue_title="$title (open its pull request)"
issue="$(gh issue list --state open --search "author:app/github-actions in:title \"$issue_title\"" \
  --json number --jq '.[0].number // empty')"
link="$SERVER/$REPO/compare/main...$branch?quick_pull=1&title=$(jq -rn --arg t "$title" '$t|@uri')"
{
  echo "**[Open the pull request]($link)**: the branch \`$branch\` holds the change."
  echo
  cat pr.md
} > issue.md
if [ -n "$issue" ]; then
  gh issue edit "$issue" --body-file issue.md
else
  gh issue create --title "$issue_title" --body-file issue.md
fi

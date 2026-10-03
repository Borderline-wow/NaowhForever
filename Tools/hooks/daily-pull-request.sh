#!/usr/bin/env bash
# The daily watch's one pull request (.github/workflows/daily-watch.yml). Its checks run one
# after another on one branch; each that changed something adds it:
#   bash Tools/hooks/daily-pull-request.sh add NAME SHORT REPORT CHANGELOG_LINE PATH...
# commits what changed under the paths (with CHANGELOG_LINE under "## Unreleased", once; empty
# for none), for a check that fails after it to go back to, and notes SHORT (what it is, a few
# words for the title), its line for the list (CHANGELOG_LINE, else SHORT) and REPORT (for the
# description). Nothing changed under the paths: nothing.
#   bash Tools/hooks/daily-pull-request.sh hold REASON_FILE
# keeps the pull request a draft, REASON_FILE's text at the top of its description: what must
# be done on our machines before it can be merged (a BiS pick CI could not find a source for).
#   bash Tools/hooks/daily-pull-request.sh open BRANCH
# squashes what was added into one commit (it is merged as one: its title and short list are
# the squash's message), pushes BRANCH and opens the pull request, or brings the one already
# open up to date. Where the organization does not let workflows open pull requests, one
# issue with a link that opens it in one click, kept up to date. Nothing added: nothing.
# Needs BASE (the commit the run started from) and, for open, GH_TOKEN, REPO, SERVER, RUN_ID.
set -euo pipefail

notes="${RUNNER_TEMP:-/tmp}/daily-changes"
mkdir -p "$notes"
REPORT_LINES=120   # each report in the description, at most; the run has them whole

add() {
  local name="$1" short="$2" report="$3" changelog="$4"
  shift 4
  if [ -z "$(git status --porcelain -- "$@")" ]; then
    echo "$name: nothing changed."
    return 0
  fi
  if [ -n "$changelog" ] && ! grep -qF -- "$changelog" CHANGELOG.md; then
    python -c 'import sys; sys.path.insert(0, "Tools"); import watch_build; watch_build.add_changelog(sys.argv[1])' \
      "$changelog"
  fi
  git add -- "$@" CHANGELOG.md
  git commit -q -m "daily: $name"
  local line="${changelog#- }"
  printf '%s\t%s\t%s\n' "$name" "$short" "${line:-$short}" >> "$notes/list"
  cp "$report" "$notes/$name.md"
  echo "$name: added ($short)."
}

hold() {
  cat "$1" >> "$notes/hold.md"
  echo "Held as a draft: $(head -n 1 "$1")"
}

# "a", "a and b", "a, b and c".
join() {
  local out="" i=0 n=$#
  for part in "$@"; do
    i=$((i + 1))
    if [ "$i" -eq 1 ]; then out="$part"
    elif [ "$i" -eq "$n" ]; then out="$out and $part"
    else out="$out, $part"; fi
  done
  printf '%s' "$out"
}

open_pr() {
  local branch="$1"
  if [ ! -s "$notes/list" ]; then
    echo "Nothing changed: no pull request."
    return 0
  fi
  local names=() shorts=() lines=()
  while IFS=$'\t' read -r name short line; do
    names+=("$name")
    shorts+=("$short")
    lines+=("$line")
  done < "$notes/list"
  local title
  title="chore(data): $(join "${shorts[@]}")"

  # One commit: the title, and what is in it.
  local list=""
  for line in "${lines[@]}"; do list="$list- $line"$'\n'; done
  git reset -q --soft "$BASE"
  git commit -q -m "$title" -m "${list%$'\n'}"

  # A draft while something must be done by hand first; ready once a run finds nothing.
  local draft=false
  if [ -s "$notes/hold.md" ]; then draft=true; fi

  # The description: what holds it, the list, each check's report folded away, the run.
  {
    if [ "$draft" = true ]; then
      echo "> [!WARNING]"
      echo "> **A draft until this is done on our machines:**"
      sed 's/^/> /' "$notes/hold.md"
      echo
    fi
    echo "Today's data changes, in one pull request (it squash merges as one commit):"
    echo
    printf '%s' "$list"
    for i in "${!names[@]}"; do
      echo
      echo "<details><summary>${shorts[$i]}: its report</summary>"
      echo
      head -n "$REPORT_LINES" "$notes/${names[$i]}.md"
      if [ "$(wc -l < "$notes/${names[$i]}.md")" -gt "$REPORT_LINES" ]; then
        echo
        echo "_Cut short: the whole report is in the run below._"
      fi
      echo
      echo "</details>"
    done
    echo
    echo "---"
    echo "Opened by the daily watch (.github/workflows/daily-watch.yml); last run: $SERVER/$REPO/actions/runs/$RUN_ID."
    echo "Checks do not run on a pull request a workflow opens: close and reopen it to run them."
    echo "The branch is rebuilt from main by each run: merge or close it, don't push to it."
  } > "$notes/pr.md"

  # A change with no line in the CHANGELOG changes nothing for players: it says so.
  local label=() link_label=""
  if git diff --quiet "$BASE" HEAD -- CHANGELOG.md; then
    label=(--label "no changelog")
    link_label="&labels=no+changelog"
  fi

  gh auth setup-git
  git push --force origin "HEAD:refs/heads/$branch"

  local issue_title="Daily data update: open its pull request"
  local issue
  issue="$(gh issue list --state open --search "author:app/github-actions in:title \"$issue_title\"" \
    --json number --jq '.[0].number // empty')"
  local pr
  pr="$(gh pr list --head "$branch" --state open --json url --jq '.[0].url // empty')"
  if [ -n "$pr" ]; then
    gh pr edit "$pr" --title "$title" --body-file "$notes/pr.md"
    if [ "$draft" = true ]; then gh pr ready "$pr" --undo; else gh pr ready "$pr"; fi
    echo "Brought up to date: $pr"
    return 0
  fi
  local as_draft=()
  if [ "$draft" = true ]; then as_draft=(--draft); fi
  if gh pr create --base main --head "$branch" "${label[@]}" "${as_draft[@]}" --title "$title" \
      --body-file "$notes/pr.md" 2> "$notes/create.err"; then
    if [ -n "$issue" ]; then
      gh issue close "$issue" --comment "Opened: $(gh pr list --head "$branch" --json url --jq '.[0].url')"
    fi
    return 0
  fi
  cat "$notes/create.err" >&2
  if ! grep -qi "not permitted to create" "$notes/create.err"; then
    echo "::error::The pull request could not be opened (see above)."
    return 1
  fi

  echo "::warning::Workflows may not open pull requests here: an issue instead."
  local link="$SERVER/$REPO/compare/main...$branch?quick_pull=1$link_label"
  link="$link&title=$(jq -rn --arg t "$title" '$t|@uri')"
  {
    echo "**[Open the pull request]($link)**: the branch \`$branch\` holds today's data changes."
    echo "This repository's workflows may not open pull requests themselves (Settings, Actions,"
    echo "General: \"Allow GitHub Actions to create and approve pull requests\")."
    echo
    cat "$notes/pr.md"
  } > "$notes/issue.md"
  if [ -n "$issue" ]; then
    gh issue edit "$issue" --body-file "$notes/issue.md"
  else
    gh issue create --title "$issue_title" --body-file "$notes/issue.md"
  fi
}

case "${1:-}" in
  add) shift; add "$@" ;;
  hold) shift; hold "$@" ;;
  open) shift; open_pr "$@" ;;
  *) echo "usage: daily-pull-request.sh add NAME SHORT REPORT CHANGELOG_LINE PATH... | hold REASON_FILE | open BRANCH" >&2
     exit 2 ;;
esac

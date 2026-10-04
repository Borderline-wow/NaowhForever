"""Release helper for .github/workflows/release.yml. From the repo root:

    python Tools/release.py prepare [--bump patch|minor|major] [--beta | --no-beta]
                                    [--version V]
    python Tools/release.py notes <tag>
    python Tools/release.py start-next
    python Tools/release.py pending
    python Tools/release.py check-body < description.md

prepare: each pull request merged since the newest tag adds the lines under "## Changelog" in
its description to "## Unreleased" (one that edited CHANGELOG.md itself is skipped), then
"## Unreleased" in CHANGELOG.md becomes "## <version>", the in-game notes' "Unreleased"
entry (Core/NaowhForever_PatchNotes.lua) takes the version as its title, and the TOC "## Version"
and ns.CODE_BUILD are set to it; prints the version. The version is the newest tag bumped
(patch: 0.5.16-beta -> 0.5.17-beta, minor: -> 0.6.0-beta, major: -> 1.0.0-beta), with
"-beta" added (--beta), dropped (--no-beta) or kept as the tag has it; --version overrides
all that. Versions before 1.0.0 must be betas or alphas. Everything is checked before
any file is written, and each file keeps its line endings.

notes: the tag's CHANGELOG.md section for players, then every commit since the previous
tag, grouped by Conventional Commit type.

start-next: an empty "## Unreleased" back at the top of CHANGELOG.md after a release, so
the next pull request only adds its line. Does nothing if the heading is already there.

pending: "## Unreleased" as the next release would write it, from the pull requests merged so
far. Needs gh, signed in.

check-body: a pull request description on stdin has at least one changelog line, for CI.
"""
import argparse
import re
import subprocess
import sys
import textwrap
from pathlib import Path

TOC = "NaowhForever.toc"
CORE = "Core/NaowhForever_Core.lua"
CHANGELOG = "CHANGELOG.md"
PATCH_NOTES = "Core/NaowhForever_PatchNotes.lua"

VERSION = re.compile(r"(\d+)\.(\d+)\.(\d+)(-[0-9A-Za-z.]+)?")
TYPES = "feat|fix|perf|refactor|docs|test|ci|build|chore|revert"
SUBJECT = re.compile(rf"({TYPES})(?:\(([^)]*)\))?!?: (.+)")
GROUPS = {"feat": "Features", "fix": "Fixes", "perf": "Performance"}
ORDER = ("Features", "Fixes", "Performance", "Other changes")
KINDS = ("Added", "Changed", "Fixed")
ENTRY = re.compile(r"(?:[-*] +)?(added|changed|fixed):[ \t]*(.*)", re.IGNORECASE)
# A squash merge ends the subject with the pull request's number.
PR_NUMBER = re.compile(r"\(#(\d+)\)$")


class ReleaseError(Exception):
    pass


def git(root, *args, check=True):
    result = subprocess.run(["git", *args], cwd=root, capture_output=True, text=True)
    if check and result.returncode != 0:
        raise ReleaseError(f"git {' '.join(args)}: {result.stderr.strip()}")
    return result


def read(root, name):
    with open(Path(root) / name, encoding="utf-8", newline="") as f:
        return f.read()


def write(root, name, text):
    with open(Path(root) / name, "w", encoding="utf-8", newline="") as f:
        f.write(text)


def tag_exists(root, tag):
    return git(root, "rev-parse", "-q", "--verify", f"refs/tags/{tag}", check=False).returncode == 0


def newest_tag(root):
    tags = [t for t in git(root, "tag", "--list").stdout.split() if VERSION.fullmatch(t)]
    if not tags:
        return None
    # 1.0.0 is newer than 1.0.0-beta.
    return max(tags, key=lambda t: (*(int(n) for n in VERSION.fullmatch(t).groups()[:3]),
                                    VERSION.fullmatch(t).group(4) is None))


def next_version(tag, bump="patch", beta=None):
    """The version after tag. beta: True adds "-beta", False drops any suffix, None keeps it."""
    major, minor, patch, suffix = VERSION.fullmatch(tag).groups()
    major, minor, patch = int(major), int(minor), int(patch)
    if bump == "major":
        major, minor, patch = major + 1, 0, 0
    elif bump == "minor":
        minor, patch = minor + 1, 0
    else:
        patch += 1
    if beta is not None:
        suffix = "-beta" if beta else ""
    return f"{major}.{minor}.{patch}{suffix or ''}"


def section(text, heading):
    """The lines under "## heading", up to the next "## ", or None without that heading."""
    lines = [line.rstrip() for line in text.splitlines()]
    try:
        start = lines.index(f"## {heading}") + 1
    except ValueError:
        return None
    end = next((i for i in range(start, len(lines)) if lines[i].startswith("## ")), len(lines))
    return lines[start:end]


def replace_line(text, pattern, replacement, missing):
    new, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise ReleaseError(missing)
    return new


def body_entries(body):
    """The "## Changelog" lines of a pull request description as (kind, text) pairs, or None
    without that section. An entry starts "Added:", "Changed:" or "Fixed:"; lines after it
    carry on the same entry."""
    text = re.sub(r"<!--.*?-->", "", (body or "").replace("\r", ""), flags=re.DOTALL)
    lines = section(text, "Changelog")
    if lines is None:
        return None
    entries = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        match = ENTRY.fullmatch(line)
        if match:
            entries.append([match.group(1).capitalize(), match.group(2)])
        elif entries:
            entries[-1][1] += " " + line
        else:
            raise ReleaseError("changelog lines start with Added:, Changed: or Fixed:, "
                               f"not: {line}")
    return [(kind, text.strip()) for kind, text in entries if text.strip()]


def pr_body(root, number):
    result = subprocess.run(["gh", "pr", "view", number, "--json", "body", "--jq", ".body"],
                            cwd=root, capture_output=True, text=True)
    if result.returncode != 0:
        raise ReleaseError(f"gh pr view {number}: {result.stderr.strip()}")
    return result.stdout


def merged_entries(root, since, fetch_body):
    """Changelog entries from the descriptions of the pull requests merged after since."""
    entries = []
    log = git(root, "log", "--reverse", "--first-parent", "--format=%H%x09%s",
              f"{since}..HEAD").stdout
    for line in log.splitlines():
        commit, subject = line.split("\t", 1)
        match = PR_NUMBER.search(subject)
        if not match:
            continue
        if git(root, "diff", "--quiet", f"{commit}^", commit, "--", CHANGELOG,
               check=False).returncode:
            continue
        try:
            entries += body_entries(fetch_body(root, match.group(1))) or []
        except ReleaseError as error:
            raise ReleaseError(f"#{match.group(1)}: {error}") from None
    return entries


def add_entries(changelog, entries):
    """changelog with entries added under their "### " heading in "## Unreleased"."""
    newline = "\r\n" if "\r\n" in changelog else "\n"
    lines = changelog.replace("\r\n", "\n").split("\n")
    start = next(i for i, line in enumerate(lines) if line.rstrip() == "## Unreleased") + 1
    for index, kind in enumerate(KINDS):
        items = []
        for _, text in filter(lambda entry: entry[0] == kind, entries):
            items += textwrap.wrap(f"- {text}", width=100, subsequent_indent="  ",
                                   break_long_words=False, break_on_hyphens=False)
        if not items:
            continue
        end = next((i for i in range(start, len(lines)) if lines[i].startswith("## ")),
                   len(lines))
        headings = {lines[i].rstrip(): i for i in range(start, end) if lines[i].startswith("### ")}
        if f"### {kind}" in headings:
            at = headings[f"### {kind}"] + 1
            while at < end and not lines[at].startswith("#"):
                at += 1
            while not lines[at - 1].strip():
                at -= 1
            lines[at:at] = items
            continue
        later = [headings[f"### {k}"] for k in KINDS[index + 1:] if f"### {k}" in headings]
        if later:
            lines[later[0]:later[0]] = [f"### {kind}", *items, ""]
        else:
            at = end
            while at > start and not lines[at - 1].strip():
                at -= 1
            lines[at:at] = ["", f"### {kind}", *items]
    return newline.join(lines)


def prepare(root, version=None, bump="patch", beta=None, fetch_body=pr_body):
    tag = newest_tag(root)
    if not version:
        if not tag:
            raise ReleaseError("no version tag yet: give the version")
        version = next_version(tag, bump, beta)
    match = VERSION.fullmatch(version)
    if not match:
        raise ReleaseError(f"'{version}' is not a version like 0.5.17-beta")
    # The packager publishes a tag without "beta" or "alpha" as a full release everywhere,
    # CurseForge included; before 1.0.0 every release is a pre-release.
    suffix = (match.group(4) or "").lower()
    if match.group(1) == "0" and "beta" not in suffix and "alpha" not in suffix:
        raise ReleaseError(f"{version}: versions before 1.0.0 are pre-releases, tick Beta")
    if tag_exists(root, version):
        raise ReleaseError(f"tag {version} already exists")

    # Only the newest section counts: the changelog still has 1.0.0 to 1.3.1 from before the
    # numbering restarted at 0.5.
    changelog = read(root, CHANGELOG)
    plain = changelog.replace("\r", "")
    first = next((line[3:].strip() for line in plain.splitlines() if line.startswith("## ")),
                 None)
    if first == "Unreleased":
        if tag:
            changelog = add_entries(changelog, merged_entries(root, tag, fetch_body))
            plain = changelog.replace("\r", "")
        if not any(line.strip() for line in section(plain, "Unreleased")):
            raise ReleaseError(f"'## Unreleased' in {CHANGELOG} is empty: nothing to release")
        changelog = replace_line(changelog, r"^## Unreleased[ \t]*(?=\r?$)", f"## {version}",
                                 f"{CHANGELOG}: no '## Unreleased' line")
    elif first != version:
        raise ReleaseError(f"{CHANGELOG} must start with '## Unreleased' or '## {version}', "
                           f"not '## {first}'")

    toc = replace_line(read(root, TOC), r"^(## Version:[ \t]*)[^\r\n]*", rf"\g<1>{version}",
                       f"{TOC} has no '## Version' line")
    core = replace_line(read(root, CORE), r'^(ns\.CODE_BUILD = ")[^"\r\n]*(")',
                        rf"\g<1>{version}\g<2>", f"{CORE} has no ns.CODE_BUILD line")
    # The in-game notes name the coming release "Unreleased" until it has a version, as the
    # changelog does; a release without in-game notes leaves the file as it is.
    patch_notes = None
    if (Path(root) / PATCH_NOTES).exists():
        text = read(root, PATCH_NOTES)
        renamed, count = re.subn(r'\{ title = "Unreleased"', f'{{ title = "{version}"', text, count=1)
        if count:
            patch_notes = renamed

    write(root, CHANGELOG, changelog)
    write(root, TOC, toc)
    write(root, CORE, core)
    if patch_notes is not None:
        write(root, PATCH_NOTES, patch_notes)
    return version


def notes(root, tag):
    player = section(read(root, CHANGELOG).replace("\r", ""), tag) or []
    while player and not player[0].strip():
        player.pop(0)
    while player and not player[-1].strip():
        player.pop()

    previous = git(root, "describe", "--tags", "--abbrev=0", f"{tag}^", check=False)
    previous = previous.stdout.strip() if previous.returncode == 0 else None
    log = git(root, "log", "--no-merges", "--format=%h%x09%s",
              f"{previous}..{tag}" if previous else tag).stdout

    grouped = {}
    for line in log.splitlines():
        commit, subject = line.split("\t", 1)
        # Release commits: "chore(release): x" now, a bare "x" before.
        if subject.startswith("chore(release)") or subject == tag:
            continue
        name, text = "Other changes", subject
        match = SUBJECT.fullmatch(subject)
        if match:
            kind, scope, summary = match.groups()
            name = GROUPS.get(kind, "Other changes")
            text = f"**{scope}:** {summary}" if scope else summary
        grouped.setdefault(name, []).append(f"- {text} ({commit})")

    out = ["## What's new", "", *player, ""]
    out += [f"## Commits since {previous}" if previous else "## Commits", ""]
    for name in ORDER:
        if name in grouped:
            out += [f"### {name}", "", *grouped[name], ""]
    return "\n".join(out)


def pending(root, fetch_body=pr_body):
    tag = newest_tag(root)
    if not tag:
        raise ReleaseError("no version tag yet")
    changelog = read(root, CHANGELOG).replace("\r", "")
    if section(changelog, "Unreleased") is None:
        raise ReleaseError(f"{CHANGELOG} has no '## Unreleased'")
    changelog = add_entries(changelog, merged_entries(root, tag, fetch_body))
    return "\n".join(["## Unreleased", *section(changelog, "Unreleased")]).rstrip()


def start_next(root):
    changelog = read(root, CHANGELOG)
    lines = changelog.replace("\r", "").splitlines()
    first = next((i for i, line in enumerate(lines) if line.startswith("## ")), None)
    if first is not None and lines[first].rstrip() == "## Unreleased":
        return False
    newline = "\r\n" if "\r\n" in changelog else "\n"
    heading = f"## Unreleased{newline}{newline}"
    if first is None:
        changelog = changelog.rstrip("\r\n") + newline + newline + heading
    else:
        changelog = re.sub(r"^## ", lambda _: heading + "## ", changelog, count=1,
                           flags=re.MULTILINE)
    write(root, CHANGELOG, changelog)
    return True


def main(argv=None):
    parser = argparse.ArgumentParser(description="Release helper for the Release workflow.")
    commands = parser.add_subparsers(dest="command", required=True)
    prepare_args = commands.add_parser("prepare")
    prepare_args.add_argument("--bump", choices=("patch", "minor", "major"), default="patch")
    prepare_args.add_argument("--beta", action=argparse.BooleanOptionalAction, default=None)
    prepare_args.add_argument("--version")
    commands.add_parser("notes").add_argument("tag")
    commands.add_parser("start-next")
    commands.add_parser("pending")
    commands.add_parser("check-body")
    args = parser.parse_args(argv)
    try:
        if args.command == "prepare":
            print(prepare(".", args.version, args.bump, args.beta))
        elif args.command == "notes":
            print(notes(".", args.tag))
        elif args.command == "pending":
            print(pending("."))
        elif args.command == "check-body":
            entries = body_entries(sys.stdin.read())
            if not entries:
                raise ReleaseError("no changelog line under '## Changelog' in the description")
            print(f"Changelog: {len(entries)} line(s) in the description")
        else:
            start_next(".")
    except ReleaseError as error:
        print(f"release: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

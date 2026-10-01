"""Checks that every file NaowhForever.toc loads exists, with the same letter case.

The game only reports a missing file as an error at login, and a path whose case differs
works on one machine and fails on another. Follows the XML files the TOC includes (see
toc_files.py), so a module's own load file is checked too. The libraries' files that
Libs/embeds.xml lists are not in git (the packager fetches them, see .pkgmeta), so they are
left to check-package.sh, which checks the built package. Run from the repo root.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from toc_files import files  # noqa: E402


def exists_exact(path):
    current = "."
    for part in path.split("/"):
        try:
            names = os.listdir(current)
        except OSError:
            return False
        if part not in names:
            return False
        current = os.path.join(current, part)
    return True


def main():
    problems = [f"{listed_at}: {path} is missing or its case differs"
                for path, listed_at in files()
                if not listed_at.startswith("Libs/") and not exists_exact(path)]
    for problem in problems:
        print(problem)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())

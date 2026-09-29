"""Checks that every file NaowhForever.toc loads exists, with the same letter case.

The game only reports a missing file as an error at login, and a path whose case differs
works on one machine and fails on another. Run from the repo root.
"""
import os
import sys

TOC = "NaowhForever.toc"


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
    problems = []
    with open(TOC, encoding="utf-8") as toc:
        for number, line in enumerate(toc, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            # "Locales\deDE.lua [AllowLoadTextLocale deDE]": the path is before the options.
            path = line.split(" [", 1)[0].strip().replace("\\", "/")
            if not exists_exact(path):
                problems.append(f"{TOC}:{number}: {path} is missing or its case differs")
    for problem in problems:
        print(problem)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())

"""Every file the TOCs load, in load order, following XML includes.

A module can load through its own XML file (NaowhForever_DungeonJournal/DungeonJournal.xml) instead of
listing each file in the TOC, so a check that reads only the TOC's lines would miss those
files. files() walks the TOC and expands each XML's <Script file> and <Include file>
entries, recursively. As the game does, a path in an XML is looked up next to that XML
first, then from the addon's root (Libs/embeds.xml writes them that way).

Used by check_toc.py and check-package.sh. Run from the repo root to print the list:
    python Tools/hooks/toc_files.py
"""
import os
import re
import sys

TOC = "NaowhForever.toc"
ENTRY = re.compile(r"""<(Script|Include)\s+file\s*=\s*["']([^"']+)["']""")
COMMENT = re.compile(r"<!--.*?-->", re.S)


def toc_paths(toc=TOC):
    """The TOC's own entries: (line number, path), with / separators."""
    with open(toc, encoding="utf-8") as lines:
        for number, line in enumerate(lines, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            # "Locales\deDE.lua [AllowLoadTextLocale deDE]": the path is before the options.
            yield number, line.split(" [", 1)[0].strip().replace("\\", "/")


def resolve(xml_path, entry):
    """Where an XML entry points: next to the XML if that exists, else from the root."""
    entry = entry.replace("\\", "/")
    beside = os.path.normpath(os.path.join(os.path.dirname(xml_path), entry)).replace("\\", "/")
    return beside if os.path.exists(beside) else entry


def tocs():
    """NaowhForever.toc, then each module addon .pkgmeta moves out of NaowhForever/, in the
    order it lists them: (folder prefix, TOC path). A module's TOC paths are relative to its
    own folder."""
    found = [("", TOC)]
    with open(".pkgmeta", encoding="utf-8") as meta:
        for line in meta:
            child = re.match(r"\s+NaowhForever/(\S+):", line)
            if child:
                name = child.group(1)
                found.append((name + "/", f"{name}/{name}.toc"))
    return found


def files(toc=None):
    """(path, where it is listed) for every file loaded, XML files included, in order."""
    for prefix, name in [("", toc)] if toc else tocs():
        for number, path in toc_paths(name):
            yield from expand(prefix + path, f"{name}:{number}")


def expand(path, listed_at, seen=None):
    seen = seen if seen is not None else set()
    yield path, listed_at
    if not path.lower().endswith(".xml") or path in seen or not os.path.exists(path):
        return
    seen.add(path)
    with open(path, encoding="utf-8") as xml:
        text = COMMENT.sub("", xml.read())
    for number, line in enumerate(text.splitlines(), 1):
        for _, entry in ENTRY.findall(line):
            yield from expand(resolve(path, entry), f"{path}:{number}", seen)


if __name__ == "__main__":
    for found, _ in files():
        print(found)
    sys.exit(0)

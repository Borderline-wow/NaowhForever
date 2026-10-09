"""Where the tools, their data and the addon are, for every Python script under Tools/.

A script in one of Tools' folders starts with

    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    import paths  # noqa: E402

which finds this file; importing it puts the tool folders on the path too, so `import wago`
or `from journal import header` works from any folder, and the tests can import any tool.
"""
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parent      # the repo: the addon's folders and Tools/
DATA = TOOLS / "data"    # every JSON input and cache the tools read and write

for folder in ("release", "build", "sources"):
    path = str(TOOLS / folder)
    if path not in sys.path:
        sys.path.insert(1, path)

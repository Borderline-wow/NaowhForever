#!/usr/bin/env bash
# Checks the zip the packager built in .release: one NaowhForever/ folder at the top, every
# file the TOC loads and every library .pkgmeta fetches is inside, and no tooling ships.
set -u
shopt -s nullglob
zips=(.release/*.zip)
if [ "${#zips[@]}" -ne 1 ]; then
    echo "Expected one zip in .release, found ${#zips[@]}."
    exit 1
fi
zip="${zips[0]}"
echo "Checking $zip"
list=$(unzip -Z1 "$zip")
problems=0
fail() { echo "  $1"; problems=$((problems + 1)); }

outside=$(echo "$list" | grep -v '^NaowhForever/' || true)
[ -z "$outside" ] || fail "outside the NaowhForever/ folder: $(echo "$outside" | head -3 | tr '\n' ' ')"

has() { echo "$list" | grep -qxF "NaowhForever/$1"; }

while IFS= read -r line; do
    line="${line%$'\r'}"
    case "$line" in "" | "#"* | " "*) continue ;; esac
    path="${line%% \[*}"
    path="${path//\\//}"
    has "$path" || fail "TOC file missing: $path"
done < NaowhForever.toc

while IFS= read -r dir; do
    echo "$list" | grep -q "^NaowhForever/$dir/." || fail "library missing: $dir"
done < <(tr -d '\r' < .pkgmeta | sed -n 's/^  \(Libs\/[^:]*\):.*/\1/p')

shipped_tooling=$(echo "$list" | grep -E '^NaowhForever/(Tools/|\.github/|\.luacheckrc|\.pre-commit-config)' || true)
[ -z "$shipped_tooling" ] || fail "tooling in the package: $(echo "$shipped_tooling" | head -3 | tr '\n' ' ')"

if [ "$problems" -eq 0 ]; then
    echo "Package: OK ($(echo "$list" | wc -l) entries)"
fi
[ "$problems" -eq 0 ]

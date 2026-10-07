#!/usr/bin/env bash
# Checks the zip the packager built in .release: NaowhForever/ and each module addon
# (NaowhForever_<Module>/, moved out by .pkgmeta) at the top, every file the TOCs load
# (following the XML files they include) and every library .pkgmeta fetches is inside, and
# no tooling ships.
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

children=$(tr -d '\r' < .pkgmeta | sed -n 's/^  NaowhForever\/\(NaowhForever_[^:]*\):.*/\1/p')
allowed="NaowhForever"
for child in $children; do allowed="$allowed|$child"; done
outside=$(echo "$list" | grep -vE "^($allowed)/" || true)
[ -z "$outside" ] || fail "outside the addon folders: $(echo "$outside" | head -3 | tr '\n' ' ')"

# A module addon's files sit in its own folder at the top of the zip, the rest in NaowhForever/.
has() {
    case "$1" in
        NaowhForever_*) echo "$list" | grep -qxF "$1" ;;
        *) echo "$list" | grep -qxF "NaowhForever/$1" ;;
    esac
}

for child in $children; do
    has "$child/$child.toc" || fail "TOC missing: $child/$child.toc"
    if echo "$list" | grep -q "^NaowhForever/$child/"; then fail "$child is still inside NaowhForever/"; fi
done

# Every file the TOCs load, following their XML includes (Tools/hooks/toc_files.py).
while IFS= read -r path; do
    path="${path%$'\r'}"
    [ -n "$path" ] || continue
    has "$path" || fail "TOC file missing: $path"
done < <(python3 Tools/hooks/toc_files.py)

while IFS= read -r dir; do
    echo "$list" | grep -q "^NaowhForever/$dir/." || fail "library missing: $dir"
done < <(tr -d '\r' < .pkgmeta | sed -n 's/^  \(Libs\/[^:]*\):.*/\1/p')

shipped_tooling=$(echo "$list" | grep -E '^NaowhForever/(Tools/|\.github/|\.luacheckrc|\.pre-commit-config)' || true)
[ -z "$shipped_tooling" ] || fail "tooling in the package: $(echo "$shipped_tooling" | head -3 | tr '\n' ' ')"

if [ "$problems" -eq 0 ]; then
    echo "Package: OK ($(echo "$list" | wc -l) entries)"
fi
[ "$problems" -eq 0 ]

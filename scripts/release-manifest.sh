#!/bin/sh
set -eu

usage="usage: release-manifest.sh <tag> <repository-url> <notes-file>

Prints latest.json for <tag>: the version, the release notes and the release page, archive and
checksum URLs. Nook reads it from the latest release to offer an update."
[ "$#" -eq 3 ] || { echo "$usage" >&2; exit 64; }

tag="$1"
repository_url="${2%/}"
notes_file="$3"

[ -f "$notes_file" ] || { echo "notes file not found: $notes_file" >&2; exit 66; }
# Matches a version tag such as v1.2.3 or v1.2.3-beta.1
echo "$tag" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$' || { echo "invalid version tag: $tag" >&2; exit 65; }

download_url="$repository_url/releases/download/$tag"
jq -n \
    --arg version "${tag#v}" \
    --rawfile notes "$notes_file" \
    --arg page "$repository_url/releases/tag/$tag" \
    --arg archive "$download_url/Nook.zip" \
    --arg checksum "$download_url/Nook.zip.sha256" \
    '{version: $version, notes: $notes, page: $page, archive: $archive, checksum: $checksum}'

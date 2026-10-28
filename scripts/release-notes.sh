#!/bin/sh
set -eu

usage="usage: release-notes.sh <tag> <repository-url>

Prints release notes for <tag>: one bullet per feat, fix or perf commit since the previous tag,
skipping commits scoped to the website, then a link to the full comparison."
[ "$#" -eq 2 ] || { echo "$usage" >&2; exit 64; }

tag="$1"
repository_url="$2"

git rev-parse --verify --quiet "$tag^{commit}" >/dev/null || { echo "unknown tag: $tag" >&2; exit 65; }
previous_tag="$(git describe --tags --abbrev=0 "$tag^" 2>/dev/null || true)"
range="$tag"
[ -z "$previous_tag" ] || range="$previous_tag..$tag"

# Matches a feat, fix or perf subject with an optional scope other than website, and captures the description
subject_pattern='^(feat|fix|perf)(\(([^)]*)\))?!?: (.+)$'

highlights="$(git log --no-merges --format=%s "$range" | sed -nE "/^(feat|fix|perf)\\(website\\)/d; s/$subject_pattern/\\4/p" | awk '{ print "- " toupper(substr($0, 1, 1)) substr($0, 2) }')"

if [ -n "$highlights" ]; then
    echo "## What's new"
    echo
    echo "$highlights"
    echo
fi
if [ -n "$previous_tag" ]; then
    echo "**Full changelog**: $repository_url/compare/$previous_tag...$tag"
fi

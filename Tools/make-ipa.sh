#!/bin/bash
#
#  make-ipa.sh
#  Tracey
#
#  Builds an unsigned Release .ipa (for sideloading, e.g. LiveContainer) at
#  build/Tracey-<version>-unsigned.ipa.
#
#  Versioning: the version people see (1.0) is MARKETING_VERSION in the project and only changes
#  by hand for a release. The build number is the commit count of HEAD, so every commit gets a
#  higher one (App Store Connect rejects a repeated build number) and any build maps back to
#  its commit with `git rev-list --reverse HEAD | sed -n <build>p`.
#
#  Usage: Tools/make-ipa.sh            (refuses uncommitted changes)
#         ALLOW_DIRTY=1 Tools/make-ipa.sh
#

set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -n "$(git status --porcelain)" && "${ALLOW_DIRTY:-0}" != 1 ]]; then
    echo "Uncommitted changes: the build number wouldn't match a commit. Commit first, or set ALLOW_DIRTY=1." >&2
    exit 1
fi

versions=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' Tracey.xcodeproj/project.pbxproj | sort -u)
if [[ $(wc -l <<< "$versions") -ne 1 ]]; then
    echo "Targets disagree on MARKETING_VERSION: $(echo $versions)" >&2
    exit 1
fi
version=$versions
build=$(git rev-list --count HEAD)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "Archiving Tracey $version ($build) from $(git rev-parse --short HEAD)…"
xcodebuild -quiet -project Tracey.xcodeproj -scheme Tracey -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$work/Tracey.xcarchive" \
    CURRENT_PROJECT_VERSION="$build" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    archive

mkdir -p "$work/Payload" build
cp -R "$work/Tracey.xcarchive/Products/Applications/Tracey.app" "$work/Payload/"
output="build/Tracey-$version-unsigned.ipa"
rm -f "$output"
(cd "$work" && zip -qry ipa.zip Payload)
mv "$work/ipa.zip" "$output"

plist="$work/Payload/Tracey.app/Info.plist"
echo "$output — Tracey $(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$plist")" \
     "($(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$plist")), $(du -h "$output" | cut -f1 | tr -d ' ')"

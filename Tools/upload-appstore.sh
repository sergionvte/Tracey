#!/bin/bash
#
#  upload-appstore.sh
#  Tracey
#
#  Archives a signed Release build and uploads it to App Store Connect (it then shows up in
#  TestFlight after Apple processes it). Uses the Apple ID signed in to Xcode and automatic
#  signing; -allowProvisioningUpdates lets Xcode create the distribution certificate and
#  App Store profile the first time.
#
#  Versioning is the same as make-ipa.sh: MARKETING_VERSION from the project, build number =
#  commit count of HEAD, so every upload must come from a new commit.
#
#  Usage: Tools/upload-appstore.sh     (refuses uncommitted changes)
#

set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "Uncommitted changes: the build number wouldn't match a commit. Commit first." >&2
    exit 1
fi

versions=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' Tracey.xcodeproj/project.pbxproj | sort -u)
if [[ $(wc -l <<< "$versions") -ne 1 ]]; then
    echo "Targets disagree on MARKETING_VERSION: $(echo $versions)" >&2
    exit 1
fi
version=$versions
build=$(git rev-list --count HEAD)
team=$(sed -n 's/.*DEVELOPMENT_TEAM = \(.*\);/\1/p' Tracey.xcodeproj/project.pbxproj | sort -u | head -1)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "Archiving Tracey $version ($build) from $(git rev-parse --short HEAD)…"
xcodebuild -quiet -project Tracey.xcodeproj -scheme Tracey -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$work/Tracey.xcarchive" \
    -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$build" \
    archive

cat > "$work/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>upload</string>
    <key>teamID</key><string>$team</string>
    <key>signingStyle</key><string>automatic</string>
    <key>uploadSymbols</key><true/>
    <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
EOF

echo "Uploading Tracey $version ($build) to App Store Connect…"
xcodebuild -exportArchive -archivePath "$work/Tracey.xcarchive" \
    -exportOptionsPlist "$work/ExportOptions.plist" -exportPath "$work/export" \
    -allowProvisioningUpdates

echo "Uploaded Tracey $version ($build). It appears in App Store Connect → TestFlight once processed."

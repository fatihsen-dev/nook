#!/bin/sh
set -eu

usage="usage: package-app.sh <version> <repository-url> <output-directory>"
[ "$#" -eq 3 ] || { echo "$usage" >&2; exit 64; }

version="$1"
repository_url="$2"
output_directory="$3"
app_name="Nook"
bundle_identifier="dev.nook.manager"
minimum_system_version="14.0"
architectures="--arch arm64 --arch x86_64"

# Matches a semantic version such as 1.2.3 or 1.2.3-beta.1
echo "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$' || { echo "invalid version: $version" >&2; exit 65; }
# Matches an https URL
echo "$repository_url" | grep -Eq '^https://[^[:space:]]+$' || { echo "repository URL must use https: $repository_url" >&2; exit 65; }

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repository_root"

# shellcheck disable=SC2086
swift build -c release --product "$app_name" $architectures
# shellcheck disable=SC2086
binary_directory="$(swift build -c release --product "$app_name" $architectures --show-bin-path)"

mkdir -p "$output_directory"
output_directory="$(cd "$output_directory" && pwd)"
app="$output_directory/$app_name.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_directory/$app_name" "$app/Contents/MacOS/$app_name"
cp "design/brand/nook.icns" "$app/Contents/Resources/nook.icns"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$app_name</string>
    <key>CFBundleIdentifier</key><string>$bundle_identifier</string>
    <key>CFBundleName</key><string>$app_name</string>
    <key>CFBundleDisplayName</key><string>$app_name</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>nook</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$version</string>
    <key>LSMinimumSystemVersion</key><string>$minimum_system_version</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NookKitPackage</key><string>$repository_url</string>
</dict>
</plist>
PLIST
plutil -lint "$app/Contents/Info.plist" >/dev/null

codesign --force --sign - "$app"

archive="$output_directory/$app_name.zip"
rm -f "$archive"
ditto -c -k --keepParent "$app" "$archive"
shasum -a 256 "$archive" | awk '{ print $1 }' > "$archive.sha256"

echo "packaged $app_name $version"
echo "  app:      $app"
echo "  archive:  $archive"
echo "  sha256:   $(cat "$archive.sha256")"

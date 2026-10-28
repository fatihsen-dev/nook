#!/bin/sh
set -eu

usage="usage: package-app.sh <version> <repository-url> <output-directory> [--sign <developer-id-identity>] [--notarize]

  --sign      sign with this Developer ID Application identity (hardened runtime, secure timestamp);
              without it the app is signed ad hoc and only runs without a Gatekeeper prompt on this Mac
  --notarize  notarize and staple the app and the disk image; needs --sign and the environment
              variables APP_STORE_CONNECT_KEY_PATH, APP_STORE_CONNECT_KEY_ID and APP_STORE_CONNECT_ISSUER_ID"
[ "$#" -ge 3 ] || { echo "$usage" >&2; exit 64; }

version="$1"
repository_url="$2"
output_directory="$3"
shift 3

signing_identity=""
should_notarize=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --sign)
            [ "$#" -ge 2 ] || { echo "--sign needs an identity" >&2; exit 64; }
            signing_identity="$2"
            shift 2
            ;;
        --notarize)
            should_notarize=true
            shift
            ;;
        *)
            echo "unknown option: $1" >&2
            echo "$usage" >&2
            exit 64
            ;;
    esac
done

app_name="Nook"
command_line_name="nookctl"
bundle_identifier="dev.nook.manager"
minimum_system_version="14.0"
architectures="--arch arm64 --arch x86_64"

# Matches a semantic version such as 1.2.3 or 1.2.3-beta.1
echo "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$' || { echo "invalid version: $version" >&2; exit 65; }
# Matches an https URL
echo "$repository_url" | grep -Eq '^https://[^[:space:]]+$' || { echo "repository URL must use https: $repository_url" >&2; exit 65; }
update_feed="${repository_url%/}/releases/latest/download/latest.json"

if [ "$should_notarize" = true ]; then
    [ -n "$signing_identity" ] || { echo "--notarize needs --sign: Apple only notarizes Developer ID signed code" >&2; exit 64; }
    for variable in APP_STORE_CONNECT_KEY_PATH APP_STORE_CONNECT_KEY_ID APP_STORE_CONNECT_ISSUER_ID; do
        eval "value=\${$variable:-}"
        [ -n "$value" ] || { echo "--notarize needs the environment variable $variable" >&2; exit 64; }
    done
    [ -f "$APP_STORE_CONNECT_KEY_PATH" ] || { echo "App Store Connect key not found: $APP_STORE_CONNECT_KEY_PATH" >&2; exit 66; }
fi

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repository_root"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

sign() {
    if [ -n "$signing_identity" ]; then
        codesign --force --options runtime --timestamp --sign "$signing_identity" "$1"
    else
        codesign --force --sign - "$1"
    fi
}

notarize() {
    submission_log="$scratch/notarization-$(basename "$1").json"
    xcrun notarytool submit "$1" \
        --key "$APP_STORE_CONNECT_KEY_PATH" \
        --key-id "$APP_STORE_CONNECT_KEY_ID" \
        --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
        --wait --output-format json > "$submission_log" \
        || { cat "$submission_log" >&2; echo "notarization request failed for $1" >&2; exit 70; }
    status="$(plutil -extract status raw -o - "$submission_log")"
    if [ "$status" != "Accepted" ]; then
        submission_id="$(plutil -extract id raw -o - "$submission_log")"
        echo "notarization of $1 ended with status $status (submission $submission_id):" >&2
        xcrun notarytool log "$submission_id" \
            --key "$APP_STORE_CONNECT_KEY_PATH" \
            --key-id "$APP_STORE_CONNECT_KEY_ID" \
            --issuer "$APP_STORE_CONNECT_ISSUER_ID" >&2
        exit 70
    fi
    echo "notarized $(basename "$1")"
}

# shellcheck disable=SC2086
swift build -c release --product "$app_name" $architectures
# shellcheck disable=SC2086
swift build -c release --product "$command_line_name" $architectures
# shellcheck disable=SC2086
binary_directory="$(swift build -c release --product "$app_name" $architectures --show-bin-path)"

mkdir -p "$output_directory"
output_directory="$(cd "$output_directory" && pwd)"
app="$output_directory/$app_name.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_directory/$app_name" "$app/Contents/MacOS/$app_name"
cp "$binary_directory/$command_line_name" "$app/Contents/MacOS/$command_line_name"
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
    <key>NookUpdateFeed</key><string>$update_feed</string>
</dict>
</plist>
PLIST
plutil -lint "$app/Contents/Info.plist" >/dev/null

sign "$app/Contents/MacOS/$command_line_name"
sign "$app"
codesign --verify --strict --deep "$app"

if [ "$should_notarize" = true ]; then
    ditto -c -k --keepParent "$app" "$scratch/$app_name-notarization.zip"
    notarize "$scratch/$app_name-notarization.zip"
    xcrun stapler staple "$app"
    spctl --assess --type execute "$app"
fi

disk_image="$output_directory/$app_name.dmg"
mkdir "$scratch/disk-image"
ditto "$app" "$scratch/disk-image/$app_name.app"
ln -s /Applications "$scratch/disk-image/Applications"
rm -f "$disk_image"
hdiutil create -quiet -volname "$app_name $version" -srcfolder "$scratch/disk-image" -fs HFS+ -format UDZO -ov "$disk_image"
[ -z "$signing_identity" ] || codesign --force --timestamp --sign "$signing_identity" "$disk_image"

if [ "$should_notarize" = true ]; then
    notarize "$disk_image"
    xcrun stapler staple "$disk_image"
    spctl --assess --type open --context context:primary-signature "$disk_image"
fi

archive="$output_directory/$app_name.zip"
rm -f "$archive"
ditto -c -k --keepParent "$app" "$archive"

shasum -a 256 "$archive" | awk '{ print $1 }' > "$archive.sha256"
shasum -a 256 "$disk_image" | awk '{ print $1 }' > "$disk_image.sha256"

echo "packaged $app_name $version"
echo "  signing:     ${signing_identity:-ad hoc}"
echo "  notarized:   $should_notarize"
echo "  app:         $app"
echo "  archive:     $archive"
echo "  disk image:  $disk_image"
echo "  sha256 zip:  $(cat "$archive.sha256")"
echo "  sha256 dmg:  $(cat "$disk_image.sha256")"

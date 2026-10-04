#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
configuration="${1:-release}"
skip_build=""
distribution=""
if [[ "$configuration" != "debug" && "$configuration" != "release" ]]; then
    echo "Usage: bash scripts/build-app.sh [debug|release] [--skip-build] [--distribution]" >&2
    exit 2
fi
for arg in "${@:2}"; do
    case "$arg" in
        --skip-build) skip_build=1 ;;
        --distribution) distribution=1 ;;
        *)
            echo "Usage: bash scripts/build-app.sh [debug|release] [--skip-build] [--distribution]" >&2
            exit 2
            ;;
    esac
done
build_args=(-c "$configuration")
if [[ -n "$distribution" ]]; then
    if [[ "$configuration" != "release" ]]; then
        echo "Distribution packages must use the release configuration." >&2
        exit 2
    fi
    if [[ -z "${VIPER_SIGN_IDENTITY:-}" || -z "${VIPER_NOTARY_PROFILE:-}" ]]; then
        echo "Set VIPER_SIGN_IDENTITY and VIPER_NOTARY_PROFILE for Developer ID signing and notarization." >&2
        exit 2
    fi
    build_args+=(--arch arm64 --arch x86_64)
fi
if [[ -z "$skip_build" ]]; then
    swift build "${build_args[@]}"
fi
bin_dir="$(swift build "${build_args[@]}" --show-bin-path)"
binary="$bin_dir/Viper"
if [[ ! -f "$binary" ]]; then
    echo "Build the $configuration executable first." >&2
    exit 1
fi
swift scripts/make-icon.swift
iconutil -c icns .build/Viper.iconset -o .build/Viper.icns
bundle="dist/Viper.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$binary" "$bundle/Contents/MacOS/Viper"
cp .build/Viper.icns "$bundle/Contents/Resources/Viper.icns"
rm -rf "$bundle/Contents/Resources/CatalogIcons"
cp -R Resources/CatalogIcons "$bundle/Contents/Resources/CatalogIcons"
cp Resources/Info.plist "$bundle/Contents/Info.plist"
if [[ -n "$distribution" ]]; then
    architectures="$(lipo -archs "$bundle/Contents/MacOS/Viper")"
    if [[ "$architectures" != *"arm64"* || "$architectures" != *"x86_64"* ]]; then
        echo "Distribution binary is not universal: $architectures" >&2
        exit 1
    fi
    codesign --force --deep --options runtime --timestamp --sign "$VIPER_SIGN_IDENTITY" "$bundle"
    codesign --verify --deep --strict --verbose=2 "$bundle"
    archive="dist/Viper-notarization.zip"
    ditto -c -k --keepParent "$bundle" "$archive"
    xcrun notarytool submit "$archive" --keychain-profile "$VIPER_NOTARY_PROFILE" --wait
    xcrun stapler staple "$bundle"
    xcrun stapler validate "$bundle"
else
    codesign --force --sign - "$bundle"
fi
# Rebuilding in place can leave the Dock showing a cached placeholder icon; refresh the registration.
touch "$bundle"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$bundle" || true
if [[ -n "$distribution" ]]; then
    echo "Created, Developer ID signed, and notarized $PWD/$bundle."
else
    echo "Created $PWD/$bundle (local development signature; not notarized). Use --distribution with signing credentials for release."
fi

#!/usr/bin/env bash
#
# Downloads and extracts a prebuilt GhosttyKit.xcframework into Vendor/.
# Pinned by ghostty submodule SHA so the binary is reproducible. Idempotent —
# skips the download if Vendor/GhosttyKit.xcframework already matches.

set -euo pipefail

GHOSTTY_SHA="88c3325dc9698d887da7e07ee0f9b79c53020be2"
GHOSTTY_RELEASE_TAG="xcframework-${GHOSTTY_SHA}-crashsubdir-cmux-crash-sentry-off-v1"
EXPECTED_SHA256="56869d9d8702d6710d5a1992a3d21c02e29b12d1130964ee546f80bff7353604"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$REPO_ROOT/Vendor"
FRAMEWORK_PATH="$VENDOR_DIR/GhosttyKit.xcframework"
STAMP_FILE="$VENDOR_DIR/.ghostty-sha"
ARCHIVE_URL="https://github.com/manaflow-ai/ghostty/releases/download/${GHOSTTY_RELEASE_TAG}/GhosttyKit.xcframework.tar.gz"

if [[ -d "$FRAMEWORK_PATH" && -f "$STAMP_FILE" && "$(cat "$STAMP_FILE")" == "$GHOSTTY_SHA" ]]; then
    echo "GhosttyKit.xcframework already at pinned SHA ($GHOSTTY_SHA). Skipping."
    exit 0
fi

mkdir -p "$VENDOR_DIR"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kooky-ghosttykit.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
ARCHIVE_PATH="$TMP_DIR/GhosttyKit.xcframework.tar.gz"

echo "Downloading GhosttyKit.xcframework for ghostty $GHOSTTY_SHA..."
curl --fail --show-error --location \
    --connect-timeout 10 \
    --max-time 600 \
    --retry 5 \
    --retry-delay 5 \
    --retry-all-errors \
    -o "$ARCHIVE_PATH" \
    "$ARCHIVE_URL"

ACTUAL_SHA256="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')"
if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
    echo "Checksum mismatch!" >&2
    echo "  expected: $EXPECTED_SHA256" >&2
    echo "  actual:   $ACTUAL_SHA256" >&2
    exit 1
fi

echo "Verified. Extracting..."
EXTRACT_DIR="$TMP_DIR/extract"
mkdir -p "$EXTRACT_DIR"
tar --no-same-owner -xzf "$ARCHIVE_PATH" -C "$EXTRACT_DIR"

if [[ ! -d "$EXTRACT_DIR/GhosttyKit.xcframework" ]]; then
    echo "Archive did not contain GhosttyKit.xcframework at the expected path." >&2
    exit 1
fi

rm -rf "$FRAMEWORK_PATH"
mv "$EXTRACT_DIR/GhosttyKit.xcframework" "$FRAMEWORK_PATH"

# SPM requires static-library xcframework slices to use a `lib*.a` filename.
# The prebuilt macOS slice ships `ghostty-internal.a` (no prefix), which SPM
# rejects. The iOS slices already use `libghostty-internal-fat.a` so they're
# untouched.
MACOS_SLICE="$FRAMEWORK_PATH/macos-arm64_x86_64"
if [[ -f "$MACOS_SLICE/ghostty-internal.a" ]]; then
    mv "$MACOS_SLICE/ghostty-internal.a" "$MACOS_SLICE/libghostty-internal.a"
    sed -i '' \
        's|<string>ghostty-internal\.a</string>|<string>libghostty-internal.a</string>|g' \
        "$FRAMEWORK_PATH/Info.plist"
    echo "Renamed macOS slice binary to libghostty-internal.a (SPM compatibility)"
fi

echo "$GHOSTTY_SHA" > "$STAMP_FILE"
echo "Installed: $FRAMEWORK_PATH"

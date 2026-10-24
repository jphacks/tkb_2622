#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DESKTOP_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
REPOSITORY_DIR=$(CDPATH= cd -- "$DESKTOP_DIR/.." && pwd)
OUTPUT_DIR="$DESKTOP_DIR/build/bin"
OUTPUT_PATH="$OUTPUT_DIR/native-collector"
SOURCE_PATH="$REPOSITORY_DIR/poc/macos-native/native/Collector.swift"

if [ "$(uname -s)" != "Darwin" ]; then
    printf '%s\n' "native-collector はmacOS上でのみビルドできます。" >&2
    exit 1
fi

if ! command -v swiftc >/dev/null 2>&1; then
    printf '%s\n' "swiftc が見つかりません。Xcode Command Line Toolsを確認してください。" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
swiftc -O \
    -framework AppKit \
    -framework CoreGraphics \
    -framework Foundation \
    "$SOURCE_PATH" \
    -o "$OUTPUT_PATH"
chmod +x "$OUTPUT_PATH"
printf 'Built %s\n' "$OUTPUT_PATH" >&2

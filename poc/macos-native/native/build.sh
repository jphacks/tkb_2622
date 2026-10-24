#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
POC_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
OUTPUT_DIR="$POC_DIR/bin"
OUTPUT_PATH="$OUTPUT_DIR/native-collector"

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
    "$SCRIPT_DIR/Collector.swift" \
    -o "$OUTPUT_PATH"
chmod +x "$OUTPUT_PATH"
printf 'Built %s\n' "$OUTPUT_PATH" >&2

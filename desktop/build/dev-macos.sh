#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DESKTOP_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
COLLECTOR_PATH="$DESKTOP_DIR/build/bin/native-collector"

if [ "$(uname -s)" != "Darwin" ]; then
    printf '%s\n' "Focus Linkのネイティブ監視はmacOSでのみ起動できます。" >&2
    exit 1
fi

sh "$SCRIPT_DIR/build-macos-collector.sh"
cd "$DESKTOP_DIR"
FOCUS_LINK_COLLECTOR_PATH="$COLLECTOR_PATH" exec wails dev "$@"

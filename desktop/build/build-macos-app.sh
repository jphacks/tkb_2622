#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DESKTOP_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
APP_PATH="$DESKTOP_DIR/build/bin/Focus Link.app"
HELPER_SOURCE="$DESKTOP_DIR/build/bin/native-collector"
HELPER_DESTINATION="$APP_PATH/Contents/MacOS/native-collector"

if [ "$(uname -s)" != "Darwin" ]; then
    printf '%s\n' "Focus LinkのアプリビルドはmacOS上で実行してください。" >&2
    exit 1
fi

cd "$DESKTOP_DIR"
wails build "$@"
sh "$SCRIPT_DIR/build-macos-collector.sh"

if [ ! -d "$APP_PATH/Contents/MacOS" ]; then
    printf '%s\n' "Wailsのアプリ出力が見つかりません: $APP_PATH" >&2
    exit 1
fi

cp "$HELPER_SOURCE" "$HELPER_DESTINATION"
chmod +x "$HELPER_DESTINATION"
printf 'Built %s\n' "$APP_PATH" >&2

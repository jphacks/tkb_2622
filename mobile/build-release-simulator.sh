#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$SCRIPT_DIR/ios-reward-time.xcodeproj"
SCHEME="RewardTimeUITests"
LOCAL_CONFIG="${FOCUS_LINK_IOS_RELEASE_XCCONFIG:-$SCRIPT_DIR/Release.local.xcconfig}"
DERIVED_DATA="${FOCUS_LINK_IOS_DERIVED_DATA:-${TMPDIR:-/tmp}/focus-link-ios-release-deriveddata}"
BUILD_CONFIG="$LOCAL_CONFIG"

if [[ "$LOCAL_CONFIG" == "$SCRIPT_DIR/Release.local.xcconfig" ]]; then
  BUILD_CONFIG="$SCRIPT_DIR/Release.xcconfig"
fi

if [[ ! -f "$LOCAL_CONFIG" ]]; then
  printf 'Release接続設定がありません。mobile/Release.local.xcconfig.exampleをmobile/Release.local.xcconfigへコピーして設定してください。\n' >&2
  exit 2
fi

python3 - "$LOCAL_CONFIG" <<'PY'
import base64
import binascii
import json
import sys
from urllib.parse import urlparse

path = sys.argv[1]
required = {
    "SUPABASE_PROJECT_URL",
    "SUPABASE_PUBLISHABLE_KEY",
    "CONNECT_API_BASE_URL",
}
values = {}
with open(path, encoding="utf-8") as config:
    for line in config:
        stripped = line.strip()
        if not stripped or stripped.startswith(("#", "//")) or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] == '"':
            value = value[1:-1]
        value = value.replace("$()", "")
        if key in required:
            values[key] = value

missing = sorted(key for key in required if not values.get(key))
if missing:
    print("Release xcconfig is missing: " + ", ".join(missing), file=sys.stderr)
    sys.exit(2)

for key in ("SUPABASE_PROJECT_URL", "CONNECT_API_BASE_URL"):
    value = values[key]
    parsed = urlparse(value)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password
            or "YOUR_PROJECT_REF" in value or "example.com" in value):
        print(f"{key} must be a real HTTPS URL without placeholders.", file=sys.stderr)
        sys.exit(2)

publishable = values["SUPABASE_PUBLISHABLE_KEY"]
is_service_role_jwt = False
jwt_parts = publishable.split(".")
if len(jwt_parts) == 3:
    try:
        payload = jwt_parts[1] + "=" * (-len(jwt_parts[1]) % 4)
        claims = json.loads(base64.urlsafe_b64decode(payload))
        is_service_role_jwt = claims.get("role") == "service_role"
    except (ValueError, binascii.Error):
        pass
if ("REPLACE_WITH" in publishable or publishable.startswith("sb_secret_")
        or is_service_role_jwt or "service_role" in publishable.lower()
        or "secret" in publishable.lower()):
    print("SUPABASE_PUBLISHABLE_KEY must be a publishable client key, not a placeholder or secret key.", file=sys.stderr)
    sys.exit(2)
PY

xcodebuild build \
  -quiet \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DERIVED_DATA" \
  -xcconfig "$BUILD_CONFIG" \
  CODE_SIGNING_ALLOWED=NO

APP="$DERIVED_DATA/Build/Products/Release-iphonesimulator/RewardTime.app"
if [[ ! -f "$APP/Info.plist" ]]; then
  echo "Release app Info.plist was not produced." >&2
  exit 1
fi

python3 - "$LOCAL_CONFIG" "$APP/Info.plist" <<'PY'
import plistlib
import sys

config_path, plist_path = sys.argv[1:]
settings = {}
with open(config_path, encoding="utf-8") as config:
    for line in config:
        stripped = line.strip()
        if not stripped or stripped.startswith(("#", "//")) or "=" not in line:
            continue
        key, value = line.split("=", 1)
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] == '"':
            value = value[1:-1]
        value = value.replace("$()", "")
        settings[key.strip()] = value

with open(plist_path, "rb") as product:
    info = plistlib.load(product)

for key in ("SUPABASE_PROJECT_URL", "SUPABASE_PUBLISHABLE_KEY", "CONNECT_API_BASE_URL"):
    if info.get(key) != settings.get(key):
        print(f"Release Info.plist does not contain configured {key}.", file=sys.stderr)
        sys.exit(1)
print("Release simulator app built; configured connection values are present in Info.plist.")
PY

#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
OUT="$PWD/build/RTUIFix.framework"
mkdir -p "$OUT"
xcrun --sdk iphoneos clang \
  -arch arm64 -miphoneos-version-min=15.0 \
  -isysroot "$SDK" -fobjc-arc -fblocks -fmodules -O2 \
  -Wall -Wextra -Werror=implicit-function-declaration \
  -dynamiclib \
  '-Wl,-install_name,@executable_path/Frameworks/RTUIFix.framework/RTUIFix' \
  -framework Foundation -framework UIKit \
  Sources/RTUIFix.m -o "$OUT/RTUIFix"
python3 - <<'PY'
import plistlib,pathlib
p=pathlib.Path("build/RTUIFix.framework/Info.plist")
p.write_bytes(plistlib.dumps({
 "CFBundleDevelopmentRegion":"en",
 "CFBundleExecutable":"RTUIFix",
 "CFBundleIdentifier":"ru.rutube.mod.uifix",
 "CFBundleInfoDictionaryVersion":"6.0",
 "CFBundleName":"RTUIFix",
 "CFBundlePackageType":"FMWK",
 "CFBundleShortVersionString":"1.0.0",
 "CFBundleVersion":"1",
 "MinimumOSVersion":"15.0",
 "CFBundleSupportedPlatforms":["iPhoneOS"],
}))
PY
file "$OUT/RTUIFix"
otool -D "$OUT/RTUIFix"

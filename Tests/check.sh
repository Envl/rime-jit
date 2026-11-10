#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
squirrel="/Library/Input Methods/Squirrel.app/Contents"
frameworks="$squirrel/Frameworks"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
userdir="$fixture/rime"
cache="$fixture/Library/Caches/RimeScreenWords"
mkdir -p "$userdir"
# Exercise the reference setup without importing the operator's schemas or dictionaries.
schema="$userdir/double_pinyin_flypy.schema.yaml"
curl -fsSL --retry 2 https://raw.githubusercontent.com/rime/rime-double-pinyin/01a13287cbd27819be1c34fa1ddc1b3643d5001b/double_pinyin_flypy.schema.yaml -o "$schema"
echo "6b522a7e9cb743474287a14678597460bd124369f32573dd63e8f04e7c41d4b9  $schema" | shasum -a 256 -c -
cat > "$userdir/default.custom.yaml" <<'YAML'
patch:
  schema_list:
    - schema: double_pinyin_flypy
YAML
RIME_USER_DIR="$userdir" /usr/bin/ruby scripts/install.rb
RIME_USER_DIR="$userdir" /usr/bin/ruby scripts/install.rb
"$squirrel/MacOS/rime_deployer" --build "$userdir" "$squirrel/SharedSupport" "$userdir/build"
# Compile against the public ABI matching the local Squirrel 1.1.2 release.
curl -fsSL --retry 2 https://raw.githubusercontent.com/rime/librime/1.16.0/src/rime_api.h -o "$fixture/rime_api.h"
echo "6eb5629162c44761e7b878f1b122f464de5c8685bd3cd5ac1e8519badc6d6424  $fixture/rime_api.h" | shasum -a 256 -c -
xcrun --sdk macosx clang -isysroot "$(xcrun --show-sdk-path)" -I"$fixture" Tests/session.c "$frameworks/librime.1.dylib" \
    "$frameworks/rime-plugins/librime-lua.dylib" -Wl,-rpath,"$frameworks" \
    -Wl,-rpath,"$frameworks/rime-plugins" -o "$fixture/session"
xcrun swiftc -O -parse-as-library Sources/{WordIndex,Snapshot,ScreenReader}.swift Tests/Fixture.swift -o "$fixture/fixture"
"$fixture/fixture" "$cache"
for mode in seed restart; do
    HOME="$fixture" "$fixture/session" "$squirrel/SharedSupport" "$userdir" "$cache/words.tsv" "$mode"
done
selected="$userdir/rime-jit-selected-double_pinyin_flypy.tsv"
[[ $(wc -l < "$selected") -eq 5 ]]
echo "Five-minute expiry, recency order and selective recall across processes OK"

#!/bin/sh -e

result=$1
target=$2
dir=$(mktemp -d)
mkdir -p "$dir/out"
mkdir -p "$dir/$result"
mkdir -p "$dir/$result/core"
mkdir -p "$dir/$result/randomizers"

cp -r 'zig-out/bin' "$dir/out"
find "$dir/out" -name "tm35-randomizer*" -exec mv {} "$dir/$result" \;
find "$dir/out" -name "tm35-apply*" -exec mv {} "$dir/$result/core" \;
find "$dir/out" -name "tm35-identify*" -exec mv {} "$dir/$result/core" \;
find "$dir/out" -name "tm35-load*" -exec mv {} "$dir/$result/core" \;
find "$dir/out" -name "tm35-*" -exec mv {} "$dir/$result/randomizers" \;
cp -r 'settings' "$dir/$result/settings"

case $target in
    *windows*) cp "lib/webview-c/ms.webview2/x64/WebView2Loader.dll" "$dir/$result" ;;
    *) ;;
esac

(
    cd "$dir"
    zip -r "$result.zip" "$result/"
)

cp "$dir/$result.zip" .
rm -r "$dir"

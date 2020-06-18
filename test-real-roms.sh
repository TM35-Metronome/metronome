#!/bin/sh -ex

program="${0##*/}"
usage() {
    echo "Usage: "
}

while [ -n "$1" ]; do
    case $1 in
        --) shift; break ;;
        -h|--help) usage; exit 0 ;;
        -*) usage; exit 1 ;;
        *) break ;;
    esac
    shift
done

zig build
for rom in $@; do
    echo "$rom" >&2
    rom_dest=$(mktemp)
    expect=$(mktemp)
    found=$(mktemp)
    zig-cache/bin/tm35-load "$rom" > "$expect"
    zig-cache/bin/tm35-apply "$rom" -aro "$rom_dest" < "$expect"
    zig-cache/bin/tm35-load "$rom_dest" > "$found"
    diff -q "$expect" "$found"

    # Change everything in rom to 1
    sed -i "s/=[0-9]*$/=1/" "$expect"
    zig-cache/bin/tm35-apply "$rom" -aro "$rom_dest" < "$expect"
    zig-cache/bin/tm35-load "$rom_dest" > "$found"
    diff -q "$expect" "$found"
    rm "$rom_dest" "$expect" "$found"
done

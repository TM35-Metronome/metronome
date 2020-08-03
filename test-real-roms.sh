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

rom_dest=$(mktemp)
expect=$(mktemp)
found=$(mktemp)

for release in $(printf "false\ntrue\n"); do
    zig build "-Drelease=$release"
    for rom in $@; do
        echo "$rom" >&2
        zig-cache/bin/tm35-load "$rom" > "$expect"
        zig-cache/bin/tm35-apply "$rom" -aro "$rom_dest" < "$expect"
        zig-cache/bin/tm35-load "$rom_dest" > "$found"
        diff -q "$expect" "$found"

        sed -i -E \
            -e "s/([^y])=([0-9]).*$/\1=\2/" \
            -e "s/\.name=.*$/.name=a/" \
            "$expect"
        zig-cache/bin/tm35-apply "$rom" -aro "$rom_dest" < "$expect"
        zig-cache/bin/tm35-load "$rom_dest" > "$found"
        diff -q "$expect" "$found"
    done
done

rm "$rom_dest" "$expect" "$found"

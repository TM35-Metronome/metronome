#!/bin/sh -ex

program="${0##*/}"
usage() {
    echo "Usage: "
}

while [ -n "$1" ]; do
    case $1 in
        --) shift; break ;;
        -h|--help) usage; exit 0 ;;
        -r|--run) run='yes' ;;
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
            -e "/party_size/b ;/pokedex_entry/b; s/=([0-9])[0-9].*$/=\10/" \
            -e "s/\.name=.*$/.name=a/" \
            -e "s/\.instant_text=.*/.instant_text=true/" \
            -e "s/\.text_delays\[([0-9]*)\]=.*/.text_delays[\1]=0/" \
            "$expect"
        
        zig-cache/bin/tm35-apply "$rom" -aro "$rom_dest" < "$expect"
        zig-cache/bin/tm35-load "$rom_dest" > "$found"

        # Instant text is a field that will always be false when
        # loading a rom, so we revert the fact that we set it to true.
        sed -i -E  "s/\.instant_text=.*/.instant_text=false/" "$expect"
        diff -q "$expect" "$found"

        if ! [ -z "$run" ]; then
            case $rom in
                *.nds) desmume "$rom_dest" ;;
                *.gba) mgba-qt "$rom_dest" ;;
            esac
        fi
    done
done

rm "$rom_dest" "$expect" "$found"

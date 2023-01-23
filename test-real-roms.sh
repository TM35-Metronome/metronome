#!/bin/sh -e

while [ -n "$1" ]; do
    case $1 in
        -r | --run) run='yes' ;;
        *) break ;;
    esac
    shift
done

rom_dest=$(mktemp)
expect=$(mktemp)
found=$(mktemp)

for rom in "$@"; do
    echo "$rom" >&2
    zig-out/bin/tm35-load "$rom" >"$expect"
    zig-out/bin/tm35-apply "$rom" -aro "$rom_dest" <"$expect"
    zig-out/bin/tm35-load "$rom_dest" >"$found"
    diff -q "$expect" "$found"

    sed -i -E \
        -e "/party_size/b; /pokedex_entry/b; s/=([0-9])[0-9].*$/=10/" \
        -e "s/=true$/=<replace_with_false>/" \
        -e "s/=false$/=true/" \
        -e "s/=<replace_with_false>$/=false/" \
        -e "s/\.name=..*$/.name=a/" \
        -e "s/\.description=..*$/.description=b/" \
        -e "s/\.pocket=.*$/.pocket=items/" \
        -e "s/\.text_delays\[([0-9]*)\]=.*/.text_delays[\1]=0/" \
        -e "s/\.text\[([0-9]*)\]=..*/.text[\1]=c/" \
        -e "s/\.egg_groups\[([0-9]*)\]=.*/.egg_groups[\1]=field/" \
        -e "s/\.growth_rate=.*/.growth_rate=medium_slow/" \
        "$expect"

    zig-out/bin/tm35-apply "$rom" -aro "$rom_dest" <"$expect"
    zig-out/bin/tm35-load "$rom_dest" >"$found"

    # Instant text is a field that will always be false when
    # loading a rom, so we revert the fact that we set it to true.
    sed -i -E "s/\.instant_text=.*/.instant_text=false/" "$expect"
    diff -q "$expect" "$found"

    if [ -n "$run" ]; then
        case $rom in
            *.nds) desmume "$rom_dest" ;;
            *.gba) mgba-qt "$rom_dest" ;;
        esac
    fi
done

rm "$rom_dest" "$expect" "$found"
echo 'done' >&2

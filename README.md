# Metronome

A set of tools for randomizing and modifying Pokémon games.

## Build

External dependencies:
* [Zig `0.5.0`](https://ziglang.org/download/)
* Linux only:
  * [zenity](https://github.com/GNOME/zenity) (optional file dialog)


After getting the dependencies just clone the repo and its submodules and run:
```
zig build
```

All build artifacts will end up in `zig-cache/bin`.
See `zig build --help` for build options.

## Resources

Links to external resources documenting the layout of Pokemom games.

### Roms

* [Gameboy Advance / Nintendo DS / DSi - Technical Info](http://problemkaputt.de/gbatek.htm)
* [Gb info](http://gbdev.gg8.se/files/docs/mirrors/pandocs.html)
* [Nds formats](http://www.romhacking.net/documents/%5B469%5Dnds_formats.htm)

### Gen 1

### Gen 2

### Gen 3

* [Pokémon Emerald Offsets](http://www.romhack.me/database/21/pok%C3%A9mon-emerald-rom-offsets/)

### Gen 4

* [HGSS File System](https://projectpokemon.org/docs/gen-4/hgss-file-system-r21/)
* [HG/SS Mapping File Specifications](https://projectpokemon.org/home/forums/topic/41695-hgss-mapping-file-specifications/?tab=comments#comment-220455)
* [HG/SS Pokemon File Specifications](https://projectpokemon.org/home/forums/topic/41694-hgss-pokemon-file-specifications/?tab=comments#comment-220454)
* [HG/SS Encounter File Specification](https://projectpokemon.org/home/forums/topic/41693-hgss-encounter-file-specification/?tab=comments#comment-220453)
* [D/P/PL/HG/SS scripting and map structure](https://sites.google.com/site/projectpokeresearch/rom-research)

### Gen 5

* [BW2 File System](https://projectpokemon.org/docs/gen-5/b2w2-file-system-r8/)
* [BW Trainer data](https://projectpokemon.org/home/forums/topic/22629-b2w2-general-rom-info/?do=findComment&comment=153174)
* [BW Move data](https://projectpokemon.org/home/forums/topic/14212-bw-move-data/?do=findComment&comment=123606)

### All Gens

* [Bulbapedia on Pokemon Data Structures](https://bulbapedia.bulbagarden.net/wiki/Category:Structures)
* [Pokemon Game Disassemblies](https://github.com/search?utf8=%E2%9C%93&q=Pokemon+Disassembly&type=)

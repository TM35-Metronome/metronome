const clap = @import("clap");
const std = @import("std");
const ston = @import("ston");
const util = @import("util");

const common = @import("common.zig");
const format = @import("format.zig");
const gen3 = @import("gen3.zig");
const gen4 = @import("gen4.zig");
const gen5 = @import("gen5.zig");
const rom = @import("rom.zig");

const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const log = std.log;
const math = std.math;
const mem = std.mem;

const path = fs.path;

const gba = rom.gba;
const nds = rom.nds;

const bit = util.bit;

const lu128 = rom.int.lu128;
const lu16 = rom.int.lu16;
const lu32 = rom.int.lu32;
const lu64 = rom.int.lu64;

const Program = @This();

allocator: *mem.Allocator,
patch: PatchOption,
no_output: bool,
replace: bool,
abort_on_first_warning: bool,
out: []const u8,
game: Game,
old_bytes: std.ArrayListUnmanaged(u8),

const PatchOption = enum {
    none,
    live,
    full,
};

pub const main = util.generateMain(Program);
pub const version = "0.0.0";
pub const description =
    \\Applies changes to Pokémon roms.
    \\
;

pub const params = &[_]clap.Param(clap.Help){
    clap.parseParam("-a, --abort-on-first-warning  Abort execution on the first warning emitted.                                                         ") catch unreachable,
    clap.parseParam("-h, --help                    Display this help text and exit.                                                                      ") catch unreachable,
    clap.parseParam("-n, --no-output               Don't output the file.                                                                                ") catch unreachable,
    clap.parseParam("-o, --output <FILE>           Override destination path.                                                                            ") catch unreachable,
    clap.parseParam("-p, --patch <none|live|full>  Output patch data to stdout when not 'none'. 'live' = patch after each line. 'full' = patch when done.") catch unreachable,
    clap.parseParam("-r, --replace                 Replace output file if it already exists.                                                             ") catch unreachable,
    clap.parseParam("-v, --version                 Output version information and exit.                                                                  ") catch unreachable,
    clap.parseParam("<ROM>                         The rom to apply the changes to.                                                                  ") catch unreachable,
};

pub fn init(allocator: *mem.Allocator, args: anytype) !Program {
    const pos = args.positionals();
    const file_name = if (pos.len > 0) pos[0] else return error.MissingFile;

    const patch_arg = args.option("--patch") orelse "none";
    const patch = std.meta.stringToEnum(PatchOption, patch_arg) orelse {
        log.err("--patch does not support '{s}'", .{patch_arg});
        return error.InvalidArgument;
    };

    var game = blk: {
        const file = try fs.cwd().openFile(file_name, .{});
        defer file.close();

        const gen3_error = if (gen3.Game.fromFile(file, allocator)) |game| {
            break :blk Game{ .gen3 = game };
        } else |err| err;

        try file.seekTo(0);

        const nds_rom = try allocator.create(nds.Rom);
        errdefer allocator.destroy(nds_rom);

        nds_rom.* = nds.Rom.fromFile(file, allocator) catch |nds_error| {
            log.err("Failed to load '{s}' as a gen3 game: {}", .{ file_name, gen3_error });
            log.err("Failed to load '{s}' as a gen4/gen5 game: {}", .{ file_name, nds_error });
            return error.InvalidRom;
        };
        errdefer nds_rom.deinit();

        const gen4_error = if (gen4.Game.fromRom(allocator, nds_rom)) |game| {
            break :blk Game{ .gen4 = game };
        } else |err| err;

        const gen5_error = if (gen5.Game.fromRom(allocator, nds_rom)) |game| {
            break :blk Game{ .gen5 = game };
        } else |err| err;

        log.err("Successfully loaded '{s}' as a nds rom.", .{file_name});
        log.err("Failed to load '{s}' as a gen4 game: {}", .{ file_name, gen4_error });
        log.err("Failed to load '{s}' as a gen5 game: {}", .{ file_name, gen5_error });
        return error.InvalidRom;
    };
    errdefer game.deinit();

    // When --patch is passed, we store a copy of the games old state, so that we
    // can generate binary patches between old and new versions.
    var old_bytes = std.ArrayListUnmanaged(u8){};
    errdefer old_bytes.deinit(allocator);
    if (patch != .none)
        try old_bytes.appendSlice(allocator, game.data());

    return Program{
        .allocator = allocator,
        .no_output = args.flag("--no-output"),
        .replace = args.flag("--replace"),
        .abort_on_first_warning = args.flag("--abort-on-first-warning"),
        .out = args.option("--output") orelse
            try fmt.allocPrint(allocator, "{s}.modified", .{path.basename(file_name)}),
        .patch = patch,
        .game = game,
        .old_bytes = old_bytes,
    };
}

pub fn run(
    program: *Program,
    comptime Reader: type,
    comptime Writer: type,
    stdio: util.CustomStdIoStreams(Reader, Writer),
) anyerror!void {
    try format.io(program.allocator, stdio.in, std.io.null_writer, .{
        .program = program,
        .out = stdio.out,
    }, useGame);

    if (program.patch == .full) {
        var it = common.PatchIterator{
            .old = program.old_bytes.items,
            .new = program.game.data(),
        };
        while (it.next()) |p| {
            try stdio.out.print("[{}]={x}\n", .{
                p.offset,
                fmt.fmtSliceHexLower(p.replacement),
            });
        }
    }

    if (program.no_output)
        return;

    const out_file = try fs.cwd().createFile(program.out, .{
        .exclusive = !program.replace,
        .truncate = false,
    });
    try program.game.apply();
    try program.game.write(out_file.writer());

    const len = program.game.data().len;
    try out_file.setEndPos(len);
}

pub fn deinit(program: *Program) void {
    program.game.deinit();
    program.old_bytes.deinit(program.allocator);
}

const Game = union(enum) {
    gen3: gen3.Game,
    gen4: gen4.Game,
    gen5: gen5.Game,

    fn data(game: Game) []const u8 {
        return switch (game) {
            .gen3 => |g| g.data,
            .gen4 => |g| g.rom.data.items,
            .gen5 => |g| g.rom.data.items,
        };
    }

    fn apply(game: *Game) !void {
        switch (game.*) {
            .gen3 => |*g| try g.apply(),
            .gen4 => |*g| try g.apply(),
            .gen5 => |*g| try g.apply(),
        }
    }

    fn write(game: Game, writer: anytype) !void {
        switch (game) {
            .gen3 => |g| try g.write(writer),
            .gen4 => |g| try g.rom.write(writer),
            .gen5 => |g| try g.rom.write(writer),
        }
    }

    fn deinit(game: Game) void {
        switch (game) {
            .gen3 => |g| g.deinit(),
            .gen4 => |g| {
                g.rom.deinit();
                g.allocator.destroy(g.rom);
                g.deinit();
            },
            .gen5 => |g| {
                g.rom.deinit();
                g.allocator.destroy(g.rom);
                g.deinit();
            },
        }
    }
};

fn useGame(ctx: anytype, game: format.Game) !void {
    const program = ctx.program;
    switch (program.game) {
        .gen3 => |*gen3_game| try applyGen3(gen3_game, game),
        .gen4 => |*gen4_game| try applyGen4(gen4_game.*, game),
        .gen5 => |*gen5_game| try applyGen5(gen5_game.*, game),
    }

    if (program.patch == .live) {
        try program.game.apply();
        var it = common.PatchIterator{
            .old = program.old_bytes.items,
            .new = program.game.data(),
        };
        while (it.next()) |p| {
            try ctx.out.print("[{}]={x}\n", .{
                p.offset,
                fmt.fmtSliceHexLower(p.replacement),
            });

            try program.old_bytes.resize(program.allocator, math.max(
                program.old_bytes.items.len,
                p.offset + p.replacement.len,
            ));
            common.patch(program.old_bytes.items, &[_]common.Patch{p});
        }
        try ctx.out.context.flush();
    }
}

fn applyGen3(game: *gen3.Game, parsed: format.Game) !void {
    switch (parsed) {
        .version => |v| {
            if (v != game.version)
                return error.VersionDontMatch;
        },
        .game_title => |title| {
            if (!mem.eql(u8, title, game.header.game_title.span()))
                return error.GameTitleDontMatch;
        },
        .gamecode => |code| {
            if (!mem.eql(u8, code, &game.header.gamecode))
                return error.GameCodeDontMatch;
        },
        .starters => |starter| {
            if (starter.index >= game.starters.len)
                return error.Error;
            game.starters[starter.index].* = lu16.init(starter.value);
            game.starters_repeat[starter.index].* = lu16.init(starter.value);
        },
        .text_delays => |delay| {
            if (delay.index >= game.text_delays.len)
                return error.Error;
            game.text_delays[delay.index] = delay.value;
        },
        .trainers => |trainers| {
            if (trainers.index >= game.trainers.len)
                return error.Error;
            const trainer = &game.trainers[trainers.index];
            const party = &game.trainer_parties[trainers.index];

            switch (trainers.value) {
                .class => |class| trainer.class = class,
                .encounter_music => |encounter_music| trainer.encounter_music.music = try math.cast(u7, encounter_music),
                .trainer_picture => |trainer_picture| trainer.trainer_picture = trainer_picture,
                .party_type => |party_type| trainer.party_type = party_type,
                .party_size => |party_size| party.size = party_size,
                .name => |str| try gen3.encodings.encode(.en_us, str, &trainer.name),
                .items => |items| {
                    if (items.index >= trainer.items.len)
                        return error.OutOfBound;

                    trainer.items[items.index] = lu16.init(items.value);
                },
                .party => |members| {
                    if (members.index >= party.size)
                        return error.Error;

                    const member = &party.members[members.index];
                    switch (members.value) {
                        .level => |level| member.base.level = lu16.init(level),
                        .species => |species| member.base.species = lu16.init(species),
                        .item => |item| member.item = lu16.init(item),
                        .moves => |moves| {
                            if (moves.index >= member.moves.len)
                                return error.IndexOutOfBound;
                            member.moves[moves.index] = lu16.init(moves.value);
                        },
                        .ability => return error.ParserFailed,
                    }
                },
            }
        },
        .moves => |moves| {
            if (moves.index >= math.min(game.move_names.len, game.moves.len))
                return error.Error;

            const move = &game.moves[moves.index];
            const move_name = &game.move_names[moves.index];
            switch (moves.value) {
                .name => |str| try gen3.encodings.encode(.en_us, str, move_name),
                .effect => |effect| move.effect = effect,
                .power => |power| move.power = power,
                .type => |_type| move.type = _type,
                .accuracy => |accuracy| move.accuracy = accuracy,
                .pp => |pp| move.pp = pp,
                .target => |target| move.target = target,
                .priority => |priority| move.priority = priority,
                .category => |category| move.category = category,
                .description => return error.IndexOutOfBound,
            }
        },
        .pokemons => |pokemons| {
            if (pokemons.index >= game.pokemons.len)
                return error.Error;

            const pokemon = &game.pokemons[pokemons.index];
            switch (pokemons.value) {
                .stats => |stats| format.setField(&pokemon.stats, stats),
                .ev_yield => |ev_yield| format.setField(&pokemon.ev_yield, ev_yield),
                .items => |items| {
                    if (items.index >= pokemon.items.len)
                        return error.IndexOutOfBound;
                    pokemon.items[items.index] = lu16.init(items.value);
                },
                .types => |types| {
                    if (types.index >= pokemon.types.len)
                        return error.IndexOutOfBound;
                    pokemon.types[types.index] = types.value;
                },
                .egg_groups => |egg_groups| {
                    if (egg_groups.index >= pokemon.egg_groups.len)
                        return error.IndexOutOfBound;
                    pokemon.egg_groups[egg_groups.index] = egg_groups.value;
                },
                .abilities => |abilities| {
                    if (abilities.index >= pokemon.abilities.len)
                        return error.IndexOutOfBound;
                    pokemon.abilities[abilities.index] = abilities.value;
                },
                .moves => |moves| {
                    if (pokemons.index >= game.level_up_learnset_pointers.len)
                        return error.IndexOutOfBound;

                    const ptr = &game.level_up_learnset_pointers[pokemons.index];
                    const lvl_up_moves = try ptr.toSliceZ2(game.data, gen3.LevelUpMove.term);
                    if (moves.index >= lvl_up_moves.len)
                        return error.IndexOutOfBound;

                    const lvl_up_move = &lvl_up_moves[moves.index];
                    switch (moves.value) {
                        .id => |id| lvl_up_move.id = try math.cast(u9, id),
                        .level => |level| lvl_up_move.level = try math.cast(u7, level),
                    }
                },
                .evos => |evos| {
                    if (pokemons.index >= game.evolutions.len)
                        return error.IndexOutOfBound;

                    const evolutions = &game.evolutions[pokemons.index];
                    if (evos.index >= evolutions.len)
                        return error.IndexOutOfBound;

                    const evolution = &evolutions[evos.index];
                    switch (evos.value) {
                        .method => |method| evolution.method = switch (method) {
                            .attack_eql_defense => .attack_eql_defense,
                            .attack_gth_defense => .attack_gth_defense,
                            .attack_lth_defense => .attack_lth_defense,
                            .beauty => .beauty,
                            .friend_ship => .friend_ship,
                            .friend_ship_during_day => .friend_ship_during_day,
                            .friend_ship_during_night => .friend_ship_during_night,
                            .level_up => .level_up,
                            .level_up_female => .level_up_female,
                            .level_up_holding_item_during_daytime => .level_up_holding_item_during_daytime,
                            .level_up_holding_item_during_the_night => .level_up_holding_item_during_the_night,
                            .level_up_in_special_magnetic_field => .level_up_in_special_magnetic_field,
                            .level_up_knowning_move => .level_up_knowning_move,
                            .level_up_male => .level_up_male,
                            .level_up_may_spawn_pokemon => .level_up_may_spawn_pokemon,
                            .level_up_near_ice_rock => .level_up_near_ice_rock,
                            .level_up_near_moss_rock => .level_up_near_moss_rock,
                            .level_up_spawn_if_cond => .level_up_spawn_if_cond,
                            .level_up_with_other_pokemon_in_party => .level_up_with_other_pokemon_in_party,
                            .personality_value1 => .personality_value1,
                            .personality_value2 => .personality_value2,
                            .trade => .trade,
                            .trade_holding_item => .trade_holding_item,
                            .unused => .unused,
                            .use_item => .use_item,
                            .use_item_on_female => .use_item_on_female,
                            .use_item_on_male => .use_item_on_male,
                            .unknown_0x02,
                            .unknown_0x03,
                            .trade_with_pokemon,
                            => return error.ParserFailed,
                        },
                        .param => |param| evolution.param = lu16.init(param),
                        .target => |target| evolution.target = lu16.init(target),
                    }
                },
                .color => |color| pokemon.color.color = color,
                .catch_rate => |catch_rate| pokemon.catch_rate = catch_rate,
                .base_exp_yield => |base_exp_yield| pokemon.base_exp_yield = try math.cast(u8, base_exp_yield),
                .gender_ratio => |gender_ratio| pokemon.gender_ratio = gender_ratio,
                .egg_cycles => |egg_cycles| pokemon.egg_cycles = egg_cycles,
                .base_friendship => |base_friendship| pokemon.base_friendship = base_friendship,
                .growth_rate => |growth_rate| pokemon.growth_rate = growth_rate,
                .tms, .hms => |ms| {
                    const is_tms = pokemons.value == .tms;
                    const len = if (is_tms) game.tms.len else game.hms.len;
                    if (ms.index >= len)
                        return error.Error;

                    const index = ms.index + game.tms.len * @boolToInt(!is_tms);
                    const learnset = &game.machine_learnsets[pokemons.index];
                    learnset.* = lu64.init(bit.setTo(u64, learnset.value(), @intCast(u6, index), ms.value));
                },
                .name => |str| {
                    if (pokemons.index >= game.pokemon_names.len)
                        return error.Error;
                    try gen3.encodings.encode(.en_us, str, &game.pokemon_names[pokemons.index]);
                },
                .pokedex_entry => |entry| {
                    if (pokemons.index == 0 or pokemons.index - 1 >= game.species_to_national_dex.len)
                        return error.Error;
                    game.species_to_national_dex[pokemons.index - 1] = lu16.init(entry);
                },
            }
        },
        .abilities => |abilities| {
            if (abilities.index >= game.ability_names.len)
                return error.Error;

            const ability_name = &game.ability_names[abilities.index];
            switch (abilities.value) {
                .name => |str| try gen3.encodings.encode(.en_us, str, ability_name),
            }
        },
        .types => |types| {
            if (types.index >= game.type_names.len)
                return error.Error;

            const type_name = &game.type_names[types.index];
            switch (types.value) {
                .name => |str| try gen3.encodings.encode(.en_us, str, type_name),
            }
        },
        .tms, .hms => |ms| {
            const pick = switch (parsed) {
                .tms => game.tms,
                .hms => game.hms,
                else => unreachable,
            };

            if (ms.index >= pick.len)
                return error.IndexOutOfBound;
            pick[ms.index] = lu16.init(ms.value);
        },
        .items => |items| {
            if (items.index >= game.items.len)
                return error.Error;

            const item = &game.items[items.index];
            switch (items.value) {
                .price => |price| item.price = lu16.init(try math.cast(u16, price)),
                .battle_effect => |battle_effect| item.battle_effect = battle_effect,
                .name => |str| try gen3.encodings.encode(.en_us, str, &item.name),
                .description => |str| {
                    const desc_small = try item.description.toSliceZ(game.data);
                    const desc = try item.description.toSlice(game.data, desc_small.len + 1);
                    try gen3.encodings.encode(.en_us, str, desc);
                },
                .pocket => |pocket| switch (game.version) {
                    .ruby, .sapphire, .emerald => item.pocket = gen3.Pocket{
                        .rse = switch (pocket) {
                            .none => .none,
                            .items => .items,
                            .key_items => .key_items,
                            .poke_balls => .poke_balls,
                            .tms_hms => .tms_hms,
                            .berries => .berries,
                        },
                    },
                    .fire_red, .leaf_green => item.pocket = gen3.Pocket{
                        .frlg = switch (pocket) {
                            .none => .none,
                            .items => .items,
                            .key_items => .key_items,
                            .poke_balls => .poke_balls,
                            .tms_hms => .tms_hms,
                            .berries => .berries,
                        },
                    },
                    else => unreachable,
                },
            }
        },
        .pokedex => |pokedex| {
            switch (game.version) {
                .emerald => {
                    if (pokedex.index >= game.pokedex.emerald.len)
                        return error.Error;

                    const entry = &game.pokedex.emerald[pokedex.index];
                    switch (pokedex.value) {
                        .height => |height| entry.height = lu16.init(try math.cast(u16, height)),
                        .weight => |weight| entry.weight = lu16.init(try math.cast(u16, weight)),
                        .category => return error.ParserFailed,
                    }
                },
                .ruby,
                .sapphire,
                .fire_red,
                .leaf_green,
                => {
                    if (pokedex.index >= game.pokedex.rsfrlg.len)
                        return error.Error;

                    const entry = &game.pokedex.rsfrlg[pokedex.index];
                    switch (pokedex.value) {
                        .height => |height| entry.height = lu16.init(try math.cast(u16, height)),
                        .weight => |weight| entry.weight = lu16.init(try math.cast(u16, weight)),
                        .category => return error.ParserFailed,
                    }
                },
                else => unreachable,
            }
        },
        .maps => |maps| {
            if (maps.index >= game.map_headers.len)
                return error.Error;

            const header = &game.map_headers[maps.index];
            switch (maps.value) {
                .music => |music| header.music = lu16.init(music),
                .cave => |cave| header.cave = cave,
                .weather => |weather| header.weather = weather,
                .type => |_type| header.map_type = _type,
                .escape_rope => |escape_rope| header.escape_rope = escape_rope,
                .battle_scene => |battle_scene| header.map_battle_scene = battle_scene,
                .allow_cycling => |allow_cycling| header.flags.allow_cycling = allow_cycling,
                .allow_escaping => |allow_escaping| header.flags.allow_escaping = allow_escaping,
                .allow_running => |allow_running| header.flags.allow_running = allow_running,
                .show_map_name => |show_map_name| header.flags.show_map_name = show_map_name,
            }
        },
        .wild_pokemons => |pokemons| {
            if (pokemons.index >= game.wild_pokemon_headers.len)
                return error.Error;

            const header = &game.wild_pokemon_headers[pokemons.index];
            switch (pokemons.value) {
                .land => |area| {
                    const land = try header.land.toPtr(game.data);
                    const wilds = try land.wild_pokemons.toPtr(game.data);
                    try applyGen3Area(area, &land.encounter_rate, wilds);
                },
                .surf => |area| {
                    const surf = try header.surf.toPtr(game.data);
                    const wilds = try surf.wild_pokemons.toPtr(game.data);
                    try applyGen3Area(area, &surf.encounter_rate, wilds);
                },
                .rock_smash => |area| {
                    const rock = try header.rock_smash.toPtr(game.data);
                    const wilds = try rock.wild_pokemons.toPtr(game.data);
                    try applyGen3Area(area, &rock.encounter_rate, wilds);
                },
                .fishing => |area| {
                    const fish = try header.fishing.toPtr(game.data);
                    const wilds = try fish.wild_pokemons.toPtr(game.data);
                    try applyGen3Area(area, &fish.encounter_rate, wilds);
                },
                .grass,
                .grass_morning,
                .grass_day,
                .grass_night,
                .dark_grass,
                .swarm_replace,
                .day_replace,
                .night_replace,
                .radar_replace,
                .unknown_replace,
                .gba_replace,
                .sea_unknown,
                .old_rod,
                .good_rod,
                .super_rod,
                .rustling_grass,
                .ripple_surf,
                .ripple_fishing,
                => return error.ParserFailed,
            }
        },
        .static_pokemons => |pokemons| {
            if (pokemons.index >= game.static_pokemons.len)
                return error.Error;

            const static_mon = game.static_pokemons[pokemons.index];
            switch (pokemons.value) {
                .species => |species| static_mon.species.* = lu16.init(species),
                .level => |level| static_mon.level.* = try math.cast(u8, level),
            }
        },
        .given_pokemons => |pokemons| {
            if (pokemons.index >= game.given_pokemons.len)
                return error.Error;

            const given_mon = game.given_pokemons[pokemons.index];
            switch (pokemons.value) {
                .species => |species| given_mon.species.* = lu16.init(species),
                .level => |level| given_mon.level.* = try math.cast(u8, level),
            }
        },
        .pokeball_items => |items| {
            if (items.index >= game.pokeball_items.len)
                return error.OutOfBound;

            const given_item = game.pokeball_items[items.index];
            switch (items.value) {
                .item => |item| given_item.item.* = lu16.init(item),
                .amount => |amount| given_item.amount.* = lu16.init(amount),
            }
        },
        .text => |texts| {
            if (texts.index >= game.text.len)
                return error.Error;
            const text_ptr = game.text[texts.index];
            const text_slice = try text_ptr.toSliceZ(game.data);

            // Slice to include the sentinel inside the slice.
            const text = text_slice[0 .. text_slice.len + 1];
            try gen3.encodings.encode(.en_us, texts.value, text);
        },
        .hidden_hollows,
        .instant_text,
        => return error.ParserFailed,
    }
}

fn applyGen3Area(area: format.WildArea, rate: *u8, wilds: []gen3.WildPokemon) !void {
    switch (area) {
        .encounter_rate => |encounter_rate| rate.* = try math.cast(u8, encounter_rate),
        .pokemons => |pokemons| {
            if (pokemons.index >= wilds.len)
                return error.IndexOutOfBound;

            const wild = &wilds[pokemons.index];
            switch (pokemons.value) {
                .min_level => |min_level| wild.min_level = min_level,
                .max_level => |max_level| wild.max_level = max_level,
                .species => |species| wild.species = lu16.init(species),
            }
        },
    }
}

fn applyGen4(game: gen4.Game, parsed: format.Game) !void {
    const header = game.rom.header();
    switch (parsed) {
        .version => |v| {
            if (v != game.info.version)
                return error.VersionDontMatch;
        },
        .game_title => |game_title| {
            if (!mem.eql(u8, game_title, header.game_title.span()))
                return error.GameTitleDontMatch;
        },
        .gamecode => |gamecode| {
            if (!mem.eql(u8, gamecode, &header.gamecode))
                return error.GameCodeDontMatch;
        },
        .instant_text => |instant_text| {
            if (instant_text)
                common.patch(game.owned.arm9, game.info.instant_text_patch);
        },
        .starters => |starters| {
            if (starters.index >= game.ptrs.starters.len)
                return error.Error;
            game.ptrs.starters[starters.index].* = lu16.init(starters.value);
        },
        .trainers => |trainers| {
            if (trainers.index >= game.ptrs.trainers.len)
                return error.Error;

            const trainer = &game.ptrs.trainers[trainers.index];
            switch (trainers.value) {
                .class => |class| trainer.class = class,
                .party_size => |party_size| trainer.party_size = party_size,
                .party_type => |party_type| trainer.party_type = party_type,
                .items => |items| {
                    if (items.index >= trainer.items.len)
                        return error.IndexOutOfBound;
                    trainer.items[items.index] = lu16.init(items.value);
                },
                .party => |party| {
                    if (trainers.index >= game.owned.trainer_parties.len)
                        return error.Error;
                    if (party.index >= trainer.party_size)
                        return error.Error;

                    const member = &game.owned.trainer_parties[trainers.index][party.index];
                    switch (party.value) {
                        .ability => |ability| member.base.gender_ability.ability = ability,
                        .level => |level| member.base.level = lu16.init(level),
                        .species => |species| member.base.species = lu16.init(species),
                        .item => |item| member.item = lu16.init(item),
                        .moves => |moves| {
                            if (moves.index >= member.moves.len)
                                return error.IndexOutOfBound;
                            member.moves[moves.index] = lu16.init(moves.value);
                        },
                    }
                },
                .encounter_music,
                .trainer_picture,
                .name,
                => return error.ParserFailed,
            }
        },
        .moves => |moves| {
            if (moves.index >= game.ptrs.moves.len)
                return error.Error;

            const descriptions = game.owned.strings.move_descriptions;
            const names = game.owned.strings.move_names;
            const move = &game.ptrs.moves[moves.index];
            switch (moves.value) {
                .description => |str| try applyGen4String(descriptions, moves.index, str),
                .name => |str| try applyGen4String(names, moves.index, str),
                .power => |power| move.power = power,
                .type => |_type| move.type = _type,
                .accuracy => |accuracy| move.accuracy = accuracy,
                .pp => |pp| move.pp = pp,
                .category => |category| move.category = category,
                .effect,
                .priority,
                .target,
                => return error.ParserFailed,
            }
        },
        .items => |items| {
            const descriptions = game.owned.strings.item_descriptions;
            const names = game.owned.strings.item_names;
            switch (items.value) {
                .description => |str| return applyGen4String(descriptions, items.index, str),
                .name => |str| return applyGen4String(names, items.index, str),
                .price,
                .battle_effect,
                .pocket,
                => {},
            }

            if (items.index >= game.ptrs.items.len)
                return error.IndexOutOfBound;

            const item = &game.ptrs.items[items.index];
            switch (items.value) {
                .description, .name => unreachable,
                .price => |price| item.price = lu16.init(try math.cast(u16, price)),
                .battle_effect => |battle_effect| item.battle_effect = battle_effect,
                .pocket => |pocket| item.pocket.pocket = switch (pocket) {
                    .items => .items,
                    .key_items => .key_items,
                    .tms_hms => .tms_hms,
                    .berries => .berries,
                    .poke_balls => .poke_balls,
                    .none => return error.ParserFailed,
                },
            }
        },
        .pokedex => |pokedex| {
            switch (pokedex.value) {
                .height => |height| {
                    if (pokedex.index >= game.ptrs.pokedex_heights.len)
                        return error.Error;
                    game.ptrs.pokedex_heights[pokedex.index] = lu32.init(height);
                },
                .weight => |weight| {
                    if (pokedex.index >= game.ptrs.pokedex_weights.len)
                        return error.Error;
                    game.ptrs.pokedex_weights[pokedex.index] = lu32.init(weight);
                },
                .category => return error.ParserFailed,
            }
        },
        .abilities => |abilities| {
            const names = game.owned.strings.ability_names;
            switch (abilities.value) {
                .name => |str| try applyGen4String(names, abilities.index, str),
            }
        },
        .types => |types| {
            const names = game.owned.strings.type_names;
            switch (types.value) {
                .name => |str| try applyGen4String(names, types.index, str),
            }
        },
        .pokemons => |pokemons| {
            if (pokemons.index >= game.ptrs.pokemons.len)
                return error.Error;

            const names = game.owned.strings.pokemon_names;
            const pokemon = &game.ptrs.pokemons[pokemons.index];
            switch (pokemons.value) {
                .stats => |stats| format.setField(&pokemon.stats, stats),
                .ev_yield => |ev_yield| format.setField(&pokemon.ev_yield, ev_yield),
                .items => |items| {
                    if (items.index >= pokemon.items.len)
                        return error.IndexOutOfBound;
                    pokemon.items[items.index] = lu16.init(items.value);
                },
                .types => |types| {
                    if (types.index >= pokemon.types.len)
                        return error.IndexOutOfBound;
                    pokemon.types[types.index] = types.value;
                },
                .egg_groups => |egg_groups| {
                    if (egg_groups.index >= pokemon.egg_groups.len)
                        return error.IndexOutOfBound;
                    pokemon.egg_groups[egg_groups.index] = egg_groups.value;
                },
                .abilities => |abilities| {
                    if (abilities.index >= pokemon.abilities.len)
                        return error.IndexOutOfBound;
                    pokemon.abilities[abilities.index] = abilities.value;
                },
                .catch_rate => |catch_rate| pokemon.catch_rate = catch_rate,
                .base_exp_yield => |base_exp_yield| pokemon.base_exp_yield = try math.cast(u8, base_exp_yield),
                .gender_ratio => |gender_ratio| pokemon.gender_ratio = gender_ratio,
                .egg_cycles => |egg_cycles| pokemon.egg_cycles = egg_cycles,
                .base_friendship => |base_friendship| pokemon.base_friendship = base_friendship,
                .growth_rate => |growth_rate| pokemon.growth_rate = growth_rate,
                .color => |color| pokemon.color.color = color,
                .name => |str| try applyGen4String(names, pokemons.index, str),
                .tms, .hms => |ms| {
                    const is_tms = pokemons.value == .tms;
                    const len = if (is_tms) game.ptrs.tms.len else game.ptrs.hms.len;
                    if (ms.index >= len)
                        return error.Error;

                    const index = ms.index + game.ptrs.tms.len * @boolToInt(!is_tms);
                    const learnset = &pokemon.machine_learnset;
                    learnset.* = lu128.init(bit.setTo(u128, learnset.value(), @intCast(u7, index), ms.value));
                },
                .moves => |moves| {
                    const bytes = game.ptrs.level_up_moves.fileData(.{ .i = @intCast(u32, pokemons.index) });
                    const rem = bytes.len % @sizeOf(gen4.LevelUpMove);
                    const lvl_up_moves = mem.bytesAsSlice(gen4.LevelUpMove, bytes[0 .. bytes.len - rem]);

                    if (moves.index >= lvl_up_moves.len)
                        return error.IndexOutOfBound;

                    const lvl_up_move = &lvl_up_moves[moves.index];
                    switch (moves.value) {
                        .id => |id| lvl_up_move.id = try math.cast(u9, id),
                        .level => |level| lvl_up_move.level = try math.cast(u7, level),
                    }
                },
                .evos => |evos| {
                    if (pokemons.index >= game.ptrs.evolutions.len)
                        return error.IndexOutOfBound;

                    const evolutions = &game.ptrs.evolutions[pokemons.index].items;
                    if (evos.index >= evolutions.len)
                        return error.IndexOutOfBound;

                    const evolution = &evolutions[evos.index];
                    switch (evos.value) {
                        .method => |method| evolution.method = switch (method) {
                            .attack_eql_defense => .attack_eql_defense,
                            .attack_gth_defense => .attack_gth_defense,
                            .attack_lth_defense => .attack_lth_defense,
                            .beauty => .beauty,
                            .friend_ship => .friend_ship,
                            .friend_ship_during_day => .friend_ship_during_day,
                            .friend_ship_during_night => .friend_ship_during_night,
                            .level_up => .level_up,
                            .level_up_female => .level_up_female,
                            .level_up_holding_item_during_daytime => .level_up_holding_item_during_daytime,
                            .level_up_holding_item_during_the_night => .level_up_holding_item_during_the_night,
                            .level_up_in_special_magnetic_field => .level_up_in_special_magnetic_field,
                            .level_up_knowning_move => .level_up_knowning_move,
                            .level_up_male => .level_up_male,
                            .level_up_may_spawn_pokemon => .level_up_may_spawn_pokemon,
                            .level_up_near_ice_rock => .level_up_near_ice_rock,
                            .level_up_near_moss_rock => .level_up_near_moss_rock,
                            .level_up_spawn_if_cond => .level_up_spawn_if_cond,
                            .level_up_with_other_pokemon_in_party => .level_up_with_other_pokemon_in_party,
                            .personality_value1 => .personality_value1,
                            .personality_value2 => .personality_value2,
                            .trade => .trade,
                            .trade_holding_item => .trade_holding_item,
                            .unused => .unused,
                            .use_item => .use_item,
                            .use_item_on_female => .use_item_on_female,
                            .use_item_on_male => .use_item_on_male,
                            .unknown_0x02,
                            .unknown_0x03,
                            .trade_with_pokemon,
                            => return error.ParserFailed,
                        },
                        .param => |param| evolution.param = lu16.init(param),
                        .target => |target| evolution.target = lu16.init(target),
                    }
                },
                .pokedex_entry => |pokedex_entry| {
                    if (pokemons.index == 0 or pokemons.index - 1 >= game.ptrs.species_to_national_dex.len)
                        return error.Error;
                    game.ptrs.species_to_national_dex[pokemons.index - 1] = lu16.init(pokedex_entry);
                },
            }
        },
        .tms, .hms => |ms| {
            const pick = switch (parsed) {
                .tms => game.ptrs.tms,
                .hms => game.ptrs.hms,
                else => unreachable,
            };

            if (ms.index >= pick.len)
                return error.IndexOutOfBound;
            pick[ms.index] = lu16.init(ms.value);
        },
        .wild_pokemons => |pokemons| {
            const wild_pokemons = game.ptrs.wild_pokemons;
            switch (game.info.version) {
                .diamond,
                .pearl,
                .platinum,
                => {
                    if (pokemons.index >= wild_pokemons.dppt.len)
                        return error.IndexOutOfBound;

                    const wilds = &wild_pokemons.dppt[pokemons.index];
                    switch (pokemons.value) {
                        .grass => |grass| switch (grass) {
                            .encounter_rate => |encounter_rate| wilds.grass_rate = lu32.init(encounter_rate),
                            .pokemons => |mons| {
                                if (mons.index >= wilds.grass.len)
                                    return error.IndexOutOfBound;

                                const mon = &wilds.grass[mons.index];
                                switch (mons.value) {
                                    .min_level => |min_level| mon.level = min_level,
                                    .max_level => |max_level| mon.level = max_level,
                                    .species => |species| mon.species = lu16.init(species),
                                }
                            },
                        },
                        .swarm_replace => |area| try applyDpptReplacement(area, &wilds.swarm_replace),
                        .day_replace => |area| try applyDpptReplacement(area, &wilds.day_replace),
                        .night_replace => |area| try applyDpptReplacement(area, &wilds.night_replace),
                        .radar_replace => |area| try applyDpptReplacement(area, &wilds.radar_replace),
                        .unknown_replace => |area| try applyDpptReplacement(area, &wilds.unknown_replace),
                        .gba_replace => |area| try applyDpptReplacement(area, &wilds.gba_replace),
                        .surf => |area| try applyDpptSea(area, &wilds.surf),
                        .sea_unknown => |area| try applyDpptSea(area, &wilds.sea_unknown),
                        .old_rod => |area| try applyDpptSea(area, &wilds.old_rod),
                        .good_rod => |area| try applyDpptSea(area, &wilds.good_rod),
                        .super_rod => |area| try applyDpptSea(area, &wilds.super_rod),
                        .grass_morning,
                        .grass_day,
                        .grass_night,
                        .dark_grass,
                        .rock_smash,
                        .fishing,
                        .land,
                        .rustling_grass,
                        .ripple_surf,
                        .ripple_fishing,
                        => return error.ParserFailed,
                    }
                },

                .heart_gold,
                .soul_silver,
                => {
                    if (pokemons.index >= wild_pokemons.hgss.len)
                        return error.IndexOutOfBound;

                    const wilds = &wild_pokemons.hgss[pokemons.index];
                    switch (pokemons.value) {
                        .grass_morning => |area| try applyHgssGrass(area, wilds, &wilds.grass_morning),
                        .grass_day => |area| try applyHgssGrass(area, wilds, &wilds.grass_day),
                        .grass_night => |area| try applyHgssGrass(area, wilds, &wilds.grass_night),
                        .surf => |area| try applyHgssSea(area, &wilds.sea_rates[0], &wilds.surf),
                        .sea_unknown => |area| try applyHgssSea(area, &wilds.sea_rates[1], &wilds.sea_unknown),
                        .old_rod => |area| try applyHgssSea(area, &wilds.sea_rates[2], &wilds.old_rod),
                        .good_rod => |area| try applyHgssSea(area, &wilds.sea_rates[3], &wilds.good_rod),
                        .super_rod => |area| try applyHgssSea(area, &wilds.sea_rates[4], &wilds.super_rod),
                        .grass,
                        .dark_grass,
                        .swarm_replace,
                        .day_replace,
                        .night_replace,
                        .radar_replace,
                        .unknown_replace,
                        .gba_replace,
                        .rock_smash,
                        .fishing,
                        .land,
                        .rustling_grass,
                        .ripple_surf,
                        .ripple_fishing,
                        => return error.ParserFailed,
                    }
                },
                else => unreachable,
            }
        },
        .static_pokemons => |pokemons| {
            if (pokemons.index >= game.ptrs.static_pokemons.len)
                return error.Error;

            const static_mon = game.ptrs.static_pokemons[pokemons.index];
            switch (pokemons.value) {
                .species => |species| static_mon.species.* = lu16.init(species),
                .level => |level| static_mon.level.* = lu16.init(level),
            }
        },
        .given_pokemons => |pokemons| {
            if (pokemons.index >= game.ptrs.given_pokemons.len)
                return error.Error;

            const given_mon = game.ptrs.given_pokemons[pokemons.index];
            switch (pokemons.value) {
                .species => |species| given_mon.species.* = lu16.init(species),
                .level => |level| given_mon.level.* = lu16.init(level),
            }
        },
        .pokeball_items => |items| {
            if (items.index >= game.ptrs.pokeball_items.len)
                return error.Error;
            const given_item = game.ptrs.pokeball_items[items.index];

            switch (items.value) {
                .item => |item| given_item.item.* = lu16.init(item),
                .amount => |amount| given_item.amount.* = lu16.init(amount),
            }
        },
        .hidden_hollows,
        .text,
        .maps,
        .text_delays,
        => return error.ParserFailed,
    }
}

fn applyHgssGrass(area: format.WildArea, wilds: *gen4.HgssWildPokemons, grass: *[12]lu16) !void {
    switch (area) {
        .encounter_rate => |encounter_rate| wilds.grass_rate = try math.cast(u8, encounter_rate),
        .pokemons => |pokemons| {
            if (pokemons.index >= grass.len)
                return error.Error;

            switch (pokemons.value) {
                .min_level => |min_level| wilds.grass_levels[pokemons.index] = min_level,
                .max_level => |max_level| wilds.grass_levels[pokemons.index] = max_level,
                .species => |species| grass[pokemons.index] = lu16.init(species),
            }
        },
    }
}

fn applyHgssSea(area: format.WildArea, rate: *u8, sea: []gen4.HgssWildPokemons.Sea) !void {
    switch (area) {
        .encounter_rate => |encounter_rate| rate.* = try math.cast(u8, encounter_rate),
        .pokemons => |pokemons| {
            if (pokemons.index >= sea.len)
                return error.IndexOutOfBound;

            const mon = &sea[pokemons.index];
            switch (pokemons.value) {
                .species => |species| mon.species = lu16.init(species),
                .min_level => |min_level| mon.min_level = min_level,
                .max_level => |max_level| mon.max_level = max_level,
            }
        },
    }
}

fn applyDpptReplacement(area: format.WildArea, replacements: []gen4.DpptWildPokemons.Replacement) !void {
    switch (area) {
        .pokemons => |pokemons| {
            if (pokemons.index >= replacements.len)
                return error.IndexOutOfBound;

            const replacement = &replacements[pokemons.index];
            switch (pokemons.value) {
                .species => |species| replacement.species = lu16.init(species),
                .min_level,
                .max_level,
                => return error.ParserFailed,
            }
        },
        .encounter_rate => return error.ParserFailed,
    }
}

fn applyDpptSea(area: format.WildArea, sea: *gen4.DpptWildPokemons.Sea) !void {
    switch (area) {
        .encounter_rate => |encounter_rate| sea.rate = lu32.init(encounter_rate),
        .pokemons => |pokemons| {
            if (pokemons.index >= sea.mons.len)
                return error.IndexOutOfBound;

            const mon = &sea.mons[pokemons.index];
            switch (pokemons.value) {
                .species => |species| mon.species = lu16.init(species),
                .min_level => |min_level| mon.min_level = min_level,
                .max_level => |max_level| mon.max_level = max_level,
            }
        },
    }
}

fn applyGen4String(strs: gen4.StringTable, index: usize, value: []const u8) !void {
    if (strs.number_of_strings <= index)
        return error.Error;

    const buf = strs.get(index);
    const writer = io.fixedBufferStream(buf).writer();
    try writer.writeAll(value);

    // Null terminate, if we didn't fill the buffer
    if (writer.context.pos < buf.len)
        buf[writer.context.pos] = 0;
}

fn applyGen5(game: gen5.Game, parsed: format.Game) !void {
    const header = game.rom.header();
    switch (parsed) {
        .version => |v| {
            if (v != game.info.version)
                return error.VersionDontMatch;
        },
        .game_title => |game_title| {
            if (!mem.eql(u8, game_title, header.game_title.span()))
                return error.GameTitleDontMatch;
        },
        .gamecode => |gamecode| {
            if (!mem.eql(u8, gamecode, &header.gamecode))
                return error.GameCodeDontMatch;
        },
        .instant_text => |instant_text| {
            if (instant_text)
                common.patch(game.owned.arm9, game.info.instant_text_patch);
        },
        .starters => |starters| {
            if (starters.index >= game.ptrs.starters.len)
                return error.Error;
            for (game.ptrs.starters[starters.index]) |starter|
                starter.* = lu16.init(starters.value);
        },
        .trainers => |trainers| {
            if (trainers.index == 0 or trainers.index - 1 >= game.ptrs.trainers.len)
                return error.Error;

            const names = game.owned.strings.trainer_names;
            const trainer = &game.ptrs.trainers[trainers.index - 1];
            switch (trainers.value) {
                .class => |class| trainer.class = class,
                .name => |str| try applyGen5String(names, trainers.index, str),
                .items => |items| {
                    if (items.index >= trainer.items.len)
                        return error.IndexOutOfBound;
                    trainer.items[items.index] = lu16.init(items.value);
                },
                .party_size => |party_size| trainer.party_size = party_size,
                .party_type => |party_type| trainer.party_type = party_type,
                .party => |party| {
                    if (trainers.index >= game.owned.trainer_parties.len)
                        return error.Error;
                    if (party.index >= trainer.party_size)
                        return error.Error;

                    const member = &game.owned.trainer_parties[trainers.index][party.index];
                    switch (party.value) {
                        .ability => |ability| member.base.gender_ability.ability = ability,
                        .level => |level| member.base.level = level,
                        .species => |species| member.base.species = lu16.init(species),
                        .item => |item| member.item = lu16.init(item),
                        .moves => |moves| {
                            if (moves.index >= member.moves.len)
                                return error.IndexOutOfBound;
                            member.moves[moves.index] = lu16.init(moves.value);
                        },
                    }
                },
                .encounter_music,
                .trainer_picture,
                => return error.ParserFailed,
            }
        },
        .pokemons => |pokemons| {
            if (pokemons.index >= game.ptrs.pokemons.fat.len)
                return error.Error;

            const names = game.owned.strings.pokemon_names;
            const pokemon = try game.ptrs.pokemons.fileAs(.{ .i = pokemons.index }, gen5.BasePokemon);
            switch (pokemons.value) {
                .stats => |stats| format.setField(&pokemon.stats, stats),
                .ev_yield => |ev_yield| format.setField(&pokemon.ev_yield, ev_yield),
                .items => |items| {
                    if (items.index >= pokemon.items.len)
                        return error.IndexOutOfBound;
                    pokemon.items[items.index] = lu16.init(items.value);
                },
                .types => |types| {
                    if (types.index >= pokemon.types.len)
                        return error.IndexOutOfBound;
                    pokemon.types[types.index] = types.value;
                },
                .egg_groups => |egg_groups| {
                    if (egg_groups.index >= pokemon.egg_groups.len)
                        return error.IndexOutOfBound;
                    pokemon.egg_groups[egg_groups.index] = egg_groups.value;
                },
                .abilities => |abilities| {
                    if (abilities.index >= pokemon.abilities.len)
                        return error.IndexOutOfBound;
                    pokemon.abilities[abilities.index] = abilities.value;
                },
                .catch_rate => |catch_rate| pokemon.catch_rate = catch_rate,
                .gender_ratio => |gender_ratio| pokemon.gender_ratio = gender_ratio,
                .egg_cycles => |egg_cycles| pokemon.egg_cycles = egg_cycles,
                .base_friendship => |base_friendship| pokemon.base_friendship = base_friendship,
                .base_exp_yield => |base_exp_yield| pokemon.base_exp_yield = lu16.init(base_exp_yield),
                .growth_rate => |growth_rate| pokemon.growth_rate = growth_rate,
                .color => |color| pokemon.color.color = color,
                .name => |str| try applyGen5String(names, pokemons.index, str),
                .tms, .hms => |ms| {
                    const is_tms = pokemons.value == .tms;
                    const len = if (is_tms) game.ptrs.tms1.len + game.ptrs.tms2.len else game.ptrs.hms.len;
                    if (ms.index >= len)
                        return error.Error;

                    const index = if (is_tms) ms.index else ms.index + game.ptrs.tms1.len + game.ptrs.tms2.len;
                    const learnset = &pokemon.machine_learnset;
                    learnset.* = lu128.init(bit.setTo(u128, learnset.value(), @intCast(u7, index), ms.value));
                },
                .moves => |moves| {
                    const bytes = game.ptrs.level_up_moves.fileData(.{ .i = pokemons.index });
                    const rem = bytes.len % @sizeOf(gen5.LevelUpMove);
                    const lvl_up_moves = mem.bytesAsSlice(gen5.LevelUpMove, bytes[0 .. bytes.len - rem]);

                    if (moves.index >= lvl_up_moves.len)
                        return error.IndexOutOfBound;

                    const lvl_up_move = &lvl_up_moves[moves.index];
                    switch (moves.value) {
                        .id => |id| lvl_up_move.id = lu16.init(id),
                        .level => |level| lvl_up_move.level = lu16.init(level),
                    }
                },
                .evos => |evos| {
                    if (pokemons.index >= game.ptrs.evolutions.len)
                        return error.Error;

                    const evolutions = &game.ptrs.evolutions[pokemons.index].items;
                    if (evos.index >= evolutions.len)
                        return error.IndexOutOfBound;

                    const evolution = &evolutions[evos.index];
                    switch (evos.value) {
                        .method => |method| evolution.method = switch (method) {
                            .attack_eql_defense => .attack_eql_defense,
                            .attack_gth_defense => .attack_gth_defense,
                            .attack_lth_defense => .attack_lth_defense,
                            .beauty => .beauty,
                            .friend_ship => .friend_ship,
                            .level_up => .level_up,
                            .level_up_female => .level_up_female,
                            .level_up_holding_item_during_daytime => .level_up_holding_item_during_daytime,
                            .level_up_holding_item_during_the_night => .level_up_holding_item_during_the_night,
                            .level_up_in_special_magnetic_field => .level_up_in_special_magnetic_field,
                            .level_up_knowning_move => .level_up_knowning_move,
                            .level_up_male => .level_up_male,
                            .level_up_may_spawn_pokemon => .level_up_may_spawn_pokemon,
                            .level_up_near_ice_rock => .level_up_near_ice_rock,
                            .level_up_near_moss_rock => .level_up_near_moss_rock,
                            .level_up_spawn_if_cond => .level_up_spawn_if_cond,
                            .level_up_with_other_pokemon_in_party => .level_up_with_other_pokemon_in_party,
                            .personality_value1 => .personality_value1,
                            .personality_value2 => .personality_value2,
                            .trade => .trade,
                            .trade_holding_item => .trade_holding_item,
                            .unused => .unused,
                            .use_item => .use_item,
                            .use_item_on_female => .use_item_on_female,
                            .use_item_on_male => .use_item_on_male,
                            .unknown_0x02 => .unknown_0x02,
                            .unknown_0x03 => .unknown_0x03,
                            .trade_with_pokemon => .trade_with_pokemon,
                            .friend_ship_during_day,
                            .friend_ship_during_night,
                            => return error.ParserFailed,
                        },
                        .param => |param| evolution.param = lu16.init(param),
                        .target => |target| evolution.target = lu16.init(target),
                    }
                },
                .pokedex_entry => |pokedex_entry| {
                    if (pokemons.index != pokedex_entry)
                        return error.TryingToChangeReadOnlyField;
                },
            }
        },
        .tms => |tms| {
            if (tms.index >= game.ptrs.tms1.len + game.ptrs.tms2.len)
                return error.IndexOutOfBound;
            if (tms.index < game.ptrs.tms1.len) {
                game.ptrs.tms1[tms.index] = lu16.init(tms.value);
            } else {
                game.ptrs.tms2[tms.index - game.ptrs.tms1.len] = lu16.init(tms.value);
            }
        },
        .hms => |hms| {
            if (hms.index >= game.ptrs.hms.len)
                return error.IndexOutOfBound;
            game.ptrs.hms[hms.index] = lu16.init(hms.value);
        },
        .items => |items| {
            if (items.index >= game.ptrs.items.len)
                return error.IndexOutOfBound;

            const descriptions = game.owned.strings.item_descriptions;
            const item = &game.ptrs.items[items.index];
            switch (items.value) {
                .price => |price| item.price = lu16.init(try math.cast(u16, price / 10)),
                .battle_effect => |battle_effect| item.battle_effect = battle_effect,
                .description => |str| try applyGen5String(descriptions, items.index, str),
                .name => |str| {
                    const names_on_ground = game.owned.strings.item_names_on_the_ground;
                    const item_names = game.owned.strings.item_names;
                    if (items.index >= item_names.keys.len)
                        return error.Error;

                    const old_name = item_names.getSpan(items.index);
                    // Here, we also applies the item name to the item_names_on_the_ground
                    // table. The way we do this is to search for the item name in the
                    // ground string, and if it exists, we replace it and apply this new
                    // string
                    applyGen5StringReplace(names_on_ground, items.index, old_name, str) catch {};
                    try applyGen5String(item_names, items.index, str);
                },
                .pocket => |pocket| item.pocket.pocket = switch (pocket) {
                    .items => .items,
                    .key_items => .key_items,
                    .poke_balls => .poke_balls,
                    .tms_hms => .tms_hms,
                    .berries,
                    .none,
                    => return error.ParserFailed,
                },
            }
        },
        .pokedex => |pokedex| {
            const names = game.owned.strings.pokedex_category_names;
            switch (pokedex.value) {
                .category => |category| try applyGen5String(names, pokedex.index, category),
                .height,
                .weight,
                => return error.ParserFailed,
            }
        },
        .moves => |moves| {
            if (moves.index >= game.ptrs.moves.len)
                return error.IndexOutOfBound;

            const names = game.owned.strings.move_names;
            const descriptions = game.owned.strings.move_descriptions;
            const move = &game.ptrs.moves[moves.index];
            switch (moves.value) {
                .description => |str| try applyGen5String(descriptions, moves.index, str),
                .name => |str| try applyGen5String(names, moves.index, str),
                .effect => |effect| move.effect = lu16.init(effect),
                .power => |power| move.power = power,
                .type => |_type| move.type = _type,
                .accuracy => |accuracy| move.accuracy = accuracy,
                .pp => |pp| move.pp = pp,
                .target => |target| move.target = target,
                .priority => |priority| move.priority = priority,
                .category => |category| move.category = category,
            }
        },
        .abilities => |abilities| {
            const names = game.owned.strings.ability_names;
            switch (abilities.value) {
                .name => |str| try applyGen5String(names, abilities.index, str),
            }
        },
        .types => |types| {
            const names = game.owned.strings.type_names;
            switch (types.value) {
                .name => |str| try applyGen5String(names, types.index, str),
            }
        },
        .maps => |maps| {
            if (maps.index >= game.ptrs.map_headers.len)
                return error.Error;

            const map_header = &game.ptrs.map_headers[maps.index];
            switch (maps.value) {
                .music => |music| map_header.music = lu16.init(music),
                .battle_scene => |battle_scene| map_header.battle_scene = battle_scene,
                .allow_cycling,
                .allow_escaping,
                .allow_running,
                .show_map_name,
                .weather,
                .cave,
                .type,
                .escape_rope,
                => return error.ParserFailed,
            }
        },
        .wild_pokemons => |pokemons| {
            if (pokemons.index >= game.ptrs.wild_pokemons.fat.len)
                return error.Error;

            const wilds = try game.ptrs.wild_pokemons.fileAs(.{ .i = pokemons.index }, gen5.WildPokemons);
            switch (pokemons.value) {
                .grass => |area| try applyGen5Area(area, "grass", 0, wilds),
                .dark_grass => |area| try applyGen5Area(area, "dark_grass", 1, wilds),
                .rustling_grass => |area| try applyGen5Area(area, "rustling_grass", 2, wilds),
                .surf => |area| try applyGen5Area(area, "surf", 3, wilds),
                .ripple_surf => |area| try applyGen5Area(area, "ripple_surf", 4, wilds),
                .fishing => |area| try applyGen5Area(area, "fishing", 5, wilds),
                .ripple_fishing => |area| try applyGen5Area(area, "ripple_fishing", 6, wilds),
                .grass_morning,
                .grass_day,
                .grass_night,
                .land,
                .rock_smash,
                .swarm_replace,
                .day_replace,
                .night_replace,
                .radar_replace,
                .unknown_replace,
                .gba_replace,
                .sea_unknown,
                .old_rod,
                .good_rod,
                .super_rod,
                => return error.ParserFailed,
            }
        },
        .static_pokemons => |pokemons| {
            if (pokemons.index >= game.ptrs.static_pokemons.len)
                return error.Error;

            const static_mon = game.ptrs.static_pokemons[pokemons.index];
            switch (pokemons.value) {
                .species => |species| static_mon.species.* = lu16.init(species),
                .level => |level| static_mon.level.* = lu16.init(level),
            }
        },
        .given_pokemons => |pokemons| {
            if (pokemons.index >= game.ptrs.given_pokemons.len)
                return error.Error;

            const given_mon = game.ptrs.given_pokemons[pokemons.index];
            switch (pokemons.value) {
                .species => |species| given_mon.species.* = lu16.init(species),
                .level => |level| given_mon.level.* = lu16.init(level),
            }
        },
        .pokeball_items => |items| {
            if (items.index >= game.ptrs.pokeball_items.len)
                return error.IndexOutOfBound;

            const given_item = game.ptrs.pokeball_items[items.index];
            switch (items.value) {
                .item => |item| given_item.item.* = lu16.init(item),
                .amount => |amount| given_item.amount.* = lu16.init(amount),
            }
        },
        .hidden_hollows => |hidden_hollows| if (game.ptrs.hidden_hollows) |hollows| {
            if (hidden_hollows.index >= hollows.len)
                return error.Error;

            const hollow = &hollows[hidden_hollows.index];
            switch (hidden_hollows.value) {
                .groups => |groups| {
                    if (groups.index >= hollow.pokemons.len)
                        return error.Error;

                    const group = &hollow.pokemons[groups.index];
                    switch (groups.value) {
                        .pokemons => |pokemons| {
                            if (pokemons.index >= group.species.len)
                                return error.IndexOutOfBound;

                            switch (pokemons.value) {
                                .species => |species| group.species[pokemons.index] = lu16.init(species),
                            }
                        },
                    }
                },
                .items => |items| {
                    if (items.index >= hollow.items.len)
                        return error.ParserFailed;

                    hollow.items[items.index] = lu16.init(items.value);
                },
            }
        } else {
            return error.ParserFailed;
        },
        .text_delays,
        .text,
        => return error.ParserFailed,
    }
}

fn applyGen5Area(
    area: format.WildArea,
    comptime field: []const u8,
    index: usize,
    wilds: *gen5.WildPokemons,
) !void {
    switch (area) {
        .encounter_rate => |encounter_rate| wilds.rates[index] = try math.cast(u8, encounter_rate),
        .pokemons => |pokemons| {
            const wild_area = &@field(wilds, field);
            if (pokemons.index >= wild_area.len)
                return error.Error;

            const wild = &wild_area[pokemons.index];
            switch (pokemons.value) {
                .min_level => |min_level| wild.min_level = min_level,
                .max_level => |max_level| wild.max_level = max_level,
                .species => |species| wild.species.setSpecies(try math.cast(u10, species)),
            }
        },
    }
}

fn applyGen5StringReplace(
    strs: gen5.StringTable,
    index: usize,
    search_for: []const u8,
    replace_with: []const u8,
) !void {
    if (strs.keys.len <= index)
        return error.Error;

    const str = strs.getSpan(index);
    const i = mem.indexOf(u8, str, search_for) orelse return;
    const before = str[0..i];
    const after = str[i + search_for.len ..];

    var buf: [1024]u8 = undefined;
    const writer = io.fixedBufferStream(&buf).writer();
    try writer.writeAll(before);
    try writer.writeAll(replace_with);
    try writer.writeAll(after);
    _ = writer.write("\x00") catch undefined;

    const written = writer.context.getWritten();
    const copy_into = strs.get(index);
    if (copy_into.len < written.len)
        return error.Error;

    mem.copy(u8, copy_into, written);

    // Null terminate, if we didn't fill the buffer
    if (written.len < copy_into.len)
        buf[written.len] = 0;
}

fn applyGen5String(strs: gen5.StringTable, index: usize, value: []const u8) !void {
    if (strs.keys.len <= index)
        return error.Error;

    const buf = strs.get(index);
    const writer = io.fixedBufferStream(buf).writer();
    try writer.writeAll(value);

    // Null terminate, if we didn't fill the buffer
    if (writer.context.pos < buf.len)
        buf[writer.context.pos] = 0;
}

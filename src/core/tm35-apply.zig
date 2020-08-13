const clap = @import("clap");
const std = @import("std");
const util = @import("util");

const common = @import("common.zig");
const gen3 = @import("gen3.zig");
const gen4 = @import("gen4.zig");
const gen5 = @import("gen5.zig");
const rom = @import("rom.zig");

const builtin = std.builtin;
const debug = std.debug;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;

const path = fs.path;

const gba = rom.gba;
const nds = rom.nds;

const bit = util.bit;
const escape = util.escape;
const exit = util.exit;
const parse = util.parse;

const li16 = rom.int.li16;
const lu16 = rom.int.lu16;
const lu32 = rom.int.lu32;
const lu64 = rom.int.lu64;
const lu128 = rom.int.lu128;

const Clap = clap.ComptimeClap(clap.Help, &params);
const Param = clap.Param(clap.Help);

pub const main = util.generateMain("0.0.0", main2, &params, usage);

const params = blk: {
    @setEvalBranchQuota(100000);
    break :blk [_]Param{
        clap.parseParam("-a, --abort-on-first-warning  Abort execution on the first warning emitted.") catch unreachable,
        clap.parseParam("-h, --help                    Display this help text and exit.             ") catch unreachable,
        clap.parseParam("-o, --output <FILE>           Override destination path.                   ") catch unreachable,
        clap.parseParam("-r, --replace                 Replace output file if it already exists.    ") catch unreachable,
        clap.parseParam("-v, --version                 Output version information and exit.         ") catch unreachable,
        Param{ .takes_value = true },
    };
};

fn usage(stream: var) !void {
    try stream.writeAll("Usage: tm35-apply ");
    try clap.usage(stream, &params);
    try stream.writeAll("\nApplies changes to Pokémon roms.\n" ++
        "\n" ++
        "Options:\n");
    try clap.help(stream, &params);
}

/// TODO: This function actually expects an allocator that owns all the memory allocated, such
///       as ArenaAllocator or FixedBufferAllocator. Can we either make this requirement explicit
///       or move the Arena into this function?
pub fn main2(
    allocator: *mem.Allocator,
    comptime InStream: type,
    comptime OutStream: type,
    stdio: util.CustomStdIoStreams(InStream, OutStream),
    args: var,
) u8 {
    const pos = args.positionals();
    const file_name = if (pos.len > 0) pos[0] else {
        stdio.err.writeAll("No file provided\n") catch {};
        usage(stdio.err) catch {};
        return 1;
    };

    const abort_on_first_warning = args.flag("--abort-on-first-warning");
    const replace = args.flag("--replace");
    const out = args.option("--output") orelse blk: {
        const res = fmt.allocPrint(allocator, "{}.modified", .{path.basename(file_name)});
        break :blk res catch |err| return exit.allocErr(stdio.err);
    };

    var nds_rom: nds.Rom = undefined;
    var game: Game = blk: {
        const file = fs.cwd().openFile(file_name, .{}) catch |err| return exit.openErr(stdio.err, file_name, err);
        defer file.close();

        const gen3_error = if (gen3.Game.fromFile(file, allocator)) |game| {
            break :blk Game{ .gen3 = game };
        } else |err| err;

        file.seekTo(0) catch |err| return exit.readErr(stdio.err, file_name, err);
        nds_rom = nds.Rom.fromFile(file, allocator) catch |nds_error| {
            stdio.err.print("Failed to load '{}' as a gen3 game: {}\n", .{ file_name, gen3_error }) catch {};
            stdio.err.print("Failed to load '{}' as a gen4/gen5 game: {}\n", .{ file_name, nds_error }) catch {};
            return 1;
        };

        const gen4_error = if (gen4.Game.fromRom(allocator, &nds_rom)) |game| {
            break :blk Game{ .gen4 = game };
        } else |err| err;

        const gen5_error = if (gen5.Game.fromRom(allocator, &nds_rom)) |game| {
            break :blk Game{ .gen5 = game };
        } else |err| err;

        stdio.err.print("Successfully loaded '{}' as a nds rom.\n", .{file_name}) catch {};
        stdio.err.print("Failed to load '{}' as a gen4 game: {}\n", .{ file_name, gen4_error }) catch {};
        stdio.err.print("Failed to load '{}' as a gen5 game: {}\n", .{ file_name, gen5_error }) catch {};
        return 1;
    };
    defer switch (game) {
        .gen3 => |*gen3_game| gen3_game.deinit(),
        .gen4 => |*gen4_game| gen4_game.deinit(),
        .gen5 => |*gen5_game| gen5_game.deinit(),
    };

    var line_num: usize = 1;
    var line_buf = std.ArrayList(u8).init(allocator);
    var stdin = io.bufferedInStream(stdio.in);

    while (util.readLine(&stdin, &line_buf) catch |err| return exit.stdinErr(stdio.err, err)) |line| : (line_num += 1) {
        const trimmed = mem.trimRight(u8, line, "\r\n");
        _ = switch (game) {
            .gen3 => |*gen3_game| applyGen3(gen3_game, line_num, trimmed),
            .gen4 => |gen4_game| applyGen4(nds_rom, gen4_game, line_num, trimmed),
            .gen5 => |gen5_game| applyGen5(nds_rom, gen5_game, line_num, trimmed),
        } catch |err| {
            stdio.err.print("(stdin):{}:1: warning: {}\n", .{ line_num, @errorName(err) }) catch {};
            stdio.err.print("{}\n", .{line}) catch {};
            if (abort_on_first_warning)
                return 1;
        };
        line_buf.resize(0) catch unreachable;
    }

    const out_file = fs.cwd().createFile(out, .{ .exclusive = !replace }) catch |err| return exit.createErr(stdio.err, out, err);
    const out_stream = out_file.outStream();
    switch (game) {
        .gen3 => |gen3_game| gen3_game.writeToStream(out_stream) catch |err| return exit.writeErr(stdio.err, out, err),
        .gen4, .gen5 => nds_rom.writeToFile(out_file) catch |err| return exit.writeErr(stdio.err, out, err),
    }

    return 0;
}

const Game = union(enum) {
    gen3: gen3.Game,
    gen4: gen4.Game,
    gen5: gen5.Game,
};

const sw = parse.Swhash(16);
const c = sw.case;
const m = sw.match;

pub fn toInt(
    comptime Int: type,
    comptime endian: builtin.Endian,
) fn ([]const u8) ?rom.int.Int(Int, endian) {
    return struct {
        const Res = rom.int.Int(Int, endian);
        fn func(str: []const u8) ?Res {
            const i = parse.toInt(Int, 10)(str) orelse return null;
            return Res.init(i);
        }
    }.func;
}

pub const parseli16v = parse.value(li16, toInt(i16, .Little));
pub const parselu16v = parse.value(lu16, toInt(u16, .Little));
pub const parselu32v = parse.value(lu32, toInt(u32, .Little));
pub const parselu64v = parse.value(lu64, toInt(u64, .Little));

pub const converters = .{
    parse.toBool,
    parse.toEnum(common.MoveCategory),
    parse.toEnum(common.EvoMethod),
    parse.toEnum(gen4.Pocket),
    parse.toEnum(gen5.Evolution.Method),
    parse.toEnum(gen5.Pocket),
    parse.toInt(u1, 10),
    parse.toInt(u2, 10),
    parse.toInt(u4, 10),
    parse.toInt(u7, 10),
    parse.toInt(u8, 10),
    parse.toInt(u9, 10),
    parse.toInt(u16, 10),
    parse.toInt(u32, 10),
    parse.toInt(u64, 10),
    toInt(u16, .Little),
    toInt(u32, .Little),
    toInt(u64, .Little),
};

fn applyGen3(game: *gen3.Game, line: usize, str: []const u8) !void {
    var parser = parse.MutParser{ .str = str };
    switch (m(try parser.parse(parse.anyField))) {
        c("version") => {
            const value = try parser.parse(comptime parse.enumv(common.Version));
            if (value != game.version)
                return error.VersionDontMatch;
        },
        c("game_title") => {
            const value = try parser.parse(parse.strv);
            if (!mem.eql(u8, value, &game.header.game_title))
                return error.GameTitleDontMatch;
        },
        c("gamecode") => {
            const value = try parser.parse(parse.strv);
            if (!mem.eql(u8, value, &game.header.gamecode))
                return error.GameCodeDontMatch;
        },
        c("starters") => {
            const index = try parser.parse(parse.index);
            const value = try parser.parse(parselu16v);
            if (index >= game.starters.len)
                return error.Error;
            game.starters[index].* = value;
            game.starters_repeat[index].* = value;
        },
        c("text_delays") => {
            const index = try parser.parse(parse.index);
            if (index >= game.text_delays.len)
                return error.Error;
            game.text_delays[index] = try parser.parse(parse.u8v);
        },
        c("trainers") => {
            const index = try parser.parse(parse.index);
            if (index >= game.trainers.len)
                return error.Error;
            const trainer = &game.trainers[index];

            const field = try parser.parse(parse.anyField);
            switch (m(field)) {
                c("class") => trainer.class = try parser.parse(parse.u8v),
                c("gender") => trainer.encounter_music.gender = try parser.parse(comptime parse.enumv(gen3.Gender)),
                c("encounter_music") => trainer.encounter_music.music = try parser.parse(parse.u7v),
                c("trainer_picture") => trainer.trainer_picture = try parser.parse(parse.u8v),
                c("is_double") => trainer.is_double = try parser.parse(parselu32v),
                c("ai") => trainer.ai = try parser.parse(parselu32v),
                c("name") => try gen3.encodings.encode(.en_us, try parser.parse(parse.strv), &trainer.name),
                c("items") => try parse.anyT(parser.str, &trainer.items, converters),
                c("party_size"), c("party_type") => {
                    const is_len = c("party_size") == m(field);

                    const old_member_size = trainer.party_type.memberSize();
                    const old_type = trainer.party_type;
                    const old_len = trainer.partyLen();
                    const old_size = old_member_size * old_len;

                    var new_len: u32 = undefined;
                    var new_type: gen3.PartyType = undefined;
                    const new_size = if (is_len) blk: {
                        new_len = try parser.parse(parse.u32v);
                        break :blk new_len * old_member_size;
                    } else blk: {
                        new_type = try parser.parse(comptime parse.enumv(gen3.PartyType));
                        break :blk old_len * new_type.memberSize();
                    };

                    if (new_size > old_size) {
                        const Ptr = gen3.Ptr([*]gen3.PartyMemberNone);
                        const old_bytes = try trainer.partyBytes(game.data);
                        const new_bytes = game.requestFreeBytes(new_size);
                        mem.set(u8, new_bytes, 0x0);
                        mem.copy(u8, new_bytes, old_bytes);
                        mem.set(u8, old_bytes, 0xff);
                        trainer.party.none.inner.ptr = try Ptr.init(new_bytes.ptr, game.data);
                    }
                    if (is_len) {
                        trainer.party.none.inner.len = lu32.init(new_len);
                    } else {
                        // A lot of boilerplat code for changing the party type correctly.
                        // We copy out the old party, and then write it back in. This
                        // ensures that as much data from the old party is preserved
                        // without overriding things during copy.
                        var old_copy = [_]gen3.PartyMemberBoth{.{}} ** 6;
                        switch (trainer.party_type) {
                            .none => for (try trainer.party.none.toSlice(game.data)) |member, j| {
                                old_copy[j].base = member.base;
                            },
                            .item => for (try trainer.party.item.toSlice(game.data)) |member, j| {
                                old_copy[j].base = member.base;
                                old_copy[j].item = member.item;
                            },
                            .moves => for (try trainer.party.moves.toSlice(game.data)) |member, j| {
                                old_copy[j].base = member.base;
                                old_copy[j].moves = member.moves;
                            },
                            .both => mem.copy(
                                gen3.PartyMemberBoth,
                                &old_copy,
                                try trainer.party.both.toSlice(game.data),
                            ),
                        }

                        trainer.party_type = new_type;
                        switch (trainer.party_type) {
                            .none => for (try trainer.party.none.toSlice(game.data)) |*member, j| {
                                member.base = old_copy[j].base;
                            },
                            .item => for (try trainer.party.item.toSlice(game.data)) |*member, j| {
                                member.base = old_copy[j].base;
                                member.item = old_copy[j].item;
                            },
                            .moves => for (try trainer.party.moves.toSlice(game.data)) |*member, j| {
                                member.base = old_copy[j].base;
                                member.moves = old_copy[j].moves;
                            },
                            .both => mem.copy(
                                gen3.PartyMemberBoth,
                                try trainer.party.both.toSlice(game.data),
                                old_copy[0..old_len],
                            ),
                        }
                    }

                    const old_bytes = try trainer.partyBytes(game.data);
                    mem.set(u8, old_bytes[new_size..], 0xff);
                },
                c("party") => {
                    const pindex = try parser.parse(parse.index);
                    if (pindex >= trainer.partyLen())
                        return error.Error;
                    const member = try trainer.partyAt(pindex, game.data);

                    switch (m(try parser.parse(parse.anyField))) {
                        c("iv") => member.iv = try parser.parse(parselu16v),
                        c("level") => member.level = try parser.parse(parselu16v),
                        c("species") => member.species = try parser.parse(parselu16v),
                        c("item") => {
                            const item = try parser.parse(parselu16v);
                            switch (trainer.party_type) {
                                .item => member.toParent(gen3.PartyMemberItem).item = item,
                                .both => member.toParent(gen3.PartyMemberBoth).item = item,
                                else => return error.NoField,
                            }
                        },
                        c("moves") => switch (trainer.party_type) {
                            .moves => {
                                const move_member = member.toParent(gen3.PartyMemberMoves);
                                try parse.anyT(parser.str, &move_member.moves, converters);
                            },
                            .both => {
                                const move_member = member.toParent(gen3.PartyMemberBoth);
                                try parse.anyT(parser.str, &move_member.moves, converters);
                            },
                            else => return error.NoField,
                        },
                        else => return error.NoField,
                    }
                },
                else => return error.NoField,
            }
        },
        c("pokemons") => {
            const index = try parser.parse(parse.index);
            if (index >= game.pokemons.len)
                return error.Error;
            const pokemon = &game.pokemons[index];

            const field = try parser.parse(parse.anyField);
            switch (m(field)) {
                c("stats") => try parse.anyT(parser.str, &pokemon.stats, converters),
                c("types") => try parse.anyT(parser.str, &pokemon.types, converters),
                c("items") => try parse.anyT(parser.str, &pokemon.items, converters),
                c("abilities") => try parse.anyT(parser.str, &pokemon.abilities, converters),
                c("ev_yield") => try parse.anyT(parser.str, &pokemon.ev_yield, converters),
                c("evos") => try parse.anyT(parser.str, &game.evolutions[index], converters),
                c("catch_rate") => pokemon.catch_rate = try parser.parse(parse.u8v),
                c("base_exp_yield") => pokemon.base_exp_yield = try parser.parse(parse.u8v),
                c("gender_ratio") => pokemon.gender_ratio = try parser.parse(parse.u8v),
                c("egg_cycles") => pokemon.egg_cycles = try parser.parse(parse.u8v),
                c("base_friendship") => pokemon.base_friendship = try parser.parse(parse.u8v),
                c("growth_rate") => pokemon.growth_rate = try parser.parse(comptime parse.enumv(common.GrowthRate)),
                c("safari_zone_rate") => pokemon.safari_zone_rate = try parser.parse(parse.u8v),
                c("color") => pokemon.color.color = try parser.parse(comptime parse.enumv(common.ColorKind)),
                c("flip") => pokemon.color.flip = try parser.parse(parse.boolv),
                c("egg_groups") => {
                    const eindex = try parser.parse(parse.index);
                    const evalue = try parser.parse(comptime parse.enumv(common.EggGroup));
                    switch (eindex) {
                        0 => pokemon.egg_group1 = evalue,
                        1 => pokemon.egg_group2 = evalue,
                        else => return error.Error,
                    }
                },
                c("tms"), c("hms") => {
                    const is_tms = c("tms") == m(field);
                    const tindex = try parser.parse(parse.index);
                    const value = try parser.parse(parse.boolv);
                    const len = if (is_tms) game.tms.len else game.hms.len;
                    if (tindex >= len)
                        return error.Error;

                    const rindex = tindex + game.tms.len * @boolToInt(!is_tms);
                    const learnset = &game.machine_learnsets[index];
                    learnset.* = lu64.init(bit.setTo(u64, learnset.value(), @intCast(u6, rindex), value));
                },
                c("moves") => {
                    const ptr = &game.level_up_learnset_pointers[index];
                    const lvl_up_moves = try ptr.toSliceZ2(game.data, gen3.LevelUpMove.term);
                    try parse.anyT(parser.str, &lvl_up_moves, converters);
                },
                c("name") => {
                    if (index >= game.pokemon_names.len)
                        return error.Error;

                    const new_name = try parser.parse(parse.strv);
                    try gen3.encodings.encode(.en_us, new_name, &game.pokemon_names[index]);
                },
                c("pokedex_entry") => {
                    if (index == 0 or index - 1 >= game.species_to_national_dex.len)
                        return error.Error;
                    game.species_to_national_dex[index - 1] = try parser.parse(parselu16v);
                },
                else => return error.NoField,
            }
        },
        c("tms") => try parse.anyT(parser.str, &game.tms, converters),
        c("hms") => try parse.anyT(parser.str, &game.hms, converters),
        c("moves") => {
            const index = try parser.parse(parse.index);
            const prev = parser.str;
            const field = try parser.parse(parse.anyField);
            switch (m(field)) {
                c("name") => {
                    if (index >= game.move_names.len)
                        return error.Error;
                    try gen3.encodings.encode(.en_us, try parser.parse(parse.strv), &game.move_names[index]);
                },
                else => {
                    if (index >= game.moves.len)
                        return error.Error;
                    try parse.anyT(prev, &game.moves[index], converters);
                },
            }
        },
        c("items") => {
            const index = try parser.parse(parse.index);
            if (index >= game.items.len)
                return error.Error;
            const item = &game.items[index];

            switch (m(try parser.parse(parse.anyField))) {
                c("id") => item.id = try parser.parse(parselu16v),
                c("price") => item.price = try parser.parse(parselu16v),
                c("hold_effect") => item.hold_effect = try parser.parse(parse.u8v),
                c("hold_effect_par") => item.hold_effect_param = try parser.parse(parse.u8v),
                c("importance") => item.importance = try parser.parse(parse.u8v),
                c("type") => item.@"type" = try parser.parse(parse.u8v),
                c("battle_usage") => item.battle_usage = try parser.parse(parselu32v),
                c("secondary_id") => item.secondary_id = try parser.parse(parselu32v),
                c("name") => try gen3.encodings.encode(.en_us, try parser.parse(parse.strv), &item.name),
                c("description") => {
                    const desc_small = try item.description.toSliceZ(game.data);
                    const description = try item.description.toSlice(game.data, desc_small.len + 1);
                    try gen3.encodings.encode(.en_us, try parser.parse(parse.strv), description);
                },
                c("pocket") => switch (game.version) {
                    .ruby, .sapphire, .emerald => item.pocket = gen3.Pocket{ .rse = try parser.parse(comptime parse.enumv(gen3.RSEPocket)) },
                    .fire_red, .leaf_green => item.pocket = gen3.Pocket{ .frlg = try parser.parse(comptime parse.enumv(gen3.FRLGPocket)) },
                    else => unreachable,
                },
                else => return error.NoField,
            }
        },
        c("pokedex") => {
            const index = try parser.parse(parse.index);
            switch (game.version) {
                .emerald => {
                    if (index >= game.pokedex.emerald.len)
                        return error.Error;
                    const entry = &game.pokedex.emerald[index];

                    switch (m(try parser.parse(parse.anyField))) {
                        c("height") => entry.height = try parser.parse(parselu16v),
                        c("weight") => entry.weight = try parser.parse(parselu16v),
                        c("pokemon_scale") => entry.pokemon_scale = try parser.parse(parselu16v),
                        c("pokemon_offset") => entry.pokemon_offset = try parser.parse(parseli16v),
                        c("trainer_scale") => entry.trainer_scale = try parser.parse(parselu16v),
                        c("trainer_offset") => entry.trainer_offset = try parser.parse(parseli16v),
                        else => return error.NoField,
                    }
                },
                .ruby,
                .sapphire,
                .fire_red,
                .leaf_green,
                => {
                    if (index >= game.pokedex.rsfrlg.len)
                        return error.Error;
                    const entry = &game.pokedex.rsfrlg[index];

                    switch (m(try parser.parse(parse.anyField))) {
                        c("height") => entry.height = try parser.parse(parselu16v),
                        c("weight") => entry.weight = try parser.parse(parselu16v),
                        c("pokemon_scale") => entry.pokemon_scale = try parser.parse(parselu16v),
                        c("pokemon_offset") => entry.pokemon_offset = try parser.parse(parseli16v),
                        c("trainer_scale") => entry.trainer_scale = try parser.parse(parselu16v),
                        c("trainer_offset") => entry.trainer_offset = try parser.parse(parseli16v),
                        else => return error.NoField,
                    }
                },
                else => unreachable,
            }
        },
        c("abilities") => {
            const index = try parser.parse(parse.index);
            if (index >= game.ability_names.len)
                return error.Error;

            switch (m(try parser.parse(parse.anyField))) {
                c("name") => try gen3.encodings.encode(.en_us, try parser.parse(parse.strv), &game.ability_names[index]),
                else => return error.Error,
            }
        },
        c("types") => {
            const index = try parser.parse(parse.index);
            if (index >= game.type_names.len)
                return error.Error;

            switch (m(try parser.parse(parse.anyField))) {
                c("name") => try gen3.encodings.encode(.en_us, try parser.parse(parse.strv), &game.type_names[index]),
                else => return error.Error,
            }
        },
        c("map") => {
            const index = try parser.parse(parse.index);
            if (index >= game.map_headers.len)
                return error.Error;

            const header = &game.map_headers[index];
            switch (m(try parser.parse(parse.anyField))) {
                c("music") => header.music = try parser.parse(parselu16v),
                c("cave") => header.cave = try parser.parse(parse.u8v),
                c("weather") => header.weather = try parser.parse(parse.u8v),
                c("type") => header.map_type = try parser.parse(parse.u8v),
                c("escape_rope") => header.escape_rope = try parser.parse(parse.u8v),
                c("battle_scene") => header.map_battle_scene = try parser.parse(parse.u8v),
                c("allow_cycling") => header.flags.allow_cycling = try parser.parse(parse.boolv),
                c("allow_escaping") => header.flags.allow_escaping = try parser.parse(parse.boolv),
                c("allow_running") => header.flags.allow_running = try parser.parse(parse.boolv),
                c("show_map_name") => header.flags.show_map_name = try parser.parse(parse.boolv),
                else => return error.NoField,
            }
        },
        c("wild_pokemons") => {
            const index = try parser.parse(parse.index);
            if (index >= game.wild_pokemon_headers.len)
                return error.Error;

            const header = &game.wild_pokemon_headers[index];
            switch (m(try parser.parse(parse.anyField))) {
                c("land") => {
                    const land = try header.land.toPtr(game.data);
                    const wilds = try land.wild_pokemons.toPtr(game.data);
                    try applyGen3Area(&parser, &land.encounter_rate, wilds);
                },
                c("surf") => {
                    const surf = try header.surf.toPtr(game.data);
                    const wilds = try surf.wild_pokemons.toPtr(game.data);
                    try applyGen3Area(&parser, &surf.encounter_rate, wilds);
                },
                c("rock_smash") => {
                    const rock = try header.rock_smash.toPtr(game.data);
                    const wilds = try rock.wild_pokemons.toPtr(game.data);
                    try applyGen3Area(&parser, &rock.encounter_rate, wilds);
                },
                c("fishing") => {
                    const fish = try header.fishing.toPtr(game.data);
                    const wilds = try fish.wild_pokemons.toPtr(game.data);
                    try applyGen3Area(&parser, &fish.encounter_rate, wilds);
                },
                else => return error.NoField,
            }
        },
        c("static_pokemons") => {
            const index = try parser.parse(parse.index);
            if (index >= game.static_pokemons.len)
                return error.Error;
            const static_mon = game.static_pokemons[index].data();

            switch (m(try parser.parse(parse.anyField))) {
                c("species") => static_mon.setwildbattle.species = try parser.parse(parselu16v),
                c("level") => static_mon.setwildbattle.level = try parser.parse(parse.u8v),
                c("item") => static_mon.setwildbattle.item = try parser.parse(parselu16v),
                else => return error.NoField,
            }
        },
        c("pokeball_items") => {
            const index = try parser.parse(parse.index);
            if (index >= game.pokeball_items.len)
                return error.Error;
            const given_item = game.pokeball_items[index];

            switch (m(try parser.parse(parse.anyField))) {
                c("item") => given_item.item.* = try parser.parse(parselu16v),
                c("amount") => given_item.amount.* = try parser.parse(parselu16v),
                else => return error.NoField,
            }
        },
        c("text") => {
            const index = try parser.parse(parse.index);
            if (index >= game.text.len)
                return error.Error;
            const text_ptr = game.text[index];
            const text_slice = try text_ptr.toSliceZ(game.data);

            // Slice to include the sentinel inside the slice.
            const text = text_slice[0 .. text_slice.len + 1];
            try gen3.encodings.encode(.en_us, try parser.parse(parse.strv), text);
        },
        else => return error.NoField,
    }
}

fn applyGen3Area(par: *parse.MutParser, rate: *u8, wilds: []gen3.WildPokemon) !void {
    switch (m(try par.parse(parse.anyField))) {
        c("encounter_rate") => rate.* = try par.parse(parse.u8v),
        c("pokemons") => try parse.anyT(par.str, &wilds, converters),
        else => return error.NoField,
    }
}

fn applyGen4(nds_rom: nds.Rom, game: gen4.Game, line: usize, str: []const u8) !void {
    var parser = parse.MutParser{ .str = str };
    const header = nds_rom.header();
    switch (m(try parser.parse(parse.anyField))) {
        c("version") => {
            const value = try parser.parse(comptime parse.enumv(common.Version));
            if (value != game.version)
                return error.VersionDontMatch;
        },
        c("game_title") => {
            const value = try parser.parse(parse.strv);
            const null_index = mem.indexOfScalar(u8, &header.game_title, 0) //
                orelse header.game_title.len;
            if (!mem.eql(u8, value, header.game_title[0..null_index]))
                return error.GameTitleDontMatch;
        },
        c("gamecode") => {
            const value = try parser.parse(parse.strv);
            if (!mem.eql(u8, value, &header.gamecode))
                return error.GameCodeDontMatch;
        },
        c("instant_text") => {
            if (try parser.parse(parse.boolv))
                common.patch(game.arm9, game.instant_text_patch);
        },
        c("starters") => {
            const index = try parser.parse(parse.index);
            if (index >= game.starters.len)
                return error.Error;
            game.starters[index].* = try parser.parse(parselu16v);
        },
        c("trainers") => {
            const index = try parser.parse(parse.index);
            if (index >= game.trainers.len)
                return error.Error;

            const trainer = &game.trainers[index];
            switch (m(try parser.parse(parse.anyField))) {
                c("class") => trainer.class = try parser.parse(parse.u8v),
                c("battle_type") => trainer.battle_type = try parser.parse(parse.u8v),
                c("battle_type2") => trainer.battle_type2 = try parser.parse(parse.u8v),
                c("ai") => trainer.ai = try parser.parse(parselu32v),
                c("items") => try parse.anyT(parser.str, &trainer.items, converters),
                c("party") => {
                    const pindex = try parser.parse(parse.index);
                    if (pindex >= trainer.party_size)
                        return error.Error;
                    const party_file = game.parties.fileData(.{ .i = @intCast(u32, index) });
                    const member = trainer.partyMember(game.version, party_file, pindex) orelse return error.OutOfBound;

                    switch (m(try parser.parse(parse.anyField))) {
                        c("iv") => member.iv = try parser.parse(parse.u8v),
                        c("gender") => member.gender_ability.gender = try parser.parse(parse.u4v),
                        c("ability") => member.gender_ability.ability = try parser.parse(parse.u4v),
                        c("level") => member.level = try parser.parse(parselu16v),
                        c("species") => member.species = try parser.parse(parselu16v),
                        c("item") => switch (trainer.party_type) {
                            .item => member.toParent(gen4.PartyMemberItem).item = try parser.parse(parselu16v),
                            .both => member.toParent(gen4.PartyMemberBoth).item = try parser.parse(parselu16v),
                            else => return error.NoField,
                        },
                        c("moves") => switch (trainer.party_type) {
                            .moves => {
                                const move_member = member.toParent(gen4.PartyMemberMoves);
                                try parse.anyT(parser.str, &move_member.moves, converters);
                            },
                            .both => {
                                const move_member = member.toParent(gen4.PartyMemberBoth);
                                try parse.anyT(parser.str, &move_member.moves, converters);
                            },
                            else => return error.NoField,
                        },
                        else => return error.NoField,
                    }
                },
                else => return error.NoField,
            }
        },
        c("moves") => {
            const index = try parser.parse(parse.index);
            const prev = parser.str;
            const field = try parser.parse(parse.anyField);
            switch (m(field)) {
                c("description") => try applyGen4String(game.move_descriptions, index, try parser.parse(parse.strv)),
                c("name") => try applyGen4String(game.move_names, index, try parser.parse(parse.strv)),
                else => {
                    if (index >= game.moves.len)
                        return error.Error;
                    try parse.anyT(prev, &game.moves[index], converters);
                },
            }
        },
        c("items") => {
            const index = try parser.parse(parse.index);
            const prev = parser.str;
            const field = try parser.parse(parse.anyField);
            switch (m(field)) {
                c("description") => try applyGen4String(game.item_descriptions, index, try parser.parse(parse.strv)),
                c("name") => try applyGen4String(game.item_names, index, try parser.parse(parse.strv)),
                else => {
                    if (index >= game.items.len)
                        return error.Error;
                    try parse.anyT(prev, &game.items[index], converters);
                },
            }
        },
        c("pokedex") => {
            const index = try parser.parse(parse.index);
            switch (m(try parser.parse(parse.anyField))) {
                c("height") => {
                    if (index >= game.pokedex_heights.len)
                        return error.Error;
                    game.pokedex_heights[index] = try parser.parse(parselu32v);
                },
                c("weight") => {
                    if (index >= game.pokedex_weights.len)
                        return error.Error;
                    game.pokedex_weights[index] = try parser.parse(parselu32v);
                },
                else => return error.NoField,
            }
        },
        c("abilities") => {
            const index = try parser.parse(parse.index);
            switch (m(try parser.parse(parse.anyField))) {
                c("name") => try applyGen4String(game.ability_names, index, try parser.parse(parse.strv)),
                else => return error.Error,
            }
        },
        c("types") => {
            const index = try parser.parse(parse.index);
            switch (m(try parser.parse(parse.anyField))) {
                c("name") => try applyGen4String(game.type_names, index, try parser.parse(parse.strv)),
                else => return error.Error,
            }
        },
        c("pokemons") => {
            const index = try parser.parse(parse.index);
            if (index >= game.pokemons.len)
                return error.Error;
            const pokemon = &game.pokemons[index];

            const field = try parser.parse(parse.anyField);
            switch (m(field)) {
                c("stats") => try parse.anyT(parser.str, &pokemon.stats, converters),
                c("types") => try parse.anyT(parser.str, &pokemon.types, converters),
                c("items") => try parse.anyT(parser.str, &pokemon.items, converters),
                c("abilities") => try parse.anyT(parser.str, &pokemon.abilities, converters),
                c("ev_yield") => try parse.anyT(parser.str, &pokemon.ev_yield, converters),
                c("catch_rate") => pokemon.catch_rate = try parser.parse(parse.u8v),
                c("base_exp_yield") => pokemon.base_exp_yield = try parser.parse(parse.u8v),
                c("gender_ratio") => pokemon.gender_ratio = try parser.parse(parse.u8v),
                c("egg_cycles") => pokemon.egg_cycles = try parser.parse(parse.u8v),
                c("base_friendship") => pokemon.base_friendship = try parser.parse(parse.u8v),
                c("growth_rate") => pokemon.growth_rate = try parser.parse(comptime parse.enumv(common.GrowthRate)),
                c("flee_rate") => pokemon.flee_rate = try parser.parse(parse.u8v),
                c("color") => pokemon.color.color = try parser.parse(comptime parse.enumv(common.ColorKind)),
                c("flip") => pokemon.color.flip = try parser.parse(parse.boolv),
                c("name") => try applyGen4String(game.pokemon_names, index, try parser.parse(parse.strv)),
                c("egg_groups") => {
                    const eindex = try parser.parse(parse.index);
                    const evalue = try parser.parse(comptime parse.enumv(common.EggGroup));
                    switch (eindex) {
                        0 => pokemon.egg_group1 = evalue,
                        1 => pokemon.egg_group2 = evalue,
                        else => return error.Error,
                    }
                },
                c("tms"), c("hms") => {
                    const is_tms = c("tms") == m(field);
                    const tindex = try parser.parse(parse.index);
                    const value = try parser.parse(parse.boolv);
                    const len = if (is_tms) game.tms.len else game.hms.len;
                    if (tindex >= len)
                        return error.Error;

                    const rindex = tindex + game.tms.len * @boolToInt(!is_tms);
                    const learnset = &pokemon.machine_learnset;
                    learnset.* = lu128.init(bit.setTo(u128, learnset.value(), @intCast(u7, rindex), value));
                },
                c("moves") => {
                    const bytes = game.level_up_moves.fileData(.{ .i = @intCast(u32, index) });
                    const rem = bytes.len % @sizeOf(gen4.LevelUpMove);
                    const lum = mem.bytesAsSlice(gen4.LevelUpMove, bytes[0 .. bytes.len - rem]);
                    try parse.anyT(parser.str, &lum, converters);
                },
                c("evos") => {
                    if (game.evolutions.len <= index)
                        return error.Error;
                    try parse.anyT(parser.str, &game.evolutions[index].items, converters);
                },
                c("pokedex_entry") => {
                    if (index == 0 or index - 1 >= game.species_to_national_dex.len)
                        return error.Error;
                    game.species_to_national_dex[index - 1] = try parser.parse(parselu16v);
                },
                else => return error.NoField,
            }
        },
        c("tms") => try parse.anyT(parser.str, &game.tms, converters),
        c("hms") => try parse.anyT(parser.str, &game.hms, converters),
        c("wild_pokemons") => {
            const wild_pokemons = game.wild_pokemons;
            const index = try parser.parse(parse.index);

            switch (game.version) {
                .diamond,
                .pearl,
                .platinum,
                => {
                    const wilds = &wild_pokemons.dppt[index];
                    switch (m(try parser.parse(parse.anyField))) {
                        c("grass") => switch (m(try parser.parse(parse.anyField))) {
                            c("encounter_rate") => wilds.grass_rate = try parser.parse(parselu32v),
                            c("pokemons") => {
                                const i = try parser.parse(parse.index);
                                if (i >= wilds.grass.len)
                                    return error.IndexOutOfBound;
                                switch (m(try parser.parse(parse.anyField))) {
                                    c("min_level") => wilds.grass[i].level = try parser.parse(parse.u8v),
                                    c("max_level") => wilds.grass[i].level = try parser.parse(parse.u8v),
                                    c("species") => wilds.grass[i].species = try parser.parse(parselu16v),
                                    else => return error.NoField,
                                }
                            },
                            else => return error.NoField,
                        },
                        c("swarm_replace") => try applyDpptReplacement(&parser, &wilds.swarm_replace),
                        c("day_replace") => try applyDpptReplacement(&parser, &wilds.day_replace),
                        c("night_replace") => try applyDpptReplacement(&parser, &wilds.night_replace),
                        c("radar_replace") => try applyDpptReplacement(&parser, &wilds.radar_replace),
                        c("unknown_replace") => try applyDpptReplacement(&parser, &wilds.unknown_replace),
                        c("gba_replace") => try applyDpptReplacement(&parser, &wilds.gba_replace),
                        c("surf") => try applyDpptSea(&parser, &wilds.surf),
                        c("sea_unknown") => try applyDpptSea(&parser, &wilds.sea_unknown),
                        c("old_rod") => try applyDpptSea(&parser, &wilds.old_rod),
                        c("good_rod") => try applyDpptSea(&parser, &wilds.good_rod),
                        c("super_rod") => try applyDpptSea(&parser, &wilds.super_rod),
                        else => return error.NoField,
                    }
                },

                .heart_gold,
                .soul_silver,
                => {
                    const wilds = &wild_pokemons.hgss[index];
                    switch (m(try parser.parse(parse.anyField))) {
                        c("grass_morning") => try applyHgssGrass(&parser, wilds, &wilds.grass_morning),
                        c("grass_day") => try applyHgssGrass(&parser, wilds, &wilds.grass_day),
                        c("grass_night") => try applyHgssGrass(&parser, wilds, &wilds.grass_night),
                        c("surf") => try applyHgssSea(&parser, &wilds.sea_rates[0], &wilds.surf),
                        c("sea_unknown") => try applyHgssSea(&parser, &wilds.sea_rates[1], &wilds.sea_unknown),
                        c("old_rod") => try applyHgssSea(&parser, &wilds.sea_rates[2], &wilds.old_rod),
                        c("good_rod") => try applyHgssSea(&parser, &wilds.sea_rates[3], &wilds.good_rod),
                        c("super_rod") => try applyHgssSea(&parser, &wilds.sea_rates[4], &wilds.super_rod),
                        else => return error.NoField,
                    }
                },
                else => unreachable,
            }
        },
        c("static_pokemons") => {
            const index = try parser.parse(parse.index);
            if (index >= game.static_pokemons.len)
                return error.Error;

            const static_mon = game.static_pokemons[index];
            switch (m(try parser.parse(parse.anyField))) {
                c("species") => static_mon.species.* = try parser.parse(parselu16v),
                c("level") => static_mon.level.* = try parser.parse(parselu16v),
                else => return error.NoField,
            }
        },
        c("pokeball_items") => {
            const index = try parser.parse(parse.index);
            if (index >= game.pokeball_items.len)
                return error.Error;
            const given_item = game.pokeball_items[index];

            switch (m(try parser.parse(parse.anyField))) {
                c("item") => given_item.item.* = try parser.parse(parselu16v),
                c("amount") => given_item.amount.* = try parser.parse(parselu16v),
                else => return error.NoField,
            }
        },
        else => return error.NoField,
    }
}

fn applyHgssGrass(par: *parse.MutParser, wilds: *gen4.HgssWildPokemons, grass: *[12]lu16) !void {
    switch (m(try par.parse(parse.anyField))) {
        c("encounter_rate") => wilds.grass_rate = try par.parse(parse.u8v),
        c("pokemons") => {
            const index = try par.parse(parse.index);
            if (index >= grass.len)
                return error.Error;
            switch (m(try par.parse(parse.anyField))) {
                c("min_level") => wilds.grass_levels[index] = try par.parse(parse.u8v),
                c("max_level") => wilds.grass_levels[index] = try par.parse(parse.u8v),
                c("species") => grass[index] = try par.parse(parselu16v),
                else => return error.NoField,
            }
        },
        else => return error.NoField,
    }
}

fn applyHgssSea(par: *parse.MutParser, rate: *u8, sea: []gen4.HgssWildPokemons.Sea) !void {
    switch (m(try par.parse(parse.anyField))) {
        c("encounter_rate") => rate.* = try par.parse(parse.u8v),
        c("pokemons") => try parse.anyT(par.str, &sea, converters),
        else => return error.NoField,
    }
}

fn applyDpptReplacement(par: *parse.MutParser, area: []gen4.DpptWildPokemons.Replacement) !void {
    try par.parse(comptime parse.field("pokemons"));
    try parse.anyT(par.str, &area, converters);
}

fn applyDpptSea(par: *parse.MutParser, sea: *gen4.DpptWildPokemons.Sea) !void {
    switch (m(try par.parse(parse.anyField))) {
        c("encounter_rate") => sea.rate = try par.parse(parselu32v),
        c("pokemons") => try parse.anyT(par.str, &sea.mons, converters),
        else => return error.NoField,
    }
}

fn applyGen4String(table: gen4.StringTable, index: usize, value: []const u8) !void {
    if (index >= table.count())
        return error.Error;
    const stream = table.getStringStream(@intCast(u32, index)).outStream();
    try gen4.encodings.encode(value, stream);
}

fn applyGen5(nds_rom: nds.Rom, game: gen5.Game, line: usize, str: []const u8) !void {
    var parser = parse.MutParser{ .str = str };
    const header = nds_rom.header();

    switch (m(try parser.parse(parse.anyField))) {
        c("version") => {
            const value = try parser.parse(comptime parse.enumv(common.Version));
            if (value != game.version)
                return error.VersionDontMatch;
        },
        c("game_title") => {
            const value = try parser.parse(parse.strv);
            const null_index = mem.indexOfScalar(u8, &header.game_title, 0) //
                orelse header.game_title.len;
            if (!mem.eql(u8, value, header.game_title[0..null_index]))
                return error.GameTitleDontMatch;
        },
        c("gamecode") => {
            const value = try parser.parse(parse.strv);
            if (!mem.eql(u8, value, &header.gamecode))
                return error.GameCodeDontMatch;
        },
        c("instant_text") => {
            if (try parser.parse(parse.boolv))
                common.patch(game.arm9, game.instant_text_patch);
        },
        c("starters") => {
            const index = try parser.parse(parse.index);
            const value = try parser.parse(parselu16v);
            if (index >= game.starters.len)
                return error.Error;
            for (game.starters[index]) |starter|
                starter.* = value;
        },
        c("trainers") => {
            const index = try parser.parse(parse.index);
            const field = try parser.parse(parse.anyField);
            if (index == 0 or index - 1 >= game.trainers.len)
                return error.Error;
            const trainer_index = @intCast(u32, index - 1);
            const trainer = &game.trainers[trainer_index];

            switch (m(field)) {
                c("class") => trainer.class = try parser.parse(parse.u8v),
                c("battle_type") => trainer.battle_type = try parser.parse(parse.u8v),
                c("ai") => trainer.ai = try parser.parse(parselu32v),
                c("is_healer") => trainer.healer = try parser.parse(parse.boolv),
                c("cash") => trainer.cash = try parser.parse(parse.u8v),
                c("post_battle_item") => trainer.post_battle_item = try parser.parse(parselu16v),
                c("items") => try parse.anyT(parser.str, &trainer.items, converters),
                c("party") => {
                    const pindex = try parser.parse(parse.index);
                    const pfield = try parser.parse(parse.anyField);
                    if (pindex >= trainer.party_size)
                        return error.Error;
                    const party_file = game.parties.fileData(.{ .i = trainer_index + 1 });
                    const member = trainer.partyMember(party_file, pindex) orelse return error.OutOfBound;

                    switch (m(pfield)) {
                        c("iv") => member.iv = try parser.parse(parse.u8v),
                        c("gender") => member.gender_ability.gender = try parser.parse(parse.u4v),
                        c("ability") => member.gender_ability.ability = try parser.parse(parse.u4v),
                        c("level") => member.level = try parser.parse(parse.u8v),
                        c("species") => member.species = try parser.parse(parselu16v),
                        c("form") => member.form = try parser.parse(parselu16v),
                        c("item") => {
                            const item = try parser.parse(parselu16v);
                            switch (trainer.party_type) {
                                .item => member.toParent(gen5.PartyMemberItem).item = item,
                                .both => member.toParent(gen5.PartyMemberBoth).item = item,
                                else => return error.NoField,
                            }
                        },
                        c("moves") => switch (trainer.party_type) {
                            .moves => {
                                const move_member = member.toParent(gen5.PartyMemberMoves);
                                try parse.anyT(parser.str, &move_member.moves, converters);
                            },
                            .both => {
                                const move_member = member.toParent(gen5.PartyMemberBoth);
                                try parse.anyT(parser.str, &move_member.moves, converters);
                            },
                            else => return error.NoField,
                        },
                        else => return error.Error,
                    }
                },
                else => return error.Error,
            }
        },
        c("pokemons") => {
            const index = @intCast(u32, try parser.parse(parse.index));
            if (index >= game.pokemons.fat.len)
                return error.Error;

            const pokemon = try game.pokemons.fileAs(.{ .i = index }, gen5.BasePokemon);
            const field = try parser.parse(parse.anyField);
            switch (m(field)) {
                c("stats") => try parse.anyT(parser.str, &pokemon.stats, converters),
                c("types") => try parse.anyT(parser.str, &pokemon.types, converters),
                c("items") => try parse.anyT(parser.str, &pokemon.items, converters),
                c("abilities") => try parse.anyT(parser.str, &pokemon.abilities, converters),
                c("catch_rate") => pokemon.catch_rate = try parser.parse(parse.u8v),
                c("gender_ratio") => pokemon.gender_ratio = try parser.parse(parse.u8v),
                c("egg_cycles") => pokemon.egg_cycles = try parser.parse(parse.u8v),
                c("base_friendship") => pokemon.base_friendship = try parser.parse(parse.u8v),
                c("growth_rate") => pokemon.growth_rate = try parser.parse(comptime parse.enumv(common.GrowthRate)),
                c("color") => pokemon.color.color = try parser.parse(comptime parse.enumv(common.ColorKind)),
                c("flip") => pokemon.color.flip = try parser.parse(parse.boolv),
                c("height") => pokemon.height = try parser.parse(parselu16v),
                c("weight") => pokemon.weight = try parser.parse(parselu16v),
                c("name") => try applyGen5String(game.pokemon_names, index, try parser.parse(parse.strv)),
                c("egg_groups") => {
                    const eindex = try parser.parse(parse.index);
                    const evalue = try parser.parse(comptime parse.enumv(common.EggGroup));
                    switch (eindex) {
                        0 => pokemon.egg_group1 = evalue,
                        1 => pokemon.egg_group2 = evalue,
                        else => return error.IndexOutOfBound,
                    }
                },
                c("tms"), c("hms") => {
                    const is_tms = c("tms") == m(field);
                    const tindex = try parser.parse(parse.index);
                    const value = try parser.parse(parse.boolv);
                    const len = if (is_tms) game.tms1.len + game.tms2.len else game.hms.len;
                    if (tindex >= len)
                        return error.Error;

                    const rindex = if (is_tms) tindex else tindex + game.tms1.len + game.tms2.len;
                    const learnset = &pokemon.machine_learnset;
                    learnset.* = lu128.init(bit.setTo(u128, learnset.value(), @intCast(u7, rindex), value));
                },
                c("moves") => {
                    const bytes = game.level_up_moves.fileData(.{ .i = @intCast(u32, index) });
                    const rem = bytes.len % @sizeOf(gen5.LevelUpMove);
                    const lum = mem.bytesAsSlice(gen5.LevelUpMove, bytes[0 .. bytes.len - rem]);
                    try parse.anyT(parser.str, &lum, converters);
                },
                c("evos") => {
                    if (game.evolutions.len <= index)
                        return error.Error;
                    try parse.anyT(parser.str, &game.evolutions[index].items, converters);
                },
                c("pokedex_entry") => {
                    const entry = try parser.parse(parse.u16v);
                    if (index != entry)
                        return error.TryingToChangeReadOnlyField;
                },
                else => return error.NoField,
            }
        },
        c("tms") => {
            const index = try parser.parse(parse.index);
            const value = try parser.parse(parselu16v);
            if (index >= game.tms1.len + game.tms2.len)
                return error.Error;
            if (index < game.tms1.len) {
                game.tms1[index] = value;
            } else {
                game.tms2[index - game.tms1.len] = value;
            }
        },
        c("hms") => try parse.anyT(parser.str, &game.hms, converters),
        c("items") => {
            const index = try parser.parse(parse.index);
            const prev = parser.str;
            const field = try parser.parse(parse.anyField);
            switch (m(field)) {
                c("description") => try applyGen5String(game.item_descriptions, index, try parser.parse(parse.strv)),
                c("name") => {
                    const new_name = try parser.parse(parse.strv);

                    // Here, we also applies the item name to the item_names_on_the_ground
                    // table. The way we do this is to search for the item name in the
                    // ground string, and if it exists, we replace it and apply this new
                    // string
                    if (index < game.item_names.entryCount(0) and index < game.item_names_on_the_ground.entryCount(0)) {
                        var name_buf: [1024]u8 = undefined;
                        var ground_buf: [1024]u8 = undefined;
                        const name_stream = game.item_names.getStringStream(0, index).inStream();
                        const ground_stream = game.item_names_on_the_ground.getStringStream(0, index).inStream();
                        const name_len = try name_stream.readAll(&name_buf);
                        const ground_len = try ground_stream.readAll(&ground_buf);
                        const name = name_buf[0..name_len];
                        const ground = ground_buf[0..ground_len];
                        if (mem.indexOf(u8, ground, name)) |name_index| {
                            if (name.len >= new_name.len) {
                                mem.copy(u8, ground[name_index..], new_name);
                                mem.copy(
                                    u8,
                                    ground[name_index + new_name.len ..],
                                    ground[name_index + name.len ..],
                                );
                                try applyGen5String(
                                    game.item_names_on_the_ground,
                                    index,
                                    ground[0 .. ground.len - (name.len - new_name.len)],
                                );
                            }
                        }
                    }

                    try applyGen5String(game.item_names, index, new_name);
                },
                c("price") => {
                    if (index >= game.items.len)
                        return error.Error;
                    const item = &game.items[index];
                    const parsed_price = try parser.parse(parse.u32v);
                    const new_price = try math.cast(u16, parsed_price / 10);
                    item.price = lu16.init(new_price);
                },
                else => {
                    if (index >= game.items.len)
                        return error.Error;
                    try parse.anyT(prev, &game.items[index], converters);
                },
            }
        },
        c("pokedex") => {
            const index = try parser.parse(parse.index);
            switch (m(try parser.parse(parse.anyField))) {
                c("category") => try applyGen5String(game.pokedex_category_names, index, try parser.parse(parse.strv)),
                else => return error.Error,
            }
        },
        c("moves") => {
            const prev = parser.str;
            const index = try parser.parse(parse.index);
            switch (m(try parser.parse(parse.anyField))) {
                c("description") => try applyGen5String(game.move_descriptions, index, try parser.parse(parse.strv)),
                c("name") => try applyGen5String(game.move_names, index, try parser.parse(parse.strv)),
                else => try parse.anyT(prev, &game.moves, converters),
            }
        },
        c("abilities") => {
            const index = try parser.parse(parse.index);
            switch (m(try parser.parse(parse.anyField))) {
                c("name") => try applyGen5String(game.ability_names, index, try parser.parse(parse.strv)),
                else => return error.Error,
            }
        },
        c("types") => {
            const index = try parser.parse(parse.index);
            switch (m(try parser.parse(parse.anyField))) {
                c("name") => try applyGen5String(game.type_names, index, try parser.parse(parse.strv)),
                else => return error.Error,
            }
        },
        c("map") => try parse.anyT(parser.str, &game.map_headers, converters),
        c("wild_pokemons") => {
            const H = struct {
                fn applyArea(par: *parse.MutParser, comptime name: []const u8, index: usize, wilds: *gen5.WildPokemons) !void {
                    switch (m(try par.parse(parse.anyField))) {
                        c("encounter_rate") => wilds.rates[index] = try par.parse(parse.u8v),
                        c("pokemons") => {
                            const windex = try par.parse(parse.index);
                            const area = &@field(wilds, name);
                            if (windex >= area.len)
                                return error.Error;
                            const wild = &area[windex];

                            switch (m(try par.parse(parse.anyField))) {
                                c("min_level") => wild.min_level = try par.parse(parse.u8v),
                                c("max_level") => wild.max_level = try par.parse(parse.u8v),
                                c("species") => wild.species.setSpecies(try par.parse(parse.u10v)),
                                c("form") => wild.species.setForm(try par.parse(parse.u6v)),
                                else => return error.NoField,
                            }
                        },
                        else => return error.Error,
                    }
                }
            };

            const index = @intCast(u32, try parser.parse(parse.index));

            if (index >= game.wild_pokemons.fat.len)
                return error.Error;

            const wilds = try game.wild_pokemons.fileAs(.{ .i = index }, gen5.WildPokemons);
            switch (m(try parser.parse(parse.anyField))) {
                c("grass") => try H.applyArea(&parser, "grass", 0, wilds),
                c("dark_grass") => try H.applyArea(&parser, "dark_grass", 1, wilds),
                c("rustling_grass") => try H.applyArea(&parser, "rustling_grass", 2, wilds),
                c("surf") => try H.applyArea(&parser, "surf", 3, wilds),
                c("ripple_surf") => try H.applyArea(&parser, "ripple_surf", 4, wilds),
                c("fishing") => try H.applyArea(&parser, "fishing", 5, wilds),
                c("ripple_fishing") => try H.applyArea(&parser, "ripple_fishing", 6, wilds),
                else => return error.NoField,
            }
        },
        c("static_pokemons") => {
            const index = try parser.parse(parse.index);
            if (index >= game.static_pokemons.len)
                return error.Error;

            const static_mon = game.static_pokemons[index];
            switch (m(try parser.parse(parse.anyField))) {
                c("species") => static_mon.species.* = try parser.parse(parselu16v),
                c("level") => static_mon.level.* = try parser.parse(parselu16v),
                else => return error.NoField,
            }
        },
        c("pokeball_items") => {
            const index = try parser.parse(parse.index);
            if (index >= game.pokeball_items.len)
                return error.Error;
            const given_item = game.pokeball_items[index];

            switch (m(try parser.parse(parse.anyField))) {
                c("item") => given_item.item.* = try parser.parse(parselu16v),
                c("amount") => given_item.amount.* = try parser.parse(parselu16v),
                else => return error.NoField,
            }
        },
        else => return error.NoField,
    }
}

fn applyGen5String(table: gen5.StringTable, index: usize, value: []const u8) !void {
    if (index >= table.entryCount(0))
        return error.Error;
    var stream = io.bufferedOutStream(table.getStringStream(0, index).outStream());
    try escape.writeUnEscaped(stream.outStream(), value, escape.zig_escapes);
    try stream.outStream().writeAll("\xff\xff");
    try stream.flush();
}

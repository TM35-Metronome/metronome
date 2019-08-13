const clap = @import("clap");
const common = @import("common.zig");
const fun = @import("fun");
const gba = @import("gba.zig");
const gen4 = @import("gen4-types.zig");
const nds = @import("nds.zig");
const std = @import("std");
const builtin = @import("builtin");
const format = @import("format");

const bits = fun.bits;
const debug = std.debug;
const heap = std.heap;
const io = std.io;
const fs = std.fs;
const math = std.math;
const mem = std.mem;
const fmt = std.fmt;
const os = std.os;
const rand = std.rand;
const slice = fun.generic.slice;
const path = fs.path;

const BufInStream = io.BufferedInStream(fs.File.InStream.Error);
const BufOutStream = io.BufferedOutStream(fs.File.OutStream.Error);
const Clap = clap.ComptimeClap([]const u8, params);
const Names = clap.Names;
const Param = clap.Param([]const u8);

const lu16 = fun.platform.lu16;
const lu32 = fun.platform.lu32;
const lu64 = fun.platform.lu64;
const lu128 = fun.platform.lu128;

const params = [_]Param{
    Param{
        .id = "abort execution on the first warning emitted",
        .names = Names{ .long = "abort-on-first-warning" },
    },
    Param{
        .id = "display this help text and exit",
        .names = Names{ .short = 'h', .long = "help" },
    },
    Param{
        .id = "override destination path",
        .names = Names{ .short = 'o', .long = "output" },
        .takes_value = true,
    },
    Param{
        .id = "",
        .takes_value = true,
    },
};

fn usage(stream: var) !void {
    try stream.write(
        \\Usage: tm35-gen4-apply [OPTION]... FILE
        \\Reads the tm35 format from stdin and applies it to a generation 4 Pokemon rom.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, params);
}

pub fn main() !void {
    const unbuf_stdout = &(try io.getStdOut()).outStream().stream;
    var buf_stdout = BufOutStream.init(unbuf_stdout);
    defer buf_stdout.flush() catch {};

    const stderr = &(try io.getStdErr()).outStream().stream;
    const stdin = &BufInStream.init(&(try std.io.getStdIn()).inStream().stream).stream;
    const stdout = &buf_stdout.stream;

    var arena = heap.ArenaAllocator.init(heap.direct_allocator);
    defer arena.deinit();

    const allocator = &arena.allocator;

    var arg_iter = clap.args.OsIterator.init(allocator);
    _ = arg_iter.next() catch undefined;

    var args = Clap.parse(allocator, clap.args.OsIterator, &arg_iter) catch |err| {
        usage(stderr) catch {};
        return err;
    };

    if (args.flag("--help"))
        return try usage(stdout);

    const file_name = if (args.positionals().len > 0) args.positionals()[0] else {
        debug.warn("No file provided");
        return try usage(stderr);
    };

    const abort_on_first_warning = args.flag("--abort-on-first-warning");
    const out = args.option("--output") orelse blk: {
        break :blk try fmt.allocPrint(allocator, "{}.modified", path.basename(file_name));
    };

    var rom = blk: {
        var file = fs.File.openRead(file_name) catch |err| {
            debug.warn("Couldn't open {}.\n", file_name);
            return err;
        };
        defer file.close();

        break :blk try nds.Rom.fromFile(file, allocator);
    };

    const game = try gen4.Game.fromRom(rom);

    var line: usize = 1;
    var line_buf = try std.Buffer.initSize(allocator, 0);

    while (stdin.readUntilDelimiterBuffer(&line_buf, '\n', 10000)) : (line += 1) {
        apply(rom, game, line, mem.trimRight(u8, line_buf.toSlice(), "\r\n")) catch |err| {
            debug.warn("(stdin):{}:1: warning: {}\n", line, @errorName(err));
            if (abort_on_first_warning)
                return err;
        };
        line_buf.shrink(0);
    } else |err| switch (err) {
        error.EndOfStream => {
            const str = mem.trim(u8, line_buf.toSlice(), " \t");
            if (str.len != 0)
                debug.warn("(stdin):{}:1: warning: none empty last line\n", line);
        },
        else => return err,
    }

    var out_file = fs.File.openWrite(out) catch |err| {
        debug.warn("Couldn't open {}\n", out);
        return err;
    };
    defer out_file.close();
    try rom.writeToFile(out_file);
}

fn apply(rom: nds.Rom, game: gen4.Game, line: usize, str: []const u8) !void {
    var parser = format.StrParser.init(str);

    if (parser.eatField("version")) {
        const version = try parser.eatEnumValue(common.Version);
        if (version != game.version)
            return error.VersionDontMatch;
    } else |_| if (parser.eatField("game_title")) {
        const value = try parser.eatValue();
        const null_index = mem.indexOfScalar(u8, rom.header.game_title, 0) orelse rom.header.game_title.len;
        if (!mem.eql(u8, value, rom.header.game_title[0..null_index]))
            return error.GameTitleDontMatch;
    } else |_| if (parser.eatField("gamecode")) {
        const value = try parser.eatValue();
        if (!mem.eql(u8, value, rom.header.gamecode))
            return error.GameCodeDontMatch;
    } else |_| if (parser.eatField("starters")) {
        const starter_index = try parser.eatIndexMax(game.starters.len);
        const value = lu16.init(try parser.eatUnsignedValue(u16, 10));
        game.starters[starter_index].* = value;
    } else |_| if (parser.eatField("trainers")) {
        const trainers = game.trainers.nodes.toSlice();
        const trainer_index = try parser.eatIndexMax(trainers.len);
        const trainer = try nodeAsType(gen4.Trainer, trainers[trainer_index]);

        if (parser.eatField("class")) {
            trainer.class = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("battle_type")) {
            trainer.battle_type = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("battle_type2")) {
            trainer.battle_type2 = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("items")) {
            const item_index = try parser.eatIndexMax(trainer.items.len);
            trainer.items[item_index] = lu16.init(try parser.eatUnsignedValue(u16, 10));
        } else |_| if (parser.eatField("ai")) {
            trainer.ai = lu32.init(try parser.eatUnsignedValue(u32, 10));
        } else |_| if (parser.eatField("party")) {
            const parties = game.parties.nodes.toSlice();
            const party_index = try parser.eatIndexMax(trainer.party_size);
            const party_file = try nodeAsFile(parties[trainer_index]);
            const member = getMemberBase(trainer.party_type, party_file.data, game.version, party_index) orelse return error.OutOfBound;

            if (parser.eatField("iv")) {
                member.iv = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("gender")) {
                member.gender_ability.gender = try parser.eatUnsignedValue(u4, 10);
            } else |_| if (parser.eatField("ability")) {
                member.gender_ability.ability = try parser.eatUnsignedValue(u4, 10);
            } else |_| if (parser.eatField("level")) {
                member.level = lu16.init(try parser.eatUnsignedValue(u16, 10));
            } else |_| if (parser.eatField("species")) {
                member.species.setSpecies(try parser.eatUnsignedValue(u10, 10));
            } else |_| if (parser.eatField("form")) {
                member.species.setForm(try parser.eatUnsignedValue(u6, 10));
            } else |_| if (parser.eatField("item")) {
                const item = try parser.eatUnsignedValue(u16, 10);
                switch (trainer.party_type) {
                    gen4.PartyType.Item => member.toParent(gen4.PartyMemberItem).item = lu16.init(item),
                    gen4.PartyType.Both => member.toParent(gen4.PartyMemberBoth).item = lu16.init(item),
                    else => return error.NoField,
                }
            } else |_| if (parser.eatField("moves")) {
                const mv_ptr = switch (trainer.party_type) {
                    gen4.PartyType.Moves => blk: {
                        const move_member = member.toParent(gen4.PartyMemberMoves);
                        const move_index = try parser.eatIndexMax(move_member.moves.len);
                        break :blk &move_member.moves[move_index];
                    },
                    gen4.PartyType.Both => blk: {
                        const move_member = member.toParent(gen4.PartyMemberBoth);
                        const move_index = try parser.eatIndexMax(move_member.moves.len);
                        break :blk &move_member.moves[move_index];
                    },
                    else => return error.NoField,
                };

                mv_ptr.* = lu16.init(try parser.eatUnsignedValue(u16, 10));
            } else |_| {
                return error.NoField;
            }
        } else |_| {
            return error.NoField;
        }
    } else |_| if (parser.eatField("moves")) {
        const moves = game.moves.nodes.toSlice();
        const move_index = try parser.eatIndexMax(moves.len);
        const move = try nodeAsType(gen4.Move, moves[move_index]);

        if (parser.eatField("category")) {
            move.category = try parser.eatEnumValue(common.MoveCategory);
        } else |_| if (parser.eatField("power")) {
            move.power = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("type")) {
            move.@"type" = try parser.eatEnumValue(gen4.Type);
        } else |_| if (parser.eatField("accuracy")) {
            move.accuracy = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("pp")) {
            move.pp = try parser.eatUnsignedValue(u8, 10);
        } else |_| {
            return error.NoField;
        }
    } else |_| if (parser.eatField("pokemons")) {
        const pokemons = game.pokemons.nodes.toSlice();
        const pokemon_index = try parser.eatIndexMax(pokemons.len);
        const pokemon = try nodeAsType(gen4.BasePokemon, pokemons[pokemon_index]);

        if (parser.eatField("stats")) {
            if (parser.eatField("hp")) {
                pokemon.stats.hp = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("attack")) {
                pokemon.stats.attack = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("defense")) {
                pokemon.stats.defense = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("speed")) {
                pokemon.stats.speed = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("sp_attack")) {
                pokemon.stats.sp_attack = try parser.eatUnsignedValue(u8, 10);
            } else |_| if (parser.eatField("sp_defense")) {
                pokemon.stats.sp_defense = try parser.eatUnsignedValue(u8, 10);
            } else |_| {
                return error.NoField;
            }
        } else |_| if (parser.eatField("types")) {
            const type_index = try parser.eatIndexMax(pokemon.types.len);
            pokemon.types[type_index] = try parser.eatEnumValue(gen4.Type);
        } else |_| if (parser.eatField("catch_rate")) {
            pokemon.catch_rate = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("base_exp_yield")) {
            pokemon.base_exp_yield = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("ev_yield")) {
            if (parser.eatField("hp")) {
                pokemon.ev_yield.hp = try parser.eatUnsignedValue(u2, 10);
            } else |_| if (parser.eatField("attack")) {
                pokemon.ev_yield.attack = try parser.eatUnsignedValue(u2, 10);
            } else |_| if (parser.eatField("defense")) {
                pokemon.ev_yield.defense = try parser.eatUnsignedValue(u2, 10);
            } else |_| if (parser.eatField("speed")) {
                pokemon.ev_yield.speed = try parser.eatUnsignedValue(u2, 10);
            } else |_| if (parser.eatField("sp_attack")) {
                pokemon.ev_yield.sp_attack = try parser.eatUnsignedValue(u2, 10);
            } else |_| if (parser.eatField("sp_defense")) {
                pokemon.ev_yield.sp_defense = try parser.eatUnsignedValue(u2, 10);
            } else |_| {
                return error.NoField;
            }
        } else |_| if (parser.eatField("items")) {
            const item_index = try parser.eatIndexMax(pokemon.items.len);
            pokemon.items[item_index] = lu16.init(try parser.eatUnsignedValue(u16, 10));
        } else |_| if (parser.eatField("gender_ratio")) {
            pokemon.gender_ratio = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("egg_cycles")) {
            pokemon.egg_cycles = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("base_friendship")) {
            pokemon.base_friendship = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("growth_rate")) {
            pokemon.growth_rate = try parser.eatEnumValue(common.GrowthRate);
        } else |_| if (parser.eatField("egg_groups")) {
            const egg_index = try parser.eatIndexMax(2);
            const egg_group = try parser.eatEnumValue(common.EggGroup);
            switch (egg_index) {
                0 => pokemon.egg_group1 = egg_group,
                1 => pokemon.egg_group2 = egg_group,
                else => return error.OutOfBound,
            }
        } else |_| if (parser.eatField("abilities")) {
            const ability_index = try parser.eatIndexMax(pokemon.abilities.len);
            pokemon.abilities[ability_index] = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("flee_rate")) {
            pokemon.flee_rate = try parser.eatUnsignedValue(u8, 10);
        } else |_| if (parser.eatField("color")) {
            pokemon.color = try parser.eatEnumValue(common.Color);
        } else |_| if (parser.eatField("tms")) {
            const tm_index = try parser.eatIndexMax(game.tms.len);
            const value = try parser.eatBoolValue();
            const learnset = &pokemon.machine_learnset;
            const new = switch (value) {
                true => bits.set(u128, learnset.value(), @intCast(u7, tm_index)),
                false => bits.clear(u128, learnset.value(), @intCast(u7, tm_index)),
                else => unreachable,
            };
            learnset.* = lu128.init(new);
        } else |_| if (parser.eatField("hms")) {
            const hm_index = try parser.eatIndexMax(game.hms.len);
            const value = try parser.eatBoolValue();
            const learnset = &pokemon.machine_learnset;
            const new = switch (value) {
                true => bits.set(u128, learnset.value(), @intCast(u7, hm_index + game.tms.len)),
                false => bits.clear(u128, learnset.value(), @intCast(u7, hm_index + game.tms.len)),
                else => unreachable,
            };
            learnset.* = lu128.init(new);
        } else |_| if (parser.eatField("evos")) {
            const evos_file = try nodeAsFile(game.evolutions.nodes.toSlice()[pokemon_index]);
            const evos = slice.bytesToSliceTrim(gen4.Evolution, evos_file.data);
            const evo_index = try parser.eatIndexMax(evos.len);
            const evo = &evos[evo_index];

            if (parser.eatField("method")) {
                evo.method = try parser.eatEnumValue(gen4.Evolution.Method);
            } else |_| if (parser.eatField("param")) {
                evo.param = lu16.init(try parser.eatUnsignedValue(u16, 10));
            } else |_| if (parser.eatField("target")) {
                evo.target = lu16.init(try parser.eatUnsignedValue(u16, 10));
            } else |_| {
                return error.NoField;
            }
        } else |_| {
            return error.NoField;
        }
    } else |_| if (parser.eatField("tms")) {
        const tm_index = try parser.eatIndexMax(game.tms.len);
        game.tms[tm_index] = lu16.init(try parser.eatUnsignedValue(u16, 10));
    } else |_| if (parser.eatField("hms")) {
        const hm_index = try parser.eatIndexMax(game.hms.len);
        game.hms[hm_index] = lu16.init(try parser.eatUnsignedValue(u16, 10));
    } else |_| if (parser.eatField("zones")) {
        const wild_pokemons = game.wild_pokemons.nodes.toSlice();
        const zone_index = try parser.eatIndexMax(wild_pokemons.len);
        try parser.eatField("wild");

        switch (game.version) {
            common.Version.Diamond,
            common.Version.Pearl,
            common.Version.Platinum,
            => {
                const wilds = try nodeAsType(gen4.DpptWildPokemons, wild_pokemons[zone_index]);
                if (parser.eatField("grass")) {
                    if (parser.eatField("encounter_rate")) {
                        wilds.grass_rate = lu32.init(try parser.eatUnsignedValue(u32, 10));
                        return;
                    } else |_| if (parser.eatField("pokemons")) {
                        const wild_index = try parser.eatIndexMax(wilds.grass.len);
                        const wild = &wilds.grass[wild_index];

                        if (parser.eatField("min_level")) {
                            wild.level = try parser.eatUnsignedValue(u8, 10);
                            return;
                        } else |_| if (parser.eatField("max_level")) {
                            wild.level = try parser.eatUnsignedValue(u8, 10);
                            return;
                        } else |_| if (parser.eatField("species")) {
                            wild.species.setSpecies(try parser.eatUnsignedValue(u10, 10));
                            return;
                        } else |_| if (parser.eatField("form")) {
                            wild.species.setForm(try parser.eatUnsignedValue(u6, 10));
                            return;
                        } else |_| {
                            return error.NoField;
                        }
                    } else |_| {
                        return error.NoField;
                    }
                } else |_| {}

                inline for ([_][]const u8{
                    "swarm_replacements",
                    "day_replacements",
                    "night_replacements",
                    "radar_replacements",
                    "unknown_replacements",
                    "gba_replacements",
                }) |area_name| skip: {
                    parser.eatField(area_name) catch break :skip;
                    parser.eatField("pokemons") catch break :skip;

                    const area = &@field(wilds, area_name);
                    const wild_index = try parser.eatIndexMax(area.len);
                    const wild = &area[wild_index];

                    if (parser.eatField("species")) {
                        wild.species.setSpecies(try parser.eatUnsignedValue(u10, 10));
                        return;
                    } else |_| if (parser.eatField("form")) {
                        wild.species.setForm(try parser.eatUnsignedValue(u6, 10));
                        return;
                    } else |_| {
                        return error.NoField;
                    }
                }

                inline for ([_][]const u8{
                    "surf",
                    "sea_unknown",
                    "old_rod",
                    "good_rod",
                    "super_rod",
                }) |area_name| skip: {
                    parser.eatField(area_name) catch break :skip;
                    if (parser.eatField("encounter_rate")) {
                        @field(wilds, area_name ++ "_rate") = lu32.init(try parser.eatUnsignedValue(u32, 10));
                        return;
                    } else |_| if (parser.eatField("pokemons")) {
                        const area = &@field(wilds, area_name);
                        const wild_index = try parser.eatIndexMax(area.len);
                        const wild = &area[wild_index];

                        if (parser.eatField("min_level")) {
                            wild.min_level = try parser.eatUnsignedValue(u8, 10);
                            return;
                        } else |_| if (parser.eatField("max_level")) {
                            wild.max_level = try parser.eatUnsignedValue(u8, 10);
                            return;
                        } else |_| if (parser.eatField("species")) {
                            wild.species.setSpecies(try parser.eatUnsignedValue(u10, 10));
                            return;
                        } else |_| if (parser.eatField("form")) {
                            wild.species.setForm(try parser.eatUnsignedValue(u6, 10));
                            return;
                        } else |_| {
                            return error.NoField;
                        }
                    } else |_| {}
                }

                return error.NoField;
            },

            common.Version.HeartGold,
            common.Version.SoulSilver,
            => {
                const wilds = try nodeAsType(gen4.HgssWildPokemons, wild_pokemons[zone_index]);
                inline for ([_][]const u8{
                    "grass_morning",
                    "grass_day",
                    "grass_night",
                }) |area_name| skip: {
                    parser.eatField(area_name) catch break :skip;
                    if (parser.eatField("encounter_rate")) {
                        wilds.grass_rate = try parser.eatUnsignedValue(u8, 10);
                        return;
                    } else |_| if (parser.eatField("pokemons")) {
                        const area = &@field(wilds, area_name);
                        const wild_index = try parser.eatIndexMax(area.len);
                        const wild = &area[wild_index];

                        if (parser.eatField("min_level")) {
                            wilds.grass_levels[wild_index] = try parser.eatUnsignedValue(u8, 10);
                            return;
                        } else |_| if (parser.eatField("max_level")) {
                            wilds.grass_levels[wild_index] = try parser.eatUnsignedValue(u8, 10);
                            return;
                        } else |_| if (parser.eatField("species")) {
                            wild.setSpecies(try parser.eatUnsignedValue(u10, 10));
                            return;
                        } else |_| if (parser.eatField("form")) {
                            wild.setForm(try parser.eatUnsignedValue(u6, 10));
                            return;
                        } else |_| {
                            return error.NoField;
                        }
                    } else |_| {}
                }

                inline for ([_][]const u8{
                    "surf",
                    "sea_unknown",
                    "old_rod",
                    "good_rod",
                    "super_rod",
                }) |area_name, j| skip: {
                    parser.eatField(area_name) catch break :skip;
                    if (parser.eatField("encounter_rate")) {
                        wilds.sea_rates[j] = try parser.eatUnsignedValue(u8, 10);
                        return;
                    } else |_| if (parser.eatField("pokemons")) {
                        const area = &@field(wilds, area_name);
                        const wild_index = try parser.eatIndexMax(area.len);
                        const wild = &area[wild_index];

                        if (parser.eatField("min_level")) {
                            wild.min_level = try parser.eatUnsignedValue(u8, 10);
                            return;
                        } else |_| if (parser.eatField("max_level")) {
                            wild.max_level = try parser.eatUnsignedValue(u8, 10);
                            return;
                        } else |_| if (parser.eatField("species")) {
                            wild.species.setSpecies(try parser.eatUnsignedValue(u10, 10));
                            return;
                        } else |_| if (parser.eatField("form")) {
                            wild.species.setForm(try parser.eatUnsignedValue(u6, 10));
                            return;
                        } else |_| {
                            return error.NoField;
                        }
                    } else |_| {}
                }

                // TODO: radio, swarm
                return error.NoField;
            },
            else => unreachable,
        }
    } else |err| {
        return error.NoField;
    }
}

fn nodeAsFile(node: nds.fs.Narc.Node) !*nds.fs.Narc.File {
    switch (node.kind) {
        nds.fs.Narc.Node.Kind.File => |file| return file,
        nds.fs.Narc.Node.Kind.Folder => return error.NotFile,
    }
}

fn nodeAsType(comptime T: type, node: nds.fs.Narc.Node) !*T {
    const file = try nodeAsFile(node);
    const data = slice.bytesToSliceTrim(T, file.data);
    return slice.at(data, 0) catch error.FileToSmall;
}

fn getMemberBase(party_type: gen4.PartyType, data: []u8, version: common.Version, i: usize) ?*gen4.PartyMemberBase {
    return switch (party_type) {
        gen4.PartyType.None => &(getMember(gen4.PartyMemberNone, data, version, i) orelse return null).base,
        gen4.PartyType.Item => &(getMember(gen4.PartyMemberItem, data, version, i) orelse return null).base,
        gen4.PartyType.Moves => &(getMember(gen4.PartyMemberMoves, data, version, i) orelse return null).base,
        gen4.PartyType.Both => &(getMember(gen4.PartyMemberBoth, data, version, i) orelse return null).base,
    };
}

fn getMember(comptime T: type, data: []u8, version: common.Version, i: usize) ?*T {
    switch (version) {
        common.Version.Diamond,
        common.Version.Pearl,
        => {
            const party = slice.bytesToSliceTrim(T, data);
            if (party.len <= i)
                return null;

            return &party[i];
        },

        common.Version.Platinum,
        common.Version.HeartGold,
        common.Version.SoulSilver,
        => {
            const party = slice.bytesToSliceTrim(gen4.HgSsPlatMember(T), data);
            if (party.len <= i)
                return null;

            return &party[i].member;
        },

        else => unreachable,
    }
}

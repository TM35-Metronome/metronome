const builtin = @import("builtin");
const clap = @import("clap");
const std = @import("std");
const util = @import("util");

const common = @import("common.zig");
const gen3 = @import("gen3.zig");
const rom = @import("rom.zig");

const debug = std.debug;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const fs = std.fs;
const testing = std.testing;

const errors = util.errors;

const gba = rom.gba;
const offsets = gen3.offsets;

const lu16 = rom.int.lu16;
const lu32 = rom.int.lu32;
const lu64 = rom.int.lu64;

const TypeId = builtin.TypeId;
const TypeInfo = builtin.TypeInfo;

const Clap = clap.ComptimeClap(clap.Help, &params);
const Param = clap.Param(clap.Help);

// TODO: proper versioning
const program_version = "0.0.0";

const params = [_]Param{
    clap.parseParam("-h, --help     Display this help text and exit.    ") catch unreachable,
    clap.parseParam("-v, --version  Output version information and exit.") catch unreachable,
    Param{ .takes_value = true },
};

fn usage(stream: var) !void {
    try stream.writeAll("Usage: tm35-gen3-disassemble-scripts");
    try clap.usage(stream, &params);
    try stream.writeAll(
        \\
        \\Finds all scripts in a generation 3 Pokemon game, disassembles them
        \\and writes them to stdout.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, &params);
}

pub fn main() u8 {
    var stdio = util.getStdIo();
    defer stdio.err.flush() catch {};

    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    defer arena.deinit();

    var arg_iter = clap.args.OsIterator.init(&arena.allocator) catch
        return errors.allocErr(stdio.err.outStream());
    const res = main2(
        &arena.allocator,
        util.StdIo.In.InStream,
        util.StdIo.Out.OutStream,
        stdio.streams(),
        clap.args.OsIterator,
        &arg_iter,
    );

    stdio.out.flush() catch |err| return errors.writeErr(stdio.err.outStream(), "<stdout>", err);
    return res;
}

pub fn main2(
    allocator: *mem.Allocator,
    comptime InStream: type,
    comptime OutStream: type,
    stdio: util.CustomStdIoStreams(InStream, OutStream),
    comptime ArgIterator: type,
    arg_iter: *ArgIterator,
) u8 {
    var args = Clap.parse(allocator, ArgIterator, arg_iter) catch |err| {
        stdio.err.print("{}\n", .{err}) catch {};
        usage(stdio.err) catch {};
        return 1;
    };

    if (args.flag("--help")) {
        usage(stdio.out) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
        return 0;
    }

    if (args.flag("--version")) {
        stdio.out.print("{}\n", .{program_version}) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
        return 0;
    }

    for (args.positionals()) |file_name, i| {
        const data = fs.cwd().readFileAlloc(allocator, file_name, math.maxInt(usize)) catch |err| return errors.readErr(stdio.err, file_name, err);
        defer allocator.free(data);
        if (data.len < @sizeOf(gba.Header))
            return errors.err(stdio.err, "'{}' is not a gen3 Pokémon game: {}\n", .{ file_name, error.FileToSmall });

        const header = mem.bytesAsSlice(gba.Header, data[0..@sizeOf(gba.Header)])[0];
        const version = getVersion(&header.gamecode) catch |err| return errors.err(stdio.err, "'{}' is not a gen3 Pokémon game: {}\n", .{ file_name, err });
        const info_err = getOffsets(data, version, header.gamecode, header.game_title, header.software_version);
        const info = info_err catch |err| return errors.err(stdio.err, "Failed to get offsets from '{}': {}\n", .{ file_name, err });
        outputInfo(stdio.out, i, info) catch |err| return errors.writeErr(stdio.err, "<stdout>", err);
    }

    return 0;
}

fn outputInfo(stream: var, i: usize, info: offsets.Info) !void {
    try stream.print(".game[{}].game_title={}\n", .{ i, info.game_title });
    try stream.print(".game[{}].gamecode={}\n", .{ i, info.gamecode });
    try stream.print(".game[{}].version={}\n", .{ i, @tagName(info.version) });
    try stream.print(".game[{}].software_version={}\n", .{ i, info.software_version });
    try stream.print(".game[{}].trainers.start={}\n", .{ i, info.trainers.start });
    try stream.print(".game[{}].trainers.len={}\n", .{ i, info.trainers.len });
    try stream.print(".game[{}].moves.start={}\n", .{ i, info.moves.start });
    try stream.print(".game[{}].moves.len={}\n", .{ i, info.moves.len });
    try stream.print(".game[{}].machine_learnsets.start={}\n", .{ i, info.machine_learnsets.start });
    try stream.print(".game[{}].machine_learnsets.len={}\n", .{ i, info.machine_learnsets.len });
    try stream.print(".game[{}].pokemons.start={}\n", .{ i, info.pokemons.start });
    try stream.print(".game[{}].pokemons.len={}\n", .{ i, info.pokemons.len });
    try stream.print(".game[{}].evolutions.start={}\n", .{ i, info.evolutions.start });
    try stream.print(".game[{}].evolutions.len={}\n", .{ i, info.evolutions.len });
    try stream.print(".game[{}].level_up_learnset_pointers.start={}\n", .{ i, info.level_up_learnset_pointers.start });
    try stream.print(".game[{}].level_up_learnset_pointers.len={}\n", .{ i, info.level_up_learnset_pointers.len });
    try stream.print(".game[{}].hms.start={}\n", .{ i, info.hms.start });
    try stream.print(".game[{}].hms.len={}\n", .{ i, info.hms.len });
    try stream.print(".game[{}].tms.start={}\n", .{ i, info.tms.start });
    try stream.print(".game[{}].tms.len={}\n", .{ i, info.tms.len });
    try stream.print(".game[{}].items.start={}\n", .{ i, info.items.start });
    try stream.print(".game[{}].items.len={}\n", .{ i, info.items.len });
    try stream.print(".game[{}].wild_pokemon_headers.start={}\n", .{ i, info.wild_pokemon_headers.start });
    try stream.print(".game[{}].wild_pokemon_headers.len={}\n", .{ i, info.wild_pokemon_headers.len });
    try stream.print(".game[{}].map_headers.start={}\n", .{ i, info.map_headers.start });
    try stream.print(".game[{}].map_headers.len={}\n", .{ i, info.map_headers.len });
    try stream.print(".game[{}].pokemon_names.start={}\n", .{ i, info.pokemon_names.start });
    try stream.print(".game[{}].pokemon_names.len={}\n", .{ i, info.pokemon_names.len });
    try stream.print(".game[{}].ability_names.start={}\n", .{ i, info.ability_names.start });
    try stream.print(".game[{}].ability_names.len={}\n", .{ i, info.ability_names.len });
    try stream.print(".game[{}].move_names.start={}\n", .{ i, info.move_names.start });
    try stream.print(".game[{}].move_names.len={}\n", .{ i, info.move_names.len });
    try stream.print(".game[{}].type_names.start={}\n", .{ i, info.type_names.start });
    try stream.print(".game[{}].type_names.len={}\n", .{ i, info.type_names.len });
}

fn getVersion(gamecode: []const u8) !common.Version {
    if (mem.startsWith(u8, gamecode, "BPE"))
        return .emerald;
    if (mem.startsWith(u8, gamecode, "BPR"))
        return .fire_red;
    if (mem.startsWith(u8, gamecode, "BPG"))
        return .leaf_green;
    if (mem.startsWith(u8, gamecode, "AXV"))
        return .ruby;
    if (mem.startsWith(u8, gamecode, "AXP"))
        return .sapphire;

    return error.UnknownPokemonVersion;
}

fn getOffsets(
    data: []const u8,
    version: common.Version,
    gamecode: [4]u8,
    game_title: [12]u8,
    software_version: u8,
) !gen3.offsets.Info {
    // TODO: A way to find starter pokemons
    const Trainers = Searcher(gen3.Trainer, &[_][]const []const u8{
        &[_][]const u8{"party"},
        &[_][]const u8{"name"},
    });
    const Moves = Searcher(gen3.Move, &[_][]const []const u8{});
    const Machines = Searcher(lu64, &[_][]const []const u8{});
    const Pokemons = Searcher(gen3.BasePokemon, &[_][]const []const u8{
        &[_][]const u8{"padding"},
        &[_][]const u8{"egg_group1_pad"},
        &[_][]const u8{"egg_group2_pad"},
    });
    const Evos = Searcher([5]gen3.Evolution, &[_][]const []const u8{&[_][]const u8{"padding"}});
    const LvlUpMoves = Searcher(u8, &[_][]const []const u8{});
    const HmTms = Searcher(lu16, &[_][]const []const u8{});
    const Items = Searcher(gen3.Item, &[_][]const []const u8{
        &[_][]const u8{"name"},
        &[_][]const u8{"description"},
        &[_][]const u8{"field_use_func"},
        &[_][]const u8{"battle_use_func"},
    });
    const WildPokemonHeaders = Searcher(gen3.WildPokemonHeader, &[_][]const []const u8{
        &[_][]const u8{"pad"},
        &[_][]const u8{"land"},
        &[_][]const u8{"surf"},
        &[_][]const u8{"rock_smash"},
        &[_][]const u8{"fishing"},
    });
    const MapHeaders = Searcher(gen3.MapHeader, &[_][]const []const u8{
        &[_][]const u8{"map_data"},
        &[_][]const u8{"map_events"},
        &[_][]const u8{"map_scripts"},
        &[_][]const u8{"map_connections"},
        &[_][]const u8{"pad"},
    });
    const LvlUpRef = gen3.Ptr([*]gen3.LevelUpMove);
    const LvlUpRefs = Searcher(LvlUpRef, &[_][]const []const u8{});
    const PokemonNames = Searcher([11]u8, &[_][]const []const u8{});
    const AbilityNames = Searcher([13]u8, &[_][]const []const u8{});
    const MoveNames = Searcher([13]u8, &[_][]const []const u8{});
    const TypeNames = Searcher([7]u8, &[_][]const []const u8{});
    const Strings = Searcher(u8, &[_][]const []const u8{});

    const trainers = switch (version) {
        .emerald => try Trainers.find4(data, &em_first_trainers, &em_last_trainers),
        .ruby,
        .sapphire,
        => try Trainers.find4(data, &rs_first_trainers, &rs_last_trainers),
        .fire_red,
        .leaf_green,
        => try Trainers.find4(data, &frls_first_trainers, &frls_last_trainers),
        else => unreachable,
    };
    const moves = try Moves.find4(data, &first_moves, &last_moves);
    const machine_learnset = try Machines.find4(data, &first_machine_learnsets, &last_machine_learnsets);
    const pokemons = try Pokemons.find4(data, &first_pokemons, &last_pokemons);
    const evolution_table = try Evos.find4(data, &first_evolutions, &last_evolutions);

    const level_up_learnset_pointers = blk: {
        var first_pointers: [first_levelup_learnsets.len]LvlUpRef = undefined;
        for (first_levelup_learnsets) |learnset, i| {
            const p = try LvlUpMoves.find2(data, learnset);
            first_pointers[i] = try LvlUpRef.init(p.ptr, data);
        }

        var last_pointers: [last_levelup_learnsets.len]LvlUpRef = undefined;
        for (last_levelup_learnsets) |learnset, i| {
            const p = try LvlUpMoves.find2(data, learnset);
            last_pointers[i] = try LvlUpRef.init(p.ptr, data);
        }

        break :blk try LvlUpRefs.find4(data, &first_pointers, &last_pointers);
    };

    const pokemon_names = try PokemonNames.find4(data, &first_pokemon_names, &last_pokemon_names);
    const ability_names = try AbilityNames.find4(data, &first_ability_names, &last_ability_names);
    const move_names = switch (version) {
        .emerald => try MoveNames.find4(data, &e_first_move_names, &last_move_names),
        .ruby,
        .sapphire,
        .fire_red,
        .leaf_green,
        => try MoveNames.find4(data, &rsfrlg_first_move_names, &last_move_names),
        else => unreachable,
    };
    const type_names_slice = try TypeNames.find2(data, &type_names);
    const hms_slice = try HmTms.find2(data, &hms);

    // TODO: Pokemon Emerald have 2 tm tables. I'll figure out some hack for that
    //       if it turns out that both tables are actually used. For now, I'll
    //       assume that the first table is the only one used.
    const tms_slice = try HmTms.find2(data, &tms);

    const items = switch (version) {
        .emerald => try Items.find4(data, &em_first_items, &em_last_items),
        .ruby,
        .sapphire,
        => try Items.find4(data, &rs_first_items, &rs_last_items),
        .fire_red,
        .leaf_green,
        => try Items.find4(data, &frlg_first_items, &frlg_last_items),
        else => unreachable,
    };

    const wild_pokemon_headers = switch (version) {
        .emerald => try WildPokemonHeaders.find4(data, &em_first_wild_mon_headers, &em_last_wild_mon_headers),
        .ruby,
        .sapphire,
        => try WildPokemonHeaders.find4(data, &rs_first_wild_mon_headers, &rs_last_wild_mon_headers),
        .fire_red,
        .leaf_green,
        => try WildPokemonHeaders.find4(data, &frlg_first_wild_mon_headers, &frlg_last_wild_mon_headers),
        else => unreachable,
    };

    const map_headers = switch (version) {
        .emerald => try MapHeaders.find4(data, &em_first_map_headers, &em_last_map_headers),
        .ruby,
        .sapphire,
        => try MapHeaders.find4(data, &rs_first_map_headers, &rs_last_map_headers),
        .fire_red,
        .leaf_green,
        => try MapHeaders.find4(data, &frlg_first_map_headers, &frlg_last_map_headers),
        else => unreachable,
    };

    return offsets.Info{
        .game_title = game_title,
        .gamecode = gamecode,
        .version = version,
        .software_version = software_version,

        .starters = undefined,
        .starters_repeat = undefined,
        .trainers = offsets.TrainerSection.init(data, trainers),
        .moves = offsets.MoveSection.init(data, moves),
        .machine_learnsets = offsets.MachineLearnsetSection.init(data, machine_learnset),
        .pokemons = offsets.BaseStatsSection.init(data, pokemons),
        .evolutions = offsets.EvolutionSection.init(data, evolution_table),
        .level_up_learnset_pointers = offsets.LevelUpLearnsetPointerSection.init(data, level_up_learnset_pointers),
        .hms = offsets.HmSection.init(data, hms_slice),
        .tms = offsets.TmSection.init(data, tms_slice),
        .items = offsets.ItemSection.init(data, items),
        .wild_pokemon_headers = offsets.WildPokemonHeaderSection.init(data, wild_pokemon_headers),
        .map_headers = offsets.MapHeaderSection.init(data, map_headers),
        .pokemon_names = offsets.PokemonNameSection.init(data, pokemon_names),
        .ability_names = offsets.AbilityNameSection.init(data, ability_names),
        .move_names = offsets.MoveNameSection.init(data, move_names),
        .type_names = offsets.TypeNameSection.init(data, type_names_slice),
    };
}

// A type for searching binary data for instances of ::T. It also allows ignoring of certain
// fields and nested fields.
pub fn Searcher(comptime T: type, comptime ignored_fields: []const []const []const u8) type {
    return struct {
        pub fn find1(data: []const u8, item: T) !*const T {
            const slice = try find2(data, &[_]T{item});
            return &slice[0];
        }

        pub fn find2(data: []const u8, items: []const T) ![]const T {
            return find4(data, items, &[_]T{});
        }

        pub fn find3(data: []const u8, start: T, end: T) ![]const T {
            return find4(data, &[_]T{start}, &[_]T{end});
        }

        pub fn find4(data: []const u8, start: []const T, end: []const T) ![]const T {
            const found_start = try findSliceHelper(data, 0, 1, start);
            const start_offset = @ptrToInt(found_start.ptr);
            const next_offset = (start_offset - @ptrToInt(data.ptr)) + start.len * @sizeOf(T);

            const found_end = try findSliceHelper(data, next_offset, @sizeOf(T), end);
            const end_offset = @ptrToInt(found_end.ptr) + found_end.len * @sizeOf(T);
            const len = @divExact(end_offset - start_offset, @sizeOf(T));

            return found_start.ptr[0..len];
        }

        fn findSliceHelper(data: []const u8, offset: usize, skip: usize, items: []const T) ![]const T {
            const bytes = items.len * @sizeOf(T);
            if (data.len < bytes)
                return error.DataNotFound;

            var i: usize = offset;
            const end = data.len - bytes;
            next: while (i <= end) : (i += skip) {
                const data_slice = data[i .. i + bytes];
                const data_items = mem.bytesAsSlice(T, data_slice);
                for (items) |item_a, j| {
                    const item_b = data_items[j];
                    if (!matches(T, ignored_fields, item_a, item_b))
                        continue :next;
                }

                // HACK: mem.bytesAsSlice does not return a pointer to the original data, if
                //       the length of the data passed in is 0. I need the pointer to point into
                //       `data_slice` so I bypass `data_items` here. I feel like this is a design
                //       mistake by the Zig `std`.
                return @ptrCast([*]const T, data_slice.ptr)[0..data_items.len];
            }

            return error.DataNotFound;
        }
    };
}

fn matches(comptime T: type, comptime ignored_fields: []const []const []const u8, a: T, b: T) bool {
    const info = @typeInfo(T);
    switch (info) {
        .Pointer => |ptr| switch (ptr.size) {
            .Slice => {
                return a.ptr == b.ptr and a.len == b.len;
            },
            else => return a == b,
        },
        .Array => {
            if (a.len != b.len)
                return false;

            for (a) |_, i| {
                if (!matches(T.Child, ignored_fields, a[i], b[i]))
                    return false;
            }

            return true;
        },
        .Optional => |optional| {
            const a_value = a orelse {
                return if (b) |_| false else true;
            };
            const b_value = b orelse return false;

            return matches(optional.child, ignored_fields, a_value, b_value);
        },
        .ErrorUnion => |err_union| {
            const a_value = a catch |a_err| {
                if (b) |_| {
                    return false;
                } else |b_err| {
                    return matches(err_union.error_set, ignored_fields, a_err, b_err);
                }
            };
            const b_value = b catch return false;

            return matches(err_union.payload, ignored_fields, a_value, b_value);
        },
        .Struct => |struct_info| {
            const next_ignored = comptime blk: {
                var res: []const []const []const u8 = &[_][]const []const u8{};
                for (ignored_fields) |fields| {
                    if (fields.len > 1)
                        res = res ++ fields[1..];
                }

                break :blk res;
            };

            ignore: inline for (struct_info.fields) |field| {
                inline for (ignored_fields) |fields| {
                    if (comptime fields.len == 1 and mem.eql(u8, fields[0], field.name))
                        continue :ignore;
                }
                if (!matches(field.field_type, next_ignored, @field(a, field.name), @field(b, field.name)))
                    return false;
            }

            return true;
        },
        .Union => |union_info| {
            const first_field = union_info.fields[0];
            comptime {
                // Only allow comparing unions that have all fields of the same
                // size.
                const size = @sizeOf(first_field.field_type);
                for (union_info.fields) |f|
                    debug.assert(@sizeOf(f.field_type) == size);
            }

            return matches(first_field.field_type, ignored_fields, @field(a, first_field.name), @field(b, first_field.name));
        },
        else => return a == b,
    }
}

test "searcher.Searcher.find" {
    const S = packed struct {
        a: u16,
        b: u32,
    };
    const s_array = &[_]S{
        S{ .a = 0, .b = 1 },
        S{ .a = 2, .b = 3 },
    };
    const data = mem.sliceAsBytes(s_array[0..]);
    const S1 = Searcher(S, &[_][]const []const u8{
        &[_][]const u8{"a"},
    });
    const S2 = Searcher(S, &[_][]const []const u8{
        &[_][]const u8{"b"},
    });

    const search_for = S{ .a = 0, .b = 3 };
    testing.expectEqual(try S1.find1(data, search_for), &s_array[1]);
    testing.expectEqual(try S2.find1(data, search_for), &s_array[0]);
}

test "searcher.Searcher.find2" {
    const S = packed struct {
        a: u16,
        b: u32,
    };
    const s_array = &[_]S{
        S{ .a = 4, .b = 1 },
        S{ .a = 0, .b = 3 },
        S{ .a = 4, .b = 1 },
    };
    const data = mem.sliceAsBytes(s_array[0..]);
    const S1 = Searcher(S, &[_][]const []const u8{
        &[_][]const u8{"a"},
    });
    const S2 = Searcher(S, &[_][]const []const u8{
        &[_][]const u8{"b"},
    });

    const search_for = &[_]S{
        S{ .a = 4, .b = 3 },
        S{ .a = 0, .b = 1 },
    };
    testing.expectEqualSlices(
        u8,
        mem.sliceAsBytes(s_array[1..3]),
        mem.sliceAsBytes(try S1.find2(data, search_for)),
    );
    testing.expectEqualSlices(
        u8,
        mem.sliceAsBytes(s_array[0..2]),
        mem.sliceAsBytes(try S2.find2(data, search_for)),
    );
}

test "searcher.Searcher.find3" {
    const S = packed struct {
        a: u16,
        b: u32,
    };
    const s_array = &[_]S{
        S{ .a = 4, .b = 1 },
        S{ .a = 0, .b = 3 },
        S{ .a = 4, .b = 1 },
        S{ .a = 0, .b = 3 },
    };
    const data = mem.sliceAsBytes(s_array[0..]);
    const S1 = Searcher(S, &[_][]const []const u8{
        &[_][]const u8{"a"},
    });
    const S2 = Searcher(S, &[_][]const []const u8{
        &[_][]const u8{"b"},
    });

    const a = S{ .a = 4, .b = 3 };
    const b = S{ .a = 4, .b = 3 };
    testing.expectEqualSlices(
        u8,
        mem.sliceAsBytes(s_array[1..4]),
        mem.sliceAsBytes(try S1.find3(data, a, b)),
    );
    testing.expectEqualSlices(
        u8,
        mem.sliceAsBytes(s_array[0..3]),
        mem.sliceAsBytes(try S2.find3(data, a, b)),
    );
}

test "searcher.Searcher.find4" {
    const S = packed struct {
        a: u16,
        b: u32,
    };
    const s_array = &[_]S{
        S{ .a = 4, .b = 1 },
        S{ .a = 0, .b = 3 },
        S{ .a = 4, .b = 1 },
        S{ .a = 0, .b = 3 },
        S{ .a = 4, .b = 1 },
        S{ .a = 0, .b = 3 },
    };
    const data = mem.sliceAsBytes(s_array[0..]);
    const S1 = Searcher(S, &[_][]const []const u8{
        &[_][]const u8{"a"},
    });
    const S2 = Searcher(S, &[_][]const []const u8{
        &[_][]const u8{"b"},
    });

    const a = &[_]S{
        S{ .a = 4, .b = 3 },
        S{ .a = 0, .b = 1 },
    };
    const b = &[_]S{
        S{ .a = 0, .b = 1 },
        S{ .a = 4, .b = 3 },
    };
    testing.expectEqualSlices(
        u8,
        mem.sliceAsBytes(s_array[1..6]),
        mem.sliceAsBytes(try S1.find4(data, a, b)),
    );
    testing.expectEqualSlices(
        u8,
        mem.sliceAsBytes(s_array[0..5]),
        mem.sliceAsBytes(try S2.find4(data, a, b)),
    );
}

const em_first_trainers = [_]gen3.Trainer{
    gen3.Trainer{
        .party_type = .none,
        .class = 0,
        .encounter_music = 0,
        .trainer_picture = 0,
        .name = undefined,
        .items = [_]lu16{ lu16.init(0), lu16.init(0), lu16.init(0), lu16.init(0) },
        .is_double = lu32.init(0),
        .ai = lu32.init(0),
        .party = undefined,
    },
    gen3.Trainer{
        .party_type = .none,
        .class = 0x02,
        .encounter_music = 0x0b,
        .trainer_picture = 0,
        .name = undefined,
        .items = [_]lu16{ lu16.init(0), lu16.init(0), lu16.init(0), lu16.init(0) },
        .is_double = lu32.init(0),
        .ai = lu32.init(7),
        .party = undefined,
    },
};

const em_last_trainers = [_]gen3.Trainer{gen3.Trainer{
    .party_type = .none,
    .class = 0x41,
    .encounter_music = 0x80,
    .trainer_picture = 0x5c,
    .name = undefined,
    .items = [_]lu16{ lu16.init(0), lu16.init(0), lu16.init(0), lu16.init(0) },
    .is_double = lu32.init(0),
    .ai = lu32.init(0),
    .party = undefined,
}};

const rs_first_trainers = [_]gen3.Trainer{
    gen3.Trainer{
        .party_type = .none,
        .class = 0,
        .encounter_music = 0,
        .trainer_picture = 0,
        .name = undefined,
        .items = [_]lu16{ lu16.init(0), lu16.init(0), lu16.init(0), lu16.init(0) },
        .is_double = lu32.init(0),
        .ai = lu32.init(0),
        .party = undefined,
    },
    gen3.Trainer{
        .party_type = .none,
        .class = 0x02,
        .encounter_music = 0x06,
        .trainer_picture = 0x46,
        .name = undefined,
        .items = [_]lu16{ lu16.init(0x16), lu16.init(0x16), lu16.init(0), lu16.init(0) },
        .is_double = lu32.init(0),
        .ai = lu32.init(7),
        .party = undefined,
    },
};

const rs_last_trainers = [_]gen3.Trainer{gen3.Trainer{
    .party_type = .none,
    .class = 0x21,
    .encounter_music = 0x0B,
    .trainer_picture = 0x06,
    .name = undefined,
    .items = [_]lu16{ lu16.init(0), lu16.init(0), lu16.init(0), lu16.init(0) },
    .is_double = lu32.init(0),
    .ai = lu32.init(1),
    .party = undefined,
}};

const frls_first_trainers = [_]gen3.Trainer{
    gen3.Trainer{
        .party_type = .none,
        .class = 0,
        .encounter_music = 0,
        .trainer_picture = 0,
        .name = undefined,
        .items = [_]lu16{
            lu16.init(0),
            lu16.init(0),
            lu16.init(0),
            lu16.init(0),
        },
        .is_double = lu32.init(0),
        .ai = lu32.init(0),
        .party = undefined,
    },
    gen3.Trainer{
        .party_type = .none,
        .class = 2,
        .encounter_music = 6,
        .trainer_picture = 0,
        .name = undefined,
        .items = [_]lu16{
            lu16.init(0),
            lu16.init(0),
            lu16.init(0),
            lu16.init(0),
        },
        .is_double = lu32.init(0),
        .ai = lu32.init(1),
        .party = undefined,
    },
};

const frls_last_trainers = [_]gen3.Trainer{
    gen3.Trainer{
        .party_type = .both,
        .class = 90,
        .encounter_music = 0,
        .trainer_picture = 125,
        .name = undefined,
        .items = [_]lu16{
            lu16.init(19),
            lu16.init(19),
            lu16.init(19),
            lu16.init(19),
        },
        .is_double = lu32.init(0),
        .ai = lu32.init(7),
        .party = undefined,
    },
    gen3.Trainer{
        .party_type = .none,
        .class = 0x47,
        .encounter_music = 0,
        .trainer_picture = 0x60,
        .name = undefined,
        .items = [_]lu16{
            lu16.init(0),
            lu16.init(0),
            lu16.init(0),
            lu16.init(0),
        },
        .is_double = lu32.init(0),
        .ai = lu32.init(1),
        .party = undefined,
    },
};

const first_moves = [_]gen3.Move{
    // Dummy
    gen3.Move{
        .effect = 0,
        .power = 0,
        .@"type" = 0,
        .accuracy = 0,
        .pp = 0,
        .side_effect_chance = 0,
        .target = 0,
        .priority = 0,
        .flags = lu32.init(0),
    },
    // Pound
    gen3.Move{
        .effect = 0,
        .power = 40,
        .@"type" = 0,
        .accuracy = 100,
        .pp = 35,
        .side_effect_chance = 0,
        .target = 0,
        .priority = 0,
        .flags = lu32.init(0x33),
    },
};

const last_moves = [_]gen3.Move{
// Psycho Boost
gen3.Move{
    .effect = 204,
    .power = 140,
    .@"type" = 14,
    .accuracy = 90,
    .pp = 5,
    .side_effect_chance = 100,
    .target = 0,
    .priority = 0,
    .flags = lu32.init(0x32),
}};

const first_machine_learnsets = [_]lu64{
    lu64.init(0x0000000000000000), // Dummy Pokemon
    lu64.init(0x00e41e0884350720), // Bulbasaur
    lu64.init(0x00e41e0884350720), // Ivysaur
    lu64.init(0x00e41e0886354730), // Venusaur
};

const last_machine_learnsets = [_]lu64{
    lu64.init(0x035c5e93b7bbd63e), // Latios
    lu64.init(0x00408e93b59bc62c), // Jirachi
    lu64.init(0x00e58fc3f5bbde2d), // Deoxys
    lu64.init(0x00419f03b41b8e28), // Chimecho
};

const first_pokemons = [_]gen3.BasePokemon{
    // Dummy
    gen3.BasePokemon{
        .stats = common.Stats{
            .hp = 0,
            .attack = 0,
            .defense = 0,
            .speed = 0,
            .sp_attack = 0,
            .sp_defense = 0,
        },

        .types = [_]u8{ 0, 0 },

        .catch_rate = 0,
        .base_exp_yield = 0,

        .ev_yield = common.EvYield{
            .hp = 0,
            .attack = 0,
            .defense = 0,
            .speed = 0,
            .sp_attack = 0,
            .sp_defense = 0,
            .padding = 0,
        },

        .items = [_]lu16{ lu16.init(0), lu16.init(0) },

        .gender_ratio = 0,
        .egg_cycles = 0,
        .base_friendship = 0,

        .growth_rate = .medium_fast,

        .egg_group1 = .invalid,
        .egg_group2 = .invalid,

        .abilities = [_]u8{ 0, 0 },
        .safari_zone_rate = 0,

        .color = common.Color{
            .color = .red,
            .flip = false,
        },

        .padding = undefined,
    },
    // Bulbasaur
    gen3.BasePokemon{
        .stats = common.Stats{
            .hp = 45,
            .attack = 49,
            .defense = 49,
            .speed = 45,
            .sp_attack = 65,
            .sp_defense = 65,
        },

        .types = [_]u8{ 12, 3 },

        .catch_rate = 45,
        .base_exp_yield = 64,

        .ev_yield = common.EvYield{
            .hp = 0,
            .attack = 0,
            .defense = 0,
            .speed = 0,
            .sp_attack = 1,
            .sp_defense = 0,
            .padding = 0,
        },

        .items = [_]lu16{ lu16.init(0), lu16.init(0) },

        .gender_ratio = comptime percentFemale(12.5),
        .egg_cycles = 20,
        .base_friendship = 70,

        .growth_rate = .medium_slow,

        .egg_group1 = .monster,
        .egg_group2 = .grass,

        .abilities = [_]u8{ 65, 0 },
        .safari_zone_rate = 0,

        .color = common.Color{
            .color = .green,
            .flip = false,
        },

        .padding = undefined,
    },
};

const last_pokemons = [_]gen3.BasePokemon{
// Chimecho
gen3.BasePokemon{
    .stats = common.Stats{
        .hp = 65,
        .attack = 50,
        .defense = 70,
        .speed = 65,
        .sp_attack = 95,
        .sp_defense = 80,
    },

    .types = [_]u8{ 14, 14 },

    .catch_rate = 45,
    .base_exp_yield = 147,

    .ev_yield = common.EvYield{
        .hp = 0,
        .attack = 0,
        .defense = 0,
        .speed = 0,
        .sp_attack = 1,
        .sp_defense = 1,
        .padding = 0,
    },

    .items = [_]lu16{ lu16.init(0), lu16.init(0) },

    .gender_ratio = comptime percentFemale(50),
    .egg_cycles = 25,
    .base_friendship = 70,

    .growth_rate = .fast,

    .egg_group1 = .amorphous,
    .egg_group2 = .amorphous,

    .abilities = [_]u8{ 26, 0 },
    .safari_zone_rate = 0,

    .color = common.Color{
        .color = .blue,
        .flip = false,
    },

    .padding = undefined,
}};

fn percentFemale(percent: f64) u8 {
    return @floatToInt(u8, math.min(@as(f64, 254), (percent * 255) / 100));
}

const unused_evo = gen3.Evolution{
    .method = .unused,
    .padding1 = undefined,
    .param = lu16.init(0),
    .target = lu16.init(0),
    .padding2 = undefined,
};
const unused_evo5 = [_]gen3.Evolution{unused_evo} ** 5;

const first_evolutions = [_][5]gen3.Evolution{
    // Dummy
    unused_evo5,

    // Bulbasaur
    [_]gen3.Evolution{
        gen3.Evolution{
            .method = .level_up,
            .padding1 = undefined,
            .param = lu16.init(16),
            .target = lu16.init(2),
            .padding2 = undefined,
        },
        unused_evo,
        unused_evo,
        unused_evo,
        unused_evo,
    },

    // Ivysaur
    [_]gen3.Evolution{
        gen3.Evolution{
            .method = .level_up,
            .padding1 = undefined,
            .param = lu16.init(32),
            .target = lu16.init(3),
            .padding2 = undefined,
        },
        unused_evo,
        unused_evo,
        unused_evo,
        unused_evo,
    },
};

const last_evolutions = [_][5]gen3.Evolution{
    // Beldum
    [_]gen3.Evolution{
        gen3.Evolution{
            .padding1 = undefined,
            .method = .level_up,
            .param = lu16.init(20),
            .target = lu16.init(399),
            .padding2 = undefined,
        },
        unused_evo,
        unused_evo,
        unused_evo,
        unused_evo,
    },

    // Metang
    [_]gen3.Evolution{
        gen3.Evolution{
            .method = .level_up,
            .padding1 = undefined,
            .param = lu16.init(45),
            .target = lu16.init(400),
            .padding2 = undefined,
        },
        unused_evo,
        unused_evo,
        unused_evo,
        unused_evo,
    },

    // Metagross, Regirock, Regice, Registeel, Kyogre, Groudon, Rayquaza
    // Latias, Latios, Jirachi, Deoxys, Chimecho
    unused_evo5,
    unused_evo5,
    unused_evo5,
    unused_evo5,
    unused_evo5,
    unused_evo5,
    unused_evo5,
    unused_evo5,
    unused_evo5,
    unused_evo5,
    unused_evo5,
    unused_evo5,
};

const first_levelup_learnsets = [_][]const u8{
    // Dummy mon have same moves as Bulbasaur
    &[_]u8{
        0x21, 0x02, 0x2D, 0x08, 0x49, 0x0E, 0x16, 0x14, 0x4D, 0x1E, 0x4F, 0x1E,
        0x4B, 0x28, 0xE6, 0x32, 0x4A, 0x40, 0xEB, 0x4E, 0x4C, 0x5C, 0xFF, 0xFF,
    },
    // Bulbasaur
    &[_]u8{
        0x21, 0x02, 0x2D, 0x08, 0x49, 0x0E, 0x16, 0x14, 0x4D, 0x1E, 0x4F, 0x1E,
        0x4B, 0x28, 0xE6, 0x32, 0x4A, 0x40, 0xEB, 0x4E, 0x4C, 0x5C, 0xFF, 0xFF,
    },
    // Ivysaur
    &[_]u8{
        0x21, 0x02, 0x2D, 0x02, 0x49, 0x02, 0x2D, 0x08, 0x49, 0x0E, 0x16, 0x14,
        0x4D, 0x1E, 0x4F, 0x1E, 0x4B, 0x2C, 0xE6, 0x3A, 0x4A, 0x4C, 0xEB, 0x5E,
        0x4C, 0x70, 0xFF, 0xFF,
    },
    // Venusaur
    &[_]u8{
        0x21, 0x02, 0x2D, 0x02, 0x49, 0x02, 0x16, 0x02, 0x2D, 0x08, 0x49, 0x0E,
        0x16, 0x14, 0x4D, 0x1E, 0x4F, 0x1E, 0x4B, 0x2C, 0xE6, 0x3A, 0x4A, 0x52,
        0xEB, 0x6A, 0x4C, 0x82, 0xFF, 0xFF,
    },
};

const last_levelup_learnsets = [_][]const u8{
// TODO: Figure out if only having Chimechos level up learnset is enough.
// Chimecho
&[_]u8{
    0x23, 0x02, 0x2D, 0x0C, 0x36, 0x13, 0x5D, 0x1C, 0x24, 0x22, 0xFD, 0x2C, 0x19,
    0x33, 0x95, 0x3C, 0x26, 0x42, 0xD7, 0x4C, 0xDB, 0x52, 0x5E, 0x5C, 0xFF, 0xFF,
}};

const hms = [_]lu16{
    lu16.init(0x000f),
    lu16.init(0x0013),
    lu16.init(0x0039),
    lu16.init(0x0046),
    lu16.init(0x0094),
    lu16.init(0x00f9),
    lu16.init(0x007f),
    lu16.init(0x0123),
};

const tms = [_]lu16{
    lu16.init(0x0108),
    lu16.init(0x0151),
    lu16.init(0x0160),
    lu16.init(0x015b),
    lu16.init(0x002e),
    lu16.init(0x005c),
    lu16.init(0x0102),
    lu16.init(0x0153),
    lu16.init(0x014b),
    lu16.init(0x00ed),
    lu16.init(0x00f1),
    lu16.init(0x010d),
    lu16.init(0x003a),
    lu16.init(0x003b),
    lu16.init(0x003f),
    lu16.init(0x0071),
    lu16.init(0x00b6),
    lu16.init(0x00f0),
    lu16.init(0x00ca),
    lu16.init(0x00db),
    lu16.init(0x00da),
    lu16.init(0x004c),
    lu16.init(0x00e7),
    lu16.init(0x0055),
    lu16.init(0x0057),
    lu16.init(0x0059),
    lu16.init(0x00d8),
    lu16.init(0x005b),
    lu16.init(0x005e),
    lu16.init(0x00f7),
    lu16.init(0x0118),
    lu16.init(0x0068),
    lu16.init(0x0073),
    lu16.init(0x015f),
    lu16.init(0x0035),
    lu16.init(0x00bc),
    lu16.init(0x00c9),
    lu16.init(0x007e),
    lu16.init(0x013d),
    lu16.init(0x014c),
    lu16.init(0x0103),
    lu16.init(0x0107),
    lu16.init(0x0122),
    lu16.init(0x009c),
    lu16.init(0x00d5),
    lu16.init(0x00a8),
    lu16.init(0x00d3),
    lu16.init(0x011d),
    lu16.init(0x0121),
    lu16.init(0x013b),
};

const em_first_items = [_]gen3.Item{
    // ????????
    gen3.Item{
        .name = undefined,
        .id = lu16.init(0),
        .price = lu16.init(0),
        .hold_effect = 0,
        .hold_effect_param = 0,
        .description = undefined,
        .importance = 0,
        .unknown = 0,
        .pocket = gen3.Pocket{ .rse = .items },
        .@"type" = 4,
        .field_use_func = undefined,
        .battle_usage = lu32.init(0),
        .battle_use_func = undefined,
        .secondary_id = lu32.init(0),
    },
    // MASTER BALL
    gen3.Item{
        .name = undefined,
        .id = lu16.init(1),
        .price = lu16.init(0),
        .hold_effect = 0,
        .hold_effect_param = 0,
        .description = undefined,
        .importance = 0,
        .unknown = 0,
        .pocket = gen3.Pocket{ .rse = .poke_balls },
        .@"type" = 0,
        .field_use_func = undefined,
        .battle_usage = lu32.init(2),
        .battle_use_func = undefined,
        .secondary_id = lu32.init(0),
    },
};

const em_last_items = [_]gen3.Item{
    // MAGMA EMBLEM
    gen3.Item{
        .name = undefined,
        .id = lu16.init(0x177),
        .price = lu16.init(0),
        .hold_effect = 0,
        .hold_effect_param = 0,
        .description = undefined,
        .importance = 1,
        .unknown = 1,
        .pocket = gen3.Pocket{ .rse = .key_items },
        .@"type" = 4,
        .field_use_func = undefined,
        .battle_usage = lu32.init(0),
        .battle_use_func = undefined,
        .secondary_id = lu32.init(0),
    },
    // OLD SEA MAP
    gen3.Item{
        .name = undefined,
        .id = lu16.init(0x178),
        .price = lu16.init(0),
        .hold_effect = 0,
        .hold_effect_param = 0,
        .description = undefined,
        .importance = 1,
        .unknown = 1,
        .pocket = gen3.Pocket{ .rse = .key_items },
        .@"type" = 4,
        .field_use_func = undefined,
        .battle_usage = lu32.init(0),
        .battle_use_func = undefined,
        .secondary_id = lu32.init(0),
    },
};

const rs_first_items = [_]gen3.Item{
    // ????????
    gen3.Item{
        .name = undefined,
        .id = lu16.init(0),
        .price = lu16.init(0),
        .hold_effect = 0,
        .hold_effect_param = 0,
        .description = undefined,
        .importance = 0,
        .unknown = 0,
        .pocket = gen3.Pocket{ .rse = .items },
        .@"type" = 4,
        .field_use_func = undefined,
        .battle_usage = lu32.init(0),
        .battle_use_func = undefined,
        .secondary_id = lu32.init(0),
    },
    // MASTER BALL
    gen3.Item{
        .name = undefined,
        .id = lu16.init(1),
        .price = lu16.init(0),
        .hold_effect = 0,
        .hold_effect_param = 0,
        .description = undefined,
        .importance = 0,
        .unknown = 0,
        .pocket = gen3.Pocket{ .rse = .poke_balls },
        .@"type" = 0,
        .field_use_func = undefined,
        .battle_usage = lu32.init(2),
        .battle_use_func = undefined,
        .secondary_id = lu32.init(0),
    },
};

const rs_last_items = [_]gen3.Item{
    // HM08
    gen3.Item{
        .name = undefined,
        .id = lu16.init(0x15A),
        .price = lu16.init(0),
        .hold_effect = 0,
        .hold_effect_param = 0,
        .description = undefined,
        .importance = 1,
        .unknown = 0,
        .pocket = gen3.Pocket{ .rse = .tms_hms },
        .@"type" = 1,
        .field_use_func = undefined,
        .battle_usage = lu32.init(0),
        .battle_use_func = undefined,
        .secondary_id = lu32.init(0),
    },
    // ????????
    gen3.Item{
        .name = undefined,
        .id = lu16.init(0),
        .price = lu16.init(0),
        .hold_effect = 0,
        .hold_effect_param = 0,
        .description = undefined,
        .importance = 0,
        .unknown = 0,
        .pocket = gen3.Pocket{ .rse = .items },
        .@"type" = 4,
        .field_use_func = undefined,
        .battle_usage = lu32.init(0),
        .battle_use_func = undefined,
        .secondary_id = lu32.init(0),
    },
    // ????????
    gen3.Item{
        .name = undefined,
        .id = lu16.init(0),
        .price = lu16.init(0),
        .hold_effect = 0,
        .hold_effect_param = 0,
        .description = undefined,
        .importance = 0,
        .unknown = 0,
        .pocket = gen3.Pocket{ .rse = .items },
        .@"type" = 4,
        .field_use_func = undefined,
        .battle_usage = lu32.init(0),
        .battle_use_func = undefined,
        .secondary_id = lu32.init(0),
    },
};

const frlg_first_items = [_]gen3.Item{
    gen3.Item{
        .name = undefined,
        .id = lu16.init(0),
        .price = lu16.init(0),
        .hold_effect = 0,
        .hold_effect_param = 0,
        .description = undefined,
        .importance = 0,
        .unknown = 0,
        .pocket = gen3.Pocket{ .frlg = .items },
        .@"type" = 4,
        .field_use_func = undefined,
        .battle_usage = lu32.init(0),
        .battle_use_func = undefined,
        .secondary_id = lu32.init(0),
    },
    gen3.Item{
        .name = undefined,
        .id = lu16.init(1),
        .price = lu16.init(0),
        .hold_effect = 0,
        .hold_effect_param = 0,
        .description = undefined,
        .importance = 0,
        .unknown = 0,
        .pocket = gen3.Pocket{ .frlg = .poke_balls },
        .@"type" = 0,
        .field_use_func = undefined,
        .battle_usage = lu32.init(2),
        .battle_use_func = undefined,
        .secondary_id = lu32.init(0),
    },
};

const frlg_last_items = [_]gen3.Item{
    gen3.Item{
        .name = undefined,
        .id = lu16.init(372),
        .price = lu16.init(0),
        .hold_effect = 0,
        .hold_effect_param = 0,
        .description = undefined,
        .importance = 1,
        .unknown = 1,
        .pocket = gen3.Pocket{ .frlg = .key_items },
        .@"type" = 4,
        .field_use_func = undefined,
        .battle_usage = lu32.init(0),
        .battle_use_func = undefined,
        .secondary_id = lu32.init(0),
    },
    gen3.Item{
        .name = undefined,
        .id = lu16.init(373),
        .price = lu16.init(0),
        .hold_effect = 0,
        .hold_effect_param = 0,
        .description = undefined,
        .importance = 1,
        .unknown = 1,
        .pocket = gen3.Pocket{ .frlg = .key_items },
        .@"type" = 4,
        .field_use_func = undefined,
        .battle_usage = lu32.init(0),
        .battle_use_func = undefined,
        .secondary_id = lu32.init(0),
    },
};

fn wildHeader(map_group: u8, map_num: u8) gen3.WildPokemonHeader {
    return gen3.WildPokemonHeader{
        .map_group = map_group,
        .map_num = map_num,
        .pad = undefined,
        .land = undefined,
        .surf = undefined,
        .rock_smash = undefined,
        .fishing = undefined,
    };
}

const em_first_wild_mon_headers = [_]gen3.WildPokemonHeader{
    wildHeader(0, 16),
    wildHeader(0, 17),
    wildHeader(0, 18),
};

const em_last_wild_mon_headers = [_]gen3.WildPokemonHeader{
    wildHeader(24, 106),
    wildHeader(24, 106),
    wildHeader(24, 107),
};

const rs_first_wild_mon_headers = [_]gen3.WildPokemonHeader{
    wildHeader(0, 0),
    wildHeader(0, 1),
    wildHeader(0, 5),
    wildHeader(0, 6),
};

const rs_last_wild_mon_headers = [_]gen3.WildPokemonHeader{
    wildHeader(0, 15),
    wildHeader(0, 50),
    wildHeader(0, 51),
};

const frlg_first_wild_mon_headers = [_]gen3.WildPokemonHeader{
    wildHeader(2, 27),
    wildHeader(2, 28),
    wildHeader(2, 29),
};

const frlg_last_wild_mon_headers = [_]gen3.WildPokemonHeader{
    wildHeader(1, 122),
    wildHeader(1, 122),
    wildHeader(1, 122),
    wildHeader(1, 122),
    wildHeader(1, 122),
    wildHeader(1, 122),
    wildHeader(1, 122),
    wildHeader(1, 122),
    wildHeader(1, 122),
};

const em_first_map_headers = [_]gen3.MapHeader{
// Petalburg City
gen3.MapHeader{
    .map_data = undefined,
    .map_events = undefined,
    .map_scripts = undefined,
    .map_connections = undefined,
    .music = lu16.init(362),
    .map_data_id = lu16.init(1),
    .map_sec = 0x07,
    .cave = 0,
    .weather = 2,
    .map_type = 2,
    .pad = undefined,
    .escape_rope = 0,
    .flags = 0b00001101,
    .map_battle_scene = 0,
}};

const em_last_map_headers = [_]gen3.MapHeader{
// Route 124 - Diving Treasure Hunters House
gen3.MapHeader{
    .map_data = undefined,
    .map_events = undefined,
    .map_scripts = undefined,
    .map_connections = undefined,
    .music = lu16.init(408),
    .map_data_id = lu16.init(301),
    .map_sec = 0x27,
    .cave = 0,
    .weather = 0,
    .map_type = 8,
    .pad = undefined,
    .escape_rope = 0,
    .flags = 0b00000000,
    .map_battle_scene = 0,
}};

const rs_first_map_headers = [_]gen3.MapHeader{
// Petalburg City
gen3.MapHeader{
    .map_data = undefined,
    .map_events = undefined,
    .map_scripts = undefined,
    .map_connections = undefined,
    .music = lu16.init(362),
    .map_data_id = lu16.init(1),
    .map_sec = 0x07,
    .cave = 0,
    .weather = 2,
    .map_type = 2,
    .pad = undefined,
    .escape_rope = 0,
    .flags = 0b00000001,
    .map_battle_scene = 0,
}};

const rs_last_map_headers = [_]gen3.MapHeader{
// Route 124 - Diving Treasure Hunters House
gen3.MapHeader{
    .map_data = undefined,
    .map_events = undefined,
    .map_scripts = undefined,
    .map_connections = undefined,
    .music = lu16.init(408),
    .map_data_id = lu16.init(302),
    .map_sec = 0x27,
    .cave = 0,
    .weather = 0,
    .map_type = 8,
    .pad = undefined,
    .escape_rope = 0,
    .flags = 0b00000000,
    .map_battle_scene = 0,
}};

const frlg_first_map_headers = [_]gen3.MapHeader{
// ???
gen3.MapHeader{
    .map_data = undefined,
    .map_events = undefined,
    .map_scripts = undefined,
    .map_connections = undefined,
    .music = lu16.init(0x12F),
    .map_data_id = lu16.init(0x2F),
    .map_sec = 0xC4,
    .cave = 0x0,
    .weather = 0x0,
    .map_type = 0x8,
    .pad = undefined,
    .escape_rope = 0x0,
    .flags = 0x0,
    .map_battle_scene = 0x8,
}};

const frlg_last_map_headers = [_]gen3.MapHeader{
// ???
gen3.MapHeader{
    .map_data = undefined,
    .map_events = undefined,
    .map_scripts = undefined,
    .map_connections = undefined,
    .music = lu16.init(0x151),
    .map_data_id = lu16.init(0xB),
    .map_sec = 0xA9,
    .cave = 0x0,
    .weather = 0x0,
    .map_type = 0x8,
    .pad = undefined,
    .escape_rope = 0x0,
    .flags = 0x0,
    .map_battle_scene = 0x0,
}};

fn __(comptime len: usize, lang: gen3.Language, str: []const u8) [len]u8 {
    @setEvalBranchQuota(100000);
    var res = [_]u8{0} ** len;
    gen3.encodings.encode(.en_us, str, &res) catch unreachable;
    return res;
}

const first_pokemon_names = [_][11]u8{
    __(11, .en_us, "??????????"),
    __(11, .en_us, "BULBASAUR"),
    __(11, .en_us, "IVYSAUR"),
    __(11, .en_us, "VENUSAUR"),
};

const last_pokemon_names = [_][11]u8{
    __(11, .en_us, "LATIAS"),
    __(11, .en_us, "LATIOS"),
    __(11, .en_us, "JIRACHI"),
    __(11, .en_us, "DEOXYS"),
    __(11, .en_us, "CHIMECHO"),
};

const first_ability_names = [_][13]u8{
    __(13, .en_us, "-------"),
    __(13, .en_us, "STENCH"),
    __(13, .en_us, "DRIZZLE"),
    __(13, .en_us, "SPEED BOOST"),
    __(13, .en_us, "BATTLE ARMOR"),
};

const last_ability_names = [_][13]u8{
    __(13, .en_us, "WHITE SMOKE"),
    __(13, .en_us, "PURE POWER"),
    __(13, .en_us, "SHELL ARMOR"),
    __(13, .en_us, "CACOPHONY"),
    __(13, .en_us, "AIR LOCK"),
};

const e_first_move_names = [_][13]u8{
    __(13, .en_us, "-"),
    __(13, .en_us, "POUND"),
    __(13, .en_us, "KARATE CHOP"),
    __(13, .en_us, "DOUBLESLAP"),
    __(13, .en_us, "COMET PUNCH"),
};

const rsfrlg_first_move_names = [_][13]u8{
    __(13, .en_us, "-$$$$$$"),
    __(13, .en_us, "POUND"),
    __(13, .en_us, "KARATE CHOP"),
    __(13, .en_us, "DOUBLESLAP"),
    __(13, .en_us, "COMET PUNCH"),
};

const last_move_names = [_][13]u8{
    __(13, .en_us, "ROCK BLAST"),
    __(13, .en_us, "SHOCK WAVE"),
    __(13, .en_us, "WATER PULSE"),
    __(13, .en_us, "DOOM DESIRE"),
    __(13, .en_us, "PSYCHO BOOST"),
};

const type_names = [_][7]u8{
    __(7, .en_us, "NORMAL"),
    __(7, .en_us, "FIGHT"),
    __(7, .en_us, "FLYING"),
    __(7, .en_us, "POISON"),
    __(7, .en_us, "GROUND"),
    __(7, .en_us, "ROCK"),
    __(7, .en_us, "BUG"),
    __(7, .en_us, "GHOST"),
    __(7, .en_us, "STEEL"),
    __(7, .en_us, "???"),
    __(7, .en_us, "FIRE"),
    __(7, .en_us, "WATER"),
    __(7, .en_us, "GRASS"),
    __(7, .en_us, "ELECTR"),
    __(7, .en_us, "PSYCHC"),
    __(7, .en_us, "ICE"),
    __(7, .en_us, "DRAGON"),
    __(7, .en_us, "DARK"),
};

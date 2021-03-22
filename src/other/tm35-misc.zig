const clap = @import("clap");
const format = @import("format");
const std = @import("std");
const util = @import("util");

const debug = std.debug;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const os = std.os;
const rand = std.rand;
const testing = std.testing;

const exit = util.exit;

const Param = clap.Param(clap.Help);

pub const main = util.generateMain("0.0.0", main2, &params, usage);

const params = blk: {
    @setEvalBranchQuota(100000);
    break :blk [_]Param{
        clap.parseParam("    --allow-biking <unchanged|nowhere|everywhere>   Change where biking is allowed (gen3 only) (default: unchanged).") catch unreachable,
        clap.parseParam("    --allow-running <unchanged|nowhere|everywhere>  Change where running is allowed (gen3 only) (default: unchanged).") catch unreachable,
        clap.parseParam("    --fast-text                                     Change text speed to fastest possible for the game.") catch unreachable,
        clap.parseParam("    --exp-yield-scaling <FLOAT>                     Scale The amount of exp Pokémons give. (default: 1.0).") catch unreachable,
        clap.parseParam("    --static-level-scaling <FLOAT>                  Scale static Pokémon levels by this number. (default: 1.0).") catch unreachable,
        clap.parseParam("    --trainer-level-scaling <FLOAT>                 Scale trainer Pokémon levels by this number. (default: 1.0).") catch unreachable,
        clap.parseParam("    --wild-level-scaling <FLOAT>                    Scale wild Pokémon levels by this number. (default: 1.0).") catch unreachable,
        clap.parseParam("-h, --help                                          Display this help text and exit.") catch unreachable,
        clap.parseParam("-v, --version                                       Output version information and exit.") catch unreachable,
    };
};

fn usage(writer: anytype) !void {
    try writer.writeAll("Usage: tm35-no-trade-evolutions ");
    try clap.usage(writer, &params);
    try writer.writeAll("\nCommand to apply miscellaneous changed.\n" ++
        "\n" ++
        "Options:\n");
    try clap.help(writer, &params);
}

const Allow = enum {
    unchanged,
    nowhere,
    everywhere,
};

/// TODO: This function actually expects an allocator that owns all the memory allocated, such
///       as ArenaAllocator or FixedBufferAllocator. Can we either make this requirement explicit
///       or move the Arena into this function?
pub fn main2(
    allocator: *mem.Allocator,
    comptime Reader: type,
    comptime Writer: type,
    stdio: util.CustomStdIoStreams(Reader, Writer),
    args: anytype,
) u8 {
    const biking_arg = args.option("--allow-biking") orelse "unchanged";
    const running_arg = args.option("--allow-running") orelse "unchanged";
    const exp_scale_arg = args.option("--exp-yield-scaling") orelse "1.0";
    const static_scale_arg = args.option("--static-level-scaling") orelse "1.0";
    const trainer_scale_arg = args.option("--trainer-level-scaling") orelse "1.0";
    const wild_scale_arg = args.option("--wild-level-scaling") orelse "1.0";

    const fast_text = args.flag("--fast-text");
    const biking = std.meta.stringToEnum(Allow, biking_arg);
    const running = std.meta.stringToEnum(Allow, running_arg);
    const trainer_scale = fmt.parseFloat(f64, trainer_scale_arg);
    const wild_scale = fmt.parseFloat(f64, wild_scale_arg);
    const static_scale = fmt.parseFloat(f64, static_scale_arg);
    const exp_scale = fmt.parseFloat(f64, exp_scale_arg);

    for ([_]struct { arg: []const u8, value: []const u8, check: ?Allow }{
        .{ .arg = "--allow-biking", .value = biking_arg, .check = biking },
        .{ .arg = "--allow-running", .value = running_arg, .check = running },
    }) |arg| {
        if (arg.check == null) {
            stdio.err.print("Invalid value for {}: {}\n", .{ arg.arg, arg.value }) catch {};
            usage(stdio.err) catch {};
            return 1;
        }
    }

    for ([_]struct { arg: []const u8, value: []const u8, check: anyerror!f64 }{
        .{ .arg = "--exp-yield-scaling", .value = exp_scale_arg, .check = exp_scale },
        .{ .arg = "--static-level-scaling", .value = static_scale_arg, .check = static_scale },
        .{ .arg = "--trainer-level-scaling", .value = trainer_scale_arg, .check = trainer_scale },
        .{ .arg = "--wild-level-scaling", .value = wild_scale_arg, .check = wild_scale },
    }) |arg| {
        if (arg.check) |_| {} else |err| {
            stdio.err.print("Invalid value for {}: {}\n", .{ arg.arg, arg.value }) catch {};
            usage(stdio.err) catch {};
            return 1;
        }
    }

    var fifo = util.io.Fifo(.Dynamic).init(allocator);
    const opt = Options{
        .fast_text = fast_text,
        .biking = biking.?,
        .running = running.?,
        .exp_scale = exp_scale catch unreachable,
        .static_scale = static_scale catch unreachable,
        .trainer_scale = trainer_scale catch unreachable,
        .wild_scale = wild_scale catch unreachable,
    };
    while (util.io.readLine(stdio.in, &fifo) catch |err| return exit.stdinErr(stdio.err, err)) |line| {
        parseLine(stdio.out, allocator, opt, line) catch |err| switch (err) {
            error.ParserFailed => stdio.out.print("{}\n", .{line}) catch |err2| {
                return exit.stdoutErr(stdio.err, err2);
            },
            else => return exit.stdoutErr(stdio.err, err),
        };
    }

    return 0;
}

const Options = struct {
    fast_text: bool,
    running: Allow,
    biking: Allow,
    exp_scale: f64,
    static_scale: f64,
    trainer_scale: f64,
    wild_scale: f64,
};

fn parseLine(out: anytype, allocator: *mem.Allocator, opt: Options, str: []const u8) !void {
    const parsed = try format.parse(allocator, str);
    switch (parsed) {
        .instant_text => |_| if (opt.fast_text) {
            return out.writeAll(".instant_text=true\n");
        } else {
            return error.ParserFailed;
        },
        .text_delays => |delay| if (opt.fast_text) {
            const new_delay = switch (delay.index) {
                0 => @as(usize, 2),
                1 => @as(usize, 1),
                else => @as(usize, 0),
            };
            return out.print(".text_delays[{}]={}\n", .{ delay.index, new_delay });
        } else {
            return error.ParserFailed;
        },
        .pokemons => |pokemons| switch (pokemons.value) {
            .base_exp_yield => |yield| if (opt.exp_scale != 1.0) {
                const new_yield_float = math.floor(@intToFloat(f64, yield) * opt.exp_scale);
                const new_yield = @floatToInt(u16, new_yield_float);
                return out.print(".pokemons[{}].base_exp_yield={}\n", .{
                    pokemons.index,
                    new_yield,
                });
            } else {
                return error.ParserFailed;
            },
            .stats,
            .types,
            .catch_rate,
            .ev_yield,
            .items,
            .gender_ratio,
            .egg_cycles,
            .base_friendship,
            .growth_rate,
            .egg_groups,
            .abilities,
            .color,
            .evos,
            .moves,
            .tms,
            .hms,
            .name,
            .pokedex_entry,
            => return error.ParserFailed,
        },
        .maps => |maps| {
            switch (maps.value) {
                .allow_cycling, .allow_running => {
                    const allow = if (maps.value == .allow_running) opt.running else opt.biking;
                    if (allow == .unchanged)
                        return error.ParserFailed;

                    return out.print(".maps[{}].{}={}\n", .{ maps.index, @tagName(maps.value), allow == .everywhere });
                },
                .music,
                .cave,
                .weather,
                .type,
                .escape_rope,
                .battle_scene,
                .allow_escaping,
                .show_map_name,
                => return error.ParserFailed,
            }
        },
        .trainers => |trainers| switch (trainers.value) {
            .party => |party| switch (party.value) {
                .level => |level| if (opt.trainer_scale != 1.0) {
                    const new_level_float = math.floor(@intToFloat(f64, level) * opt.trainer_scale);
                    const new_level = @floatToInt(u8, math.min(new_level_float, 100));
                    return out.print(".trainers[{}].party[{}].level={}\n", .{
                        trainers.index,
                        party.index,
                        new_level,
                    });
                } else {
                    return error.ParserFailed;
                },
                .ability,
                .species,
                .item,
                .moves,
                => return error.ParserFailed,
            },
            .class,
            .encounter_music,
            .trainer_picture,
            .name,
            .items,
            .party_type,
            .party_size,
            => return error.ParserFailed,
        },
        .wild_pokemons => |wild_areas| {
            const wild_area = switch (wild_areas.value) {
                .grass,
                .grass_morning,
                .grass_day,
                .grass_night,
                .dark_grass,
                .rustling_grass,
                .land,
                .surf,
                .ripple_surf,
                .rock_smash,
                .fishing,
                .ripple_fishing,
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
                => |*res| res,
            };

            switch (wild_area.*) {
                .pokemons => |pokemons| switch (pokemons.value) {
                    .min_level, .max_level => |level| if (opt.wild_scale != 1.0) {
                        const new_level_float = math.floor(@intToFloat(f64, level) * opt.wild_scale);
                        const new_level = @floatToInt(u8, math.min(new_level_float, 100));
                        return out.print(".wild_pokemons[{}].{}.pokemons[{}].{}={}\n", .{
                            wild_areas.index,
                            @tagName(wild_areas.value),
                            pokemons.index,
                            @tagName(pokemons.value),
                            new_level,
                        });
                    } else {
                        return error.ParserFailed;
                    },
                    .species => return error.ParserFailed,
                },
                .encounter_rate => return error.ParserFailed,
            }
        },
        .static_pokemons => |pokemons| switch (pokemons.value) {
            .level => |level| if (opt.static_scale != 1.0) {
                const new_level_float = math.floor(@intToFloat(f64, level) * opt.static_scale);
                const new_level = @floatToInt(u8, math.min(new_level_float, 100));
                return out.print(".static_pokemons[{}].level={}\n", .{ pokemons.index, new_level });
            } else {
                return error.ParserFailed;
            },
            .species => return error.ParserFailed,
        },
        .version,
        .game_title,
        .gamecode,
        .starters,
        .moves,
        .abilities,
        .types,
        .tms,
        .hms,
        .items,
        .pokedex,
        .given_pokemons,
        .pokeball_items,
        .hidden_hollows,
        .text,
        => return error.ParserFailed,
    }
    unreachable;
}

test "tm35-misc" {
    util.testing.testProgram(main2, &params, &[_][]const u8{"--allow-biking=everywhere"},
        \\.maps[0].allow_cycling=false
        \\.maps[0].allow_cycling=true
        \\
    ,
        \\.maps[0].allow_cycling=true
        \\.maps[0].allow_cycling=true
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{"--allow-biking=nowhere"},
        \\.maps[0].allow_cycling=false
        \\.maps[0].allow_cycling=true
        \\
    ,
        \\.maps[0].allow_cycling=false
        \\.maps[0].allow_cycling=false
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{"--allow-biking=unchanged"},
        \\.maps[0].allow_cycling=false
        \\.maps[0].allow_cycling=true
        \\
    ,
        \\.maps[0].allow_cycling=false
        \\.maps[0].allow_cycling=true
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{"--allow-running=everywhere"},
        \\.maps[0].allow_running=false
        \\.maps[0].allow_running=true
        \\
    ,
        \\.maps[0].allow_running=true
        \\.maps[0].allow_running=true
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{"--allow-running=nowhere"},
        \\.maps[0].allow_running=false
        \\.maps[0].allow_running=true
        \\
    ,
        \\.maps[0].allow_running=false
        \\.maps[0].allow_running=false
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{"--allow-running=unchanged"},
        \\.maps[0].allow_running=false
        \\.maps[0].allow_running=true
        \\
    ,
        \\.maps[0].allow_running=false
        \\.maps[0].allow_running=true
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{"--fast-text"},
        \\.instant_text=false
        \\.instant_text=true
        \\.text_delays[0]=10
        \\.text_delays[1]=10
        \\.text_delays[2]=10
        \\.text_delays[3]=10
        \\
    ,
        \\.instant_text=true
        \\.instant_text=true
        \\.text_delays[0]=2
        \\.text_delays[1]=1
        \\.text_delays[2]=0
        \\.text_delays[3]=0
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{"--static-level-scaling=0.5"},
        \\.static_pokemons[0].level=20
        \\.static_pokemons[1].level=30
        \\
    ,
        \\.static_pokemons[0].level=10
        \\.static_pokemons[1].level=15
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{"--trainer-level-scaling=0.5"},
        \\.trainers[0].party[0].level=20
        \\.trainers[10].party[10].level=10
        \\
    ,
        \\.trainers[0].party[0].level=10
        \\.trainers[10].party[10].level=5
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{"--wild-level-scaling=0.5"},
        \\.wild_pokemons[0].grass.pokemons[0].min_level=10
        \\.wild_pokemons[0].grass.pokemons[0].max_level=20
        \\.wild_pokemons[0].fishing.pokemons[0].min_level=20
        \\.wild_pokemons[0].fishing.pokemons[0].max_level=40
        \\
    ,
        \\.wild_pokemons[0].grass.pokemons[0].min_level=5
        \\.wild_pokemons[0].grass.pokemons[0].max_level=10
        \\.wild_pokemons[0].fishing.pokemons[0].min_level=10
        \\.wild_pokemons[0].fishing.pokemons[0].max_level=20
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{"--exp-yield-scaling=0.5"},
        \\.pokemons[0].pokedex_entry=0
        \\.pokemons[0].base_exp_yield=20
        \\.pokemons[1].base_exp_yield=40
        \\
    ,
        \\.pokemons[0].pokedex_entry=0
        \\.pokemons[0].base_exp_yield=10
        \\.pokemons[1].base_exp_yield=20
        \\
    );
}

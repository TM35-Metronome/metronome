const clap = @import("clap");
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
const parse = util.parse;

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

    var fifo = util.read.Fifo(.Dynamic).init(allocator);
    const opt = Options{
        .fast_text = fast_text,
        .biking = biking.?,
        .running = running.?,
        .exp_scale = exp_scale catch unreachable,
        .static_scale = static_scale catch unreachable,
        .trainer_scale = trainer_scale catch unreachable,
        .wild_scale = wild_scale catch unreachable,
    };
    while (util.read.line(stdio.in, &fifo) catch |err| return exit.stdinErr(stdio.err, err)) |line| {
        parseLine(stdio.out, opt, line) catch |err| switch (err) {
            error.ParseError => stdio.out.print("{}\n", .{line}) catch |err2| {
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

fn parseLine(out: anytype, opt: Options, str: []const u8) !void {
    const sw = parse.Swhash(16);
    const m = sw.match;
    const c = sw.case;
    var p = parse.MutParser{ .str = str };

    switch (m(try p.parse(parse.anyField))) {
        c("instant_text") => if (opt.fast_text) {
            _ = try p.parse(parse.boolv);
            return out.writeAll(".instant_text=true\n");
        } else {
            return error.ParseError;
        },
        c("text_delays") => if (opt.fast_text) {
            const index = try p.parse(parse.index);
            _ = try p.parse(parse.usizev);

            const new_index = switch (index) {
                0 => @as(usize, 2),
                1 => @as(usize, 1),
                else => @as(usize, 0),
            };
            return out.print(".text_delays[{}]={}\n", .{ index, new_index });
        } else {
            return error.ParseError;
        },
        c("pokemons") => if (opt.exp_scale != 1.0) {
            const pokemon_index = try p.parse(parse.index);
            try p.parse(comptime parse.field("base_exp_yield"));
            const yield = try p.parse(parse.u16v);

            const new_yield_float = math.floor(@intToFloat(f64, yield) * opt.exp_scale);
            const new_yield = @floatToInt(u16, new_yield_float);
            return out.print(".pokemons[{}].base_exp_yield={}\n", .{
                pokemon_index,
                new_yield,
            });
        },
        c("map") => {
            const index = try p.parse(parse.index);
            const field = try p.parse(parse.anyField);
            switch (m(field)) {
                c("allow_cycling"), c("allow_running") => {
                    const allow = if (c("allow_running") == m(field)) opt.running else opt.biking;
                    if (allow == .unchanged)
                        return error.ParseError;

                    return out.print(".map[{}].{}={}\n", .{ index, field, allow == .everywhere });
                },
                else => return error.ParseError,
            }
        },
        c("trainers") => if (opt.trainer_scale != 1.0) {
            const trainer_index = try p.parse(parse.index);
            try p.parse(comptime parse.field("party"));
            const party_index = try p.parse(parse.index);
            try p.parse(comptime parse.field("level"));
            const level = try p.parse(parse.u8v);

            const new_level_float = math.floor(@intToFloat(f64, level) * opt.trainer_scale);
            const new_level = @floatToInt(u8, math.min(new_level_float, 100));
            return out.print(".trainers[{}].party[{}].level={}\n", .{
                trainer_index,
                party_index,
                new_level,
            });
        } else {
            return error.ParseError;
        },
        c("wild_pokemons") => if (opt.wild_scale != 1.0) {
            const zone_index = try p.parse(parse.index);
            const area_name = try p.parse(parse.anyField);

            try p.parse(comptime parse.field("pokemons"));
            const poke_index = try p.parse(parse.index);

            const field = try p.parse(parse.anyField);
            switch (m(field)) {
                c("min_level"), c("max_level") => {
                    const level = try p.parse(parse.u8v);
                    const new_level_float = math.floor(@intToFloat(f64, level) * opt.wild_scale);
                    const new_level = @floatToInt(u8, math.min(new_level_float, 100));
                    return out.print(".wild_pokemons[{}].{}.pokemons[{}].{}={}\n", .{
                        zone_index,
                        area_name,
                        poke_index,
                        field,
                        new_level,
                    });
                },
                else => return error.ParseError,
            }
        } else {
            return error.ParseError;
        },
        c("static_pokemons") => if (opt.static_scale != 1.0) {
            const index = try p.parse(parse.index);
            try p.parse(comptime parse.field("level"));
            const level = try p.parse(parse.u8v);

            const new_level_float = math.floor(@intToFloat(f64, level) * opt.static_scale);
            const new_level = @floatToInt(u8, math.min(new_level_float, 100));
            return out.print(".static_pokemons[{}].level={}\n", .{ index, new_level });
        } else {
            return error.ParseError;
        },
        else => return error.ParseError,
    }
    unreachable;
}

test "tm35-misc" {
    util.testing.testProgram(main2, &params, &[_][]const u8{"--allow-biking=everywhere"},
        \\.map[0].allow_cycling=false
        \\.map[0].allow_cycling=true
        \\
    ,
        \\.map[0].allow_cycling=true
        \\.map[0].allow_cycling=true
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{"--allow-biking=nowhere"},
        \\.map[0].allow_cycling=false
        \\.map[0].allow_cycling=true
        \\
    ,
        \\.map[0].allow_cycling=false
        \\.map[0].allow_cycling=false
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{"--allow-biking=unchanged"},
        \\.map[0].allow_cycling=false
        \\.map[0].allow_cycling=true
        \\
    ,
        \\.map[0].allow_cycling=false
        \\.map[0].allow_cycling=true
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{"--allow-running=everywhere"},
        \\.map[0].allow_running=false
        \\.map[0].allow_running=true
        \\
    ,
        \\.map[0].allow_running=true
        \\.map[0].allow_running=true
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{"--allow-running=nowhere"},
        \\.map[0].allow_running=false
        \\.map[0].allow_running=true
        \\
    ,
        \\.map[0].allow_running=false
        \\.map[0].allow_running=false
        \\
    );
    util.testing.testProgram(main2, &params, &[_][]const u8{"--allow-running=unchanged"},
        \\.map[0].allow_running=false
        \\.map[0].allow_running=true
        \\
    ,
        \\.map[0].allow_running=false
        \\.map[0].allow_running=true
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
        \\.pokemons[0].base_exp_yield=20
        \\.pokemons[1].base_exp_yield=40
        \\
    ,
        \\.pokemons[0].base_exp_yield=10
        \\.pokemons[1].base_exp_yield=20
        \\
    );
}

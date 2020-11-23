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
        clap.parseParam("    --trainer-level-scaling <FLOAT>                 Scale trainer Pokémon levels by this number. (default: 1.0).") catch unreachable,
        clap.parseParam("    --wild-level-scaling <FLOAT>                    Scale wild Pokémon levels by this number. (default: 1.0).") catch unreachable,
        clap.parseParam("    --static-level-scaling <FLOAT>                  Scale static Pokémon levels by this number. (default: 1.0).") catch unreachable,
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
    const trainer_scale_arg = args.option("--trainer-level-scaling") orelse "1.0";
    const wild_scale_arg = args.option("--wild-level-scaling") orelse "1.0";
    const static_scale_arg = args.option("--static-level-scaling") orelse "1.0";

    const fast_text = args.flag("--fast-text");
    const biking = std.meta.stringToEnum(Allow, biking_arg);
    const running = std.meta.stringToEnum(Allow, running_arg);
    const trainer_scale = fmt.parseFloat(f64, trainer_scale_arg);
    const wild_scale = fmt.parseFloat(f64, wild_scale_arg);
    const static_scale = fmt.parseFloat(f64, static_scale_arg);

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
        .{ .arg = "--trainer-level-scaling", .value = trainer_scale_arg, .check = trainer_scale },
        .{ .arg = "--static-level-scaling", .value = static_scale_arg, .check = static_scale },
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
        .trainer_scale = trainer_scale catch unreachable,
        .wild_scale = wild_scale catch unreachable,
        .static_scale = static_scale catch unreachable,
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
    trainer_scale: f64,
    wild_scale: f64,
    static_scale: f64,
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
        },
        c("text_delays") => if (opt.fast_text) {
            const index = try p.parse(parse.index);
            _ = try p.parse(parse.usizev);
            return out.print(".text_delays[{}]={}\n", .{
                index, switch (index) {
                    0 => @as(usize, 2),
                    1 => @as(usize, 1),
                    else => @as(usize, 0),
                },
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

            const new_level_float = math.floor(@intToFloat(f64, level) * opt.wild_scale);
            const new_level = @floatToInt(u8, math.min(new_level_float, 100));
            return out.print(".trainers[{}].party[{}].level={}\n", .{
                trainer_index,
                party_index,
                new_level,
            });
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
        },
        c("static_pokemons") => {
            const index = try p.parse(parse.index);
            try p.parse(comptime parse.field("level"));
            const level = try p.parse(parse.u8v);

            const new_level_float = math.floor(@intToFloat(f64, level) * opt.wild_scale);
            const new_level = @floatToInt(u8, math.min(new_level_float, 100));
            return out.print(".static_pokemons[{}].level={}\n", .{ index, new_level });
        },
        else => return error.ParseError,
    }
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
}

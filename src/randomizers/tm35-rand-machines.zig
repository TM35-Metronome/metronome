const clap = @import("clap");
const format = @import("format");
const std = @import("std");
const ston = @import("ston");
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
const unicode = std.unicode;

const Utf8 = util.unicode.Utf8View;

const escape = util.escape;
const parse = util.parse;

const Program = @This();

allocator: mem.Allocator,
options: struct {
    seed: u64,
    hms: bool,
},
items: Items = Items{},
moves: Moves = Moves{},
tms: Machines = Machines{},
hms: Machines = Machines{},

pub const main = util.generateMain(Program);
pub const version = "0.0.0";
pub const description =
    \\Randomizes the moves of tms.
    \\
;

pub const params = &[_]clap.Param(clap.Help){
    clap.parseParam("-h, --help        Display this help text and exit.                                                          ") catch unreachable,
    clap.parseParam("    --hms         Also randomize hms (this may break your game).                                            ") catch unreachable,
    clap.parseParam("-s, --seed <INT>  The seed to use for random numbers. A random seed will be picked if this is not specified.") catch unreachable,
    clap.parseParam("-v, --version     Output version information and exit.                                                      ") catch unreachable,
};

pub fn init(allocator: mem.Allocator, args: anytype) !Program {
    const seed = try util.getSeed(args);
    const hms = args.flag("--hms");

    return Program{
        .allocator = allocator,
        .options = .{
            .seed = seed,
            .hms = hms,
        },
    };
}

pub fn run(
    program: *Program,
    comptime Reader: type,
    comptime Writer: type,
    stdio: util.CustomStdIoStreams(Reader, Writer),
) anyerror!void {
    try format.io(program.allocator, stdio.in, stdio.out, program, useGame);
    try program.randomize();
    try program.output(stdio.out);
}

fn output(program: *Program, writer: anytype) !void {
    try ston.serialize(writer, .{
        .tms = program.tms,
        .hms = program.hms,
    });
    for (program.items.values()) |item, i| {
        try ston.serialize(writer, .{ .items = ston.index(program.items.keys()[i], .{
            .description = ston.string(escape.default.escapeFmt(item.description)),
        }) });
    }
}

fn useGame(program: *Program, parsed: format.Game) !void {
    const allocator = program.allocator;
    switch (parsed) {
        .tms => |tms| {
            _ = try program.tms.put(allocator, tms.index, tms.value);
            return;
        },
        .hms => |ms| if (program.options.hms) {
            _ = try program.hms.put(allocator, ms.index, ms.value);
            return;
        } else {
            return error.ParserFailed;
        },
        .moves => |moves| {
            const move = (try program.moves.getOrPutValue(allocator, moves.index, .{})).value_ptr;
            switch (moves.value) {
                .description => |_desc| {
                    const desc = try escape.default.unescapeAlloc(allocator, _desc);
                    move.description = try Utf8.init(desc);
                },
                else => {},
            }
            return error.ParserFailed;
        },
        .items => |items| {
            const item = (try program.items.getOrPutValue(allocator, items.index, .{})).value_ptr;
            switch (items.value) {
                .pocket => |pocket| item.pocket = pocket,
                .name => |_name| {
                    const unescaped_name = try escape.default.unescapeAlloc(allocator, _name);
                    item.name = try Utf8.init(unescaped_name);
                },
                .description => |_desc| {
                    const desc = try escape.default.unescapeAlloc(allocator, _desc);
                    item.description = try Utf8.init(desc);
                },
                else => {},
            }
            return error.ParserFailed;
        },
        .version,
        .game_title,
        .gamecode,
        .instant_text,
        .starters,
        .text_delays,
        .trainers,
        .pokemons,
        .abilities,
        .types,
        .pokedex,
        .maps,
        .wild_pokemons,
        .static_pokemons,
        .given_pokemons,
        .pokeball_items,
        .hidden_hollows,
        .text,
        => return error.ParserFailed,
    }
    unreachable;
}

fn randomize(program: *Program) !void {
    const allocator = program.allocator;
    const random = rand.DefaultPrng.init(program.options.seed).random();

    randomizeMachines(program, random, program.tms.values());
    randomizeMachines(program, random, program.hms.values());

    // Find the maximum length of a line. Used to split descriptions into lines.
    var max_line_len: usize = 0;
    for (program.items.values()) |item| {
        var desc = item.description;
        while (mem.indexOf(u8, desc.bytes, "\n")) |index| {
            const line = Utf8.init(desc.bytes[0..index]) catch unreachable;
            max_line_len = math.max(line.len, max_line_len);
            desc = Utf8.init(desc.bytes[index + 1 ..]) catch unreachable;
        }
        max_line_len = math.max(description.len, max_line_len);
    }

    // HACK: The games does not used mono fonts, so actually, using the
    //       max_line_len to destribute newlines will not actually be totally
    //       correct. The best I can do here is to just reduce the max_line_len
    //       by some amount and hope it is enough for all strings.
    max_line_len -|= 5;

    for (program.items.values()) |*item| {
        if (item.pocket != .tms_hms)
            continue;

        const is_tm = mem.startsWith(u8, item.name.bytes, "TM");
        const is_hm = mem.startsWith(u8, item.name.bytes, "HM");
        if (is_tm or is_hm) {
            const number = fmt.parseUnsigned(u8, item.name.bytes[2..], 10) catch continue;
            const machines = if (is_tm) program.tms else program.hms;
            const move_id = machines.get(number - 1) orelse continue;
            const move = program.moves.get(move_id) orelse continue;
            const new_desc = try util.unicode.splitIntoLines(
                allocator,
                max_line_len,
                move.description,
            );
            item.description = new_desc.slice(0, item.description.len);
        }
    }
}

fn randomizeMachines(program: *Program, random: rand.Random, machines: []u16) void {
    const pick_from = program.moves.keys();
    for (machines) |*machine, i| while (true) {
        machine.* = util.random.item(random, pick_from).?.*;

        // Prevent duplicates if possible. We cannot prevent it if we have less moves to pick
        // from than there is machines
        if (pick_from.len < machines.len)
            break;
        if (mem.indexOfScalar(u16, machines[0..i], machine.*) == null)
            break;
    };
}

const Items = std.AutoArrayHashMapUnmanaged(u16, Item);
const Machines = std.AutoArrayHashMapUnmanaged(u8, u16);
const Moves = std.AutoArrayHashMapUnmanaged(u16, Move);

const Item = struct {
    pocket: format.Pocket = .none,
    name: Utf8 = Utf8.init("") catch unreachable,
    description: Utf8 = Utf8.init("") catch unreachable,
};

const Move = struct {
    description: Utf8 = Utf8.init("") catch unreachable,
};

//
// Testing
//

fn expectSameMachines(a: CollectedMachinesSet, b: CollectedMachinesSet) !void {
    try util.set.expectEqual(a, b);
}

fn expectDifferentMachines(a: CollectedMachinesSet, b: CollectedMachinesSet) !void {
    try testing.expect(!util.set.eql(a, b));
}

const CollectedMachinesSet = std.AutoHashMap(ston.Index(u8, u16), void);

const CollectedMachines = struct {
    hms: CollectedMachinesSet,
    tms: CollectedMachinesSet,

    fn deinit(machines: *CollectedMachines) void {
        machines.hms.deinit();
        machines.tms.deinit();
    }
};

fn collectMachines(in: []const u8) !CollectedMachines {
    var res = CollectedMachines{
        .hms = std.AutoHashMap(ston.Index(u8, u16), void).init(testing.allocator),
        .tms = std.AutoHashMap(ston.Index(u8, u16), void).init(testing.allocator),
    };
    errdefer res.deinit();

    var parser = ston.Parser{ .str = in };
    var des = ston.Deserializer(format.Game){ .parser = &parser };
    while (des.next()) |line| switch (line) {
        .hms => |v| try testing.expect((try res.hms.fetchPut(v, {})) == null),
        .tms => |v| try testing.expect((try res.tms.fetchPut(v, {})) == null),
        else => {},
    } else |_| {
        try testing.expectEqual(parser.str.len, parser.i);
    }

    return res;
}

test {
    const number_of_seeds = 20;
    const test_case = try util.testing.filter(util.testing.test_case, &.{
        ".hms[*]=*",
        ".tms[*]=*",
        ".moves[*].pp=*",
    });
    defer testing.allocator.free(test_case);

    var original_machines = try collectMachines(test_case);
    defer original_machines.deinit();

    var seed: usize = 0;
    while (seed < number_of_seeds) : (seed += 1) {
        var buf: [20]u8 = undefined;
        const seed_arg = std.fmt.bufPrint(&buf, "--seed={}", .{seed}) catch unreachable;
        const res = try util.testing.runProgram(Program, .{
            .in = test_case,
            .args = &[_][]const u8{seed_arg},
        });
        defer testing.allocator.free(res);

        var res_machines = try collectMachines(res);
        defer res_machines.deinit();

        try expectSameMachines(original_machines.hms, res_machines.hms);
        try expectDifferentMachines(original_machines.tms, res_machines.tms);
    }

    seed = 0;
    while (seed < number_of_seeds) : (seed += 1) {
        var buf: [20]u8 = undefined;
        const seed_arg = std.fmt.bufPrint(&buf, "--seed={}", .{seed}) catch unreachable;
        const res = try util.testing.runProgram(Program, .{
            .in = test_case,
            .args = &[_][]const u8{ seed_arg, "--hms" },
        });
        defer testing.allocator.free(res);

        var res_machines = try collectMachines(res);
        defer res_machines.deinit();

        try expectDifferentMachines(original_machines.hms, res_machines.hms);
        try expectDifferentMachines(original_machines.tms, res_machines.tms);
    }
}

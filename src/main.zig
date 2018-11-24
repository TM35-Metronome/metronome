const clap = @import("zig-clap");
const format = @import("tm35-format");
const fun = @import("fun-with-zig");
const std = @import("std");

const debug = std.debug;
const fmt = std.fmt;
const io = std.io;
const math = std.math;
const mem = std.mem;
const os = std.os;

const Clap = clap.ComptimeClap([]const u8, params);
const Names = clap.Names;
const Param = clap.Param([]const u8);

const params = []Param{
    Param.flag(
        "display this help text and exit",
        Names.both("help"),
    ),
    Param.flag(
        "the seed used to randomize stats",
        Names.both("seed"),
    ),
    Param.positional(""),
};

fn usage(stream: var) !void {
    try stream.write(
        \\Usage: tm35-rand-stats [OPTION]... FILE
        \\Reads the tm35 format from stdin and randomizes the stats of pokemons.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, params);
}

pub fn main() u8 {
    const stdin_file = std.io.getStdIn() catch return 1;
    const stderr_file = std.io.getStdErr() catch return 1;
    const stdout_file = std.io.getStdOut() catch return 1;
    var stdin_stream = stdin_file.inStream();
    var stderr_stream = stderr_file.outStream();
    var stdout_stream = stdout_file.outStream();
    var buf_stdin = io.BufferedInStream(os.File.InStream.Error).init(&stdin_stream.stream);
    var buf_stdout = io.BufferedOutStream(os.File.OutStream.Error).init(&stdout_stream.stream);

    const stdin = &buf_stdin.stream;
    const stdout = &buf_stdout.stream;
    const stderr = &stderr_stream.stream;

    var direct_allocator_state = std.heap.DirectAllocator.init();
    const direct_allocator = &direct_allocator_state.allocator;
    defer direct_allocator_state.deinit();

    // TODO: Other allocator?
    const allocator = direct_allocator;

    var arg_iter = clap.args.OsIterator.init(allocator);
    const iter = &arg_iter.iter;
    defer arg_iter.deinit();
    _ = iter.next() catch undefined;

    var args = Clap.parse(allocator, clap.args.OsIterator.Error, iter) catch |err| {
        debug.warn("error: {}\n", err);
        usage(stderr) catch {};
        return 1;
    };
    defer args.deinit();

    main2(allocator, args, stdin, stdout, stderr) catch |err| {
        debug.warn("error: {}\n", err);
        return 1;
    };

    buf_stdout.flush() catch |err| {
        debug.warn("error: {}\n", err);
        return 1;
    };

    return 0;
}

pub fn main2(allocator: *mem.Allocator, args: Clap, stdin: var, stdout: var, stderr: var) !void {
    if (args.flag("--help"))
        return try usage(stdout);

    const pokemons = try Parser.parse(allocator, stdin, stdout);



    var iter = pokemons.iterator();
    while (iter.next()) |kv| {
        inline for ([][]const u8{
            "hp",
            "attack",
            "defense",
            "speed",
            "sp_attack",
            "sp_defense",
        }) |stat| {
            if (@field(kv.value, stat)) |s|
                try stdout.print("pokemons[{}].stats.{}={}\n", kv.key, stat, s);
        }
    }
}

const PokemonMap = std.AutoHashMap(usize, Pokemon);
const EvoMap = std.AutoHashMap(usize, usize);

const Pokemon = struct {
    hp: ?u8,
    attack: ?u8,
    defense: ?u8,
    speed: ?u8,
    sp_attack: ?u8,
    sp_defense: ?u8,
    evos: EvoMap,
};

const Parser = struct {
    parser: format.Parser,
    line: usize,

    fn parse(allocator: *mem.Allocator, in_stream: var, out_stream: var) !PokemonMap {
        var res = PokemonMap.init(allocator);
        var line_buf = try std.Buffer.initSize(allocator, 0);
        defer line_buf.deinit();

        var line: usize = 1;
        while (readLine(in_stream, &line_buf)) |str| : (line += 1) {
            var parser = Parser{
                .parser = format.Parser.init(format.Tokenizer.init(str)),
                .line = line,
            };

            switch (parser.parseLine(&res, str) catch PrintLine.True) {
                PrintLine.True => try out_stream.print("{}\n", str),
                PrintLine.False => {},
            }

            line_buf.shrink(0);
        } else |err| switch (err) {
            error.EndOfStream => {},
            else => return err,
        }

        return res;
    }

    const PrintLine = enum {
        True,
        False,
    };

    fn parseLine(parser: *Parser, pokemons: *PokemonMap, str: []const u8) !PrintLine {
        @setEvalBranchQuota(100000);

        const tf = fun.match.StringSwitch([][]const u8{
            "pokemons",
        });

        const top_field_node = switch (parser.parser.next() orelse return PrintLine.True) {
            format.Parser.Result.Ok => |node| node.Field,
            format.Parser.Result.Error => |err| return parser.reportSyntaxError(err),
        };

        switch (tf.match(top_field_node.ident.str)) {
            tf.case("pokemons") => {
                const pokemon_index = try parser.expectIndex(usize, math.maxInt(usize));
                const pokemon_field_node = try parser.expect(format.Node.Kind.Field);
                const pf = fun.match.StringSwitch([][]const u8{
                    "stats",
                    "evos",
                });

                switch (pf.match(pokemon_field_node.ident.str)) {
                    pf.case("stats") => {
                        const stats_field_node = try parser.expect(format.Node.Kind.Field);
                        const sf = fun.match.StringSwitch([][]const u8{
                            "hp",
                            "attack",
                            "defense",
                            "speed",
                            "sp_attack",
                            "sp_defense",
                        });

                        const match = sf.match(stats_field_node.ident.str);
                        const value = switch (match) {
                            sf.case("hp") => try parser.expectIntValue(u8),
                            sf.case("attack") => try parser.expectIntValue(u8),
                            sf.case("defense") => try parser.expectIntValue(u8),
                            sf.case("speed") => try parser.expectIntValue(u8),
                            sf.case("sp_attack") => try parser.expectIntValue(u8),
                            sf.case("sp_defense") => try parser.expectIntValue(u8),
                            else => return PrintLine.True,
                        };

                        const entry = try pokemons.getOrPut(pokemon_index);
                        const pokemon = &entry.kv.value;
                        if (!entry.found_existing) {
                            pokemon.* = Pokemon{
                                .hp = null,
                                .attack = null,
                                .defense = null,
                                .speed = null,
                                .sp_attack = null,
                                .sp_defense = null,
                                .evos = EvoMap.init(pokemons.allocator),
                            };
                        }

                        switch (match) {
                            sf.case("hp") => pokemon.hp = value,
                            sf.case("attack") => pokemon.attack = value,
                            sf.case("defense") => pokemon.defense = value,
                            sf.case("speed") => pokemon.speed = value,
                            sf.case("sp_attack") => pokemon.sp_attack = value,
                            sf.case("sp_defense") => pokemon.sp_defense = value,
                            else => unreachable,
                        }

                        return PrintLine.False;
                    },
                    pf.case("evos") => {
                        const evo_index = try parser.expectIndex(usize, math.maxInt(usize));
                        const evo_field_node = try parser.expect(format.Node.Kind.Field);
                        const ef = fun.match.StringSwitch([][]const u8{
                            "target",
                            "HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                            "1HACK TO RESOLVE https://github.com/ziglang/zig/issues/1608",
                        });

                        switch (ef.match(evo_field_node.ident.str)) {
                            ef.case("target") => {
                                const entry = try pokemons.getOrPut(pokemon_index);
                                const pokemon = &entry.kv.value;
                                if (!entry.found_existing) {
                                    pokemon.* = Pokemon{
                                        .hp = null,
                                        .attack = null,
                                        .defense = null,
                                        .speed = null,
                                        .sp_attack = null,
                                        .sp_defense = null,
                                        .evos = EvoMap.init(pokemons.allocator),
                                    };
                                }

                                const value = try parser.expectIntValue(usize);
                                _ = try pokemon.evos.put(evo_index, value);

                                return PrintLine.True;
                            },
                            else => {},
                        }
                    },
                    else => {},
                }
            },
            else => {},
        }

        return PrintLine.True;
    }

    fn expect(parser: *Parser, comptime kind: format.Node.Kind) !@field(format.Node, @tagName(kind)) {
        switch (parser.parser.next().?) {
            format.Parser.Result.Ok => |node| switch (node) {
                kind => |res| return res,
                else => return parser.reportNodeError(node),
            },
            format.Parser.Result.Error => |err| return parser.reportSyntaxError(err),
        }
    }

    fn expectIndex(parser: *Parser, comptime Int: type, bound: Int) !Int {
        const index_node = try parser.expect(format.Node.Kind.Index);
        return try parser.parseInt(Int, bound, index_node.int);
    }

    fn expectIntValue(parser: *Parser, comptime Int: type) !Int {
        const value_node = try parser.expect(format.Node.Kind.Value);
        return try parser.parseInt(Int, math.maxInt(Int), value_node.value);
    }

    fn expectEnumValue(parser: *Parser, comptime Enum: type) !Enum {
        const value_node = try parser.expect(format.Node.Kind.Value);
        const token = value_node.value;
        const value = mem.trim(u8, token.str, "\t ");

        return stringToEnum(Enum, value) orelse {
            const fields = @typeInfo(Enum).Enum.fields;
            const column = token.index(parser.parser.tok.str) + 1;
            parser.warning(column, "expected ");

            inline for (fields) |field, i| {
                const rev_i = (fields.len - 1) - i;
                debug.warn("'{}'", field.name);
                if (rev_i == 1)
                    debug.warn(" or ");
                if (rev_i > 1)
                    debug.warn(", ");
            }

            debug.warn(" found '{}'\n", value);
            return error.NotInEnum;
        };
    }

    fn expectBoolValue(parser: *Parser) !bool {
        const value_node = try parser.expect(format.Node.Kind.Value);
        const bs = fun.match.StringSwitch([][]const u8{
            "true",
            "false",
        });

        return switch (bs.match(value_node.value.str)) {
            bs.case("true") => true,
            bs.case("false") => false,
            else => {
                const column = value_node.value.index(parser.parser.tok.str) + 1;
                parser.warning(column, "expected 'true' or 'false' found {}", value_node.value.str);
                return error.NotBool;
            }
        };
    }

    fn parseInt(parser: *const Parser, comptime Int: type, bound: Int, token: format.Token) !Int {
        const column = token.index(parser.parser.tok.str) + 1;
        const str = mem.trim(u8, token.str, "\t ");
        overflow: {
            return fmt.parseUnsigned(Int, str, 10) catch |err| {
                switch (err) {
                    error.Overflow => break :overflow,
                    error.InvalidCharacter => {
                        parser.warning(column, "{} is not an number", str);
                        return err;
                    },
                }
            };
        }

        parser.warning(column, "{} is not within the bound {}", str, bound);
        return error.Overflow;
    }

    fn reportNodeError(parser: *const Parser, node: format.Node) error{InvalidNode} {
        const first = node.first();
        const i = first.index(parser.parser.tok.str);
        var tok = format.Tokenizer.init(parser.parser.tok.str[0..i]);

        parser.warning(i + 1, "'");
        while (tok.next()) |token|
            debug.warn("{}", token.str);

        debug.warn("' ");
        switch (node) {
            format.Node.Kind.Field => |field| debug.warn("does not have field '{}'\n", field.ident.str),
            format.Node.Kind.Index => |index| debug.warn("cannot be indexed at '{}'\n", index.int.str),
            format.Node.Kind.Value => |value| debug.warn("cannot be set to '{}'\n", value.value.str),
        }

        return error.InvalidNode;
    }

    fn reportSyntaxError(parser: *const Parser, err: format.Parser.Error) error{SyntaxError} {
        parser.warning(err.found.index(parser.parser.tok.str), "expected ");
        for (err.expected) |id, i| {
            const rev_i = (err.expected.len - 1) - i;
            debug.warn("{}", id.str());
            if (rev_i == 1)
                debug.warn(" or ");
            if (rev_i > 1)
                debug.warn(", ");
        }

        debug.warn(" found {}", err.found.str);
        return error.SyntaxError;
    }

    fn warning(parser: *const Parser, col: usize, comptime f: []const u8, a: ...) void {
        debug.warn("(stdin):{}:{}: warning: ", parser.line, col);
        debug.warn(f, a);
    }
};

fn readLine(stream: var, buf: *std.Buffer) ![]u8 {
    while (true) {
        const byte = try stream.readByte();
        switch (byte) {
            '\n' => return buf.toSlice(),
            else => try buf.appendByte(byte),
        }
    }
}

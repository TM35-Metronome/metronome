//! build: zig build-exe tools/asm-macros-to-zig-struct.zig --pkg-begin util src/common/util.zig --pkg-end
//! usage: cat macros.s | asm-macros-to-zig-struct > file.zig
//!
//! Reads assembly macros from stdin an converts them to
//! Zig structs. The macros have to be in the following
//! format:
//! ```
//! .macro Return2 a, b
//! .hword  0x3, \a, \b
//! .endm
//! ```
//!
//! The above will generate:
//! ```
//! pub const Command = packed struct {
//!     tag: Kind,
//!     data: packed union {
//!         Return2: Return2,
//!     },
//!     pub const Kind = packed enum(u16) {
//!         Return2 = lu16.init(0x3).valueNative(),
//!     };
//!     pub const Return2 = packed struct {
//!         a: lu16,
//!         b: lu16,
//!     };
//! };
//! ```
//! This script was used to generate `gen4/script.zig`

const std = @import("std");
const util = @import("util");

const debug = std.debug;
const heap = std.heap;
const mem = std.mem;

pub fn main() !void {
    var stdio_buf = util.getStdIo();
    const stdio = stdio_buf.streams();
    defer stdio_buf.err.flush() catch {};
    defer stdio_buf.out.flush() catch {};

    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    defer arena.deinit();

    const a = &arena.allocator;

    const Command = struct {
        name: []const u8,
        optcode: []const u8,
        curr_field_type: []const u8,
        fields: std.ArrayList(Field),

        const Field = struct {
            name: []const u8,
            type: []const u8,
        };
    };

    const State = union(enum) {
        Start,
        LookForOptCode: []const u8,
        LookForFields: Command,
    };

    var fifo = util.read.Fifo(.Dynamic).init(a);
    var commands = std.ArrayList(Command).init(a);
    var state: State = .Start;

    next_line: while (try util.read.line(stdio.in, &fifo)) |line| {
        const trimmed = mem.trim(u8, line, " \r\n");
        errdefer debug.warn("{}\n", .{trimmed});
        if (trimmed.len == 0)
            continue;

        var it = mem.tokenize(trimmed, " \t,");
        curr_line: while (true) switch (state) {
            .Start => {
                const macro = it.next() orelse return error.Error;
                const name = it.next() orelse return error.Error;
                if (mem.startsWith(u8, macro, "@"))
                    continue :next_line;
                if (!mem.eql(u8, macro, ".macro"))
                    return error.Error;

                state = State{ .LookForOptCode = try mem.dupe(a, u8, name) };
                continue :next_line;
            },
            .LookForOptCode => |name| {
                const hword = it.next() orelse return error.Error;
                const optcode = it.next() orelse return error.Error;
                if (!mem.eql(u8, hword, ".hword"))
                    return error.Error;
                if (!mem.startsWith(u8, optcode, "0x"))
                    return error.Error;

                state = State{
                    .LookForFields = Command{
                        .name = name,
                        .optcode = try mem.dupe(a, u8, optcode),
                        .curr_field_type = "lu16",
                        .fields = std.ArrayList(Command.Field).init(a),
                    },
                };
                continue :curr_line;
            },
            .LookForFields => |*command| {
                const next = it.next() orelse continue :next_line;
                if (mem.eql(u8, next, ".endm")) {
                    try commands.append(command.*);
                    state = .Start;
                    continue :next_line;
                }
                if (mem.eql(u8, next, ".word")) {
                    command.curr_field_type = "lu32";
                    continue :curr_line;
                }
                if (mem.eql(u8, next, ".hword")) {
                    command.curr_field_type = "lu16";
                    continue :curr_line;
                }
                if (mem.eql(u8, next, ".byte")) {
                    command.curr_field_type = "u8";
                    continue :curr_line;
                }
                if (!mem.startsWith(u8, next, "\\"))
                    continue :curr_line;

                try command.fields.append(Command.Field{
                    .name = try mem.dupe(a, u8, next[1..]),
                    .type = command.curr_field_type,
                });
                continue :curr_line;
            },
        };

        line_buf.resize(0) catch unreachable;
    }

    try stdio.out.writeAll(
        \\pub const Command = packed struct {
        \\tag: Kind,
        \\data: extern union {
        \\
    );
    for (commands.items) |command|
        try stdio.out.print("{}: {},\n", .{ command.name, command.name });

    try stdio.out.writeAll(
        \\},
        \\pub const Kind = packed enum(u16) {
        \\
    );
    for (commands.items) |command|
        try stdio.out.print("{} = lu16.init({}).value(),\n", .{ command.name, command.optcode });

    try stdio.out.writeAll(
        \\};
        \\
    );
    for (commands.items) |command| {
        try stdio.out.print("pub const {} = packed struct {{\n", .{command.name});
        for (command.fields.items) |field| {
            var tokenizer = std.zig.Tokenizer.init(field.name);
            const token = tokenizer.next();
            switch (token.id) {
                .Identifier => try stdio.out.print("{}: {},\n", .{ field.name, field.type }),
                else => try stdio.out.print("@\"{}\": {},\n", .{ field.name, field.type }),
            }
        }
        try stdio.out.writeAll("};\n");
    }

    try stdio.out.writeAll(
        \\};
        \\
    );
}

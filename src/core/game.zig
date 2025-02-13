pub const Game = union(enum) {
    gen3: gen3.Game,
    gen4: gen4.Game,
    gen5: gen5.Game,

    pub fn fromFile(file: std.fs.File, allocator: std.mem.Allocator) !Game {
        if (gen3.Game.fromFile(file, allocator)) |game| {
            return Game{ .gen3 = game };
        } else |_| {}

        try file.seekTo(0);

        const nds_rom = try allocator.create(rom.nds.Rom);
        errdefer allocator.destroy(nds_rom);

        nds_rom.* = try rom.nds.Rom.fromFile(file, allocator);
        errdefer nds_rom.deinit();

        if (gen4.Game.fromRom(allocator, nds_rom)) |game| {
            return Game{ .gen4 = game };
        } else |_| {}

        return Game{ .gen5 = try gen5.Game.fromRom(allocator, nds_rom) };
    }

    pub fn data(game: Game) []const u8 {
        return switch (game) {
            .gen3 => |g| g.data,
            .gen4 => |g| g.rom.data.items,
            .gen5 => |g| g.rom.data.items,
        };
    }

    pub fn apply(game: *Game) !void {
        switch (game.*) {
            inline else => |*g| try g.apply(),
        }
    }

    pub fn write(game: Game, writer: anytype) !void {
        switch (game) {
            .gen3 => |g| try g.write(writer),
            .gen4 => |g| try g.rom.write(writer),
            .gen5 => |g| try g.rom.write(writer),
        }
    }

    pub fn deinit(game: Game) void {
        switch (game) {
            .gen3 => |g| g.deinit(),
            .gen4 => |g| {
                g.rom.deinit();
                g.deinit();
                g.allocator.destroy(g.rom);
            },
            .gen5 => |g| {
                g.rom.deinit();
                g.deinit();
                g.allocator.destroy(g.rom);
            },
        }
    }
};

fn fuzzFromFile(_: void, input: []const u8) !void {
    const cwd = std.fs.cwd();
    const input_file = try cwd.createFile(".zig-cache/fuzz_game_from_file.input", .{
        .read = true,
    });
    defer input_file.close();
    const output_file = try cwd.createFile(".zig-cache/fuzz_game_from_file.output", .{});
    defer output_file.close();

    try input_file.writeAll(input);
    try input_file.seekTo(0);

    const game = Game.fromFile(input_file, std.testing.allocator) catch return;
    defer game.deinit();

    try game.write(output_file.writer());
}

test "Game.fromFile fuzz" {
    try std.testing.fuzz({}, fuzzFromFile, .{});
}

test {
    _ = gen3;
    _ = gen4;
    _ = gen5;
    _ = rom;
}

const gen3 = @import("gen3.zig");
const gen4 = @import("gen4.zig");
const gen5 = @import("gen5.zig");
const rom = @import("rom.zig");
const std = @import("std");

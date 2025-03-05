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

pub fn fuzzCorpus(allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    var corpus = std.ArrayList([]const u8).init(allocator);
    errdefer corpus.deinit();

    const test_rom = (try readTestRom(allocator)) orelse return corpus;
    errdefer allocator.free(test_rom);

    try corpus.append(test_rom);
    return corpus;
}

pub fn readTestRom(allocator: std.mem.Allocator) !?[]u8 {
    const rom_path = build_options.rom_path orelse return null;
    return try std.fs.cwd().readFileAlloc(allocator, rom_path, std.math.maxInt(usize));
}

fn fuzzFromFile(_: void, input: []const u8) !void {
    const cwd = std.fs.cwd();
    const input_file = try cwd.createFile(".zig-cache/fuzz_game_from_file.input", .{
        .read = true,
    });
    defer input_file.close();

    try input_file.writeAll(input);
    try input_file.seekTo(0);

    var game = Game.fromFile(input_file, std.testing.allocator) catch return;
    defer game.deinit();

    try game.apply();
    try game.write(std.io.null_writer);
}

test "Game.fromFile fuzz" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.fuzz({}, fuzzFromFile, .{
        .corpus = (try fuzzCorpus(arena.allocator())).items,
    });
}

test {
    _ = build_options;
    _ = gen3;
    _ = gen4;
    _ = gen5;
    _ = rom;
}

const build_options = @import("build_options");
const gen3 = @import("gen3.zig");
const gen4 = @import("gen4.zig");
const gen5 = @import("gen5.zig");
const rom = @import("rom.zig");
const std = @import("std");

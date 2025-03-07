const clap = @import("clap");
const core = @import("core");
const std = @import("std");
const util = @import("util");

const debug = std.debug;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const mem = std.mem;
const os = std.os;

const rom = core.rom;

const path = fs.path;

const nds = rom.nds;

const Program = @This();

allocator: mem.Allocator,
in: []const u8,
out: []const u8,

pub const main = util.generateMain(Program);
pub const version = "0.0.0";
pub const description =
    \\Reads a Nintendo DS rom and extract its file system into a folder.
    \\
;

pub const parsers = .{
    .ROM = clap.parsers.string,
    .FILE = clap.parsers.string,
};

pub const params = clap.parseParamsComptime(
    \\-h, --help
    \\        Display this help text and exit.
    \\
    \\-o, --output <FILE>
    \\        Override destination path.
    \\
    \\-v, --version
    \\        Output version information and exit.
    \\
    \\<ROM>
    \\
);

pub fn init(allocator: mem.Allocator, args: anytype) !Program {
    const pos = args.positionals[0];
    const file_name = pos orelse return error.MissingFile;

    const out = args.args.output orelse
        try fmt.allocPrint(allocator, "{s}.output", .{path.basename(file_name)});

    return Program{
        .allocator = allocator,
        .in = file_name,
        .out = out,
    };
}

pub fn run(
    program: *Program,
    comptime Reader: type,
    comptime Writer: type,
    stdio: util.CustomStdIoStreams(Reader, Writer),
) anyerror!void {
    _ = stdio;

    const allocator = program.allocator;
    const cwd = fs.cwd();

    const rom_file = try cwd.openFile(program.in, .{});
    defer rom_file.close();

    var nds_rom = try nds.Rom.fromFile(rom_file, allocator);

    try cwd.makePath(program.out);

    // All dir instances should actually be `const`, but `Dir.close` takes mutable pointer, so we
    // can't actually do that...
    var out_dir = try cwd.openDir(program.out, .{});
    defer out_dir.close();

    try out_dir.makeDir("arm9_overlays");
    try out_dir.makeDir("arm7_overlays");
    try out_dir.makeDir("root");

    var arm9_overlays_dir = try out_dir.openDir("arm9_overlays", .{});
    defer arm9_overlays_dir.close();
    var arm7_overlays_dir = try out_dir.openDir("arm7_overlays", .{});
    defer arm7_overlays_dir.close();
    var root_dir = try out_dir.openDir("root", .{});
    defer root_dir.close();

    try out_dir.writeFile(.{
        .sub_path = "arm9",
        .data = nds_rom.arm9(),
    });
    if (rom.nds.blz.decode(allocator, nds_rom.arm9())) |arm9| {
        try out_dir.writeFile(.{
            .sub_path = "arm9_decoded",
            .data = arm9,
        });
    } else |_| {}

    try out_dir.writeFile(.{
        .sub_path = "arm7",
        .data = nds_rom.arm7(),
    });
    // try out_dir.writeFile("nitro_footer", nds_rom.nitroFooter());
    if (nds_rom.banner()) |banner|
        try out_dir.writeFile(.{
            .sub_path = "banner",
            .data = mem.asBytes(banner),
        });

    const file_system = nds_rom.fileSystem();
    try writeOverlays(allocator, arm9_overlays_dir, file_system, nds_rom.arm9OverlayTable());
    try writeOverlays(allocator, arm7_overlays_dir, file_system, nds_rom.arm7OverlayTable());

    try writeFs(root_dir, file_system, nds.fs.root);
}

fn writeFs(dir: fs.Dir, file_system: nds.fs.Fs, folder: nds.fs.Dir) anyerror!void {
    var it = file_system.iterate(folder);
    while (it.next()) |entry| {
        switch (entry.handle) {
            .file => |file| try dir.writeFile(.{
                .sub_path = entry.name,
                .data = file_system.fileData(file),
            }),
            .dir => |sub_folder| {
                try dir.makeDir(entry.name);
                var sub_dir = try dir.openDir(entry.name, .{});
                defer sub_dir.close();

                try writeFs(sub_dir, file_system, sub_folder);
            },
        }
    }
}

fn writeOverlays(
    allocator: mem.Allocator,
    dir: fs.Dir,
    file_system: nds.fs.Fs,
    overlays: []align(1) const nds.Overlay,
) !void {
    var buf: [fs.max_path_bytes]u8 = undefined;

    for (overlays, 0..) |*overlay, i| {
        try dir.writeFile(.{
            .sub_path = fmt.bufPrint(&buf, "overlay{}", .{i}) catch unreachable,
            .data = mem.asBytes(overlay),
        });

        const data = file_system.fileData(.{ .i = overlay.file_id });
        if (nds.blz.decode(allocator, data)) |d| {
            std.log.info("Decompressed overlay {}", .{i});
            try dir.writeFile(.{
                .sub_path = fmt.bufPrint(&buf, "file{}", .{i}) catch unreachable,
                .data = d,
            });
        } else |_| {
            try dir.writeFile(.{
                .sub_path = fmt.bufPrint(&buf, "file{}", .{i}) catch unreachable,
                .data = data,
            });
        }
    }
}

const std = @import("std");

const formats = @import("formats.zig");
const int = @import("../int.zig");
const nds = @import("../nds.zig");

const debug = std.debug;
const fmt = std.fmt;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const os = std.os;
const testing = std.testing;

const lu16 = int.lu16;
const lu32 = int.lu32;

pub const Dir = struct { i: u16 };
pub const File = struct { i: u32 };
pub const Handle = union(enum) {
    file: File,
    dir: Dir,
};

pub const root = Dir{ .i = 0 };

pub const Fs = struct {
    fnt_main: []align(1) FntMainEntry,
    fnt: []u8,
    fat: []align(1) nds.Range,
    data: []u8,

    pub fn openNarc(fs: nds.fs.Fs, dir: Dir, path: []const u8) !nds.fs.Fs {
        const file = try fs.openFileData(dir, path);
        return try nds.fs.Fs.fromNarc(file);
    }

    pub fn openFileData(fs: Fs, dir: Dir, path: []const u8) ![]u8 {
        const file = try fs.openFile(dir, path);
        return fs.fileData(file);
    }

    pub fn openFile(fs: Fs, dir: Dir, path: []const u8) !File {
        const handle = try fs.open(dir, path);
        if (handle == .dir)
            return error.DoesntExist;
        return handle.file;
    }

    pub fn openDir(fs: Fs, dir: Dir, path: []const u8) !Dir {
        const handle = try fs.open(dir, path);
        if (handle == .file)
            return error.DoesntExist;
        return handle.dir;
    }

    pub fn open(fs: Fs, dir: Dir, path: []const u8) !Handle {
        var handle = Handle{ .dir = dir };
        const relative = if (mem.startsWith(u8, path, "/")) blk: {
            handle.dir = root; // Set handle to root
            break :blk path[1..];
        } else path;

        var split = mem.split(u8, relative, "/");
        while (split.next()) |name| {
            switch (handle) {
                .file => return error.DoesntExist,
                .dir => |d| {
                    var it = fs.iterate(d);
                    handle = it.find(name) orelse return error.DoesntExist;
                },
            }
        }

        return handle;
    }

    pub fn iterate(fs: Fs, dir: Dir) Iterator {
        const fnt_entry = fs.fnt_main[dir.i];
        const file_handle = fnt_entry.first_file_handle.value();
        const offset = fnt_entry.offset_to_subtable.value();
        debug.assert(fs.fnt.len >= offset);

        return Iterator{
            .file_handle = file_handle,
            .fnt_sub_table = fs.fnt[offset..],
        };
    }

    pub fn fileAs(fs: Fs, file: File, comptime T: type) !*align(1) T {
        const data = fs.fileData(file);
        if (@sizeOf(T) > data.len)
            return error.FileToSmall;
        return @ptrCast(*align(1) T, data.ptr);
    }

    pub fn fileData(fs: Fs, file: File) []u8 {
        const f = fs.fat[file.i];
        return fs.data[f.start.value()..f.end.value()];
    }

    /// Reinterprets the file system as a slice of T. This can only be
    /// done if the file system is arranged in a certain way:
    /// * All files must have the same size of `@sizeOf(T)`
    /// * All files must be arranged sequentially in memory with no padding
    ///   and in the same order as the `fat`.
    ///
    /// This function is useful when working with roms that stores arrays
    /// of structs in narc file systems.
    pub fn toSlice(fs: Fs, first: usize, comptime T: type) ![]align(1) T {
        if (fs.fat.len == first)
            return &[0]T{};

        const start = fs.fat[first].start.value();
        var end = start;
        for (fs.fat[first..]) |fat| {
            const fat_start = fat.start.value();
            if (fat_start != end)
                return error.FsIsNotSequential;
            end += @sizeOf(T);
        }

        return mem.bytesAsSlice(T, fs.data[start..end]);
    }

    pub fn fromFnt(fnt: []u8, fat: []align(1) nds.Range, data: []u8) Fs {
        return Fs{
            .fnt_main = fntMainTable(fnt),
            .fnt = fnt,
            .fat = fat,
            .data = data,
        };
    }

    fn fntMainTable(fnt: []u8) []align(1) FntMainEntry {
        const rem = fnt.len % @sizeOf(FntMainEntry);
        const fnt_mains = mem.bytesAsSlice(FntMainEntry, fnt[0 .. fnt.len - rem]);
        const len = fnt_mains[0].parent_id.value();

        // TODO: We have no control over if roms we load are structured correctly, so this should
        //       not be an assert but an error.
        debug.assert(fnt_mains.len >= len and len <= 4096 and len != 0);
        return fnt_mains[0..len];
    }

    /// Get a file system from a narc file. This function can failed if the
    /// bytes are not a valid narc.
    pub fn fromNarc(data: []u8) !Fs {
        var fbs = io.fixedBufferStream(data);
        const reader = fbs.reader();
        const names = formats.Chunk.names;

        const header = try reader.readStruct(formats.Header);
        if (!mem.eql(u8, &header.chunk_name, names.narc))
            return error.InvalidNarcHeader;
        if (header.byte_order.value() != 0xFFFE)
            return error.InvalidNarcHeader;
        if (header.chunk_size.value() != 0x0010)
            return error.InvalidNarcHeader;
        if (header.following_chunks.value() != 0x0003)
            return error.InvalidNarcHeader;

        const fat_header = try reader.readStruct(formats.FatChunk);
        if (!mem.eql(u8, &fat_header.header.name, names.fat))
            return error.InvalidNarcHeader;

        const fat_size = fat_header.header.size.value() - @sizeOf(formats.FatChunk);
        const fat = mem.bytesAsSlice(nds.Range, data[fbs.pos..][0..fat_size]);
        fbs.pos += fat_size;

        const fnt_header = try reader.readStruct(formats.Chunk);
        const fnt_size = fnt_header.size.value() - @sizeOf(formats.Chunk);
        if (!mem.eql(u8, &fnt_header.name, names.fnt))
            return error.InvalidNarcHeader;

        const fnt = data[fbs.pos..][0..fnt_size];
        fbs.pos += fnt_size;

        const file_data_header = try reader.readStruct(formats.Chunk);
        if (!mem.eql(u8, &file_data_header.name, names.file_data))
            return error.InvalidNarcHeader;

        return Fs.fromFnt(fnt, fat, data[fbs.pos..]);
    }
};

pub const Iterator = struct {
    file_handle: u32,
    fnt_sub_table: []const u8,

    pub const Result = struct {
        handle: Handle,
        name: []const u8,
    };

    pub fn next(it: *Iterator) ?Result {
        var fbs = io.fixedBufferStream(it.fnt_sub_table);

        const reader = fbs.reader();
        const type_length = reader.readByte() catch return null;
        if (type_length == 0)
            return null;

        const length = type_length & 0x7F;
        const is_folder = (type_length & 0x80) != 0;
        const name = fbs.buffer[fbs.pos..][0..length];
        fbs.pos += length;

        const handle = if (is_folder) blk: {
            const read_id = reader.readIntLittle(u16) catch return null;
            debug.assert(read_id >= 0xF001 and read_id <= 0xFFFF);
            break :blk read_id & 0x0FFF;
        } else blk: {
            defer it.file_handle += 1;
            break :blk it.file_handle;
        };

        it.fnt_sub_table = fbs.buffer[fbs.pos..];
        return Result{
            .handle = if (is_folder)
                Handle{ .dir = .{ .i = @intCast(u16, handle) } }
            else
                Handle{ .file = .{ .i = handle } },
            .name = name,
        };
    }

    pub fn find(it: *Iterator, name: []const u8) ?Handle {
        while (it.next()) |entry| {
            if (mem.eql(u8, entry.name, name))
                return entry.handle;
        }
        return null;
    }
};

pub const FntMainEntry = extern struct {
    offset_to_subtable: lu32,
    first_file_handle: lu16,

    // For the first entry in main-table, the parent id is actually,
    // the total number of directories (See FNT Directory Main-Table):
    // http://problemkaputt.de/gbatek.htm#dscartridgenitroromandnitroarcfilesystems
    parent_id: lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 8);
    }
};

pub fn narcSize(file_count: usize, data_size: usize) usize {
    return @sizeOf(formats.Header) +
        @sizeOf(formats.FatChunk) +
        @sizeOf(nds.Range) * file_count +
        @sizeOf(formats.Chunk) * 2 +
        @sizeOf(FntMainEntry) +
        data_size;
}

pub const SimpleNarcBuilder = struct {
    stream: io.FixedBufferStream([]u8),

    pub fn init(buf: []u8, file_count: usize) SimpleNarcBuilder {
        var fbs = io.fixedBufferStream(buf);
        const writer = fbs.writer();
        writer.writeAll(&mem.toBytes(formats.Header.narc(0))) catch unreachable;
        writer.writeAll(&mem.toBytes(formats.FatChunk.init(@intCast(u16, file_count)))) catch unreachable;
        writer.context.pos += file_count * @sizeOf(nds.Range);
        writer.writeAll(&mem.toBytes(formats.Chunk{
            .name = formats.Chunk.names.fnt.*,
            .size = lu32.init(@sizeOf(formats.Chunk) + @sizeOf(FntMainEntry)),
        })) catch unreachable;
        writer.writeAll(&mem.toBytes(FntMainEntry{
            .offset_to_subtable = lu32.init(0),
            .first_file_handle = lu16.init(0),
            .parent_id = lu16.init(1),
        })) catch unreachable;
        writer.writeAll(&mem.toBytes(formats.Chunk{
            .name = formats.Chunk.names.file_data.*,
            .size = lu32.init(0),
        })) catch unreachable;

        return SimpleNarcBuilder{ .stream = writer.context.* };
    }

    pub fn fat(builder: SimpleNarcBuilder) []align(1) nds.Range {
        const res = builder.stream.buffer;
        const off = @sizeOf(formats.Header);
        const fat_header = mem.bytesAsValue(
            formats.FatChunk,
            res[off..][0..@sizeOf(formats.FatChunk)],
        );

        const size = fat_header.header.size.value();
        return mem.bytesAsSlice(
            nds.Range,
            res[off..][0..size][@sizeOf(formats.FatChunk)..],
        );
    }

    pub fn finish(builder: *SimpleNarcBuilder) []u8 {
        const res = builder.stream.buffer;
        var off: usize = 0;
        const header = mem.bytesAsValue(
            formats.Header,
            res[0..@sizeOf(formats.Header)],
        );

        off += @sizeOf(formats.Header);
        const fat_header = mem.bytesAsValue(
            formats.FatChunk,
            res[off..][0..@sizeOf(formats.FatChunk)],
        );

        off += fat_header.header.size.value();
        const fnt_header = mem.bytesAsValue(
            formats.Chunk,
            res[off..][0..@sizeOf(formats.Chunk)],
        );

        off += fnt_header.size.value();
        const file_header = mem.bytesAsValue(
            formats.Chunk,
            res[off..][0..@sizeOf(formats.Chunk)],
        );

        header.file_size = lu32.init(@intCast(u32, res.len));
        file_header.size = lu32.init(@intCast(u32, res.len - off));
        return res;
    }
};

pub const Builder = struct {
    fnt_main: std.ArrayList(FntMainEntry),
    fnt_sub: std.ArrayList(u8),
    fat: std.ArrayList(nds.Range),
    file_bytes: u32,

    pub fn init(allocator: mem.Allocator) !Builder {
        var fnt_main = std.ArrayList(FntMainEntry).init(allocator);
        var fnt_sub = std.ArrayList(u8).init(allocator);
        errdefer fnt_main.deinit();
        errdefer fnt_sub.deinit();

        try fnt_main.append(.{
            .offset_to_subtable = lu32.init(0),
            .first_file_handle = lu16.init(0),
            .parent_id = lu16.init(1),
        });
        try fnt_sub.append(0);

        return Builder{
            .fnt_main = fnt_main,
            .fnt_sub = fnt_sub,
            .fat = std.ArrayList(nds.Range).init(allocator),
            .file_bytes = 0,
        };
    }

    pub fn createTree(b: *Builder, dir: Dir, path: []const u8) !Dir {
        var curr = dir;
        const relative = if (mem.startsWith(u8, path, "/")) blk: {
            curr = root; // Set handle to root
            break :blk path[1..];
        } else path;

        var split = mem.split(u8, relative, "/");
        while (split.next()) |name|
            curr = try b.createDir(curr, name);

        return curr;
    }

    pub fn createDir(b: *Builder, dir: Dir, path: []const u8) !Dir {
        const fs = b.toFs();
        const dir_name = std.fs.path.basenamePosix(path);
        const parent = if (std.fs.path.dirnamePosix(path)) |parent_path|
            try fs.openDir(dir, parent_path)
        else
            dir;

        if (fs.openDir(parent, dir_name)) |handle| {
            return handle;
        } else |err| switch (err) {
            error.DoesntExist => {},
        }

        const parent_entry = b.fnt_main.items[parent.i];
        const parent_offset = parent_entry.offset_to_subtable.value();
        const handle = @intCast(u16, b.fnt_main.items.len);

        var buf: [1024]u8 = undefined;
        var fbs = io.fixedBufferStream(&buf);
        const len = @intCast(u7, dir_name.len);
        const kind = @as(u8, @boolToInt(true)) << 7;
        const id = @intCast(u16, 0xF000 | b.fnt_main.items.len);
        try fbs.writer().writeByte(kind | len);
        try fbs.writer().writeAll(dir_name);
        try fbs.writer().writeIntLittle(u16, id);

        const written = fbs.getWritten();
        try b.fnt_sub.ensureTotalCapacity(b.fnt_sub.items.len + written.len + 1);
        b.fnt_sub.insertSlice(parent_offset, written) catch unreachable;

        const offset = @intCast(u32, b.fnt_sub.items.len);
        b.fnt_sub.appendAssumeCapacity(0);

        for (b.fnt_main.items) |*entry| {
            const old_offset = entry.offset_to_subtable.value();
            const new_offset = old_offset + written.len;
            if (old_offset > parent_offset)
                entry.offset_to_subtable = lu32.init(@intCast(u32, new_offset));
        }

        try b.fnt_main.append(.{
            .offset_to_subtable = lu32.init(offset),
            .first_file_handle = parent_entry.first_file_handle,
            .parent_id = lu16.init(parent.i),
        });
        return Dir{ .i = handle };
    }

    pub fn createFile(b: *Builder, dir: Dir, path: []const u8, size: u32) !File {
        const fs = b.toFs();
        const file_name = std.fs.path.basenamePosix(path);
        const parent = if (std.fs.path.dirnamePosix(path)) |parent_path|
            try fs.openDir(dir, parent_path)
        else
            dir;

        if (fs.openFile(parent, file_name)) |handle| {
            return handle;
        } else |err| switch (err) {
            error.DoesntExist => {},
        }

        const parent_entry = b.fnt_main.items[parent.i];
        const parent_offset = parent_entry.offset_to_subtable.value();
        const handle = parent_entry.first_file_handle.value();

        var buf: [1024]u8 = undefined;
        var fbs = io.fixedBufferStream(&buf);
        const len = @intCast(u7, file_name.len);
        const kind = @as(u8, @boolToInt(false)) << 7;
        try fbs.writer().writeByte(kind | len);
        try fbs.writer().writeAll(file_name);

        const written = fbs.getWritten();
        try b.fnt_sub.ensureTotalCapacity(b.fnt_sub.items.len + written.len);
        b.fnt_sub.insertSlice(parent_offset, written) catch unreachable;

        for (b.fnt_main.items) |*entry, i| {
            const old_offset = entry.offset_to_subtable.value();
            const new_offset = old_offset + written.len;
            if (old_offset > parent_offset)
                entry.offset_to_subtable = lu32.init(@intCast(u32, new_offset));
            const old_file_handle = entry.first_file_handle.value();
            const new_file_handle = old_file_handle + 1;
            if (old_file_handle >= handle and parent.i != i)
                entry.first_file_handle = lu16.init(@intCast(u16, new_file_handle));
        }

        const start = b.file_bytes;
        try b.fat.insert(handle, nds.Range.init(start, start + size));

        b.file_bytes += size;
        return File{ .i = handle };
    }

    pub fn toFs(b: Builder) Fs {
        return Fs{
            .fnt_main = b.fnt_main.items,
            .fnt = b.fnt_sub.items,
            .fat = b.fat.items,
            .data = &[_]u8{},
        };
    }

    // Leaves builder in a none usable state. Only `deinit` is valid
    // after `finish`
    pub fn finish(builder: *Builder) !Fs {
        const sub_table_offset = builder.fnt_main.items.len * @sizeOf(FntMainEntry);
        for (builder.fnt_main.items) |*entry| {
            const new_offset = entry.offset_to_subtable.value() + sub_table_offset;
            entry.offset_to_subtable = lu32.init(@intCast(u32, new_offset));
        }

        const fnt_main_bytes = mem.sliceAsBytes(builder.fnt_main.items);
        try builder.fnt_sub.insertSlice(0, fnt_main_bytes);
        return Fs{
            .fnt_main = try builder.fnt_main.toOwnedSlice(),
            .fnt = try builder.fnt_sub.toOwnedSlice(),
            .fat = try builder.fat.toOwnedSlice(),
            .data = &[_]u8{},
        };
    }

    pub fn deinit(builder: Builder) void {
        builder.fnt_main.deinit();
        builder.fnt_sub.deinit();
        builder.fat.deinit();
    }
};

test "Builder" {
    const paths = [_][]const u8{
        "a/a",
        "a/b",
        "a/c/a",
        "b",
        "d/a",
    };
    var b = try Builder.init(testing.allocator);
    defer b.deinit();

    for (paths) |path| {
        if (std.fs.path.dirnamePosix(path)) |dir_path|
            _ = try b.createTree(root, dir_path);
        _ = try b.createFile(root, path, 0);
    }

    const fs = try b.finish();
    defer testing.allocator.free(fs.fnt_main);
    defer testing.allocator.free(fs.fnt);
    defer testing.allocator.free(fs.fat);

    for (paths) |path|
        _ = try fs.openFile(root, path);
    try testing.expectError(error.DoesntExist, fs.openFile(root, "a"));
    try testing.expectError(error.DoesntExist, fs.openFile(root, "a/c"));
    try testing.expectError(error.DoesntExist, fs.openFile(root, "a/c/b"));
}

const std = @import("std");

const formats = @import("formats.zig");
const int = @import("../int.zig");

const debug = std.debug;
const fmt = std.fmt;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const os = std.os;

const lu16 = int.lu16;
const lu32 = int.lu32;

pub const Fs = struct {
    fnt: []const u8,
    fat: []const FatEntry,
    data: []u8,

    pub fn lookup(fs: Fs, path: []const []const u8) ?[]u8 {
        const fat = fs.lookupFat(path) orelse return null;
        return fs.data[fat.start.value()..fat.end.value()];
    }

    pub fn lookupFat(fs: Fs, path: []const []const u8) ?FatEntry {
        var it = fs.iterate(0);
        outer: for (path) |folder, i| {
            const is_last = i == path.len - 1;

            while (it.next()) |entry| {
                switch (entry.kind) {
                    .file => {
                        if (is_last and mem.eql(u8, entry.name, folder))
                            return fs.fat[entry.id];
                    },
                    .folder => {
                        if (is_last or !mem.eql(u8, entry.name, folder))
                            continue;

                        it = fs.iterate(entry.id);
                        continue :outer; // We found the folder. Continue on to the next one
                    },
                }
            }
            return null;
        }
        unreachable;
    }

    pub fn iterate(fs: Fs, folder_id: u32) Iterator {
        const fnt_main_table = blk: {
            const rem = fs.fnt.len % @sizeOf(FntMainEntry);
            const fnt_mains = mem.bytesAsSlice(FntMainEntry, fs.fnt[0 .. fs.fnt.len - rem]);
            const len = fnt_mains[0].parent_id.value();

            debug.assert(fnt_mains.len >= len and len <= 4096 and len != 0);
            break :blk fnt_mains[0..len];
        };

        const fnt_entry = fnt_main_table[folder_id];
        const file_id = fnt_entry.first_file_id_in_subtable.value();
        const offset = fnt_entry.offset_to_subtable.value();
        debug.assert(fs.fnt.len >= offset);

        return Iterator{
            .file_id = file_id,
            .fnt_sub_table = fs.fnt[offset..],
        };
    }

    pub fn at(fs: Fs, i: usize) []u8 {
        const fat = fs.fat[i];
        return fs.data[fat.start.value()..fat.end.value()];
    }

    /// Reinterprets the file system as a slice of T. This can only be
    /// done if the file system is arranged in a certain way:
    /// * All files must have the same size of `@sizeOf(T)`
    /// * All files must be arranged sequentially in memory with no padding
    ///   and in the same order as the `fat`.
    ///
    /// This function is useful when working with roms that stores arrays
    /// of structs in narc file systems.
    pub fn toSlice(fs: Fs, comptime T: type) ![]T {
        if (fs.fat.len == 0)
            return &[0]T{};

        const start = fs.fat[0].start.value();
        var end = start;
        for (fs.fat) |fat| {
            const fat_start = fat.start.value();
            if (fat_start != end)
                return error.FsIsNotSequential;
            if (fat.size() != @sizeOf(T))
                return error.FsIsNotType;
            end = fat.end.value();
        }

        return mem.bytesAsSlice(T, fs.data[start..end]);
    }

    /// Get a file system from a narc file. This function can faile if the
    /// bytes are not a valid narc.
    pub fn fromNarc(data: []u8) !Fs {
        var fbs = io.fixedBufferStream(data);
        const stream = fbs.inStream();
        const names = formats.Chunk.names;

        const header = try stream.readStruct(formats.Header);
        if (!mem.eql(u8, &header.chunk_name, names.narc))
            return error.InvalidNarcHeader;
        if (header.byte_order.value() != 0xFFFE)
            return error.InvalidNarcHeader;
        if (header.chunk_size.value() != 0x0010)
            return error.InvalidNarcHeader;
        if (header.following_chunks.value() != 0x0003)
            return error.InvalidNarcHeader;

        const fat_header = try stream.readStruct(formats.FatChunk);
        if (!mem.eql(u8, &fat_header.header.name, names.fat))
            return error.InvalidNarcHeader;

        const fat_size = fat_header.header.size.value() - @sizeOf(formats.FatChunk);
        const fat = mem.bytesAsSlice(FatEntry, data[fbs.pos..][0..fat_size]);
        fbs.pos += fat_size;

        const fnt_header = try stream.readStruct(formats.Chunk);
        const fnt_size = fnt_header.size.value() - @sizeOf(formats.Chunk);
        if (!mem.eql(u8, &fnt_header.name, names.fnt))
            return error.InvalidNarcHeader;

        const fnt = data[fbs.pos..][0..fnt_size];
        fbs.pos += fnt_size;

        const file_data_header = try stream.readStruct(formats.Chunk);
        if (!mem.eql(u8, &file_data_header.name, names.file_data))
            return error.InvalidNarcHeader;

        return Fs{
            .fat = fat,
            .fnt = fnt,
            .data = data[fbs.pos..],
        };
    }
};

pub const Iterator = struct {
    file_id: u32,
    fnt_sub_table: []const u8,

    pub fn next(it: *Iterator) ?Entry {
        var fbs = io.fixedBufferStream(it.fnt_sub_table);

        const stream = fbs.inStream();
        const type_length = stream.readByte() catch return null;
        if (type_length == 0)
            return null;

        const length = type_length & 0x7F;
        const is_folder = (type_length & 0x80) != 0;
        const name = fbs.buffer[fbs.pos..][0..length];
        fbs.pos += length;

        const id = if (is_folder) blk: {
            const read_id = stream.readIntLittle(u16) catch return null;
            debug.assert(read_id >= 0xF001 and read_id <= 0xFFFF);
            break :blk read_id & 0x0FFF;
        } else blk: {
            defer it.file_id += 1;
            break :blk it.file_id;
        };

        it.fnt_sub_table = fbs.buffer[fbs.pos..];
        return Entry{
            .kind = if (is_folder) .folder else .file,
            .id = id,
            .name = name,
        };
    }
};

pub const Entry = struct {
    kind: Kind,
    id: u32,
    name: []const u8,

    pub const Kind = enum {
        file,
        folder,
    };
};

pub const FntMainEntry = packed struct {
    offset_to_subtable: lu32,
    first_file_id_in_subtable: lu16,

    // For the first entry in main-table, the parent id is actually,
    // the total number of directories (See FNT Directory Main-Table):
    // http://problemkaputt.de/gbatek.htm#dscartridgenitroromandnitroarcfilesystems
    parent_id: lu16,
};

pub const FatEntry = extern struct {
    start: lu32,
    end: lu32,

    pub fn init(offset: u32, s: u32) FatEntry {
        return FatEntry{
            .start = lu32.init(offset),
            .end = lu32.init(offset + s),
        };
    }

    pub fn size(entry: FatEntry) usize {
        return entry.end.value() - entry.start.value();
    }
};

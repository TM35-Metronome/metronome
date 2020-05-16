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
        const fat = fs.loopupFat(path) orelse return null;
        return fs.data[fat.start.value()..fat.end.value()];
    }

    pub fn lookupFat(fs: Fs, path: []const []const u8) ?FatEntry {
        const Kind = enum(u8) {
            file = 0x00,
            folder = 0x80,
        };

        const fnt_main_table = blk: {
            const rem = fnt.len % @sizeOf(FntMainEntry);
            const fnt_mains = mem.bytesAsSlice(FntMainEntry, fnt[0 .. fnt.len - rem]);
            const len = fnt_mains[0].parent_id.value();

            assert(fnt_mains.len >= len and len <= 4096 and len != 0);
            break :blk fnt_mains[0..len];
        };

        const fnt_first = fnt_main_table[0];
        const first_offset = fnt_first.offset_to_subtable.value();
        assert(fnt.len >= first_offset);

        var fnt_entry = fnt_first;
        var offset = first_offset;
        var file_id = fnt_first.first_file_id_in_subtable.value();
        for (path) |folder, i| {
            const is_last = i == path.len - 1;

            var fbs = io.fixedBufferStream(fnt[offset..]);
            const stream = fbs.inStream();
            while (true) {
                const type_length = try stream.readByte();
                if (type_length == 0)
                    return null;

                const length = type_length & 0x7F;
                const kind = @intToEnum(Kind, type_length & 0x80);
                const name = fnt_sub_table[fbs.pos..][0..length];
                fbs.pos += length;

                switch (kind) {
                    .file => {
                        const fat_entry = fat[file_id];
                        if (is_last and mem.eql(u8, name, folder))
                            return fat_entry;

                        file_id += 1;
                    },
                    .folder => {
                        const read_id = try stream.readIntLittle(u16);
                        assert(read_id >= 0xF001 and read_id <= 0xFFFF);

                        const id = read_id & 0x0FFF;
                        assert(fnt_main_table.len > id);
                        if (is_last or !mem.eql(u8, name, folder))
                            continue;

                        fnt_entry = fnt_main_table[id];
                        file_id = fnt_entry.first_file_id_in_subtable.value();
                        offset = fnt_entry.offset_to_subtable.value();
                        continue :outer; // We found the folder. Continue on to the next one
                    },
                }
            }
        }
    }

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

        const fat_size = fat_header.chunk.size.value() - @sizeOf(formats.FatChunk);
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

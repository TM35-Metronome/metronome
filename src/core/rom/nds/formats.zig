pub const Header = extern struct {
    chunk_name: [4]u8,
    byte_order: u16,
    version: u16,
    file_size: u32,
    chunk_size: u16,
    following_chunks: u16,

    pub fn narc(file_size: u32) Header {
        return Header{
            .chunk_name = Chunk.names.narc.*,
            .byte_order = 0xFFFE,
            .version = 0x0100,
            .file_size = file_size,
            .chunk_size = @sizeOf(Header),
            .following_chunks = 0x0003,
        };
    }

    comptime {
        std.debug.assert(@sizeOf(@This()) == 16);
    }
};

pub const Chunk = extern struct {
    name: [4]u8,
    size: u32,

    pub const names = struct {
        pub const narc = "NARC";
        pub const fat = "BTAF";
        pub const fnt = "BTNF";
        pub const file_data = "GMIF";
    };

    comptime {
        std.debug.assert(@sizeOf(@This()) == 8);
    }
};

pub const FatChunk = extern struct {
    header: Chunk,
    file_count: u16,
    reserved: u16 = 0,

    pub fn init(file_count: u16) FatChunk {
        return .{
            .header = .{
                .name = Chunk.names.fat.*,
                .size = @intCast(@sizeOf(FatChunk) + @sizeOf(nds.Range) * file_count),
            },
            .file_count = file_count,
        };
    }

    comptime {
        std.debug.assert(@sizeOf(@This()) == 12);
    }
};

test {
    _ = nds;
}

const nds = @import("../nds.zig");
const std = @import("std");

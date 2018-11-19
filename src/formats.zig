const fun = @import("../lib/fun-with-zig/src/index.zig");

const lu16 = fun.platform.lu16;
const lu32 = fun.platform.lu32;

pub const Header = packed struct {
    chunk_name: [4]u8,
    byte_order: lu16,
    version: lu16,
    file_size: lu32,
    chunk_size: lu16,
    following_chunks: lu16,

    pub fn narc(file_size: u32) Header {
        return Header{
            .chunk_name = Chunk.names.narc,
            .byte_order = lu16.init(0xFFFE),
            .version = lu16.init(0x0100),
            .file_size = lu32.init(file_size),
            .chunk_size = lu16.init(@sizeOf(Header)),
            .following_chunks = lu16.init(0x0003),
        };
    }
};

pub const Chunk = packed struct {
    name: [4]u8,
    size: lu32,

    const names = struct {
        const narc = "NARC";
        const fat = "BTAF";
        const fnt = "BTNF";
        const file_data = "GMIF";
    };
};

pub const FatChunk = packed struct {
    header: Chunk,
    file_count: lu16,
    reserved: lu16,
};

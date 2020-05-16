const std = @import("std");

const blz = @import("nds/blz.zig");
const overlay = @import("nds/overlay.zig");
const int = @import("int.zig");

const debug = std.debug;
const generic = fun.generic;
const heap = std.heap;
const io = std.io;
const mem = std.mem;
const os = std.os;

const lu16 = int.lu16;
const lu32 = int.lu32;

pub const fs = @import("nds/fs.zig");

pub const Banner = @import("nds/banner.zig").Banner;
pub const Header = @import("nds/header.zig").Header;
pub const Overlay = overlay.Overlay;

test "nds" {
    _ = @import("nds/banner.zig");
    _ = @import("nds/blz.zig");
    _ = @import("nds/formats.zig");
    _ = @import("nds/fs.zig");
    _ = @import("nds/header.zig");
    _ = @import("nds/overlay.zig");
    _ = @import("nds/test.zig");
}

pub const Rom = struct {
    allocator: *mem.Allocator,
    data: []u8,

    pub fn header(rom: Rom) *const Header {
        return mem.bytesAsValue(Header, rom.data[0..@sizeOf(Header)]);
    }

    pub fn banner(rom: Rom) *Banner {
        const h = rom.header();
        const offset = h.banner_offset.value();
        const bytes = rom.data[offset..][0..@sizeOf(Banner)];
        return mem.bytesAsValue(Banner, bytes);
    }

    /// Returns the arm9 section of the rom. Note here that this section could
    /// be encoded and therefor not very usefull. Call decodeArm9 before this
    /// if you need the section to be decoded.
    pub fn arm9(rom: Rom) []u8 {
        const h = rom.header();
        const offset = h.arm9_rom_offset.value();
        return rom.data[offset..][0..h.arm9_size.value()];
    }

    /// Decodes the arm9 section of the rom inplace. This function might not do anything
    /// if the section is already decoded.
    pub fn decodeArm9(rom: Rom) !void {
        // After arm9, there is 12 bytes that might be a nitro footer. If the first
        // 4 bytes are == 0xDEC00621, then it's a nitro_footer.
        // NOTE: This information was deduced from reading the source code for
        //       ndstool and EveryFileExplore. http://problemkaputt.de/gbatek.htm does
        //       not seem to have this information anywhere.
        unreachable; // TODO
    }

    pub fn arm7(rom: Rom) []u8 {
        const h = rom.header();
        const offset = h.arm7_rom_offset.value();
        return rom.data[offset..][0..h.arm7_size.value()];
    }

    pub fn arm9OverlayTable(rom: Rom) []Overlay {
        const h = rom.header();
        const offset = h.arm9_overlay_offset.value();
        const bytes = rom.data[offset..][0..h.arm9_overlay_size.value()];
        return mem.bytesAsSlice(Overlay, bytes);
    }

    pub fn arm7OverlayTable(rom: Rom) []Overlay {
        const h = rom.header();
        const offset = h.arm7_overlay_offset.value();
        const bytes = rom.data[offset..][0..h.arm7_overlay_size.value()];
        return mem.bytesAsSlice(Overlay, bytes);
    }

    pub fn fileSystem(rom: Rom) fs.Fs {
        const h = rom.header();
        const fnt_offset = h.fnt_offset.value();
        const fat_offset = h.fat_offset.value();
        const fnt_bytes = rom.data[offset..][0..h.fnt_size.value()];
        const fat_bytes = rom.data[offset..][0..h.fat_size.value()];
        return fs.Fs{
            .fnt = fnt_bytes,
            .fat = mem.bytesAsSlice(fs.FatEntry, bytes),
            .data = rom.data,
        };
    }

    pub fn fromFile(file: std.fs.File, allocator: *mem.Allocator) !Rom {
        const in_stream = file.inStream();
        const size = try file.getEndPos();
        try file.seekTo(0);

        const rom_data = try allocator.alloc(u8, size);
        errdefer allocator.free(rom_data);

        try in_stream.readNoEof(rom_data);
        const res = Rom{
            .allocator = allocator,
            .data = rom_data,
        };
        try res.header().validate();

        // TODO: we should validate that all the offsets and sizes are not
        //       out of bounds of the rom_data.
        return res;
    }

    pub fn writeToFile(rom: Rom, file: std.fs.File) !void {
        // The contract here is that once you have an `nds.Rom`, it should
        // always be a valid rom, so we just assert that this is true here
        // for sanity.
        res.header().validate() catch unreachable;
        try file.writeAll(rom.data);

        // TODO: Left over form old code. I need to make sure these fields are updated
        //       correctly during modification of the rom.
        // Update these fields when the rom size changes.
        // header.total_used_rom_size = lu32.init(@intCast(u32, mem.alignForward(try file.getPos(), 4)));
        // header.device_capacity = blk: {
        //     // Devicecapacity (Chipsize = 128KB SHL nn) (eg. 7 = 16MB)
        //     const size = header.total_used_rom_size.value();
        //     var device_cap: u6 = 0;
        //     while (@shlExact(@as(u64, 128000), device_cap) < size) : (device_cap += 1) {}
        //
        //     break :blk device_cap;
        // };

        // Update checksum when header changes. This is why we probably shouldn't expose the
        // header to the user directly.
        // header.header_checksum = lu16.init(header.calcChecksum());
    }

    pub fn deinit(rom: Rom) void {
        rom.allocator.free(rom.data);
    }
};

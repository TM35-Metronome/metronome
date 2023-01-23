const std = @import("std");

const int = @import("int.zig");
pub const blz = @import("nds/blz.zig");

const debug = std.debug;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const os = std.os;
const testing = std.testing;

const lu16 = int.lu16;
const lu32 = int.lu32;

pub const formats = @import("nds/formats.zig");
pub const fs = @import("nds/fs.zig");

pub const Banner = @import("nds/banner.zig").Banner;
pub const Header = @import("nds/header.zig").Header;

comptime {
    std.testing.refAllDecls(@This());
}

pub const Range = extern struct {
    start: lu32,
    end: lu32,

    pub fn init(start: usize, end: usize) Range {
        return .{
            .start = lu32.init(@intCast(u32, start)),
            .end = lu32.init(@intCast(u32, end)),
        };
    }

    pub fn len(r: Range) u32 {
        return r.end.value() - r.start.value();
    }

    pub fn slice(r: Range, s: anytype) mem.Span(@TypeOf(s)) {
        return s[r.start.value()..r.end.value()];
    }

    comptime {
        std.debug.assert(@sizeOf(@This()) == 8);
    }
};

pub const Slice = extern struct {
    start: lu32,
    len: lu32,

    pub fn fromSlice(data: []const u8, s: []const u8) Slice {
        const start = @ptrToInt(s.ptr) - @ptrToInt(data.ptr);
        return init(start, s.len);
    }

    pub fn init(start: usize, len: usize) Slice {
        return .{
            .start = lu32.init(@intCast(u32, start)),
            .len = lu32.init(@intCast(u32, len)),
        };
    }

    pub fn end(s: Slice) u32 {
        return s.start.value() + s.len.value();
    }

    pub fn slice(sl: Slice, s: anytype) mem.Span(@TypeOf(s)) {
        return s[sl.start.value()..sl.end()];
    }

    comptime {
        std.debug.assert(@sizeOf(@This()) == 8);
    }
};

pub const Overlay = extern struct {
    overlay_id: lu32,
    ram_address: lu32,
    ram_size: lu32,
    bss_size: lu32,
    static_initialiser_start_address: lu32,
    static_initialiser_end_address: lu32,
    file_id: lu32,
    reserved: [4]u8,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 32);
    }
};

pub const Rom = struct {
    data: std.ArrayList(u8),

    pub fn new(allocator: mem.Allocator, game_title: []const u8, gamecode: []const u8, opts: struct {
        arm9_size: u32 = 0,
        arm7_size: u32 = 0,
        files: u32 = 0,
    }) !Rom {
        var res = Rom{ .data = std.ArrayList(u8).init(allocator) };
        var writer = res.data.writer();
        errdefer res.deinit();

        var h = mem.zeroes(Header);
        mem.copy(u8, &h.game_title, game_title);
        mem.copy(u8, &h.gamecode, gamecode);
        h.secure_area_delay = lu16.init(0x051E);
        h.rom_header_size = lu32.init(0x4000);
        h.digest_ntr_region_offset = lu32.init(0x4000);
        h.title_id_rest = "\x00\x03\x00".*;

        try writer.writeAll(mem.asBytes(&h));
        try writer.writeAll("\x00" ** (0x4000 - @sizeOf(Header)));

        h.arm9.entry_address = lu32.init(0x2000000);
        h.arm9.ram_address = lu32.init(0x2000000);
        h.arm9.offset = lu32.init(@intCast(u32, res.data.len));
        h.arm9.size = lu32.init(opts.arm9_size);
        try writer.writeByteNTimes(0, h.arm9.size.value());
        try writer.writeByteNTimes(0, 0x8000 -| res.data.len);

        h.arm7.ram_address = lu32.init(0x2000000);
        h.arm7.entry_address = lu32.init(0x2000000);
        h.arm7.offset = lu32.init(@intCast(u32, res.data.len));
        h.arm7.size = lu32.init(opts.arm7_size);
        try writer.writeByteNTimes(0, h.arm7.size.value());

        h.fat.start = lu32.init(@intCast(u32, res.data.len));
        h.fat.len = lu32.init(opts.files * @sizeOf(Range));
        try writer.writeByteNTimes(0, h.fat.len.value());

        return res;
    }

    pub fn header(rom: Rom) *align(1) Header {
        return mem.bytesAsValue(Header, rom.data.items[0..@sizeOf(Header)]);
    }

    pub fn banner(rom: Rom) ?*align(1) Banner {
        const h = rom.header();
        const offset = h.banner_offset.value();
        if (offset == 0)
            return null;

        const bytes = rom.data.items[offset..][0..@sizeOf(Banner)];
        return mem.bytesAsValue(Banner, bytes);
    }

    /// Returns the arm9 section of the rom. Note here that this section could
    /// be encoded and therefore not very useful.
    pub fn arm9(rom: Rom) []u8 {
        const h = rom.header();
        const offset = h.arm9.offset.value();
        return rom.data.items[offset..][0..h.arm9.size.value()];
    }

    // pub fn nitroFooter(rom: Rom) []u8 {
    //     const h = rom.header();
    //     const offset = h.arm9.offset.value() + h.arm9.size.value();
    //     const footer = rom.data.items[offset..][0..12];
    //     if (@bitCast(lu32, footer[0..4].*).value() != 0xDEC00621)
    //         return footer[0..0];
    //     return footer;
    // }

    pub fn arm7(rom: Rom) []u8 {
        const h = rom.header();
        const offset = h.arm7.offset.value();
        return rom.data.items[offset..][0..h.arm7.size.value()];
    }

    pub fn arm9OverlayTable(rom: Rom) []align(1) Overlay {
        const h = rom.header();
        const bytes = h.arm9_overlay.slice(rom.data.items);
        return mem.bytesAsSlice(Overlay, bytes);
    }

    pub fn arm7OverlayTable(rom: Rom) []align(1) Overlay {
        const h = rom.header();
        const bytes = h.arm7_overlay.slice(rom.data.items);
        return mem.bytesAsSlice(Overlay, bytes);
    }

    pub fn fileSystem(rom: Rom) fs.Fs {
        const h = rom.header();
        const fnt_bytes = h.fnt.slice(rom.data.items);
        const fat_bytes = h.fat.slice(rom.data.items);
        return fs.Fs.fromFnt(
            fnt_bytes,
            mem.bytesAsSlice(Range, fat_bytes),
            rom.data.items,
        );
    }

    pub fn resizeSection(rom: *Rom, old: []const u8, new_size: usize) ![]u8 {
        const data = &rom.data;
        var buf: [1 * (1024 * 1024)]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buf);
        const sections = try rom.buildSectionTable(fba.allocator());

        const old_slice = Slice.fromSlice(data.items, old);
        const old_start = old_slice.start.value();
        const old_len = old_slice.len.value();

        const section_index = for (sections) |s, i| {
            const slice = s.toSlice(data.items);
            if (slice.start.value() == old_start and slice.len.value() == old_len)
                break i;
        } else unreachable;

        const is_last_section = section_index == sections.len - 1;
        const following_section_start = if (is_last_section)
            math.maxInt(u32)
        else
            sections[section_index + 1].toSlice(data.items).start.value();

        const potential_new_end = old_start + new_size;
        const can_perform_in_place_resize = potential_new_end <= following_section_start;
        if (can_perform_in_place_resize and !is_last_section) {
            // If there is room, we can beform the resize of the section inline in memory.
            // This only requires modifying the section offset in the rom. No copy required.
            const section = sections[section_index];
            section.set(data.items, Slice.init(old_start, new_size));

            const h = rom.header();
            h.header_checksum = lu16.init(h.calcChecksum());

            return data.items[old_start..][0..new_size];
        }

        const arm9_section = rom.arm9();
        const can_move_to_end_of_file = old.ptr != arm9_section.ptr;
        var end: u32 = undefined;
        const new_start = if (can_move_to_end_of_file) blk: {
            // Most sections can be moved to the end of the rom. This is more efficient
            // than making room for the section where it is currently located. It will
            // fragment the rom a little, but we don't have to perform massive copies
            // using this method.
            const last_section = sections[sections.len - 1].toSlice(data.items);
            const last_section_end = last_section.end();

            const new_start = mem.alignForward(last_section_end, 128);
            const section = sections[section_index];
            section.set(data.items, Slice.init(new_start, new_size));
            end = section.toSlice(data.items).end();

            if (new_start + new_size > data.items.len)
                try data.resize(data.items.len * 2);

            mem.copy(
                u8,
                data.items[new_start..][0..new_size],
                data.items[old_start..][0..old.len],
            );

            break :blk new_start;
        } else blk: {
            // Some sections (arm9) are not allowed to be moved, so we have to make room
            // for it where it is currently stored. This is expensive, but there is really
            // no other option.
            const extra_bytes = new_size - old.len;
            const old_sec_end = old_slice.end();
            const old_rom_end = sections[sections.len - 1].toSlice(data.items).end();

            for (sections[section_index + 1 ..]) |section| {
                const section_slice = section.toSlice(data.items);
                section.set(data.items, Slice.init(
                    section_slice.start.value() + extra_bytes,
                    section_slice.len.value(),
                ));
            }

            const section = sections[section_index];
            section.set(data.items, Slice.init(old_start, new_size));

            end = sections[sections.len - 1].toSlice(data.items).end();
            if (end > data.items.len)
                try data.resize(data.items.len * 2);

            mem.copyBackwards(
                u8,
                data.items[old_sec_end + extra_bytes ..],
                data.items[old_sec_end..old_rom_end],
            );
            break :blk old_start;
        };

        // Update header after resize
        const h = rom.header();
        h.total_used_rom_size = lu32.init(@intCast(u32, end));
        h.device_capacity = blk: {
            // Devicecapacity (Chipsize = 128KB SHL nn) (eg. 7 = 16MB)
            const size = data.items.len;
            var device_cap: u6 = 0;
            while (@shlExact(@as(u64, 128 * 1024), device_cap) < size) : (device_cap += 1) {}

            break :blk device_cap;
        };

        h.header_checksum = lu16.init(h.calcChecksum());
        return data.items[new_start..][0..new_size];
    }

    /// A generic structure for pointing to memory in the nds rom. The memory
    /// pointed to is the memory for a `start/end` or `start/len` pair. This
    /// structure does NOT point to the memory that these `start/X` pairs
    /// refer to, but to the pairs them self. The reason for this is
    /// so that we can modify this `start/X` indexes as we move sections
    /// around the rom during a resize.
    const Section = struct {
        start_index: u32,
        other_index: u32,
        kind: Kind,

        const Kind = enum {
            range,
            slice,
        };

        fn fromRange(data: []const u8, range: *align(1) const Range) Section {
            return fromStartEnd(data, &range.start, &range.end);
        }

        fn fromSlice(data: []const u8, slice: *align(1) const Slice) Section {
            return fromStartLen(data, &slice.start, &slice.len);
        }

        fn fromArm(data: []const u8, arm: *align(1) const Header.Arm) Section {
            return fromStartLen(data, &arm.offset, &arm.size);
        }

        fn fromStartEnd(
            data: []const u8,
            start: *align(1) const lu32,
            end: *align(1) const lu32,
        ) Section {
            return fromAny(data, .range, start, end);
        }

        fn fromStartLen(
            data: []const u8,
            start: *align(1) const lu32,
            len: *align(1) const lu32,
        ) Section {
            return fromAny(data, .slice, start, len);
        }

        fn fromAny(
            data: []const u8,
            kind: Kind,
            start: *align(1) const lu32,
            other: *align(1) const lu32,
        ) Section {
            const data_end = @ptrToInt(data.ptr) + data.len;
            const start_index = @ptrToInt(start) - @ptrToInt(data.ptr);
            const other_index = @ptrToInt(other) - @ptrToInt(data.ptr);
            debug.assert(start_index + @sizeOf(lu32) <= data_end);
            debug.assert(other_index + @sizeOf(lu32) <= data_end);
            debug.assert(kind == .slice or start.value() <= other.value());
            return .{
                .start_index = @intCast(u32, start_index),
                .other_index = @intCast(u32, other_index),
                .kind = kind,
            };
        }

        fn toSlice(section: Section, data: []const u8) Slice {
            // We discard const here, so that we can call `getPtr`. This
            // is safe, as `getPtr` only needs a mutable pointer so that
            // it can return one. We don't modify the pointee, so there
            // is nothing unsafe about this discard.
            const const_discarded = @intToPtr([*]u8, @ptrToInt(data.ptr))[0..data.len];
            const start = section.getPtr(const_discarded, .start).value();
            const other = section.getPtr(const_discarded, .other).value();
            const len = other - start * @boolToInt(section.kind == .range);
            return Slice.init(start, len);
        }

        fn getPtr(section: Section, data: []u8, field: enum { start, other }) *align(1) lu32 {
            const index = switch (field) {
                .start => section.start_index,
                .other => section.other_index,
            };
            const bytes = data[index..][0..@sizeOf(lu32)];
            return mem.bytesAsValue(lu32, bytes);
        }

        fn set(section: Section, data: []u8, slice: Slice) void {
            section.getPtr(data, .start).* = slice.start;
            switch (section.kind) {
                .slice => section.getPtr(data, .other).* = slice.len,
                .range => section.getPtr(data, .other).* = lu32.init(slice.end()),
            }
        }

        fn before(data: []const u8, a: Section, b: Section) bool {
            const a_slice = a.toSlice(data);
            const b_slice = b.toSlice(data);
            return a_slice.start.value() < b_slice.start.value();
        }
    };

    fn buildSectionTable(rom: Rom, allocator: mem.Allocator) ![]Section {
        const h = rom.header();

        const file_system = rom.fileSystem();
        const fat = file_system.fat;

        var sections = std.ArrayList(Section).init(allocator);
        try sections.ensureTotalCapacity(7 + fat.len);

        const data = &rom.data;
        sections.appendAssumeCapacity(Section.fromStartLen(
            data.items,
            &h.banner_offset,
            &h.banner_size,
        ));
        sections.appendAssumeCapacity(Section.fromArm(data.items, &h.arm9));
        sections.appendAssumeCapacity(Section.fromArm(data.items, &h.arm7));
        sections.appendAssumeCapacity(Section.fromSlice(data.items, &h.arm9_overlay));
        sections.appendAssumeCapacity(Section.fromSlice(data.items, &h.arm7_overlay));
        sections.appendAssumeCapacity(Section.fromSlice(data.items, &h.fat));
        sections.appendAssumeCapacity(Section.fromSlice(data.items, &h.fnt));
        for (fat) |*f|
            sections.appendAssumeCapacity(Section.fromRange(data.items, f));

        // Sort sections by where they appear in the rom.
        std.sort.sort(Section, sections.items, data.items, Section.before);
        return sections.toOwnedSlice();
    }

    pub fn fromFile(file: std.fs.File, allocator: mem.Allocator) !Rom {
        const reader = file.reader();
        const size = try file.getEndPos();
        try file.seekTo(0);

        if (size < @sizeOf(Header))
            return error.InvalidRom;
        if (size < 4096)
            return error.InvalidRom;

        var data = std.ArrayList(u8).init(allocator);
        errdefer data.deinit();

        try data.resize(size);
        try reader.readNoEof(data.items);

        const res = Rom{ .data = data };
        try res.header().validate();

        // TODO: we should validate that all the offsets and sizes are not
        //       out of bounds of the rom.data.items.
        return res;
    }

    pub fn write(rom: Rom, writer: anytype) !void {
        // The contract here is that once you have an `nds.Rom`, it should
        // always be a valid rom, so we just assert that this is true here
        // for sanity.
        rom.header().validate() catch unreachable;
        try writer.writeAll(rom.data.items);
    }

    pub fn deinit(rom: Rom) void {
        rom.data.deinit();
    }
};

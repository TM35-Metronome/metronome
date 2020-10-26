const std = @import("std");

const blz = @import("nds/blz.zig");
const int = @import("int.zig");

const debug = std.debug;
const generic = fun.generic;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const os = std.os;

const lu16 = int.lu16;
const lu32 = int.lu32;

pub const formats = @import("nds/formats.zig");
pub const fs = @import("nds/fs.zig");

pub const Banner = @import("nds/banner.zig").Banner;
pub const Header = @import("nds/header.zig").Header;

test "nds" {
    _ = @import("nds/banner.zig");
    _ = @import("nds/blz.zig");
    _ = @import("nds/formats.zig");
    _ = @import("nds/fs.zig");
    _ = @import("nds/header.zig");
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

    pub fn slice(r: Range, s: var) mem.Span(@TypeOf(s)) {
        return s[r.start.value()..r.end.value()];
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

    pub fn slice(sl: Slice, s: var) mem.Span(@TypeOf(s)) {
        return s[sl.start.value()..sl.end()];
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
};

pub const Rom = struct {
    data: std.ArrayList(u8),

    pub fn header(rom: Rom) *const Header {
        return mem.bytesAsValue(Header, rom.data.items[0..@sizeOf(Header)]);
    }

    pub fn banner(rom: Rom) *Banner {
        const h = rom.header();
        const offset = h.banner_offset.value();
        const bytes = rom.data.items[offset..][0..@sizeOf(Banner)];
        return mem.bytesAsValue(Banner, bytes);
    }

    /// Returns the arm9 section of the rom. Note here that this section could
    /// be encoded and therefor not very useful. Call decodeArm9 before this
    /// if you need the section to be decoded.
    pub fn arm9(rom: Rom) []u8 {
        const h = rom.header();
        const offset = h.arm9.offset.value();
        return rom.data.items[offset..][0..h.arm9.size.value()];
    }

    pub fn nitroFooter(rom: Rom) []u8 {
        const h = rom.header();
        const offset = h.arm9.offset.value() + h.arm9.size.value();
        const footer = rom.data.items[offset..][0..12];
        if (@bitCast(lu32, footer[0..4].*).value() != 0xDEC00621)
            return footer[0..0];
        return footer;
    }

    pub fn arm7(rom: Rom) []u8 {
        const h = rom.header();
        const offset = h.arm7.offset.value();
        return rom.data.items[offset..][0..h.arm7.size.value()];
    }

    pub fn arm9OverlayTable(rom: Rom) []Overlay {
        const h = rom.header();
        const bytes = h.arm9_overlay.slice(rom.data.items);
        return mem.bytesAsSlice(Overlay, bytes);
    }

    pub fn arm7OverlayTable(rom: Rom) []Overlay {
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

    /// Decodes the arm9 section and returns it to the caller. The caller
    /// owns the memory.
    pub fn getDecodedArm9(rom: Rom, allocator: *mem.Allocator) ![]u8 {
        const h = rom.header();
        const arm9_bytes = rom.arm9();

        return blz.decode(arm9_bytes, allocator) catch |err| switch (err) {
            error.WrongDecodedLength,
            error.Overflow,
            error.BadLength,
            error.BadHeaderLength,
            error.BadHeader,
            // Assume bad encoded format means that arm9 wasn't encoded.
            => return mem.dupe(allocator, u8, arm9_bytes),
            else => |e| return e,
        };
    }

    pub fn resizeSection(rom: *Rom, old: []const u8, new_size: usize) ![]u8 {
        const rom_data = rom.data.items;
        var buf: [1 * (1024 * 1024)]u8 = undefined;
        const fba = &std.heap.FixedBufferAllocator.init(&buf).allocator;
        const sections = try rom.buildSectionTable(fba);

        const old_slice = Slice.fromSlice(rom_data, old);
        const old_start = old_slice.start.value();
        const old_len = old_slice.len.value();

        const section_index = for (sections) |s, i| {
            const slice = s.toSlice(rom_data);
            if (slice.start.value() == old_start and
                slice.len.value() == old_len)
            {
                break i;
            }
        } else unreachable;

        const is_last_section = section_index == sections.len - 1;
        const following_section_start = if (is_last_section)
            math.maxInt(u32)
        else
            sections[section_index + 1].toSlice(rom_data).start.value();

        const potential_new_end = old_start + new_size;
        const can_perform_in_place_resize = potential_new_end <= following_section_start;
        if (can_perform_in_place_resize) {
            // If there is room, we can befor the resize of the section inline in memory.
            // This only requires modifying the section offset in the rom. No copy required.
            const section = sections[section_index];
            section.set(rom_data, Slice.init(old_start, new_size));
            return rom_data[old_start..][0..new_size];
        }

        const arm9_section = rom.arm9();
        const can_move_to_end_of_file = old.ptr != arm9_section.ptr;
        const new_start = if (can_move_to_end_of_file) blk: {
            // Most sections can be moved to the end of the rom. This is more efficient
            // than making room for the section where it is currently located. It will
            // fragment the rom a little, but we don't have to perform massive copies
            // using this method.
            const last_section = sections[sections.len - 1].toSlice(rom_data);
            const last_section_end = last_section.end();
            const new_start = mem.alignForward(last_section_end, 128);
            try rom.data.resize(new_start + new_size);
            mem.copy(
                u8,
                rom.data.items[new_start..][0..new_size],
                rom.data.items[old_start..][0..math.min(new_size, old.len)],
            );

            const section = sections[section_index];
            section.set(rom_data, Slice.init(new_start, new_size));
            break :blk new_start;
        } else blk: {
            // Some sections (arm9) are not allowed to be moved, so we have to make room
            // for it where it is currently stored. This is expensive, but there is really
            // no other option.
            const extra_bytes = new_size - old.len;
            const old_rom_len = rom_data.len;
            const old_sec_end = old_slice.end();
            const new_rom_len = old_rom_len + extra_bytes;
            try rom.data.resize(new_rom_len);

            for (sections[section_index + 1 ..]) |section, i| {
                const section_slice = section.toSlice(rom_data);
                section.set(rom_data, Slice.init(
                    section_slice.start.value() + extra_bytes,
                    section_slice.len.value(),
                ));
            }

            mem.copyBackwards(
                u8,
                rom.data.items[old_sec_end + extra_bytes ..],
                rom.data.items[old_sec_end..old_len],
            );
            break :blk old_start;
        };

        // Update header after resize
        const h = @intToPtr(*Header, @ptrToInt(rom.header()));
        h.total_used_rom_size = lu32.init(@intCast(u32, rom_data.len));
        h.device_capacity = blk: {
            // Devicecapacity (Chipsize = 128KB SHL nn) (eg. 7 = 16MB)
            const size = h.total_used_rom_size.value();
            var device_cap: u6 = 0;
            while (@shlExact(@as(u64, 128000), device_cap) < size) : (device_cap += 1) {}

            break :blk device_cap;
        };

        h.header_checksum = lu16.init(h.calcChecksum());
        return rom_data[old_start..][0..new_size];
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

        fn fromRange(data: []const u8, range: *const Range) Section {
            return fromStartEnd(data, &range.start, &range.end);
        }

        fn fromSlice(data: []const u8, slice: *const Slice) Section {
            return fromStartLen(data, &slice.start, &slice.len);
        }

        fn fromArm(data: []const u8, arm: *const Header.Arm) Section {
            return fromStartLen(data, &arm.offset, &arm.size);
        }

        fn fromStartEnd(data: []const u8, start: *const lu32, end: *const lu32) Section {
            return fromAny(data, .range, start, end);
        }

        fn fromStartLen(data: []const u8, start: *const lu32, len: *const lu32) Section {
            return fromAny(data, .slice, start, len);
        }

        fn fromAny(data: []const u8, kind: Kind, start: *const lu32, other: *const lu32) Section {
            const data_end = @ptrToInt(data.ptr) + data.len;
            const start_index = @ptrToInt(start) - @ptrToInt(data.ptr);
            const other_index = @ptrToInt(other) - @ptrToInt(data.ptr);
            debug.assert(start_index + @sizeOf(lu32) <= data_end);
            debug.assert(other_index + @sizeOf(lu32) <= data_end);
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
            const len = switch (section.kind) {
                .range => blk: {
                    const end = section.getPtr(const_discarded, .other).value();
                    break :blk end - start;
                },
                .slice => section.getPtr(const_discarded, .other).value(),
            };
            return Slice.init(start, len);
        }

        fn getPtr(section: Section, data: []u8, field: enum { start, other }) *lu32 {
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
    };

    fn buildSectionTable(rom: Rom, allocator: *mem.Allocator) ![]Section {
        // Nds internals like this functions are allowed to modify data
        // that is returned as `const` to the user, so we discard `const`
        // here. This is always safe.
        const h = @intToPtr(*Header, @ptrToInt(rom.header()));

        const nitro_footer = rom.nitroFooter();
        const file_system = rom.fileSystem();
        const fat = file_system.fat;

        var sections = std.ArrayList(Section).init(allocator);
        try sections.ensureCapacity(7 + fat.len);

        const rom_data = rom.data.items;
        sections.append(Section.fromStartLen(
            rom_data,
            &h.banner_offset,
            &h.banner_size,
        )) catch unreachable;
        sections.append(Section.fromArm(rom_data, &h.arm9)) catch unreachable;
        sections.append(Section.fromArm(rom_data, &h.arm7)) catch unreachable;
        sections.append(Section.fromSlice(rom_data, &h.arm9_overlay)) catch unreachable;
        sections.append(Section.fromSlice(rom_data, &h.arm7_overlay)) catch unreachable;
        sections.append(Section.fromSlice(rom_data, &h.fat)) catch unreachable;
        sections.append(Section.fromSlice(rom_data, &h.fnt)) catch unreachable;
        for (fat) |*f|
            sections.append(Section.fromRange(rom_data, f)) catch unreachable;

        // Sort sections by where they appear in the rom.
        // std.sort.sort(Section, sections.items, Section.before);
        return sections.toOwnedSlice();
    }

    pub fn fromFile(file: std.fs.File, allocator: *mem.Allocator) !Rom {
        const in_stream = file.inStream();
        const size = try file.getEndPos();
        try file.seekTo(0);

        var rom_data = std.ArrayList(u8).init(allocator);
        errdefer rom_data.deinit();
        try rom_data.resize(size);

        try in_stream.readNoEof(rom_data.items);
        const res = Rom{
            .data = rom_data,
        };
        try res.header().validate();

        // TODO: we should validate that all the offsets and sizes are not
        //       out of bounds of the rom.data.items.
        return res;
    }

    pub fn writeToStream(rom: Rom, stream: var) !void {
        // The contract here is that once you have an `nds.Rom`, it should
        // always be a valid rom, so we just assert that this is true here
        // for sanity.
        rom.header().validate() catch unreachable;
        try stream.writeAll(rom.data.items);
    }

    pub fn deinit(rom: Rom) void {
        rom.data.deinit();
    }
};

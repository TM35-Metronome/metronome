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

    pub fn init(start: u32, end: u32) Range {
        return .{ .start = lu32.init(start), .end = lu32.init(end) };
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

    pub fn init(start: u32, len: u32) Slice {
        return .{ .start = lu32.init(start), .len = lu32.init(len) };
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
        if (!mem.startsWith(u8, footer, &lu32.init(0xDEC00621).bytes))
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

    /// Decodes the arm9 section of the rom in place. This function might not do anything
    /// if the section is already decoded.
    pub fn decodeArm9(rom: *Rom) !void {
        const h = rom.header();
        const arm9_bytes = rom.arm9();
        const footer = rom.nitroFooter();

        // TODO: Would be cool if we could ask for the decoded length, and
        //       then preallocate that section directly in the roms bytes.
        //       We could then just pass a buffer to blz.decode, and it would
        //       decode into that buffer. Should be possible.
        const decoded = blz.decode(arm9_bytes, rom.data.allocator) catch |err| switch (err) {
            error.WrongDecodedLength,
            error.Overflow,
            error.BadLength,
            error.BadHeaderLength,
            error.BadHeader,
            => return, // Assume bad encoded format means that arm9 wasn't encoded.
            else => |e| return e,
        };
        defer rom.data.allocator.free(decoded);

        const arm9_slice = Slice{
            .start = h.arm9.offset,
            .len = h.arm9.size,
        };
        try rom.resizeSection(arm9_slice, @intCast(u32, decoded.len));
        mem.copy(u8, rom.arm9(), decoded);
        return;
    }

    pub fn newFileSystem(rom: *Rom, builder: fs.Builder) !void {
        const h = @intToPtr(*Header, @ptrToInt(rom.header()));
        h.fnt.len = lu32.init(0);
        h.fat.len = lu32.init(0);

        const fnt_sub = builder.fnt;
        const fnt_main = builder.fnt_main;
        const fnt_main_size = fnt_main.len * @sizeOf(fs.FntMainEntry);
        const fnt_size = fnt_sub.len + fnt_main_size * @boolToInt(fnt_sub.ptr != fnt_main.ptr);
        try rom.resizeSection(h.fnt, fnt_size);
        try rom.resizeSection(h.fat, builder.fat.len * @sizeOf(Range));

        const new_fs = rom.fileSystem();
        mem.set(Range, new_fs.fat, Range.init(0, 0));

        // To avoid allocations in this function, we use a local 1MB
        // buffer. This is a guess for the maximum bytes we will ever
        // realistically need to perform this resize.
        var buf: [1 * (1024 * 1024)]u8 = undefined;
        const fba = &std.heap.FixedBufferAllocator.init(&buf).allocator;
        const sections = try rom.buildSectionTable(fba);
        const end = sections[sections.len - 1].toSlice().end();

        for (new_fs.fat) |*new, i| {
            const f = builder.fat[i];
            new.* = nds.Range.init(
                f.start.value() + end,
                f.end.value() + end,
            );
            if (f.end.value() <= builder.data.len) {
                const data = builder.data[f.start.value()..f.end.value()];
                mem.copy(u8, new_fs.data[new.start.value()..], data);
            }
        }

        mem.copy(u8, new_fs.fnt, mem.sliceAsBytes(builder.fnt_main));
        mem.copy(u8, new_fs.fnt[fnt_size - fnt_sub.len ..], builder.fnt);
    }

    /// A generic structure for pointing to memory in the nds rom. The memory
    /// pointed to is the memory for a `start/end` or `start/len` pair. This
    /// structure does NOT point to the memory that these `start/X` pairs
    /// refer to, but to the pairs them self. The reason for this is
    /// so that we can modify this `start/X` indexes as we move sections
    /// around the rom during a resize. Section also have properties that
    /// define restrictions on what these indexes are actually allowed to
    /// point too.
    const Section = struct {
        // HACK: To get `Section.order` to work (so we can sort `Section`)
        //       we actually have to have the pointer embedded in the struct.
        //       This really is a waist of space and unsafe as well, as
        //       the memory of `Section` is expected to be reallocated.
        //       It is however, safe to use this pointer before the
        //       reallocation occurs.
        ptr: [*]const u8,
        start_index: u32,
        other_index: u32,
        kind: Kind,
        properties: Properties,

        const Kind = enum {
            range,
            slice,
        };

        const Properties = struct {
            // Is `!= 0` if this section requires section for extra data after
            // the end. This is for thing like the `nitro_footer` after
            // arm9.
            trailing_data: u16 = 0,

            // The range in which it is valid to place the memory for this
            // section.
            range: RangeProp = RangeProp{},

            const RangeProp = struct {
                start: u32 = 0x8000,
                end: u32 = math.maxInt(u32),
            };
        };

        fn fromRange(data: []const u8, range: *const Range, prop: Properties) Section {
            return fromStartEnd(data, &range.start, &range.end, prop);
        }

        fn fromSlice(data: []const u8, slice: *const Slice, prop: Properties) Section {
            return fromStartLen(data, &slice.start, &slice.len, prop);
        }

        fn fromArm(data: []const u8, arm: *const Header.Arm, prop: Properties) Section {
            return fromStartLen(data, &arm.offset, &arm.size, prop);
        }

        fn fromStartEnd(data: []const u8, start: *const lu32, end: *const lu32, prop: Properties) Section {
            return fromAny(data, .range, start, end, prop);
        }

        fn fromStartLen(data: []const u8, start: *const lu32, len: *const lu32, prop: Properties) Section {
            return fromAny(data, .slice, start, len, prop);
        }

        fn fromAny(data: []const u8, kind: Kind, start: *const lu32, other: *const lu32, prop: Properties) Section {
            const data_end = @ptrToInt(data.ptr) + data.len;
            const start_index = @ptrToInt(start) - @ptrToInt(data.ptr);
            const other_index = @ptrToInt(other) - @ptrToInt(data.ptr);
            debug.assert(start_index + @sizeOf(lu32) <= data_end);
            debug.assert(other_index + @sizeOf(lu32) <= data_end);
            return .{
                .ptr = data.ptr,
                .start_index = @intCast(u32, start_index),
                .other_index = @intCast(u32, other_index),
                .kind = kind,
                .properties = prop,
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

        /// Checks if the slice passed in have the `properties` defined
        /// by this section.
        fn sliceHasProperties(section: Section, slice: Slice) bool {
            const start = slice.start.value();
            const fixed = section.properties.range.start == section.properties.range.end;
            return (fixed and section.properties.range.start == start) or
                (section.properties.range.start <= start and
                start < section.properties.range.end);
        }

        fn set(section: Section, data: []u8, slice: Slice) void {
            debug.assert(section.sliceHasProperties(slice));
            section.getPtr(data, .start).* = slice.start;
            switch (section.kind) {
                .slice => section.getPtr(data, .other).* = slice.len,
                .range => section.getPtr(data, .other).* = lu32.init(slice.end()),
            }
        }

        fn order(a: Section, b: Section) math.Order {
            // HACK: Here is where we use `ptr`. To save space, we never
            //       store the length of the pointer. To get a slice, we
            //       just slice from 0..max. This should be safe, as
            //       all the `fromX` validate that the indexes are inside
            //       the slice that `ptr` comes from.
            const m = math.maxInt(usize);
            const a_slice = a.toSlice(a.ptr[0..m]);
            const b_slice = b.toSlice(b.ptr[0..m]);
            return math.order(a_slice.start.value(), b_slice.start.value());
        }

        fn before(a: Section, b: Section) bool {
            return order(a, b) == .lt;
        }
    };

    /// The most complicated function in this file. This functions job
    /// is to resize one section in the rom to a new, bigger, size.
    /// It it needs to move sections, it will correct the offsets that
    /// point to those sections as well.
    fn resizeSection(rom: *Rom, section_to_resize: Slice, new_size: u32) !void {
        // Nds internals like this functions are allowed to modify data
        // that is returned as `const` to the user, so we discard `const`
        // here. This is always safe.
        const h = @intToPtr(*Header, @ptrToInt(rom.header()));

        // To avoid allocations in this function, we use a local 1MB
        // buffer. This is a guess for the maximum bytes we will ever
        // realistically need to perform this resize.
        var buf: [1 * (1024 * 1024)]u8 = undefined;
        const fba = &std.heap.FixedBufferAllocator.init(&buf).allocator;
        const sections = try rom.buildSectionTable(fba);

        // Find the index to the section the caller wants to resize.
        // It is the callers job to ensure that the section they pass in
        // actually exists.
        const sec_index = for (sections) |section, i| {
            const section_slice = section.toSlice(rom.data.items);
            if (section_to_resize.start.value() == section_slice.start.value()) {
                debug.assert(section_to_resize.len.value() == section_slice.len.value());
                break i;
            }
        } else unreachable;

        // Get the current, previous and next sections. These will
        // be used to look for opportunities to perform the inline
        // without moving any section other than the one resized.
        const curr_sec = sections[sec_index];
        const prev_sec = if (sec_index == 0) curr_sec else sections[sec_index - 1];
        const next_sec = sections[sec_index + 1];

        const prev_slice = prev_sec.toSlice(rom.data.items);
        const curr_slice = curr_sec.toSlice(rom.data.items);
        const next_slice = next_sec.toSlice(rom.data.items);
        debug.assert(curr_slice.len.value() < new_size);

        const trailing_data = curr_sec.properties.trailing_data;

        // Get the space available between the previous and next
        // section.
        const space_available_for_inline_resize = Range.init(
            prev_slice.start.value(),
            next_slice.start.value(),
        );
        if (new_size + trailing_data <= space_available_for_inline_resize.len()) {
            // If our new size fits into this space, then we can simply
            // perform an inline resize.
            const start = space_available_for_inline_resize.start.value();
            const old_start = curr_slice.start.value();
            const old_end = curr_slice.end();
            const old_section = rom.data.items[old_start .. old_end + trailing_data];
            const new_slice = Slice.init(start, new_size);
            if (!curr_sec.sliceHasProperties(new_slice))
                return error.InvalidResize;
            curr_sec.set(rom.data.items, new_slice);

            // Copy trailing data to the end
            const new_end = new_slice.end();
            const new_section = rom.data.items[start .. new_end + trailing_data];
            mem.copy(
                u8,
                new_section[new_end..],
                new_section[old_end..old_section.len],
            );
            // Copy rest to destination
            mem.copy(
                u8,
                new_section[0..new_end],
                new_section[old_start..old_end],
            );
            return;
        }

        // Ok, we couldn't perform an inline resize, so we will have to
        // move all sections after this one to make room.
        const space_needed = (new_size + trailing_data) -
            (next_slice.start.value() - curr_slice.start.value());

        const sections_to_move = sections[sec_index + 1 ..];

        // Validate that the resize doesn't break any of the properties
        // of the sections we move.
        for (sections_to_move) |section| {
            const slice = section.toSlice(rom.data.items);
            const start = slice.start.value() + space_needed;
            const len = slice.len.value();
            if (!section.sliceHasProperties(Slice.init(start, len)))
                return error.InvalidResize;
        }

        // Find the last section and make the end of that section
        // the end of the rom. Then resize the rom to have enough
        // room for our section after the resize. Because the rom
        // is an ArrayList(u8) this might do reallocation if there
        // is enough capacity.
        const last_sec = sections[sections.len - 1];
        const old_len = last_sec.toSlice(rom.data.items).end();
        try rom.data.resize(old_len + space_needed);

        // Update the offsets of the sections we need to move.
        for (sections_to_move) |section| {
            const slice = section.toSlice(rom.data.items);
            const start = slice.start.value() + space_needed;
            const len = slice.len.value();
            section.set(rom.data.items, Slice.init(start, len));
        }

        // Update the section we are resizing to have its new size.
        curr_sec.set(rom.data.items, Slice.init(curr_slice.start.value(), new_size));

        const start_of_data_to_move = curr_slice.end();
        const old_data = rom.data.items[0..old_len];
        const data_to_move = old_data[start_of_data_to_move..];
        const place_to_move_data = rom.data.items[start_of_data_to_move + space_needed ..];

        // Now we move everything to make room for the resize.
        mem.copyBackwards(u8, place_to_move_data, data_to_move);

        // Update header after resize
        h.total_used_rom_size = lu32.init(@intCast(u32, rom.data.items.len));
        h.device_capacity = blk: {
            // Devicecapacity (Chipsize = 128KB SHL nn) (eg. 7 = 16MB)
            const size = h.total_used_rom_size.value();
            var device_cap: u6 = 0;
            while (@shlExact(@as(u64, 128000), device_cap) < size) : (device_cap += 1) {}

            break :blk device_cap;
        };

        h.header_checksum = lu16.init(h.calcChecksum());
        return;
    }

    fn buildSectionTable(rom: Rom, allocator: *mem.Allocator) ![]Section {
        // Nds internals like this functions are allowed to modify data
        // that is returned as `const` to the user, so we discard `const`
        // here. This is always safe.
        const h = @intToPtr(*Header, @ptrToInt(rom.header()));

        const nitro_footer = rom.nitroFooter();
        const file_system = rom.fileSystem();
        const fat = file_system.fat;

        var sections = std.ArrayList(Section).init(allocator);
        try sections.append(Section.fromStartLen(
            rom.data.items,
            &h.banner_offset,
            &h.banner_size,
            .{},
        ));
        try sections.append(Section.fromArm(rom.data.items, &h.arm9, .{
            .range = .{ .start = 0x4000, .end = 0x4000 },
            .trailing_data = @intCast(u16, nitro_footer.len),
        }));
        try sections.append(Section.fromArm(rom.data.items, &h.arm7, .{}));
        try sections.append(Section.fromSlice(rom.data.items, &h.arm9_overlay, .{}));
        try sections.append(Section.fromSlice(rom.data.items, &h.arm7_overlay, .{}));
        try sections.append(Section.fromSlice(rom.data.items, &h.fat, .{}));
        try sections.append(Section.fromSlice(rom.data.items, &h.fnt, .{}));
        for (fat) |*f|
            try sections.append(Section.fromRange(rom.data.items, f, .{}));

        // Sort sections by where they appear in the rom.
        std.sort.sort(Section, sections.items, Section.before);
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

    pub fn writeToFile(rom: Rom, file: std.fs.File) !void {
        // The contract here is that once you have an `nds.Rom`, it should
        // always be a valid rom, so we just assert that this is true here
        // for sanity.
        rom.header().validate() catch unreachable;
        try file.writeAll(rom.data.items);
    }

    pub fn deinit(rom: Rom) void {
        rom.data.deinit();
    }
};

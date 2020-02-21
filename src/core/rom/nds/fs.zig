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

/// An in memory filesystem used as an abstraction over the filesystems found in the nintendo ds.
/// The filesystem have the following properties:
///   * Peserves the order files and folders where added to the file system.
///     * This is required, as certain nds games use indexs to fat entries when accessing data,
///       instead of path lookup.
///   * Uses posix paths for accessing files and folders.
///     * `/` is the root folder.
///     * TODO: `..` is the parent folder.
///     * TODO: `.` is the current folder.
///   * It is not `ArenaAllocator` friendly, as it uses `ArrayList` and `HashMap` as containers.
///   * TODO: We can't delete files or folders yet
pub fn Folder(comptime TFile: type) type {
    return struct {
        const Self = @This();
        const IndexMap = std.StringHashMap(usize);
        const Nodes = std.ArrayList(Node);

        pub const File = TFile;
        pub const Node = struct {
            // We both store names in `indexs` and here, so that we have access to the names
            // when doing ordered iteration.
            name: []const u8,
            kind: Kind,

            pub const Kind = union(enum) {
                file: *File,
                folder: *Self,
            };

            pub fn asFile(node: Node) !*File {
                switch (node.kind) {
                    .file => |file| return file,
                    .folder => return error.NotAFile,
                }
            }

            pub fn asDataFile(node: Node, comptime T: type) !*T {
                const file = try asFile(node);
                const bytes = file.data;
                const rem = bytes.len % @sizeOf(T);
                const data = @bytesToSlice(T, bytes[0 .. bytes.len - rem]);
                if (data.len == 0)
                    return error.FileToSmall;

                return &data[0];
            }
        };

        // The parent folder. If we are root, then this is `null`
        parent: ?*Self,

        // Maps names -> indexs in `nodes`. Used for fast lookup.
        indexs: IndexMap,

        // Stores our nodes. We use an arraylist to preserve the order of created nodes.
        nodes: Nodes,

        /// Allocate and initialize a new filesystem.
        pub fn create(a: *mem.Allocator) !*Self {
            const res = try a.create(Self);
            res.* = Self.init(a);
            return res;
        }

        /// Deinitialize and free the filesystem.
        pub fn destroy(folder: *Self) void {
            folder.deinit();
        }

        pub fn init(a: *mem.Allocator) Self {
            return Self{
                .parent = null,
                .indexs = IndexMap.init(a),
                .nodes = Nodes.init(a),
            };
        }

        pub fn deinit(folder: *Self) void {
            const parent = folder.parent;
            var curr: ?*Self = folder;
            while (curr != parent) {
                const f = curr.?;
                const a = f.allocator();
                if (f.nodes.popOrNull()) |node| {
                    switch (node.kind) {
                        .file => |file| {
                            file.deinit();
                            a.destroy(file);
                        },
                        .folder => |sub_folder| curr = sub_folder,
                    }
                } else {
                    var it = f.indexs.iterator();
                    while (it.next()) |entry|
                        a.free(entry.key);

                    f.indexs.deinit();
                    f.nodes.deinit();
                    curr = f.parent;
                    f.* = undefined;
                    a.destroy(f);
                }
            }
        }

        // TODO: ensureCapacity for HashMap?
        pub fn ensureCapacity(folder: *Self, new_capacity: usize) !void {
            try folder.nodes.ensureCapacity(new_capacity);
        }

        /// Get the allocator the filesystem uses for allocating files and folders.
        pub fn allocator(folder: *Self) *mem.Allocator {
            return folder.nodes.allocator;
        }

        /// Get the filesystesm root.
        pub fn root(folder: *Self) *Self {
            var res = folder;
            while (res.parent) |next|
                res = next;

            return res;
        }

        /// Given a posix path, return the file at the path location.
        /// Return null if no file exists and the path location.
        pub fn getFile(folder: *Self, path: []const u8) ?*File {
            const node = folder.get(path) orelse return null;
            switch (node) {
                .file => |res| return res,
                .folder => return null,
            }
        }

        /// Given a posix path, return the folder at the path location.
        /// Return null if no file exists and the path location.
        pub fn getFolder(folder: *Self, path: []const u8) ?*Self {
            const node = folder.get(path) orelse return null;
            switch (node) {
                .file => return null,
                .folder => |res| return res,
            }
        }

        /// Check if a file or folder exists at the path location.
        pub fn exists(folder: *Self, path: []const u8) bool {
            return folder.get(path) != null;
        }

        fn get(folder: *Self, path: []const u8) ?Node.Kind {
            var res = Node.Kind{ .folder = folder.startFolder(path) };
            var it = mem.tokenize(path, "/");
            while (it.next()) |name| {
                switch (res) {
                    .file => return null,
                    .folder => |tmp| {
                        const entry = tmp.indexs.get(name) orelse return null;
                        const index = entry.value;
                        res = tmp.nodes.toSlice()[index].kind;
                    },
                }
            }

            return res;
        }

        fn startFolder(folder: *Self, path: []const u8) *Self {
            if (path.len == 0 or path[0] != '/')
                return folder;

            return folder.root();
        }

        /// Create a file in the current folder.
        pub fn createFile(folder: *Self, name: []const u8, file: File) !*File {
            const res = try folder.createNode(name);
            res.kind = Node.Kind{ .file = try folder.allocator().create(File) };
            res.kind.file.* = file;

            return res.kind.file;
        }

        /// Create a folder in the current folder.
        pub fn createFolder(folder: *Self, name: []const u8) !*Self {
            const res = try folder.createNode(name);
            const fold = try Self.create(folder.allocator());
            fold.parent = folder;
            res.kind = Node.Kind{ .folder = fold };

            return res.kind.folder;
        }

        /// Create all none existing folders in `path`.
        pub fn createPath(folder: *Self, path: []const u8) !*Self {
            var res = folder.startFolder(path);
            var it = mem.tokenize(path, "/");
            while (it.next()) |name| {
                if (res.indexs.get(name)) |entry| {
                    const node = res.nodes.toSliceConst()[entry.value];
                    switch (node.kind) {
                        .file => return error.FileInPath,
                        .folder => |sub_folder| res = sub_folder,
                    }
                } else {
                    res = res.createFolder(name) catch |err| {
                        // TODO: https://github.com/ziglang/zig/issues/769
                        switch (err) {
                            // We just checked that the folder doesn't exist, so this error
                            // should never happen.
                            error.NameExists => unreachable,
                            else => return err,
                        }
                    };
                }
            }

            return res;
        }

        /// Create all none existing folders in `path` and creates a file at the path location.
        pub fn createPathAndFile(folder: *Self, path: []const u8, file: File) !*File {
            var res_folder = folder;
            if (std.fs.path.dirnamePosix(path)) |dirname|
                res_folder = try folder.createPath(dirname);

            return try res_folder.createFile(std.fs.path.basenamePosix(path), file);
        }

        fn createNode(folder: *Self, name: []const u8) !*Node {
            try validateName(name);
            if (folder.indexs.contains(name))
                return error.NameExists;

            const a = folder.allocator();
            const index = folder.nodes.len;
            const owned_name = try mem.dupe(a, u8, name);
            errdefer a.free(owned_name);

            const res = try folder.nodes.addOne();
            errdefer _ = folder.nodes.pop();
            _ = try folder.indexs.put(owned_name, index);

            res.name = owned_name;
            return res;
        }

        fn validateName(name: []const u8) !void {
            if (name.len == 0)
                return error.InvalidName;

            for (name) |char| {
                if (char == '/')
                    return error.InvalidName;
            }
        }
    };
}

pub const Narc = Folder(struct {
    const Self = @This();

    allocator: *mem.Allocator,
    data: []u8,

    pub fn deinit(file: *Self) void {
        file.allocator.free(file.data);
        file.* = undefined;
    }
});

pub const Nitro = Folder(union(enum) {
    const Self = @This();

    binary: Binary,
    narc: *Narc,

    pub fn deinit(file: *Self) void {
        switch (file.*) {
            .binary => |bin| bin.allocator.free(bin.data),
            .narc => |narc| narc.destroy(),
        }

        file.* = undefined;
    }

    pub const Binary = struct {
        allocator: *mem.Allocator,
        data: []u8,
    };
});

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

pub fn readNitro(file: std.fs.File, allocator: *mem.Allocator, fnt: []const u8, fat: []const FatEntry) !*Nitro {
    return readHelper(Nitro, file, allocator, fnt, fat, 0);
}

pub fn readNarc(file: std.fs.File, allocator: *mem.Allocator, fnt: []const u8, fat: []const FatEntry, img_base: usize) !*Narc {
    return readHelper(Narc, file, allocator, fnt, fat, img_base);
}

fn readHelper(comptime F: type, file: std.fs.File, allocator: *mem.Allocator, fnt: []const u8, fat: []const FatEntry, img_base: usize) !*F {
    const fnt_main_table = blk: {
        const rem = fnt.len % @sizeOf(FntMainEntry);
        const fnt_mains = @bytesToSlice(FntMainEntry, fnt[0 .. fnt.len - rem]);
        if (fnt_mains.len == 0)
            return error.InvalidFnt;

        const len = fnt_mains[0].parent_id.value();
        if (fnt_mains.len < len or len > 4096)
            return error.InvalidFnt;

        break :blk fnt_mains[0..len];
    };

    const State = struct {
        folder: *F,
        file_id: u16,
        fnt_sub_table: []const u8,
    };

    var stack = std.ArrayList(State).init(allocator);
    defer stack.deinit();

    const root = try F.create(allocator);
    errdefer root.destroy();

    const fnt_first = fnt_main_table[0];
    const first_offset = fnt_first.offset_to_subtable.value();
    if (fnt.len < first_offset)
        return error.InvalidFnt;

    try stack.append(State{
        .folder = root,
        .file_id = fnt_first.first_file_id_in_subtable.value(),
        .fnt_sub_table = fnt[first_offset..],
    });

    while (stack.popOrNull()) |state| {
        const folder = state.folder;
        const file_id = state.file_id;
        const fnt_sub_table = state.fnt_sub_table;

        var mem_stream = io.SliceInStream.init(fnt_sub_table);
        const stream = &mem_stream.stream;

        const Kind = enum(u8) {
            file = 0x00,
            folder = 0x80,
        };
        const type_length = try stream.readByte();

        if (type_length == 0x80)
            return error.InvalidSubTableTypeLength;
        if (type_length == 0x00)
            continue;

        const length = type_length & 0x7F;
        const kind = @intToEnum(Kind, type_length & 0x80);
        const name = try allocator.alloc(u8, length);
        defer allocator.free(name);
        try stream.readNoEof(name);

        switch (kind) {
            .file => {
                if (fat.len <= file_id)
                    return error.InvalidFileId;

                const fat_entry = fat[file_id];
                _ = try folder.createFile(name, switch (F) {
                    Nitro => try readNitroFile(file, allocator, fat_entry, img_base),
                    Narc => try readNarcFile(file, allocator, fat_entry, img_base),
                    else => comptime unreachable,
                });

                stack.append(State{
                    .folder = folder,
                    .file_id = file_id + 1,
                    .fnt_sub_table = mem_stream.slice[mem_stream.pos..],
                }) catch unreachable;
            },
            .folder => {
                const read_id = try stream.readIntLittle(u16);
                if (read_id < 0xF001 or read_id > 0xFFFF)
                    return error.InvalidSubDirectoryId;

                const id = read_id & 0x0FFF;
                if (fnt_main_table.len <= id)
                    return error.InvalidSubDirectoryId;

                const fnt_entry = fnt_main_table[id];
                const sub_folder = try folder.createFolder(name);

                const offset = fnt_entry.offset_to_subtable.value();
                if (fnt.len < offset)
                    return error.InvalidFnt;

                stack.append(State{
                    .folder = folder,
                    .file_id = file_id,
                    .fnt_sub_table = mem_stream.slice[mem_stream.pos..],
                }) catch unreachable;
                try stack.append(State{
                    .folder = sub_folder,
                    .file_id = fnt_entry.first_file_id_in_subtable.value(),
                    .fnt_sub_table = fnt[offset..],
                });
            },
        }
    }

    return root;
}

pub fn readNitroFile(file: std.fs.File, allocator: *mem.Allocator, fat_entry: FatEntry, img_base: usize) !Nitro.File {
    var file_in_stream = file.inStream();

    narc_read: {
        const names = formats.Chunk.names;

        try file.seekTo(fat_entry.start.value() + img_base);
        const file_start = try file.getPos();

        var buffered_in_stream = io.BufferedInStream(std.fs.File.InStream.Error).init(&file_in_stream.stream);
        const stream = &buffered_in_stream.stream;

        const header = stream.readStruct(formats.Header) catch break :narc_read;
        if (!mem.eql(u8, header.chunk_name, names.narc))
            break :narc_read;
        if (header.byte_order.value() != 0xFFFE)
            break :narc_read;
        if (header.chunk_size.value() != 0x0010)
            break :narc_read;
        if (header.following_chunks.value() != 0x0003)
            break :narc_read;

        // If we have a valid narc header, then we assume we are reading a narc
        // file. All error from here, are therefore bubbled up.
        const fat_header = try stream.readStruct(formats.FatChunk);
        const fat_size = math.sub(u32, fat_header.header.size.value(), @sizeOf(formats.FatChunk)) catch return error.InvalidChunkSize;

        if (!mem.eql(u8, fat_header.header.name, names.fat))
            return error.InvalidChunkName;
        if (fat_size % @sizeOf(FatEntry) != 0)
            return error.InvalidChunkSize;
        if (fat_size / @sizeOf(FatEntry) != fat_header.file_count.value())
            return error.InvalidChunkSize;

        const fat = try allocator.alloc(FatEntry, fat_header.file_count.value());
        defer allocator.free(fat);
        try stream.readNoEof(@sliceToBytes(fat));

        const fnt_header = try stream.readStruct(formats.Chunk);
        const fnt_size = math.sub(u32, fnt_header.size.value(), @sizeOf(formats.Chunk)) catch return error.InvalidChunkSize;

        if (!mem.eql(u8, fnt_header.name, names.fnt))
            return error.InvalidChunkName;

        const fnt = try allocator.alloc(u8, fnt_size);
        defer allocator.free(fnt);
        try stream.readNoEof(fnt);

        const rem = fnt.len % @sizeOf(FntMainEntry);
        const fnt_mains = @bytesToSlice(FntMainEntry, fnt[0 .. fnt.len - rem]);
        if (fnt_mains.len == 0)
            return error.InvalidChunkSize;

        const first_fnt = fnt_mains[0];
        const file_data_header = try stream.readStruct(formats.Chunk);
        if (!mem.eql(u8, file_data_header.name, names.file_data))
            return error.InvalidChunkName;

        // Since we are using buffered input, be have to seek back to the narc_img_base,
        // when we start reading the file system
        const narc_img_base = file_start + @sizeOf(formats.Header) + fat_header.header.size.value() + fnt_header.size.value() + @sizeOf(formats.Chunk);
        try file.seekTo(narc_img_base);

        // If the first_fnt's offset points into it self, then there doesn't exist an
        // fnt sub table and files don't have names. We therefore can't use our normal
        // read function, as it relies on the fnt sub table to build the file system.
        if (first_fnt.offset_to_subtable.value() < @sizeOf(FntMainEntry)) {
            const narc = try Narc.create(allocator);

            for (fat) |entry, i| {
                var buf: [10]u8 = undefined;
                const sub_file_name = try fmt.bufPrint(buf[0..], "{}", i);
                const sub_file = try readNarcFile(file, allocator, entry, narc_img_base);
                _ = try narc.createFile(sub_file_name, sub_file);
            }

            return Nitro.File{ .narc = narc };
        } else {
            return Nitro.File{ .narc = try readNarc(file, allocator, fnt, fat, narc_img_base) };
        }
    }

    try file.seekTo(fat_entry.start.value() + img_base);
    const data = try allocator.alloc(u8, fat_entry.size());
    errdefer allocator.free(data);
    try file_in_stream.stream.readNoEof(data);

    return Nitro.File{
        .binary = Nitro.File.Binary{
            .allocator = allocator,
            .data = data,
        },
    };
}

pub fn readNarcFile(file: std.fs.File, allocator: *mem.Allocator, fat_entry: FatEntry, img_base: usize) !Narc.File {
    var file_in_stream = file.inStream();
    const stream = &file_in_stream.stream;

    try file.seekTo(fat_entry.start.value() + img_base);
    const data = try allocator.alloc(u8, fat_entry.size());
    errdefer allocator.free(data);
    try stream.readNoEof(data);

    return Narc.File{
        .allocator = allocator,
        .data = data,
    };
}

pub fn FntAndFiles(comptime FileType: type) type {
    return struct {
        files: []*FileType,
        main_fnt: []FntMainEntry,
        sub_fnt: []const u8,
    };
}

pub fn getFntAndFiles(comptime F: type, root: *F, allocator: *mem.Allocator) !FntAndFiles(F.File) {
    comptime debug.assert(F == Nitro or F == Narc);

    var files = std.ArrayList(*F.File).init(allocator);
    var main_fnt = std.ArrayList(FntMainEntry).init(allocator);
    var sub_fnt = try std.Buffer.initSize(allocator, 0);

    const State = struct {
        folder: *F,
        parent_id: u16,
    };
    var states = std.ArrayList(State).init(allocator);
    var current_state: u16 = 0;

    defer states.deinit();
    try states.append(State{
        .folder = root,
        .parent_id = undefined, // We don't know the parent_id of root yet. Filling it out later
    });

    while (current_state < states.len) : (current_state += 1) {
        const state = states.toSliceConst()[current_state];

        try main_fnt.append(FntMainEntry{
            // We don't know the exect offset yet, but we can save the offset from the sub tables
            // base, and then calculate the real offset later.
            .offset_to_subtable = lu32.init(@intCast(u32, sub_fnt.len())),
            .first_file_id_in_subtable = lu16.init(@intCast(u16, files.len)),
            .parent_id = lu16.init(state.parent_id),
        });

        for (state.folder.nodes.toSliceConst()) |node| {
            // The filesystem should uphold the invariant that nodes have names that are not
            // zero length.
            debug.assert(node.name.len != 0x00);

            switch (node.kind) {
                .folder => |folder| {
                    try sub_fnt.appendByte(@intCast(u8, node.name.len + 0x80));
                    try sub_fnt.append(node.name);
                    try sub_fnt.append(lu16.init(@intCast(u16, states.len + 0xF000)).bytes);

                    try states.append(State{
                        .folder = folder,
                        .parent_id = current_state + 0xF000,
                    });
                },
                .file => |f| {
                    try sub_fnt.appendByte(@intCast(u8, node.name.len));
                    try sub_fnt.append(node.name);
                    try files.append(f);
                },
            }
        }

        try sub_fnt.appendByte(0x00);
    }

    // Filling in root parent id
    main_fnt.items[0].parent_id = lu16.init(@intCast(u16, main_fnt.len));

    // We now know the real offset_to_subtable, and can therefore fill it out.
    for (main_fnt.toSlice()) |*entry| {
        const main_fnt_len = main_fnt.len * @sizeOf(FntMainEntry);
        const offset_from_subtable_base = entry.offset_to_subtable.value();
        entry.offset_to_subtable = lu32.init(@intCast(u32, offset_from_subtable_base + main_fnt_len));
    }

    return FntAndFiles(F.File){
        .files = files.toOwnedSlice(),
        .main_fnt = main_fnt.toOwnedSlice(),
        .sub_fnt = sub_fnt.list.toOwnedSlice(),
    };
}

pub fn writeNitroFile(file: std.fs.File, allocator: *mem.Allocator, fs_file: Nitro.File) !void {
    switch (fs_file) {
        .binary => |bin| {
            try file.write(bin.data);
        },
        .narc => |narc| {
            const fntAndFiles = try getFntAndFiles(Narc, narc, allocator);
            const files = fntAndFiles.files;
            const main_fnt = fntAndFiles.main_fnt;
            const sub_fnt = fntAndFiles.sub_fnt;
            defer {
                allocator.free(files);
                allocator.free(main_fnt);
                allocator.free(sub_fnt);
            }

            const file_start = try file.getPos();
            const fat_start = file_start + @sizeOf(formats.Header);
            const fnt_start = fat_start + @sizeOf(formats.FatChunk) + files.len * @sizeOf(FatEntry);
            const fnt_end = fnt_start + @sizeOf(formats.Chunk) + sub_fnt.len + main_fnt.len * @sizeOf(FntMainEntry);
            const file_image_start = mem.alignForward(fnt_end, u32(0x4));
            const narc_img_base = file_image_start + @sizeOf(formats.Chunk);
            const file_end = blk: {
                var res = narc_img_base;
                for (files) |f| {
                    res += f.data.len;
                }

                break :blk res;
            };

            var file_out_stream = file.outStream();
            var buffered_out_stream = io.BufferedOutStream(std.fs.File.OutStream.Error).init(&file_out_stream.stream);

            const stream = &buffered_out_stream.stream;

            try stream.write(mem.toBytes(formats.Header.narc(@intCast(u32, file_end - file_start))));
            try stream.write(mem.toBytes(formats.FatChunk{
                .header = formats.Chunk{
                    .name = formats.Chunk.names.fat,
                    .size = lu32.init(@intCast(u32, fnt_start - fat_start)),
                },
                .file_count = lu16.init(@intCast(u16, files.len)),
                .reserved = lu16.init(0x00),
            }));

            var start: u32 = 0;
            for (files) |f| {
                const len = @intCast(u32, f.data.len);
                const fat_entry = FatEntry.init(start, len);
                try stream.write(mem.toBytes(fat_entry));
                start += len;
            }

            try stream.write(mem.toBytes(formats.Chunk{
                .name = formats.Chunk.names.fnt,
                .size = lu32.init(@intCast(u32, file_image_start - fnt_start)),
            }));
            try stream.write(@sliceToBytes(main_fnt));
            try stream.write(sub_fnt);
            try stream.writeByteNTimes(0xFF, file_image_start - fnt_end);

            try stream.write(mem.toBytes(formats.Chunk{
                .name = formats.Chunk.names.file_data,
                .size = lu32.init(@intCast(u32, file_end - file_image_start)),
            }));
            for (files) |f| {
                try stream.write(f.data);
            }

            try buffered_out_stream.flush();
        },
    }
}

const nds = @import("../nds.zig");
const int = @import("../int.zig");
const std = @import("std");

const debug = std.debug;
const fmt = std.fmt;
const fs = nds.fs;
const heap = std.heap;
const mem = std.mem;
const os = std.os;
const rand = std.rand;

const lu16 = int.lu16;
const lu32 = int.lu32;
const lu64 = int.lu64;
const lu128 = int.lu128;

fn countParents(comptime Folder: type, folder: *Folder) usize {
    var res: usize = 0;
    var tmp = folder;
    while (tmp.parent) |par| {
        tmp = par;
        res += 1;
    }

    return res;
}

fn randomFs(allocator: *mem.Allocator, random: *rand.Random, comptime Folder: type) !*Folder {
    comptime debug.assert(Folder == fs.Nitro or Folder == fs.Narc);

    const root = try Folder.create(allocator);
    var unique: u64 = 0;
    var curr: ?*Folder = root;
    while (curr) |folder| {
        const parents = countParents(Folder, folder);
        const choice = random.range(usize, 0, 255);
        if (choice < parents + folder.nodes.len) {
            curr = folder.parent;
            break;
        }

        const is_file = random.scalar(bool);
        var name_buf: [50]u8 = undefined;
        const name = try fmt.bufPrint(name_buf[0..], "{}", unique);
        unique += 1;

        if (is_file) {
            switch (Folder) {
                fs.Nitro => {
                    _ = try folder.createFile(name, blk: {
                        const is_narc = random.scalar(bool);

                        if (is_narc) {
                            break :blk fs.Nitro.File{ .Narc = try randomFs(allocator, random, fs.Narc) };
                        }

                        const data = try allocator.alloc(u8, random.range(usize, 10, 100));
                        random.bytes(data);
                        break :blk fs.Nitro.File{
                            .Binary = fs.Nitro.File.Binary{
                                .allocator = allocator,
                                .data = data,
                            },
                        };
                    });
                },
                fs.Narc => {
                    const data = try allocator.alloc(u8, random.range(usize, 10, 100));
                    random.bytes(data);
                    _ = try folder.createFile(name, fs.Narc.File{
                        .allocator = allocator,
                        .data = data,
                    });
                },
                else => comptime unreachable,
            }
        } else {
            curr = try folder.createFolder(name);
        }
    }

    return root;
}

fn fsEqual(allocator: *mem.Allocator, comptime Folder: type, fs1: *Folder, fs2: *Folder) !bool {
    comptime debug.assert(Folder == fs.Nitro or Folder == fs.Narc);

    const FolderPair = struct {
        f1: *Folder,
        f2: *Folder,
    };

    var folders_to_compare = std.ArrayList(FolderPair).init(allocator);
    defer folders_to_compare.deinit();
    try folders_to_compare.append(FolderPair{
        .f1 = fs1,
        .f2 = fs2,
    });

    while (folders_to_compare.popOrNull()) |pair| {
        for (pair.f1.nodes.toSliceConst()) |n1| {
            switch (n1.kind) {
                Folder.Node.Kind.File => |f1| {
                    const f2 = pair.f2.getFile(n1.name) orelse return false;
                    switch (Folder) {
                        fs.Nitro => {
                            const Tag = @TagType(fs.Nitro.File);
                            switch (f1.*) {
                                Tag.Binary => {
                                    if (f2.* != Tag.Binary)
                                        return false;
                                    if (!mem.eql(u8, f1.Binary.data, f2.Binary.data))
                                        return false;
                                },
                                Tag.Narc => {
                                    if (f2.* != Tag.Narc)
                                        return false;
                                    if (!try fsEqual(allocator, fs.Narc, f1.Narc, f2.Narc))
                                        return false;
                                },
                            }
                        },
                        fs.Narc => {
                            if (!mem.eql(u8, f1.data, f2.data))
                                return false;
                        },
                        else => comptime unreachable,
                    }
                },
                Folder.Node.Kind.Folder => |f1| {
                    const f2 = pair.f2.getFolder(n1.name) orelse return false;
                    try folders_to_compare.append(FolderPair{
                        .f1 = f1,
                        .f2 = f2,
                    });
                },
            }
        }
    }

    return true;
}

const TestFolder = fs.Folder(struct {
    // TODO: We cannot compare pointers to zero sized types, so this field have to exist.
    a: u8,

    fn deinit(file: *@This()) void {}
});

fn assertError(res: var, expected: anyerror) void {
    if (res) |_| {
        unreachable;
    } else |actual| {
        debug.assert(expected == actual);
    }
}

test "nds.fs.Folder.deinit" {
    var buf: [2 * 1024]u8 = undefined;
    var fix_buf_alloc = heap.FixedBufferAllocator.init(buf[0..]);
    const allocator = &fix_buf_alloc.allocator;

    const root = try TestFolder.create(allocator);
    root.deinit();
}

test "nds.fs.Folder.createFile" {
    var buf: [2 * 1024]u8 = undefined;
    var fix_buf_alloc = heap.FixedBufferAllocator.init(buf[0..]);
    const allocator = &fix_buf_alloc.allocator;

    const root = try TestFolder.create(allocator);

    const a = try root.createFile("a", undefined);
    const b = root.getFile("a") orelse unreachable;
    debug.assert(@ptrToInt(a) == @ptrToInt(b));

    assertError(root.createFile("a", undefined), error.NameExists);
    assertError(root.createFile("/", undefined), error.InvalidName);
}

test "nds.fs.Folder.createFolder" {
    var buf: [2 * 1024]u8 = undefined;
    var fix_buf_alloc = heap.FixedBufferAllocator.init(buf[0..]);
    const allocator = &fix_buf_alloc.allocator;

    const root = try TestFolder.create(allocator);

    const a = try root.createFolder("a");
    const b = root.getFolder("a") orelse unreachable;
    debug.assert(@ptrToInt(a) == @ptrToInt(b));

    assertError(root.createFolder("a"), error.NameExists);
    assertError(root.createFolder("/"), error.InvalidName);
}

test "nds.fs.Folder.createPath" {
    var buf: [3 * 1024]u8 = undefined;
    var fix_buf_alloc = heap.FixedBufferAllocator.init(buf[0..]);
    const allocator = &fix_buf_alloc.allocator;

    const root = try TestFolder.create(allocator);
    const a = try root.createPath("b/a");
    const b = root.getFolder("b/a") orelse unreachable;
    debug.assert(@ptrToInt(a) == @ptrToInt(b));

    _ = try root.createFile("a", undefined);
    assertError(root.createPath("a"), error.FileInPath);
}

test "nds.fs.Folder.getFile" {
    var buf: [2 * 1024]u8 = undefined;
    var fix_buf_alloc = heap.FixedBufferAllocator.init(buf[0..]);
    const allocator = &fix_buf_alloc.allocator;

    const root = try TestFolder.create(allocator);
    const a = try root.createFolder("a");
    _ = try root.createFile("a1", undefined);
    _ = try a.createFile("a2", undefined);

    const a1 = root.getFile("a1") orelse unreachable;
    const a2 = a.getFile("a2") orelse unreachable;
    const a1_root = a.getFile("/a1") orelse unreachable;
    debug.assert(root.getFile("a2") == null);
    debug.assert(a.getFile("a1") == null);

    const a2_path = root.getFile("a/a2") orelse unreachable;
    debug.assert(@ptrToInt(a1) == @ptrToInt(a1_root));
    debug.assert(@ptrToInt(a2) == @ptrToInt(a2_path));
}

test "nds.fs.Folder.getFolder" {
    var buf: [3 * 1024]u8 = undefined;
    var fix_buf_alloc = heap.FixedBufferAllocator.init(buf[0..]);
    const allocator = &fix_buf_alloc.allocator;

    const root = try TestFolder.create(allocator);
    const a = try root.createFolder("a");
    _ = try root.createFolder("a1");
    _ = try a.createFolder("a2");

    const a1 = root.getFolder("a1") orelse unreachable;
    const a2 = a.getFolder("a2") orelse unreachable;
    const a1_root = a.getFolder("/a1") orelse unreachable;
    debug.assert(root.getFolder("a2") == null);
    debug.assert(a.getFolder("a1") == null);

    const a2_path = root.getFolder("a/a2") orelse unreachable;
    debug.assert(@ptrToInt(a1) == @ptrToInt(a1_root));
    debug.assert(@ptrToInt(a2) == @ptrToInt(a2_path));
}

test "nds.fs.Folder.exists" {
    var buf: [2 * 1024]u8 = undefined;
    var fix_buf_alloc = heap.FixedBufferAllocator.init(buf[0..]);
    const allocator = &fix_buf_alloc.allocator;

    const root = try TestFolder.create(allocator);
    _ = try root.createFolder("a");
    _ = try root.createFile("b", undefined);

    debug.assert(root.exists("a"));
    debug.assert(root.exists("b"));
    debug.assert(!root.exists("c"));
}

test "nds.fs.Folder.root" {
    var buf: [7 * 1024]u8 = undefined;
    var fix_buf_alloc = heap.FixedBufferAllocator.init(buf[0..]);
    const allocator = &fix_buf_alloc.allocator;

    const root = try TestFolder.create(allocator);
    const a = try root.createPath("a");
    const b = try root.createPath("a/b");
    const c = try root.createPath("a/b/c");
    const d = try root.createPath("c/b/d");
    debug.assert(@ptrToInt(root) == @ptrToInt(root.root()));
    debug.assert(@ptrToInt(root) == @ptrToInt(a.root()));
    debug.assert(@ptrToInt(root) == @ptrToInt(b.root()));
    debug.assert(@ptrToInt(root) == @ptrToInt(c.root()));
    debug.assert(@ptrToInt(root) == @ptrToInt(d.root()));
}

test "nds.fs.read/writeNitro" {
    var buf: [400 * 1024]u8 = undefined;
    var fix_buf_alloc = heap.FixedBufferAllocator.init(buf[0..]);
    var random = rand.DefaultPrng.init(0);

    const allocator = &fix_buf_alloc.allocator;

    const root = try randomFs(allocator, &random.random, fs.Nitro);
    const fntAndFiles = try fs.getFntAndFiles(fs.Nitro, root, allocator);
    const files = fntAndFiles.files;
    const main_fnt = fntAndFiles.main_fnt;
    const sub_fnt = fntAndFiles.sub_fnt;

    const fnt_buff_size = @sliceToBytes(main_fnt).len + sub_fnt.len;
    const fnt_buff = try allocator.alloc(u8, fnt_buff_size);
    const fnt = try fmt.bufPrint(fnt_buff, "{}{}", @sliceToBytes(main_fnt), sub_fnt);
    var fat = std.ArrayList(fs.FatEntry).init(allocator);

    const test_file = "__nds.fs.test.read.write__";
    defer std.fs.deleteFile(test_file) catch unreachable;

    {
        var file = try std.fs.File.openWrite(test_file);
        defer file.close();

        for (files) |f| {
            const pos = @intCast(u32, try file.getPos());
            try fs.writeNitroFile(file, allocator, f.*);
            fat.append(fs.FatEntry.init(pos, @intCast(u32, try file.getPos()) - pos)) catch unreachable;
        }
    }

    const fs2 = blk: {
        var file = try std.fs.File.openRead(test_file);
        defer file.close();
        break :blk try fs.readNitro(file, allocator, fnt, fat.toSlice());
    };

    debug.assert(try fsEqual(allocator, fs.Nitro, root, fs2));
}

test "nds.Rom" {
    var buf: [400 * 1024]u8 = undefined;
    var fix_buf_alloc = heap.FixedBufferAllocator.init(buf[0..]);
    var random = rand.DefaultPrng.init(1);

    const allocator = &fix_buf_alloc.allocator;

    var rom1 = nds.Rom{
        .allocator = allocator,
        .header = nds.Header{
            .game_title = "A" ** 12,
            .gamecode = "A" ** 4,
            .makercode = "ST",
            .unitcode = 0x00,
            .encryption_seed_select = 0x00,
            .device_capacity = 0x00,
            .reserved1 = [_]u8{0} ** 7,
            .reserved2 = 0x00,
            .nds_region = 0x00,
            .rom_version = 0x00,
            .autostart = 0x00,
            .arm9_rom_offset = lu32.init(0x4000),
            .arm9_entry_address = lu32.init(0x2000000),
            .arm9_ram_address = lu32.init(0x2000000),
            .arm9_size = lu32.init(0x3BFE00),
            .arm7_rom_offset = lu32.init(0x8000),
            .arm7_entry_address = lu32.init(0x2000000),
            .arm7_ram_address = lu32.init(0x2000000),
            .arm7_size = lu32.init(0x3BFE00),
            .fnt_offset = lu32.init(0x00),
            .fnt_size = lu32.init(0x00),
            .fat_offset = lu32.init(0x00),
            .fat_size = lu32.init(0x00),
            .arm9_overlay_offset = lu32.init(0x00),
            .arm9_overlay_size = lu32.init(0x00),
            .arm7_overlay_offset = lu32.init(0x00),
            .arm7_overlay_size = lu32.init(0x00),
            .port_40001A4h_setting_for_normal_commands = [_]u8{0} ** 4,
            .port_40001A4h_setting_for_key1_commands = [_]u8{0} ** 4,
            .banner_offset = lu32.init(0x00),
            .secure_area_checksum = lu16.init(0x00),
            .secure_area_delay = lu16.init(0x051E),
            .arm9_auto_load_list_ram_address = lu32.init(0x00),
            .arm7_auto_load_list_ram_address = lu32.init(0x00),
            .secure_area_disable = lu64.init(0x00),
            .total_used_rom_size = lu32.init(0x00),
            .rom_header_size = lu32.init(0x4000),
            .reserved3 = [_]u8{0x00} ** 0x38,
            .nintendo_logo = [_]u8{0x00} ** 0x9C,
            .nintendo_logo_checksum = lu16.init(0x00),
            .header_checksum = lu16.init(0x00),
            .debug_rom_offset = lu32.init(0x00),
            .debug_size = lu32.init(0x00),
            .debug_ram_address = lu32.init(0x00),
            .reserved4 = [_]u8{0x00} ** 4,
            .reserved5 = [_]u8{0x00} ** 0x10,
            .wram_slots = [_]u8{0x00} ** 20,
            .arm9_wram_areas = [_]u8{0x00} ** 12,
            .arm7_wram_areas = [_]u8{0x00} ** 12,
            .wram_slot_master = [_]u8{0x00} ** 3,
            .unknown = 0,
            .region_flags = [_]u8{0x00} ** 4,
            .access_control = [_]u8{0x00} ** 4,
            .arm7_scfg_ext_setting = [_]u8{0x00} ** 4,
            .reserved6 = [_]u8{0x00} ** 3,
            .unknown_flags = 0,
            .arm9i_rom_offset = lu32.init(0x00),
            .reserved7 = [_]u8{0x00} ** 4,
            .arm9i_ram_load_address = lu32.init(0x00),
            .arm9i_size = lu32.init(0x00),
            .arm7i_rom_offset = lu32.init(0x00),
            .device_list_arm7_ram_addr = lu32.init(0x00),
            .arm7i_ram_load_address = lu32.init(0x00),
            .arm7i_size = lu32.init(0x00),
            .digest_ntr_region_offset = lu32.init(0x4000),
            .digest_ntr_region_length = lu32.init(0x00),
            .digest_twl_region_offset = lu32.init(0x00),
            .digest_twl_region_length = lu32.init(0x00),
            .digest_sector_hashtable_offset = lu32.init(0x00),
            .digest_sector_hashtable_length = lu32.init(0x00),
            .digest_block_hashtable_offset = lu32.init(0x00),
            .digest_block_hashtable_length = lu32.init(0x00),
            .digest_sector_size = lu32.init(0x00),
            .digest_block_sectorcount = lu32.init(0x00),
            .banner_size = lu32.init(0x00),
            .reserved8 = [_]u8{0x00} ** 4,
            .total_used_rom_size_including_dsi_area = lu32.init(0x00),
            .reserved9 = [_]u8{0x00} ** 4,
            .reserved10 = [_]u8{0x00} ** 4,
            .reserved11 = [_]u8{0x00} ** 4,
            .modcrypt_area_1_offset = lu32.init(0x00),
            .modcrypt_area_1_size = lu32.init(0x00),
            .modcrypt_area_2_offset = lu32.init(0x00),
            .modcrypt_area_2_size = lu32.init(0x00),
            .title_id_emagcode = [_]u8{0x00} ** 4,
            .title_id_filetype = 0,
            .title_id_rest = [_]u8{ 0x00, 0x03, 0x00 },
            .public_sav_filesize = lu32.init(0x00),
            .private_sav_filesize = lu32.init(0x00),
            .reserved12 = [_]u8{0x00} ** 176,
            .cero_japan = 0,
            .esrb_us_canada = 0,
            .reserved13 = 0,
            .usk_germany = 0,
            .pegi_pan_europe = 0,
            .resereved14 = 0,
            .pegi_portugal = 0,
            .pegi_and_bbfc_uk = 0,
            .agcb_australia = 0,
            .grb_south_korea = 0,
            .reserved15 = [_]u8{0x00} ** 6,
            .arm9_hash_with_secure_area = [_]u8{0x00} ** 20,
            .arm7_hash = [_]u8{0x00} ** 20,
            .digest_master_hash = [_]u8{0x00} ** 20,
            .icon_title_hash = [_]u8{0x00} ** 20,
            .arm9i_hash = [_]u8{0x00} ** 20,
            .arm7i_hash = [_]u8{0x00} ** 20,
            .reserved16 = [_]u8{0x00} ** 40,
            .arm9_hash_without_secure_area = [_]u8{0x00} ** 20,
            .reserved17 = [_]u8{0x00} ** 2636,
            .reserved18 = [_]u8{0x00} ** 0x180,
            .signature_across_header_entries = [_]u8{0x00} ** 0x80,
        },
        .banner = nds.Banner{
            .version = 0x1,
            .has_animated_dsi_icon = 0,
            .crc16_across_0020h_083Fh = lu16.init(0x00),
            .crc16_across_0020h_093Fh = lu16.init(0x00),
            .crc16_across_0020h_0A3Fh = lu16.init(0x00),
            .crc16_across_1240h_23BFh = lu16.init(0x00),
            .reserved1 = [_]u8{0x00} ** 0x16,
            .icon_bitmap = [_]u8{0x00} ** 0x200,
            .icon_palette = [_]u8{0x00} ** 0x20,
            .title_japanese = [_]u8{0x00} ** 0x100,
            .title_english = [_]u8{0x00} ** 0x100,
            .title_french = [_]u8{0x00} ** 0x100,
            .title_german = [_]u8{0x00} ** 0x100,
            .title_italian = [_]u8{0x00} ** 0x100,
            .title_spanish = [_]u8{0x00} ** 0x100,
        },
        .arm9 = [_]u8{},
        .arm7 = [_]u8{},
        .nitro_footer = [_]lu32{
            lu32.init(0),
            lu32.init(0),
            lu32.init(0),
        },
        .arm9_overlay_table = [_]nds.Overlay{},
        .arm9_overlay_files = [_][]u8{},
        .arm7_overlay_table = [_]nds.Overlay{},
        .arm7_overlay_files = [_][]u8{},
        .root = try randomFs(allocator, &random.random, fs.Nitro),
    };

    const name = try fmt.allocPrint(allocator, "__{}_{}__", rom1.header.game_title, rom1.header.gamecode);
    errdefer allocator.free(name);

    {
        const file = try std.fs.File.openWrite(name);
        errdefer std.fs.deleteFile(name) catch {};
        defer file.close();

        try rom1.writeToFile(file);
    }
    defer std.fs.deleteFile(name) catch {};

    var rom2 = blk: {
        const file = try std.fs.File.openRead(name);
        defer file.close();
        break :blk try nds.Rom.fromFile(file, allocator);
    };
    defer rom2.deinit();
}

const clap = @import("clap");
const std = @import("std");
const util = @import("util");

const load = @import("tm35-load.zig");
const apply = @import("tm35-apply.zig");

const common = @import("common.zig");
const gen3 = @import("gen3.zig");
const gen4 = @import("gen4.zig");
const gen5 = @import("gen5.zig");
const rom = @import("rom.zig");

const debug = std.debug;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const os = std.os;
const testing = std.testing;

const lu16 = rom.int.lu16;
const lu32 = rom.int.lu32;
const lu64 = rom.int.lu64;

const StdIo = util.CustomStdIoStreams(
    std.io.FixedBufferStream([]u8).InStream,
    std.io.FixedBufferStream([]u8).OutStream,
);

test "load/apply" {
    const gen_buf = try std.heap.page_allocator.alloc(u8, 25 * 1024 * 1024);
    defer std.heap.page_allocator.free(gen_buf);

    const program_buf = try std.heap.page_allocator.alloc(u8, 18 * 1024 * 1024);
    defer std.heap.page_allocator.free(program_buf);

    const out_buf = try std.heap.page_allocator.alloc(u8, 4 * 1024 * 1024);
    defer std.heap.page_allocator.free(out_buf);

    var gen_fba = heap.FixedBufferAllocator.init(gen_buf);
    deleteFakeRoms();
    const roms = try generateFakeRoms(&gen_fba.allocator);

    var stderr_buf: [1024]u8 = undefined;
    for (roms) |rom_path| {
        var stderr = io.fixedBufferStream(&stderr_buf);
        var fba = heap.FixedBufferAllocator.init(program_buf);

        var load_stdout = io.fixedBufferStream(out_buf);
        var load_args = clap.args.SliceIterator{ .args = &[_][]const u8{rom_path} };
        const load_res = load.main2(
            &fba.allocator,
            StdIo.InStream,
            StdIo.OutStream,
            StdIo{
                .in = undefined,
                .out = load_stdout.outStream(),
                .err = stderr.outStream(),
            },
            clap.args.SliceIterator,
            &load_args,
        );
        debug.warn("{}", .{stderr.getWritten()});
        testing.expectEqual(@as(u8, 0), load_res);
        testing.expectEqualSlices(u8, "", stderr.getWritten());

        const load_written = load_stdout.getWritten();

        // Validate that certain entries are outputted for
        // all generations of games
        for ([_][]const u8{
            ".starters[0]=",
            ".starters[1]=",
            ".starters[2]=",
            ".trainers[0].party[0].iv=",
            ".trainers[0].party[0].level=",
            ".trainers[0].party[0].species=",
            ".trainers[0].items[0]=",
            ".moves[0].power=",
            ".moves[0].type=",
            ".moves[0].accuracy=",
            ".moves[0].pp=",
            ".pokemons[0].stats.hp=",
            ".pokemons[0].stats.attack=",
            ".pokemons[0].stats.defense=",
            ".pokemons[0].stats.speed=",
            ".pokemons[0].stats.sp_attack=",
            ".pokemons[0].stats.sp_defense=",
            ".pokemons[0].types[0]=",
            ".pokemons[0].items[0]=",
            ".pokemons[0].abilities[0]=",
            ".pokemons[0].evos[0].target=",
            ".pokemons[0].evos[0].method=",
            ".pokemons[0].tms[0]=",
            ".pokemons[0].hms[0]=",
            ".pokemons[0].moves[0].id=",
            ".pokemons[0].moves[0].level=",
            ".tms[0]=",
            ".hms[0]=",
            ".zones[0].wild.surf.encounter_rate=",
            ".zones[0].wild.surf.pokemons[0].min_level=",
            ".zones[0].wild.surf.pokemons[0].max_level=",
            ".zones[0].wild.surf.pokemons[0].species=",
        }) |expected_string| {
            if (mem.indexOf(u8, load_written, expected_string) == null) {
                debug.warn("{}\n", .{load_written});
                debug.warn("{}\n", .{rom_path});
                debug.warn("Could not find {}\n", .{expected_string});
                testing.expect(false);
            }
        }

        validateThatAllNumbersAre(load_written, 0);
        changeAllNumberValuesTo(load_written, 1);

        fba = heap.FixedBufferAllocator.init(program_buf);
        var apply_stdin = io.fixedBufferStream(load_written);
        var apply_args = clap.args.SliceIterator{
            .args = &[_][]const u8{
                rom_path,
                "-o",
                rom_path,
                "--replace",
            },
        };
        const apply_res = apply.main2(
            &fba.allocator,
            StdIo.InStream,
            StdIo.OutStream,
            StdIo{
                .in = apply_stdin.inStream(),
                .out = undefined,
                .err = stderr.outStream(),
            },
            clap.args.SliceIterator,
            &apply_args,
        );
        debug.warn("{}", .{stderr.getWritten()});
        testing.expectEqual(@as(u8, 0), apply_res);
        testing.expectEqualSlices(u8, "", stderr.getWritten());

        fba = heap.FixedBufferAllocator.init(program_buf);
        load_stdout = io.fixedBufferStream(out_buf);
        load_args = clap.args.SliceIterator{ .args = &[_][]const u8{rom_path} };
        const load_res2 = load.main2(
            &fba.allocator,
            StdIo.InStream,
            StdIo.OutStream,
            StdIo{
                .in = undefined,
                .out = load_stdout.outStream(),
                .err = stderr.outStream(),
            },
            clap.args.SliceIterator,
            &load_args,
        );
        debug.warn("{}", .{stderr.getWritten()});
        testing.expectEqual(@as(u8, 0), load_res2);
        testing.expectEqualSlices(u8, "", stderr.getWritten());

        const load_written2 = load_stdout.getWritten();
        validateThatAllNumbersAre(load_written2, 1);
    }
}

fn validateThatAllNumbersAre(text: []const u8, num: usize) void {
    var lines = mem.split(text, "\n");
    while (lines.next()) |line| {
        const eql = mem.indexOfScalar(u8, line, '=') orelse continue;
        const value_str = line[eql + 1 ..];
        const value = fmt.parseInt(usize, value_str, 10) catch continue;
        if (num != value) {
            debug.warn("{}\n", .{line});
            testing.expectEqual(num, value);
        }
    }
}

fn changeAllNumberValuesTo(text: []u8, num: usize) void {
    var lines = mem.split(text, "\n");
    while (lines.next()) |line| {
        const eql = mem.indexOfScalar(u8, line, '=') orelse continue;
        const value_str = line[eql + 1 ..];
        const value = fmt.parseInt(usize, value_str, 10) catch continue;
        const index_in_text = util.indexOfPtr(u8, text, &value_str[0]);

        var buf: [1]u8 = undefined;
        _ = fmt.bufPrint(&buf, "{}", .{num}) catch continue;
        mem.set(u8, text[index_in_text..][0..value_str.len], buf[0]);
    }
}

const tmp_folder = "zig-cache" ++ fs.path.sep_str ++ "__fake_roms__" ++ fs.path.sep_str;

fn zeroInit(comptime T: type) T {
    var res: T = undefined;
    mem.set(u8, mem.asBytes(&res), 0);
    return res;
}

pub fn generateFakeRoms(allocator: *mem.Allocator) ![][]u8 {
    const tmp = try allocator.alloc(u8, 20 * 1024 * 1024);
    defer allocator.free(tmp);

    var tmp_fix_buf_alloc = heap.FixedBufferAllocator.init(tmp[0..]);
    const tmp_allocator = &tmp_fix_buf_alloc.allocator;

    deleteFakeRoms();
    try fs.cwd().makeDir(tmp_folder);
    errdefer deleteFakeRoms();

    tmp_fix_buf_alloc = heap.FixedBufferAllocator.init(tmp[0..]);

    var rom_names = std.ArrayList([]u8).init(allocator);
    errdefer {
        for (rom_names.items) |name|
            allocator.free(name);
        rom_names.deinit();
    }

    for (gen3.offsets.infos) |info| {
        const name = try genGen3FakeRom(tmp_allocator, info);
        try rom_names.append(try mem.dupe(allocator, u8, name));
        tmp_fix_buf_alloc = heap.FixedBufferAllocator.init(tmp[0..]);
    }

    for (gen4.offsets.infos) |info| {
        const name = try genGen4FakeRom(tmp_allocator, info);
        try rom_names.append(try mem.dupe(allocator, u8, name));
        tmp_fix_buf_alloc = heap.FixedBufferAllocator.init(tmp[0..]);
    }

    for (gen5.offsets.infos) |info| {
        const name = try genGen5FakeRom(tmp_allocator, info);
        try rom_names.append(try mem.dupe(allocator, u8, name));
        tmp_fix_buf_alloc = heap.FixedBufferAllocator.init(tmp[0..]);
    }

    return rom_names.toOwnedSlice();
}

pub fn deleteFakeRoms() void {
    fs.cwd().deleteTree(tmp_folder) catch {};
}

fn Checklist(comptime size: usize) type {
    return struct {
        const Item = struct {
            name: []const u8,
            checked: bool,
        };

        items: [size]Item,

        pub fn set(list: *@This(), name: []const u8, check: bool) !void {
            for (list.items) |*i| {
                if (mem.eql(u8, i.name, name)) {
                    i.checked = check;
                    return;
                }
            }

            return error.ItemNotFound;
        }

        pub fn all(list: *@This(), check: bool) bool {
            for (list.items) |i| {
                if (i.checked != check)
                    return false;
            }

            return true;
        }
    };
}

fn checklistFromT(comptime T: type) Checklist(@typeInfo(T).Struct.fields.len) {
    const fields = @typeInfo(T).Struct.fields;
    var res: Checklist(fields.len) = undefined;

    inline for (fields) |field, i| {
        res.items[i].name = field.name;
        res.items[i].checked = false;
    }

    return res;
}

fn genGen3FakeRom(allocator: *mem.Allocator, info: gen3.offsets.Info) ![]u8 {
    const Helper = struct {
        fn genWildInfo(buf: []u8, comptime n: comptime_int, free: *u32) !gen3.Ref(gen3.WildPokemonInfo(n)) {
            const wild_offset = free.*;
            const info_offset = free.* + @sizeOf(gen3.WildPokemon) * n;
            var wild_info = zeroInit(gen3.WildPokemonInfo(n));
            wild_info.wild_pokemons = try gen3.Ref([n]gen3.WildPokemon).init(wild_offset);
            mem.copy(u8, buf[info_offset..], &mem.toBytes(wild_info));

            free.* = info_offset + @sizeOf(gen3.WildPokemonInfo(n));
            return try gen3.Ref(gen3.WildPokemonInfo(n)).init(info_offset);
        }

        fn fillSection(buf: []u8, section: var, val: @TypeOf(section).T) !void {
            mem.set(@TypeOf(section).T, section.slice(buf), val);
        }
    };

    const buf = try allocator.alloc(u8, 0x1000000);
    mem.set(u8, buf, 0);

    var free_space_offset = getGen3FreeSpace(info);
    var header = zeroInit(rom.gba.Header);
    header.game_title = info.game_title;
    header.gamecode = info.gamecode;
    header.makercode = "AA".*;
    header.fixed_value = 0x96;
    mem.copy(u8, buf, &mem.toBytes(header));

    // We use a checklist to assert at comptime that we generate info
    // for all fields in gen3.offsets.Info
    comptime var checklist = checklistFromT(gen3.offsets.Info);

    comptime checklist.set("game_title", true) catch unreachable;
    comptime checklist.set("gamecode", true) catch unreachable;
    comptime checklist.set("version", true) catch unreachable;
    comptime checklist.set("software_version", true) catch unreachable;

    // These should just be zero, which the memset above handled
    comptime checklist.set("starters", true) catch unreachable;
    comptime checklist.set("starters_repeat", true) catch unreachable;
    comptime checklist.set("moves", true) catch unreachable;
    comptime checklist.set("machine_learnsets", true) catch unreachable;
    comptime checklist.set("pokemons", true) catch unreachable;
    comptime checklist.set("hms", true) catch unreachable;
    comptime checklist.set("tms", true) catch unreachable;
    comptime checklist.set("items", true) catch unreachable;

    comptime checklist.set("trainers", true) catch unreachable;
    for (info.trainers.slice(buf)) |*trainer, i| {
        const party_offset = free_space_offset;
        const party_len = 3;
        trainer.party = gen3.Party{ .none = try gen3.Slice(gen3.PartyMemberNone).init(party_offset, party_len) };
        trainer.party_type = @intToEnum(gen3.PartyType, @intCast(u8, i % 4));

        switch (trainer.party_type) {
            .none => free_space_offset += party_len * @sizeOf(gen3.PartyMemberNone),
            .item => free_space_offset += party_len * @sizeOf(gen3.PartyMemberItem),
            .moves => free_space_offset += party_len * @sizeOf(gen3.PartyMemberMoves),
            .both => free_space_offset += party_len * @sizeOf(gen3.PartyMemberBoth),
        }
    }

    comptime checklist.set("level_up_learnset_pointers", true) catch unreachable;
    for (info.level_up_learnset_pointers.slice(buf)) |*learnset, i| {
        const learnset_offset = free_space_offset;
        const learned_moves = 3;
        learnset.* = try gen3.Ptr(gen3.LevelUpMove).init(learnset_offset);

        var j: usize = 0;
        while (j < learned_moves) : (j += 1)
            free_space_offset += @sizeOf(gen3.LevelUpMove);
        mem.copy(u8, buf[free_space_offset..], &[_]u8{ 0xFF, 0xFF });
        free_space_offset += @sizeOf(gen3.LevelUpMove);
    }

    comptime checklist.set("wild_pokemon_headers", true) catch unreachable;
    for (info.wild_pokemon_headers.slice(buf)) |*wild_header, i| {
        wild_header.land = try Helper.genWildInfo(buf, 12, &free_space_offset);
        wild_header.surf = try Helper.genWildInfo(buf, 5, &free_space_offset);
        wild_header.rock_smash = try Helper.genWildInfo(buf, 5, &free_space_offset);
        wild_header.fishing = try Helper.genWildInfo(buf, 10, &free_space_offset);
    }

    comptime checklist.set("map_headers", true) catch unreachable;
    for (info.map_headers.slice(buf)) |*map_header, i| {
        const map_events_off = free_space_offset;
        free_space_offset += @sizeOf(gen3.MapEvents);

        const map_script_off = free_space_offset;
        free_space_offset += @sizeOf(gen3.MapScript);

        map_header.map_events = try gen3.Ref(gen3.MapEvents).init(map_events_off);
        map_header.map_scripts = try gen3.Ptr(gen3.MapScript).init(map_script_off);
    }

    comptime checklist.set("evolutions", true) catch unreachable;
    for (info.evolutions.slice(buf)) |*evos|
        evos[0].method = .level_up;

    // Assert that we have generated data for all fields
    comptime std.debug.assert(checklist.all(true));

    const name = try fmt.allocPrint(allocator, "{}__{}_{}_{}__", .{ tmp_folder, info.game_title, info.gamecode, @tagName(info.version) });
    errdefer allocator.free(name);

    errdefer fs.cwd().deleteFile(name) catch {};
    try fs.cwd().writeFile(name, buf);

    return name;
}

fn getGen3FreeSpace(info: gen3.offsets.Info) u32 {
    var res: u32 = 0;
    inline for (@typeInfo(gen3.offsets.Info).Struct.fields) |field| {
        if (@typeInfo(field.field_type) == .Struct and @hasDecl(field.field_type, "end")) {
            res = math.max(res, @intCast(u32, @field(info, field.name).end()));
        }
    }

    return res;
}

fn ndsHeader(game_title: [11:0]u8, gamecode: [4]u8) [0x4000]u8 {
    var res = zeroInit([0x4000]u8);
    const header = @ptrCast(*nds.Header, &res);
    header.game_title = game_title;
    header.gamecode = gamecode;
    header.makercode = "ST".*;
    header.arm9.entry_address = lu32.init(0x2000000);
    header.arm9.ram_address = lu32.init(0x2000000);
    header.arm7.entry_address = lu32.init(0x2000000);
    header.arm7.ram_address = lu32.init(0x2000000);
    header.secure_area_delay = lu16.init(0x051E);
    header.rom_header_size = lu32.init(0x4000);
    header.digest_ntr_region_offset = lu32.init(0x4000);
    header.title_id_rest = [_]u8{ 0x00, 0x03, 0x00 };

    return res;
}

const nds_banner = rom.nds.Banner{
    .version = 1,
    .has_animated_dsi_icon = 0,
    .crc16_across_0020h_083fh = lu16.init(0x00),
    .crc16_across_0020h_093fh = lu16.init(0x00),
    .crc16_across_0020h_0a3fh = lu16.init(0x00),
    .crc16_across_1240h_23bfh = lu16.init(0x00),
    .reserved1 = [_]u8{0x00} ** 0x16,
    .icon_bitmap = [_]u8{0x00} ** 0x200,
    .icon_palette = [_]u8{0x00} ** 0x20,
    .title_japanese = [_]u8{0x00} ** 0x100,
    .title_english = [_]u8{0x00} ** 0x100,
    .title_french = [_]u8{0x00} ** 0x100,
    .title_german = [_]u8{0x00} ** 0x100,
    .title_italian = [_]u8{0x00} ** 0x100,
    .title_spanish = [_]u8{0x00} ** 0x100,
};

fn createNarc(alloc: *mem.Allocator, data: var, count: u32) !void {
    try createNarcData(alloc, mem.toBytes(data)[0..], count, term);
}

fn createNarcData(alloc: *mem.Allocator, data: []const u8, count: u32) !void {
    var res = std.ArrayList(u8).init(alloc);
    defer res.deinit();

    const stream = res.outStream();
    try stream.writeStructure(formats.Header{
        .chunk_name = formats.Chunk.names.narc,
        .byte_order = lu16.init(0xFFFE),
        .chunk_size = lu16.init(0x0010),
        .following_chunks = lu16.init(0x0003),
    });
    try stream.writeStructure(formats.FatChunk{
        .header = .{
            .name = formats.Chunk.names.fat,
            .size = lu32.init(count * @sizeOf(nds.Range) + @sizeOf(format.FatChunk)),
        },
        .file_count = lu16.init(count),
        .reserved = lu16.init(0),
    });

    var i: u32 = 0;
    while (i < count) : (i += 1) {
        try stream.writeStructure(
            nds.Range.init(i * data.len, i * data.len + data.len),
        );
    }
    try stream.writeStructure(formats.Chunk{
        .name = formats.Chunk.names.fnt,
        .size = lu32.init(@sizeOf(format.Chunk)),
    });
    try stream.writeStructure(formats.Chunk{
        .name = formats.Chunk.names.file_data,
        .size = lu32.init(@sizeOf(format.Chunk) + data.len * count),
    });
    i = 0;
    while (i < count) : (i += 1) {
        try stream.writeAll(data);
    }
    return res.toOwnedSlice();
}

fn genGen4FakeRom(allocator: *mem.Allocator, info: gen4.offsets.Info) ![]u8 {
    // We use a checklist to assert at comptime that we generate info
    // for all fields in gen4.offsets.Info
    comptime var checklist = checklistFromT(gen4.offsets.Info);
    comptime checklist.set("version", true) catch unreachable;

    var header = ndsHeader();
    var rom = nds.Rom{
        .data = std.ArrayList(u8).init(allocator),
    };
    defer rom.deinit();

    const stream = rom.data.outStream();
    {
        comptime checklist.set("game_title", true) catch unreachable;
        comptime checklist.set("gamecode", true) catch unreachable;
        try stream.writeAll(&ndsHeader(info.game_title, info.gamecode));
    }
    {
        comptime checklist.set("hm_tm_prefix", true) catch unreachable;
        comptime checklist.set("starters", true) catch unreachable;
        const machine_len = (gen4.offsets.tm_count + gen4.offsets.hm_count) * @sizeOf(u16) +
            info.hm_tm_prefix.len;
        const arm9_size = switch (info.starters) {
            .arm9 => |offset| offset + gen4.offsets.starters_len + machine_len,
            .overlay9 => machine_len,
        };
        const header = @intToPtr(*Header, @ptrToInt(rom.header()));
        header.arm9.offset = lu32.init(@intCast(u32, rom.data.items.len));
        header.arm9.size = lu32.init(arm9_size);
        try stream.writeByteNTimes(0, arm9_size);

        const arm9 = rom.arm9();
        mem.copy(u8, arm9[arm9.len - machine_len ..], info.hm_tm_prefix);
    }

    {
        const header = @intToPtr(*Header, @ptrToInt(rom.header()));
        const offset = @intCast(u32, rom.data.items.len);
        header.arm7.offset = lu32.init(offset);
        header.arm7.size = lu32.init(0);
        header.arm7_overlay = nds.Slice.init(offset, 0);
        header.banner_offset = lu32.init(offset);

        try stream.writeAll(mem.asBytes(&nds_banner));
    }

    comptime checklist.set("scripts", true) catch unreachable;
    comptime checklist.set("pokemons", true) catch unreachable;
    comptime checklist.set("level_up_moves", true) catch unreachable;
    comptime checklist.set("moves", true) catch unreachable;
    comptime checklist.set("itemdata", true) catch unreachable;
    comptime checklist.set("trainers", true) catch unreachable;
    comptime checklist.set("parties", true) catch unreachable;
    comptime checklist.set("evolutions", true) catch unreachable;
    comptime checklist.set("wild_pokemons", true) catch unreachable;

    var fat = std.ArrayList(nds.Range).init(allocator);
    var fnt_main = std.ArrayList(fs.FntMainEntry).init(allocator);
    var fnt_sub = std.ArrayList(u8).init(allocator);
    var files = std.ArrayList(u8).init(allocator);

    try fnt_main.append(.{
        .offset_to_subtable = lu32.init(0),
        .first_file_id_in_subtable = lu16.init(0),
        .parent_id = lu16.init(0),
    });

    // TODO: Sort
    const files = [_][]const []const u8{
        info.scripts,
        info.pokemons,
        info.level_up_moves,
        info.moves,
        info.itemdata,
        info.trainers,
        info.evolutions,
        info.parties,
        info.wild_pokemons,
    };

    var entry: usize = 0;
    var depth: usize = 0;
    while (true) : (depth += 1) {
        for (files) |file| {
            var file_depth: usize = 0;

            if (file.path.len <= depth)
                continue;

            const is_file = file.path.len - 1 == depth;
        }

        try fnt.append(0);
    }

    fnt_main.items[0].parent_id = lu16.init(@intCast(u16, fnt_main.items.len));

    var trainer = zeroInit(gen4.Trainer);
    var evo = zeroInit(gen4.Evolution);
    trainer.party_size = 1;
    evo.method = .level_up;
    const files = [_][]const u8{
        .{ .path = info.scripts, .data = try createNarcData(allocator, "", 10) },
        .{ .path = info.pokemons, .data = try createNarc(allocator, zeroInit(gen4.BasePokemon), 10) },
        .{ .path = info.level_up_moves, .data = try createNarc(allocator, zeroInit(gen4.LevelUpMove), 10) },
        .{ .path = info.moves, .data = try createNarc(allocator, zeroInit(gen4.Move), 10) },
        .{ .path = info.itemdata, .data = try createNarc(allocator, zeroInit(gen4.Item), 10) },
        .{ .path = info.trainers, .data = try createNarc(allocator, trainer, 10) },
        .{ .path = info.evolutions, .data = try createNarc(allocator, evo, 10) },
        .{
            .path = info.parties,
            .data = switch (info.version) {
                .diamond, .pearl => try createNarc(allocator, zeroInit(gen4.PartyMemberNone), 10),
                .heart_gold, .soul_silver, .platinum => try createNarc(allocator, zeroInit(gen4.HgSsPlatMember(gen4.PartyMemberNone)), 10),
                else => unreachable,
            },
        },
        .{
            .path = info.wild_pokemons,
            .data = switch (info.version) {
                .diamond, .pearl, .platinum => try createNarc(allocator, zeroInit(gen4.DpptWildPokemons), 10),
                .heart_gold, .soul_silver => try createNarc(allocator, zeroInit(gen4.HgssWildPokemons), 10),
                else => unreachable,
            },
        },
    };

    // Assert that we have generated data for all fields
    comptime std.debug.assert(checklist.all(true));

    const nds_rom = rom.nds.Rom{
        .arm9_overlay_table = switch (info.starters) {
            .arm9 => &[_]rom.nds.Overlay{},
            .overlay9 => |overlay| blk: {
                const res = try allocator.alloc(rom.nds.Overlay, overlay.file + 1);
                mem.set(u8, mem.sliceAsBytes(res), 0);
                break :blk res;
            },
        },
        .arm9_overlay_files = switch (info.starters) {
            .arm9 => &[_][]u8{},
            .overlay9 => |overlay| blk: {
                const res = try allocator.alloc([]u8, overlay.file + 1);
                for (res) |*bytes|
                    bytes.* = "";

                res[overlay.file] = try allocator.alloc(u8, overlay.offset + gen4.offsets.starters_len);
                mem.set(u8, res[overlay.file], 0);
                break :blk res;
            },
        },
        .root = try rom.nds.fs.Nitro.create(allocator),
    };
    const root = nds_rom.root;

    const name = try fmt.allocPrint(allocator, "{}__{}_{}_{}__", .{ tmp_folder, mem.spanZ(&info.game_title), info.gamecode, @tagName(info.version) });
    errdefer allocator.free(name);

    var file = try fs.cwd().createFile(name, .{});
    errdefer fs.cwd().deleteFile(name) catch {};
    defer file.close();

    try nds_rom.writeToFile(file);

    return name;
}

fn genGen5FakeRom(allocator: *mem.Allocator, info: gen5.offsets.Info) ![]u8 {
    const machine_len = gen5.offsets.tm_count + gen5.offsets.hm_count;
    const machines = [_]lu16{comptime lu16.init(0)} ** machine_len;
    const arm9 = try fmt.allocPrint(allocator, "{}{}", .{ gen5.offsets.hm_tm_prefix, mem.sliceAsBytes(machines[0..]) });
    defer allocator.free(arm9);

    const nds_rom = rom.nds.Rom{
        .allocator = allocator,
        .header = ndsHeader(info.game_title, info.gamecode),
        .banner = ndsBanner,
        .arm9 = arm9,
        .arm7 = &[_]u8{},
        .nitro_footer = [_]lu32{comptime lu32.init(0)} ** 3,
        .arm9_overlay_table = &[_]rom.nds.Overlay{},
        .arm9_overlay_files = &[_][]u8{},
        .arm7_overlay_table = &[_]rom.nds.Overlay{},
        .arm7_overlay_files = &[_][]u8{},
        .root = try rom.nds.fs.Nitro.create(allocator),
    };
    const root = nds_rom.root;

    // We use a checklist to assert at comptime that we generate info
    // for all fields in gen5.offsets.Info
    comptime var checklist = checklistFromT(gen5.offsets.Info);
    comptime checklist.set("game_title", true) catch unreachable;
    comptime checklist.set("gamecode", true) catch unreachable;
    comptime checklist.set("version", true) catch unreachable;

    comptime checklist.set("starters", true) catch unreachable;
    comptime checklist.set("scripts", true) catch unreachable;
    {
        var files_to_create: usize = 0;
        var size_of_files: usize = 0;
        for (info.starters) |offs| {
            for (offs) |offset, j| {
                files_to_create = math.max(files_to_create, offset.file + 1);
                size_of_files = math.max(size_of_files, offset.offset + 2);
            }
        }
        const data = try allocator.alloc(u8, size_of_files);
        mem.set(u8, data, 0);
        try createNarcData(allocator, root, info.scripts, data, files_to_create, "");
    }

    comptime checklist.set("pokemons", true) catch unreachable;
    try createNarc(allocator, root, info.pokemons, zeroInit(gen5.BasePokemon), 10, "");

    comptime checklist.set("evolutions", true) catch unreachable;
    var evo = zeroInit(gen5.Evolution);
    evo.method = .level_up;
    try createNarc(allocator, root, info.evolutions, evo, 10, "");

    comptime checklist.set("level_up_moves", true) catch unreachable;
    try createNarc(allocator, root, info.level_up_moves, zeroInit(gen5.LevelUpMove), 10, "");

    comptime checklist.set("moves", true) catch unreachable;
    try createNarc(allocator, root, info.moves, zeroInit(gen5.Move), 10, "");

    comptime checklist.set("itemdata", true) catch unreachable;
    try createNarc(allocator, root, info.itemdata, zeroInit(gen5.Item), 10, "");

    comptime checklist.set("trainers", true) catch unreachable;
    var trainer = zeroInit(gen5.Trainer);
    trainer.party_size = 1;
    try createNarc(allocator, root, info.trainers, trainer, 10, "");

    comptime checklist.set("parties", true) catch unreachable;
    try createNarc(allocator, root, info.parties, zeroInit(gen5.PartyMemberNone), 10, "");

    comptime checklist.set("wild_pokemons", true) catch unreachable;
    try createNarc(allocator, root, info.wild_pokemons, zeroInit(gen5.WildPokemons), 10, "");

    // Assert that we have generated data for all fields
    comptime std.debug.assert(checklist.all(true));

    const name = try fmt.allocPrint(allocator, "{}__{}_{}_{}__", .{ tmp_folder, mem.spanZ(&info.game_title), info.gamecode, @tagName(info.version) });
    errdefer allocator.free(name);

    var file = try fs.cwd().createFile(name, .{});
    errdefer fs.cwd().deleteFile(name) catch {};
    defer file.close();

    try nds_rom.writeToFile(file);

    return name;
}

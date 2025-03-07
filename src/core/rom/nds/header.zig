pub const CrcModbus = std.hash.crc.Crc(u16, .{
    .polynomial = 0x8005,
    .initial = 0xFFFF,
    .xor_output = 0x0000,
    .reflect_input = true,
    .reflect_output = true,
});

test CrcModbus {
    std.debug.assert(CrcModbus.hash("123456789") == 0x4B37);
}

// http://problemkaputt.de/gbatek.htm#dscartridgeheader
pub const Header = extern struct {
    game_title: util.TerminatedArray(12, u8, 0),
    gamecode: [4]u8,
    makercode: [2]u8,

    unitcode: u8,
    encryption_seed_select: u8,
    device_capacity: u8,

    reserved1: [7]u8,
    reserved2: u8, // (except, used on DSi)

    nds_region: u8,
    rom_version: u8,
    autostart: u8,

    arm9: Arm,
    arm7: Arm,
    fnt: nds.Slice,
    fat: nds.Slice,
    arm9_overlay: nds.Slice,
    arm7_overlay: nds.Slice,

    // TODO: Rename when I know exactly what his means.
    port_40001a4h_setting_for_normal_commands: [4]u8,
    port_40001a4h_setting_for_key1_commands: [4]u8,

    banner_offset: u32,

    secure_area_checksum: u16,
    secure_area_delay: u16,

    arm9_auto_load_list_ram_address: u32,
    arm7_auto_load_list_ram_address: u32,

    secure_area_disable: u64,
    total_used_rom_size: u32,
    rom_header_size: u32,

    reserved3: [0x38]u8,

    nintendo_logo: [0x9C]u8,
    nintendo_logo_checksum: u16,

    header_checksum: u16,

    debug_rom_offset: u32,
    debug_size: u32,
    debug_ram_address: u32,

    reserved4: [4]u8,
    reserved5: [0x10]u8,

    // New DSi Header Entries
    wram_slots: [20]u8,
    arm9_wram_areas: [12]u8,
    arm7_wram_areas: [12]u8,
    wram_slot_master: [3]u8,

    // 1AFh 1    ... whatever, rather not 4000247h WRAMCNT ?
    //                (above byte is usually 03h)
    //                (but, it's FCh in System Menu?)
    //                (but, it's 00h in System Settings?)
    unknown: u8,

    region_flags: [4]u8,
    access_control: [4]u8,

    arm7_scfg_ext_setting: [4]u8,

    reserved6: [3]u8,

    // 1BFh 1    Flags? (usually 01h) (DSiware Browser: 0Bh)
    //         bit2: Custom Icon  (0=No/Normal, 1=Use banner.save)
    unknown_flags: u8,

    arm9i_rom_offset: u32,

    reserved7: [4]u8,

    arm9i_ram_load_address: u32,
    arm9i_size: u32,
    arm7i_rom_offset: u32,

    device_list_arm7_ram_addr: u32,

    arm7i_ram_load_address: u32,
    arm7i_size: u32,

    digest_ntr_region_offset: u32,
    digest_ntr_region_length: u32,
    digest_twl_region_offset: u32,
    digest_twl_region_length: u32,
    digest_sector_hashtable_offset: u32,
    digest_sector_hashtable_length: u32,
    digest_block_hashtable_offset: u32,
    digest_block_hashtable_length: u32,
    digest_sector_size: u32,
    digest_block_sectorcount: u32,

    banner_size: u32,

    reserved8: [4]u8,

    total_used_rom_size_including_dsi_area: u32,

    reserved9: [4]u8,
    reserved10: [4]u8,
    reserved11: [4]u8,

    modcrypt_area_1_offset: u32,
    modcrypt_area_1_size: u32,
    modcrypt_area_2_offset: u32,
    modcrypt_area_2_size: u32,

    title_id_emagcode: [4]u8,
    title_id_filetype: u8,

    // 235h 1    Title ID, Zero     (00h=Normal)
    // 236h 1    Title ID, Three    (03h=Normal, why?)
    // 237h 1    Title ID, Zero     (00h=Normal)
    title_id_rest: [3]u8,

    public_sav_filesize: u32,
    private_sav_filesize: u32,

    reserved12: [176]u8,

    // Parental Control Age Ratings
    cero_japan: u8,
    esrb_us_canada: u8,

    reserved13: u8,

    usk_germany: u8,
    pegi_pan_europe: u8,

    resereved14: u8,

    pegi_portugal: u8,
    pegi_and_bbfc_uk: u8,
    agcb_australia: u8,
    grb_south_korea: u8,

    reserved15: [6]u8,

    // SHA1-HMACS and RSA-SHA1
    arm9_hash_with_secure_area: [20]u8,
    arm7_hash: [20]u8,
    digest_master_hash: [20]u8,
    icon_title_hash: [20]u8,
    arm9i_hash: [20]u8,
    arm7i_hash: [20]u8,

    reserved16: [40]u8,

    arm9_hash_without_secure_area: [20]u8,

    reserved17: [2636]u8,
    reserved18: [0x180]u8,

    signature_across_header_entries: [0x80]u8,

    comptime {
        std.debug.assert(@sizeOf(Header) == 4096);
    }

    pub const Arm = extern struct {
        offset: u32,
        entry_address: u32,
        ram_address: u32,
        size: u32,
    };

    pub fn isDsi(header: Header) bool {
        return (header.unitcode & 0x02) != 0;
    }

    pub fn calcChecksum(header: Header) u16 {
        return CrcModbus.hash(std.mem.toBytes(header)[0..0x15E]);
    }

    pub fn validate(header: Header) !void {
        if (header.header_checksum != header.calcChecksum())
            return error.InvalidHeaderChecksum;

        for (header.game_title.slice()) |item| {
            if (std.ascii.isLower(item))
                return error.InvalidGameTitle;
        }
        for (header.gamecode) |item| {
            if (!std.ascii.isUpper(item))
                return error.InvalidGamecode;
        }

        // TODO: Docs says that makercode is uber ascii, but for Pokemon games, it is
        //       ascii numbers.
        //const makercode = std.ascii.asAsciiConst(header.makercode) catch return error.InvalidMakercode;
        //if (!it.all(makercode, std.ascii.isUpper))
        //    return error.InvalidMakercode;

        if (header.unitcode > 0x03)
            return error.InvalidUnitcode;
        if (header.encryption_seed_select > 0x07)
            return error.InvalidEncryptionSeedSelect;

        //if (!it.all(header.reserved1[0..], isZero))
        //    return error.InvalidReserved1;

        // It seems that arm9 (secure area) is always at 0x4000
        // http://problemkaputt.de/gbatek.htm#dscartridgesecurearea
        if (header.arm9.offset != 0x4000)
            return error.InvalidArm9RomOffset;
        if (header.arm9.entry_address < 0x2000000 or 0x23BFE00 < header.arm9.entry_address)
            return error.InvalidArm9EntryAddress;
        if (header.arm9.ram_address < 0x2000000 or 0x23BFE00 < header.arm9.ram_address)
            return error.InvalidArm9RamAddress;
        if (header.arm9.size > 0x3BFE00)
            return error.InvalidArm9Size;

        if (header.arm7.offset < 0x8000)
            return error.InvalidArm7RomOffset;
        if ((header.arm7.entry_address < 0x2000000 or 0x23BFE00 < header.arm7.entry_address) and
            (header.arm7.entry_address < 0x37F8000 or 0x3807E00 < header.arm7.entry_address))
            return error.InvalidArm7EntryAddress;
        if ((header.arm7.ram_address < 0x2000000 or 0x23BFE00 < header.arm7.ram_address) and
            (header.arm7.ram_address < 0x37F8000 or 0x3807E00 < header.arm7.ram_address))
            return error.InvalidArm7RamAddress;
        if (header.arm7.size > 0x3BFE00)
            return error.InvalidArm7Size;

        if (header.arm9_overlay.start % @alignOf(nds.Overlay) != 0)
            return error.InvalidArm9OverlayOffset;
        if (header.arm7_overlay.start % @alignOf(nds.Overlay) != 0)
            return error.InvalidArm7OverlayOffset;

        if (header.banner_offset != 0 and header.banner_offset < 0x8000)
            return error.InvalidIconTitleOffset;
        if (header.banner_offset % @alignOf(nds.Banner) != 0)
            return error.InvalidIconTitleOffset;

        if (header.secure_area_delay != 0x051E and header.secure_area_delay != 0x0D7E)
            return error.InvalidSecureAreaDelay;

        if (header.rom_header_size != 0x4000)
            return error.InvalidRomHeaderSize;

        //if (!it.all(header.reserved3, isZero))
        //    return error.InvalidReserved3;
        //if (!it.all(header.reserved4, isZero))
        //    return error.InvalidReserved4;
        //if (!it.all(header.reserved5, isZero))
        //    return error.InvalidReserved5;

        if (header.isDsi()) {
            //if (!it.all(header.reserved6[0..], isZero))
            //    return error.InvalidReserved6;
            //if (!it.all(header.reserved7[0..], isZero))
            //    return error.InvalidReserved7;

            // TODO: (usually same as ARM9 rom offs, 0004000h)
            //       Does that mean that it also always 0x4000?
            if (header.digest_ntr_region_offset != 0x4000)
                return error.InvalidDigestNtrRegionOffset;
            //if (!std.mem.eql(u8, header.reserved8, [_]u8{ 0x00, 0x00, 0x01, 0x00 }))
            //    return error.InvalidReserved8;
            //if (!it.all(header.reserved9, isZero))
            //    return error.InvalidReserved9;
            if (!std.mem.eql(u8, &header.title_id_rest, "\x00\x03\x00"))
                return error.InvalidTitleIdRest;
            //if (!it.all(header.reserved12, isZero))
            //    return error.InvalidReserved12;
            //if (!it.all(header.reserved16, isZero))
            //    return error.InvalidReserved16;
            //if (!it.all(header.reserved17, isZero))
            //    return error.InvalidReserved17;
            //if (!it.all(header.reserved18, isZero))
            //    return error.InvalidReserved18;
        }
    }

    fn isZero(b: u8) bool {
        return b == 0;
    }
};

test {
    _ = nds;
    _ = util;
}

const nds = @import("../nds.zig");
const std = @import("std");
const util = @import("../../../util.zig");

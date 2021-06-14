const crc = @import("crc");
const it = @import("ziter");
const std = @import("std");
const util = @import("util");

const int = @import("../int.zig");
const nds = @import("../nds.zig");

const ascii = std.ascii;
const debug = std.debug;
const io = std.io;
const mem = std.mem;

const lu16 = int.lu16;
const lu32 = int.lu32;
const lu64 = int.lu64;

pub const crc_modbus = blk: {
    @setEvalBranchQuota(crc.crcspec_init_backward_cycles);
    break :blk crc.CrcSpec(u16).init(0x8005, 0xFFFF, 0x0000, true, true);
};

test "nds.crc_modbus" {
    debug.assert(crc_modbus.checksum("123456789") == 0x4B37);
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

    banner_offset: lu32,

    secure_area_checksum: lu16,
    secure_area_delay: lu16,

    arm9_auto_load_list_ram_address: lu32,
    arm7_auto_load_list_ram_address: lu32,

    secure_area_disable: lu64,
    total_used_rom_size: lu32,
    rom_header_size: lu32,

    reserved3: [0x38]u8,

    nintendo_logo: [0x9C]u8,
    nintendo_logo_checksum: lu16,

    header_checksum: lu16,

    debug_rom_offset: lu32,
    debug_size: lu32,
    debug_ram_address: lu32,

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
    //         bit2: Custom Icon  (0=No/Normal, 1=Use banner.sav)
    unknown_flags: u8,

    arm9i_rom_offset: lu32,

    reserved7: [4]u8,

    arm9i_ram_load_address: lu32,
    arm9i_size: lu32,
    arm7i_rom_offset: lu32,

    device_list_arm7_ram_addr: lu32,

    arm7i_ram_load_address: lu32,
    arm7i_size: lu32,

    digest_ntr_region_offset: lu32,
    digest_ntr_region_length: lu32,
    digest_twl_region_offset: lu32,
    digest_twl_region_length: lu32,
    digest_sector_hashtable_offset: lu32,
    digest_sector_hashtable_length: lu32,
    digest_block_hashtable_offset: lu32,
    digest_block_hashtable_length: lu32,
    digest_sector_size: lu32,
    digest_block_sectorcount: lu32,

    banner_size: lu32,

    reserved8: [4]u8,

    total_used_rom_size_including_dsi_area: lu32,

    reserved9: [4]u8,
    reserved10: [4]u8,
    reserved11: [4]u8,

    modcrypt_area_1_offset: lu32,
    modcrypt_area_1_size: lu32,
    modcrypt_area_2_offset: lu32,
    modcrypt_area_2_size: lu32,

    title_id_emagcode: [4]u8,
    title_id_filetype: u8,

    // 235h 1    Title ID, Zero     (00h=Normal)
    // 236h 1    Title ID, Three    (03h=Normal, why?)
    // 237h 1    Title ID, Zero     (00h=Normal)
    title_id_rest: [3]u8,

    public_sav_filesize: lu32,
    private_sav_filesize: lu32,

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
        debug.assert(@sizeOf(Header) == 4096);
    }

    pub const Arm = extern struct {
        offset: lu32,
        entry_address: lu32,
        ram_address: lu32,
        size: lu32,
    };

    pub fn isDsi(header: Header) bool {
        return (header.unitcode & 0x02) != 0;
    }

    pub fn calcChecksum(header: Header) u16 {
        return crc_modbus.checksum(mem.toBytes(header)[0..0x15E]);
    }

    pub fn validate(header: Header) !void {
        if (header.header_checksum.value() != header.calcChecksum())
            return error.InvalidHeaderChecksum;

        if (!it.all(header.game_title.span(), notLower))
            return error.InvalidGameTitle;
        if (!it.all(&header.gamecode, ascii.isUpper))
            return error.InvalidGamecode;

        // TODO: Docs says that makercode is uber ascii, but for Pokemon games, it is
        //       ascii numbers.
        //const makercode = ascii.asAsciiConst(header.makercode) catch return error.InvalidMakercode;
        //if (!it.all(makercode, ascii.isUpper))
        //    return error.InvalidMakercode;

        if (header.unitcode > 0x03)
            return error.InvalidUnitcode;
        if (header.encryption_seed_select > 0x07)
            return error.InvalidEncryptionSeedSelect;

        //if (!it.all(header.reserved1[0..], isZero))
        //    return error.InvalidReserved1;

        // It seems that arm9 (secure area) is always at 0x4000
        // http://problemkaputt.de/gbatek.htm#dscartridgesecurearea
        if (header.arm9.offset.value() != 0x4000)
            return error.InvalidArm9RomOffset;
        if (header.arm9.entry_address.value() < 0x2000000 or 0x23BFE00 < header.arm9.entry_address.value())
            return error.InvalidArm9EntryAddress;
        if (header.arm9.ram_address.value() < 0x2000000 or 0x23BFE00 < header.arm9.ram_address.value())
            return error.InvalidArm9RamAddress;
        if (header.arm9.size.value() > 0x3BFE00)
            return error.InvalidArm9Size;

        if (header.arm7.offset.value() < 0x8000)
            return error.InvalidArm7RomOffset;
        if ((header.arm7.entry_address.value() < 0x2000000 or 0x23BFE00 < header.arm7.entry_address.value()) and
            (header.arm7.entry_address.value() < 0x37F8000 or 0x3807E00 < header.arm7.entry_address.value()))
            return error.InvalidArm7EntryAddress;
        if ((header.arm7.ram_address.value() < 0x2000000 or 0x23BFE00 < header.arm7.ram_address.value()) and
            (header.arm7.ram_address.value() < 0x37F8000 or 0x3807E00 < header.arm7.ram_address.value()))
            return error.InvalidArm7RamAddress;
        if (header.arm7.size.value() > 0x3BFE00)
            return error.InvalidArm7Size;

        if (header.banner_offset.value() != 0 and header.banner_offset.value() < 0x8000)
            return error.InvalidIconTitleOffset;

        if (header.secure_area_delay.value() != 0x051E and header.secure_area_delay.value() != 0x0D7E)
            return error.InvalidSecureAreaDelay;

        if (header.rom_header_size.value() != 0x4000)
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
            if (header.digest_ntr_region_offset.value() != 0x4000)
                return error.InvalidDigestNtrRegionOffset;
            //if (!mem.eql(u8, header.reserved8, [_]u8{ 0x00, 0x00, 0x01, 0x00 }))
            //    return error.InvalidReserved8;
            //if (!it.all(header.reserved9, isZero))
            //    return error.InvalidReserved9;
            if (!mem.eql(u8, &header.title_id_rest, "\x00\x03\x00"))
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

    fn notLower(char: u8) bool {
        return !ascii.isLower(char);
    }
};

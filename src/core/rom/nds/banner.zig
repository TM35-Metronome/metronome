const util = @import("util");
const int = @import("../int.zig");

const algorithm = util.algorithm;
const lu16 = int.lu16;

pub const Banner = extern struct {
    version: u8,
    has_animated_dsi_icon: u8,

    crc16_across_0020h_083fh: lu16,
    crc16_across_0020h_093fh: lu16,
    crc16_across_0020h_0a3fh: lu16,
    crc16_across_1240h_23bfh: lu16,

    reserved1: [0x16]u8,

    icon_bitmap: [0x200]u8,
    icon_palette: [0x20]u8,

    title_japanese: [0x100]u8,
    title_english: [0x100]u8,
    title_french: [0x100]u8,
    title_german: [0x100]u8,
    title_italian: [0x100]u8,
    title_spanish: [0x100]u8,
    //title_chinese:  [0x100]u8,
    //title_korean:   [0x100]u8,

    // TODO: Banner is actually a variable size structure.
    //       "original Icon/Title structure rounded to 200h-byte sector boundary (ie. A00h bytes for Version 1 or 2),"
    //       "however, later DSi carts are having a size entry at CartHdr[208h] (usually 23C0h)."
    //reserved2: [0x800]u8,

    //// animated DSi icons only
    //icon_animation_bitmap: [0x1000]u8,
    //icon_animation_palette: [0x100]u8,
    //icon_animation_sequence: [0x80]u8, // Should be [0x40]lu16?

    pub fn validate(banner: Banner) !void {
        if (banner.version == 0)
            return error.InvalidVersion;

        if (!algorithm.all(u8, banner.reserved1, isZero))
            return error.InvalidReserved1;

        //if (!utils.algorithm.all(u8, banner.reserved2, ascii.isZero))
        //    return error.InvalidReserved2;

        //if (!banner.has_animated_dsi_icon) {
        //    if (!utils.algorithm.all(u8, banner.icon_animation_bitmap, is0xFF))
        //        return error.InvalidIconAnimationBitmap;
        //    if (!utils.algorithm.all(u8, banner.icon_animation_palette, is0xFF))
        //        return error.InvalidIconAnimationPalette;
        //    if (!utils.algorithm.all(u8, banner.icon_animation_sequence, is0xFF))
        //        return error.InvalidIconAnimationSequence;
        //}
    }

    fn isZero(b: u8) bool {
        return b == 0;
    }

    fn is0xFF(char: u8) bool {
        return char == 0xFF;
    }
};

const std = @import("std");
const util = @import("util");

const ascii = std.ascii;
const debug = std.debug;
const io = std.io;
const mem = std.mem;

pub const Header = extern struct {
    rom_entry_point: [4]u8,
    nintendo_logo: [156]u8,
    game_title: util.TerminatedArray(12, u8, 0),
    gamecode: [4]u8,
    makercode: [2]u8,

    fixed_value: u8,
    main_unit_code: u8,
    device_type: u8,

    reserved1: [7]u8,

    software_version: u8,
    complement_check: u8,

    reserved2: [2]u8,

    comptime {
        std.debug.assert(@sizeOf(Header) == 192);
    }

    pub fn validate(header: *const Header) !void {
        for (header.game_title.span()) |item| {
            if (ascii.isLower(item))
                return error.InvalidGameTitle;
        }
        for (header.gamecode) |item| {
            if (!ascii.isUpper(item))
                return error.InvalidGamecode;
        }

        // TODO: Docs says that makercode is uber ascii, but for Pokemon games, it is
        //       ascii numbers.
        // const makercode = ascii.asAsciiConst(header.makercode) catch return error.InvalidMakercode;
        // if (!it.all(makercode, ascii.isUpper))
        //     return error.InvalidMakercode;
        if (header.fixed_value != 0x96)
            return error.InvalidFixedValue;

        for (header.reserved1) |item| {
            if (item != 0)
                return error.InvalidReserved1;
        }
        for (header.reserved2) |item| {
            if (item != 0)
                return error.InvalidReserved1;
        }
    }
};

const fun = @import("../lib/fun-with-zig/src/index.zig"); // TODO: package fix
const std = @import("std");

const ascii = fun.ascii;
const debug = std.debug;
const generic = fun.generic;
const io = std.io;
const mem = std.mem;
const slice = generic.slice;

const assert = debug.assert;

pub const Header = packed struct {
    rom_entry_point: [4]u8,
    nintendo_logo: [156]u8,
    game_title: [12]u8,
    gamecode: [4]u8,
    makercode: [2]u8,

    fixed_value: u8,
    main_unit_code: u8,
    device_type: u8,

    reserved1: [7]u8,

    software_version: u8,
    complement_check: u8,

    reserved2: [2]u8,

    pub fn validate(header: *const Header) !void {
        const game_title = ascii.asAsciiConst(header.game_title) catch return error.InvalidGameTitle;
        if (!slice.all(game_title, notLower))
            return error.InvalidGameTitle;

        const gamecode = ascii.asAsciiConst(header.gamecode) catch return error.InvalidGamecode;
        if (!slice.all(gamecode, ascii.isUpper))
            return error.InvalidGamecode;

        // TODO: Docs says that makercode is uber ascii, but for Pokemon games, it is
        //       ascii numbers.
        // const makercode = ascii.asAsciiConst(header.makercode) catch return error.InvalidMakercode;
        // if (!slice.all(makercode, ascii.isUpper))
        //     return error.InvalidMakercode;
        if (header.fixed_value != 0x96)
            return error.InvalidFixedValue;

        if (!slice.all(header.reserved1[0..], isZero))
            return error.InvalidReserved1;
        if (!slice.all(header.reserved2[0..], isZero))
            return error.InvalidReserved2;
    }

    fn isZero(b: u8) bool {
        return b == 0;
    }

    fn notLower(char: u7) bool {
        return !ascii.isLower(char);
    }
};

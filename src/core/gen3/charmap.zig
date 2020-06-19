const std = @import("std");

const debug = std.debug;
const io = std.io;
const mem = std.mem;
const testing = std.testing;

pub const CharMap = []const Char;
pub const Char = [2][]const u8;
pub const char_map = [_]Char{
    Char{ " ", "\x00" },
    Char{ "À", "\x01" },
    Char{ "Á", "\x02" },
    Char{ "Â", "\x03" },
    Char{ "Ç", "\x04" },
    Char{ "È", "\x05" },
    Char{ "É", "\x06" },
    Char{ "Ê", "\x07" },
    Char{ "Ë", "\x08" },
    Char{ "Ì", "\x09" },
    Char{ "Î", "\x0B" },
    Char{ "Ï", "\x0C" },
    Char{ "Ò", "\x0D" },
    Char{ "Ó", "\x0E" },
    Char{ "Ô", "\x0F" },
    Char{ "Œ", "\x10" },
    Char{ "Ù", "\x11" },
    Char{ "Ú", "\x12" },
    Char{ "Û", "\x13" },
    Char{ "Ñ", "\x14" },
    Char{ "ß", "\x15" },
    Char{ "à", "\x16" },
    Char{ "á", "\x17" },
    Char{ "ç", "\x19" },
    Char{ "è", "\x1A" },
    Char{ "é", "\x1B" },
    Char{ "ê", "\x1C" },
    Char{ "ë", "\x1D" },
    Char{ "ì", "\x1E" },
    Char{ "î", "\x20" },
    Char{ "ï", "\x21" },
    Char{ "ò", "\x22" },
    Char{ "ó", "\x23" },
    Char{ "ô", "\x24" },
    Char{ "œ", "\x25" },
    Char{ "ù", "\x26" },
    Char{ "ú", "\x27" },
    Char{ "û", "\x28" },
    Char{ "ñ", "\x29" },
    Char{ "º", "\x2A" },
    Char{ "ª", "\x2B" },
    Char{ "{SUPER_ER}", "\x2C" },
    Char{ "&", "\x2D" },
    Char{ "+", "\x2E" },
    Char{ "{LV}", "\x34" },
    Char{ "=", "\x35" },
    Char{ ";", "\x36" },
    Char{ "¿", "\x51" },
    Char{ "¡", "\x52" },
    Char{ "{PK}", "\x53" },
    Char{ "{PKMN}", "\x53\x54" },
    Char{ "{POKEBLOCK}", "\x55\x56\x57\x58\x59" },
    Char{ "Í", "\x5A" },
    Char{ "%", "\x5B" },
    Char{ "(", "\x5C" },
    Char{ ")", "\x5D" },
    Char{ "â", "\x68" },
    Char{ "í", "\x6F" },
    Char{ "{UNK_SPACER}", "\x77" },
    Char{ "{UP_ARROW}", "\x79" },
    Char{ "{DOWN_ARROW}", "\x7A" },
    Char{ "{LEFT_ARROW}", "\x7B" },
    Char{ "{RIGHT_ARROW}", "\x7C" },
    Char{ "{SUPER_E}", "\x84" },
    Char{ "<", "\x85" },
    Char{ ">", "\x86" },
    Char{ "{SUPER_RE}", "\xA0" },
    Char{ "0", "\xA1" },
    Char{ "1", "\xA2" },
    Char{ "2", "\xA3" },
    Char{ "3", "\xA4" },
    Char{ "4", "\xA5" },
    Char{ "5", "\xA6" },
    Char{ "6", "\xA7" },
    Char{ "7", "\xA8" },
    Char{ "8", "\xA9" },
    Char{ "9", "\xAA" },
    Char{ "!", "\xAB" },
    Char{ "?", "\xAC" },
    Char{ ".", "\xAD" },
    Char{ "-", "\xAE" },
    Char{ "·", "\xAF" },
    Char{ "…", "\xB0" },
    Char{ "“", "\xB1" },
    Char{ "”", "\xB2" },
    Char{ "‘", "\xB3" },
    Char{ "'", "\xB4" },
    Char{ "♂", "\xB5" },
    Char{ "♀", "\xB6" },
    Char{ "¥", "\xB7" },
    Char{ ",", "\xB8" },
    Char{ "×", "\xB9" },
    Char{ "/", "\xBA" },
    Char{ "A", "\xBB" },
    Char{ "B", "\xBC" },
    Char{ "C", "\xBD" },
    Char{ "D", "\xBE" },
    Char{ "E", "\xBF" },
    Char{ "F", "\xC0" },
    Char{ "G", "\xC1" },
    Char{ "H", "\xC2" },
    Char{ "I", "\xC3" },
    Char{ "J", "\xC4" },
    Char{ "K", "\xC5" },
    Char{ "L", "\xC6" },
    Char{ "M", "\xC7" },
    Char{ "N", "\xC8" },
    Char{ "O", "\xC9" },
    Char{ "P", "\xCA" },
    Char{ "Q", "\xCB" },
    Char{ "R", "\xCC" },
    Char{ "S", "\xCD" },
    Char{ "T", "\xCE" },
    Char{ "U", "\xCF" },
    Char{ "V", "\xD0" },
    Char{ "W", "\xD1" },
    Char{ "X", "\xD2" },
    Char{ "Y", "\xD3" },
    Char{ "Z", "\xD4" },
    Char{ "a", "\xD5" },
    Char{ "b", "\xD6" },
    Char{ "c", "\xD7" },
    Char{ "d", "\xD8" },
    Char{ "e", "\xD9" },
    Char{ "f", "\xDA" },
    Char{ "g", "\xDB" },
    Char{ "h", "\xDC" },
    Char{ "i", "\xDD" },
    Char{ "j", "\xDE" },
    Char{ "k", "\xDF" },
    Char{ "l", "\xE0" },
    Char{ "m", "\xE1" },
    Char{ "n", "\xE2" },
    Char{ "o", "\xE3" },
    Char{ "p", "\xE4" },
    Char{ "q", "\xE5" },
    Char{ "r", "\xE6" },
    Char{ "s", "\xE7" },
    Char{ "t", "\xE8" },
    Char{ "u", "\xE9" },
    Char{ "v", "\xEA" },
    Char{ "w", "\xEB" },
    Char{ "x", "\xEC" },
    Char{ "y", "\xED" },
    Char{ "z", "\xEE" },
    Char{ "▶", "\xEF" },
    Char{ ":", "\xF0" },
    Char{ "Ä", "\xF1" },
    Char{ "Ö", "\xF2" },
    Char{ "Ü", "\xF3" },
    Char{ "ä", "\xF4" },
    Char{ "ö", "\xF5" },
    Char{ "ü", "\xF6" },
    Char{ "{TALL_PLUS}", "\xFC\x0C\xFB" },
    Char{ "$", "\xFF" },
};

pub fn decode(in_stream: var, out_stream: var) !void {
    try helper(.Decode, in_stream, out_stream);
}

pub fn encode(in_stream: var, out_stream: var) !void {
    try helper(.Encode, in_stream, out_stream);
}

fn helper(op: enum {
    Encode,
    Decode,
}, in_stream: var, out_stream: var) !void {
    const in = if (op == .Encode) usize(0) else 1;
    const out = if (op == .Encode) usize(1) else 0;
    var buf: [64]u8 = undefined;
    var len: usize = 0;

    while (true) {
        len += try in_stream.readFull(buf[len..]);
        const chars = buf[0..len];
        if (chars.len == 0)
            break;

        var best_match: ?Char = null;
        for (char_map) |char| {
            debug.assert(char[in].len <= buf.len);
            if (!mem.startsWith(u8, chars, char[in]))
                continue;
            best_match = if (best_match) |best| blk: {
                debug.assert(best[in].len != char[in].len);
                break :blk if (best[in].len < char[in].len) char else best;
            } else char;
        }

        const best = best_match orelse return error.DecodeError;
        try out_stream.write(best[out]);
        mem.copy(u8, chars, chars[best[in].len..]);
        len -= best[in].len;
    }
}

fn testHelpder(comptime func: var, in: []const u8, out: []const u8) !void {
    var res: [1024]u8 = undefined;
    var sis = io.SliceInStream.init(in);
    var sos = io.SliceOutStream.init(&res);
    try func(&sis.stream, &sos.stream);
    testing.expectEqualSlices(u8, out, sos.getWritten());
}

fn _test(decoded: []const u8, encoded: []const u8) !void {
    try testHelpder(decode, encoded, decoded);
    try testHelpder(encode, decoded, encoded);
}

test "encode/decode" {
    try _test("HELLO WORLD", "\xC2\xBF\xC6\xC6\xC9\x00\xD1\xC9\xCC\xC6\xBE");
    try _test("{PK}{PKMN}", "\x53\x53\x54");
}

//@ Hiragana
//'あ' = 01
//'い' = 02
//'う' = 03
//'え' = 04
//'お' = 05
//'か' = 06
//'き' = 07
//'く' = 08
//'け' = 09
//'こ' = 0A
//'さ' = 0B
//'し' = 0C
//'す' = 0D
//'せ' = 0E
//'そ' = 0F
//'た' = 10
//'ち' = 11
//'つ' = 12
//'て' = 13
//'と' = 14
//'な' = 15
//'に' = 16
//'ぬ' = 17
//'ね' = 18
//'の' = 19
//'は' = 1A
//'ひ' = 1B
//'ふ' = 1C
//'へ' = 1D
//'ほ' = 1E
//'ま' = 1F
//'み' = 20
//'む' = 21
//'め' = 22
//'も' = 23
//'や' = 24
//'ゆ' = 25
//'よ' = 26
//'ら' = 27
//'り' = 28
//'る' = 29
//'れ' = 2A
//'ろ' = 2B
//'わ' = 2C
//'を' = 2D
//'ん' = 2E
//'ぁ' = 2F
//'ぃ' = 30
//'ぅ' = 31
//'ぇ' = 32
//'ぉ' = 33
//'ゃ' = 34
//'ゅ' = 35
//'ょ' = 36
//'が' = 37
//'ぎ' = 38
//'ぐ' = 39
//'げ' = 3A
//'ご' = 3B
//'ざ' = 3C
//'じ' = 3D
//'ず' = 3E
//'ぜ' = 3F
//'ぞ' = 40
//'だ' = 41
//'ぢ' = 42
//'づ' = 43
//'で' = 44
//'ど' = 45
//'ば' = 46
//'び' = 47
//'ぶ' = 48
//'べ' = 49
//'ぼ' = 4A
//'ぱ' = 4B
//'ぴ' = 4C
//'ぷ' = 4D
//'ぺ' = 4E
//'ぽ' = 4F
//'っ' = 50
//
//@ Katakana
//'ア' = 51
//'イ' = 52
//'ウ' = 53
//'エ' = 54
//'オ' = 55
//'カ' = 56
//'キ' = 57
//'ク' = 58
//'ケ' = 59
//'コ' = 5A
//'サ' = 5B
//'シ' = 5C
//'ス' = 5D
//'セ' = 5E
//'ソ' = 5F
//'タ' = 60
//'チ' = 61
//'ツ' = 62
//'テ' = 63
//'ト' = 64
//'ナ' = 65
//'ニ' = 66
//'ヌ' = 67
//'ネ' = 68
//'ノ' = 69
//'ハ' = 6A
//'ヒ' = 6B
//'フ' = 6C
//'ヘ' = 6D
//'ホ' = 6E
//'マ' = 6F
//'ミ' = 70
//'ム' = 71
//'メ' = 72
//'モ' = 73
//'ヤ' = 74
//'ユ' = 75
//'ヨ' = 76
//'ラ' = 77
//'リ' = 78
//'ル' = 79
//'レ' = 7A
//'ロ' = 7B
//'ワ' = 7C
//'ヲ' = 7D
//'ン' = 7E
//'ァ' = 7F
//'ィ' = 80
//'ゥ' = 81
//'ェ' = 82
//'ォ' = 83
//'ャ' = 84
//'ュ' = 85
//'ョ' = 86
//'ガ' = 87
//'ギ' = 88
//'グ' = 89
//'ゲ' = 8A
//'ゴ' = 8B
//'ザ' = 8C
//'ジ' = 8D
//'ズ' = 8E
//'ゼ' = 8F
//'ゾ' = 90
//'ダ' = 91
//'ヂ' = 92
//'ヅ' = 93
//'デ' = 94
//'ド' = 95
//'バ' = 96
//'ビ' = 97
//'ブ' = 98
//'ベ' = 99
//'ボ' = 9A
//'パ' = 9B
//'ピ' = 9C
//'プ' = 9D
//'ペ' = 9E
//'ポ' = 9F
//'ッ' = A0
//
//@ Japanese punctuation
//'　' = 00
//'！' = AB
//'？' = AC
//'。' = AD
//'ー' = AE
//'⋯' = B0
//
//STRING = FD
//
//@ string placeholders
//PLAYER         = FD 01
//STR_VAR_1      = FD 02
//STR_VAR_2      = FD 03
//STR_VAR_3      = FD 04
//KUN            = FD 05
//RIVAL          = FD 06
//@ version-dependent strings (originally made for Ruby/Sapphire differences)
//@ Emerald uses the Sapphire strings (except for VERSION).
//VERSION        = FD 07 @ "EMERALD"
//AQUA           = FD 08
//MAGMA          = FD 09
//ARCHIE         = FD 0A
//MAXIE          = FD 0B
//KYOGRE         = FD 0C
//GROUDON        = FD 0D
//
//@ battle string placeholders
//
//B_BUFF1 = FD 00
//B_BUFF2 = FD 01
//B_COPY_VAR_1 = FD 02
//B_COPY_VAR_2 = FD 03
//B_COPY_VAR_3 = FD 04
//B_PLAYER_MON1_NAME = FD 05
//B_OPPONENT_MON1_NAME = FD 06
//B_PLAYER_MON2_NAME = FD 07
//B_OPPONENT_MON2_NAME = FD 08
//B_LINK_PLAYER_MON1_NAME = FD 09
//B_LINK_OPPONENT_MON1_NAME = FD 0A
//B_LINK_PLAYER_MON2_NAME = FD 0B
//B_LINK_OPPONENT_MON2_NAME = FD 0C
//B_ATK_NAME_WITH_PREFIX_MON1 = FD 0D
//B_ATK_PARTNER_NAME = FD 0E
//B_ATK_NAME_WITH_PREFIX = FD 0F
//B_DEF_NAME_WITH_PREFIX = FD 10
//B_EFF_NAME_WITH_PREFIX = FD 11 @ EFF = short for gEffectBattler
//B_ACTIVE_NAME_WITH_PREFIX = FD 12
//B_SCR_ACTIVE_NAME_WITH_PREFIX = FD 13
//B_CURRENT_MOVE = FD 14
//B_LAST_MOVE = FD 15
//B_LAST_ITEM = FD 16
//B_LAST_ABILITY = FD 17
//B_ATK_ABILITY = FD 18
//B_DEF_ABILITY = FD 19
//B_SCR_ACTIVE_ABILITY = FD 1A
//B_EFF_ABILITY = FD 1B
//B_TRAINER1_CLASS = FD 1C
//B_TRAINER1_NAME = FD 1D
//B_LINK_PLAYER_NAME = FD 1E
//B_LINK_PARTNER_NAME = FD 1F
//B_LINK_OPPONENT1_NAME = FD 20
//B_LINK_OPPONENT2_NAME = FD 21
//B_LINK_SCR_TRAINER_NAME = FD 22
//B_PLAYER_NAME = FD 23
//B_TRAINER1_LOSE_TEXT = FD 24
//B_TRAINER1_WIN_TEXT = FD 25
//B_26 = FD 26
//B_PC_CREATOR_NAME = FD 27
//B_ATK_PREFIX1 = FD 28
//B_DEF_PREFIX1 = FD 29
//B_ATK_PREFIX2 = FD 2A
//B_DEF_PREFIX2 = FD 2B
//B_ATK_PREFIX3 = FD 2C
//B_DEF_PREFIX3 = FD 2D
//B_TRAINER2_CLASS = FD 2E
//B_TRAINER2_NAME = FD 2F
//B_TRAINER2_LOSE_TEXT = FD 30
//B_TRAINER2_WIN_TEXT = FD 31
//B_PARTNER_CLASS = FD 32
//B_PARTNER_NAME = FD 33
//B_BUFF3 = FD 34
//
//@ indicates the end of a town/city name (before " TOWN" or " CITY")
//NAME_END = FC 00
//
//@ special 0xF7 character
//SPECIAL_F7  =   F7
//
//@ more text functions
//
//COLOR = FC 01 @ use a color listed below right after
//HIGHLIGHT = FC 02 @ same as fc 01
//SHADOW = FC 03 @ same as fc 01
//COLOR_HIGHLIGHT_SHADOW = FC 04 @ takes 3 bytes
//PALETTE = FC 05 @ used in credits
//SIZE = FC 06 @ note that anything other than "SMALL" is invalid
//UNKNOWN_7 = FC 07
//PAUSE = FC 08 @ manually print the wait byte after this, havent mapped them
//PAUSE_UNTIL_PRESS = FC 09
//UNKNOWN_A = FC 0A
//PLAY_BGM = FC 0B
//ESCAPE = FC 0C
//SHIFT_TEXT = FC 0D
//UNKNOWN_E = FC 0E
//UNKNOWN_F = FC 0F
//PLAY_SE = FC 10
//CLEAR = FC 11
//SKIP = FC 12
//CLEAR_TO = FC 13
//MIN_LETTER_SPACING = FC 14
//JPN = FC 15
//ENG = FC 16
//PAUSE_MUSIC = FC 17
//RESUME_MUSIC = FC 18
//
//@ colors
//
//TRANSPARENT = 00
//WHITE = 01
//DARK_GREY = 02
//LIGHT_GREY = 03
//RED = 04
//LIGHT_RED = 05
//GREEN = 06
//LIGHT_GREEN = 07
//BLUE = 08
//LIGHT_BLUE = 09
//@ these next colors can be set to anything arbitrary at runtime
//@ usually though they'll have the textbox border colors as described below
//DYNAMIC_COLOR1 = 0A @ white
//DYNAMIC_COLOR2 = 0B @ white with a tinge of green
//DYNAMIC_COLOR3 = 0C @ white 2
//DYNAMIC_COLOR4 = 0D @ aquamarine
//DYNAMIC_COLOR5 = 0E @ blue-green
//DYNAMIC_COLOR6 = 0F @ cerulean
//
//@ sound and music
//
//MUS_DUMMY = 00 00
//SE_KAIFUKU = 01 00
//SE_PC_LOGIN = 02 00
//SE_PC_OFF = 03 00
//SE_PC_ON = 04 00
//SE_SELECT = 05 00
//SE_WIN_OPEN = 06 00
//SE_WALL_HIT = 07 00
//SE_DOOR = 08 00
//SE_KAIDAN = 09 00
//SE_DANSA = 0A 00
//SE_JITENSYA = 0B 00
//SE_KOUKA_L = 0C 00
//SE_KOUKA_M = 0D 00
//SE_KOUKA_H = 0E 00
//SE_BOWA2 = 0F 00
//SE_POKE_DEAD = 10 00
//SE_NIGERU = 11 00
//SE_JIDO_DOA = 12 00
//SE_NAMINORI = 13 00
//SE_BAN = 14 00
//SE_PIN = 15 00
//SE_BOO = 16 00
//SE_BOWA = 17 00
//SE_JYUNI = 18 00
//SE_A = 19 00
//SE_I = 1A 00
//SE_U = 1B 00
//SE_E = 1C 00
//SE_O = 1D 00
//SE_N = 1E 00
//SE_SEIKAI = 1F 00
//SE_HAZURE = 20 00
//SE_EXP = 21 00
//SE_JITE_PYOKO = 22 00
//SE_MU_PACHI = 23 00
//SE_TK_KASYA = 24 00
//SE_FU_ZAKU = 25 00
//SE_FU_ZAKU2 = 26 00
//SE_FU_ZUZUZU = 27 00
//SE_RU_GASHIN = 28 00
//SE_RU_GASYAN = 29 00
//SE_RU_BARI = 2A 00
//SE_RU_HYUU = 2B 00
//SE_KI_GASYAN = 2C 00
//SE_TK_WARPIN = 2D 00
//SE_TK_WARPOUT = 2E 00
//SE_TU_SAA = 2F 00
//SE_HI_TURUN = 30 00
//SE_TRACK_MOVE = 31 00
//SE_TRACK_STOP = 32 00
//SE_TRACK_HAIKI = 33 00
//SE_TRACK_DOOR = 34 00
//SE_MOTER = 35 00
//SE_CARD = 36 00
//SE_SAVE = 37 00
//SE_KON = 38 00
//SE_KON2 = 39 00
//SE_KON3 = 3A 00
//SE_KON4 = 3B 00
//SE_SUIKOMU = 3C 00
//SE_NAGERU = 3D 00
//SE_TOY_C = 3E 00
//SE_TOY_D = 3F 00
//SE_TOY_E = 40 00
//SE_TOY_F = 41 00
//SE_TOY_G = 42 00
//SE_TOY_A = 43 00
//SE_TOY_B = 44 00
//SE_TOY_C1 = 45 00
//SE_MIZU = 46 00
//SE_HASHI = 47 00
//SE_DAUGI = 48 00
//SE_PINPON = 49 00
//SE_FUUSEN1 = 4A 00
//SE_FUUSEN2 = 4B 00
//SE_FUUSEN3 = 4C 00
//SE_TOY_KABE = 4D 00
//SE_TOY_DANGO = 4E 00
//SE_DOKU = 4F 00
//SE_ESUKA = 50 00
//SE_T_AME = 51 00
//SE_T_AME_E = 52 00
//SE_T_OOAME = 53 00
//SE_T_OOAME_E = 54 00
//SE_T_KOAME = 55 00
//SE_T_KOAME_E = 56 00
//SE_T_KAMI = 57 00
//SE_T_KAMI2 = 58 00
//SE_ELEBETA = 59 00
//SE_HINSI = 5A 00
//SE_EXPMAX = 5B 00
//SE_TAMAKORO = 5C 00
//SE_TAMAKORO_E = 5D 00
//SE_BASABASA = 5E 00
//SE_REGI = 5F 00
//SE_C_GAJI = 60 00
//SE_C_MAKU_U = 61 00
//SE_C_MAKU_D = 62 00
//SE_C_PASI = 63 00
//SE_C_SYU = 64 00
//SE_C_PIKON = 65 00
//SE_REAPOKE = 66 00
//SE_OP_BASYU = 67 00
//SE_BT_START = 68 00
//SE_DENDOU = 69 00
//SE_JIHANKI = 6A 00
//SE_TAMA = 6B 00
//SE_Z_SCROLL = 6C 00
//SE_Z_PAGE = 6D 00
//SE_PN_ON = 6E 00
//SE_PN_OFF = 6F 00
//SE_Z_SEARCH = 70 00
//SE_TAMAGO = 71 00
//SE_TB_START = 72 00
//SE_TB_KON = 73 00
//SE_TB_KARA = 74 00
//SE_BIDORO = 75 00
//SE_W085 = 76 00
//SE_W085B = 77 00
//SE_W231 = 78 00
//SE_W171 = 79 00
//SE_W233 = 7A 00
//SE_W233B = 7B 00
//SE_W145 = 7C 00
//SE_W145B = 7D 00
//SE_W145C = 7E 00
//SE_W240 = 7F 00
//SE_W015 = 80 00
//SE_W081 = 81 00
//SE_W081B = 82 00
//SE_W088 = 83 00
//SE_W016 = 84 00
//SE_W016B = 85 00
//SE_W003 = 86 00
//SE_W104 = 87 00
//SE_W013 = 88 00
//SE_W196 = 89 00
//SE_W086 = 8A 00
//SE_W004 = 8B 00
//SE_W025 = 8C 00
//SE_W025B = 8D 00
//SE_W152 = 8E 00
//SE_W026 = 8F 00
//SE_W172 = 90 00
//SE_W172B = 91 00
//SE_W053 = 92 00
//SE_W007 = 93 00
//SE_W092 = 94 00
//SE_W221 = 95 00
//SE_W221B = 96 00
//SE_W052 = 97 00
//SE_W036 = 98 00
//SE_W059 = 99 00
//SE_W059B = 9A 00
//SE_W010 = 9B 00
//SE_W011 = 9C 00
//SE_W017 = 9D 00
//SE_W019 = 9E 00
//SE_W028 = 9F 00
//SE_W013B = A0 00
//SE_W044 = A1 00
//SE_W029 = A2 00
//SE_W057 = A3 00
//SE_W056 = A4 00
//SE_W250 = A5 00
//SE_W030 = A6 00
//SE_W039 = A7 00
//SE_W054 = A8 00
//SE_W077 = A9 00
//SE_W020 = AA 00
//SE_W082 = AB 00
//SE_W047 = AC 00
//SE_W195 = AD 00
//SE_W006 = AE 00
//SE_W091 = AF 00
//SE_W146 = B0 00
//SE_W120 = B1 00
//SE_W153 = B2 00
//SE_W071B = B3 00
//SE_W071 = B4 00
//SE_W103 = B5 00
//SE_W062 = B6 00
//SE_W062B = B7 00
//SE_W048 = B8 00
//SE_W187 = B9 00
//SE_W118 = BA 00
//SE_W155 = BB 00
//SE_W122 = BC 00
//SE_W060 = BD 00
//SE_W185 = BE 00
//SE_W014 = BF 00
//SE_W043 = C0 00
//SE_W207 = C1 00
//SE_W207B = C2 00
//SE_W215 = C3 00
//SE_W109 = C4 00
//SE_W173 = C5 00
//SE_W280 = C6 00
//SE_W202 = C7 00
//SE_W060B = C8 00
//SE_W076 = C9 00
//SE_W080 = CA 00
//SE_W100 = CB 00
//SE_W107 = CC 00
//SE_W166 = CD 00
//SE_W129 = CE 00
//SE_W115 = CF 00
//SE_W112 = D0 00
//SE_W197 = D1 00
//SE_W199 = D2 00
//SE_W236 = D3 00
//SE_W204 = D4 00
//SE_W268 = D5 00
//SE_W070 = D6 00
//SE_W063 = D7 00
//SE_W127 = D8 00
//SE_W179 = D9 00
//SE_W151 = DA 00
//SE_W201 = DB 00
//SE_W161 = DC 00
//SE_W161B = DD 00
//SE_W227 = DE 00
//SE_W227B = DF 00
//SE_W226 = E0 00
//SE_W208 = E1 00
//SE_W213 = E2 00
//SE_W213B = E3 00
//SE_W234 = E4 00
//SE_W260 = E5 00
//SE_W328 = E6 00
//SE_W320 = E7 00
//SE_W255 = E8 00
//SE_W291 = E9 00
//SE_W089 = EA 00
//SE_W239 = EB 00
//SE_W230 = EC 00
//SE_W281 = ED 00
//SE_W327 = EE 00
//SE_W287 = EF 00
//SE_W257 = F0 00
//SE_W253 = F1 00
//SE_W258 = F2 00
//SE_W322 = F3 00
//SE_W298 = F4 00
//SE_W287B = F5 00
//SE_W114 = F6 00
//SE_W063B = F7 00
//SE_RG_W_DOOR = F8 00
//SE_RG_CARD1 = F9 00
//SE_RG_CARD2 = FA 00
//SE_RG_CARD3 = FB 00
//SE_RG_BAG1 = FC 00
//SE_RG_BAG2 = FD 00
//SE_RG_GETTING = FE 00
//SE_RG_SHOP = FF 00
//SE_RG_KITEKI = 00 01
//SE_RG_HELP_OP = 01 01
//SE_RG_HELP_CL = 02 01
//SE_RG_HELP_NG = 03 01
//SE_RG_DEOMOV = 04 01
//SE_RG_EXCELLENT = 05 01
//SE_RG_NAWAMISS = 06 01
//SE_TOREEYE = 07 01
//SE_TOREOFF = 08 01
//SE_HANTEI1 = 09 01
//SE_HANTEI2 = 0A 01
//SE_CURTAIN = 0B 01
//SE_CURTAIN1 = 0C 01
//SE_USSOKI = 0D 01
//MUS_TETSUJI = 5E 01
//MUS_FIELD13 = 5F 01
//MUS_KACHI22 = 60 01
//MUS_KACHI2 = 61 01
//MUS_KACHI3 = 62 01
//MUS_KACHI5 = 63 01
//MUS_PCC = 64 01
//MUS_NIBI = 65 01
//MUS_SUIKUN = 66 01
//MUS_DOORO1 = 67 01
//MUS_DOORO_X1 = 68 01
//MUS_DOORO_X3 = 69 01
//MUS_MACHI_S2 = 6A 01
//MUS_MACHI_S4 = 6B 01
//MUS_GIM = 6C 01
//MUS_NAMINORI = 6D 01
//MUS_DAN01 = 6E 01
//MUS_FANFA1 = 6F 01
//MUS_ME_ASA = 70 01
//MUS_ME_BACHI = 71 01
//MUS_FANFA4 = 72 01
//MUS_FANFA5 = 73 01
//MUS_ME_WAZA = 74 01
//MUS_BIJYUTU = 75 01
//MUS_DOORO_X4 = 76 01
//MUS_FUNE_KAN = 77 01
//MUS_ME_SHINKA = 78 01
//MUS_SHINKA = 79 01
//MUS_ME_WASURE = 7A 01
//MUS_SYOUJOEYE = 7B 01
//MUS_BOYEYE = 7C 01
//MUS_DAN02 = 7D 01
//MUS_MACHI_S3 = 7E 01
//MUS_ODAMAKI = 7F 01
//MUS_B_TOWER = 80 01
//MUS_SWIMEYE = 81 01
//MUS_DAN03 = 82 01
//MUS_ME_KINOMI = 83 01
//MUS_ME_TAMA = 84 01
//MUS_ME_B_BIG = 85 01
//MUS_ME_B_SMALL = 86 01
//MUS_ME_ZANNEN = 87 01
//MUS_BD_TIME = 88 01
//MUS_TEST1 = 89 01
//MUS_TEST2 = 8A 01
//MUS_TEST3 = 8B 01
//MUS_TEST4 = 8C 01
//MUS_TEST = 8D 01
//MUS_GOMACHI0 = 8E 01
//MUS_GOTOWN = 8F 01
//MUS_POKECEN = 90 01
//MUS_NEXTROAD = 91 01
//MUS_GRANROAD = 92 01
//MUS_CYCLING = 93 01
//MUS_FRIENDLY = 94 01
//MUS_MISHIRO = 95 01
//MUS_TOZAN = 96 01
//MUS_GIRLEYE = 97 01
//MUS_MINAMO = 98 01
//MUS_ASHROAD = 99 01
//MUS_EVENT0 = 9A 01
//MUS_DEEPDEEP = 9B 01
//MUS_KACHI1 = 9C 01
//MUS_TITLE3 = 9D 01
//MUS_DEMO1 = 9E 01
//MUS_GIRL_SUP = 9F 01
//MUS_HAGESHII = A0 01
//MUS_KAKKOII = A1 01
//MUS_KAZANBAI = A2 01
//MUS_AQA_0 = A3 01
//MUS_TSURETEK = A4 01
//MUS_BOY_SUP = A5 01
//MUS_RAINBOW = A6 01
//MUS_AYASII = A7 01
//MUS_KACHI4 = A8 01
//MUS_ROPEWAY = A9 01
//MUS_CASINO = AA 01
//MUS_HIGHTOWN = AB 01
//MUS_SAFARI = AC 01
//MUS_C_ROAD = AD 01
//MUS_AJITO = AE 01
//MUS_M_BOAT = AF 01
//MUS_M_DUNGON = B0 01
//MUS_FINECITY = B1 01
//MUS_MACHUPI = B2 01
//MUS_P_SCHOOL = B3 01
//MUS_DENDOU = B4 01
//MUS_TONEKUSA = B5 01
//MUS_MABOROSI = B6 01
//MUS_CON_FAN = B7 01
//MUS_CONTEST0 = B8 01
//MUS_MGM0 = B9 01
//MUS_T_BATTLE = BA 01
//MUS_OOAME = BB 01
//MUS_HIDERI = BC 01
//MUS_RUNECITY = BD 01
//MUS_CON_K = BE 01
//MUS_EIKOU_R = BF 01
//MUS_KARAKURI = C0 01
//MUS_HUTAGO = C1 01
//MUS_SITENNOU = C2 01
//MUS_YAMA_EYE = C3 01
//MUS_CONLOBBY = C4 01
//MUS_INTER_V = C5 01
//MUS_DAIGO = C6 01
//MUS_THANKFOR = C7 01
//MUS_END = C8 01
//MUS_B_FRONTIER = C9 01
//MUS_B_ARENA = CA 01
//MUS_ME_POINTGET = CB 01
//MUS_ME_TORE_EYE = CC 01
//MUS_PYRAMID = CD 01
//MUS_PYRAMID_TOP = CE 01
//MUS_B_PALACE = CF 01
//MUS_REKKUU_KOURIN = D0 01
//MUS_SATTOWER = D1 01
//MUS_ME_SYMBOLGET = D2 01
//MUS_B_DOME = D3 01
//MUS_B_TUBE = D4 01
//MUS_B_FACTORY = D5 01
//MUS_VS_REKKU = D6 01
//MUS_VS_FRONT = D7 01
//MUS_VS_MEW = D8 01
//MUS_B_DOME1 = D9 01
//MUS_BATTLE27 = DA 01
//MUS_BATTLE31 = DB 01
//MUS_BATTLE20 = DC 01
//MUS_BATTLE32 = DD 01
//MUS_BATTLE33 = DE 01
//MUS_BATTLE36 = DF 01
//MUS_BATTLE34 = E0 01
//MUS_BATTLE35 = E1 01
//MUS_BATTLE38 = E2 01
//MUS_BATTLE30 = E3 01
//MUS_RG_ANNAI = E4 01
//MUS_RG_SLOT = E5 01
//MUS_RG_AJITO = E6 01
//MUS_RG_GYM = E7 01
//MUS_RG_PURIN = E8 01
//MUS_RG_DEMO = E9 01
//MUS_RG_TITLE = EA 01
//MUS_RG_GUREN = EB 01
//MUS_RG_SHION = EC 01
//MUS_RG_KAIHUKU = ED 01
//MUS_RG_CYCLING = EE 01
//MUS_RG_ROCKET = EF 01
//MUS_RG_SHOUJO = F0 01
//MUS_RG_SHOUNEN = F1 01
//MUS_RG_DENDOU = F2 01
//MUS_RG_T_MORI = F3 01
//MUS_RG_OTSUKIMI = F4 01
//MUS_RG_POKEYASHI = F5 01
//MUS_RG_ENDING = F6 01
//MUS_RG_LOAD01 = F7 01
//MUS_RG_OPENING = F8 01
//MUS_RG_LOAD02 = F9 01
//MUS_RG_LOAD03 = FA 01
//MUS_RG_CHAMP_R = FB 01
//MUS_RG_VS_GYM = FC 01
//MUS_RG_VS_TORE = FD 01
//MUS_RG_VS_YASEI = FE 01
//MUS_RG_VS_LAST = FF 01
//MUS_RG_MASARA = 00 02
//MUS_RG_KENKYU = 01 02
//MUS_RG_OHKIDO = 02 02
//MUS_RG_POKECEN = 03 02
//MUS_RG_SANTOAN = 04 02
//MUS_RG_NAMINORI = 05 02
//MUS_RG_P_TOWER = 06 02
//MUS_RG_SHIRUHU = 07 02
//MUS_RG_HANADA = 08 02
//MUS_RG_TAMAMUSI = 09 02
//MUS_RG_WIN_TRE = 0A 02
//MUS_RG_WIN_YASEI = 0B 02
//MUS_RG_WIN_GYM = 0C 02
//MUS_RG_KUCHIBA = 0D 02
//MUS_RG_NIBI = 0E 02
//MUS_RG_RIVAL1 = 0F 02
//MUS_RG_RIVAL2 = 10 02
//MUS_RG_FAN2 = 11 02
//MUS_RG_FAN5 = 12 02
//MUS_RG_FAN6 = 13 02
//MUS_ME_RG_PHOTO = 14 02
//MUS_RG_TITLEROG = 15 02
//MUS_RG_GET_YASEI = 16 02
//MUS_RG_SOUSA = 17 02
//MUS_RG_SEKAIKAN = 18 02
//MUS_RG_SEIBETU = 19 02
//MUS_RG_JUMP = 1A 02
//MUS_RG_UNION = 1B 02
//MUS_RG_NETWORK = 1C 02
//MUS_RG_OKURIMONO = 1D 02
//MUS_RG_KINOMIKUI = 1E 02
//MUS_RG_NANADUNGEON = 1F 02
//MUS_RG_OSHIE_TV = 20 02
//MUS_RG_NANASHIMA = 21 02
//MUS_RG_NANAISEKI = 22 02
//MUS_RG_NANA123 = 23 02
//MUS_RG_NANA45 = 24 02
//MUS_RG_NANA67 = 25 02
//MUS_RG_POKEFUE = 26 02
//MUS_RG_VS_DEO = 27 02
//MUS_RG_VS_MYU2 = 28 02
//MUS_RG_VS_DEN = 29 02
//MUS_RG_EXEYE = 2A 02
//MUS_RG_DEOEYE = 2B 02
//MUS_RG_T_TOWER = 2C 02
//MUS_RG_SLOWMASARA = 2D 02
//MUS_RG_TVNOIZE = 2E 02
//PH_TRAP_BLEND = 2F 02
//PH_TRAP_HELD = 30 02
//PH_TRAP_SOLO = 31 02
//PH_FACE_BLEND = 32 02
//PH_FACE_HELD = 33 02
//PH_FACE_SOLO = 34 02
//PH_CLOTH_BLEND = 35 02
//PH_CLOTH_HELD = 36 02
//PH_CLOTH_SOLO = 37 02
//PH_DRESS_BLEND = 38 02
//PH_DRESS_HELD = 39 02
//PH_DRESS_SOLO = 3A 02
//PH_FLEECE_BLEND = 3B 02
//PH_FLEECE_HELD = 3C 02
//PH_FLEECE_SOLO = 3D 02
//PH_KIT_BLEND = 3E 02
//PH_KIT_HELD = 3F 02
//PH_KIT_SOLO = 40 02
//PH_PRICE_BLEND = 41 02
//PH_PRICE_HELD = 42 02
//PH_PRICE_SOLO = 43 02
//PH_LOT_BLEND = 44 02
//PH_LOT_HELD = 45 02
//PH_LOT_SOLO = 46 02
//PH_GOAT_BLEND = 47 02
//PH_GOAT_HELD = 48 02
//PH_GOAT_SOLO = 49 02
//PH_THOUGHT_BLEND = 4A 02
//PH_THOUGHT_HELD = 4B 02
//PH_THOUGHT_SOLO = 4C 02
//PH_CHOICE_BLEND = 4D 02
//PH_CHOICE_HELD = 4E 02
//PH_CHOICE_SOLO = 4F 02
//PH_MOUTH_BLEND = 50 02
//PH_MOUTH_HELD = 51 02
//PH_MOUTH_SOLO = 52 02
//PH_FOOT_BLEND = 53 02
//PH_FOOT_HELD = 54 02
//PH_FOOT_SOLO = 55 02
//PH_GOOSE_BLEND = 56 02
//PH_GOOSE_HELD = 57 02
//PH_GOOSE_SOLO = 58 02
//PH_STRUT_BLEND = 59 02
//PH_STRUT_HELD = 5A 02
//PH_STRUT_SOLO = 5B 02
//PH_CURE_BLEND = 5C 02
//PH_CURE_HELD = 5D 02
//PH_CURE_SOLO = 5E 02
//PH_NURSE_BLEND = 5F 02
//PH_NURSE_HELD = 60 02
//PH_NURSE_SOLO = 61 02
//
//A_BUTTON = F8 00
//B_BUTTON = F8 01
//L_BUTTON = F8 02
//R_BUTTON = F8 03
//START_BUTTON = F8 04
//SELECT_BUTTON = F8 05
//DPAD_UP = F8 06
//DPAD_DOWN = F8 07
//DPAD_LEFT = F8 08
//DPAD_RIGHT = F8 09
//DPAD_UPDOWN = F8 0A
//DPAD_LEFTRIGHT = F8 0B
//DPAD_NONE = F8 0C
//
//UP_ARROW_2 = F9 00
//DOWN_ARROW_2 = F9 01
//LEFT_ARROW_2 = F9 02
//RIGHT_ARROW_2 = F9 03
//PLUS = F9 04
//LV_2 = F9 05
//PP = F9 06
//ID = F9 07
//NO = F9 08
//UNDERSCORE = F9 09
//CIRCLE_1 = F9 0A
//CIRCLE_2 = F9 0B
//CIRCLE_3 = F9 0C
//CIRCLE_4 = F9 0D
//CIRCLE_5 = F9 0E
//CIRCLE_6 = F9 0F
//CIRCLE_7 = F9 10
//CIRCLE_8 = F9 11
//CIRCLE_9 = F9 12
//ROUND_LEFT_PAREN = F9 13
//ROUND_RIGHT_PAREN = F9 14
//CIRCLE_DOT = F9 15
//TRIANGLE = F9 16
//BIG_MULT_X = F9 17
//
//EMOJI_UNDERSCORE = F9 D0
//EMOJI_PIPE = F9 D1
//EMOJI_HIGHBAR = F9 D2
//EMOJI_TILDE = F9 D3
//EMOJI_LEFT_PAREN = F9 D4
//EMOJI_RIGHT_PAREN = F9 D5
//EMOJI_UNION = F9 D6 @ ⊂
//EMOJI_GREATER_THAN = F9 D7
//EMOJI_LEFT_EYE = F9 D8
//EMOJI_RIGHT_EYE = F9 D9
//EMOJI_AT = F9 DA
//EMOJI_SEMICOLON = F9 DB
//EMOJI_PLUS = F9 DC
//EMOJI_MINUS = F9 DD
//EMOJI_EQUALS = F9 DE
//EMOJI_SPIRAL = F9 DF
//EMOJI_TONGUE = F9 E0
//EMOJI_TRIANGLE_OUTLINE = F9 E1
//EMOJI_ACUTE = F9 E2
//EMOJI_GRAVE = F9 E3
//EMOJI_CIRCLE = F9 E4
//EMOJI_TRIANGLE = F9 E5
//EMOJI_SQUARE = F9 E6
//EMOJI_HEART = F9 E7
//EMOJI_MOON = F9 E8
//EMOJI_NOTE = F9 E9
//EMOJI_BALL = F9 EA
//EMOJI_BOLT = F9 EB
//EMOJI_LEAF = F9 EC
//EMOJI_FIRE = F9 ED
//EMOJI_WATER = F9 EE
//EMOJI_LEFT_FIST = F9 EF
//EMOJI_RIGHT_FIST = F9 F0
//EMOJI_BIGWHEEL = F9 F1
//EMOJI_SMALLWHEEL = F9 F2
//EMOJI_SPHERE = F9 F3
//EMOJI_IRRITATED = F9 F4
//EMOJI_MISCHIEVOUS = F9 F5
//EMOJI_HAPPY = F9 F6
//EMOJI_ANGRY = F9 F7
//EMOJI_SURPRISED = F9 F8
//EMOJI_BIGSMILE = F9 F9
//EMOJI_EVIL = F9 FA
//EMOJI_TIRED = F9 FB
//EMOJI_NEUTRAL = F9 FC
//EMOJI_SHOCKED = F9 FD
//EMOJI_BIGANGER = F9 FE
//
//'\l' = FA @ scroll up window text
//'\p' = FB @ new paragraph
//'\n' = FE @ new line
//

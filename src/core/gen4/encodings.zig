const std = @import("std");
const rom = @import("../rom.zig");

const io = std.io;
const mem = std.mem;

pub const all = [_]rom.encoding.Char{
    .{ "\\x0000", "\x00\x00" },
    .{ "\\x0001", "\x01\x00" },
    .{ "ぁ", "\x02\x00" },
    .{ "あ", "\x03\x00" },
    .{ "ぃ", "\x04\x00" },
    .{ "い", "\x05\x00" },
    .{ "ぅ", "\x06\x00" },
    .{ "う", "\x07\x00" },
    .{ "ぇ", "\x08\x00" },
    .{ "え", "\x09\x00" },
    .{ "ぉ", "\x0A\x00" },
    .{ "お", "\x0B\x00" },
    .{ "か", "\x0C\x00" },
    .{ "が", "\x0D\x00" },
    .{ "き", "\x0E\x00" },
    .{ "ぎ", "\x0F\x00" },
    .{ "く", "\x10\x00" },
    .{ "ぐ", "\x11\x00" },
    .{ "け", "\x12\x00" },
    .{ "げ", "\x13\x00" },
    .{ "こ", "\x14\x00" },
    .{ "ご", "\x15\x00" },
    .{ "さ", "\x16\x00" },
    .{ "ざ", "\x17\x00" },
    .{ "し", "\x18\x00" },
    .{ "じ", "\x19\x00" },
    .{ "す", "\x1A\x00" },
    .{ "ず", "\x1B\x00" },
    .{ "せ", "\x1C\x00" },
    .{ "ぜ", "\x1D\x00" },
    .{ "そ", "\x1E\x00" },
    .{ "ぞ", "\x1F\x00" },
    .{ "た", "\x20\x00" },
    .{ "だ", "\x21\x00" },
    .{ "ち", "\x22\x00" },
    .{ "ぢ", "\x23\x00" },
    .{ "っ", "\x24\x00" },
    .{ "つ", "\x25\x00" },
    .{ "づ", "\x26\x00" },
    .{ "て", "\x27\x00" },
    .{ "で", "\x28\x00" },
    .{ "と", "\x29\x00" },
    .{ "ど", "\x2A\x00" },
    .{ "な", "\x2B\x00" },
    .{ "に", "\x2C\x00" },
    .{ "ぬ", "\x2D\x00" },
    .{ "ね", "\x2E\x00" },
    .{ "の", "\x2F\x00" },
    .{ "は", "\x30\x00" },
    .{ "ば", "\x31\x00" },
    .{ "ぱ", "\x32\x00" },
    .{ "ひ", "\x33\x00" },
    .{ "び", "\x34\x00" },
    .{ "ぴ", "\x35\x00" },
    .{ "ふ", "\x36\x00" },
    .{ "ぶ", "\x37\x00" },
    .{ "ぷ", "\x38\x00" },
    .{ "へ", "\x39\x00" },
    .{ "べ", "\x3A\x00" },
    .{ "ぺ", "\x3B\x00" },
    .{ "ほ", "\x3C\x00" },
    .{ "ぼ", "\x3D\x00" },
    .{ "ぽ", "\x3E\x00" },
    .{ "ま", "\x3F\x00" },
    .{ "み", "\x40\x00" },
    .{ "む", "\x41\x00" },
    .{ "め", "\x42\x00" },
    .{ "も", "\x43\x00" },
    .{ "ゃ", "\x44\x00" },
    .{ "や", "\x45\x00" },
    .{ "ゅ", "\x46\x00" },
    .{ "ゆ", "\x47\x00" },
    .{ "ょ", "\x48\x00" },
    .{ "よ", "\x49\x00" },
    .{ "ら", "\x4A\x00" },
    .{ "り", "\x4B\x00" },
    .{ "る", "\x4C\x00" },
    .{ "れ", "\x4D\x00" },
    .{ "ろ", "\x4E\x00" },
    .{ "わ", "\x4F\x00" },
    .{ "を", "\x50\x00" },
    .{ "ん", "\x51\x00" },
    .{ "ァ", "\x52\x00" },
    .{ "ア", "\x53\x00" },
    .{ "ィ", "\x54\x00" },
    .{ "イ", "\x55\x00" },
    .{ "ゥ", "\x56\x00" },
    .{ "ウ", "\x57\x00" },
    .{ "ェ", "\x58\x00" },
    .{ "エ", "\x59\x00" },
    .{ "ォ", "\x5A\x00" },
    .{ "オ", "\x5B\x00" },
    .{ "カ", "\x5C\x00" },
    .{ "ガ", "\x5D\x00" },
    .{ "キ", "\x5E\x00" },
    .{ "ギ", "\x5F\x00" },
    .{ "ク", "\x60\x00" },
    .{ "グ", "\x61\x00" },
    .{ "ケ", "\x62\x00" },
    .{ "ゲ", "\x63\x00" },
    .{ "コ", "\x64\x00" },
    .{ "ゴ", "\x65\x00" },
    .{ "サ", "\x66\x00" },
    .{ "ザ", "\x67\x00" },
    .{ "シ", "\x68\x00" },
    .{ "ジ", "\x69\x00" },
    .{ "ス", "\x6A\x00" },
    .{ "ズ", "\x6B\x00" },
    .{ "セ", "\x6C\x00" },
    .{ "ゼ", "\x6D\x00" },
    .{ "ソ", "\x6E\x00" },
    .{ "ゾ", "\x6F\x00" },
    .{ "タ", "\x70\x00" },
    .{ "ダ", "\x71\x00" },
    .{ "チ", "\x72\x00" },
    .{ "ヂ", "\x73\x00" },
    .{ "ッ", "\x74\x00" },
    .{ "ツ", "\x75\x00" },
    .{ "ヅ", "\x76\x00" },
    .{ "テ", "\x77\x00" },
    .{ "デ", "\x78\x00" },
    .{ "ト", "\x79\x00" },
    .{ "ド", "\x7A\x00" },
    .{ "ナ", "\x7B\x00" },
    .{ "ニ", "\x7C\x00" },
    .{ "ヌ", "\x7D\x00" },
    .{ "ネ", "\x7E\x00" },
    .{ "ノ", "\x7F\x00" },
    .{ "ハ", "\x80\x00" },
    .{ "バ", "\x81\x00" },
    .{ "パ", "\x82\x00" },
    .{ "ヒ", "\x83\x00" },
    .{ "ビ", "\x84\x00" },
    .{ "ピ", "\x85\x00" },
    .{ "フ", "\x86\x00" },
    .{ "ブ", "\x87\x00" },
    .{ "プ", "\x88\x00" },
    .{ "ヘ", "\x89\x00" },
    .{ "ベ", "\x8A\x00" },
    .{ "ペ", "\x8B\x00" },
    .{ "ホ", "\x8C\x00" },
    .{ "ボ", "\x8D\x00" },
    .{ "ポ", "\x8E\x00" },
    .{ "マ", "\x8F\x00" },
    .{ "ミ", "\x90\x00" },
    .{ "ム", "\x91\x00" },
    .{ "メ", "\x92\x00" },
    .{ "モ", "\x93\x00" },
    .{ "ャ", "\x94\x00" },
    .{ "ヤ", "\x95\x00" },
    .{ "ュ", "\x96\x00" },
    .{ "ユ", "\x97\x00" },
    .{ "ョ", "\x98\x00" },
    .{ "ヨ", "\x99\x00" },
    .{ "ラ", "\x9A\x00" },
    .{ "リ", "\x9B\x00" },
    .{ "ル", "\x9C\x00" },
    .{ "レ", "\x9D\x00" },
    .{ "ロ", "\x9E\x00" },
    .{ "ワ", "\x9F\x00" },
    .{ "ヲ", "\xA0\x00" },
    .{ "ン", "\xA1\x00" },
    .{ "０", "\xA2\x00" },
    .{ "１", "\xA3\x00" },
    .{ "２", "\xA4\x00" },
    .{ "３", "\xA5\x00" },
    .{ "４", "\xA6\x00" },
    .{ "５", "\xA7\x00" },
    .{ "６", "\xA8\x00" },
    .{ "７", "\xA9\x00" },
    .{ "８", "\xAA\x00" },
    .{ "９", "\xAB\x00" },
    .{ "Ａ", "\xAC\x00" },
    .{ "Ｂ", "\xAD\x00" },
    .{ "Ｃ", "\xAE\x00" },
    .{ "Ｄ", "\xAF\x00" },
    .{ "Ｅ", "\xB0\x00" },
    .{ "Ｆ", "\xB1\x00" },
    .{ "Ｇ", "\xB2\x00" },
    .{ "Ｈ", "\xB3\x00" },
    .{ "Ｉ", "\xB4\x00" },
    .{ "Ｊ", "\xB5\x00" },
    .{ "Ｋ", "\xB6\x00" },
    .{ "Ｌ", "\xB7\x00" },
    .{ "Ｍ", "\xB8\x00" },
    .{ "Ｎ", "\xB9\x00" },
    .{ "Ｏ", "\xBA\x00" },
    .{ "Ｐ", "\xBB\x00" },
    .{ "Ｑ", "\xBC\x00" },
    .{ "Ｒ", "\xBD\x00" },
    .{ "Ｓ", "\xBE\x00" },
    .{ "Ｔ", "\xBF\x00" },
    .{ "Ｕ", "\xC0\x00" },
    .{ "Ｖ", "\xC1\x00" },
    .{ "Ｗ", "\xC2\x00" },
    .{ "Ｘ", "\xC3\x00" },
    .{ "Ｙ", "\xC4\x00" },
    .{ "Ｚ", "\xC5\x00" },
    .{ "ａ", "\xC6\x00" },
    .{ "ｂ", "\xC7\x00" },
    .{ "ｃ", "\xC8\x00" },
    .{ "ｄ", "\xC9\x00" },
    .{ "ｅ", "\xCA\x00" },
    .{ "ｆ", "\xCB\x00" },
    .{ "ｇ", "\xCC\x00" },
    .{ "ｈ", "\xCD\x00" },
    .{ "ｉ", "\xCE\x00" },
    .{ "ｊ", "\xCF\x00" },
    .{ "ｋ", "\xD0\x00" },
    .{ "ｌ", "\xD1\x00" },
    .{ "ｍ", "\xD2\x00" },
    .{ "ｎ", "\xD3\x00" },
    .{ "ｏ", "\xD4\x00" },
    .{ "ｐ", "\xD5\x00" },
    .{ "ｑ", "\xD6\x00" },
    .{ "ｒ", "\xD7\x00" },
    .{ "ｓ", "\xD8\x00" },
    .{ "ｔ", "\xD9\x00" },
    .{ "ｕ", "\xDA\x00" },
    .{ "ｖ", "\xDB\x00" },
    .{ "ｗ", "\xDC\x00" },
    .{ "ｘ", "\xDD\x00" },
    .{ "ｙ", "\xDE\x00" },
    .{ "ｚ", "\xDF\x00" },
    .{ " (224)", "\xE0\x00" },
    .{ "！", "\xE1\x00" },
    .{ "？", "\xE2\x00" },
    .{ "、", "\xE3\x00" },
    .{ "。", "\xE4\x00" },
    .{ "…", "\xE5\x00" },
    .{ "・", "\xE6\x00" },
    .{ "／", "\xE7\x00" },
    .{ "「", "\xE8\x00" },
    .{ "」", "\xE9\x00" },
    .{ "『", "\xEA\x00" },
    .{ "』", "\xEB\x00" },
    .{ "（", "\xEC\x00" },
    .{ "）", "\xED\x00" },
    .{ "♂", "\xEE\x00" },
    .{ "♀", "\xEF\x00" },
    .{ "＋", "\xF0\x00" },
    .{ "ー", "\xF1\x00" },
    .{ "×", "\xF2\x00" },
    .{ "÷", "\xF3\x00" },
    .{ "=", "\xF4\x00" },
    .{ "~", "\xF5\x00" },
    .{ "：", "\xF6\x00" },
    .{ "；", "\xF7\x00" },
    .{ "．", "\xF8\x00" },
    .{ "，", "\xF9\x00" },
    .{ "♠", "\xFA\x00" },
    .{ "♣", "\xFB\x00" },
    .{ "♥", "\xFC\x00" },
    .{ "♦", "\xFD\x00" },
    .{ "★", "\xFE\x00" },
    .{ "◎", "\xFF\x00" },
    .{ "○", "\x00\x01" },
    .{ "□", "\x01\x01" },
    .{ "△", "\x02\x01" },
    .{ "◇", "\x03\x01" },
    .{ "＠", "\x04\x01" },
    .{ "♪", "\x05\x01" },
    .{ "%", "\x06\x01" },
    .{ "☀", "\x07\x01" },
    .{ "☁", "\x08\x01" },
    .{ "☂", "\x09\x01" },
    .{ "☃", "\x0A\x01" },
    .{ "\\x010B", "\x0B\x01" },
    .{ "\\x010C", "\x0C\x01" },
    .{ "\\x010D", "\x0D\x01" },
    .{ "\\x010E", "\x0E\x01" },
    .{ "⤴", "\x0F\x01" },
    .{ "⤵", "\x10\x01" },
    .{ "\\x0111", "\x11\x01" },
    .{ "円", "\x12\x01" },
    .{ "\\x0113", "\x13\x01" },
    .{ "\\x0114", "\x14\x01" },
    .{ "\\x0115", "\x15\x01" },
    .{ "✉", "\x16\x01" },
    .{ "\\x0117", "\x17\x01" },
    .{ "\\x0118", "\x18\x01" },
    .{ "\\x0119", "\x19\x01" },
    .{ "\\x011A", "\x1A\x01" },
    .{ "←", "\x1B\x01" },
    .{ "↑", "\x1C\x01" },
    .{ "↓", "\x1D\x01" },
    .{ "→", "\x1E\x01" },
    .{ "\\x011F", "\x1F\x01" },
    .{ "&", "\x20\x01" },
    .{ "0", "\x21\x01" },
    .{ "1", "\x22\x01" },
    .{ "2", "\x23\x01" },
    .{ "3", "\x24\x01" },
    .{ "4", "\x25\x01" },
    .{ "5", "\x26\x01" },
    .{ "6", "\x27\x01" },
    .{ "7", "\x28\x01" },
    .{ "8", "\x29\x01" },
    .{ "9", "\x2A\x01" },
    .{ "A", "\x2B\x01" },
    .{ "B", "\x2C\x01" },
    .{ "C", "\x2D\x01" },
    .{ "D", "\x2E\x01" },
    .{ "E", "\x2F\x01" },
    .{ "F", "\x30\x01" },
    .{ "G", "\x31\x01" },
    .{ "H", "\x32\x01" },
    .{ "I", "\x33\x01" },
    .{ "J", "\x34\x01" },
    .{ "K", "\x35\x01" },
    .{ "L", "\x36\x01" },
    .{ "M", "\x37\x01" },
    .{ "N", "\x38\x01" },
    .{ "O", "\x39\x01" },
    .{ "P", "\x3A\x01" },
    .{ "Q", "\x3B\x01" },
    .{ "R", "\x3C\x01" },
    .{ "S", "\x3D\x01" },
    .{ "T", "\x3E\x01" },
    .{ "U", "\x3F\x01" },
    .{ "V", "\x40\x01" },
    .{ "W", "\x41\x01" },
    .{ "X", "\x42\x01" },
    .{ "Y", "\x43\x01" },
    .{ "Z", "\x44\x01" },
    .{ "a", "\x45\x01" },
    .{ "b", "\x46\x01" },
    .{ "c", "\x47\x01" },
    .{ "d", "\x48\x01" },
    .{ "e", "\x49\x01" },
    .{ "f", "\x4A\x01" },
    .{ "g", "\x4B\x01" },
    .{ "h", "\x4C\x01" },
    .{ "i", "\x4D\x01" },
    .{ "j", "\x4E\x01" },
    .{ "k", "\x4F\x01" },
    .{ "l", "\x50\x01" },
    .{ "m", "\x51\x01" },
    .{ "n", "\x52\x01" },
    .{ "o", "\x53\x01" },
    .{ "p", "\x54\x01" },
    .{ "q", "\x55\x01" },
    .{ "r", "\x56\x01" },
    .{ "s", "\x57\x01" },
    .{ "t", "\x58\x01" },
    .{ "u", "\x59\x01" },
    .{ "v", "\x5A\x01" },
    .{ "w", "\x5B\x01" },
    .{ "x", "\x5C\x01" },
    .{ "y", "\x5D\x01" },
    .{ "z", "\x5E\x01" },
    .{ "À", "\x5F\x01" },
    .{ "Á", "\x60\x01" },
    .{ "Â", "\x61\x01" },
    .{ "\\x0162", "\x62\x01" },
    .{ "Ä", "\x63\x01" },
    .{ "\\x0164", "\x64\x01" },
    .{ "\\x0165", "\x65\x01" },
    .{ "Ç", "\x66\x01" },
    .{ "È", "\x67\x01" },
    .{ "É", "\x68\x01" },
    .{ "Ê", "\x69\x01" },
    .{ "Ë", "\x6A\x01" },
    .{ "Ì", "\x6B\x01" },
    .{ "Í", "\x6C\x01" },
    .{ "Î", "\x6D\x01" },
    .{ "Ï", "\x6E\x01" },
    .{ "\\x016F", "\x6F\x01" },
    .{ "Ñ", "\x70\x01" },
    .{ "Ò", "\x71\x01" },
    .{ "Ó", "\x72\x01" },
    .{ "Ô", "\x73\x01" },
    .{ "\\x0174", "\x74\x01" },
    .{ "Ö", "\x75\x01" },
    .{ "×", "\x76\x01" },
    .{ "\\x0177", "\x77\x01" },
    .{ "Ù", "\x78\x01" },
    .{ "Ú", "\x79\x01" },
    .{ "Û", "\x7A\x01" },
    .{ "Ü", "\x7B\x01" },
    .{ "\\x017C", "\x7C\x01" },
    .{ "\\x017D", "\x7D\x01" },
    .{ "ß", "\x7E\x01" },
    .{ "à", "\x7F\x01" },
    .{ "á", "\x80\x01" },
    .{ "â", "\x81\x01" },
    .{ "\\x0182", "\x82\x01" },
    .{ "ä", "\x83\x01" },
    .{ "\\x0184", "\x84\x01" },
    .{ "\\x0185", "\x85\x01" },
    .{ "ç", "\x86\x01" },
    .{ "è", "\x87\x01" },
    .{ "é", "\x88\x01" },
    .{ "ê", "\x89\x01" },
    .{ "ë", "\x8A\x01" },
    .{ "ì", "\x8B\x01" },
    .{ "í", "\x8C\x01" },
    .{ "î", "\x8D\x01" },
    .{ "ï", "\x8E\x01" },
    .{ "\\x018F", "\x8F\x01" },
    .{ "ñ", "\x90\x01" },
    .{ "ò", "\x91\x01" },
    .{ "ó", "\x92\x01" },
    .{ "ô", "\x93\x01" },
    .{ "\\x0194", "\x94\x01" },
    .{ "ö", "\x95\x01" },
    .{ "÷", "\x96\x01" },
    .{ "\\x0197", "\x97\x01" },
    .{ "ù", "\x98\x01" },
    .{ "ú", "\x99\x01" },
    .{ "û", "\x9A\x01" },
    .{ "ü", "\x9B\x01" },
    .{ "\\x019C", "\x9C\x01" },
    .{ "\\x019D", "\x9D\x01" },
    .{ "\\x019E", "\x9E\x01" },
    .{ "Œ", "\x9F\x01" },
    .{ "œ", "\xA0\x01" },
    .{ "\\x01A1", "\xA1\x01" },
    .{ "\\x01A2", "\xA2\x01" },
    .{ "ª", "\xA3\x01" },
    .{ "º", "\xA4\x01" },
    .{ "ᵉʳ", "\xA5\x01" },
    .{ "ʳᵉ", "\xA6\x01" },
    .{ "ʳ", "\xA7\x01" },
    .{ "¥", "\xA8\x01" },
    .{ "¡", "\xA9\x01" },
    .{ "¿", "\xAA\x01" },
    .{ "!", "\xAB\x01" },
    .{ "?", "\xAC\x01" },
    .{ ",", "\xAD\x01" },
    .{ ".", "\xAE\x01" },
    .{ "…", "\xAF\x01" },
    .{ "·", "\xB0\x01" },
    .{ "/", "\xB1\x01" },
    .{ "‘", "\xB2\x01" },
    .{ "'", "\xB3\x01" },
    .{ "“", "\xB4\x01" },
    .{ "”", "\xB5\x01" },
    .{ "„", "\xB6\x01" },
    .{ "«", "\xB7\x01" },
    .{ "»", "\xB8\x01" },
    .{ "(", "\xB9\x01" },
    .{ ")", "\xBA\x01" },
    .{ "♂", "\xBB\x01" },
    .{ "♀", "\xBC\x01" },
    .{ "+", "\xBD\x01" },
    .{ "-", "\xBE\x01" },
    .{ "*", "\xBF\x01" },
    .{ "#", "\xC0\x01" },
    .{ "=", "\xC1\x01" },
    .{ "\\and", "\xC2\x01" },
    .{ "~", "\xC3\x01" },
    .{ ":", "\xC4\x01" },
    .{ ";", "\xC5\x01" },
    .{ "♠", "\xC6\x01" },
    .{ "♣", "\xC7\x01" },
    .{ "♥", "\xC8\x01" },
    .{ "♦", "\xC9\x01" },
    .{ "★", "\xCA\x01" },
    .{ "◎", "\xCB\x01" },
    .{ "○", "\xCC\x01" },
    .{ "□", "\xCD\x01" },
    .{ "△", "\xCE\x01" },
    .{ "◇", "\xCF\x01" },
    .{ "@", "\xD0\x01" },
    .{ "♪", "\xD1\x01" },
    .{ "%", "\xD2\x01" },
    .{ "☀", "\xD3\x01" },
    .{ "☁", "\xD4\x01" },
    .{ "☂", "\xD5\x01" },
    .{ "☃", "\xD6\x01" },
    .{ "\\x01D7", "\xD7\x01" },
    .{ "\\x01D8", "\xD8\x01" },
    .{ "\\x01D9", "\xD9\x01" },
    .{ "\\x01DA", "\xDA\x01" },
    .{ "⤴", "\xDB\x01" },
    .{ "⤵", "\xDC\x01" },
    .{ "\\x01DD", "\xDD\x01" },
    .{ " ", "\xDE\x01" },
    .{ "\\x01DF", "\xDF\x01" },
    .{ "[PK]", "\xE0\x01" },
    .{ "[MN]", "\xE1\x01" },
    .{ "가", "\x01\x04" },
    .{ "갈", "\x05\x04" },
    .{ "갑", "\x09\x04" },
    .{ "강", "\x0D\x04" },
    .{ "개", "\x13\x04" },
    .{ "갱", "\x1B\x04" },
    .{ "갸", "\x1C\x04" },
    .{ "거", "\x25\x04" },
    .{ "검", "\x2B\x04" },
    .{ "게", "\x34\x04" },
    .{ "겔", "\x36\x04" },
    .{ "겟", "\x39\x04" },
    .{ "고", "\x4D\x04" },
    .{ "곤", "\x4F\x04" },
    .{ "골", "\x51\x04" },
    .{ "곰", "\x55\x04" },
    .{ "공", "\x58\x04" },
    .{ "광", "\x62\x04" },
    .{ "괴", "\x69\x04" },
    .{ "구", "\x76\x04" },
    .{ "군", "\x78\x04" },
    .{ "굴", "\x7A\x04" },
    .{ "귀", "\x8B\x04" },
    .{ "그", "\x95\x04" },
    .{ "근", "\x97\x04" },
    .{ "글", "\x99\x04" },
    .{ "기", "\xA0\x04" },
    .{ "깅", "\xA9\x04" },
    .{ "까", "\xAC\x04" },
    .{ "깍", "\xAD\x04" },
    .{ "깜", "\xB2\x04" },
    .{ "깝", "\xB3\x04" },
    .{ "깨", "\xB8\x04" },
    .{ "꺽", "\xC5\x04" },
    .{ "껍", "\xCA\x04" },
    .{ "꼬", "\xDB\x04" },
    .{ "꼴", "\xDF\x04" },
    .{ "꽃", "\xE5\x04" },
    .{ "꾸", "\xF5\x04" },
    .{ "꿀", "\xF8\x04" },
    .{ "나", "\x24\x05" },
    .{ "날", "\x29\x05" },
    .{ "내", "\x35\x05" },
    .{ "냄", "\x39\x05" },
    .{ "냥", "\x43\x05" },
    .{ "너", "\x44\x05" },
    .{ "네", "\x51\x05" },
    .{ "노", "\x65\x05" },
    .{ "놈", "\x6A\x05" },
    .{ "농", "\x6D\x05" },
    .{ "뇽", "\x80\x05" },
    .{ "누", "\x81\x05" },
    .{ "눈", "\x83\x05" },
    .{ "느", "\x98\x05" },
    .{ "늪", "\xA3\x05" },
    .{ "니", "\xA7\x05" },
    .{ "다", "\xB1\x05" },
    .{ "닥", "\xB2\x05" },
    .{ "단", "\xB4\x05" },
    .{ "담", "\xBB\x05" },
    .{ "대", "\xC3\x05" },
    .{ "더", "\xCD\x05" },
    .{ "덕", "\xCE\x05" },
    .{ "덩", "\xD8\x05" },
    .{ "데", "\xDB\x05" },
    .{ "델", "\xDE\x05" },
    .{ "도", "\xEB\x05" },
    .{ "독", "\xEC\x05" },
    .{ "돈", "\xED\x05" },
    .{ "돌", "\xEF\x05" },
    .{ "동", "\xF5\x05" },
    .{ "두", "\x04\x06" },
    .{ "둔", "\x06\x06" },
    .{ "둠", "\x08\x06" },
    .{ "둥", "\x0B\x06" },
    .{ "드", "\x1B\x06" },
    .{ "들", "\x1F\x06" },
    .{ "디", "\x26\x06" },
    .{ "딘", "\x28\x06" },
    .{ "딜", "\x2A\x06" },
    .{ "딥", "\x2C\x06" },
    .{ "딱", "\x32\x06" },
    .{ "딸", "\x34\x06" },
    .{ "또", "\x5B\x06" },
    .{ "뚜", "\x65\x06" },
    .{ "뚝", "\x66\x06" },
    .{ "뚤", "\x68\x06" },
    .{ "라", "\x87\x06" },
    .{ "락", "\x88\x06" },
    .{ "란", "\x89\x06" },
    .{ "랄", "\x8A\x06" },
    .{ "랑", "\x8F\x06" },
    .{ "래", "\x93\x06" },
    .{ "랜", "\x95\x06" },
    .{ "램", "\x97\x06" },
    .{ "랩", "\x98\x06" },
    .{ "러", "\xA1\x06" },
    .{ "럭", "\xA2\x06" },
    .{ "런", "\xA3\x06" },
    .{ "렁", "\xA9\x06" },
    .{ "레", "\xAB\x06" },
    .{ "렌", "\xAD\x06" },
    .{ "렛", "\xB1\x06" },
    .{ "력", "\xB4\x06" },
    .{ "로", "\xC0\x06" },
    .{ "록", "\xC1\x06" },
    .{ "롤", "\xC3\x06" },
    .{ "롭", "\xC5\x06" },
    .{ "롱", "\xC7\x06" },
    .{ "룡", "\xD8\x06" },
    .{ "루", "\xD9\x06" },
    .{ "룸", "\xDD\x06" },
    .{ "륙", "\xEC\x06" },
    .{ "르", "\xF3\x06" },
    .{ "리", "\xFE\x06" },
    .{ "린", "\x00\x07" },
    .{ "릴", "\x01\x07" },
    .{ "림", "\x02\x07" },
    .{ "링", "\x05\x07" },
    .{ "마", "\x06\x07" },
    .{ "만", "\x08\x07" },
    .{ "말", "\x0B\x07" },
    .{ "맘", "\x0E\x07" },
    .{ "망", "\x11\x07" },
    .{ "매", "\x15\x07" },
    .{ "맨", "\x17\x07" },
    .{ "먹", "\x24\x07" },
    .{ "메", "\x2E\x07" },
    .{ "모", "\x40\x07" },
    .{ "몬", "\x43\x07" },
    .{ "몽", "\x49\x07" },
    .{ "무", "\x59\x07" },
    .{ "물", "\x5E\x07" },
    .{ "뭉", "\x64\x07" },
    .{ "뮤", "\x70\x07" },
    .{ "미", "\x7A\x07" },
    .{ "밀", "\x7E\x07" },
    .{ "바", "\x87\x07" },
    .{ "발", "\x8D\x07" },
    .{ "밤", "\x91\x07" },
    .{ "방", "\x94\x07" },
    .{ "배", "\x96\x07" },
    .{ "뱃", "\x9C\x07" },
    .{ "버", "\xA4\x07" },
    .{ "벅", "\xA5\x07" },
    .{ "번", "\xA6\x07" },
    .{ "범", "\xAA\x07" },
    .{ "베", "\xAF\x07" },
    .{ "벨", "\xB3\x07" },
    .{ "별", "\xBC\x07" },
    .{ "보", "\xC4\x07" },
    .{ "복", "\xC5\x07" },
    .{ "볼", "\xC8\x07" },
    .{ "부", "\xDA\x07" },
    .{ "북", "\xDB\x07" },
    .{ "분", "\xDC\x07" },
    .{ "불", "\xDE\x07" },
    .{ "붐", "\xE1\x07" },
    .{ "붕", "\xE4\x07" },
    .{ "뷰", "\xF0\x07" },
    .{ "브", "\xF6\x07" },
    .{ "블", "\xF9\x07" },
    .{ "비", "\xFD\x07" },
    .{ "빈", "\xFF\x07" },
    .{ "빌", "\x00\x08" },
    .{ "뻐", "\x1F\x08" },
    .{ "뽀", "\x31\x08" },
    .{ "뿌", "\x3B\x08" },
    .{ "뿔", "\x3E\x08" },
    .{ "뿡", "\x41\x08" },
    .{ "쁘", "\x44\x08" },
    .{ "삐", "\x49\x08" },
    .{ "사", "\x51\x08" },
    .{ "산", "\x54\x08" },
    .{ "삼", "\x59\x08" },
    .{ "상", "\x5D\x08" },
    .{ "새", "\x5F\x08" },
    .{ "색", "\x60\x08" },
    .{ "샤", "\x68\x08" },
    .{ "선", "\x79\x08" },
    .{ "설", "\x7B\x08" },
    .{ "섯", "\x80\x08" },
    .{ "성", "\x82\x08" },
    .{ "세", "\x84\x08" },
    .{ "섹", "\x85\x08" },
    .{ "셀", "\x87\x08" },
    .{ "소", "\x9A\x08" },
    .{ "손", "\x9D\x08" },
    .{ "솔", "\x9E\x08" },
    .{ "솜", "\xA0\x08" },
    .{ "송", "\xA3\x08" },
    .{ "수", "\xBE\x08" },
    .{ "술", "\xC2\x08" },
    .{ "숭", "\xC6\x08" },
    .{ "쉐", "\xCC\x08" },
    .{ "쉘", "\xCF\x08" },
    .{ "슈", "\xDA\x08" },
    .{ "스", "\xE0\x08" },
    .{ "슬", "\xE3\x08" },
    .{ "시", "\xE9\x08" },
    .{ "식", "\xEA\x08" },
    .{ "신", "\xEB\x08" },
    .{ "실", "\xED\x08" },
    .{ "쌩", "\x05\x09" },
    .{ "썬", "\x09\x09" },
    .{ "쏘", "\x14\x09" },
    .{ "쓰", "\x36\x09" },
    .{ "씨", "\x42\x09" },
    .{ "아", "\x4A\x09" },
    .{ "안", "\x4C\x09" },
    .{ "알", "\x4F\x09" },
    .{ "암", "\x53\x09" },
    .{ "애", "\x5A\x09" },
    .{ "앤", "\x5C\x09" },
    .{ "앱", "\x5F\x09" },
    .{ "야", "\x63\x09" },
    .{ "어", "\x72\x09" },
    .{ "얼", "\x77\x09" },
    .{ "엉", "\x7F\x09" },
    .{ "에", "\x83\x09" },
    .{ "엘", "\x86\x09" },
    .{ "엠", "\x87\x09" },
    .{ "여", "\x8B\x09" },
    .{ "연", "\x8E\x09" },
    .{ "염", "\x92\x09" },
    .{ "영", "\x97\x09" },
    .{ "오", "\xA2\x09" },
    .{ "온", "\xA4\x09" },
    .{ "옹", "\xAD\x09" },
    .{ "와", "\xAF\x09" },
    .{ "왈", "\xB2\x09" },
    .{ "왕", "\xB7\x09" },
    .{ "요", "\xC6\x09" },
    .{ "용", "\xCD\x09" },
    .{ "우", "\xCE\x09" },
    .{ "울", "\xD1\x09" },
    .{ "움", "\xD4\x09" },
    .{ "원", "\xDA\x09" },
    .{ "윈", "\xE9\x09" },
    .{ "유", "\xEF\x09" },
    .{ "육", "\xF0\x09" },
    .{ "윤", "\xF1\x09" },
    .{ "을", "\xFB\x09" },
    .{ "음", "\xFD\x09" },
    .{ "이", "\x0C\x0A" },
    .{ "인", "\x0E\x0A" },
    .{ "일", "\x0F\x0A" },
    .{ "임", "\x13\x0A" },
    .{ "입", "\x14\x0A" },
    .{ "잉", "\x17\x0A" },
    .{ "잎", "\x19\x0A" },
    .{ "자", "\x1A\x0A" },
    .{ "잠", "\x21\x0A" },
    .{ "장", "\x25\x0A" },
    .{ "재", "\x27\x0A" },
    .{ "쟈", "\x30\x0A" },
    .{ "쟝", "\x36\x0A" },
    .{ "저", "\x3A\x0A" },
    .{ "전", "\x3C\x0A" },
    .{ "점", "\x3F\x0A" },
    .{ "제", "\x44\x0A" },
    .{ "젤", "\x47\x0A" },
    .{ "져", "\x4C\x0A" },
    .{ "조", "\x54\x0A" },
    .{ "죤", "\x72\x0A" },
    .{ "주", "\x74\x0A" },
    .{ "중", "\x7D\x0A" },
    .{ "쥬", "\x88\x0A" },
    .{ "즈", "\x8C\x0A" },
    .{ "지", "\x94\x0A" },
    .{ "직", "\x95\x0A" },
    .{ "진", "\x96\x0A" },
    .{ "질", "\x98\x0A" },
    .{ "짱", "\xAB\x0A" },
    .{ "찌", "\xEA\x0A" },
    .{ "차", "\xF3\x0A" },
    .{ "참", "\xF8\x0A" },
    .{ "챙", "\x06\x0B" },
    .{ "챠", "\x07\x0B" },
    .{ "철", "\x10\x0B" },
    .{ "체", "\x16\x0B" },
    .{ "초", "\x24\x0B" },
    .{ "총", "\x2B\x0B" },
    .{ "쵸", "\x37\x0B" },
    .{ "충", "\x40\x0B" },
    .{ "츄", "\x4C\x0B" },
    .{ "츠", "\x51\x0B" },
    .{ "치", "\x59\x0B" },
    .{ "칠", "\x5D\x0B" },
    .{ "침", "\x5F\x0B" },
    .{ "카", "\x63\x0B" },
    .{ "칸", "\x65\x0B" },
    .{ "캐", "\x6B\x0B" },
    .{ "캥", "\x73\x0B" },
    .{ "컹", "\x80\x0B" },
    .{ "케", "\x81\x0B" },
    .{ "켄", "\x83\x0B" },
    .{ "켈", "\x84\x0B" },
    .{ "코", "\x92\x0B" },
    .{ "콘", "\x94\x0B" },
    .{ "콜", "\x95\x0B" },
    .{ "쿠", "\xA5\x0B" },
    .{ "쿤", "\xA7\x0B" },
    .{ "퀸", "\xB5\x0B" },
    .{ "크", "\xBF\x0B" },
    .{ "키", "\xC6\x0B" },
    .{ "킬", "\xC9\x0B" },
    .{ "킹", "\xCD\x0B" },
    .{ "타", "\xCE\x0B" },
    .{ "탁", "\xCF\x0B" },
    .{ "탕", "\xD7\x0B" },
    .{ "태", "\xD8\x0B" },
    .{ "탱", "\xE0\x0B" },
    .{ "터", "\xE3\x0B" },
    .{ "턴", "\xE5\x0B" },
    .{ "텀", "\xE8\x0B" },
    .{ "텅", "\xEC\x0B" },
    .{ "테", "\xED\x0B" },
    .{ "토", "\xFA\x0B" },
    .{ "톡", "\xFB\x0B" },
    .{ "톤", "\xFC\x0B" },
    .{ "톱", "\xFF\x0B" },
    .{ "통", "\x01\x0C" },
    .{ "투", "\x0B\x0C" },
    .{ "트", "\x22\x0C" },
    .{ "틈", "\x28\x0C" },
    .{ "티", "\x30\x0C" },
    .{ "틱", "\x31\x0C" },
    .{ "틸", "\x33\x0C" },
    .{ "파", "\x38\x0C" },
    .{ "팜", "\x3E\x0C" },
    .{ "팡", "\x42\x0C" },
    .{ "패", "\x44\x0C" },
    .{ "팬", "\x46\x0C" },
    .{ "팽", "\x4C\x0C" },
    .{ "퍼", "\x4F\x0C" },
    .{ "퍽", "\x50\x0C" },
    .{ "펄", "\x52\x0C" },
    .{ "페", "\x58\x0C" },
    .{ "펫", "\x5E\x0C" },
    .{ "포", "\x6B\x0C" },
    .{ "폭", "\x6C\x0C" },
    .{ "폴", "\x6E\x0C" },
    .{ "퐁", "\x72\x0C" },
    .{ "푸", "\x7C\x0C" },
    .{ "풀", "\x80\x0C" },
    .{ "풍", "\x85\x0C" },
    .{ "프", "\x93\x0C" },
    .{ "플", "\x95\x0C" },
    .{ "피", "\x99\x0C" },
    .{ "픽", "\x9A\x0C" },
    .{ "핑", "\xA0\x0C" },
    .{ "하", "\xA1\x0C" },
    .{ "한", "\xA3\x0C" },
    .{ "핫", "\xA8\x0C" },
    .{ "해", "\xAA\x0C" },
    .{ "핸", "\xAC\x0C" },
    .{ "헌", "\xB7\x0C" },
    .{ "헤", "\xBE\x0C" },
    .{ "헬", "\xC1\x0C" },
    .{ "형", "\xCE\x0C" },
    .{ "호", "\xD3\x0C" },
    .{ "홍", "\xDB\x0C" },
    .{ "화", "\xDD\x0C" },
    .{ "후", "\xF4\x0C" },
    .{ "흉", "\x14\x0D" },
    .{ "흔", "\x17\x0D" },
    .{ "히", "\x27\x0D" },
    .{ "각", "\x02\x04" },
    .{ "간", "\x03\x04" },
    .{ "감", "\x08\x04" },
    .{ "갚", "\x11\x04" },
    .{ "객", "\x14\x04" },
    .{ "걸", "\x29\x04" },
    .{ "겁", "\x2C\x04" },
    .{ "격", "\x3D\x04" },
    .{ "결", "\x41\x04" },
    .{ "경", "\x46\x04" },
    .{ "관", "\x5C\x04" },
    .{ "교", "\x71\x04" },
    .{ "굳", "\x79\x04" },
    .{ "권", "\x85\x04" },
    .{ "금", "\x9B\x04" },
    .{ "길", "\xA4\x04" },
    .{ "김", "\xA6\x04" },
    .{ "깃", "\xA8\x04" },
    .{ "껏", "\xCB\x04" },
    .{ "꿈", "\xFA\x04" },
    .{ "꿔", "\xFF\x04" },
    .{ "꿰", "\x03\x05" },
    .{ "끼", "\x1C\x05" },
    .{ "난", "\x27\x05" },
    .{ "낳", "\x34\x05" },
    .{ "냉", "\x3D\x05" },
    .{ "널", "\x48\x05" },
    .{ "넷", "\x57\x05" },
    .{ "념", "\x5E\x05" },
    .{ "녹", "\x66\x05" },
    .{ "논", "\x67\x05" },
    .{ "놀", "\x68\x05" },
    .{ "는", "\x9A\x05" },
    .{ "늘", "\x9B\x05" },
    .{ "닉", "\xA8\x05" },
    .{ "달", "\xB6\x05" },
    .{ "당", "\xBF\x05" },
    .{ "댄", "\xC5\x05" },
    .{ "던", "\xD0\x05" },
    .{ "둑", "\x05\x06" },
    .{ "뒀", "\x0D\x06" },
    .{ "등", "\x24\x06" },
    .{ "딧", "\x2D\x06" },
    .{ "따", "\x31\x06" },
    .{ "땅", "\x39\x06" },
    .{ "때", "\x3B\x06" },
    .{ "떨", "\x47\x06" },
    .{ "뚫", "\x69\x06" },
    .{ "뛰", "\x6D\x06" },
    .{ "람", "\x8B\x06" },
    .{ "렉", "\xAC\x06" },
    .{ "려", "\xB3\x06" },
    .{ "령", "\xBB\x06" },
    .{ "례", "\xBC\x06" },
    .{ "료", "\xD3\x06" },
    .{ "류", "\xEB\x06" },
    .{ "름", "\xF7\x06" },
    .{ "릎", "\xFD\x06" },
    .{ "릭", "\xFF\x06" },
    .{ "릿", "\x04\x07" },
    .{ "막", "\x07\x07" },
    .{ "맹", "\x1D\x07" },
    .{ "머", "\x23\x07" },
    .{ "멀", "\x26\x07" },
    .{ "멍", "\x2B\x07" },
    .{ "멧", "\x34\x07" },
    .{ "면", "\x39\x07" },
    .{ "멸", "\x3A\x07" },
    .{ "명", "\x3D\x07" },
    .{ "목", "\x41\x07" },
    .{ "몸", "\x46\x07" },
    .{ "묵", "\x5A\x07" },
    .{ "묶", "\x5B\x07" },
    .{ "문", "\x5C\x07" },
    .{ "믹", "\x7B\x07" },
    .{ "민", "\x7C\x07" },
    .{ "박", "\x88\x07" },
    .{ "반", "\x8B\x07" },
    .{ "받", "\x8C\x07" },
    .{ "밟", "\x90\x07" },
    .{ "밥", "\x92\x07" },
    .{ "뱀", "\x9A\x07" },
    .{ "벌", "\xA8\x07" },
    .{ "법", "\xAB\x07" },
    .{ "벤", "\xB1\x07" },
    .{ "벽", "\xBA\x07" },
    .{ "변", "\xBB\x07" },
    .{ "본", "\xC7\x07" },
    .{ "봄", "\xC9\x07" },
    .{ "봉", "\xCC\x07" },
    .{ "빔", "\x02\x08" },
    .{ "빙", "\x05\x08" },
    .{ "빛", "\x07\x08" },
    .{ "뺨", "\x1E\x08" },
    .{ "뼈", "\x2A\x08" },
    .{ "뽐", "\x35\x08" },
    .{ "뿜", "\x3F\x08" },
    .{ "쁜", "\x45\x08" },
    .{ "살", "\x56\x08" },
    .{ "생", "\x67\x08" },
    .{ "섀", "\x70\x08" },
    .{ "서", "\x75\x08" },
    .{ "석", "\x76\x08" },
    .{ "속", "\x9B\x08" },
    .{ "쇼", "\xB6\x08" },
    .{ "숏", "\xBC\x08" },
    .{ "순", "\xC0\x08" },
    .{ "숟", "\xC1\x08" },
    .{ "숨", "\xC3\x08" },
    .{ "쉬", "\xD2\x08" },
    .{ "습", "\xE6\x08" },
    .{ "승", "\xE8\x08" },
    .{ "싫", "\xEE\x08" },
    .{ "심", "\xEF\x08" },
    .{ "싸", "\xF4\x08" },
    .{ "악", "\x4B\x09" },
    .{ "압", "\x54\x09" },
    .{ "앞", "\x59\x09" },
    .{ "액", "\x5B\x09" },
    .{ "앵", "\x62\x09" },
    .{ "양", "\x6B\x09" },
    .{ "억", "\x73\x09" },
    .{ "언", "\x74\x09" },
    .{ "엄", "\x7A\x09" },
    .{ "업", "\x7B\x09" },
    .{ "역", "\x8C\x09" },
    .{ "열", "\x8F\x09" },
    .{ "예", "\x9B\x09" },
    .{ "옥", "\xA3\x09" },
    .{ "운", "\xD0\x09" },
    .{ "웅", "\xD7\x09" },
    .{ "워", "\xD8\x09" },
    .{ "웨", "\xE0\x09" },
    .{ "웹", "\xE5\x09" },
    .{ "위", "\xE7\x09" },
    .{ "으", "\xF8\x09" },
    .{ "은", "\xFA\x09" },
    .{ "의", "\x07\x0A" },
    .{ "작", "\x1B\x0A" },
    .{ "잼", "\x2B\x0A" },
    .{ "쟁", "\x2F\x0A" },
    .{ "적", "\x3B\x0A" },
    .{ "절", "\x3D\x0A" },
    .{ "정", "\x42\x0A" },
    .{ "젠", "\x46\x0A" },
    .{ "젬", "\x48\x0A" },
    .{ "죽", "\x75\x0A" },
    .{ "쥐", "\x81\x0A" },
    .{ "즌", "\x8E\x0A" },
    .{ "집", "\x9B\x0A" },
    .{ "짓", "\x9C\x0A" },
    .{ "짖", "\x9E\x0A" },
    .{ "짜", "\xA1\x0A" },
    .{ "짝", "\xA2\x0A" },
    .{ "째", "\xAC\x0A" },
    .{ "쪼", "\xC5\x0A" },
    .{ "찍", "\xEB\x0A" },
    .{ "찝", "\xEF\x0A" },
    .{ "채", "\xFE\x0A" },
    .{ "챔", "\x02\x0B" },
    .{ "처", "\x0D\x0B" },
    .{ "천", "\x0F\x0B" },
    .{ "청", "\x15\x0B" },
    .{ "쳐", "\x1E\x0B" },
    .{ "촙", "\x29\x0B" },
    .{ "최", "\x30\x0B" },
    .{ "추", "\x39\x0B" },
    .{ "축", "\x3A\x0B" },
    .{ "출", "\x3C\x0B" },
    .{ "춤", "\x3D\x0B" },
    .{ "취", "\x45\x0B" },
    .{ "칼", "\x66\x0B" },
    .{ "커", "\x77\x0B" },
    .{ "컬", "\x7B\x0B" },
    .{ "컷", "\x7E\x0B" },
    .{ "콤", "\x96\x0B" },
    .{ "쾌", "\xA0\x0B" },
    .{ "퀴", "\xB3\x0B" },
    .{ "클", "\xC2\x0B" },
    .{ "킥", "\xC7\x0B" },
    .{ "탄", "\xD0\x0B" },
    .{ "탈", "\xD1\x0B" },
    .{ "탐", "\xD3\x0B" },
    .{ "택", "\xD9\x0B" },
    .{ "털", "\xE6\x0B" },
    .{ "텍", "\xEE\x0B" },
    .{ "텔", "\xF0\x0B" },
    .{ "톰", "\xFE\x0B" },
    .{ "튀", "\x16\x0C" },
    .{ "튜", "\x1D\x0C" },
    .{ "판", "\x3B\x0C" },
    .{ "팔", "\x3C\x0C" },
    .{ "팩", "\x45\x0C" },
    .{ "펀", "\x51\x0C" },
    .{ "펌", "\x53\x0C" },
    .{ "폰", "\x6D\x0C" },
    .{ "품", "\x82\x0C" },
    .{ "픔", "\x96\x0C" },
    .{ "핀", "\x9B\x0C" },
    .{ "필", "\x9C\x0C" },
    .{ "할", "\xA4\x0C" },
    .{ "핥", "\xA5\x0C" },
    .{ "함", "\xA6\x0C" },
    .{ "합", "\xA7\x0C" },
    .{ "항", "\xA9\x0C" },
    .{ "햄", "\xAE\x0C" },
    .{ "햇", "\xB0\x0C" },
    .{ "향", "\xB4\x0C" },
    .{ "혈", "\xC9\x0C" },
    .{ "혜", "\xCF\x0C" },
    .{ "혹", "\xD4\x0C" },
    .{ "혼", "\xD5\x0C" },
    .{ "홀", "\xD6\x0C" },
    .{ "환", "\xDF\x0C" },
    .{ "회", "\xE8\x0C" },
    .{ "효", "\xEF\x0C" },
    .{ "휘", "\x06\x0D" },
    .{ "휩", "\x0B\x0D" },
    .{ "흑", "\x16\x0D" },
    .{ "흙", "\x1B\x0D" },
    .{ "흡", "\x1D\x0D" },
    .{ "희", "\x21\x0D" },
    .{ "흰", "\x22\x0D" },
    .{ "힘", "\x2B\x0D" },
    .{ "갤", "\x16\x04" },
    .{ "건", "\x27\x04" },
    .{ "계", "\x48\x04" },
    .{ "과", "\x5A\x04" },
    .{ "굵", "\x7B\x04" },
    .{ "규", "\x92\x04" },
    .{ "급", "\x9C\x04" },
    .{ "깁", "\xA7\x04" },
    .{ "끈", "\x12\x05" },
    .{ "낚", "\x26\x05" },
    .{ "낡", "\x2A\x05" },
    .{ "남", "\x2C\x05" },
    .{ "능", "\xA1\x05" },
    .{ "닌", "\xA9\x05" },
    .{ "닷", "\xBD\x05" },
    .{ "뜨", "\x73\x06" },
    .{ "띠", "\x80\x06" },
    .{ "랭", "\x9B\x06" },
    .{ "뢰", "\xCC\x06" },
    .{ "룰", "\xDC\x06" },
    .{ "른", "\xF5\x06" },
    .{ "맛", "\x10\x07" },
    .{ "맞", "\x12\x07" },
    .{ "맥", "\x16\x07" },
    .{ "맵", "\x1A\x07" },
    .{ "멘", "\x30\x07" },
    .{ "멜", "\x31\x07" },
    .{ "멤", "\x32\x07" },
    .{ "백", "\x97\x07" },
    .{ "밴", "\x98\x07" },
    .{ "병", "\xC0\x07" },
    .{ "빨", "\x0B\x08" },
    .{ "샘", "\x63\x08" },
    .{ "셔", "\x8D\x08" },
    .{ "셜", "\x90\x08" },
    .{ "쇠", "\xB0\x08" },
    .{ "숙", "\xBF\x08" },
    .{ "숲", "\xC9\x08" },
    .{ "슝", "\xDF\x08" },
    .{ "싯", "\xF1\x08" },
    .{ "쐐", "\x21\x09" },
    .{ "않", "\x4E\x09" },
    .{ "약", "\x64\x09" },
    .{ "없", "\x7C\x09" },
    .{ "있", "\x16\x0A" },
    .{ "잔", "\x1C\x0A" },
    .{ "잘", "\x1F\x0A" },
    .{ "좋", "\x5F\x0A" },
    .{ "줄", "\x77\x0A" },
    .{ "징", "\x9D\x0A" },
    .{ "창", "\xFC\x0A" },
    .{ "첩", "\x12\x0B" },
    .{ "친", "\x5B\x0B" },
    .{ "캄", "\x67\x0B" },
    .{ "켓", "\x87\x0B" },
    .{ "퀵", "\xB4\x0B" },
    .{ "큰", "\xC1\x0B" },
    .{ "튼", "\x24\x0C" },
    .{ "틀", "\x26\x0C" },
    .{ "펙", "\x59\x0C" },
    .{ "펜", "\x5A\x0C" },
    .{ "편", "\x61\x0C" },
    .{ "평", "\x66\x0C" },
    .{ "표", "\x77\x0C" },
    .{ "푼", "\x7E\x0C" },
    .{ "학", "\xA2\x0C" },
    .{ "행", "\xB2\x0C" },
    .{ "허", "\xB5\x0C" },
    .{ "험", "\xBA\x0C" },
    .{ "활", "\xE0\x0C" },
    .{ "힐", "\x2A\x0D" },
    .{ "\n", "\x00\xE0" },
    .{ "\\p", "\xBC\x25" },
    .{ "\\l", "\xBD\x25" },
};

test "all" {
    try rom.encoding.testCharMap(&all, "HELLO WORLD", "\x32\x01\x2F\x01\x36\x01\x36\x01\x39\x01\xDE\x01\x41\x01\x39\x01\x3C\x01\x36\x01\x2E\x01");
}

pub fn encode(str: []const u8, out: []u8) !void {
    var fos = io.fixedBufferStream(out);
    try rom.encoding.encode(&all, 0, str, fos.outStream());
    try fos.outStream().writeAll("\xff\xff");
}

pub fn decode(str: []const u8, out_stream: var) !void {
    const end = mem.indexOf(u8, str, "\xff\xff") orelse str.len;
    try rom.encoding.encode(&all, 1, str[0..end], out_stream);
}

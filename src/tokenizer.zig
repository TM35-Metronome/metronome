const std = @import("std");

const debug = std.debug;
const mem = std.mem;

pub const Token = struct {
    id: Id,
    str: []const u8,

    pub const Id = enum {
        Invalid,
        Identifier,
        Integer,
        LBracket,
        RBracket,
        Equal,
        Dot,
    };

    pub fn init(id: Id, str: []const u8) Token {
        return Token{
            .id = id,
            .str = str,
        };
    }
};

pub fn next(str: []const u8) ?struct { token: Token, rest: []const u8 } {
    const Res = @typeOf(next).ReturnType.Child;
    const State = enum {
        Begin,
        Identifier,
        Integer,

        fn result(id: Token.Id, s: []const u8, start: usize, size: usize) Res {
            return Res{
                .token = Token{
                    .id = id,
                    .str = s[start..][0..size],
                },
                .rest = s[start + size..],
            };
        }
    };

    var state = State.Begin;
    var start: usize = 0;
    for (str) |c, i| switch (state) {
        State.Begin => switch (c) {
            '\t', ' ' => start += 1,
            'a' ... 'z', 'A' ... 'Z', '_' => state = State.Identifier,
            '0' ... '9' => state = State.Integer,
            '[' => return State.result(Token.Id.LBracket, str, start, 1),
            ']' => return State.result(Token.Id.RBracket, str, start, 1),
            '=' => return State.result(Token.Id.Equal, str, start, 1),
            '.' => return State.result(Token.Id.Dot, str, start, 1),
            '#' => return null,
            else => return State.result(Token.Id.Invalid, str, start, 1),
        },
        State.Identifier => switch (c) {
            'a' ... 'z','A' ... 'Z', '0' ... '9', '_' => {},
            else => return State.result(Token.Id.Identifier, str, start, i - start),
        },
        State.Integer => switch (c) {
            '0' ... '9' => {},
            else => return State.result(Token.Id.Integer, str, start, i - start),
        },
    };

    return switch (state) {
        State.Begin => null,
        State.Identifier => State.result(Token.Id.Identifier, str, start, str.len - start),
        State.Integer => State.result(Token.Id.Integer, str, start, str.len - start),
    };
}

fn testNext(str: []const u8, tokens: []const Token) void {
    var rest = str;
    for (tokens) |t1| {
        const res = next(rest) orelse unreachable;
        const t2 = res.token;
        rest = res.rest;
        debug.assert(t1.id == t2.id);
        debug.assert(mem.eql(u8, t1.str, t2.str));
    }

    if (next(rest)) |_| unreachable;
}

test "tokenizer.next" {
    testNext("  ", []Token{});
    testNext("#", []Token{});
    testNext("#11233114411##", []Token{});
    testNext("a", []Token{Token.init(Token.Id.Identifier, "a")});
    testNext("aA", []Token{Token.init(Token.Id.Identifier, "aA")});
    testNext("aA1", []Token{Token.init(Token.Id.Identifier, "aA1")});
    testNext("1", []Token{Token.init(Token.Id.Integer, "1")});
    testNext("01", []Token{Token.init(Token.Id.Integer, "01")});
    testNext("987654321", []Token{Token.init(Token.Id.Integer, "987654321")});
    testNext("[", []Token{Token.init(Token.Id.LBracket, "[")});
    testNext("]", []Token{Token.init(Token.Id.RBracket, "]")});
    testNext("=", []Token{Token.init(Token.Id.Equal, "=")});
    testNext(".", []Token{Token.init(Token.Id.Dot, ".")});
    testNext(",", []Token{Token.init(Token.Id.Invalid, ",")});
    testNext("a 1[]=.#15553234 2 sdsd t", []Token{
        Token.init(Token.Id.Identifier, "a"),
        Token.init(Token.Id.Integer, "1"),
        Token.init(Token.Id.LBracket, "["),
        Token.init(Token.Id.RBracket, "]"),
        Token.init(Token.Id.Equal, "="),
        Token.init(Token.Id.Dot, "."),
    });
}

const std = @import("std");

const debug = std.debug;
const fmt = std.fmt;
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
        Star,
        Equal,
        Dot,

        pub fn str(id: Id) []const u8 {
            return switch (id) {
                Id.Invalid => "Invalid",
                Id.Identifier => "Identifier",
                Id.Integer => "Integer",
                Id.LBracket => "[",
                Id.RBracket => "]",
                Id.Star => "*",
                Id.Equal => "=",
                Id.Dot => ".",
            };
        }
    };

    pub fn init(id: Id, str: []const u8) Token {
        return Token{
            .id = id,
            .str = str,
        };
    }

    pub fn index(tok: Token, src: []const u8) usize {
        const res = @ptrToInt(tok.str.ptr) - @ptrToInt(str.ptr);
        debug.assert(res <= src.len);
        return res;
    }
};

pub const Tokenizer = struct {
    str: []const u8,
    i: usize,

    pub fn init(str: []const u8) Tokenizer {
        return Tokenizer{
            .str = str,
            .i = 0,
        };
    }

    pub fn rest(tok: Tokenizer) []const u8 {
        return tok.str[tok.i..];
    }

    pub fn next(tok: *Tokenizer) ?Token {
        const State = enum {
            Begin,
            Identifier,
            Integer,
        };

        var state = State.Begin;
        var start: usize = tok.i;
        while (tok.i < tok.str.len) {
            const c = tok.str[tok.i];
            tok.i += 1;

            switch (state) {
                State.Begin => switch (c) {
                    '\t', ' ' => start += 1,
                    'a'...'z', 'A'...'Z', '_' => state = State.Identifier,
                    '0'...'9' => state = State.Integer,
                    '[' => return Token.init(Token.Id.LBracket, tok.str[start..tok.i]),
                    ']' => return Token.init(Token.Id.RBracket, tok.str[start..tok.i]),
                    '*' => return Token.init(Token.Id.Star, tok.str[start..tok.i]),
                    '=' => return Token.init(Token.Id.Equal, tok.str[start..tok.i]),
                    '.' => return Token.init(Token.Id.Dot, tok.str[start..tok.i]),
                    '#' => return null,
                    else => return Token.init(Token.Id.Invalid, tok.str[start..tok.i]),
                },
                State.Identifier => switch (c) {
                    'a'...'z', 'A'...'Z', '0'...'9', '_' => {},
                    else => {
                        tok.i -= 1;
                        return Token.init(Token.Id.Identifier, tok.str[start..tok.i]);
                    },
                },
                State.Integer => switch (c) {
                    '0'...'9' => {},
                    else => {
                        tok.i -= 1;
                        return Token.init(Token.Id.Integer, tok.str[start..tok.i]);
                    },
                },
            }
        }

        return switch (state) {
            State.Begin => null,
            State.Identifier => Token.init(Token.Id.Identifier, tok.str[start..tok.i]),
            State.Integer => Token.init(Token.Id.Integer, tok.str[start..tok.i]),
        };
    }
};

fn testTokenizer(str: []const u8, tokens: []const Token) void {
    var tok = Tokenizer.init(str);
    for (tokens) |t1| {
        const t2 = tok.next() orelse unreachable;
        debug.assert(t1.id == t2.id);
        debug.assert(mem.eql(u8, t1.str, t2.str));
    }

    if (tok.next()) |_| unreachable;
}

test "Tokenizer" {
    testTokenizer("  ", []Token{});
    testTokenizer("#", []Token{});
    testTokenizer("#11233114411##", []Token{});
    testTokenizer("a", []Token{Token.init(Token.Id.Identifier, "a")});
    testTokenizer("aA", []Token{Token.init(Token.Id.Identifier, "aA")});
    testTokenizer("aA1", []Token{Token.init(Token.Id.Identifier, "aA1")});
    testTokenizer("1", []Token{Token.init(Token.Id.Integer, "1")});
    testTokenizer("01", []Token{Token.init(Token.Id.Integer, "01")});
    testTokenizer("987654321", []Token{Token.init(Token.Id.Integer, "987654321")});
    testTokenizer("[", []Token{Token.init(Token.Id.LBracket, "[")});
    testTokenizer("]", []Token{Token.init(Token.Id.RBracket, "]")});
    testTokenizer("*", []Token{Token.init(Token.Id.Star, "*")});
    testTokenizer("=", []Token{Token.init(Token.Id.Equal, "=")});
    testTokenizer(".", []Token{Token.init(Token.Id.Dot, ".")});
    testTokenizer(",", []Token{Token.init(Token.Id.Invalid, ",")});
    testTokenizer("a 1[]=.#15553234 2 sdsd t", []Token{
        Token.init(Token.Id.Identifier, "a"),
        Token.init(Token.Id.Integer, "1"),
        Token.init(Token.Id.LBracket, "["),
        Token.init(Token.Id.RBracket, "]"),
        Token.init(Token.Id.Equal, "="),
        Token.init(Token.Id.Dot, "."),
    });
}

pub const Node = union(enum) {
    Field: Field,
    Index: Index,
    Value: Value,

    pub const Kind = @TagType(Node);

    pub const Field = struct {
        dot: Token,
        ident: Token,
    };

    pub const Index = struct {
        lbracket: Token,
        int: Token,
        rbracket: Token,
    };

    pub const Value = struct {
        equal: Token,
        str: []const u8,
    };

    pub fn first(node: Node) Token {
        return switch (node) {
            Node.Kind.Field => |field| field.dot,
            Node.Kind.Index => |index| index.lbracket,
            Node.Kind.Value => |value| value.equal,
        };
    }

    pub fn last(node: Node) Token {
        return switch (node) {
            Node.Kind.Field => |field| field.ident,
            Node.Kind.Index => |index| index.rbracket,
            Node.Kind.Value => |value| value.equal,
        };
    }
};

pub const Parser = struct {
    pub const Error = struct {
        expected: []const Token.Id,
        found: Token,
    };

    pub const Result = union(enum) {
        Ok: Node,
        Error: Error,

        pub fn ok(res: Node) Result {
            return Result{ .Ok = res };
        }

        pub fn err(found: Token, expected: []const Token.Id) Result {
            return Result{
                .Error = Error{
                    .expected = expected,
                    .found = found,
                },
            };
        }
    };

    const State = union(enum) {
        Line,
        Suffix,
        Field: Token,
        Index: Token,
        IndexEnd: [2]Token,
        Done,
    };

    tok: Tokenizer,
    state: State,

    pub fn init(tok: Tokenizer) Parser {
        return Parser{
            .tok = tok,
            .state = State.Line,
        };
    }

    pub fn next(par: *Parser) ?Result {
        var err_token = Token.init(Token.Id.Invalid, par.tok.rest());
        while (par.tok.next()) |token| {
            err_token = token;
            switch (par.state) {
                State.Line => switch (token.id) {
                    Token.Id.Identifier => {
                        par.state = State.Suffix;
                        return Result.ok(Node{
                            .Field = Node.Field{
                                .dot = Token.init(Token.Id.Dot, token.str[0..0]),
                                .ident = token,
                            },
                        });
                    },
                    else => break,
                },
                State.Suffix => switch (token.id) {
                    Token.Id.Dot => par.state = State{ .Field = token },
                    Token.Id.LBracket => par.state = State{ .Index = token },
                    Token.Id.Equal => {
                        par.state = State.Done;
                        return Result.ok(Node{
                            .Value = Node.Value{
                                .equal = token,
                                .str = par.tok.rest(),
                            },
                        });
                    },
                    else => break,
                },
                State.Field => |dot| switch (token.id) {
                    Token.Id.Identifier => {
                        par.state = State.Suffix;
                        return Result.ok(Node{
                            .Field = Node.Field{
                                .dot = dot,
                                .ident = token,
                            },
                        });
                    },
                    else => break,
                },
                State.Index => |lbracket| switch (token.id) {
                    Token.Id.Integer => par.state = State{ .IndexEnd = []Token{ lbracket, token } },
                    else => break,
                },
                State.IndexEnd => |tokens| switch (token.id) {
                    Token.Id.RBracket => {
                        par.state = State.Suffix;
                        return Result.ok(Node{
                            .Index = Node.Index{
                                .lbracket = tokens[0],
                                .int = tokens[1],
                                .rbracket = token,
                            },
                        });
                    },
                    else => break,
                },
                State.Done => break,
            }
        }

        return switch (par.state) {
            State.Suffix => Result.err(err_token, []Token.Id{
                Token.Id.Dot,
                Token.Id.LBracket,
                Token.Id.Equal,
            }),
            State.Field => Result.err(err_token, []Token.Id{Token.Id.Identifier}),
            State.Index => Result.err(err_token, []Token.Id{Token.Id.Integer}),
            State.IndexEnd => Result.err(err_token, []Token.Id{Token.Id.RBracket}),
            State.Done, State.Line => return null,
        };
    }
};

fn testParser(str: []const u8, nodes: []const Node) void {
    var parser = Parser.init(Tokenizer.init(str));
    for (nodes) |n1| {
        const res = parser.next().?;
        const n2 = res.Ok;
        switch (n1) {
            Node.Kind.Field => |f1| {
                const f2 = n2.Field;
                debug.assert(f1.ident.id == f2.ident.id);
                debug.assert(mem.eql(u8, f1.ident.str, f2.ident.str));
            },
            Node.Kind.Index => |in1| {
                const in2 = n2.Index;
                debug.assert(in1.lbracket.id == in2.lbracket.id);
                debug.assert(mem.eql(u8, in1.lbracket.str, in2.lbracket.str));
                debug.assert(in1.int.id == in2.int.id);
                debug.assert(mem.eql(u8, in1.int.str, in2.int.str));
                debug.assert(in1.rbracket.id == in2.rbracket.id);
                debug.assert(mem.eql(u8, in1.rbracket.str, in2.rbracket.str));
            },
            Node.Kind.Value => |v1| {
                const v2 = n2.Value;
                debug.assert(v1.equal.id == v2.equal.id);
                debug.assert(mem.eql(u8, v1.equal.str, v2.equal.str));
                debug.assert(mem.eql(u8, v1.str, v2.str));
            },
        }
    }

    if (parser.next()) |_| unreachable;
}

test "Parser" {
    testParser("", []Node{});
    testParser("   ", []Node{});
    testParser(" # This is a comment", []Node{});
    testParser("a=1", []Node{
        Node{
            .Field = Node.Field{
                .dot = Token.init(Token.Id.Dot, ""),
                .ident = Token.init(Token.Id.Identifier, "a"),
            },
        },
        Node{
            .Value = Node.Value{
                .equal = Token.init(Token.Id.Equal, "="),
                .str = "1",
            },
        },
    });
    testParser("a.b=1", []Node{
        Node{
            .Field = Node.Field{
                .dot = Token.init(Token.Id.Dot, ""),
                .ident = Token.init(Token.Id.Identifier, "a"),
            },
        },
        Node{
            .Field = Node.Field{
                .dot = Token.init(Token.Id.Dot, "."),
                .ident = Token.init(Token.Id.Identifier, "b"),
            },
        },
        Node{
            .Value = Node.Value{
                .equal = Token.init(Token.Id.Equal, "="),
                .str = "1",
            },
        },
    });
    testParser("a[1]=1", []Node{
        Node{
            .Field = Node.Field{
                .dot = Token.init(Token.Id.Dot, ""),
                .ident = Token.init(Token.Id.Identifier, "a"),
            },
        },
        Node{
            .Index = Node.Index{
                .lbracket = Token.init(Token.Id.LBracket, "["),
                .int = Token.init(Token.Id.Integer, "1"),
                .rbracket = Token.init(Token.Id.RBracket, "]"),
            },
        },
        Node{
            .Value = Node.Value{
                .equal = Token.init(Token.Id.Equal, "="),
                .str = "1",
            },
        },
    });
    testParser(" a [ 1 ] = 1", []Node{
        Node{
            .Field = Node.Field{
                .dot = Token.init(Token.Id.Dot, ""),
                .ident = Token.init(Token.Id.Identifier, "a"),
            },
        },
        Node{
            .Index = Node.Index{
                .lbracket = Token.init(Token.Id.LBracket, "["),
                .int = Token.init(Token.Id.Integer, "1"),
                .rbracket = Token.init(Token.Id.RBracket, "]"),
            },
        },
        Node{
            .Value = Node.Value{
                .equal = Token.init(Token.Id.Equal, "="),
                .str = " 1",
            },
        },
    });
}

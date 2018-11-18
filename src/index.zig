const parse = @import("parser.zig");
const tokenizer = @import("tokenizer.zig");

pub const Property = struct {
    access: []const Access,
    value: []const u8,
};

pub const Access = union(enum) {
    Field: []const u8,
    Index: usize,
};

pub const Pattern = union(enum) {
    Field: []const u8,
    FieldPattern: usize,
    Index: usize,
    IndexPattern: usize,
};

test "" {
    _ = parse;
    _ = tokenizer;
}

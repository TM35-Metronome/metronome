test {
    _ = encoding;
    _ = gba;
    _ = nds;
    _ = ptr;
}

pub const encoding = @import("rom/encoding.zig");
pub const gba = @import("rom/gba.zig");
pub const nds = @import("rom/nds.zig");
pub const ptr = @import("rom/ptr.zig");

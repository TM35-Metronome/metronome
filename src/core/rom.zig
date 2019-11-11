pub const gba = @import("rom/gba.zig");
pub const int = @import("rom/int.zig");
pub const nds = @import("rom/nds.zig");

test "" {
    _ = gba;
    _ = int;
    _ = nds;
}

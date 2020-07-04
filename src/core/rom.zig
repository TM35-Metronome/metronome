pub const encoding = @import("rom/encoding.zig");
pub const gba = @import("rom/gba.zig");
pub const int = @import("rom/int.zig");
pub const nds = @import("rom/nds.zig");
pub const ptr = @import("rom/ptr.zig");

test "" {
    @import("std").meta.refAllDecls(@This());
}

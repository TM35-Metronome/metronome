test {
    _ = common;
    _ = dummy;
    _ = Game;
    _ = gen3;
    _ = gen4;
    _ = gen5;
    _ = rom;
    _ = script;
}

pub const common = @import("core/common.zig");
pub const dummy = @import("core/dummy.zig");
pub const Game = @import("core/game.zig").Game;
pub const gen3 = @import("core/gen3.zig");
pub const gen4 = @import("core/gen4.zig");
pub const gen5 = @import("core/gen5.zig");
pub const rom = @import("core/rom.zig");
pub const script = @import("core/script.zig");

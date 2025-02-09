pub const all = []const Command{
    @import("cmd/randomize-trainers.zig").command,
};

const Command = @import("Command.zig");

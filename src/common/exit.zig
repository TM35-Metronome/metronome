pub fn allocErr(stream: anytype) u8 {
    return err(stream, "Allocation failed\n", .{});
}

pub fn stdoutErr(stream: anytype, errr: anyerror) u8 {
    return writeErr(stream, "<stdout>", errr);
}

pub fn stdinErr(stream: anytype, errr: anyerror) u8 {
    return readErr(stream, "<stdin>", errr);
}

pub fn writeErr(stream: anytype, file: []const u8, errr: anyerror) u8 {
    return err(stream, "failed to write data to '{}': {}\n", .{ file, errr });
}

pub fn readErr(stream: anytype, file: []const u8, errr: anyerror) u8 {
    return err(stream, "Failed to read data from '{}': {}\n", .{ file, errr });
}

pub fn randErr(stream: anytype, errr: anyerror) u8 {
    return err(stream, "Failed to randomize data: {}\n", .{errr});
}

pub fn openErr(stream: anytype, file_name: []const u8, errr: anyerror) u8 {
    return err(stream, "Unable to open '{}': {}\n", .{ file_name, errr });
}

pub fn createErr(stream: anytype, file_name: []const u8, errr: anyerror) u8 {
    return err(stream, "Could not create file '{}': {}\n", .{ file_name, errr });
}

pub fn makePathErr(stream: anytype, path_str: []const u8, errr: anyerror) u8 {
    return err(stream, "Failed to make path '{}': {}\n", .{ path_str, errr });
}

pub fn err(stream: anytype, comptime format_str: []const u8, args: anytype) u8 {
    stream.print(format_str, args) catch {};
    return 1;
}

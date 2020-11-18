pub fn allocErr(writer: anytype) u8 {
    return err(writer, "Allocation failed\n", .{});
}

pub fn stdoutErr(writer: anytype, errr: anyerror) u8 {
    return writeErr(writer, "<stdout>", errr);
}

pub fn stdinErr(writer: anytype, errr: anyerror) u8 {
    return readErr(writer, "<stdin>", errr);
}

pub fn writeErr(writer: anytype, file: []const u8, errr: anyerror) u8 {
    return err(writer, "failed to write data to '{}': {}\n", .{ file, errr });
}

pub fn readErr(writer: anytype, file: []const u8, errr: anyerror) u8 {
    return err(writer, "Failed to read data from '{}': {}\n", .{ file, errr });
}

pub fn randErr(writer: anytype, errr: anyerror) u8 {
    return err(writer, "Failed to randomize data: {}\n", .{errr});
}

pub fn openErr(writer: anytype, file_name: []const u8, errr: anyerror) u8 {
    return err(writer, "Unable to open '{}': {}\n", .{ file_name, errr });
}

pub fn createErr(writer: anytype, file_name: []const u8, errr: anyerror) u8 {
    return err(writer, "Could not create file '{}': {}\n", .{ file_name, errr });
}

pub fn makePathErr(writer: anytype, path_str: []const u8, errr: anyerror) u8 {
    return err(writer, "Failed to make path '{}': {}\n", .{ path_str, errr });
}

pub fn err(writer: anytype, comptime format_str: []const u8, args: anytype) u8 {
    writer.print(format_str, args) catch {};
    return 1;
}

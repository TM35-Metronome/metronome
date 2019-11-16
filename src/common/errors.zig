pub fn allocErr(stream: var) u8 {
    return err(stream, "Allocation failed\n");
}

pub fn writeErr(stream: var, file: []const u8, errr: anyerror) u8 {
    return err(stream, "Failed to write data to '{}': {}\n", file, errr);
}

pub fn readErr(stream: var, file: []const u8, errr: anyerror) u8 {
    return err(stream, "Failed to read data from '{}': {}\n", file, errr);
}

pub fn randErr(stream: var, errr: anyerror) u8 {
    return err(stream, "Failed to randomize data: {}\n", errr);
}

pub fn openErr(stream: var, file_name: []const u8, errr: anyerror) u8 {
    return err(stream, "Unable to open '{}': {}\n", file_name, errr);
}

pub fn createErr(stream: var, file_name: []const u8, errr: anyerror) u8 {
    return err(stream, "Could not create file '{}': {}\n", file_name, errr);
}

pub fn makePathErr(stream: var, path_str: []const u8, errr: anyerror) u8 {
    return err(stream, "Failed to make path '{}': {}\n", path_str, errr);
}

pub fn err(stream: var, comptime format_str: []const u8, args: ...) u8 {
    stream.print(format_str, args) catch {};
    return 1;
}

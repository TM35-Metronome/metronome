const std = @import("std");
const builtin = @import("builtin");

const debug = std.debug;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const os = std.os;
const testing = std.testing;

pub const algorithm = @import("algorithm.zig");
pub const bit = @import("bit.zig");
pub const escape = @import("escape.zig");
pub const format = @import("format.zig");

pub const readLine = @import("readline.zig").readLine;

test "" {
    _ = algorithm;
    _ = bit;
    _ = escape;
    _ = format;
    _ = readLine;
}

pub const StdIo = struct {
    in: fs.File.InStream,
    out: fs.File.OutStream,
    err: fs.File.OutStream,

    pub fn getBuffered(stdio: *StdIo) BufferedStdIo {
        return BufferedStdIo{
            .in = io.BufferedInStream(fs.File.ReadError).init(&stdio.in.stream),
            .out = io.BufferedOutStream(fs.File.WriteError).init(&stdio.out.stream),
            .err = io.BufferedOutStream(fs.File.WriteError).init(&stdio.err.stream),
        };
    }

    pub fn getStreams(stdio: *StdIo) StdIoStreams {
        return StdIoStreams{
            .in = &stdio.in.stream,
            .out = &stdio.out.stream,
            .err = &stdio.err.stream,
        };
    }
};

pub const BufferedStdIo = struct {
    in: io.BufferedInStream(fs.File.ReadError),
    out: io.BufferedOutStream(fs.File.WriteError),
    err: io.BufferedOutStream(fs.File.WriteError),

    pub fn getStreams(stdio: *BufferedStdIo) StdIoStreams {
        return StdIoStreams{
            .in = &stdio.in.stream,
            .out = &stdio.out.stream,
            .err = &stdio.err.stream,
        };
    }
};

pub const StdIoStreams = CustomStdIoStreams(fs.File.ReadError, fs.File.WriteError);
pub fn CustomStdIoStreams(comptime ReadError: type, comptime WriteError: type) type {
    return struct {
        in: *io.InStream(ReadError),
        out: *io.OutStream(WriteError),
        err: *io.OutStream(WriteError),
    };
}

pub fn getStdIo() !StdIo {
    return StdIo{
        .in = (try io.getStdIn()).inStream(),
        .out = (try io.getStdOut()).outStream(),
        .err = (try io.getStdErr()).outStream(),
    };
}

test "getStdIo" {
    var stdio = try getStdIo();
    var buf_stdio = stdio.getBuffered();
}

/// Given a slice and a pointer, returns the pointers index into the slice.
/// ptr has to point into slice.
pub fn indexOfPtr(comptime T: type, slice: []const T, ptr: *const T) usize {
    const start = @ptrToInt(slice.ptr);
    const item = @ptrToInt(ptr);
    const dist_from_start = item - start;
    const res = @divExact(dist_from_start, @sizeOf(T));
    debug.assert(res < slice.len);
    return res;
}

test "indexOfPtr" {
    const arr = "abcde";
    for (arr) |*item, i| {
        testing.expectEqual(i, indexOfPtr(u8, arr, item));
    }
}

pub fn StackArrayList(comptime size: usize, comptime T: type) type {
    return struct {
        items: [size]T = undefined,
        len: usize = 0,

        pub fn fromSlice(items: []const T) !@This() {
            if (size < items.len)
                return error.SliceToBig;

            var res: @This() = undefined;
            mem.copy(T, &res.items, items);
            res.len = items.len;
            return res;
        }

        pub fn toSlice(list: *@This()) []T {
            return list.items[0..list.len];
        }

        pub fn toSliceConst(list: *const @This()) []const T {
            return list.items[0..list.len];
        }
    };
}

pub const Path = StackArrayList(fs.MAX_PATH_BYTES, u8);

pub const path = struct {
    pub fn join(paths: []const []const u8) !Path {
        var res: Path = undefined;

        // FixedBufferAllocator + FailingAllocator are used here to ensure that a max
        // of MAX_PATH_BYTES is allocated, and that only one allocation occures. This
        // ensures that only a valid path has been allocated into res.
        var fba = heap.FixedBufferAllocator.init(&res.items);
        var failing = debug.FailingAllocator.init(&fba.allocator, math.maxInt(usize));
        const res_slice = try fs.path.join(&failing.allocator, paths);
        res.len = res_slice.len;
        debug.assert(failing.allocations == 1);

        return res;
    }

    pub fn resolve(paths: []const []const u8) !Path {
        var res: Path = undefined;

        // FixedBufferAllocator + FailingAllocator are used here to ensure that a max
        // of MAX_PATH_BYTES is allocated, and that only one allocation occures. This
        // ensures that only a valid path has been allocated into res.
        var fba = heap.FixedBufferAllocator.init(&res.items);
        var failing = debug.FailingAllocator.init(&fba.allocator, math.maxInt(usize));
        const res_slice = try fs.path.resolve(&failing.allocator, paths);
        res.len = res_slice.len;
        debug.assert(failing.allocations == 1);

        return res;
    }
};

pub const dir = struct {
    pub fn selfExeDir() !Path {
        var res: Path = undefined;
        const res_slice = try fs.selfExeDirPath(&res.items);
        res.len = res_slice.len;
        return res;
    }

    pub fn cwd() !Path {
        var res: Path = undefined;
        const res_slice = try os.getcwd(&res.items);
        res.len = res_slice.len;
        return res;
    }

    pub const DirError = error{NotAvailable};

    pub fn home() DirError!Path {
        switch (builtin.os) {
            .linux, .windows => return getEnvPath("HOME"),
            else => @compileError("Unsupported os"),
        }
    }

    pub fn cache() DirError!Path {
        switch (builtin.os) {
            .linux => return getEnvPathWithHomeFallback("XDG_CACHE_HOME", ".cache"),
            .windows => return knownFolder(&FOLDERID_LocalAppData),
            else => @compileError("Unsupported os"),
        }
    }

    pub fn config() DirError!Path {
        switch (builtin.os) {
            .linux => return getEnvPathWithHomeFallback("XDG_CONFIG_HOME", ".config"),
            .windows => return knownFolder(&FOLDERID_RoamingAppData),
            else => @compileError("Unsupported os"),
        }
    }

    pub fn audio() DirError!Path {
        switch (builtin.os) {
            .linux => return runXdgUserDirCommand("MUSIC"),
            .windows => return knownFolder(&FOLDERID_Music),
            else => @compileError("Unsupported os"),
        }
    }

    pub fn desktop() DirError!Path {
        switch (builtin.os) {
            .linux => return runXdgUserDirCommand("DESKTOP"),
            .windows => return knownFolder(&FOLDERID_Desktop),
            else => @compileError("Unsupported os"),
        }
    }

    pub fn documents() DirError!Path {
        switch (builtin.os) {
            .linux => return runXdgUserDirCommand("DOCUMENTS"),
            .windows => return knownFolder(&FOLDERID_Documents),
            else => @compileError("Unsupported os"),
        }
    }

    pub fn download() DirError!Path {
        switch (builtin.os) {
            .linux => return runXdgUserDirCommand("DOWNLOAD"),
            .windows => return knownFolder(&FOLDERID_Downloads),
            else => @compileError("Unsupported os"),
        }
    }

    pub fn pictures() DirError!Path {
        switch (builtin.os) {
            .linux => return runXdgUserDirCommand("PICTURES"),
            .windows => return knownFolder(&FOLDERID_Pictures),
            else => @compileError("Unsupported os"),
        }
    }

    pub fn public() DirError!Path {
        switch (builtin.os) {
            .linux => return runXdgUserDirCommand("PUBLICSHARE"),
            .windows => return knownFolder(&FOLDERID_Public),
            else => @compileError("Unsupported os"),
        }
    }

    pub fn templates() DirError!Path {
        switch (builtin.os) {
            .linux => return runXdgUserDirCommand("TEMPLATES"),
            .windows => return knownFolder(&FOLDERID_Templates),
            else => @compileError("Unsupported os"),
        }
    }

    pub fn videos() DirError!Path {
        switch (builtin.os) {
            .linux => return runXdgUserDirCommand("VIDEOS"),
            .windows => return knownFolder(&FOLDERID_Videos),
            else => @compileError("Unsupported os"),
        }
    }

    fn getEnvPathWithHomeFallback(key: []const u8, home_fallback: []const u8) DirError!Path {
        return getEnvPath(key) catch {
            const home_dir = try getEnvPath("HOME");
            return path.join([_][]const u8{ home_dir.toSliceConst(), home_fallback, "" }) catch return DirError.NotAvailable;
        };
    }

    fn getEnvPath(key: []const u8) DirError!Path {
        const env = os.getenv(key) orelse return DirError.NotAvailable;
        if (!fs.path.isAbsolute(env))
            return DirError.NotAvailable;

        return path.join([_][]const u8{ env, "" }) catch return DirError.NotAvailable;
    }

    fn runXdgUserDirCommand(key: []const u8) DirError!Path {
        var process_buf: [1024 * 1024]u8 = undefined;
        var fba = heap.FixedBufferAllocator.init(&process_buf);
        comptime debug.assert(@sizeOf(std.ChildProcess) <= process_buf.len);

        // std.ChildProcess.init current impl allocates ChildProcess and nothing else.
        // Therefore it should never fail, as long as the above assert doesn't trigger.
        // Remember to make sure that this assumetion is up to date with zigs std lib.
        const process = std.ChildProcess.init([_][]const u8{ "xdg-user-dir", key }, &fba.allocator) catch unreachable;
        defer process.deinit();
        process.stdin_behavior = .Ignore;
        process.stdout_behavior = .Pipe;
        process.stderr_behavior = .Ignore;

        process.spawn() catch return DirError.NotAvailable;
        errdefer _ = process.kill() catch undefined;

        const stdout_stream = &process.stdout.?.inStream().stream;
        var res: Path = undefined;
        res.len = stdout_stream.readFull(&res.items) catch return DirError.NotAvailable;

        const term = process.wait() catch return DirError.NotAvailable;
        if (term == .Exited and term.Exited != 0)
            return DirError.NotAvailable;
        if (term != .Exited)
            return DirError.NotAvailable;

        res.len -= 1; // Remove newline. Assumes that if xdg-user-dir succeeds. It'll always return something

        // Join result with nothing, so that we always get an ending seperator
        res = path.join([_][]const u8{ res.toSliceConst(), "" }) catch return DirError.NotAvailable;

        // It's not very useful if xdg-user-dir returns the home dir, so let's assume that
        // the dir is not available if that happends.
        const home_dir = home() catch Path{};
        if (mem.eql(u8, res.toSliceConst(), home_dir.toSliceConst()))
            return DirError.NotAvailable;

        return res;
    }

    const FOLDERID_LocalAppData = os.windows.GUID.parse("{F1B32785-6FBA-4FCF-9D55-7B8E7F157091}");
    const FOLDERID_RoamingAppData = os.windows.GUID.parse("{3EB685DB-65F9-4CF6-A03A-E3EF65729F3D}");
    const FOLDERID_Music = os.windows.GUID.parse("{4BD8D571-6D19-48D3-BE97-422220080E43}");
    const FOLDERID_Desktop = os.windows.GUID.parse("{B4BFCC3A-DB2C-424C-B029-7FE99A87C641}");
    const FOLDERID_Documents = os.windows.GUID.parse("{FDD39AD0-238F-46AF-ADB4-6C85480369C7}");
    const FOLDERID_Downloads = os.windows.GUID.parse("{374DE290-123F-4565-9164-39C4925E467B}");
    const FOLDERID_Pictures = os.windows.GUID.parse("{33E28130-4E1E-4676-835A-98395C3BC3BB}");
    const FOLDERID_Public = os.windows.GUID.parse("{DFDF76A2-C82A-4D63-906A-5644AC457385}");
    const FOLDERID_Templates = os.windows.GUID.parse("{A63293E8-664E-48DB-A079-DF759E0509F7}");
    const FOLDERID_Videos = os.windows.GUID.parse("{18989B1D-99B5-455B-841C-AB7C74E4DDFC}");

    fn knownFolder(id: *const os.windows.KNOWNFOLDERID) DirError!Path {
        var res_path: [*]os.windows.WCHAR = undefined;
        const err = os.windows.shell32.SHGetKnownFolderPath(id, 0, null, &res_path);
        if (err != os.windows.S_OK)
            return DirError.NotAvailable;

        defer os.windows.ole32.CoTaskMemFree(@ptrCast(*c_void, res_path));

        var buf: [fs.MAX_PATH_BYTES * 2]u8 = undefined;
        var fba = heap.FixedBufferAllocator.init(&buf);
        const utf8_path = std.unicode.utf16leToUtf8Alloc(&fba.allocator, mem.toSlice(u16, res_path)) catch return DirError.NotAvailable;

        // Join result with nothing, so that we always get an ending seperator
        return path.join([_][]const u8{ utf8_path, "" }) catch return DirError.NotAvailable;
    }
};

pub fn ToNonConstPointer(comptime T: type) type {
    var info = @typeInfo(T);
    info.Pointer.is_const = false;
    return @Type(info);
}

pub fn castAwayConst(ptr: anytype) ToNonConstPointer(@TypeOf(ptr)) {
    const T = @TypeOf(ptr);
    const info = @typeInfo(T).Pointer;
    switch (info.size) {
        .One,
        .Many,
        .C,
        => {
            const addr = @intFromPtr(ptr);
            return @ptrFromInt(addr);
        },
        .Slice => return castAwayConst(ptr.ptr)[0..ptr.len],
    }
}

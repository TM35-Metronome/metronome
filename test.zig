pub fn main() void {
    for ([]void{{}}**0xFF) |_, i|
        @import("std").debug.warn("{X}\n", usize(@import("std").math.maxInt(u7)));
}

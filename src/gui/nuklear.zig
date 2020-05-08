const builtin = @import("builtin");
const std = @import("std");

const c = @import("c.zig");

const debug = std.debug;
const math = std.math;
const mem = std.mem;

// Custom functions provided to nuklear
export fn zig_assert(ok: c_int) void {
    debug.assert(ok != 0);
}

export fn zig_memset(ptr: [*]u8, c0: u8, len: usize) void {
    mem.set(u8, ptr[0..len], c0);
}

export fn zig_memcopy(dst: [*]u8, src: [*]const u8, len: usize) [*]u8 {
    mem.copy(u8, dst[0..len], src[0..len]);
    return dst;
}

export fn zig_sqrt(value: f32) f32 {
    return math.sqrt(value);
}

export fn zig_sin(value: f32) f32 {
    return math.sin(value);
}

export fn zig_cos(value: f32) f32 {
    return math.cos(value);
}

// Custom
pub fn buttonInactive(ctx: *Context, text: []const u8) void {
    const old_button_style = ctx.style.button;
    ctx.style.button.normal = ctx.style.button.active;
    ctx.style.button.hover = ctx.style.button.active;
    ctx.style.button.active = ctx.style.button.active;
    ctx.style.button.text_background = ctx.style.button.text_active;
    ctx.style.button.text_normal = ctx.style.button.text_active;
    ctx.style.button.text_hover = ctx.style.button.text_active;
    ctx.style.button.text_active = ctx.style.button.text_active;
    _ = button(ctx, text);
    ctx.style.button = old_button_style;
}

pub fn buttonActivatable(ctx: *Context, text: []const u8, active: bool) bool {
    if (active) {
        return button(ctx, text);
    } else {
        buttonInactive(ctx, text);
        return false;
    }
}

pub fn nonPaddedGroupBegin(ctx: *Context, title: [*]const u8, flags: c.nk_flags) bool {
    const old = ctx.style.window;
    ctx.style.window.group_padding = vec2(0, 0);
    const is_showing = c.nk_group_begin(ctx, title, flags) != 0;
    ctx.style.window = old;

    return is_showing;
}

pub fn nonPaddedGroupEnd(ctx: *Context) void {
    const old = ctx.style.window;
    ctx.style.window.group_padding = vec2(0, 0);
    c.nk_group_end(ctx);
    ctx.style.window = old;
}

pub fn fontWidth(ctx: *Context, text: []const u8) f32 {
    const style_font = ctx.style.font;
    return style_font.*.width.?(style_font.*.userdata, 0, text.ptr, @intCast(c_int, text.len));
}

pub const Align = enum {
    left,
    right,
};

pub const no_button_clicked = math.maxInt(usize);

pub const Button = struct {
    text: []const u8,
    is_active: bool = true,
};

pub fn buttonWidth(ctx: *Context, text: []const u8) f32 {
    const style_button = ctx.style.button;
    return fontWidth(ctx, text) + style_button.border +
        (style_button.padding.x + style_button.rounding) * 2;
}

pub fn buttonsAutoWidth(ctx: *Context, alignment: Align, height: f32, buttons_: []const Button) usize {
    var biggest: f32 = 0;
    for (buttons_) |but|
        biggest = math.max(biggest, buttonWidth(ctx, but.text));

    return buttons(ctx, alignment, biggest, height, buttons_);
}

pub fn buttons(ctx: *Context, alignment: Align, width: f32, height: f32, buttons_: []const Button) usize {
    c.nk_layout_row_template_begin(ctx, height);
    if (alignment == .right)
        c.nk_layout_row_template_push_dynamic(ctx);

    for (buttons_) |_|
        c.nk_layout_row_template_push_static(ctx, width);

    if (alignment == .left)
        c.nk_layout_row_template_push_dynamic(ctx);
    c.nk_layout_row_template_end(ctx);

    if (alignment == .right)
        c.nk_label(ctx, "", c.NK_TEXT_LEFT);

    var res: usize = no_button_clicked;
    for (buttons_) |but, i| {
        if (buttonActivatable(ctx, but.text, but.is_active))
            res = i;
    }

    if (alignment == .left)
        c.nk_label(ctx, "", c.NK_TEXT_LEFT);

    return res;
}

pub const Context = c.nk_context;
pub const Rect = c.struct_nk_rect;
pub const Vec2 = c.struct_nk_vec2;
pub const Color = c.nk_color;

pub fn begin(ctx: *c.nk_context, title: [*]const u8, r: Rect, flags: c.nk_flags) bool {
    return c.nkBegin(ctx, title, &r, flags) != 0;
}

pub fn button(ctx: *Context, text: []const u8) bool {
    return c.nk_button_text(ctx, text.ptr, @intCast(c_int, text.len)) != 0;
}

pub fn rect(x: f32, y: f32, w: f32, h: f32) Rect {
    return Rect{ .x = x, .y = y, .w = w, .h = h };
}

pub fn vec2(x: f32, y: f32) Vec2 {
    return Vec2{ .x = x, .y = y };
}

pub fn rgba(r: u8, g: u8, b: u8, a: u8) Color {
    return Color{ .r = r, .g = g, .b = b, .a = a };
}

pub fn rgb(r: u8, g: u8, b: u8) Color {
    return rgba(r, g, b, 255);
}

const builtin = @import("builtin");
const std = @import("std");

pub const c = @cImport({
    @cInclude("impl.h");
});

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
pub const FileBrowser = @import("nuklear/file-browser.zig").FileBrowser;
pub const fileBrowser = @import("nuklear/file-browser.zig").fileBrowser;

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
    Left,
    Right,
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
    if (alignment == .Right)
        c.nk_layout_row_template_push_dynamic(ctx);

    for (buttons_) |_|
        c.nk_layout_row_template_push_static(ctx, width);

    if (alignment == .Left)
        c.nk_layout_row_template_push_dynamic(ctx);
    c.nk_layout_row_template_end(ctx);

    if (alignment == .Right)
        c.nk_label(ctx, c"", TEXT_LEFT);

    var res: usize = no_button_clicked;
    for (buttons_) |but, i| {
        if (buttonActivatable(ctx, but.text, but.is_active))
            res = i;
    }

    if (alignment == .Left)
        c.nk_label(ctx, c"", TEXT_LEFT);

    return res;
}

// Nuklear functions
pub const TEXT_ALIGN_LEFT = @enumToInt(c.NK_TEXT_ALIGN_LEFT);
pub const TEXT_ALIGN_CENTERED = @enumToInt(c.NK_TEXT_ALIGN_CENTERED);
pub const TEXT_ALIGN_RIGHT = @enumToInt(c.NK_TEXT_ALIGN_RIGHT);
pub const TEXT_ALIGN_TOP = @enumToInt(c.NK_TEXT_ALIGN_TOP);
pub const TEXT_ALIGN_MIDDLE = @enumToInt(c.NK_TEXT_ALIGN_MIDDLE);
pub const TEXT_ALIGN_BOTTOM = @enumToInt(c.NK_TEXT_ALIGN_BOTTOM);
pub const TEXT_LEFT = @enumToInt(c.NK_TEXT_LEFT);
pub const TEXT_CENTERED = @enumToInt(c.NK_TEXT_CENTERED);
pub const TEXT_RIGHT = @enumToInt(c.NK_TEXT_RIGHT);

pub const WINDOW_BORDER = @enumToInt(c.NK_WINDOW_BORDER);
pub const WINDOW_MOVABLE = @enumToInt(c.NK_WINDOW_MOVABLE);
pub const WINDOW_SCALABLE = @enumToInt(c.NK_WINDOW_SCALABLE);
pub const WINDOW_CLOSABLE = @enumToInt(c.NK_WINDOW_CLOSABLE);
pub const WINDOW_MINIMIZABLE = @enumToInt(c.NK_WINDOW_MINIMIZABLE);
pub const WINDOW_NO_SCROLLBAR = @enumToInt(c.NK_WINDOW_NO_SCROLLBAR);
pub const WINDOW_TITLE = @enumToInt(c.NK_WINDOW_TITLE);
pub const WINDOW_SCROLL_AUTO_HIDE = @enumToInt(c.NK_WINDOW_SCROLL_AUTO_HIDE);
pub const WINDOW_BACKGROUND = @enumToInt(c.NK_WINDOW_BACKGROUND);
pub const WINDOW_SCALE_LEFT = @enumToInt(c.NK_WINDOW_SCALE_LEFT);
pub const WINDOW_NO_INPUT = @enumToInt(c.NK_WINDOW_NO_INPUT);

pub const EDIT_DEFAULT = @enumToInt(c.NK_EDIT_DEFAULT);
pub const EDIT_READ_ONLY = @enumToInt(c.NK_EDIT_READ_ONLY);
pub const EDIT_AUTO_SELECT = @enumToInt(c.NK_EDIT_AUTO_SELECT);
pub const EDIT_SIG_ENTER = @enumToInt(c.NK_EDIT_SIG_ENTER);
pub const EDIT_ALLOW_TAB = @enumToInt(c.NK_EDIT_ALLOW_TAB);
pub const EDIT_NO_CURSOR = @enumToInt(c.NK_EDIT_NO_CURSOR);
pub const EDIT_SELECTABLE = @enumToInt(c.NK_EDIT_SELECTABLE);
pub const EDIT_CLIPBOARD = @enumToInt(c.NK_EDIT_CLIPBOARD);
pub const EDIT_CTRL_ENTER_NEWLINE = @enumToInt(c.NK_EDIT_CTRL_ENTER_NEWLINE);
pub const EDIT_NO_HORIZONTAL_SCROLL = @enumToInt(c.NK_EDIT_NO_HORIZONTAL_SCROLL);
pub const EDIT_ALWAYS_INSERT_MODE = @enumToInt(c.NK_EDIT_ALWAYS_INSERT_MODE);
pub const EDIT_MULTILINE = @enumToInt(c.NK_EDIT_MULTILINE);
pub const EDIT_GOTO_END_ON_ACTIVATE = @enumToInt(c.NK_EDIT_GOTO_END_ON_ACTIVATE);

pub const EDIT_SIMPLE = @enumToInt(c.NK_EDIT_SIMPLE);
pub const EDIT_FIELD = @enumToInt(c.NK_EDIT_FIELD);
pub const EDIT_BOX = @enumToInt(c.NK_EDIT_BOX);
pub const EDIT_EDITOR = @enumToInt(c.NK_EDIT_EDITOR);

pub const EDIT_ACTIVE = @enumToInt(c.NK_EDIT_ACTIVE);
pub const EDIT_INACTIVE = @enumToInt(c.NK_EDIT_INACTIVE);
pub const EDIT_ACTIVATED = @enumToInt(c.NK_EDIT_ACTIVATED);
pub const EDIT_DEACTIVATED = @enumToInt(c.NK_EDIT_DEACTIVATED);
pub const EDIT_COMMITED = @enumToInt(c.NK_EDIT_COMMITED);

pub const COLOR_TEXT = @enumToInt(c.NK_COLOR_TEXT);
pub const COLOR_WINDOW = @enumToInt(c.NK_COLOR_WINDOW);
pub const COLOR_HEADER = @enumToInt(c.NK_COLOR_HEADER);
pub const COLOR_BORDER = @enumToInt(c.NK_COLOR_BORDER);
pub const COLOR_BUTTON = @enumToInt(c.NK_COLOR_BUTTON);
pub const COLOR_BUTTON_HOVER = @enumToInt(c.NK_COLOR_BUTTON_HOVER);
pub const COLOR_BUTTON_ACTIVE = @enumToInt(c.NK_COLOR_BUTTON_ACTIVE);
pub const COLOR_TOGGLE = @enumToInt(c.NK_COLOR_TOGGLE);
pub const COLOR_TOGGLE_HOVER = @enumToInt(c.NK_COLOR_TOGGLE_HOVER);
pub const COLOR_TOGGLE_CURSOR = @enumToInt(c.NK_COLOR_TOGGLE_CURSOR);
pub const COLOR_SELECT = @enumToInt(c.NK_COLOR_SELECT);
pub const COLOR_SELECT_ACTIVE = @enumToInt(c.NK_COLOR_SELECT_ACTIVE);
pub const COLOR_SLIDER = @enumToInt(c.NK_COLOR_SLIDER);
pub const COLOR_SLIDER_CURSOR = @enumToInt(c.NK_COLOR_SLIDER_CURSOR);
pub const COLOR_SLIDER_CURSOR_HOVER = @enumToInt(c.NK_COLOR_SLIDER_CURSOR_HOVER);
pub const COLOR_SLIDER_CURSOR_ACTIVE = @enumToInt(c.NK_COLOR_SLIDER_CURSOR_ACTIVE);
pub const COLOR_PROPERTY = @enumToInt(c.NK_COLOR_PROPERTY);
pub const COLOR_EDIT = @enumToInt(c.NK_COLOR_EDIT);
pub const COLOR_EDIT_CURSOR = @enumToInt(c.NK_COLOR_EDIT_CURSOR);
pub const COLOR_COMBO = @enumToInt(c.NK_COLOR_COMBO);
pub const COLOR_CHART = @enumToInt(c.NK_COLOR_CHART);
pub const COLOR_CHART_COLOR = @enumToInt(c.NK_COLOR_CHART_COLOR);
pub const COLOR_CHART_COLOR_HIGHLIGHT = @enumToInt(c.NK_COLOR_CHART_COLOR_HIGHLIGHT);
pub const COLOR_SCROLLBAR = @enumToInt(c.NK_COLOR_SCROLLBAR);
pub const COLOR_SCROLLBAR_CURSOR = @enumToInt(c.NK_COLOR_SCROLLBAR_CURSOR);
pub const COLOR_SCROLLBAR_CURSOR_HOVER = @enumToInt(c.NK_COLOR_SCROLLBAR_CURSOR_HOVER);
pub const COLOR_SCROLLBAR_CURSOR_ACTIVE = @enumToInt(c.NK_COLOR_SCROLLBAR_CURSOR_ACTIVE);
pub const COLOR_TAB_HEADER = @enumToInt(c.NK_COLOR_TAB_HEADER);
pub const COLOR_COUNT = @enumToInt(c.NK_COLOR_COUNT);

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

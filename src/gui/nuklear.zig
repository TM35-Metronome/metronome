const builtin = @import("builtin");
const std = @import("std");

pub const c = @cImport(switch (builtin.os) {
    .linux => @cInclude("x11.h"),
    else => @compileError("Unsupported os"),
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

// Nuklear functions
pub const NK_TEXT_ALIGN_LEFT = @enumToInt(c.NK_TEXT_ALIGN_LEFT);
pub const NK_TEXT_ALIGN_CENTERED = @enumToInt(c.NK_TEXT_ALIGN_CENTERED);
pub const NK_TEXT_ALIGN_RIGHT = @enumToInt(c.NK_TEXT_ALIGN_RIGHT);
pub const NK_TEXT_ALIGN_TOP = @enumToInt(c.NK_TEXT_ALIGN_TOP);
pub const NK_TEXT_ALIGN_MIDDLE = @enumToInt(c.NK_TEXT_ALIGN_MIDDLE);
pub const NK_TEXT_ALIGN_BOTTOM = @enumToInt(c.NK_TEXT_ALIGN_BOTTOM);
pub const NK_TEXT_LEFT = @enumToInt(c.NK_TEXT_LEFT);
pub const NK_TEXT_CENTERED = @enumToInt(c.NK_TEXT_CENTERED);
pub const NK_TEXT_RIGHT = @enumToInt(c.NK_TEXT_RIGHT);

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

pub const Context = c.nk_context;

pub fn begin(ctx: *c.nk_context, title: [*]const u8, r: c.struct_nk_rect, flags: c.nk_flags) bool {
    return c.nkBegin(ctx, title, &r, flags) != 0;
}

pub fn rect(x: f32, y: f32, w: f32, h: f32) c.struct_nk_rect {
    return c.struct_nk_rect{ .x = x, .y = y, .w = w, .h = h };
}

pub fn vec2(x: f32, y: f32) c.struct_nk_vec2 {
    return c.struct_nk_vec2{ .x = x, .y = y };
}

pub fn rgba(r: u8, g: u8, b: u8, a: u8) c.nk_color {
    return c.nk_color{ .r = r, .g = g, .b = b, .a = a };
}

// Backend functions
pub fn create(window: Window, font: Window.Font) !*Context {
    switch (builtin.os) {
        .linux => {
            var attr: c.XWindowAttributes = undefined;
            _ = c.XGetWindowAttributes(window.display, window.window, &attr);

            return c.nk_xlib_init(
                font,
                window.display,
                window.screen,
                window.window,
                window.visual,
                window.colormap,
                @intCast(c_uint, attr.width),
                @intCast(c_uint, attr.height),
            ) orelse return error.CouldNotCreateContext;
        },
        else => @compileError("Unsupported os"),
    }
}

pub fn destroy(ctx: *Context, window: Window) void {
    switch (builtin.os) {
        .linux => c.nk_xlib_shutdown(),
        else => @compileError("Unsupported os"),
    }
}

pub fn isExitEvent(event: Window.Event) bool {
    switch (builtin.os) {
        .linux => return event.type == c.ClientMessage,
        else => @compileError("Unsupported os"),
    }
}

pub fn handleEvent(ctx: *Context, window: Window, event: Window.Event) void {
    switch (builtin.os) {
        .linux => {
            var evn = event;
            _ = c.nk_xlib_handle_event(window.display, window.screen, window.window, &evn);
        },
        else => @compileError("Unsupported os"),
    }
}

pub fn render(ctx: *Context, window: Window) void {
    switch (builtin.os) {
        .linux => {
            _ = c.XClearWindow(window.display, window.window);
            c.nkXlibRender(window.window, &c.nk_color{ .r = 0, .g = 0, .b = 0, .a = 0 });
            _ = c.XFlush(window.display);
        },
        else => @compileError("Unsupported os"),
    }
}

pub const Window = switch (builtin.os) {
    .linux => X11Window,
    else => @compileError("Unsupported os"),
};

pub const X11Window = struct {
    width: usize,
    height: usize,

    display: *c.Display,
    screen: c_int,
    visual: *c.Visual,
    colormap: c.Colormap,
    window: c.Window,

    pub const Font = *c.XFont;
    pub const Event = c.XEvent;

    pub fn create(width: usize, height: usize) !X11Window {
        const display = c.XOpenDisplay(null) orelse return error.CouldNotOpenDisplay;
        errdefer _ = c.XCloseDisplay(display);

        const root = c.defaultRootWindow(display);
        const screen = c.XDefaultScreen(display);
        const visual = c.XDefaultVisual(display, screen);
        const colormap = c.XCreateColormap(display, root, visual, c.AllocNone);
        errdefer _ = c.XFreeColormap(display, colormap);

        var set_w_attr = c.XSetWindowAttributes{
            .colormap = colormap,
            .event_mask = c.ExposureMask | c.KeyPressMask | c.KeyReleaseMask |
                c.ButtonPress | c.ButtonReleaseMask | c.ButtonMotionMask |
                c.Button1MotionMask | c.Button3MotionMask | c.Button4MotionMask | c.Button5MotionMask |
                c.PointerMotionMask | c.KeymapStateMask | c.StructureNotifyMask,
            .cursor = 0,
            .override_redirect = 0,
            .do_not_propagate_mask = 0,
            .save_under = 0,
            .backing_pixel = 0,
            .backing_planes = 0,
            .backing_store = 0,
            .win_gravity = 0,
            .bit_gravity = 0,
            .border_pixel = 0,
            .border_pixmap = 0,
            .background_pixel = 0,
            .background_pixmap = 0,
        };

        const window = c.XCreateWindow(
            display,
            root,
            0,
            0,
            @intCast(c_uint, width),
            @intCast(c_uint, height),
            0,
            c.XDefaultDepth(display, screen),
            c.InputOutput,
            visual,
            c.CWEventMask | c.CWColormap,
            &set_w_attr,
        );
        errdefer _ = c.XDestroyWindow(display, window);
        errdefer _ = c.XUnmapWindow(display, window);

        _ = c.XStoreName(display, window, c"X11");
        _ = c.XMapWindow(display, window);
        var delete_window = c.XInternAtom(display, c"WM_DELETE_WINDOW", c.False);
        _ = c.XSetWMProtocols(display, window, &delete_window, 1);

        var attr: c.XWindowAttributes = undefined;
        _ = c.XGetWindowAttributes(display, window, &attr);

        return X11Window{
            .width = @intCast(usize, attr.width),
            .height = @intCast(usize, attr.height),

            .display = display,
            .screen = screen,
            .visual = visual,
            .colormap = colormap,
            .window = window,
        };
    }

    pub fn destroy(window: X11Window) void {
        _ = c.XUnmapWindow(window.display, window.window);
        _ = c.XDestroyWindow(window.display, window.window);
        _ = c.XFreeColormap(window.display, window.colormap);
        _ = c.XCloseDisplay(window.display);
    }

    pub fn createFont(window: X11Window, name: [*]const u8) Font {
        return c.nk_xfont_create(window.display, name).?;
    }

    pub fn destroyFont(window: X11Window, font: Font) void {
        return c.nk_xfont_del(window.display, font);
    }

    pub fn nextEvent(window: *X11Window) ?Event {
        var event: Event = undefined;
        while (c.XPending(window.display) != 0) {
            _ = c.XNextEvent(window.display, &event);
            if (event.type == c.ClientMessage)
                return event;
            if (event.type == c.ConfigureNotify) {
                window.width = @intCast(usize, event.xconfigure.width);
                window.height = @intCast(usize, event.xconfigure.height);
            }
            if (c.XFilterEvent(&event, window.window) != 0)
                continue;

            return event;
        }

        return null;
    }
};

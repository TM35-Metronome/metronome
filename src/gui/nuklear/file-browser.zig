const std = @import("std");
const util = @import("util");

const nk = @import("../nuklear.zig");

const debug = std.debug;
const fs = std.fs;
const heap = std.heap;
const math = std.math;
const mem = std.mem;

const c = nk.c;

pub const FileBrowser = struct {
    allocator: *mem.Allocator,
    selected_file: util.Path = util.Path{},
    search_path: util.Path,
    curr_dir: util.Path,

    audio_dir: util.Path,
    cache_dir: util.Path,
    config_dir: util.Path,
    desktop_dir: util.Path,
    document_dir: util.Path,
    download_dir: util.Path,
    home_dir: util.Path,
    picture_dir: util.Path,
    public_dir: util.Path,
    template_dir: util.Path,
    video_dir: util.Path,

    entries: []Entry,
    last_selected_entry: usize = 0,
    mode: Mode,

    pub const Pressed = enum {
        Confirm,
        Cancel,
    };

    pub const Mode = enum {
        Save,
        OpenOne,
        OpenMany,
    };

    pub const Entry = struct {
        name: []const u8,
        kind: fs.Dir.Entry.Kind,
        selected: bool,
    };

    pub fn open(allocator: *mem.Allocator, mode: Mode, path: []const u8) !FileBrowser {
        var dir = try fs.Dir.open(allocator, path);
        defer dir.close();

        // Do a path.join here, so that curr_path will always look like a directory
        // (ending with '\\' or '/' depeding on platform).
        const dir_path = try util.path.join([_][]const u8{ path, "" });
        var entries = std.ArrayList(Entry).init(allocator);
        defer {
            for (entries.toSlice()) |entry|
                allocator.free(entry.name);
            entries.deinit();
        }

        while (try dir.next()) |entry| {
            const name = try mem.dupe(allocator, u8, entry.name);
            errdefer allocator.free(name);

            try entries.append(Entry{
                .name = name,
                .kind = entry.kind,
                .selected = false,
            });
        }

        return FileBrowser{
            .allocator = allocator,
            .search_path = dir_path,
            .curr_dir = dir_path,

            .audio_dir = util.dir.audio() catch util.Path{},
            .cache_dir = util.dir.cache() catch util.Path{},
            .config_dir = util.dir.config() catch util.Path{},
            .desktop_dir = util.dir.desktop() catch util.Path{},
            .document_dir = util.dir.documents() catch util.Path{},
            .download_dir = util.dir.download() catch util.Path{},
            .home_dir = util.dir.home() catch util.Path{},
            .picture_dir = util.dir.pictures() catch util.Path{},
            .public_dir = util.dir.public() catch util.Path{},
            .template_dir = util.dir.templates() catch util.Path{},
            .video_dir = util.dir.videos() catch util.Path{},

            .entries = entries.toOwnedSlice(),
            .mode = mode,
        };
    }

    pub fn close(browser: FileBrowser) void {
        const allocator = browser.allocator;
        for (browser.entries) |entry|
            allocator.free(entry.name);
        allocator.free(browser.entries);
    }
};

///
/// +------------------------------+
/// | file-name.txt                |
/// +------------------------------+
/// +-----------+ +----------------+
/// | Download  | | /path/to/      |
/// | Documents | +----------------+
/// | Home      | +----------------+
/// |           | | file.txt      ||
/// |           | | folder        "|
/// |           | | file2.obj     "|
/// +-----------+ +----------------+
///            +--------+ +--------+
///            | Cancel | |   Ok   |
///            +--------+ +--------+
///
pub fn fileBrowser(ctx: *c.nk_context, browser: *FileBrowser, height: f32) ?FileBrowser.Pressed {
    const border_group = nk.WINDOW_BORDER | nk.WINDOW_NO_SCROLLBAR;
    const layout = ctx.current.*.layout;
    const min_height = layout.*.row.min_height;

    const bar_edit_mode = nk.EDIT_SIMPLE | nk.EDIT_SIG_ENTER;
    const bar_height = ctx.style.edit.border * 2 +
        ctx.style.edit.padding.y * 2 +
        min_height;

    var res: ?FileBrowser.Pressed = null;
    if (browser.mode == .Save) {
        // +------------------------------+
        // | file-name.txt                |
        // +------------------------------+
        c.nk_layout_row_dynamic(ctx, bar_height, 1);
        if (c.nk_group_begin(ctx, c"file-browser-name-bar", border_group) != 0) {
            defer c.nk_group_end(ctx);
            c.nk_layout_row_dynamic(ctx, 0, 1);

            const flags = c.nk_edit_string(ctx, bar_edit_mode, &browser.selected_file.items, @ptrCast(*c_int, &browser.selected_file.len), browser.selected_file.items.len, c.nk_filter_default);
            if (flags & @intCast(c_uint, nk.EDIT_COMMITED) != 0) {
                res = .Confirm;
            }
        }
    }

    const used_up_space = ctx.style.window.padding.y * 2 +
        if (browser.mode == .Save) ctx.style.window.spacing.y + bar_height else 0;
    const ok_cancel_buttons_height = ctx.style.window.spacing.y +
        min_height;
    const below_file_name_height = height - (used_up_space + ok_cancel_buttons_height);
    c.nk_layout_row_template_begin(ctx, below_file_name_height);
    c.nk_layout_row_template_push_static(ctx, 250);
    c.nk_layout_row_template_push_dynamic(ctx);
    c.nk_layout_row_template_end(ctx);

    // +-----------+
    // | Download  |
    // | Documents |
    // | Home      |
    // |           |
    // |           |
    // |           |
    // +-----------+
    if (c.nk_group_begin(ctx, c"file-browser-explorer", border_group) != 0) {
        defer c.nk_group_end(ctx);
        c.nk_layout_row_dynamic(ctx, 0, 1);

        var clicked: ?util.Path = null;
        if (clickablePath(ctx, "Audio", browser.audio_dir, browser.curr_dir))
            clicked = browser.audio_dir;
        if (clickablePath(ctx, "Cache", browser.cache_dir, browser.curr_dir))
            clicked = browser.cache_dir;
        if (clickablePath(ctx, "Config", browser.config_dir, browser.curr_dir))
            clicked = browser.config_dir;
        if (clickablePath(ctx, "Documents", browser.document_dir, browser.curr_dir))
            clicked = browser.document_dir;
        if (clickablePath(ctx, "Download", browser.download_dir, browser.curr_dir))
            clicked = browser.download_dir;
        if (clickablePath(ctx, "Home", browser.home_dir, browser.curr_dir))
            clicked = browser.home_dir;
        if (clickablePath(ctx, "Pictures", browser.picture_dir, browser.curr_dir))
            clicked = browser.picture_dir;
        if (clickablePath(ctx, "Public", browser.public_dir, browser.curr_dir))
            clicked = browser.public_dir;
        if (clickablePath(ctx, "Template", browser.template_dir, browser.curr_dir))
            clicked = browser.template_dir;
        if (clickablePath(ctx, "Video", browser.video_dir, browser.curr_dir))
            clicked = browser.video_dir;

        if (clicked) |path| {
            if (FileBrowser.open(browser.allocator, browser.mode, path.toSliceConst())) |new_browser| {
                browser.close();
                browser.* = new_browser;
            } else |_| {}
        }
    }

    if (nk.nonPaddedGroupBegin(ctx, c"file-browser-explorer", nk.WINDOW_NO_SCROLLBAR)) {
        defer nk.nonPaddedGroupEnd(ctx);
        // +----------------+
        // | /path/to/      |
        // +----------------+
        c.nk_layout_row_dynamic(ctx, bar_height, 1);
        if (c.nk_group_begin(ctx, c"file-browser-search-bar", border_group) != 0) {
            defer c.nk_group_end(ctx);
            c.nk_layout_row_dynamic(ctx, 0, 1);

            const flags = c.nk_edit_string(ctx, bar_edit_mode, &browser.search_path.items, @ptrCast(*c_int, &browser.search_path.len), browser.search_path.items.len, c.nk_filter_default);
            if (flags & @intCast(c_uint, nk.EDIT_COMMITED) != 0) {
                if (FileBrowser.open(browser.allocator, browser.mode, browser.search_path.toSliceConst())) |new_browser| {
                    browser.close();
                    browser.* = new_browser;
                } else |_| if (fs.File.access(browser.search_path.toSliceConst())) {
                    res = .Confirm;
                } else |_| {}
            }
        }

        // +----------------+
        // | file.txt      ||
        // | folder        "|
        // | file2.obj     "|
        // +----------------+
        const used_up_space2 = ctx.style.window.spacing.y + bar_height;
        c.nk_layout_row_dynamic(ctx, below_file_name_height - used_up_space2, 1);

        // HACK: I don't want spacing between the items in my nk_list_view, but I cannot
        // remove the spacing outside the if (nk_list_view_begin), because that will also
        // remove the spacing between the list view and its neighbors.
        // The best solution I could come up with is to set the spacing to 0 inside, and
        // tell the list view that the items have a height of item_height - spacing.
        const old_spacing = ctx.style.window.spacing;

        var list_view: c.nk_list_view = undefined;
        if (c.nk_list_view_begin(ctx, &list_view, c"file-browser-files", nk.WINDOW_BORDER, @floatToInt(c_int, min_height - ctx.style.window.spacing.y), @intCast(c_int, browser.entries.len)) != 0) {
            defer c.nk_list_view_end(&list_view);
            defer ctx.style.window.spacing = old_spacing;
            ctx.style.window.spacing.x = 0;
            ctx.style.window.spacing.y = 0;

            c.nk_layout_row_dynamic(ctx, 0, 1);

            const begin = @intCast(usize, list_view.begin);
            const end = @intCast(usize, list_view.end);
            for (browser.entries[begin..end]) |*entry, entry_i| {
                const i = begin + entry_i;
                var bounds: c.struct_nk_rect = undefined;
                c.nkWidgetBounds(ctx, &bounds);

                var selected: c_int = @boolToInt(entry.selected);
                if (c.nk_selectable_text(ctx, entry.name.ptr, @intCast(c_int, entry.name.len), nk.TEXT_LEFT, &selected) != 0) {
                    browser.selected_file = util.Path.fromSlice(entry.name) catch unreachable;

                    if (browser.mode == .OpenMany and c.nk_input_is_key_down(&ctx.input, c.NK_KEY_SHIFT) != 0) {
                        const from = math.min(i, browser.last_selected_entry);
                        const to = math.max(i, browser.last_selected_entry) + 1;
                        for (browser.entries) |*e|
                            e.selected = false;
                        for (browser.entries[from..to]) |*e|
                            e.selected = true;
                    } else if (browser.mode == .OpenMany and c.nk_input_is_key_down(&ctx.input, c.NK_KEY_CTRL) != 0) {
                        browser.last_selected_entry = i;
                        entry.selected = true;
                    } else {
                        browser.last_selected_entry = i;
                        for (browser.entries) |*e|
                            e.selected = false;
                        entry.selected = true;
                    }
                }
                if (c.nkInputIsMouseClickInRect(&ctx.input, c.NK_BUTTON_DOUBLE, &bounds) != 0) switch (entry.kind) {
                    .Directory => {
                        const dir = util.path.join([_][]const u8{
                            browser.curr_dir.toSliceConst(),
                            entry.name,
                        }) catch continue;

                        if (FileBrowser.open(browser.allocator, browser.mode, dir.toSliceConst())) |new_browser| {
                            browser.close();
                            browser.* = new_browser;
                        } else |_| {}
                    },
                    else => res = .Confirm,
                };
            }
        }
    }

    // +--------+ +--------+
    // | Cancel | |  Open  |
    // +--------+ +--------+
    const cancel_text: []const u8 = "Cancel";
    const confirm_text: []const u8 = switch (browser.mode) {
        .Save => "Save",
        .OpenOne, .OpenMany => "Open",
    };
    const style_font = ctx.style.font;
    const style_button = ctx.style.button;
    const cancel_width = style_font.*.width.?(style_font.*.userdata, 0, cancel_text.ptr, @intCast(c_int, cancel_text.len));
    const button_width = cancel_width + style_button.border +
        (style_button.padding.x + style_button.rounding) * 6;

    c.nk_layout_row_template_begin(ctx, 0);
    c.nk_layout_row_template_push_dynamic(ctx);
    c.nk_layout_row_template_push_static(ctx, button_width);
    c.nk_layout_row_template_push_static(ctx, button_width);
    c.nk_layout_row_template_end(ctx);

    c.nk_label(ctx, c"", nk.TEXT_LEFT);
    if (c.nk_button_text(ctx, cancel_text.ptr, @intCast(c_int, cancel_text.len)) != 0)
        res = .Cancel;

    const confirm_is_active = switch (browser.mode) {
        .Save, .OpenOne => browser.selected_file.len != 0,
        .OpenMany => blk: {
            for (browser.entries) |entry| {
                if (entry.selected)
                    break :blk true;
            }
            break :blk false;
        },
    };

    if (confirm_is_active) {
        if (c.nk_button_text(ctx, confirm_text.ptr, @intCast(c_int, confirm_text.len)) != 0)
            res = .Confirm;
    } else {
        _ = nk.inactiveButton(ctx, confirm_text);
    }

    return res;
}

fn clickablePath(ctx: *nk.Context, text: []const u8, path: util.Path, curr: util.Path) bool {
    if (path.len == 0)
        return false;

    var selected: c_int = @boolToInt(mem.eql(u8, path.toSliceConst(), curr.toSliceConst()));
    return c.nk_selectable_text(ctx, text.ptr, @intCast(c_int, text.len), nk.TEXT_LEFT, &selected) != 0;
}

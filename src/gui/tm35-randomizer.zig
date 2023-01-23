const builtin = @import("builtin");
const clap = @import("clap");
const std = @import("std");
const util = @import("util");

const c = @import("c.zig");

const Executables = @import("Executables.zig");
const Settings = @import("Settings.zig");

const debug = std.debug;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const process = std.process;
const time = std.time;

const escape = util.escape;

const path = fs.path;

// TODO: proper versioning
const program_version = "0.0.0";

const bug_message = "Hi user. You have just hit a bug/limitation in the program. " ++
    "If you care about this program, please report this to the issue tracker here: " ++
    "https://github.com/TM35-Metronome/metronome/issues/new";

const platform = switch (builtin.target.os.tag) {
    .windows => struct {
        extern "kernel32" fn GetConsoleWindow() callconv(std.os.windows.WINAPI) std.os.windows.HWND;
    },
    else => struct {},
};

pub fn main() anyerror!void {
    // HACK: I don't want to show a console to the user.
    //       Here is someone explaing what to pass to the C compiler to make that happen:
    //       https://stackoverflow.com/a/9619254
    //       I have no idea how to get the same behavior using the Zig compiler, so instead
    //       I use this solution:
    //       https://stackoverflow.com/a/9618984
    switch (builtin.target.os.tag) {
        .windows => _ = std.os.windows.user32.showWindow(platform.GetConsoleWindow(), 0),
        else => {},
    }

    var program = try Program.init(heap.c_allocator);
    defer program.deinit();

    try program.render();
    program.run();
}

const Program = @This();

allocator: mem.Allocator,
view: c.webview_t,
loaded_rom: ?util.Path = null,

mode: enum { select, edit } = .select,
render_buffer: std.ArrayListUnmanaged(u8) = std.ArrayListUnmanaged(u8){},
new_settings_name: std.ArrayListUnmanaged(u8) = std.ArrayListUnmanaged(u8){},
exes: Executables,
settings: std.ArrayListUnmanaged(Settings),
selected_settings: usize = math.maxInt(usize),
selected_exe_command: usize = 0,
selected_setting_command: usize = math.maxInt(usize),

fn init(allocator: mem.Allocator) !Program {
    const exes = try Executables.find(allocator);
    errdefer exes.deinit();

    const settings = try Settings.loadAll(allocator);
    errdefer {
        Settings.deinitAll(settings.items);
        settings.deinit();
    }

    const w = c.webview_create(1, null);
    errdefer c.webview_destroy(w);

    c.webview_set_title(w, "Webview Example");
    c.webview_set_size(w, 800, 600, c.WEBVIEW_HINT_NONE);

    return Program{
        .allocator = allocator,
        .exes = exes,
        .settings = settings,
        .view = w,
    };
}

fn deinit(program: *Program) void {
    for (program.settings.items) |*settings| settings.deinit(program.allocator);
    program.render_buffer.deinit(program.allocator);
    program.new_settings_name.deinit(program.allocator);
    program.exes.deinit();
    program.settings.deinit(program.allocator);
    c.webview_destroy(program.view);
}

fn run(program: *Program) void {
    const p = program;
    const w = p.view;
    c.webview_bind(w, "tm35SelectSettings", wrap(.redraw, selectSettings), p);
    c.webview_bind(w, "tm35SelectExeCommand", wrap(.no_redraw, selectExeCommand), p);
    c.webview_bind(w, "tm35SelectSettingCommand", wrap(.redraw, selectSettingCommand), p);
    c.webview_bind(w, "tm35SetSettingName", wrap(.no_redraw, setSettingName), p);
    c.webview_bind(w, "tm35SetSettingDescription", wrap(.no_redraw, setSettingDescription), p);
    c.webview_bind(w, "tm35CheckCheckbox", wrap(.no_redraw, checkCheckbox), p);
    c.webview_bind(w, "tm35SetInt", wrap(.no_redraw, setInt), p);
    c.webview_bind(w, "tm35SetFloat", wrap(.no_redraw, setFloat), p);
    c.webview_bind(w, "tm35SetEnum", wrap(.no_redraw, setEnum), p);
    c.webview_bind(w, "tm35SetString", wrap(.no_redraw, setString), p);
    c.webview_bind(w, "tm35AddCommand", wrap(.redraw, addCommand), p);
    c.webview_bind(w, "tm35RemoveCommand", wrap(.redraw, removeCommand), p);
    c.webview_bind(w, "tm35SetNewSettingsName", wrap(.no_redraw, setNewSettingsName), p);
    c.webview_bind(w, "tm35NewSettings", wrap(.redraw, newSettings), p);
    c.webview_bind(w, "tm35SwitchToEditMode", wrap(.redraw, switchToEditMode), p);
    c.webview_bind(w, "tm35SwitchToSelectMode", wrap(.redraw, switchToSelectMode), p);
    c.webview_bind(w, "tm35DeleteSelected", wrap(.redraw, deleteSelected), p);
    c.webview_bind(w, "tm35LoadRom", wrap(.redraw, loadRom), p);
    c.webview_bind(w, "tm35Randomize", wrap(.redraw, randomize), p);
    c.webview_run(w);
}

fn selectedSettings(program: Program) ?*Settings {
    if (program.selected_settings < program.settings.items.len)
        return &program.settings.items[program.selected_settings];
    return null;
}

fn selectedExeCommand(program: Program) ?*const Executables.Command {
    if (program.selected_exe_command < program.exes.commands.len)
        return &program.exes.commands[program.selected_exe_command];
    return null;
}

fn selectedSettingCommand(program: Program) ?*Settings.Command {
    const settings = program.selectedSettings() orelse return null;
    if (program.selected_setting_command < settings.commands.items.len)
        return &settings.commands.items[program.selected_setting_command];
    return null;
}

fn render(program: *Program) !void {
    program.render_buffer.shrinkRetainingCapacity(0);
    const writer = program.render_buffer.writer(program.allocator);
    try writer.writeAll(
        \\<html lang="en">
        \\<meta name='viewport' content='width=device-width, width=device-height, initial-scale=1.0'>
        \\<style>
        \\* {
        \\    box-sizing: border-box;
        \\    padding: 0;
        \\    margin: 0;
        \\    min-height: 0;
        \\    min-width: 0;
        \\}
        \\textarea {
        \\    resize: none;
        \\}
        \\.root {
        \\    padding: 10px;
        \\    width: 100vw;
        \\    height: 100vh;
        \\}
        \\.grid {
        \\    display: grid;
        \\    gap: 4px 4px;
        \\}
        \\.col-1fr {
        \\    grid-template-columns: 1fr;
        \\}
        \\.col-auto-auto {
        \\    grid-template-columns: auto auto;
        \\}
        \\.col-220px-1fr {
        \\    grid-template-columns: 220px 1fr;
        \\}
        \\.col-1fr-26px-26px {
        \\    grid-template-columns: 1fr 26px 26px;
        \\}
        \\.col-1fr-1fr-1fr {
        \\    grid-template-columns: 1fr 1fr 1fr;
        \\}
        \\.row-1fr {
        \\    grid-template-rows: 1fr;
        \\}
        \\.row-1fr-26px-26px {
        \\    grid-template-rows: 1fr 26px 26px;
        \\}
        \\.row-26px-26px {
        \\    grid-template-rows: 26px 26px;
        \\}
        \\.row-auto-1fr {
        \\    grid-template-rows: auto 1fr;
        \\}
        \\.row-auto-auto-1fr {
        \\    grid-template-rows: auto auto 1fr;
        \\}
        \\.row-auto-1fr-26px-26px {
        \\    grid-template-rows: auto 1fr 26px 26px;
        \\}
        \\.text-center {
        \\    text-align: center;
        \\}
        \\</style>
        \\<main class='root grid col-220px-1fr row-1fr'>
        \\
    );

    switch (program.mode) {
        .select => {
            try program.renderSettingsList(writer);
            try program.renderSettingsDetails(writer);
        },
        .edit => {
            try program.renderCommandList(writer);
            try program.renderCommandSettings(writer);
        },
    }

    try writer.writeAll(
        \\</main>
        \\</html>
        \\
    );
    try writer.writeByte(0);

    const content = program.render_buffer.items;
    const content_z = content[0 .. content.len - 1 :0];
    c.webview_set_html(program.view, content_z.ptr);
}

fn renderSettingsList(program: Program, writer: anytype) !void {
    try writer.writeAll(
        \\<div class='grid col-1fr row-1fr-26px-26px'>
        \\    <select autofocus size='2' onchange='tm35SelectSettings(this.selectedIndex)'>
        \\
    );

    for (program.settings.items) |setting, i| {
        const is_selected = program.selected_settings == i;
        const selected = if (is_selected) " selected=true" else "";
        try writer.writeAll("        ");
        try writer.print("<option{s}>{s}</option>\n", .{
            selected,
            html.escapeFmt(setting.name.items),
        });
    }

    const disabled = if (program.selectedSettings()) |_| "" else " disabled";
    try writer.print(
        \\    </select>
        \\    <input placeholder='New settings name'
        \\        onchange='tm35SetNewSettingsName(this.value)'
        \\        value='{[name]s}'/>
        \\    <div class='grid col-1fr-1fr-1fr row-1fr'>
        \\        <button onclick='tm35NewSettings()'>New</button>
        \\        <button{[disabled]s} onclick='tm35SwitchToEditMode()'>Edit</button>
        \\        <button{[disabled]s} onclick='tm35DeleteSelected()'>Delete</button>
        \\    </div>
        \\</div>
        \\
    ,
        .{
            .name = html.escapeFmt(program.new_settings_name.items),
            .disabled = disabled,
        },
    );
}

fn renderSettingsDetails(program: Program, writer: anytype) !void {
    const title = if (program.selectedSettings()) |settings| settings.name.items else "Metronome";
    const desc = if (program.selectedSettings()) |settings|
        settings.description.items
    else
        \\Welcome to Metronome, the pokemon rom randomizer. What you see here is a menu for
        \\selecting premade randomization settings and applying them to a rom of your choice.
        \\
        \\You can also create your own settings by using the buttons in the bottom left corner.
        \\
        ;
    try writer.print(
        \\<div class='grid col-1fr row-auto-1fr-26px-26px'>
        \\    <h1 class='text-center'>{[title]s}</h1>
        \\    <article>
    ,
        .{
            .title = html.escapeFmt(title),
        },
    );

    _ = c.md_html(
        desc.ptr,
        @intCast(c.MD_SIZE, desc.len),
        generateMdRender(@TypeOf(writer)),
        discardConst(&writer),
        0,
        0,
    );

    try writer.writeAll(
        \\</article>
        \\
    );

    const randomize_button = if (program.loaded_rom == null and program.selectedSettings() == null)
        "<button disabled>Select settings and load a rom</button>"
    else if (program.loaded_rom == null)
        "<button disabled>Load a rom</button>"
    else if (program.selectedSettings() == null)
        "<button disabled>Select settings</button>"
    else
        "<button onclick='tm35Randomize()'>Randomize!</button>";

    const rom = if (program.loaded_rom) |*rom| fs.path.basename(rom.slice()) else "Choose Rom";
    try writer.print(
        \\    <button onclick='tm35LoadRom()'>{s}</button>
        \\    {s}
        \\</div>
        \\
    ,
        .{ html.escapeFmt(rom), randomize_button },
    );
}

fn generateMdRender(
    comptime Writer: type,
) fn ([*c]const c.MD_CHAR, c.MD_SIZE, ?*anyopaque) callconv(.C) void {
    return struct {
        fn mdRender(
            ptr: [*c]const c.MD_CHAR,
            len: c.MD_SIZE,
            userdata: ?*anyopaque,
        ) callconv(.C) void {
            const str = @ptrCast([*]const u8, ptr)[0..len];
            const writer = @ptrCast(*const Writer, @alignCast(@alignOf(Writer), userdata));
            writer.writeAll(str) catch {};
        }
    }.mdRender;
}

fn DiscardConst(comptime Ptr: type) type {
    var info = @typeInfo(Ptr);
    info.Pointer.is_const = false;
    return @Type(info);
}

fn discardConst(ptr: anytype) DiscardConst(@TypeOf(ptr)) {
    const Res = DiscardConst(@TypeOf(ptr));
    switch (@typeInfo(Res).Pointer.size) {
        .Slice => {
            const res = discardConst(ptr.ptr);
            return res[0..ptr.len];
        },
        else => return @intToPtr(Res, @ptrToInt(ptr)),
    }
}

fn renderCommandList(program: Program, writer: anytype) !void {
    try writer.writeAll(
        \\<div class='grid col-1fr row-1fr-26px-26px'>
        \\    <select autofocus size='2' onchange='tm35SelectSettingCommand(this.selectedIndex)'>
        \\
    );

    const settings = program.selectedSettings().?;
    for (settings.commands.items) |command, i| {
        const is_selected = program.selected_setting_command == i;
        const selected = if (is_selected) " selected=true" else "";
        try writer.writeAll("            ");
        try writer.print("<option{s}>{s}</option>\n", .{
            selected,
            html_pretty_command.escapeFmt(command.name.items),
        });
    }

    try writer.writeAll(
        \\    </select>
        \\    <div class='grid col-1fr-26px-26px row-1fr'>
        \\        <select onchange='tm35SelectExeCommand(this.selectedIndex)'>
        \\
    );

    for (program.exes.commands) |command, i| {
        const is_selected = program.selected_exe_command == i;
        const selected = if (is_selected) " selected=true" else "";
        try writer.writeAll("        ");
        try writer.print("<option{s}>{s}</option>\n", .{
            selected,
            html_pretty_command.escapeFmt(command.name()),
        });
    }

    try writer.print(
        \\        </select>
        \\        <button onclick='tm35AddCommand()'>+</button>
        \\        <button onclick='tm35RemoveCommand()'>-</button>
        \\    </div>
        \\    <div class='grid col-auto-auto row-1fr'>
        \\        <button onclick='tm35SelectSettingCommand("{}")'>General settings</button>
        \\        <button onclick='tm35SwitchToSelectMode()'>Done</button>
        \\    </div>
        \\</div>
        \\
    , .{math.maxInt(usize)});
}

fn renderCommandSettings(program: Program, writer: anytype) !void {
    const settings = program.selectedSettingCommand() orelse {
        const settings = program.selectedSettings().?;
        try writer.print(
            \\<div class='grid col-1fr row-auto-auto-1fr'>
            \\    <div>
            \\        <label for='name'>Name:</label>
            \\        <input id='name' value='{s}' onchange='tm35SetSettingName(this.value)'/>
            \\    </div>
            \\    <label for='desc'>Description:</label>
            \\    <textarea id='desc'
            \\        onchange='tm35SetSettingDescription(this.value)'>{s}</textarea>
            \\</div>
            \\
        , .{
            html.escapeFmt(settings.name.items),
            html.escapeFmt(settings.description.items),
        });
        return;
    };

    try writer.print(
        \\<div class='grid col-1fr row-auto-1fr'>
        \\    <h1 class='text-center'>{s}</h1>
        \\    <div>
        \\    <table>
        \\
    , .{html_pretty_command.escapeFmt(settings.name.items)});

    const command = program.exes.findByName(settings.name.items).?;
    for (command.flags) |flag, i| {
        const param = command.params[flag.i];
        const name = param.names.longest().name;
        const arg = if (settings.get(param)) |arg| arg.value.items else "";

        const checked = if (mem.eql(u8, arg, "true")) " checked" else "";
        try writer.print(
            \\<tr>
            \\<td><label for='{[name]s}' title='{[description]s}'>{[pretty_name]s}</label></td>
            \\<td><input{[checked]s} type='checkbox' id='{[name]s}' title='{[description]s}'
            \\    onchange='tm35CheckCheckbox({[index]}, this.checked)'/></td>
            \\</tr>
            \\
        , .{
            .name = html.escapeFmt(name),
            .pretty_name = html_pretty.escapeFmt(name),
            .description = html.escapeFmt(mem.trim(u8, param.id.description(), " ")),
            .checked = checked,
            .index = i,
        });
    }

    const is_num_constaint = "(event.charCode >= 48 && event.charCode <= 57)";
    for (command.ints) |int, i| {
        const param = command.params[int.i];
        const name = param.names.longest().name;
        const arg = if (settings.get(param)) |arg| arg.value.items else "";

        try writer.print(
            \\<tr>
            \\<td><label for='{[name]s}' title='{[description]s}'>{[pretty_name]s}</label></td>
            \\<td><input id='{[name]s}' title='{[description]s}' value='{[value]s}'
            \\    placeholder='{[default]d}'
            \\    onkeypress='return {[constraint]s}'
            \\    onchange='tm35SetInt({[index]}, this.value || "{[default]d}")'/></td>
            \\</tr>
            \\
        ,
            .{
                .name = html_pretty.escapeFmt(name),
                .pretty_name = html_pretty.escapeFmt(name),
                .description = html.escapeFmt(mem.trim(u8, param.id.description(), " ")),
                .value = html.escapeFmt(arg),
                .default = int.default,
                .index = i,
                .constraint = is_num_constaint,
            },
        );
    }

    const only_has_one_dot_constaint =
        "(event.charCode == 46 && !this.value.includes(\".\"))";
    for (command.floats) |float, i| {
        const param = command.params[float.i];
        const name = param.names.longest().name;
        const arg = if (settings.get(param)) |arg| arg.value.items else "";

        try writer.print(
            \\<tr>
            \\<td><label for='{[name]s}' title='{[description]s}'>{[pretty_name]s}</label></td>
            \\<td><input id='{[name]s}' title='{[description]s}' value='{[value]s}'
            \\    placeholder='{[default]d}'
            \\    onkeypress='return {[constaint_1]s} || {[constaint_2]s}'
            \\    onchange='tm35SetFloat({[index]}, this.value || "{[default]d}")'/></td>
            \\</tr>
            \\
        , .{
            .name = html_pretty.escapeFmt(name),
            .pretty_name = html_pretty.escapeFmt(name),
            .description = html.escapeFmt(mem.trim(u8, param.id.description(), " ")),
            .value = html.escapeFmt(arg),
            .default = float.default,
            .index = i,
            .constaint_1 = is_num_constaint,
            .constaint_2 = only_has_one_dot_constaint,
        });
    }

    for (command.enums) |enumeration, i| {
        const param = command.params[enumeration.i];
        const name = param.names.longest().name;
        const default = enumeration.options[enumeration.default];
        const arg = if (settings.get(param)) |arg| arg.value.items else default;

        try writer.print(
            \\<tr>
            \\<td><label for='{[name]s}' title='{[description]s}'>{[pretty_name]s}</label></td>
            \\<td><select id='{[name]s}' title='{[description]s}'
            \\    onchange='tm35SetEnum({[index]}, this.value)'>
            \\
        , .{
            .name = html.escapeFmt(name),
            .pretty_name = html_pretty.escapeFmt(name),
            .description = html.escapeFmt(mem.trim(u8, param.id.description(), " ")),
            .index = i,
        });

        for (enumeration.options) |option| {
            const selected = if (mem.eql(u8, option, arg)) " selected=true" else "";
            try writer.print(
                \\<option{[selected]s}
                \\    value='{[value]s}'>{[pretty_value]s}</option>
                \\
            , .{
                .selected = selected,
                .value = html.escapeFmt(option),
                .pretty_value = html_pretty.escapeFmt(option),
            });
        }

        try writer.writeAll(
            \\</select></td>
            \\</tr>
            \\
        );
    }

    try writer.writeAll(
        \\    </table>
        \\
    );

    for (command.multi_strings) |string, i| {
        const param = command.params[string.i];
        const name = param.names.longest().name;
        const arg = if (settings.get(param)) |arg| arg.value.items else "";

        try writer.print(
            \\<label for='{[name]s}' title='{[description]s}'>{[pretty_name]s}</label><br/>
            \\<textarea id='{[name]s}' title='{[description]s}' rows='4' cols='50'
            \\    onchange='tm35SetString({[index]}, this.value)'>{[value]s}</textarea>
            \\<br/>
            \\
        , .{
            .name = html.escapeFmt(name),
            .pretty_name = html_pretty.escapeFmt(name),
            .description = html.escapeFmt(mem.trim(u8, param.id.description(), " ")),
            .value = html.escapeFmt(arg),
            .index = i,
        });
    }

    try writer.writeAll(
        \\    </div>
        \\</div>
        \\
    );
}

fn selectSettings(program: *Program, selected: usize) !void {
    program.selected_settings = selected;
}

fn selectSettingCommand(program: *Program, selected: usize) !void {
    program.selected_setting_command = selected;
}

fn selectExeCommand(program: *Program, selected: usize) !void {
    program.selected_exe_command = selected;
}

fn setSettingName(program: *Program, value: []const u8) !void {
    const allocator = program.allocator;
    const settings = program.selectedSettings().?;

    settings.name.shrinkRetainingCapacity(0);
    try settings.name.appendSlice(allocator, value);
    try settings.save();
}

fn setSettingDescription(program: *Program, value: []const u8) !void {
    const allocator = program.allocator;
    const settings = program.selectedSettings().?;

    settings.description.shrinkRetainingCapacity(0);
    try settings.description.appendSlice(allocator, value);
    try settings.save();
}

fn checkCheckbox(program: *Program, flag: usize, value: bool) !void {
    const allocator = program.allocator;
    const settings = program.selectedSettings().?;

    const command_settings = program.selectedSettingCommand().?;
    const command = program.exes.findByName(command_settings.name.items).?;
    const param = command.params[command.flags[flag].i];
    const arg = try command_settings.getOrPut(allocator, param);
    arg.arg.value.shrinkRetainingCapacity(0);
    try arg.arg.value.appendSlice(allocator, if (value) "true" else "false");
    try settings.save();
}

fn setInt(program: *Program, int: usize, value: usize) !void {
    const allocator = program.allocator;
    const settings = program.selectedSettings().?;

    const command_settings = program.selectedSettingCommand().?;
    const command = program.exes.findByName(command_settings.name.items).?;
    const param = command.params[command.ints[int].i];
    const arg = try command_settings.getOrPut(allocator, param);
    arg.arg.value.shrinkRetainingCapacity(0);
    try arg.arg.value.writer(allocator).print("{}", .{value});
    try settings.save();
}

fn setFloat(program: *Program, float: usize, value: f64) !void {
    const allocator = program.allocator;
    const settings = program.selectedSettings().?;

    const command_settings = program.selectedSettingCommand().?;
    const command = program.exes.findByName(command_settings.name.items).?;
    const param = command.params[command.floats[float].i];
    const arg = try command_settings.getOrPut(allocator, param);
    arg.arg.value.shrinkRetainingCapacity(0);
    try arg.arg.value.writer(allocator).print("{d}", .{value});
    try settings.save();
}

fn setEnum(program: *Program, enumeration: usize, value: []const u8) !void {
    const allocator = program.allocator;
    const settings = program.selectedSettings().?;

    const command_settings = program.selectedSettingCommand().?;
    const command = program.exes.findByName(command_settings.name.items).?;
    const param = command.params[command.enums[enumeration].i];
    const arg = try command_settings.getOrPut(allocator, param);
    arg.arg.value.shrinkRetainingCapacity(0);
    try arg.arg.value.appendSlice(allocator, value);
    try settings.save();
}

fn setString(program: *Program, string: usize, value: []const u8) !void {
    const allocator = program.allocator;
    const settings = program.selectedSettings().?;

    const command_settings = program.selectedSettingCommand().?;
    const command = program.exes.findByName(command_settings.name.items).?;
    const param = command.params[command.multi_strings[string].i];
    const arg = try command_settings.getOrPut(allocator, param);
    arg.arg.value.shrinkRetainingCapacity(0);
    try arg.arg.value.appendSlice(allocator, value);
    try settings.save();
}

fn addCommand(program: *Program) !void {
    const allocator = program.allocator;
    const settings = program.selectedSettings().?;
    const command = program.selectedExeCommand().?;

    {
        var cmd = try Settings.Command.init(allocator, command.name());
        errdefer cmd.deinit(allocator);
        try settings.commands.append(allocator, cmd);
    }

    program.selected_setting_command = settings.commands.items.len - 1;
    try settings.save();
}

fn removeCommand(program: *Program) !void {
    _ = program.selectedSettingCommand() orelse return;

    const settings = program.selectedSettings().?;
    _ = settings.commands.orderedRemove(program.selected_setting_command);
    program.selected_setting_command = math.maxInt(usize);

    try settings.save();
}

fn setNewSettingsName(program: *Program, value: []const u8) !void {
    program.new_settings_name.shrinkRetainingCapacity(0);
    try program.new_settings_name.appendSlice(program.allocator, value);
}

fn newSettings(program: *Program) !void {
    if (program.new_settings_name.items.len == 0)
        return;

    const allocator = program.allocator;
    var settings = try Settings.new(allocator, program.new_settings_name.items);
    errdefer settings.deinit(allocator);

    try program.settings.append(allocator, settings);
    program.selected_settings = program.settings.items.len - 1;
}

fn switchToEditMode(program: *Program) !void {
    debug.assert(program.mode == .select);
    program.mode = .edit;
    program.selected_exe_command = 0;
    program.selected_setting_command = math.maxInt(usize);
}

fn switchToSelectMode(program: *Program) !void {
    debug.assert(program.mode == .edit);
    program.mode = .select;
}

fn deleteSelected(program: *Program) !void {
    // TODO: Confirmation
    if (program.selectedSettings()) |settings| {
        try std.fs.cwd().deleteFile(settings.path.items);

        var removed = program.settings.orderedRemove(program.selected_settings);
        removed.deinit(program.allocator);
        program.selected_settings = math.maxInt(usize);
    }
}

fn loadRom(program: *Program) !void {
    var m_out_path: ?[*:0]u8 = null;
    const rom_path = switch (c.NFD_OpenDialog("gb,gba,nds", null, &m_out_path)) {
        c.NFD_ERROR => return error.DialogError,
        c.NFD_CANCEL => return,
        c.NFD_OKAY => blk: {
            const out_path = m_out_path.?;
            defer std.c.free(out_path);
            break :blk try util.Path.fromSlice(mem.span(out_path));
        },
        else => unreachable,
    };

    const result = try std.ChildProcess.exec(.{
        .allocator = program.allocator,
        .argv = &[_][]const u8{
            program.exes.identify.slice(),
            rom_path.slice(),
        },
    });
    defer {
        program.allocator.free(result.stdout);
        program.allocator.free(result.stderr);
    }

    if (result.term != .Exited or result.term.Exited != 0)
        return error.NotAPokemonRom;

    program.loaded_rom = rom_path;
}

fn randomize(program: *Program) !void {
    var m_out_path: ?[*:0]u8 = null;
    const out = switch (c.NFD_SaveDialog("gb,gba,nds", null, &m_out_path)) {
        c.NFD_ERROR => return error.DialogError,
        c.NFD_CANCEL => return,
        c.NFD_OKAY => blk: {
            const out_path = m_out_path.?;
            defer std.c.free(out_path);
            break :blk try util.Path.fromSlice(mem.span(out_path));
        },
        else => unreachable,
    };

    const cache_dir = try util.dir.folder(.cache);
    const program_cache_dir = util.path.join(&[_][]const u8{
        cache_dir.constSlice(),
        Executables.program_name,
    });
    const script_file_name = util.path.join(&[_][]const u8{
        program_cache_dir.constSlice(),
        "tmp_script",
    });
    std.log.info("{s}", .{script_file_name.constSlice()});

    {
        try fs.cwd().makePath(program_cache_dir.constSlice());
        const file = try fs.cwd().createFile(script_file_name.constSlice(), .{});
        defer file.close();
        try program.outputScript(file.writer(), out.slice());
    }

    var buf: [1024 * 40]u8 = undefined;
    var fba = heap.FixedBufferAllocator.init(&buf);
    const term = switch (builtin.target.os.tag) {
        .linux => blk: {
            var sh = std.ChildProcess.init(
                &[_][]const u8{ "sh", script_file_name.constSlice() },
                fba.allocator(),
            );
            break :blk try sh.spawnAndWait();
        },
        .windows => blk: {
            var cmd = std.ChildProcess.init(
                &[_][]const u8{ "cmd", "/c", "call", script_file_name.constSlice() },
                fba.allocator(),
            );
            break :blk try cmd.spawnAndWait();
        },
        else => @compileError("Unsupported os"),
    };
    switch (term) {
        .Exited => |code| {
            if (code != 0)
                return error.CommandFailed;
        },
        .Signal, .Stopped, .Unknown => |_| {
            return error.CommandFailed;
        },
    }
}

fn outputScript(
    program: *Program,
    writer: anytype,
    out: []const u8,
) !void {
    const esc = escape.generate(&escapes);
    try writer.writeAll(quotes);
    try esc.escapeWrite(writer, program.exes.load.constSlice());
    try writer.writeAll(quotes ++ " " ++ quotes);
    try esc.escapeWrite(writer, program.loaded_rom.?.slice());
    try writer.writeAll(quotes ++ " | ");

    const settings = program.selectedSettings().?;

    for (settings.commands.items) |*setting| {
        const command = program.exes.findByName(setting.name.items) orelse continue;

        try writer.writeAll(quotes);
        try esc.escapeWrite(writer, command.path);
        try writer.writeAll(quotes);

        for (command.flags) |flag_param| {
            const param = command.params[flag_param.i];
            const flag = setting.get(param) orelse continue;
            if (!mem.eql(u8, flag.value.items, "true"))
                continue;

            const longest = param.names.longest();
            try writer.writeAll(" " ++ quotes);
            try esc.escapePrint(writer, "{s}{s}", .{ longest.kind.prefix(), longest.name });
            try writer.writeAll(quotes);
        }
        for (command.ints) |int_param| {
            const param = command.params[int_param.i];
            try outputArgument(writer, esc, setting, param);
        }
        for (command.floats) |float_param| {
            const param = command.params[float_param.i];
            try outputArgument(writer, esc, setting, param);
        }
        for (command.enums) |enum_param| {
            const param = command.params[enum_param.i];
            try outputArgument(writer, esc, setting, param);
        }
        for (command.multi_strings) |multi_param| {
            const param = command.params[multi_param.i];
            const arg = setting.get(param) orelse continue;
            const longest = param.names.longest();

            var it = mem.tokenize(u8, arg.value.items, "\r\n");
            while (it.next()) |string| {
                try writer.writeAll(" " ++ quotes);
                try esc.escapePrint(writer, "{s}{s}={s}", .{
                    longest.kind.prefix(), longest.name, string,
                });
                try writer.writeAll(quotes);
            }
        }

        try writer.writeAll(" | ");
    }

    try writer.writeAll(quotes);
    try esc.escapeWrite(writer, program.exes.apply.constSlice());
    try writer.writeAll(quotes ++ " --replace --output " ++ quotes);
    try esc.escapeWrite(writer, out);
    try writer.writeAll(quotes ++ " " ++ quotes);
    try esc.escapeWrite(writer, program.loaded_rom.?.slice());
    try writer.writeAll(quotes);
    try writer.writeAll("\n");
}

fn outputArgument(
    writer: anytype,
    esc: anytype,
    settings: *Settings.Command,
    param: clap.Param(clap.Help),
) !void {
    const arg = settings.get(param) orelse return;
    const longest = param.names.longest();
    try writer.writeAll(" " ++ quotes);
    try esc.escapePrint(writer, "{s}{s}={s}", .{
        longest.kind.prefix(), longest.name, arg.value.items,
    });
    try writer.writeAll(quotes);
}

const html = escape.generate(&.{
    .{ .escaped = "&#39;", .unescaped = "'" },
    .{ .escaped = "&amp;", .unescaped = "&" },
    .{ .escaped = "&gt;", .unescaped = ">" },
    .{ .escaped = "&lt;", .unescaped = "<" },
    .{ .escaped = "&quot;", .unescaped = "\"" },
});

const html_pretty_command = escape.generate(&.{
    .{ .escaped = "&#39;", .unescaped = "'" },
    .{ .escaped = "&amp;", .unescaped = "&" },
    .{ .escaped = "&gt;", .unescaped = ">" },
    .{ .escaped = "&lt;", .unescaped = "<" },
    .{ .escaped = "&quot;", .unescaped = "\"" },
    .{ .escaped = "random", .unescaped = "rand" },
    .{ .escaped = " ", .unescaped = "-" },
    .{ .escaped = " ", .unescaped = "_" },
    .{ .escaped = "", .unescaped = "tm35-" },
});

const html_pretty = escape.generate(&.{
    .{ .escaped = "&#39;", .unescaped = "'" },
    .{ .escaped = "&amp;", .unescaped = "&" },
    .{ .escaped = "&gt;", .unescaped = ">" },
    .{ .escaped = "&lt;", .unescaped = "<" },
    .{ .escaped = "&quot;", .unescaped = "\"" },
    .{ .escaped = " ", .unescaped = "-" },
    .{ .escaped = " ", .unescaped = "_" },
});

const escapes = switch (builtin.target.os.tag) {
    .linux => [_]escape.Escape{
        .{ .escaped = "'\\''", .unescaped = "\'" },
    },
    .windows => [_]escape.Escape{
        .{ .escaped = "\\\"", .unescaped = "\"" },
    },
    else => @compileError("Unsupported os"),
};
const quotes = switch (builtin.target.os.tag) {
    .linux => "'",
    .windows => "\"",
    else => @compileError("Unsupported os"),
};

const ReDraw = enum {
    redraw,
    no_redraw,
};

fn wrap(
    comptime redraw: ReDraw,
    comptime func: anytype,
) fn ([*c]const u8, [*c]const u8, ?*anyopaque) callconv(.C) void {
    return struct {
        fn wrapper(seq: [*c]const u8, req: [*c]const u8, arg: ?*anyopaque) callconv(.C) void {
            const program = @ptrCast(*Program, @alignCast(@alignOf(Program), arg));
            const req_slice = mem.span(req);

            std.log.info("{s}", .{req_slice});
            if (call(program, req_slice)) |_| {
                c.webview_return(program.view, seq, 0, "{}");
            } else |err| {
                std.log.err("{s}", .{@errorName(err)});
                c.webview_return(program.view, seq, 1, "{}");
            }
        }

        fn call(program: *Program, req: []const u8) !void {
            var parser = std.json.Parser.init(program.allocator, false);
            defer parser.deinit();

            var parsed = try parser.parse(req);
            defer parsed.deinit();

            const tree = parsed.root;
            const info = @typeInfo(@TypeOf(func)).Fn;
            switch (info.params.len) {
                1 => try func(program),
                2 => try func(
                    program,
                    try parseArg(info.params[1].type.?, tree, 0),
                ),
                3 => try func(
                    program,
                    try parseArg(info.params[1].type.?, tree, 0),
                    try parseArg(info.params[2].type.?, tree, 1),
                ),
                else => comptime unreachable,
            }
            switch (redraw) {
                .redraw => try program.render(),
                .no_redraw => {},
            }
        }
    }.wrapper;
}

fn parseArg(comptime T: type, tree: std.json.Value, arg: usize) !T {
    if (tree != .Array)
        return error.InvalidArgument;

    const arg_values = tree.Array.items;
    if (arg_values.len <= arg)
        return error.TooFewArguments;

    const arg_value = arg_values[arg];
    switch (T) {
        []const u8 => switch (arg_value) {
            .String => |s| return s,
            else => return error.InvalidArgument,
        },
        else => {},
    }

    switch (@typeInfo(T)) {
        .Int => switch (arg_value) {
            .Integer => |i| return std.math.cast(T, i) orelse return error.IntArgDoesNotFit,
            .String => |s| return try fmt.parseInt(T, s, 0),
            else => return error.InvalidArgument,
        },
        .Float => switch (arg_value) {
            .Float => |f| return @floatCast(T, f),
            .String => |s| return try fmt.parseFloat(T, s),
            else => return error.InvalidArgument,
        },
        .Bool => switch (arg_value) {
            .Bool => |b| return b,
            else => return error.InvalidArgument,
        },
        else => @compileError("Cannot parse '" ++ @typeName(T) ++ "'"),
    }
}

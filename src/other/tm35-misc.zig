const clap = @import("clap");
const format = @import("format");
const std = @import("std");
const util = @import("util");

const debug = std.debug;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const log = std.log;
const math = std.math;
const mem = std.mem;
const os = std.os;
const rand = std.rand;
const testing = std.testing;

const Program = @This();

allocator: mem.Allocator,
options: struct {
    easy_hms: bool,
    fast_text: bool,
    biking: Allow,
    running: Allow,
    exp_scale: f64,
    static_scale: f64,
    trainer_scale: f64,
    wild_scale: f64,
},

const Allow = enum {
    unchanged,
    nowhere,
    everywhere,
};

pub const main = util.generateMain(Program);
pub const version = "0.0.0";
pub const description =
    \\Command to apply miscellaneous changed.
    \\
;

pub const parsers = .{
    .FLOAT = clap.parsers.float(f64),
    .@"unchanged|nowhere|everywhere" = clap.parsers.enumeration(Allow),
};

pub const params = clap.parseParamsComptime(
    \\    --allow-biking <unchanged|nowhere|everywhere>
    \\        Change where biking is allowed (gen3 only) (default: unchanged).
    \\
    \\    --allow-running <unchanged|nowhere|everywhere>
    \\        Change where running is allowed (gen3 only) (default: unchanged).
    \\
    \\    --easy-hms
    \\        Have all Pokémon be able to learn all HMs.
    \\
    \\    --fast-text
    \\        Change text speed to fastest possible for the game.
    \\
    \\    --exp-yield-scaling <FLOAT>
    \\        Scale The amount of exp Pokémons give. (default: 1.0).
    \\
    \\    --static-level-scaling <FLOAT>
    \\        Scale static Pokémon levels by this number. (default: 1.0).
    \\
    \\    --trainer-level-scaling <FLOAT>
    \\        Scale trainer Pokémon levels by this number. (default: 1.0).
    \\
    \\    --wild-level-scaling <FLOAT>
    \\        Scale wild Pokémon levels by this number. (default: 1.0).
    \\
    \\-h, --help
    \\        Display this help text and exit.
    \\
    \\-v, --version
    \\        Output version information and exit.
    \\
);

pub fn init(allocator: mem.Allocator, args: anytype) !Program {
    return Program{
        .allocator = allocator,
        .options = .{
            .easy_hms = args.args.@"easy-hms",
            .fast_text = args.args.@"fast-text",
            .biking = args.args.@"allow-biking" orelse .unchanged,
            .running = args.args.@"allow-running" orelse .unchanged,
            .exp_scale = args.args.@"exp-yield-scaling" orelse 1.0,
            .static_scale = args.args.@"static-level-scaling" orelse 1.0,
            .trainer_scale = args.args.@"trainer-level-scaling" orelse 1.0,
            .wild_scale = args.args.@"wild-level-scaling" orelse 1.0,
        },
    };
}

pub fn run(
    program: *Program,
    comptime Reader: type,
    comptime Writer: type,
    stdio: util.CustomStdIoStreams(Reader, Writer),
) !void {
    try format.io(
        program.allocator,
        stdio.in,
        stdio.out,
        .{ .out = stdio.out, .program = program },
        useGame,
    );
}

fn useGame(ctx: anytype, game: format.Game) !void {
    const out = ctx.out;
    const program = ctx.program;
    switch (game) {
        .instant_text => |_| if (program.options.fast_text) {
            return out.print(".instant_text=true\n", .{});
        } else {
            return error.DidNotConsumeData;
        },
        .text_delays => |delay| if (program.options.fast_text) {
            const new_delay = switch (delay.index) {
                0 => @as(usize, 2),
                1 => @as(usize, 1),
                else => @as(usize, 0),
            };
            return out.print(".text_delays[{}]={}\n", .{ delay.index, new_delay });
        } else {
            return error.DidNotConsumeData;
        },
        .pokemons => |pokemons| switch (pokemons.value) {
            .base_exp_yield => |yield| if (program.options.exp_scale != 1.0) {
                const new_yield_float = math.floor(@intToFloat(f64, yield) * program.options.exp_scale);
                const new_yield = @floatToInt(u16, new_yield_float);
                return out.print(".pokemons[{}].base_exp_yield={}\n", .{
                    pokemons.index,
                    new_yield,
                });
            } else {
                return error.DidNotConsumeData;
            },
            .hms => |hm| return out.print(".pokemons[{}].hms[{}]={}\n", .{
                pokemons.index,
                hm.index,
                hm.value or program.options.easy_hms,
            }),
            .stats,
            .types,
            .catch_rate,
            .items,
            .gender_ratio,
            .egg_cycles,
            .base_friendship,
            .growth_rate,
            .egg_groups,
            .abilities,
            .evos,
            .moves,
            .tms,
            .name,
            .pokedex_entry,
            => return error.DidNotConsumeData,
        },
        .maps => |maps| {
            switch (maps.value) {
                .allow_cycling, .allow_running => {
                    const allow = if (maps.value == .allow_running) program.options.running else program.options.biking;
                    if (allow == .unchanged)
                        return error.DidNotConsumeData;

                    return out.print(".maps[{}].{s}={}\n", .{
                        maps.index,
                        @tagName(maps.value),
                        allow == .everywhere,
                    });
                },
                .music,
                .cave,
                .weather,
                .type,
                .escape_rope,
                .battle_scene,
                .allow_escaping,
                .show_map_name,
                => return error.DidNotConsumeData,
            }
        },
        .trainers => |trainers| switch (trainers.value) {
            .party => |party| switch (party.value) {
                .level => |level| if (program.options.trainer_scale != 1.0) {
                    const new_level_float = math.floor(@intToFloat(f64, level) * program.options.trainer_scale);
                    const new_level = @floatToInt(u8, math.min(new_level_float, 100));
                    return out.print(".trainers[{}].party[{}].level={}\n", .{
                        trainers.index,
                        party.index,
                        new_level,
                    });
                } else {
                    return error.DidNotConsumeData;
                },
                .ability,
                .species,
                .item,
                .moves,
                => return error.DidNotConsumeData,
            },
            .class,
            .trainer_picture,
            .name,
            .items,
            .party_type,
            .party_size,
            => return error.DidNotConsumeData,
        },
        .wild_pokemons => |wild_areas| {
            const wild_area = wild_areas.value.value();
            switch (wild_area) {
                .pokemons => |pokemons| switch (pokemons.value) {
                    .min_level, .max_level => |level| if (program.options.wild_scale != 1.0) {
                        const new_level_float = math.floor(@intToFloat(f64, level) * program.options.wild_scale);
                        const new_level = @floatToInt(u8, math.min(new_level_float, 100));
                        return out.print(".wild_pokemons[{}].{s}.pokemons[{}].{s}={}\n", .{
                            wild_areas.index,
                            @tagName(wild_areas.value),
                            pokemons.index,
                            @tagName(pokemons.value),
                            new_level,
                        });
                    } else {
                        return error.DidNotConsumeData;
                    },
                    .species => return error.DidNotConsumeData,
                },
                .encounter_rate => return error.DidNotConsumeData,
            }
        },
        .static_pokemons => |pokemons| switch (pokemons.value) {
            .level => |level| if (program.options.static_scale != 1.0) {
                const new_level_float = math.floor(
                    @intToFloat(f64, level) * program.options.static_scale,
                );
                const new_level = @floatToInt(u8, math.min(new_level_float, 100));
                return out.print(".static_pokemons[{}].level={}\n", .{ pokemons.index, new_level });
            } else {
                return error.DidNotConsumeData;
            },
            .species => return error.DidNotConsumeData,
        },
        .version,
        .game_title,
        .gamecode,
        .starters,
        .moves,
        .abilities,
        .types,
        .tms,
        .hms,
        .items,
        .pokedex,
        .given_pokemons,
        .pokeball_items,
        .hidden_hollows,
        .text,
        => return error.DidNotConsumeData,
    }
    unreachable;
}

test "tm35-misc" {
    const Pattern = util.testing.Pattern;
    const test_input = try util.testing.filter(util.testing.test_case, &.{
        ".maps[*].allow_*=*",
        ".instant_text=*",
        ".text_delays[*]=*",
        ".static_pokemons[*].level=*",
        ".trainers[*].party[*].level=*",
        ".wild_pokemons[*].*.pokemons[*].*_level=*",
        ".pokemons[*].base_exp_yield=*",
        ".pokemons[*].hms[*]=*",
    });
    defer testing.allocator.free(test_input);

    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_input,
        .args = &[_][]const u8{"--allow-biking=unchanged"},
        .patterns = &[_]Pattern{
            Pattern.endsWith(165, 165, "].allow_cycling=true"),
            Pattern.endsWith(353, 353, "].allow_cycling=false"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_input,
        .args = &[_][]const u8{"--allow-biking=everywhere"},
        .patterns = &[_]Pattern{
            Pattern.endsWith(518, 518, "].allow_cycling=true"),
            Pattern.endsWith(0, 0, "].allow_cycling=false"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_input,
        .args = &[_][]const u8{"--allow-biking=nowhere"},
        .patterns = &[_]Pattern{
            Pattern.endsWith(0, 0, "].allow_cycling=true"),
            Pattern.endsWith(518, 518, "].allow_cycling=false"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_input,
        .args = &[_][]const u8{"--allow-running=unchanged"},
        .patterns = &[_]Pattern{
            Pattern.endsWith(228, 228, "].allow_running=true"),
            Pattern.endsWith(290, 290, "].allow_running=false"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_input,
        .args = &[_][]const u8{"--allow-running=everywhere"},
        .patterns = &[_]Pattern{
            Pattern.endsWith(518, 518, "].allow_running=true"),
            Pattern.endsWith(0, 0, "].allow_running=false"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_input,
        .args = &[_][]const u8{"--allow-running=nowhere"},
        .patterns = &[_]Pattern{
            Pattern.endsWith(0, 0, "].allow_running=true"),
            Pattern.endsWith(518, 518, "].allow_running=false"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_input,
        .args = &[_][]const u8{"--fast-text"},
        .patterns = &[_]Pattern{
            Pattern.endsWith(1, 1, ".instant_text=true"),
            Pattern.endsWith(1, 1, ".text_delays[0]=2"),
            Pattern.endsWith(1, 1, ".text_delays[1]=1"),
            Pattern.endsWith(1, 1, ".text_delays[2]=0"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_input,
        .args = &[_][]const u8{"--static-level-scaling=1.0"},
        .patterns = &[_]Pattern{
            Pattern.glob(4, 4, ".static_pokemons[*].level=70"),
            Pattern.glob(3, 3, ".static_pokemons[*].level=68"),
            Pattern.glob(10, 10, ".static_pokemons[*].level=65"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_input,
        .args = &[_][]const u8{"--static-level-scaling=0.5"},
        .patterns = &[_]Pattern{
            Pattern.glob(4, 4, ".static_pokemons[*].level=35"),
            Pattern.glob(3, 3, ".static_pokemons[*].level=34"),
            Pattern.glob(10, 10, ".static_pokemons[*].level=32"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_input,
        .args = &[_][]const u8{"--trainer-level-scaling=1.0"},
        .patterns = &[_]Pattern{
            Pattern.glob(11, 11, ".trainers[*].party[*].level=20"),
            Pattern.glob(16, 16, ".trainers[*].party[*].level=40"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_input,
        .args = &[_][]const u8{"--trainer-level-scaling=2.0"},
        .patterns = &[_]Pattern{
            Pattern.glob(11, 11, ".trainers[*].party[*].level=40"),
            Pattern.glob(16, 16, ".trainers[*].party[*].level=80"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_input,
        .args = &[_][]const u8{"--wild-level-scaling=1.0"},
        .patterns = &[_]Pattern{
            Pattern.glob(97, 97, ".wild_pokemons[*].*.pokemons[*].min_level=10"),
            Pattern.glob(37, 37, ".wild_pokemons[*].*.pokemons[*].max_level=10"),
            Pattern.glob(9, 9, ".wild_pokemons[*].*.pokemons[*].min_level=20"),
            Pattern.glob(44, 44, ".wild_pokemons[*].*.pokemons[*].max_level=20"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_input,
        .args = &[_][]const u8{"--wild-level-scaling=2.0"},
        .patterns = &[_]Pattern{
            Pattern.glob(97, 97, ".wild_pokemons[*].*.pokemons[*].min_level=20"),
            Pattern.glob(37, 37, ".wild_pokemons[*].*.pokemons[*].max_level=20"),
            Pattern.glob(9, 9, ".wild_pokemons[*].*.pokemons[*].min_level=40"),
            Pattern.glob(44, 44, ".wild_pokemons[*].*.pokemons[*].max_level=40"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_input,
        .args = &[_][]const u8{"--exp-yield-scaling=1.0"},
        .patterns = &[_]Pattern{
            Pattern.endsWith(6, 6, "].base_exp_yield=50"),
            Pattern.endsWith(20, 20, "].base_exp_yield=60"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_input,
        .args = &[_][]const u8{"--exp-yield-scaling=2.0"},
        .patterns = &[_]Pattern{
            Pattern.endsWith(6, 6, "].base_exp_yield=100"),
            Pattern.endsWith(20, 20, "].base_exp_yield=120"),
        },
    });
    try util.testing.runProgramFindPatterns(Program, .{
        .in = test_input,
        .args = &[_][]const u8{"--easy-hms"},
        .patterns = &[_]Pattern{
            Pattern.glob(0, 0, ".pokemons[*].hms[*]=false"),
        },
    });
}

const std = @import("std");

const common = @import("common.zig");
const rom = @import("rom.zig");

pub const offsets = @import("gen5/offsets.zig");
pub const script = @import("gen5/script.zig");

const mem = std.mem;

const nds = rom.nds;

const Narc = nds.fs.Narc;
const Nitro = nds.fs.Nitro;

const lu16 = rom.int.lu16;
const lu32 = rom.int.lu32;
const lu128 = rom.int.lu128;

pub const BasePokemon = extern struct {
    stats: common.Stats,
    types: [2]Type,

    catch_rate: u8,

    evs: [3]u8, // TODO: Figure out if common.EvYield fits in these 3 bytes
    items: [3]lu16,

    gender_ratio: u8,
    egg_cycles: u8,
    base_friendship: u8,

    growth_rate: common.GrowthRate,

    egg_group1: common.EggGroup,
    egg_group2: common.EggGroup,

    abilities: [3]u8,

    // TODO: The three fields below are kinda unknown
    flee_rate: u8,
    form_stats_start: [2]u8,
    form_sprites_start: [2]u8,

    form_count: u8,

    color: common.Color,

    base_exp_yield: u8,

    height: lu16,
    weight: lu16,

    // Memory layout
    // TMS 01-92, HMS 01-06, TMS 93-95
    machine_learnset: lu128,

    // TODO: Tutor data only exists in BW2
    //special_tutors: lu32,
    //driftveil_tutor: lu32,
    //lentimas_tutor: lu32,
    //humilau_tutor: lu32,
    //nacrene_tutor: lu32,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 55);
    }
};

pub const PartyType = packed enum(u8) {
    none = 0b00,
    item = 0b10,
    moves = 0b01,
    both = 0b11,
};

pub const PartyMemberBase = extern struct {
    iv: u8,
    gender_ability: GenderAbilityPair,
    level: u8,
    padding: u8,
    species: lu16,
    form: lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 8);
    }

    const GenderAbilityPair = packed struct {
        gender: u4,
        ability: u4,
    };

    pub fn toParent(base: *PartyMemberBase, comptime Parent: type) *Parent {
        return @fieldParentPtr(Parent, "base", base);
    }
};

pub const PartyMemberNone = extern struct {
    base: PartyMemberBase,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 8);
    }
};

pub const PartyMemberItem = extern struct {
    base: PartyMemberBase,
    item: lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 10);
    }
};

pub const PartyMemberMoves = extern struct {
    base: PartyMemberBase,
    moves: [4]lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 16);
    }
};

pub const PartyMemberBoth = extern struct {
    base: PartyMemberBase,
    item: lu16,
    moves: [4]lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 18);
    }
};

pub const Trainer = extern struct {
    party_type: PartyType,
    class: u8,
    battle_type: u8, // TODO: This should probably be an enum
    party_size: u8,
    items: [4]lu16,
    ai: lu32,
    healer: bool,
    cash: u8,
    post_battle_item: lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 20);
    }

    pub fn partyMember(trainer: Trainer, party: []u8, i: usize) ?*PartyMemberBase {
        return switch (trainer.party_type) {
            .none => trainer.partyMemberHelper(party, @sizeOf(PartyMemberNone), i),
            .item => trainer.partyMemberHelper(party, @sizeOf(PartyMemberItem), i),
            .moves => trainer.partyMemberHelper(party, @sizeOf(PartyMemberMoves), i),
            .both => trainer.partyMemberHelper(party, @sizeOf(PartyMemberBoth), i),
        };
    }

    fn partyMemberHelper(trainer: Trainer, party: []u8, member_size: usize, i: usize) ?*PartyMemberBase {
        const start = i * member_size;
        const end = start + member_size;
        if (party.len < end)
            return null;

        return &mem.bytesAsSlice(PartyMemberBase, party[start..][0..@sizeOf(PartyMemberBase)])[0];
    }
};

pub const Move = packed struct {
    type: Type,
    effect_category: u8,
    category: common.MoveCategory,
    power: u8,
    accuracy: u8,
    pp: u8,
    priority: u8,
    min_hits: u4,
    max_hits: u4,
    result_effect: lu16,
    effect_chance: u8,
    status: u8,
    min_turns: u8,
    max_turns: u8,
    crit: u8,
    flinch: u8,
    effect: lu16,
    target_hp: u8,
    user_hp: u8,
    target: u8,
    // TODO: Arrays of uneven elements doesn't quite work in
    //       packed structs.
    stats_affected1: u8,
    stats_affected2: u8,
    stats_affected3: u8,
    stats_affected_magnetude1: u8,
    stats_affected_magnetude2: u8,
    stats_affected_magnetude3: u8,
    stats_affected_chance1: u8,
    stats_affected_chance2: u8,
    stats_affected_chance3: u8,

    // TODO: Figure out if this is actually how the last fields are layed out.
    padding1: [2]u8,
    flags: lu16,
    padding2: [2]u8,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 36);
    }
};

pub const LevelUpMove = extern struct {
    id: lu16,
    level: lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 4);
    }
};

pub const Type = packed enum(u8) {
    normal = 0x00,
    fighting = 0x01,
    flying = 0x02,
    poison = 0x03,
    ground = 0x04,
    rock = 0x05,
    bug = 0x06,
    ghost = 0x07,
    steel = 0x08,
    fire = 0x09,
    water = 0x0A,
    grass = 0x0B,
    electric = 0x0C,
    psychic = 0x0D,
    ice = 0x0E,
    dragon = 0x0F,
    dark = 0x10,
    _,
};

// TODO: Verify layout
pub const Evolution = extern struct {
    method: Method,
    padding: u8,
    param: lu16,
    target: lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 6);
    }

    pub const Method = packed enum(u8) {
        unused = 0x00,
        friend_ship = 0x01,
        unknown_0x02 = 0x02,
        unknown_0x03 = 0x03,
        level_up = 0x04,
        trade = 0x05,
        trade_holding_item = 0x06,
        trade_with_pokemon = 0x07,
        use_item = 0x08,
        attack_gth_defense = 0x09,
        attack_eql_defense = 0x0A,
        attack_lth_defense = 0x0B,
        personality_value1 = 0x0C,
        personality_value2 = 0x0D,
        level_up_may_spawn_pokemon = 0x0E,
        level_up_spawn_if_cond = 0x0F,
        beauty = 0x10,
        use_item_on_male = 0x11,
        use_item_on_female = 0x12,
        level_up_holding_item_during_daytime = 0x13,
        level_up_holding_item_during_the_night = 0x14,
        level_up_knowning_move = 0x15,
        level_up_with_other_pokemon_in_party = 0x16,
        level_up_male = 0x17,
        level_up_female = 0x18,
        level_up_in_special_magnetic_field = 0x19,
        level_up_near_moss_rock = 0x1A,
        level_up_near_ice_rock = 0x1B,
        _,
    };
};

pub const Species = extern struct {
    value: lu16,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 2);
    }

    pub fn species(s: Species) u10 {
        return @truncate(u10, s.value.value());
    }

    pub fn setSpecies(s: *Species, spe: u10) void {
        s.value = lu16.init((@as(u16, s.form()) << @as(u4, 10)) | spe);
    }

    pub fn form(s: Species) u6 {
        return @truncate(u6, s.value.value() >> 10);
    }

    pub fn setForm(s: *Species, f: u10) void {
        s.value = lu16.init((@as(u16, f) << @as(u4, 10)) | s.species());
    }
};

pub const WildPokemon = extern struct {
    species: Species,
    min_level: u8,
    max_level: u8,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 4);
    }
};

pub const WildPokemons = extern struct {
    rates: [7]u8,
    pad: u8,
    grass: [12]WildPokemon,
    dark_grass: [12]WildPokemon,
    rustling_grass: [12]WildPokemon,
    surf: [5]WildPokemon,
    ripple_surf: [5]WildPokemon,
    fishing: [5]WildPokemon,
    ripple_fishing: [5]WildPokemon,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 232);
    }
};

pub const Pocket = packed enum(u4) {
    items = 0x00,
    tms_hms = 0x01,
    key_items = 0x02,
    balls = 0x08,
    _,
};

// https://github.com/projectpokemon/PPRE/blob/master/pokemon/itemtool/itemdata.py
pub const Item = packed struct {
    price: lu16,
    battle_effect: u8,
    gain: u8,
    berry: u8,
    fling_effect: u8,
    fling_power: u8,
    natural_gift_power: u8,
    flag: u8,
    pocket: Pocket,
    unknown: u4,
    type: u8,
    category: u8,
    category2: lu16,
    category3: u8,
    index: u8,
    anti_index: u8,
    statboosts: Boost,
    ev_yield: common.EvYield,
    hp_restore: u8,
    pp_restore: u8,
    happy1: u8,
    happy2: u8,
    happy3: u8,
    padding1: u8,
    padding2: u8,
    padding3: u8,
    padding4: u8,
    padding5: u8,
    padding6: u8,

    pub const Boost = packed struct {
        hp: u2,
        level: u1,
        evolution: u1,
        attack: u4,
        defense: u4,
        sp_attack: u4,
        sp_defense: u4,
        speed: u4,
        accuracy: u4,
        crit: u2,
        pp: u2,
        target: u8,
        target2: u8,
    };

    comptime {
        std.debug.assert(@sizeOf(@This()) == 36);
    }
};

const PokeballItem = struct {
    item: *lu16,
    amount: *lu16,
};

pub const Game = struct {
    version: common.Version,
    allocator: *mem.Allocator,

    starters: [3][]*lu16,
    moves: []Move,
    trainers: []Trainer,
    items: []Item,
    tms1: []lu16,
    hms: []lu16,
    tms2: []lu16,
    static_pokemons: []*script.Command,
    pokeball_items: []PokeballItem,

    wild_pokemons: nds.fs.Fs,
    pokemons: nds.fs.Fs,
    scripts: nds.fs.Fs,
    evolutions: nds.fs.Fs,
    level_up_moves: nds.fs.Fs,
    parties: nds.fs.Fs,

    pub fn fromRom(allocator: *mem.Allocator, nds_rom: *nds.Rom) !Game {
        try nds_rom.decodeArm9();
        const header = nds_rom.header();
        const arm9 = nds_rom.arm9();
        const file_system = nds_rom.fileSystem();

        const info = try getOffsets(&header.gamecode);
        const hm_tm_prefix_index = mem.indexOf(u8, arm9, offsets.hm_tm_prefix) orelse return error.CouldNotFindTmsOrHms;
        const hm_tm_index = hm_tm_prefix_index + offsets.hm_tm_prefix.len;
        const hm_tm_len = (offsets.tm_count + offsets.hm_count) * @sizeOf(u16);
        const hm_tms = mem.bytesAsSlice(lu16, arm9[hm_tm_index..][0..hm_tm_len]);
        const scripts = try getNarc(file_system, info.scripts);

        const commands = try findScriptCommands(info.version, scripts, allocator);
        errdefer {
            allocator.free(commands.static_pokemons);
            allocator.free(commands.pokeball_items);
        }

        return Game{
            .version = info.version,
            .allocator = allocator,
            .starters = blk: {
                var res: [3][]*lu16 = undefined;
                var filled: usize = 0;
                errdefer for (res[0..filled]) |item|
                    allocator.free(item);

                for (info.starters) |offs, i| {
                    res[i] = try allocator.alloc(*lu16, offs.len);
                    filled += 1;

                    for (offs) |offset, j| {
                        const fat = scripts.fat[offset.file];
                        const file_data = scripts.data[fat.start.value()..fat.end.value()];
                        res[i][j] = mem.bytesAsValue(lu16, file_data[offset.offset..][0..2]);
                    }
                }

                break :blk res;
            },
            .moves = try (try getNarc(file_system, info.moves)).toSlice(0, Move),
            .trainers = try (try getNarc(file_system, info.trainers)).toSlice(1, Trainer),
            .items = try (try getNarc(file_system, info.itemdata)).toSlice(0, Item),
            .tms1 = hm_tms[0..92],
            .hms = hm_tms[92..98],
            .tms2 = hm_tms[98..],
            .static_pokemons = commands.static_pokemons,
            .pokeball_items = commands.pokeball_items,

            .wild_pokemons = try getNarc(file_system, info.wild_pokemons),
            .parties = try getNarc(file_system, info.parties),
            .pokemons = try getNarc(file_system, info.pokemons),
            .evolutions = try getNarc(file_system, info.evolutions),
            .level_up_moves = try getNarc(file_system, info.level_up_moves),
            .scripts = scripts,
        };
    }

    pub fn deinit(game: Game) void {
        for (game.starters) |starter_ptrs|
            game.allocator.free(starter_ptrs);
        game.allocator.free(game.static_pokemons);
        game.allocator.free(game.pokeball_items);
    }

    const ScriptCommands = struct {
        static_pokemons: []*script.Command,
        pokeball_items: []PokeballItem,
    };

    fn findScriptCommands(version: common.Version, scripts: nds.fs.Fs, allocator: *mem.Allocator) !ScriptCommands {
        if (version == .black or version == .white) {
            // We don't support decoding scripts for hg/ss yet.
            return ScriptCommands{
                .static_pokemons = &[_]*script.Command{},
                .pokeball_items = &[_]PokeballItem{},
            };
        }

        var static_pokemons = std.ArrayList(*script.Command).init(allocator);
        errdefer static_pokemons.deinit();
        var pokeball_items = std.ArrayList(PokeballItem).init(allocator);
        errdefer pokeball_items.deinit();

        var script_offsets = std.ArrayList(isize).init(allocator);
        defer script_offsets.deinit();

        for (scripts.fat) |fat, script_i| {
            const script_data = scripts.data[fat.start.value()..fat.end.value()];
            defer script_offsets.resize(0) catch unreachable;

            for (script.getScriptOffsets(script_data)) |relative_offset, i| {
                const offset = relative_offset.value() + @intCast(isize, i + 1) * @sizeOf(lu32);
                if (@intCast(isize, script_data.len) < offset)
                    continue;
                if (offset < 0)
                    continue;
                try script_offsets.append(offset);
            }

            // The variable 0x8008 is the variables that stores items given
            // from Pokéballs.
            var var_800C: ?*lu16 = null;

            var offset_i: usize = 0;
            while (offset_i < script_offsets.items.len) : (offset_i += 1) {
                const offset = script_offsets.items[offset_i];
                if (@intCast(isize, script_data.len) < offset)
                    return error.Error;
                if (offset < 0)
                    return error.Error;

                var decoder = script.CommandDecoder{
                    .bytes = script_data,
                    .i = @intCast(usize, offset),
                };
                while (decoder.next() catch continue) |command| {
                    // If we hit var 0x800C, the var_800C_tmp will be set and
                    // var_800C will become var_800C_tmp. Then the next iteration
                    // of this loop will set var_8008 to null again. This allows us
                    // to store this state for only the next iteration of the loop.
                    var var_800C_tmp: ?*lu16 = null;
                    defer var_800C = var_800C_tmp;

                    switch (command.tag) {
                        // TODO: We're not finding any given items yet
                        .wild_battle => try static_pokemons.append(command),

                        // In scripts, field items are two set_var_eq_val commands
                        // followed by a jump to the code that gives this item:
                        //   set_var_eq_val 0x800C // Item given
                        //   set_var_eq_val 0x800D // Amount of items
                        //   jump ???
                        .set_var_eq_val => switch (command.data().set_var_eq_val.container.value()) {
                            0x800C => var_800C_tmp = &command.data().set_var_eq_val.value,
                            0x800D => if (var_800C) |item| {
                                const amount = &command.data().set_var_eq_val.value;
                                try pokeball_items.append(PokeballItem{
                                    .item = item,
                                    .amount = amount,
                                });
                            },
                            else => {},
                        },
                        .jump => {
                            const off = command.data().jump.offset.value();
                            if (off >= 0)
                                try script_offsets.append(off + @intCast(isize, decoder.i));
                        },
                        .@"if" => {
                            const off = command.data().@"if".offset.value();
                            if (off >= 0)
                                try script_offsets.append(off + @intCast(isize, decoder.i));
                        },
                        else => {},
                    }
                }
            }
        }

        return ScriptCommands{
            .static_pokemons = static_pokemons.toOwnedSlice(),
            .pokeball_items = pokeball_items.toOwnedSlice(),
        };
    }

    fn nodeAsFile(node: nds.fs.Narc.Node) !*nds.fs.Narc.File {
        switch (node.kind) {
            .file => |file| return file,
            .folder => return error.NotFile,
        }
    }

    fn getOffsets(gamecode: []const u8) !offsets.Info {
        for (offsets.infos) |info| {
            //if (!mem.eql(u8, info.game_title, game_title))
            //    continue;
            if (!mem.eql(u8, &info.gamecode, gamecode))
                continue;

            return info;
        }

        return error.NotGen5Game;
    }

    pub fn getNarc(fs: nds.fs.Fs, path: []const u8) !nds.fs.Fs {
        const file = try fs.openFileData(nds.fs.root, path);
        return try nds.fs.Fs.fromNarc(file);
    }
};

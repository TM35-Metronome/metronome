const std = @import("std");

const debug = std.debug;
const math = std.math;
const mem = std.mem;

pub const Patch = struct {
    offset: usize,
    replacement: []const u8,
};

pub fn patch(memory: []u8, patchs: []const Patch) void {
    for (patchs) |p|
        mem.copy(u8, memory[p.offset..], p.replacement);
}

pub const PatchIterator = struct {
    old: []const u8,
    new: []const u8,
    i: usize = 0,

    pub fn next(it: *PatchIterator) ?Patch {
        const end_it = math.min(it.old.len, it.new.len);

        const chunk_size = @sizeOf(u256);
        while (it.i + chunk_size <= end_it) : (it.i += chunk_size) {
            const new_chunk = @ptrCast(*align(1) const u256, it.new[it.i..][0..chunk_size]).*;
            const old_chunk = @ptrCast(*align(1) const u256, it.old[it.i..][0..chunk_size]).*;
            if (new_chunk != old_chunk)
                break;
        }

        while (it.i < end_it) : (it.i += 1) {
            if (it.new[it.i] != it.old[it.i])
                break;
        }

        const start = it.i;
        while (it.i < end_it) : (it.i += 1) {
            if (it.new[it.i] == it.old[it.i])
                break;
        }

        const end = if (it.i == it.old.len) it.new.len else it.i;
        if (start == end)
            return null;
        return Patch{
            .offset = start,
            .replacement = it.new[start..end],
        };
    }
};

pub const Version = enum {
    red,
    blue,
    yellow,

    gold,
    silver,
    crystal,

    ruby,
    sapphire,
    emerald,
    fire_red,
    leaf_green,

    diamond,
    pearl,
    platinum,
    heart_gold,
    soul_silver,

    black,
    white,
    black2,
    white2,

    x,
    y,
    omega_ruby,
    alpha_sapphire,

    sun,
    moon,
    ultra_sun,
    ultra_moon,

    pub fn humanString(version: Version) []const u8 {
        return switch (version) {
            .red => "Red",
            .blue => "Blue",
            .yellow => "Yellow",
            .gold => "Gold",
            .silver => "Silver",
            .crystal => "Crystal",
            .ruby => "Ruby",
            .sapphire => "Sapphire",
            .emerald => "Emerald",
            .fire_red => "Fire Red",
            .leaf_green => "Leaf Green",
            .diamond => "Diamond",
            .pearl => "Pearl",
            .platinum => "Platinum",
            .heart_gold => "Heart Gold",
            .soul_silver => "Soul Silver",
            .black => "Black",
            .white => "White",
            .black2 => "Black 2",
            .white2 => "White 2",
            .x => "X",
            .y => "Y",
            .omega_ruby => "Omega Ruby",
            .alpha_sapphire => "Alpha Sapphire",
            .sun => "Sun",
            .moon => "Moon",
            .ultra_sun => "Ultra Sun",
            .ultra_moon => "Ultra Moon",
        };
    }
};

pub const PartyType = enum(u8) {
    none = 0b00,
    item = 0b10,
    moves = 0b01,
    both = 0b11,

    pub fn haveItem(t: PartyType) bool {
        return t == .item or t == .both;
    }

    pub fn haveMoves(t: PartyType) bool {
        return t == .moves or t == .both;
    }
};

pub const Stats = extern struct {
    hp: u8,
    attack: u8,
    defense: u8,
    speed: u8,
    sp_attack: u8,
    sp_defense: u8,

    comptime {
        std.debug.assert(@sizeOf(Stats) == 6);
    }
};

pub const MoveCategory = enum(u8) {
    physical = 0x00,
    status = 0x01,
    special = 0x02,
};

pub const GrowthRate = enum(u8) {
    medium_fast = 0x00,
    erratic = 0x01,
    fluctuating = 0x02,
    medium_slow = 0x03,
    fast = 0x04,
    slow = 0x05,
};

pub const EggGroup = enum(u8) {
    invalid = 0x00, // TODO: Figure out if there is a 0x00 egg group
    monster = 0x01,
    water1 = 0x02,
    bug = 0x03,
    flying = 0x04,
    field = 0x05,
    fairy = 0x06,
    grass = 0x07,
    human_like = 0x08,
    water3 = 0x09,
    mineral = 0x0A,
    amorphous = 0x0B,
    water2 = 0x0C,
    ditto = 0x0D,
    dragon = 0x0E,
    undiscovered = 0x0F,
    _,
};

pub const ColorKind = enum(u7) {
    red = 0x00,
    blue = 0x01,
    yellow = 0x02,
    green = 0x03,
    black = 0x04,
    brown = 0x05,
    purple = 0x06,
    gray = 0x07,
    white = 0x08,
    pink = 0x09,
    green2 = 0x0A,
};

pub const Color = packed struct {
    color: ColorKind,
    flip: bool,
};

// Common between gen3-4
pub const EvoMethod = enum(u8) {
    unused = 0x00,
    friend_ship = 0x01,
    friend_ship_during_day = 0x02,
    friend_ship_during_night = 0x03,
    level_up = 0x04,
    trade = 0x05,
    trade_holding_item = 0x06,
    use_item = 0x07,
    attack_gth_defense = 0x08,
    attack_eql_defense = 0x09,
    attack_lth_defense = 0x0A,
    personality_value1 = 0x0B,
    personality_value2 = 0x0C,
    level_up_may_spawn_pokemon = 0x0D,
    level_up_spawn_if_cond = 0x0E,
    beauty = 0x0F,
    use_item_on_male = 0x10,
    use_item_on_female = 0x11,
    level_up_holding_item_during_daytime = 0x12,
    level_up_holding_item_during_the_night = 0x13,
    level_up_knowning_move = 0x14,
    level_up_with_other_pokemon_in_party = 0x15,
    level_up_male = 0x16,
    level_up_female = 0x17,
    level_up_in_special_magnetic_field = 0x18,
    level_up_near_moss_rock = 0x19,
    level_up_near_ice_rock = 0x1A,
    _,
};

// TODO: Figure out if the this have the same layout in all games that have it.
//       They probably have, so let's assume that for now and if a bug
//       is ever encountered related to this, we figure it out.
pub const EvYield = packed struct {
    hp: u2,
    attack: u2,
    defense: u2,
    speed: u2,
    sp_attack: u2,
    sp_defense: u2,

    comptime {
        std.debug.assert(@sizeOf(EvYield) == 2);
    }
};

pub const TypeEffectiveness = packed struct {
    attacker: u8,
    defender: u8,
    multiplier: u8,
};

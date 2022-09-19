const rom = @import("../rom.zig");
const script = @import("../script.zig");
const std = @import("std");

const builtin = std.builtin;
const mem = std.mem;

const li32 = rom.int.li32;
const lu16 = rom.int.lu16;
const lu32 = rom.int.lu32;

pub fn getScriptOffsets(data: []const u8) []const li32 {
    var len: usize = 0;
    while (true) : (len += 1) {
        const rest = data[len * 4 ..];
        if (rest.len < 4 or (rest[0] == 0x13 and rest[1] == 0xfd))
            break;
    }
    return mem.bytesAsSlice(li32, data[0 .. len * 4]);
}

pub const CommandDecoder = script.CommandDecoder(Command, struct {
    fn isEnd(cmd: Command) bool {
        switch (cmd.kind) {
            .end,
            .jump,
            .end_function,
            => return true,
            else => return false,
        }
    }
}.isEnd);

pub fn expectNext(decoder: *CommandDecoder, kind: Command.Kind) ?*align(1) Command {
    const command = (decoder.next() catch return null) orelse return null;
    if (command.kind != kind)
        return null;
    return command;
}

// https://pastebin.com/QPrYmFwY
pub const Command = extern union {
    kind: Kind,
    nop1: Arg0,
    nop2: Arg0,
    end: Arg0,
    return_after_delay: Arg1(lu16),
    call_routine: CallRoutine,
    end_function: Arg1(lu16),
    logic06: Arg1(lu16),
    logic07: Arg1(lu16),
    compare_to: CompareTo,
    store_var: StoreVar,
    clear_var: ClearVar,
    unknown_0b: Unknown_0B,
    unknown_0c: Unknown_0C,
    unknown_0d: Unknown_0D,
    unknown_0e: Unknown_0E,
    unknown_0f: Unknown_0F,
    store_flag: StoreFlag,
    condition: Condition,
    unknown_12: Unknown_12,
    unknown_13: Unknown_13,
    unknown_14: Unknown_14,
    unknown_16: Unknown_16,
    unknown_17: Unknown_17,
    compare: Compare,
    call_std: CallStd,
    return_std: Arg0,
    jump: Jump,
    @"if": If,
    unknown_21: Unknown_21,
    unknown_22: Unknown_22,
    set_flag: SetFlag,
    clear_flag: ClearFlag,
    set_var_flag_status: SetVarFlagStatus,
    set_var_26: SetVar26,
    set_var_27: SetVar27,
    set_var_eq_val: SetVarEqVal,
    set_var_29: SetVar29,
    set_var_2a: SetVar2A,
    set_var_2b: SetVar2B,
    dir_vars: Arg2(lu16, lu16),
    unknown_2d: Unknown_2D,
    lock_all: Arg0,
    unlock_all: Arg0,
    wait_moment: Arg0,
    wait_button: Arg0,
    musical_message: MusicalMessage,
    event_grey_message: EventGreyMessage,
    close_musical_message: Arg0,
    closed_event_grey_message: Arg0,
    bubble_message: BubbleMessage,
    close_bubble_message: Arg0,
    show_message_at: ShowMessageAt,
    close_show_message_at: Arg0,
    message: Message,
    message2: Message2,
    close_message_k_p: Arg0,
    close_message_k_p2: Arg0,
    money_box: MoneyBox,
    close_money_box: Arg0,
    update_money_box: Arg0,
    bordered_message: BorderedMessage,
    close_bordered_message: Arg0,
    paper_message: PaperMessage,
    close_paper_message: Arg0,
    yes_no: YesNo,
    message3: Message3,
    double_message: DoubleMessage,
    angry_message: AngryMessage,
    close_angry_message: Arg0,
    set_var_hero: SetVarHero,
    set_var_item: SetVarItem,
    unknown_4e: unknown_4E,
    set_var_item2: SetVarItem2,
    set_var_item3: SetVarItem3,
    set_var_move: SetVarMove,
    set_var_bag: SetVarBag,
    set_var_party_poke: SetVarPartyPoke,
    set_var_party_poke2: SetVarPartyPoke2,
    set_var_unknown: SetVar_Unknown,
    set_var_type: SetVarType,
    set_var_poke: SetVarPoke,
    set_var_poke2: SetVarPoke2,
    set_var_location: SetVarLocation,
    set_var_poke_nick: SetVarPokeNick,
    set_var_unknown2: SetVar_Unknown2,
    set_var_store_value5_c: SetVarStoreValue5C,
    set_var_musical_info: SetVarMusicalInfo,
    set_var_nations: SetVarNations,
    set_var_activities: SetVarActivities,
    set_var_power: SetVarPower,
    set_var_trainer_type: SetVarTrainerType,
    set_var_trainer_type2: SetVarTrainerType2,
    set_var_general_word: SetVarGeneralWord,
    apply_movement: ApplyMovement,
    wait_movement: Arg0,
    store_hero_position: StoreHeroPosition,
    unknown_67: Unknown_67,
    store_hero_position2: StoreHeroPosition2,
    store_npc_position: StoreNPCPosition,
    unknown_6a: Unknown_6A,
    add_npc: AddNPC,
    remove_npc: RemoveNPC,
    set_o_w_position: SetOWPosition,
    unknown_6e: Arg1(lu16),
    unknown_6f: Arg1(lu16),
    unknown_70: Unknown_70,
    unknown_71: Unknown_71,
    unknown_72: Unknown_72,
    unknown_73: Unknown_73,
    face_player: Arg0,
    release: Release,
    release_all: Arg0,
    lock_77: Lock,
    unknown_78: Unknown_78,
    unknown_79: Unknown_79,
    move_npc_to: MoveNPCTo,
    unknown_7c: Unknown_7C,
    unknown_7d: Unknown_7D,
    teleport_up_npc: TeleportUpNPC,
    unknown_7f: Unknown_7F,
    unknown_80: Arg1(lu16),
    unknown_81: Arg0,
    unknown_82: Unknown_82,
    set_var83: SetVar83,
    set_var84: SetVar84,
    single_trainer_battle: SingleTrainerBattle,
    double_trainer_battle: DoubleTrainerBattle,
    unknown_87: Unknown_87,
    unknown_88: Unknown_88,
    unknown_8a: Unknown_8A,
    play_trainer_music: PlayTrainerMusic,
    end_battle: Arg0,
    store_battle_result: StoreBattleResult,
    unknown_179: Arg0,
    unknown_17a: Arg0,
    unknown_17b: Arg1(lu16),
    unknown_17c: Arg1(lu16),
    set_status_cg: Arg1(lu16),
    show_cg: Arg1(lu16),
    call_screen_animation: Arg1(lu16),
    disable_trainer: Arg0,
    d_var90: DVar90,
    d_var92: DVar92,
    d_var93: DVar93,
    trainer_battle: TrainerBattle,
    deactivate_trainer_i_d: DeactivateTrainerID,
    unknown_96: Unknown_96,
    store_active_trainer_i_d: StoreActiveTrainerID,
    change_music: ChangeMusic,
    fade_to_default_music: Arg0,
    unknown_9f: Arg0,
    unknown_a2: Unknown_A2,
    unknown_a3: Arg1(lu16),
    unknown_a4: Arg1(lu16),
    unknown_a5: Unknown_A5,
    play_sound: PlaySound,
    wait_sound_a7: Arg0,
    wait_sound: Arg0,
    play_fanfare: PlayFanfare,
    wait_fanfare: Arg0,
    play_cry: PlayCry,
    wait_cry: Arg0,
    set_text_script_message: SetTextScriptMessage,
    close_multi: Arg0,
    unknown_b1: Arg0,
    multi2: Multi2,
    fade_screen: FadeScreen,
    reset_screen: ResetScreen,
    screen_b5: Screen_B5,
    take_item: TakeItem,
    check_item_bag_space: CheckItemBagSpace,
    check_item_bag_number: CheckItemBagNumber,
    store_item_count: StoreItemCount,
    unknown_ba: Unknown_BA,
    unknown_bb: Unknown_BB,
    unknown_bc: Arg1(lu16),
    warp: Warp,
    teleport_warp: TeleportWarp,
    fall_warp: FallWarp,
    fast_warp: FastWarp,
    union_warp: Arg0,
    teleport_warp2: TeleportWarp2,
    surf_animation: Arg0,
    special_animation: Arg1(lu16),
    special_animation2: SpecialAnimation2,
    call_animation: CallAnimation,
    store_random_number: StoreRandomNumber,
    store_var_item: Arg1(lu16),
    store_var_cd: Arg1(lu16),
    store_var_ce: Arg1(lu16),
    store_var_cf: Arg1(lu16),
    store_date: StoreDate,
    store_d1: Store_D1,
    store_d2: Arg1(lu16),
    store_d3: Arg1(lu16),
    store_birth_day: StoreBirthDay,
    store_badge: StoreBadge,
    set_badge: SetBadge,
    store_badge_number: StoreBadgeNumber,
    store_version: Arg1(lu16),
    store_gender: Arg1(lu16),
    activate_key_item: Arg1(lu16),
    unknown_f9: Arg1(lu16),
    take_money: TakeMoney,
    check_money: CheckMoney,
    store_party_species: Arg2(lu16, lu16),
    store_pokemon_form_number: Arg2(lu16, lu16),
    store_party_number_minimum: StorePartyNumberMinimum,
    give_pokemon_1: GivePokemon1,
    give_pokemon_2: GivePokemon2,
    give_pokemon_3: GivePokemon3,
    badge_animation: Arg1(lu16),
    unknown_125: Arg4(lu16, lu16, lu16, lu16),
    unknown_127: Arg4(lu16, lu16, lu16, lu16),
    unknown_128: Arg1(lu16),
    unknown_129: Arg2(lu16, lu16),
    unknown_12A: Arg1(lu16),
    unknown_12D: Arg4(lu16, lu16, lu16, lu16),
    unknown_134: Arg0,
    unknown_13F: Arg0,
    stop_camera_event: Arg0,
    lock_camera: Arg0,
    move_camera: MoveCamera,
    unknown_144: Arg1(lu16),
    end_camera_event: Arg0,
    start_pokemon_musical: Arg2(u8, lu16),
    check_pokemon_musical_functions: Arg3(u8, lu16, lu16),
    pokemon_menu_musical_functions: Arg4(lu16, lu16, lu16, lu16),
    choose_pokemon_musical: Arg2(lu16, lu16),
    unknown_182: Arg1(lu16),
    unknown_186: Arg1(lu16),
    unknown_187: Arg1(lu16),
    unknown_188: Arg1(lu16),
    unknown_189: Arg1(lu16),
    unknown_1D8: Arg2(lu16, lu16),
    unknown_1C2: Arg2(lu16, lu16),
    end_event_bc: Arg0,
    store_trainer_id: Arg2(lu16, lu16),
    unknown_1C7: Arg0,
    store_var_message: Arg2(lu16, lu16),
    boot_p_c_sound: Arg0,
    unknown_136: Arg1(lu16),
    check_wireless: Arg1(lu16),
    release_camera: Arg0,
    reset_camera: ResetCamera,
    call_end: Arg0,
    call_start: Arg0,
    liberty_ship_anm: Arg2(lu16, lu16),
    open_interpoke: Arg2(lu16, lu16),
    wild_battle: WildBattle,
    wild_battle_store_result: WildBattleStoreResult,
    screen_function: Arg0,
    fade_from_black: Arg0,
    fade_into_black: Arg0,
    fade_from_white: Arg0,
    fade_into_white: Arg0,
    unknown_1b5: Arg0,
    unknown_1b7: Arg1(lu16),
    unknown_1b8: Arg1(lu16),
    unknown_1EA: Arg4(lu16, lu16, lu16, lu16),
    switch_ow_position: SwitchOwPosition,
    dream_world_function: Arg4(lu16, lu16, lu16, lu16),
    dream_world_function2: Arg4(lu16, lu16, lu16, lu16),
    show_dream_world_furniture: Arg2(lu16, lu16),
    check_item_interesting_bag: Arg2(lu16, lu16),
    unknown_229: Arg2(lu16, lu16),
    check_send_save_cg: Arg2(lu16, lu16),
    unknown_246: Arg1(lu16),
    unknown_24c: Arg1(lu16),
    lock_24f: Arg0,
    give_pokemon_4: GivePokemon4,

    comptime {
        std.debug.assert(@sizeOf(Command) == 24);
    }

    pub const Kind = enum(u16) {
        nop1 = lu16.init(0x00).value(),
        nop2 = lu16.init(0x01).value(),
        end = lu16.init(0x02).value(),
        return_after_delay = lu16.init(0x03).value(),
        call_routine = lu16.init(0x04).value(),
        end_function = lu16.init(0x05).value(),
        logic06 = lu16.init(0x06).value(),
        logic07 = lu16.init(0x07).value(),
        compare_to = lu16.init(0x08).value(),
        store_var = lu16.init(0x09).value(),
        clear_var = lu16.init(0x0A).value(),
        unknown_0b = lu16.init(0x0B).value(),
        unknown_0c = lu16.init(0x0C).value(),
        unknown_0d = lu16.init(0x0D).value(),
        unknown_0e = lu16.init(0x0E).value(),
        unknown_0f = lu16.init(0x0F).value(),
        store_flag = lu16.init(0x10).value(),
        condition = lu16.init(0x11).value(),
        unknown_12 = lu16.init(0x12).value(),
        unknown_13 = lu16.init(0x13).value(),
        unknown_14 = lu16.init(0x14).value(),
        unknown_16 = lu16.init(0x16).value(),
        unknown_17 = lu16.init(0x17).value(),
        compare = lu16.init(0x19).value(),
        call_std = lu16.init(0x1C).value(),
        return_std = lu16.init(0x1D).value(),
        jump = lu16.init(0x1E).value(),
        @"if" = lu16.init(0x1F).value(),
        unknown_21 = lu16.init(0x21).value(),
        unknown_22 = lu16.init(0x22).value(),
        set_flag = lu16.init(0x23).value(),
        clear_flag = lu16.init(0x24).value(),
        set_var_flag_status = lu16.init(0x25).value(),
        set_var_26 = lu16.init(0x26).value(),
        set_var_27 = lu16.init(0x27).value(),
        set_var_eq_val = lu16.init(0x28).value(),
        set_var_29 = lu16.init(0x29).value(),
        set_var_2a = lu16.init(0x2A).value(),
        set_var_2b = lu16.init(0x2B).value(),
        dir_vars = lu16.init(0x2C).value(),
        unknown_2d = lu16.init(0x2D).value(),
        lock_all = lu16.init(0x2E).value(),
        unlock_all = lu16.init(0x2F).value(),
        wait_moment = lu16.init(0x30).value(),
        wait_button = lu16.init(0x32).value(),
        musical_message = lu16.init(0x33).value(),
        event_grey_message = lu16.init(0x34).value(),
        close_musical_message = lu16.init(0x35).value(),
        closed_event_grey_message = lu16.init(0x36).value(),
        bubble_message = lu16.init(0x38).value(),
        close_bubble_message = lu16.init(0x39).value(),
        show_message_at = lu16.init(0x3A).value(),
        close_show_message_at = lu16.init(0x3B).value(),
        message = lu16.init(0x3C).value(),
        message2 = lu16.init(0x3D).value(),
        close_message_k_p = lu16.init(0x3E).value(),
        close_message_k_p2 = lu16.init(0x3F).value(),
        money_box = lu16.init(0x40).value(),
        close_money_box = lu16.init(0x41).value(),
        update_money_box = lu16.init(0x42).value(),
        bordered_message = lu16.init(0x43).value(),
        close_bordered_message = lu16.init(0x44).value(),
        paper_message = lu16.init(0x45).value(),
        close_paper_message = lu16.init(0x46).value(),
        yes_no = lu16.init(0x47).value(),
        message3 = lu16.init(0x48).value(),
        double_message = lu16.init(0x49).value(),
        angry_message = lu16.init(0x4A).value(),
        close_angry_message = lu16.init(0x4B).value(),
        set_var_hero = lu16.init(0x4C).value(),
        set_var_item = lu16.init(0x4D).value(),
        unknown_4e = lu16.init(0x4E).value(),
        set_var_item2 = lu16.init(0x4F).value(),
        set_var_item3 = lu16.init(0x50).value(),
        set_var_move = lu16.init(0x51).value(),
        set_var_bag = lu16.init(0x52).value(),
        set_var_party_poke = lu16.init(0x53).value(),
        set_var_party_poke2 = lu16.init(0x54).value(),
        set_var_unknown = lu16.init(0x55).value(),
        set_var_type = lu16.init(0x56).value(),
        set_var_poke = lu16.init(0x57).value(),
        set_var_poke2 = lu16.init(0x58).value(),
        set_var_location = lu16.init(0x59).value(),
        set_var_poke_nick = lu16.init(0x5A).value(),
        set_var_unknown2 = lu16.init(0x5B).value(),
        set_var_store_value5_c = lu16.init(0x5C).value(),
        set_var_musical_info = lu16.init(0x5D).value(),
        set_var_nations = lu16.init(0x5E).value(),
        set_var_activities = lu16.init(0x5F).value(),
        set_var_power = lu16.init(0x60).value(),
        set_var_trainer_type = lu16.init(0x61).value(),
        set_var_trainer_type2 = lu16.init(0x62).value(),
        set_var_general_word = lu16.init(0x63).value(),
        apply_movement = lu16.init(0x64).value(),
        wait_movement = lu16.init(0x65).value(),
        store_hero_position = lu16.init(0x66).value(),
        unknown_67 = lu16.init(0x67).value(),
        store_hero_position2 = lu16.init(0x68).value(),
        store_npc_position = lu16.init(0x69).value(),
        unknown_6a = lu16.init(0x6A).value(),
        add_npc = lu16.init(0x6B).value(),
        remove_npc = lu16.init(0x6C).value(),
        set_o_w_position = lu16.init(0x6D).value(),
        unknown_6e = lu16.init(0x6E).value(),
        unknown_6f = lu16.init(0x6F).value(),
        unknown_70 = lu16.init(0x70).value(),
        unknown_71 = lu16.init(0x71).value(),
        unknown_72 = lu16.init(0x72).value(),
        unknown_73 = lu16.init(0x73).value(),
        face_player = lu16.init(0x74).value(),
        release = lu16.init(0x75).value(),
        release_all = lu16.init(0x76).value(),
        lock_77 = lu16.init(0x77).value(),
        unknown_78 = lu16.init(0x78).value(),
        unknown_79 = lu16.init(0x79).value(),
        move_npc_to = lu16.init(0x7B).value(),
        unknown_7c = lu16.init(0x7C).value(),
        unknown_7d = lu16.init(0x7D).value(),
        teleport_up_npc = lu16.init(0x7E).value(),
        unknown_7f = lu16.init(0x7F).value(),
        unknown_80 = lu16.init(0x80).value(),
        unknown_81 = lu16.init(0x81).value(),
        unknown_82 = lu16.init(0x82).value(),
        set_var83 = lu16.init(0x83).value(),
        set_var84 = lu16.init(0x84).value(),
        single_trainer_battle = lu16.init(0x85).value(),
        double_trainer_battle = lu16.init(0x86).value(),
        unknown_87 = lu16.init(0x87).value(),
        unknown_88 = lu16.init(0x88).value(),
        unknown_8a = lu16.init(0x8A).value(),
        play_trainer_music = lu16.init(0x8B).value(),
        end_battle = lu16.init(0x8C).value(),
        store_battle_result = lu16.init(0x8D).value(),
        disable_trainer = lu16.init(0x8E).value(),
        d_var90 = lu16.init(0x90).value(),
        d_var92 = lu16.init(0x92).value(),
        d_var93 = lu16.init(0x93).value(),
        trainer_battle = lu16.init(0x94).value(),
        deactivate_trainer_i_d = lu16.init(0x95).value(),
        unknown_96 = lu16.init(0x96).value(),
        store_active_trainer_i_d = lu16.init(0x97).value(),
        change_music = lu16.init(0x98).value(),
        fade_to_default_music = lu16.init(0x9E).value(),
        unknown_9f = lu16.init(0x9F).value(),
        unknown_a2 = lu16.init(0xA2).value(),
        unknown_a3 = lu16.init(0xA3).value(),
        unknown_a4 = lu16.init(0xA4).value(),
        unknown_a5 = lu16.init(0xA5).value(),
        play_sound = lu16.init(0xA6).value(),
        wait_sound_a7 = lu16.init(0xA7).value(),
        wait_sound = lu16.init(0xA8).value(),
        play_fanfare = lu16.init(0xA9).value(),
        wait_fanfare = lu16.init(0xAA).value(),
        play_cry = lu16.init(0xAB).value(),
        wait_cry = lu16.init(0xAC).value(),
        set_text_script_message = lu16.init(0xAF).value(),
        close_multi = lu16.init(0xB0).value(),
        unknown_b1 = lu16.init(0xB1).value(),
        multi2 = lu16.init(0xB2).value(),
        fade_screen = lu16.init(0xB3).value(),
        reset_screen = lu16.init(0xB4).value(),
        screen_b5 = lu16.init(0xB5).value(),
        take_item = lu16.init(0xB6).value(),
        check_item_bag_space = lu16.init(0xB7).value(),
        check_item_bag_number = lu16.init(0xB8).value(),
        store_item_count = lu16.init(0xB9).value(),
        unknown_ba = lu16.init(0xBA).value(),
        unknown_bb = lu16.init(0xBB).value(),
        unknown_bc = lu16.init(0xBC).value(),
        warp = lu16.init(0xBE).value(),
        teleport_warp = lu16.init(0xBF).value(),
        fall_warp = lu16.init(0xC1).value(),
        fast_warp = lu16.init(0xC2).value(),
        union_warp = lu16.init(0xC3).value(),
        teleport_warp2 = lu16.init(0xC4).value(),
        surf_animation = lu16.init(0xC5).value(),
        special_animation = lu16.init(0xC6).value(),
        special_animation2 = lu16.init(0xC7).value(),
        call_animation = lu16.init(0xC8).value(),
        store_random_number = lu16.init(0xCB).value(),
        store_var_item = lu16.init(0xCC).value(),
        store_var_cd = lu16.init(0xCD).value(),
        store_var_ce = lu16.init(0xCE).value(),
        store_var_cf = lu16.init(0xCF).value(),
        store_date = lu16.init(0xD0).value(),
        store_d1 = lu16.init(0xD1).value(),
        store_d2 = lu16.init(0xD2).value(),
        store_d3 = lu16.init(0xD3).value(),
        store_birth_day = lu16.init(0xD4).value(),
        store_badge = lu16.init(0xD5).value(),
        set_badge = lu16.init(0xD6).value(),
        store_badge_number = lu16.init(0xD7).value(),
        store_version = lu16.init(0xE0).value(),
        store_gender = lu16.init(0xE1).value(),
        activate_key_item = lu16.init(0xE7).value(),
        unknown_f9 = lu16.init(0xF9).value(),
        take_money = lu16.init(0xFA).value(),
        check_money = lu16.init(0xFB).value(),
        store_party_species = lu16.init(0xFE).value(),
        store_pokemon_form_number = lu16.init(0xFF).value(),
        store_party_number_minimum = lu16.init(0x103).value(),
        give_pokemon_1 = lu16.init(0x10C).value(),
        give_pokemon_2 = lu16.init(0x10E).value(),
        give_pokemon_3 = lu16.init(0x10F).value(),
        badge_animation = lu16.init(0x11E).value(),
        unknown_125 = lu16.init(0x125).value(),
        unknown_127 = lu16.init(0x127).value(),
        unknown_128 = lu16.init(0x128).value(),
        unknown_129 = lu16.init(0x129).value(),
        unknown_12A = lu16.init(0x12A).value(),
        unknown_12D = lu16.init(0x12D).value(),
        unknown_134 = lu16.init(0x134).value(),
        unknown_13F = lu16.init(0x13F).value(),
        stop_camera_event = lu16.init(0x140).value(),
        lock_camera = lu16.init(0x141).value(),
        move_camera = lu16.init(0x143).value(),
        unknown_144 = lu16.init(0x144).value(),
        end_camera_event = lu16.init(0x145).value(),
        start_pokemon_musical = lu16.init(0x167).value(),
        check_pokemon_musical_functions = lu16.init(0x169).value(),
        pokemon_menu_musical_functions = lu16.init(0x16B).value(),
        choose_pokemon_musical = lu16.init(0x16E).value(),
        unknown_182 = lu16.init(0x182).value(),
        unknown_186 = lu16.init(0x186).value(),
        unknown_187 = lu16.init(0x187).value(),
        unknown_188 = lu16.init(0x188).value(),
        unknown_189 = lu16.init(0x189).value(),
        unknown_1D8 = lu16.init(0x1D8).value(),
        unknown_1C2 = lu16.init(0x1C2).value(),
        end_event_bc = lu16.init(0x1C3).value(),
        store_trainer_id = lu16.init(0x1C4).value(),
        unknown_1C7 = lu16.init(0x1C7).value(),
        store_var_message = lu16.init(0x1C9).value(),
        boot_p_c_sound = lu16.init(0x130).value(),
        unknown_136 = lu16.init(0x136).value(),
        check_wireless = lu16.init(0x13B).value(),
        release_camera = lu16.init(0x142).value(),
        reset_camera = lu16.init(0x147).value(),
        call_end = lu16.init(0x14A).value(),
        call_start = lu16.init(0x14B).value(),
        liberty_ship_anm = lu16.init(0x154).value(),
        open_interpoke = lu16.init(0x155).value(),
        wild_battle = lu16.init(0x174).value(),
        wild_battle_store_result = lu16.init(0x178).value(),
        unknown_179 = lu16.init(0x179).value(),
        unknown_17a = lu16.init(0x17a).value(),
        unknown_17b = lu16.init(0x17b).value(),
        unknown_17c = lu16.init(0x17c).value(),
        set_status_cg = lu16.init(0x19B).value(),
        show_cg = lu16.init(0x19E).value(),
        call_screen_animation = lu16.init(0x19F).value(),
        screen_function = lu16.init(0x1B1).value(),
        fade_from_black = lu16.init(0x1AB).value(),
        fade_into_black = lu16.init(0x1AC).value(),
        fade_from_white = lu16.init(0x1AD).value(),
        fade_into_white = lu16.init(0x1AE).value(),
        unknown_1b5 = lu16.init(0x1b5).value(),
        unknown_1b7 = lu16.init(0x1b7).value(),
        unknown_1b8 = lu16.init(0x1b8).value(),
        unknown_1EA = lu16.init(0x1EA).value(),
        switch_ow_position = lu16.init(0x1EC).value(),
        dream_world_function = lu16.init(0x209).value(),
        dream_world_function2 = lu16.init(0x20A).value(),
        show_dream_world_furniture = lu16.init(0x20B).value(),
        check_item_interesting_bag = lu16.init(0x20E).value(),
        unknown_229 = lu16.init(0x229).value(),
        check_send_save_cg = lu16.init(0x23B).value(),
        unknown_246 = lu16.init(0x246).value(),
        unknown_24c = lu16.init(0x24c).value(),
        lock_24f = lu16.init(0x24f).value(),
        give_pokemon_4 = lu16.init(0x2ea).value(),
    };

    pub const Arg0 = packed struct {
        kind: Kind,
    };
    pub fn Arg1(comptime T: type) type {
        return packed struct {
            kind: Kind,
            arg: T,
        };
    }
    pub fn Arg2(comptime T1: type, comptime T2: type) type {
        return packed struct {
            kind: Kind,
            arg1: T1,
            args2: T2,
        };
    }
    pub fn Arg3(comptime T1: type, comptime T2: type, comptime T3: type) type {
        return packed struct {
            kind: Kind,
            arg1: T1,
            args2: T2,
            args3: T3,
        };
    }
    pub fn Arg4(comptime T1: type, comptime T2: type, comptime T3: type, comptime T4: type) type {
        return packed struct {
            kind: Kind,
            arg1: T1,
            args2: T2,
            args3: T3,
            args4: T4,
        };
    }
    pub const CallRoutine = packed struct {
        kind: Kind,
        offset: li32,
    };
    pub const CompareTo = packed struct {
        kind: Kind,
        value: lu16,
    };
    pub const StoreVar = packed struct {
        kind: Kind,
        @"var": lu16,
    };
    pub const ClearVar = packed struct {
        kind: Kind,
        @"var": lu16,
    };
    pub const Unknown_0B = packed struct {
        kind: Kind,
        value: lu16,
    };
    pub const Unknown_0C = packed struct {
        kind: Kind,
        value: lu16,
    };
    pub const Unknown_0D = packed struct {
        kind: Kind,
        value: lu16,
    };
    pub const Unknown_0E = packed struct {
        kind: Kind,
        value: lu16,
    };
    pub const Unknown_0F = packed struct {
        kind: Kind,
        value: lu16,
    };
    pub const StoreFlag = packed struct {
        kind: Kind,
        value: lu16,
    };
    pub const Condition = packed struct {
        kind: Kind,
        condition: lu16,
    };
    pub const Unknown_12 = packed struct {
        kind: Kind,
        value: lu16,
    };
    pub const Unknown_13 = packed struct {
        kind: Kind,
        value1: lu16,
        value2: lu16,
    };
    pub const Unknown_14 = packed struct {
        kind: Kind,
        value: lu16,
    };
    pub const Unknown_16 = packed struct {
        kind: Kind,
        value: lu16,
    };
    pub const Unknown_17 = packed struct {
        kind: Kind,
        value: lu16,
    };
    pub const Compare = packed struct {
        kind: Kind,
        value1: lu16,
        value2: lu16,
    };
    pub const CallStd = packed struct {
        kind: Kind,
        function: lu16,
    };
    pub const Jump = packed struct {
        kind: Kind,
        offset: li32,
    };
    pub const If = packed struct {
        kind: Kind,
        value: u8,
        offset: li32,
    };
    pub const Unknown_21 = packed struct {
        kind: Kind,
        value: lu16,
    };
    pub const Unknown_22 = packed struct {
        kind: Kind,
        value: lu16,
    };
    pub const SetFlag = packed struct {
        kind: Kind,
        value: lu16,
    };
    pub const ClearFlag = packed struct {
        kind: Kind,
        flag: lu16,
    };
    pub const SetVarFlagStatus = packed struct {
        kind: Kind,
        flag: lu16,
        status: lu16,
    };
    pub const SetVar26 = packed struct {
        kind: Kind,
        value1: lu16,
        value2: lu16,
    };
    pub const SetVar27 = packed struct {
        kind: Kind,
        value1: lu16,
        value2: lu16,
    };
    pub const SetVarEqVal = packed struct {
        kind: Kind,
        container: lu16,
        value: lu16,
    };
    pub const SetVar29 = packed struct {
        kind: Kind,
        container: lu16,
        value: lu16,
    };
    pub const SetVar2A = packed struct {
        kind: Kind,
        container: lu16,
        value: lu16,
    };
    pub const SetVar2B = packed struct {
        kind: Kind,
        value: lu16,
    };
    pub const Unknown_2D = packed struct {
        kind: Kind,
        value: lu16,
    };
    pub const MusicalMessage = packed struct {
        kind: Kind,
        id: lu16,
    };
    pub const EventGreyMessage = packed struct {
        kind: Kind,
        id: lu16,
        view: lu16,
    };
    pub const BubbleMessage = packed struct {
        kind: Kind,
        id: lu16,
        location: u8,
    };
    pub const ShowMessageAt = packed struct {
        kind: Kind,
        id: lu16,
        xcoord: lu16,
        ycoord: lu16,
        zcoord: lu16,
    };
    pub const Message = packed struct {
        kind: Kind,
        id: lu16,
        npc: lu16,
        position: lu16,
        type: lu16,
    };
    pub const Message2 = packed struct {
        kind: Kind,
        id: lu16,
        npc: lu16,
        position: lu16,
        type: lu16,
    };
    pub const MoneyBox = packed struct {
        kind: Kind,
        xcoord: lu16,
        ycoord: lu16,
    };
    pub const BorderedMessage = packed struct {
        kind: Kind,
        id: lu16,
        color: lu16,
    };
    pub const PaperMessage = packed struct {
        kind: Kind,
        id: lu16,
        transcoord: lu16,
    };
    pub const YesNo = packed struct {
        kind: Kind,
        yesno: lu16,
    };
    pub const Message3 = packed struct {
        kind: Kind,
        id: lu16,
        npc: lu16,
        position: lu16,
        type: lu16,
        unknown: lu16,
    };
    pub const DoubleMessage = packed struct {
        kind: Kind,
        idblack: lu16,
        idwhite: lu16,
        npc: lu16,
        position: lu16,
        type: lu16,
    };
    pub const AngryMessage = packed struct {
        kind: Kind,
        id: lu16,
        unknownbyte: u8,
        position: lu16,
    };
    pub const SetVarHero = packed struct {
        kind: Kind,
        arg: u8,
    };
    pub const SetVarItem = packed struct {
        kind: Kind,
        arg: u8,
        item: lu16,
    };
    pub const unknown_4E = packed struct {
        kind: Kind,
        arg1: u8,
        arg2: lu16,
        arg3: lu16,
        arg4: u8,
    };
    pub const SetVarItem2 = packed struct {
        kind: Kind,
        arg: u8,
        item: lu16,
    };
    pub const SetVarItem3 = packed struct {
        kind: Kind,
        arg: u8,
        item: lu16,
    };
    pub const SetVarMove = packed struct {
        kind: Kind,
        arg: u8,
        move: lu16,
    };
    pub const SetVarBag = packed struct {
        kind: Kind,
        arg: u8,
        item: lu16,
    };
    pub const SetVarPartyPoke = packed struct {
        kind: Kind,
        arg: u8,
        party_poke: lu16,
    };
    pub const SetVarPartyPoke2 = packed struct {
        kind: Kind,
        arg: u8,
        party_poke: lu16,
    };
    pub const SetVar_Unknown = packed struct {
        kind: Kind,
        arg: u8,
        value: lu16,
    };
    pub const SetVarType = packed struct {
        kind: Kind,
        arg: u8,
        type: lu16,
    };
    pub const SetVarPoke = packed struct {
        kind: Kind,
        arg: u8,
        poke: lu16,
    };
    pub const SetVarPoke2 = packed struct {
        kind: Kind,
        arg: u8,
        poke: lu16,
    };
    pub const SetVarLocation = packed struct {
        kind: Kind,
        arg: u8,
        location: lu16,
    };
    pub const SetVarPokeNick = packed struct {
        kind: Kind,
        arg: u8,
        poke: lu16,
    };
    pub const SetVar_Unknown2 = packed struct {
        kind: Kind,
        arg: u8,
        value: lu16,
    };
    pub const SetVarStoreValue5C = packed struct {
        kind: Kind,
        arg: u8,
        container: lu16,
        stat: lu16,
    };
    pub const SetVarMusicalInfo = packed struct {
        kind: Kind,
        arg: lu16,
        value: lu16,
    };
    pub const SetVarNations = packed struct {
        kind: Kind,
        arg: u8,
        value: lu16,
    };
    pub const SetVarActivities = packed struct {
        kind: Kind,
        arg: u8,
        value: lu16,
    };
    pub const SetVarPower = packed struct {
        kind: Kind,
        arg: u8,
        value: lu16,
    };
    pub const SetVarTrainerType = packed struct {
        kind: Kind,
        arg: u8,
        value: lu16,
    };
    pub const SetVarTrainerType2 = packed struct {
        kind: Kind,
        arg: u8,
        value: lu16,
    };
    pub const SetVarGeneralWord = packed struct {
        kind: Kind,
        arg: u8,
        value: lu16,
    };
    pub const ApplyMovement = packed struct {
        kind: Kind,
        npc: lu16,
        movementdata: lu32,
    };
    pub const StoreHeroPosition = packed struct {
        kind: Kind,
        xcoord: lu16,
        ycoord: lu16,
    };
    pub const Unknown_67 = packed struct {
        kind: Kind,
        value: lu16,
        value2: lu16,
    };
    pub const StoreHeroPosition2 = packed struct {
        kind: Kind,
        xcoord: lu16,
        ycoord: lu16,
    };
    pub const StoreNPCPosition = packed struct {
        kind: Kind,
        npc: lu16,
        xcoord: lu16,
        ycoord: lu16,
    };
    pub const Unknown_6A = packed struct {
        kind: Kind,
        npc: lu16,
        flag: lu16,
    };
    pub const AddNPC = packed struct {
        kind: Kind,
        npc: lu16,
    };
    pub const RemoveNPC = packed struct {
        kind: Kind,
        npc: lu16,
    };
    pub const SetOWPosition = packed struct {
        kind: Kind,
        npc: lu16,
        xcoord: lu16,
        ycoord: lu16,
        zcoord: lu16,
        direction: lu16,
    };
    pub const Unknown_70 = packed struct {
        kind: Kind,
        arg: lu16,
        arg2: lu16,
        arg3: lu16,
        arg4: lu16,
        arg5: lu16,
    };
    pub const Unknown_71 = packed struct {
        kind: Kind,
        arg: lu16,
        arg2: lu16,
        arg3: lu16,
    };
    pub const Unknown_72 = packed struct {
        kind: Kind,
        arg: lu16,
        arg2: lu16,
        arg3: lu16,
        arg4: lu16,
    };
    pub const Unknown_73 = packed struct {
        kind: Kind,
        arg: lu16,
        arg2: lu16,
    };
    pub const Release = packed struct {
        kind: Kind,
        npc: lu16,
    };
    pub const Lock = packed struct {
        kind: Kind,
        npc: lu16,
    };
    pub const Unknown_78 = packed struct {
        kind: Kind,
        @"var": lu16,
    };
    pub const Unknown_79 = packed struct {
        kind: Kind,
        npc: lu16,
        arg2: lu16,
        arg3: lu16,
    };
    pub const MoveNPCTo = packed struct {
        kind: Kind,
        npc: lu16,
        xcoord: lu16,
        ycoord: lu16,
        zcoord: lu16,
    };
    pub const Unknown_7C = packed struct {
        kind: Kind,
        arg: lu16,
        arg2: lu16,
        arg3: lu16,
        arg4: lu16,
    };
    pub const Unknown_7D = packed struct {
        kind: Kind,
        arg: lu16,
        arg2: lu16,
        arg3: lu16,
        arg4: lu16,
    };
    pub const TeleportUpNPC = packed struct {
        kind: Kind,
        npc: lu16,
    };
    pub const Unknown_7F = packed struct {
        kind: Kind,
        arg: lu16,
        arg2: lu16,
    };
    pub const Unknown_82 = packed struct {
        kind: Kind,
        arg: lu16,
        arg2: lu16,
    };
    pub const SetVar83 = packed struct {
        kind: Kind,
        value: lu16,
    };
    pub const SetVar84 = packed struct {
        kind: Kind,
        value: lu16,
    };
    pub const SingleTrainerBattle = packed struct {
        kind: Kind,
        trainerid: lu16,
        trainerid2: lu16,
        logic: lu16,
    };
    pub const DoubleTrainerBattle = packed struct {
        kind: Kind,
        ally: lu16,
        trainerid: lu16,
        trainerid2: lu16,
        logic: lu16,
    };
    pub const Unknown_87 = packed struct {
        kind: Kind,
        arg: lu16,
        arg2: lu16,
        arg3: lu16,
    };
    pub const Unknown_88 = packed struct {
        kind: Kind,
        arg: lu16,
        arg2: lu16,
        arg3: lu16,
    };
    pub const Unknown_8A = packed struct {
        kind: Kind,
        arg: lu16,
        arg2: lu16,
    };
    pub const PlayTrainerMusic = packed struct {
        kind: Kind,
        songid: lu16,
    };
    pub const StoreBattleResult = packed struct {
        kind: Kind,
        variable: lu16,
    };
    pub const DVar90 = packed struct {
        kind: Kind,
        arg: lu16,
        arg2: lu16,
    };
    pub const DVar92 = packed struct {
        kind: Kind,
        arg: lu16,
        arg2: lu16,
    };
    pub const DVar93 = packed struct {
        kind: Kind,
        arg: lu16,
        arg2: lu16,
    };
    pub const TrainerBattle = packed struct {
        kind: Kind,
        trainerid: lu16,
        arg2: lu16,
        arg3: lu16,
        arg4: lu16,
    };
    pub const DeactivateTrainerID = packed struct {
        kind: Kind,
        id: lu16,
    };
    pub const Unknown_96 = packed struct {
        kind: Kind,
        trainerid: lu16,
    };
    pub const StoreActiveTrainerID = packed struct {
        kind: Kind,
        trainerid: lu16,
        arg2: lu16,
    };
    pub const ChangeMusic = packed struct {
        kind: Kind,
        songid: lu16,
    };
    pub const Unknown_A2 = packed struct {
        kind: Kind,
        sound: lu16,
        arg2: lu16,
    };
    pub const Unknown_A5 = packed struct {
        kind: Kind,
        arg: lu16,
        arg2: lu16,
    };
    pub const PlaySound = packed struct {
        kind: Kind,
        id: lu16,
    };
    pub const PlayFanfare = packed struct {
        kind: Kind,
        id: lu16,
    };
    pub const PlayCry = packed struct {
        kind: Kind,
        id: lu16,
        arg2: lu16,
    };
    pub const SetTextScriptMessage = packed struct {
        kind: Kind,
        id: lu16,
        arg2: lu16,
        arg3: lu16,
    };
    pub const Multi2 = packed struct {
        kind: Kind,
        arg: u8,
        arg2: u8,
        arg3: u8,
        arg4: u8,
        arg5: u8,
        @"var": lu16,
    };
    pub const FadeScreen = packed struct {
        kind: Kind,
        arg: lu16,
        arg2: lu16,
        arg3: lu16,
        arg4: lu16,
    };
    pub const ResetScreen = packed struct {
        kind: Kind,
        arg: lu16,
        arg2: lu16,
        arg3: lu16,
    };
    pub const Screen_B5 = packed struct {
        kind: Kind,
        arg: lu16,
        arg2: lu16,
        arg3: lu16,
    };
    pub const TakeItem = packed struct {
        kind: Kind,
        item: lu16,
        quantity: lu16,
        result: lu16,
    };
    pub const CheckItemBagSpace = packed struct {
        kind: Kind,
        item: lu16,
        quantity: lu16,
        result: lu16,
    };
    pub const CheckItemBagNumber = packed struct {
        kind: Kind,
        item: lu16,
        quantity: lu16,
        result: lu16,
    };
    pub const StoreItemCount = packed struct {
        kind: Kind,
        item: lu16,
        result: lu16,
    };
    pub const Unknown_BA = packed struct {
        kind: Kind,
        arg: lu16,
        arg2: lu16,
        arg3: lu16,
        arg4: lu16,
    };
    pub const Unknown_BB = packed struct {
        kind: Kind,
        arg: lu16,
        arg2: lu16,
    };
    pub const Warp = packed struct {
        kind: Kind,
        mapid: lu16,
        xcoord: lu16,
        ycoord: lu16,
    };
    pub const TeleportWarp = packed struct {
        kind: Kind,
        mapid: lu16,
        xcoord: lu16,
        ycoord: lu16,
        zcoord: lu16,
        npcfacing: lu16,
    };
    pub const FallWarp = packed struct {
        kind: Kind,
        mapid: lu16,
        xcoord: lu16,
        ycoord: lu16,
    };
    pub const FastWarp = packed struct {
        kind: Kind,
        mapid: lu16,
        xcoord: lu16,
        ycoord: lu16,
        herofacing: lu16,
    };
    pub const TeleportWarp2 = packed struct {
        kind: Kind,
        mapid: lu16,
        xcoord: lu16,
        ycoord: lu16,
        zcoord: lu16,
        herofacing: lu16,
    };
    pub const SpecialAnimation2 = packed struct {
        kind: Kind,
        arg: lu16,
        arg2: lu16,
    };
    pub const CallAnimation = packed struct {
        kind: Kind,
        arg: lu16,
        arg2: lu16,
    };
    pub const StoreRandomNumber = packed struct {
        kind: Kind,
        arg: lu16,
        arg2: lu16,
    };
    pub const StoreDate = packed struct {
        kind: Kind,
        month: lu16,
        date: lu16,
    };
    pub const Store_D1 = packed struct {
        kind: Kind,
        arg: lu16,
        arg2: lu16,
    };
    pub const StoreBirthDay = packed struct {
        kind: Kind,
        month: lu16,
        day: lu16,
    };
    pub const StoreBadge = packed struct {
        kind: Kind,
        @"var": lu16,
        badge: lu16,
    };
    pub const SetBadge = packed struct {
        kind: Kind,
        badge: lu16,
    };
    pub const StoreBadgeNumber = packed struct {
        kind: Kind,
        badge: lu16,
    };
    pub const TakeMoney = packed struct {
        kind: Kind,
        amount: lu16,
    };
    pub const CheckMoney = packed struct {
        kind: Kind,
        storage: lu16,
        value: lu16,
    };
    pub const StorePartyNumberMinimum = packed struct {
        kind: Kind,
        result: lu16,
        number: lu16,
    };
    pub const GivePokemon1 = packed struct {
        kind: Kind,
        result: lu16,
        species: lu16,
        item: lu16,
        level: lu16,
    };
    pub const GivePokemon2 = packed struct {
        kind: Kind,
        result: lu16,
        species: lu16,
        form: lu16,
        level: lu16,
        unknown_0: lu16,
        unknown_1: lu16,
        unknown_2: lu16,
        unknown_3: lu16,
        unknown_4: lu16,
    };
    pub const GivePokemon3 = packed struct {
        kind: Kind,
        result: lu16,
        species: lu16,
        is_full: lu16,
    };
    pub const GivePokemon4 = packed struct {
        kind: Kind,
        result: lu16,
        species: lu16,
        level: lu16,
        unknown_0: lu16,
        unknown_1: lu16,
        unknown_2: lu16,
    };
    pub const MoveCamera = packed struct {
        kind: Kind,
        arg1: lu16,
        arg2: lu16,
        arg3: lu32,
        arg4: lu32,
        arg5: lu32,
        arg6: lu32,
        arg7: lu16,
    };
    pub const ResetCamera = packed struct {
        kind: Kind,
        arg1: lu16,
        arg2: lu16,
        arg3: lu16,
        arg4: lu16,
        arg5: lu16,
        arg6: lu16,
    };
    pub const SwitchOwPosition = packed struct {
        kind: Kind,
        arg1: lu16,
        arg2: lu16,
        arg3: lu16,
        arg4: lu16,
        arg5: lu16,
    };
    pub const WildBattle = packed struct {
        kind: Kind,
        species: lu16,
        level: lu16,
    };
    pub const WildBattleStoreResult = packed struct {
        kind: Kind,
        species: lu16,
        level: lu16,
        variable: lu16,
    };
};

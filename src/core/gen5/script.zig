const rom = @import("../rom.zig");
const script = @import("../script.zig");
const std = @import("std");

const builtin = std.builtin;
const mem = std.mem;

const li32 = rom.int.li32;
const lu16 = rom.int.lu16;
const lu32 = rom.int.lu32;

pub fn getScriptOffsets(data: []const u8) []align(1) const li32 {
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
    compare_to: Value,
    store_var: Var,
    clear_var: Var,
    unknown_0b: Value,
    unknown_0c: Value,
    unknown_0d: Value,
    unknown_0e: Value,
    unknown_0f: Value,
    store_flag: Value,
    condition: Condition,
    unknown_12: Value,
    unknown_13: Arg2(lu16, lu16),
    unknown_14: Value,
    unknown_16: Value,
    unknown_17: Value,
    compare: Value2,
    call_std: CallStd,
    return_std: Arg0,
    jump: Jump,
    @"if": If,
    unknown_21: Value,
    unknown_22: Value,
    set_flag: Value,
    clear_flag: ClearFlag,
    set_var_flag_status: SetVarFlagStatus,
    set_var_26: Value2,
    set_var_27: Value2,
    set_var_eq_val: SetVarContainer,
    set_var_29: SetVarContainer,
    set_var_2a: SetVarContainer,
    set_var_2b: Value,
    dir_vars: Arg2(lu16, lu16),
    unknown_2d: Value,
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
    message2: Message,
    close_message_k_p: Arg0,
    close_message_k_p2: Arg0,
    money_box: Coord,
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
    set_var_hero: Arg1(u8),
    set_var_item: ArgValue(u8, lu16),
    unknown_4e: Arg4(u8, lu16, lu16, u8),
    set_var_item2: ArgValue(u8, lu16),
    set_var_item3: ArgValue(u8, lu16),
    set_var_move: ArgValue(u8, lu16),
    set_var_bag: ArgValue(u8, lu16),
    set_var_party_poke: ArgValue(u8, lu16),
    set_var_party_poke2: ArgValue(u8, lu16),
    set_var_unknown: ArgValue(u8, lu16),
    set_var_type: ArgValue(u8, lu16),
    set_var_poke: ArgValue(u8, lu16),
    set_var_poke2: ArgValue(u8, lu16),
    set_var_location: ArgValue(u8, lu16),
    set_var_poke_nick: ArgValue(u8, lu16),
    set_var_unknown2: ArgValue(u8, lu16),
    set_var_store_value5_c: SetVarStoreValue5C,
    set_var_musical_info: ArgValue(lu16, lu16),
    set_var_nations: ArgValue(u8, lu16),
    set_var_activities: ArgValue(u8, lu16),
    set_var_power: ArgValue(u8, lu16),
    set_var_trainer_type: ArgValue(u8, lu16),
    set_var_trainer_type2: ArgValue(u8, lu16),
    set_var_general_word: ArgValue(u8, lu16),
    apply_movement: ApplyMovement,
    wait_movement: Arg0,
    store_hero_position: Coord,
    unknown_67: Arg2(lu16, lu16),
    store_hero_position2: Coord,
    store_npc_position: StoreNPCPosition,
    unknown_6a: Unknown_6A,
    add_npc: NPC,
    remove_npc: NPC,
    set_o_w_position: SetOWPosition,
    unknown_6e: Arg1(lu16),
    unknown_6f: Arg1(lu16),
    unknown_70: Unknown_70,
    unknown_71: Arg3(lu16, lu16, lu16),
    unknown_72: Arg4(lu16, lu16, lu16, lu16),
    unknown_73: Arg2(lu16, lu16),
    face_player: Arg0,
    release: NPC,
    release_all: Arg0,
    lock_77: NPC,
    unknown_78: Var,
    unknown_79: Unknown_79,
    move_npc_to: MoveNPCTo,
    unknown_7c: Arg4(lu16, lu16, lu16, lu16),
    unknown_7d: Arg4(lu16, lu16, lu16, lu16),
    teleport_up_npc: TeleportUpNPC,
    unknown_7f: Arg2(lu16, lu16),
    unknown_80: Arg1(lu16),
    unknown_81: Arg0,
    unknown_82: Arg2(lu16, lu16),
    set_var83: Value,
    set_var84: Value,
    single_trainer_battle: SingleTrainerBattle,
    double_trainer_battle: DoubleTrainerBattle,
    unknown_87: Arg3(lu16, lu16, lu16),
    unknown_88: Arg3(lu16, lu16, lu16),
    unknown_8a: Arg2(lu16, lu16),
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
    d_var90: Arg2(lu16, lu16),
    d_var92: Arg2(lu16, lu16),
    d_var93: Arg2(lu16, lu16),
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
    unknown_a5: Arg2(lu16, lu16),
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
    fade_screen: Arg4(lu16, lu16, lu16, lu16),
    reset_screen: Arg3(lu16, lu16, lu16),
    screen_b5: Arg3(lu16, lu16, lu16),
    take_item: TakeItem,
    check_item_bag_space: CheckItemBagSpace,
    check_item_bag_number: CheckItemBagNumber,
    store_item_count: StoreItemCount,
    unknown_ba: Arg4(lu16, lu16, lu16, lu16),
    unknown_bb: Arg2(lu16, lu16),
    unknown_bc: Arg1(lu16),
    warp: Warp,
    teleport_warp: TeleportWarp,
    fall_warp: FallWarp,
    fast_warp: FastWarp,
    union_warp: Arg0,
    teleport_warp2: TeleportWarp2,
    surf_animation: Arg0,
    special_animation: Arg1(lu16),
    special_animation2: Arg2(lu16, lu16),
    call_animation: Arg2(lu16, lu16),
    store_random_number: Arg2(lu16, lu16),
    store_var_item: Arg1(lu16),
    store_var_cd: Arg1(lu16),
    store_var_ce: Arg1(lu16),
    store_var_cf: Arg1(lu16),
    store_date: StoreDate,
    store_d1: Arg2(lu16, lu16),
    store_d2: Arg1(lu16),
    store_d3: Arg1(lu16),
    store_birth_day: StoreBirthDay,
    store_badge: StoreBadge,
    set_badge: Badge,
    store_badge_number: Badge,
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

    pub const Arg0 = extern struct {
        kind: Kind align(1),
    };
    pub fn Arg1(comptime T: type) type {
        return extern struct {
            kind: Kind align(1),
            arg: T align(1),
        };
    }

    pub fn Arg2(comptime T1: type, comptime T2: type) type {
        return extern struct {
            kind: Kind align(1),
            arg1: T1 align(1),
            arg2: T2 align(1),
        };
    }
    pub fn Arg3(comptime T1: type, comptime T2: type, comptime T3: type) type {
        return extern struct {
            kind: Kind align(1),
            arg1: T1 align(1),
            arg2: T2 align(1),
            arg3: T3 align(1),
        };
    }
    pub fn Arg4(comptime T1: type, comptime T2: type, comptime T3: type, comptime T4: type) type {
        return extern struct {
            kind: Kind align(1),
            arg1: T1 align(1),
            arg2: T2 align(1),
            arg3: T3 align(1),
            arg4: T4 align(1),
        };
    }
    pub fn ArgValue(comptime T1: type, comptime T2: type) type {
        return extern struct {
            kind: Kind align(1),
            arg: T1 align(1),
            value: T2 align(1),
        };
    }
    pub const Value = extern struct {
        kind: Kind align(1),
        value: lu16 align(1),
    };
    pub const Value2 = extern struct {
        kind: Kind align(1),
        value1: lu16 align(1),
        value2: lu16 align(1),
    };
    pub const CallRoutine = extern struct {
        kind: Kind align(1),
        offset: li32 align(1),
    };
    pub const Var = extern struct {
        kind: Kind align(1),
        @"var": lu16 align(1),
    };
    pub const Condition = extern struct {
        kind: Kind align(1),
        condition: lu16 align(1),
    };
    pub const CallStd = extern struct {
        kind: Kind align(1),
        function: lu16 align(1),
    };
    pub const Jump = extern struct {
        kind: Kind align(1),
        offset: li32 align(1),
    };
    pub const If = extern struct {
        kind: Kind align(1),
        value: u8 align(1),
        offset: li32 align(1),
    };
    pub const ClearFlag = extern struct {
        kind: Kind align(1),
        flag: lu16 align(1),
    };
    pub const SetVarFlagStatus = extern struct {
        kind: Kind align(1),
        flag: lu16 align(1),
        status: lu16 align(1),
    };
    pub const SetVarContainer = extern struct {
        kind: Kind align(1),
        container: lu16 align(1),
        value: lu16 align(1),
    };
    pub const MusicalMessage = extern struct {
        kind: Kind align(1),
        id: lu16 align(1),
    };
    pub const EventGreyMessage = extern struct {
        kind: Kind align(1),
        id: lu16 align(1),
        view: lu16 align(1),
    };
    pub const BubbleMessage = extern struct {
        kind: Kind align(1),
        id: lu16 align(1),
        location: u8 align(1),
    };
    pub const ShowMessageAt = extern struct {
        kind: Kind align(1),
        id: lu16 align(1),
        xcoord: lu16 align(1),
        ycoord: lu16 align(1),
        zcoord: lu16 align(1),
    };
    pub const Message = extern struct {
        kind: Kind align(1),
        id: lu16 align(1),
        npc: lu16 align(1),
        position: lu16 align(1),
        type: lu16 align(1),
    };
    pub const Coord = extern struct {
        kind: Kind align(1),
        xcoord: lu16 align(1),
        ycoord: lu16 align(1),
    };
    pub const BorderedMessage = extern struct {
        kind: Kind align(1),
        id: lu16 align(1),
        color: lu16 align(1),
    };
    pub const PaperMessage = extern struct {
        kind: Kind align(1),
        id: lu16 align(1),
        transcoord: lu16 align(1),
    };
    pub const YesNo = extern struct {
        kind: Kind align(1),
        yesno: lu16 align(1),
    };
    pub const Message3 = extern struct {
        kind: Kind align(1),
        id: lu16 align(1),
        npc: lu16 align(1),
        position: lu16 align(1),
        type: lu16 align(1),
        unknown: lu16 align(1),
    };
    pub const DoubleMessage = extern struct {
        kind: Kind align(1),
        idblack: lu16 align(1),
        idwhite: lu16 align(1),
        npc: lu16 align(1),
        position: lu16 align(1),
        type: lu16 align(1),
    };
    pub const AngryMessage = extern struct {
        kind: Kind align(1),
        id: lu16 align(1),
        unknownbyte: u8 align(1),
        position: lu16 align(1),
    };
    pub const SetVarStoreValue5C = extern struct {
        kind: Kind align(1),
        arg: u8 align(1),
        container: lu16 align(1),
        stat: lu16 align(1),
    };
    pub const ApplyMovement = extern struct {
        kind: Kind align(1),
        npc: lu16 align(1),
        movementdata: lu32 align(1),
    };
    pub const StoreNPCPosition = extern struct {
        kind: Kind align(1),
        npc: lu16 align(1),
        xcoord: lu16 align(1),
        ycoord: lu16 align(1),
    };
    pub const Unknown_6A = extern struct {
        kind: Kind align(1),
        npc: lu16 align(1),
        flag: lu16 align(1),
    };
    pub const NPC = extern struct {
        kind: Kind align(1),
        npc: lu16 align(1),
    };
    pub const SetOWPosition = extern struct {
        kind: Kind align(1),
        npc: lu16 align(1),
        xcoord: lu16 align(1),
        ycoord: lu16 align(1),
        zcoord: lu16 align(1),
        direction: lu16 align(1),
    };
    pub const Unknown_70 = extern struct {
        kind: Kind align(1),
        arg: lu16 align(1),
        arg2: lu16 align(1),
        arg3: lu16 align(1),
        arg4: lu16 align(1),
        arg5: lu16 align(1),
    };
    pub const Unknown_79 = extern struct {
        kind: Kind align(1),
        npc: lu16 align(1),
        arg2: lu16 align(1),
        arg3: lu16 align(1),
    };
    pub const MoveNPCTo = extern struct {
        kind: Kind align(1),
        npc: lu16 align(1),
        xcoord: lu16 align(1),
        ycoord: lu16 align(1),
        zcoord: lu16 align(1),
    };
    pub const TeleportUpNPC = extern struct {
        kind: Kind align(1),
        npc: lu16 align(1),
    };
    pub const SingleTrainerBattle = extern struct {
        kind: Kind align(1),
        trainerid: lu16 align(1),
        trainerid2: lu16 align(1),
        logic: lu16 align(1),
    };
    pub const DoubleTrainerBattle = extern struct {
        kind: Kind align(1),
        ally: lu16 align(1),
        trainerid: lu16 align(1),
        trainerid2: lu16 align(1),
        logic: lu16 align(1),
    };
    pub const PlayTrainerMusic = extern struct {
        kind: Kind align(1),
        songid: lu16 align(1),
    };
    pub const StoreBattleResult = extern struct {
        kind: Kind align(1),
        variable: lu16 align(1),
    };
    pub const TrainerBattle = extern struct {
        kind: Kind align(1),
        trainerid: lu16 align(1),
        arg2: lu16 align(1),
        arg3: lu16 align(1),
        arg4: lu16 align(1),
    };
    pub const DeactivateTrainerID = extern struct {
        kind: Kind align(1),
        id: lu16 align(1),
    };
    pub const Unknown_96 = extern struct {
        kind: Kind align(1),
        trainerid: lu16 align(1),
    };
    pub const StoreActiveTrainerID = extern struct {
        kind: Kind align(1),
        trainerid: lu16 align(1),
        arg2: lu16 align(1),
    };
    pub const ChangeMusic = extern struct {
        kind: Kind align(1),
        songid: lu16 align(1),
    };
    pub const Unknown_A2 = extern struct {
        kind: Kind align(1),
        sound: lu16 align(1),
        arg2: lu16 align(1),
    };
    pub const PlaySound = extern struct {
        kind: Kind align(1),
        id: lu16 align(1),
    };
    pub const PlayFanfare = extern struct {
        kind: Kind align(1),
        id: lu16 align(1),
    };
    pub const PlayCry = extern struct {
        kind: Kind align(1),
        id: lu16 align(1),
        arg2: lu16 align(1),
    };
    pub const SetTextScriptMessage = extern struct {
        kind: Kind align(1),
        id: lu16 align(1),
        arg2: lu16 align(1),
        arg3: lu16 align(1),
    };
    pub const Multi2 = extern struct {
        kind: Kind align(1),
        arg: u8 align(1),
        arg2: u8 align(1),
        arg3: u8 align(1),
        arg4: u8 align(1),
        arg5: u8 align(1),
        @"var": lu16 align(1),
    };
    pub const TakeItem = extern struct {
        kind: Kind align(1),
        item: lu16 align(1),
        quantity: lu16 align(1),
        result: lu16 align(1),
    };
    pub const CheckItemBagSpace = extern struct {
        kind: Kind align(1),
        item: lu16 align(1),
        quantity: lu16 align(1),
        result: lu16 align(1),
    };
    pub const CheckItemBagNumber = extern struct {
        kind: Kind align(1),
        item: lu16 align(1),
        quantity: lu16 align(1),
        result: lu16 align(1),
    };
    pub const StoreItemCount = extern struct {
        kind: Kind align(1),
        item: lu16 align(1),
        result: lu16 align(1),
    };
    pub const Warp = extern struct {
        kind: Kind align(1),
        mapid: lu16 align(1),
        xcoord: lu16 align(1),
        ycoord: lu16 align(1),
    };
    pub const TeleportWarp = extern struct {
        kind: Kind align(1),
        mapid: lu16 align(1),
        xcoord: lu16 align(1),
        ycoord: lu16 align(1),
        zcoord: lu16 align(1),
        npcfacing: lu16 align(1),
    };
    pub const FallWarp = extern struct {
        kind: Kind align(1),
        mapid: lu16 align(1),
        xcoord: lu16 align(1),
        ycoord: lu16 align(1),
    };
    pub const FastWarp = extern struct {
        kind: Kind align(1),
        mapid: lu16 align(1),
        xcoord: lu16 align(1),
        ycoord: lu16 align(1),
        herofacing: lu16 align(1),
    };
    pub const TeleportWarp2 = extern struct {
        kind: Kind align(1),
        mapid: lu16 align(1),
        xcoord: lu16 align(1),
        ycoord: lu16 align(1),
        zcoord: lu16 align(1),
        herofacing: lu16 align(1),
    };
    pub const StoreDate = extern struct {
        kind: Kind align(1),
        month: lu16 align(1),
        date: lu16 align(1),
    };
    pub const StoreBirthDay = extern struct {
        kind: Kind align(1),
        month: lu16 align(1),
        day: lu16 align(1),
    };
    pub const StoreBadge = extern struct {
        kind: Kind align(1),
        @"var": lu16 align(1),
        badge: lu16 align(1),
    };
    pub const Badge = extern struct {
        kind: Kind align(1),
        badge: lu16 align(1),
    };
    pub const TakeMoney = extern struct {
        kind: Kind align(1),
        amount: lu16 align(1),
    };
    pub const CheckMoney = extern struct {
        kind: Kind align(1),
        storage: lu16 align(1),
        value: lu16 align(1),
    };
    pub const StorePartyNumberMinimum = extern struct {
        kind: Kind align(1),
        result: lu16 align(1),
        number: lu16 align(1),
    };
    pub const GivePokemon1 = extern struct {
        kind: Kind align(1),
        result: lu16 align(1),
        species: lu16 align(1),
        item: lu16 align(1),
        level: lu16 align(1),
    };
    pub const GivePokemon2 = extern struct {
        kind: Kind align(1),
        result: lu16 align(1),
        species: lu16 align(1),
        form: lu16 align(1),
        level: lu16 align(1),
        unknown_0: lu16 align(1),
        unknown_1: lu16 align(1),
        unknown_2: lu16 align(1),
        unknown_3: lu16 align(1),
        unknown_4: lu16 align(1),
    };
    pub const GivePokemon3 = extern struct {
        kind: Kind align(1),
        result: lu16 align(1),
        species: lu16 align(1),
        is_full: lu16 align(1),
    };
    pub const GivePokemon4 = extern struct {
        kind: Kind align(1),
        result: lu16 align(1),
        species: lu16 align(1),
        level: lu16 align(1),
        unknown_0: lu16 align(1),
        unknown_1: lu16 align(1),
        unknown_2: lu16 align(1),
    };
    pub const MoveCamera = extern struct {
        kind: Kind align(1),
        arg1: lu16 align(1),
        arg2: lu16 align(1),
        arg3: lu32 align(1),
        arg4: lu32 align(1),
        arg5: lu32 align(1),
        arg6: lu32 align(1),
        arg7: lu16 align(1),
    };
    pub const ResetCamera = extern struct {
        kind: Kind align(1),
        arg1: lu16 align(1),
        arg2: lu16 align(1),
        arg3: lu16 align(1),
        arg4: lu16 align(1),
        arg5: lu16 align(1),
        arg6: lu16 align(1),
    };
    pub const SwitchOwPosition = extern struct {
        kind: Kind align(1),
        arg1: lu16 align(1),
        arg2: lu16 align(1),
        arg3: lu16 align(1),
        arg4: lu16 align(1),
        arg5: lu16 align(1),
    };
    pub const WildBattle = extern struct {
        kind: Kind align(1),
        species: lu16 align(1),
        level: lu16 align(1),
    };
    pub const WildBattleStoreResult = extern struct {
        kind: Kind align(1),
        species: lu16 align(1),
        level: lu16 align(1),
        variable: lu16 align(1),
    };

    comptime {
        @setEvalBranchQuota(1000000);
        std.debug.assert(script.isPacked(@This()));
    }
};

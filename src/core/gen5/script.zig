const std = @import("std");
const rom = @import("../rom.zig");
const script = @import("../script.zig");

const mem = std.mem;

const lu16 = rom.int.lu16;
const lu32 = rom.int.lu32;
const li32 = rom.int.li32;

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
        switch (cmd.tag) {
            .end,
            .jump,
            => return true,
            else => return false,
        }
    }
}.isEnd);

// https://pastebin.com/QPrYmFwY
pub const Command = packed struct {
    tag: Kind,
    _data: Data,

    /// HACK: Zig crashes when trying to access `_data` during code generation. This
    ///       seem to happen because &cmd.data gives a bit aligned pointer, which then
    ///       does not get properly handled in codegen. This function works around this
    ///       by manually skipping the tag field to get the data field.
    pub fn data(cmd: *Command) *Data {
        const bytes = mem.asBytes(cmd);
        return mem.bytesAsValue(Data, bytes[@sizeOf(Kind)..][0..@sizeOf(Data)]);
    }

    const Data = packed union {
        nop1: void,
        nop2: void,
        end: void,
        return_after_delay: Arg1(lu16),
        call_routine: CallRoutine,
        end_function: Arg1(lu16),
        logic06: Arg1(lu16),
        logic07: Arg1(lu16),
        compare_to: CompareTo,
        store_var: StoreVar,
        clear_var: ClearVar,
        unknown_0_b: Unknown_0B,
        unknown_0_c: Unknown_0C,
        unknown_0_d: Unknown_0D,
        unknown_0_e: Unknown_0E,
        unknown_0_f: Unknown_0F,
        store_flag: StoreFlag,
        condition: Condition,
        unknown_12: Unknown_12,
        unknown_13: Unknown_13,
        unknown_14: Unknown_14,
        unknown_16: Unknown_16,
        unknown_17: Unknown_17,
        compare: Compare,
        call_std: CallStd,
        return_std: void,
        jump: Jump,
        @"if": If,
        unknown_21: Unknown_21,
        unknown_22: Unknown_22,
        set_flag: SetFlag,
        clear_flag: ClearFlag,
        set_var_flag_status: SetVarFlagStatus,
        set_var26: SetVar26,
        set_var27: SetVar27,
        set_var_eq_val: SetVarEqVal,
        set_var29: SetVar29,
        set_var2_a: SetVar2A,
        set_var2_b: SetVar2B,
        unknown_2_d: Unknown_2D,
        lock_all: void,
        unlock_all: void,
        wait_moment: void,
        wait_button: void,
        musical_message: MusicalMessage,
        event_grey_message: EventGreyMessage,
        close_musical_message: void,
        closed_event_grey_message: void,
        bubble_message: BubbleMessage,
        close_bubble_message: void,
        show_message_at: ShowMessageAt,
        close_show_message_at: void,
        message: Message,
        message2: Message2,
        close_message_k_p: void,
        close_message_k_p2: void,
        money_box: MoneyBox,
        close_money_box: void,
        update_money_box: void,
        bordered_message: BorderedMessage,
        close_bordered_message: void,
        paper_message: PaperMessage,
        close_paper_message: void,
        yes_no: YesNo,
        message3: Message3,
        double_message: DoubleMessage,
        angry_message: AngryMessage,
        close_angry_message: void,
        set_var_hero: SetVarHero,
        set_var_item: SetVarItem,
        unknown_4_e: unknown_4E,
        set_var_item2: SetVarItem2,
        set_var_item3: SetVarItem3,
        set_var_move: SetVarMove,
        set_var_bag: SetVarBag,
        set_var_party_poke: SetVarPartyPoke,
        set_var_party_poke2: SetVarPartyPoke2,
        set_var__unknown: SetVar_Unknown,
        set_var_type: SetVarType,
        set_var_poke: SetVarPoke,
        set_var_poke2: SetVarPoke2,
        set_var_location: SetVarLocation,
        set_var_poke_nick: SetVarPokeNick,
        set_var__unknown2: SetVar_Unknown2,
        set_var_store_value5_c: SetVarStoreValue5C,
        set_var_musical_info: SetVarMusicalInfo,
        set_var_nations: SetVarNations,
        set_var_activities: SetVarActivities,
        set_var_power: SetVarPower,
        set_var_trainer_type: SetVarTrainerType,
        set_var_trainer_type2: SetVarTrainerType2,
        set_var_general_word: SetVarGeneralWord,
        apply_movement: ApplyMovement,
        wait_movement: void,
        store_hero_position: StoreHeroPosition,
        unknown_67: Unknown_67,
        store_hero_position2: StoreHeroPosition2,
        store_n_p_c_position: StoreNPCPosition,
        unknown_6_a: Unknown_6A,
        add_n_p_c: AddNPC,
        remove_n_p_c: RemoveNPC,
        set_o_w_position: SetOWPosition,
        unknown_6_e: Arg1(lu16),
        unknown_6_f: Arg1(lu16),
        unknown_70: Unknown_70,
        unknown_71: Unknown_71,
        unknown_72: Unknown_72,
        unknown_73: Unknown_73,
        face_player: void,
        release: Release,
        release_all: void,
        lock: Lock,
        unknown_78: Unknown_78,
        unknown_79: Unknown_79,
        move_n_p_c_to: MoveNPCTo,
        unknown_7_c: Unknown_7C,
        unknown_7_d: Unknown_7D,
        teleport_up_n_p_c: TeleportUpNPC,
        unknown_7_f: Unknown_7F,
        unknown_80: Arg1(lu16),
        unknown_81: void,
        unknown_82: Unknown_82,
        set_var83: SetVar83,
        set_var84: SetVar84,
        single_trainer_battle: SingleTrainerBattle,
        double_trainer_battle: DoubleTrainerBattle,
        unknown_87: Unknown_87,
        unknown_88: Unknown_88,
        unknown_8_a: Unknown_8A,
        play_trainer_music: PlayTrainerMusic,
        end_battle: void,
        store_battle_result: StoreBattleResult,
        unknown_179: void,
        unknown_17a: void,
        unknown_17b: Arg1(lu16),
        unknown_17c: Arg1(lu16),
        disable_trainer: void,
        d_var90: DVar90,
        d_var92: DVar92,
        d_var93: DVar93,
        trainer_battle: TrainerBattle,
        deactivate_trainer_i_d: DeactivateTrainerID,
        unknown_96: Unknown_96,
        store_active_trainer_i_d: StoreActiveTrainerID,
        change_music: ChangeMusic,
        fade_to_default_music: void,
        unknown_9_f: void,
        unknown__a2: Unknown_A2,
        unknown__a3: Arg1(lu16),
        unknown__a4: Arg1(lu16),
        unknown__a5: Unknown_A5,
        play_sound: PlaySound,
        wait_sound_a7: void,
        wait_sound: void,
        play_fanfare: PlayFanfare,
        wait_fanfare: void,
        play_cry: PlayCry,
        wait_cry: void,
        set_text_script_message: SetTextScriptMessage,
        close_multi: void,
        unknown__b1: void,
        multi2: Multi2,
        fade_screen: FadeScreen,
        reset_screen: ResetScreen,
        screen__b5: Screen_B5,
        take_item: TakeItem,
        check_item_bag_space: CheckItemBagSpace,
        check_item_bag_number: CheckItemBagNumber,
        store_item_count: StoreItemCount,
        unknown__b_a: Unknown_BA,
        unknown__b_b: Unknown_BB,
        unknown__b_c: Arg1(lu16),
        warp: Warp,
        teleport_warp: TeleportWarp,
        fall_warp: FallWarp,
        fast_warp: FastWarp,
        union_warp: void,
        teleport_warp2: TeleportWarp2,
        surf_animation: void,
        special_animation: Arg1(lu16),
        special_animation2: SpecialAnimation2,
        call_animation: CallAnimation,
        store_random_number: StoreRandomNumber,
        store_var_item: Arg1(lu16),
        store_var__c_d: Arg1(lu16),
        store_var__c_e: Arg1(lu16),
        store_var__c_f: Arg1(lu16),
        store_date: StoreDate,
        store__d1: Store_D1,
        store__d2: Arg1(lu16),
        store__d3: Arg1(lu16),
        store_birth_day: StoreBirthDay,
        store_badge: StoreBadge,
        set_badge: SetBadge,
        store_badge_number: StoreBadgeNumber,
        check_money: CheckMoney,
        give_pokemon: GivePokemon,
        boot_p_c_sound: void,
        unknown_136: Arg1(lu16),
        wild_battle: WildBattle,
        wild_battle_store_result: WildBattleStoreResult,
        fade_into_black: void,
        unknown_1b7: Arg1(lu16),
        unknown_1b8: Arg1(lu16),
    };
    pub const Kind = packed enum(u16) {
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
        unknown_0_b = lu16.init(0x0B).value(),
        unknown_0_c = lu16.init(0x0C).value(),
        unknown_0_d = lu16.init(0x0D).value(),
        unknown_0_e = lu16.init(0x0E).value(),
        unknown_0_f = lu16.init(0x0F).value(),
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
        set_var26 = lu16.init(0x26).value(),
        set_var27 = lu16.init(0x27).value(),
        set_var_eq_val = lu16.init(0x28).value(),
        set_var29 = lu16.init(0x29).value(),
        set_var2_a = lu16.init(0x2A).value(),
        set_var2_b = lu16.init(0x2B).value(),
        unknown_2_d = lu16.init(0x2D).value(),
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
        unknown_4_e = lu16.init(0x4E).value(),
        set_var_item2 = lu16.init(0x4F).value(),
        set_var_item3 = lu16.init(0x50).value(),
        set_var_move = lu16.init(0x51).value(),
        set_var_bag = lu16.init(0x52).value(),
        set_var_party_poke = lu16.init(0x53).value(),
        set_var_party_poke2 = lu16.init(0x54).value(),
        set_var__unknown = lu16.init(0x55).value(),
        set_var_type = lu16.init(0x56).value(),
        set_var_poke = lu16.init(0x57).value(),
        set_var_poke2 = lu16.init(0x58).value(),
        set_var_location = lu16.init(0x59).value(),
        set_var_poke_nick = lu16.init(0x5A).value(),
        set_var__unknown2 = lu16.init(0x5B).value(),
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
        store_n_p_c_position = lu16.init(0x69).value(),
        unknown_6_a = lu16.init(0x6A).value(),
        add_n_p_c = lu16.init(0x6B).value(),
        remove_n_p_c = lu16.init(0x6C).value(),
        set_o_w_position = lu16.init(0x6D).value(),
        unknown_6_e = lu16.init(0x6E).value(),
        unknown_6_f = lu16.init(0x6F).value(),
        unknown_70 = lu16.init(0x70).value(),
        unknown_71 = lu16.init(0x71).value(),
        unknown_72 = lu16.init(0x72).value(),
        unknown_73 = lu16.init(0x73).value(),
        face_player = lu16.init(0x74).value(),
        release = lu16.init(0x75).value(),
        release_all = lu16.init(0x76).value(),
        lock = lu16.init(0x77).value(),
        unknown_78 = lu16.init(0x78).value(),
        unknown_79 = lu16.init(0x79).value(),
        move_n_p_c_to = lu16.init(0x7B).value(),
        unknown_7_c = lu16.init(0x7C).value(),
        unknown_7_d = lu16.init(0x7D).value(),
        teleport_up_n_p_c = lu16.init(0x7E).value(),
        unknown_7_f = lu16.init(0x7F).value(),
        unknown_80 = lu16.init(0x80).value(),
        unknown_81 = lu16.init(0x81).value(),
        unknown_82 = lu16.init(0x82).value(),
        set_var83 = lu16.init(0x83).value(),
        set_var84 = lu16.init(0x84).value(),
        single_trainer_battle = lu16.init(0x85).value(),
        double_trainer_battle = lu16.init(0x86).value(),
        unknown_87 = lu16.init(0x87).value(),
        unknown_88 = lu16.init(0x88).value(),
        unknown_8_a = lu16.init(0x8A).value(),
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
        unknown_9_f = lu16.init(0x9F).value(),
        unknown__a2 = lu16.init(0xA2).value(),
        unknown__a3 = lu16.init(0xA3).value(),
        unknown__a4 = lu16.init(0xA4).value(),
        unknown__a5 = lu16.init(0xA5).value(),
        play_sound = lu16.init(0xA6).value(),
        wait_sound_a7 = lu16.init(0xA7).value(),
        wait_sound = lu16.init(0xA8).value(),
        play_fanfare = lu16.init(0xA9).value(),
        wait_fanfare = lu16.init(0xAA).value(),
        play_cry = lu16.init(0xAB).value(),
        wait_cry = lu16.init(0xAC).value(),
        set_text_script_message = lu16.init(0xAF).value(),
        close_multi = lu16.init(0xB0).value(),
        unknown__b1 = lu16.init(0xB1).value(),
        multi2 = lu16.init(0xB2).value(),
        fade_screen = lu16.init(0xB3).value(),
        reset_screen = lu16.init(0xB4).value(),
        screen__b5 = lu16.init(0xB5).value(),
        take_item = lu16.init(0xB6).value(),
        check_item_bag_space = lu16.init(0xB7).value(),
        check_item_bag_number = lu16.init(0xB8).value(),
        store_item_count = lu16.init(0xB9).value(),
        unknown__b_a = lu16.init(0xBA).value(),
        unknown__b_b = lu16.init(0xBB).value(),
        unknown__b_c = lu16.init(0xBC).value(),
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
        store_var__c_d = lu16.init(0xCD).value(),
        store_var__c_e = lu16.init(0xCE).value(),
        store_var__c_f = lu16.init(0xCF).value(),
        store_date = lu16.init(0xD0).value(),
        store__d1 = lu16.init(0xD1).value(),
        store__d2 = lu16.init(0xD2).value(),
        store__d3 = lu16.init(0xD3).value(),
        store_birth_day = lu16.init(0xD4).value(),
        store_badge = lu16.init(0xD5).value(),
        set_badge = lu16.init(0xD6).value(),
        store_badge_number = lu16.init(0xD7).value(),
        check_money = lu16.init(0xFB).value(),
        give_pokemon = lu16.init(0x10C).value(),
        boot_p_c_sound = lu16.init(0x130).value(),
        unknown_136 = lu16.init(0x136).value(),
        wild_battle = lu16.init(0x174).value(),
        wild_battle_store_result = lu16.init(0x178).value(),
        unknown_179 = lu16.init(0x179).value(),
        unknown_17a = lu16.init(0x17a).value(),
        unknown_17b = lu16.init(0x17b).value(),
        unknown_17c = lu16.init(0x17c).value(),
        fade_into_black = lu16.init(0x1AC).value(),
        unknown_1b7 = lu16.init(0x1b7).value(),
        unknown_1b8 = lu16.init(0x1b8).value(),
    };

    pub fn Arg1(comptime T: type) type {
        return packed struct { arg: T };
    }
    pub const CallRoutine = packed struct {
        arg: li32,
    };
    pub const CompareTo = packed struct {
        value: lu16,
    };
    pub const StoreVar = packed struct {
        @"var": lu16,
    };
    pub const ClearVar = packed struct {
        @"var": lu16,
    };
    pub const Unknown_0B = packed struct {
        value: lu16,
    };
    pub const Unknown_0C = packed struct {
        value: lu16,
    };
    pub const Unknown_0D = packed struct {
        value: lu16,
    };
    pub const Unknown_0E = packed struct {
        value: lu16,
    };
    pub const Unknown_0F = packed struct {
        value: lu16,
    };
    pub const StoreFlag = packed struct {
        value: lu16,
    };
    pub const Condition = packed struct {
        condition: lu16,
    };
    pub const Unknown_12 = packed struct {
        value: lu16,
    };
    pub const Unknown_13 = packed struct {
        value1: lu16,
        value2: lu16,
    };
    pub const Unknown_14 = packed struct {
        value: lu16,
    };
    pub const Unknown_16 = packed struct {
        value: lu16,
    };
    pub const Unknown_17 = packed struct {
        value: lu16,
    };
    pub const Compare = packed struct {
        value1: lu16,
        value2: lu16,
    };
    pub const CallStd = packed struct {
        function: lu16,
    };
    pub const Jump = packed struct {
        offset: li32,
    };
    pub const If = packed struct {
        value: u8,
        offset: li32,
    };
    pub const Unknown_21 = packed struct {
        value: lu16,
    };
    pub const Unknown_22 = packed struct {
        value: lu16,
    };
    pub const SetFlag = packed struct {
        value: lu16,
    };
    pub const ClearFlag = packed struct {
        flag: lu16,
    };
    pub const SetVarFlagStatus = packed struct {
        flag: lu16,
        status: lu16,
    };
    pub const SetVar26 = packed struct {
        value1: lu16,
        value2: lu16,
    };
    pub const SetVar27 = packed struct {
        value1: lu16,
        value2: lu16,
    };
    pub const SetVarEqVal = packed struct {
        container: lu16,
        value: lu16,
    };
    pub const SetVar29 = packed struct {
        container: lu16,
        value: lu16,
    };
    pub const SetVar2A = packed struct {
        container: lu16,
        value: lu16,
    };
    pub const SetVar2B = packed struct {
        value: lu16,
    };
    pub const Unknown_2D = packed struct {
        value: lu16,
    };
    pub const MusicalMessage = packed struct {
        id: lu16,
    };
    pub const EventGreyMessage = packed struct {
        id: lu16,
        location: u8,
    };
    pub const BubbleMessage = packed struct {
        id: lu16,
        location: u8,
    };
    pub const ShowMessageAt = packed struct {
        id: lu16,
        xcoord: lu16,
        ycoord: lu16,
        zcoord: lu16,
    };
    pub const Message = packed struct {
        id: lu16,
        npc: lu16,
        position: lu16,
        type: lu16,
    };
    pub const Message2 = packed struct {
        id: lu16,
        npc: lu16,
        position: lu16,
        type: lu16,
    };
    pub const MoneyBox = packed struct {
        xcoord: lu16,
        ycoord: lu16,
    };
    pub const BorderedMessage = packed struct {
        id: lu16,
        color: lu16,
    };
    pub const PaperMessage = packed struct {
        id: lu16,
        transcoord: lu16,
    };
    pub const YesNo = packed struct {
        yesno: lu16,
    };
    pub const Message3 = packed struct {
        id: lu16,
        npc: lu16,
        position: lu16,
        type: lu16,
        unknown: lu16,
    };
    pub const DoubleMessage = packed struct {
        idblack: lu16,
        idwhite: lu16,
        npc: lu16,
        position: lu16,
        type: lu16,
    };
    pub const AngryMessage = packed struct {
        id: lu16,
        unknownbyte: u8,
        position: lu16,
    };
    pub const SetVarHero = packed struct {
        arg: u8,
    };
    pub const SetVarItem = packed struct {
        arg: u8,
        item: lu16,
    };
    pub const unknown_4E = packed struct {
        arg1: u8,
        arg2: lu16,
        arg3: lu16,
        arg4: u8,
    };
    pub const SetVarItem2 = packed struct {
        arg: u8,
        item: lu16,
    };
    pub const SetVarItem3 = packed struct {
        arg: u8,
        item: lu16,
    };
    pub const SetVarMove = packed struct {
        arg: u8,
        move: lu16,
    };
    pub const SetVarBag = packed struct {
        arg: u8,
        item: lu16,
    };
    pub const SetVarPartyPoke = packed struct {
        arg: u8,
        party_poke: lu16,
    };
    pub const SetVarPartyPoke2 = packed struct {
        arg: u8,
        party_poke: lu16,
    };
    pub const SetVar_Unknown = packed struct {
        arg: u8,
        value: lu16,
    };
    pub const SetVarType = packed struct {
        arg: u8,
        type: lu16,
    };
    pub const SetVarPoke = packed struct {
        arg: u8,
        poke: lu16,
    };
    pub const SetVarPoke2 = packed struct {
        arg: u8,
        poke: lu16,
    };
    pub const SetVarLocation = packed struct {
        arg: u8,
        location: lu16,
    };
    pub const SetVarPokeNick = packed struct {
        arg: u8,
        poke: lu16,
    };
    pub const SetVar_Unknown2 = packed struct {
        arg: u8,
        value: lu16,
    };
    pub const SetVarStoreValue5C = packed struct {
        arg: u8,
        container: lu16,
        stat: lu16,
    };
    pub const SetVarMusicalInfo = packed struct {
        arg: lu16,
        value: lu16,
    };
    pub const SetVarNations = packed struct {
        arg: u8,
        value: lu16,
    };
    pub const SetVarActivities = packed struct {
        arg: u8,
        value: lu16,
    };
    pub const SetVarPower = packed struct {
        arg: u8,
        value: lu16,
    };
    pub const SetVarTrainerType = packed struct {
        arg: u8,
        value: lu16,
    };
    pub const SetVarTrainerType2 = packed struct {
        arg: u8,
        value: lu16,
    };
    pub const SetVarGeneralWord = packed struct {
        arg: u8,
        value: lu16,
    };
    pub const ApplyMovement = packed struct {
        npc: lu16,
        movementdata: lu32,
    };
    pub const StoreHeroPosition = packed struct {
        xcoord: lu16,
        ycoord: lu16,
    };
    pub const Unknown_67 = packed struct {
        value: lu16,
        value2: lu16,
    };
    pub const StoreHeroPosition2 = packed struct {
        xcoord: lu16,
        ycoord: lu16,
    };
    pub const StoreNPCPosition = packed struct {
        npc: lu16,
        xcoord: lu16,
        ycoord: lu16,
    };
    pub const Unknown_6A = packed struct {
        npc: lu16,
        flag: lu16,
    };
    pub const AddNPC = packed struct {
        npc: lu16,
    };
    pub const RemoveNPC = packed struct {
        npc: lu16,
    };
    pub const SetOWPosition = packed struct {
        npc: lu16,
        xcoord: lu16,
        ycoord: lu16,
        zcoord: lu16,
        direction: lu16,
    };
    pub const Unknown_70 = packed struct {
        arg: lu16,
        arg2: lu16,
        arg3: lu16,
        arg4: lu16,
        arg5: lu16,
    };
    pub const Unknown_71 = packed struct {
        arg: lu16,
        arg2: lu16,
        arg3: lu16,
    };
    pub const Unknown_72 = packed struct {
        arg: lu16,
        arg2: lu16,
        arg3: lu16,
        arg4: lu16,
    };
    pub const Unknown_73 = packed struct {
        arg: lu16,
        arg2: lu16,
    };
    pub const Release = packed struct {
        npc: lu16,
    };
    pub const Lock = packed struct {
        npc: lu16,
    };
    pub const Unknown_78 = packed struct {
        @"var": lu16,
    };
    pub const Unknown_79 = packed struct {
        npc: lu16,
        arg2: lu16,
        arg3: lu16,
    };
    pub const MoveNPCTo = packed struct {
        npc: lu16,
        xcoord: lu16,
        ycoord: lu16,
        zcoord: lu16,
    };
    pub const Unknown_7C = packed struct {
        arg: lu16,
        arg2: lu16,
        arg3: lu16,
        arg4: lu16,
    };
    pub const Unknown_7D = packed struct {
        arg: lu16,
        arg2: lu16,
        arg3: lu16,
        arg4: lu16,
    };
    pub const TeleportUpNPC = packed struct {
        npc: lu16,
    };
    pub const Unknown_7F = packed struct {
        arg: lu16,
        arg2: lu16,
    };
    pub const Unknown_82 = packed struct {
        arg: lu16,
        arg2: lu16,
    };
    pub const SetVar83 = packed struct {
        value: lu16,
    };
    pub const SetVar84 = packed struct {
        value: lu16,
    };
    pub const SingleTrainerBattle = packed struct {
        trainerid: lu16,
        trainerid2: lu16,
        logic: lu16,
    };
    pub const DoubleTrainerBattle = packed struct {
        ally: lu16,
        trainerid: lu16,
        trainerid2: lu16,
        logic: lu16,
    };
    pub const Unknown_87 = packed struct {
        arg: lu16,
        arg2: lu16,
        arg3: lu16,
    };
    pub const Unknown_88 = packed struct {
        arg: lu16,
        arg2: lu16,
        arg3: lu16,
    };
    pub const Unknown_8A = packed struct {
        arg: lu16,
        arg2: lu16,
    };
    pub const PlayTrainerMusic = packed struct {
        songid: lu16,
    };
    pub const StoreBattleResult = packed struct {
        variable: lu16,
    };
    pub const DVar90 = packed struct {
        arg: lu16,
        arg2: lu16,
    };
    pub const DVar92 = packed struct {
        arg: lu16,
        arg2: lu16,
    };
    pub const DVar93 = packed struct {
        arg: lu16,
        arg2: lu16,
    };
    pub const TrainerBattle = packed struct {
        trainerid: lu16,
        arg2: lu16,
        arg3: lu16,
        arg4: lu16,
    };
    pub const DeactivateTrainerID = packed struct {
        id: lu16,
    };
    pub const Unknown_96 = packed struct {
        trainerid: lu16,
    };
    pub const StoreActiveTrainerID = packed struct {
        trainerid: lu16,
        arg2: lu16,
    };
    pub const ChangeMusic = packed struct {
        songid: lu16,
    };
    pub const Unknown_A2 = packed struct {
        sound: lu16,
        arg2: lu16,
    };
    pub const Unknown_A5 = packed struct {
        arg: lu16,
        arg2: lu16,
    };
    pub const PlaySound = packed struct {
        id: lu16,
    };
    pub const PlayFanfare = packed struct {
        id: lu16,
    };
    pub const PlayCry = packed struct {
        id: lu16,
        arg2: lu16,
    };
    pub const SetTextScriptMessage = packed struct {
        id: lu16,
        arg2: lu16,
        arg3: lu16,
    };
    pub const Multi2 = packed struct {
        arg: u8,
        arg2: u8,
        arg3: u8,
        arg4: u8,
        arg5: u8,
        @"var": lu16,
    };
    pub const FadeScreen = packed struct {
        arg: lu16,
        arg2: lu16,
        arg3: lu16,
        arg4: lu16,
    };
    pub const ResetScreen = packed struct {
        arg: lu16,
        arg2: lu16,
        arg3: lu16,
    };
    pub const Screen_B5 = packed struct {
        arg: lu16,
        arg2: lu16,
        arg3: lu16,
    };
    pub const TakeItem = packed struct {
        item: lu16,
        quantity: lu16,
        result: lu16,
    };
    pub const CheckItemBagSpace = packed struct {
        item: lu16,
        minimumquantity: lu16,
        result: lu16,
    };
    pub const CheckItemBagNumber = packed struct {
        item: lu16,
        result: lu16,
    };
    pub const StoreItemCount = packed struct {
        item: lu16,
        result: lu16,
    };
    pub const Unknown_BA = packed struct {
        arg: lu16,
        arg2: lu16,
        arg3: lu16,
        arg4: lu16,
    };
    pub const Unknown_BB = packed struct {
        arg: lu16,
        arg2: lu16,
    };
    pub const Warp = packed struct {
        mapid: lu16,
        xcoord: lu16,
        ycoord: lu16,
    };
    pub const TeleportWarp = packed struct {
        mapid: lu16,
        xcoord: lu16,
        ycoord: lu16,
        zcoord: lu16,
        npcfacing: lu16,
    };
    pub const FallWarp = packed struct {
        mapid: lu16,
        xcoord: lu16,
        ycoord: lu16,
    };
    pub const FastWarp = packed struct {
        mapid: lu16,
        xcoord: lu16,
        ycoord: lu16,
        herofacing: lu16,
    };
    pub const TeleportWarp2 = packed struct {
        mapid: lu16,
        xcoord: lu16,
        ycoord: lu16,
        zcoord: lu16,
        herofacing: lu16,
    };
    pub const SpecialAnimation2 = packed struct {
        arg: lu16,
        arg2: lu16,
    };
    pub const CallAnimation = packed struct {
        arg: lu16,
        arg2: lu16,
    };
    pub const StoreRandomNumber = packed struct {
        arg: lu16,
        arg2: lu16,
    };
    pub const StoreDate = packed struct {
        month: lu16,
        date: lu16,
    };
    pub const Store_D1 = packed struct {
        arg: lu16,
        arg2: lu16,
    };
    pub const StoreBirthDay = packed struct {
        month: lu16,
        day: lu16,
    };
    pub const StoreBadge = packed struct {
        @"var": lu16,
        badge: lu16,
    };
    pub const SetBadge = packed struct {
        badge: lu16,
    };
    pub const StoreBadgeNumber = packed struct {
        badge: lu16,
    };
    pub const CheckMoney = packed struct {
        storage: lu16,
        value: lu16,
    };
    pub const GivePokemon = packed struct {
        species: lu16,
        item: lu16,
        level: lu16,
    };
    pub const WildBattle = packed struct {
        species: lu16,
        level: lu16,
    };
    pub const WildBattleStoreResult = packed struct {
        species: lu16,
        level: lu16,
        variable: lu16,
    };
};

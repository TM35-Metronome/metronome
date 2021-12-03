const rom = @import("../rom.zig");
const script = @import("../script.zig");
const std = @import("std");

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
        switch (cmd.tag) {
            .end,
            .@"return",
            .return2,
            .jump,
            => return true,
            else => return false,
        }
    }
}.isEnd);

// These commands are only valid in dia/pearl/plat
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
        nop0: void,
        nop1: void,
        end: void,
        return2: Return2,
        cmd_a: Cmd_a,
        @"if": If,
        if2: If2,
        call_standard: CallStandard,
        exit_standard: void,
        jump: Jump,
        call: Call,
        @"return": void,
        compare_last_result_jump: CompareLastResultJump,
        compare_last_result_call: CompareLastResultCall,
        set_flag: SetFlag,
        clear_flag: ClearFlag,
        check_flag: CheckFlag,
        cmd_21: Cmd_21,
        cmd_22: Cmd_22,
        set_trainer_id: SetTrainerId,
        cmd_24: Cmd_24,
        clear_trainer_id: ClearTrainerId,
        script_cmd__add_value: ScriptCmd_AddValue,
        script_cmd__sub_value: ScriptCmd_SubValue,
        set_var: SetVar,
        copy_var: CopyVar,
        message2: Message2,
        message: Message,
        message3: Message3,
        message4: Message4,
        message5: Message5,
        cmd_30: void,
        wait_button: void,
        cmd_32: void,
        cmd_33: void,
        close_msg_on_key_press: void,
        freeze_message_box: void,
        call_message_box: CallMessageBox,
        color_msg_box: ColorMsgBox,
        type_message_box: TypeMessageBox,
        no_map_message_box: void,
        call_text_msg_box: void,
        store_menu_status: StoreMenuStatus,
        show_menu: void,
        yes_no_box: YesNoBox,
        multi: Multi,
        multi2: Multi2,
        cmd_42: Cmd_42,
        close_multi: void,
        multi3: Multi3,
        multi4: Multi4,
        txt_msg_scrp_multi: TxtMsgScrpMulti,
        close_multi4: void,
        play_fanfare: PlayFanfare,
        multi_row: MultiRow,
        play_fanfare2: PlayFanfare2,
        wait_fanfare: WaitFanfare,
        play_cry: PlayCry,
        wait_cry: void,
        soundfr: Soundfr,
        cmd_4f: void,
        play_sound: PlaySound,
        stop: Stop,
        restart: void,
        cmd_53: Cmd_53,
        switch_music: SwitchMusic,
        store_saying_learned: StoreSayingLearned,
        play_sound2: PlaySound2,
        cmd_58: Cmd_58,
        check_saying_learned: CheckSayingLearned,
        swith_music2: SwithMusic2,
        act_microphone: void,
        deact_microphone: void,
        cmd_5d: void,
        apply_movement: ApplyMovement,
        wait_movement: void,
        lock_all: void,
        release_all: void,
        lock: Lock,
        release: Release,
        add_people: AddPeople,
        remove_people: RemovePeople,
        lock_cam: LockCam,
        zoom_cam: void,
        face_player: void,
        check_sprite_position: CheckSpritePosition,
        check_person_position: CheckPersonPosition,
        continue_follow: ContinueFollow,
        follow_hero: FollowHero,
        take_money: TakeMoney,
        check_money: CheckMoney,
        show_money: ShowMoney,
        hide_money: void,
        update_money: void,
        show_coins: ShowCoins,
        hide_coins: void,
        update_coins: void,
        check_coins: CheckCoins,
        give_coins: GiveCoins,
        take_coins: TakeCoins,
        take_item: TakeItem,
        give_item: GiveItem,
        check_store_item: CheckStoreItem,
        check_item: CheckItem,
        store_item_taken: StoreItemTaken,
        store_item_type: StoreItemType,
        send_item_type1: SendItemType1,
        cmd_84: Cmd_84,
        check_underground_pc_status: CheckUndergroundPcStatus,
        cmd_86: Cmd_86,
        send_item_type2: SendItemType2,
        cmd_88: Cmd_88,
        cmd_89: Cmd_89,
        cmd_8a: Cmd_8a,
        cmd_8b: Cmd_8b,
        cmd_8c: Cmd_8c,
        cmd_8d: Cmd_8d,
        cmd_8e: Cmd_8e,
        send_item_type3: SendItemType3,
        check_pokemon_party: CheckPokemonParty,
        store_pokemon_party: StorePokemonParty,
        set_pokemon_party_stored: SetPokemonPartyStored,
        give_pokemon: GivePokemon,
        give_egg: GiveEgg,
        check_move: CheckMove,
        check_place_stored: CheckPlaceStored,
        cmd_9b: Cmd_9b,
        cmd_9c: void,
        cmd_9d: void,
        cmd_9e: void,
        cmd_9f: void,
        cmd_a0: void,
        call_end: void,
        cmd__a2: void,
        wfc_: void,
        cmd_a4: Cmd_a4,
        interview: void,
        dress_pokemon: DressPokemon,
        display_dressed_pokemon: DisplayDressedPokemon,
        display_contest_pokemon: DisplayContestPokemon,
        open_ball_capsule: void,
        open_sinnoh_maps: void,
        open_pc_function: OpenPcFunction,
        draw_union: void,
        trainer_case_union: void,
        trade_union: void,
        record_mixing_union: void,
        end_game: void,
        hall_fame_anm: void,
        store_wfc_status: StoreWfcStatus,
        start_wfc: StartWfc,
        choose_starter: void,
        battle_starter: void,
        battle_id: BattleId,
        set_var_battle: SetVarBattle,
        check_battle_type: CheckBattleType,
        set_var_battle2: SetVarBattle2,
        choose_poke_nick: ChoosePokeNick,
        fade_screen: FadeScreen,
        reset_screen: void,
        warp: Warp,
        rock_climb_animation: RockClimbAnimation,
        surf_animation: void,
        waterfall_animation: WaterfallAnimation,
        flash_animation: void,
        defog_animation: void,
        prep_hm_effect: PrepHmEffect,
        tuxedo: void,
        check_bike: CheckBike,
        ride_bike: RideBike,
        ride_bike2: RideBike2,
        give_poke_hiro_anm: GivePokeHiroAnm,
        stop_give_poke_hiro_anm: void,
        set_var_hero: SetVarHero,
        set_variable_rival: SetVariableRival,
        set_var_alter: SetVarAlter,
        set_var_poke: SetVarPoke,
        set_var_item: SetVarItem,
        set_var_item_num: SetVarItemNum,
        set_var_atk_item: SetVarAtkItem,
        set_var_atk: SetVarAtk,
        set_variable_number: SetVariableNumber,
        set_var_poke_nick: SetVarPokeNick,
        set_var_obj: SetVarObj,
        set_var_trainer: SetVarTrainer,
        set_var_wi_fi_sprite: SetVarWiFiSprite,
        set_var_poke_stored: SetVarPokeStored,
        set_var_str_hero: SetVarStrHero,
        set_var_str_rival: SetVarStrRival,
        store_starter: StoreStarter,
        cmd_df: Cmd_df,
        set_var_item_stored: SetVarItemStored,
        set_var_item_stored2: SetVarItemStored2,
        set_var_swarm_poke: SetVarSwarmPoke,
        check_swarm_poke: CheckSwarmPoke,
        start_battle_analysis: StartBattleAnalysis,
        trainer_battle: TrainerBattle,
        endtrainer_battle: EndtrainerBattle,
        trainer_battle_stored: TrainerBattleStored,
        trainer_battle_stored2: TrainerBattleStored2,
        check_trainer_status: CheckTrainerStatus,
        store_league_trainer: StoreLeagueTrainer,
        lost_go_pc: void,
        check_trainer_lost: CheckTrainerLost,
        check_trainer_status2: CheckTrainerStatus2,
        store_poke_party_defeated: StorePokePartyDefeated,
        chs_friend: ChsFriend,
        wire_battle_wait: WireBattleWait,
        cmd_f6: void,
        pokecontest: void,
        start_ovation: StartOvation,
        stop_ovation: StopOvation,
        cmd_fa: Cmd_fa,
        cmd_fb: Cmd_fb,
        cmd_fc: Cmd_fc,
        setvar_other_entry: SetvarOtherEntry,
        cmd_fe: Cmd_fe,
        setvat_hiro_entry: SetvatHiroEntry,
        cmd_100: void,
        black_flash_effect: void,
        setvar_type_contest: SetvarTypeContest,
        setvar_rank_contest: SetvarRankContest,
        cmd_104: Cmd_104,
        cmd_105: Cmd_105,
        cmd_106: Cmd_106,
        cmd_107: Cmd_107,
        store_people_id_contest: StorePeopleIdContest,
        cmd_109: Cmd_109,
        setvat_hiro_entry2: SetvatHiroEntry2,
        act_people_contest: ActPeopleContest,
        cmd_10c: Cmd_10c,
        cmd_10d: Cmd_10d,
        cmd_10e: Cmd_10e,
        cmd_10f: Cmd_10f,
        cmd_110: Cmd_110,
        flash_contest: FlashContest,
        end_flash: void,
        carpet_anm: void,
        cmd_114: void,
        cmd_115: Cmd_115,
        show_lnk_cnt_record: void,
        cmd_117: void,
        cmd_118: void,
        store_pokerus: StorePokerus,
        warp_map_elevator: WarpMapElevator,
        check_floor: CheckFloor,
        start_lift: StartLift,
        store_sin_pokemon_seen: StoreSinPokemonSeen,
        cmd_11f: Cmd_11f,
        store_tot_pokemon_seen: StoreTotPokemonSeen,
        store_nat_pokemon_seen: StoreNatPokemonSeen,
        set_var_text_pokedex: SetVarTextPokedex,
        wild_battle: WildBattle,
        starter_battle: StarterBattle,
        explanation_battle: void,
        honey_tree_battle: void,
        check_if_honey_slathered: CheckIfHoneySlathered,
        random_battle: void,
        stop_random_battle: void,
        write_autograph: void,
        store_save_data: StoreSaveData,
        check_save_data: CheckSaveData,
        check_dress: CheckDress,
        check_contest_win: CheckContestWin,
        store_photo_name: StorePhotoName,
        give_poketch: void,
        check_ptch_appl: CheckPtchAppl,
        act_pktch_appl: ActPktchAppl,
        store_poketch_app: StorePoketchApp,
        friend_b_t: FriendBT,
        friend_b_t2: void,
        cmd_138: Cmd_138,
        open_union_function2: OpenUnionFunction2,
        start_union: void,
        link_closed: void,
        set_union_function_id: SetUnionFunctionId,
        close_union_function: void,
        close_union_function2: void,
        set_var_union_message: SetVarUnionMessage,
        store_your_decision_union: StoreYourDecisionUnion,
        store_other_decision_union: StoreOtherDecisionUnion,
        cmd_142: void,
        check_other_decision_union: CheckOtherDecisionUnion,
        store_your_decision_union2: StoreYourDecisionUnion2,
        store_other_decision_union2: StoreOtherDecisionUnion2,
        check_other_decision_union2: CheckOtherDecisionUnion2,
        pokemart: Pokemart,
        pokemart1: Pokemart1,
        pokemart2: Pokemart2,
        pokemart3: Pokemart3,
        defeat_go_pokecenter: void,
        act_bike: ActBike,
        check_gender: CheckGender,
        heal_pokemon: void,
        deact_wireless: void,
        delete_entry: void,
        cmd_151: void,
        underground_id: UndergroundId,
        union_room: void,
        open_wi_fi_sprite: void,
        store_wi_fi_sprite: StoreWiFiSprite,
        act_wi_fi_sprite: ActWiFiSprite,
        cmd_157: Cmd_157,
        activate_pokedex: void,
        give_running_shoes: void,
        check_badge: CheckBadge,
        enable_badge: EnableBadge,
        disable_badge: DisableBadge,
        check_follow: CheckFollow,
        start_follow: void,
        stop_follow: void,
        cmd_164: void,
        cmd_166: Cmd_166,
        prepare_door_animation: PrepareDoorAnimation,
        wait_action: WaitAction,
        wait_close: WaitClose,
        open_door: OpenDoor,
        close_door: CloseDoor,
        act_dcare_function: void,
        store_p_d_care_num: StorePDCareNum,
        pastoria_city_function: void,
        pastoria_city_function2: void,
        hearthrome_gym_function: void,
        hearthrome_gym_function2: void,
        canalave_gym_function: void,
        veilstone_gym_function: void,
        sunishore_gym_function: SunishoreGymFunction,
        sunishore_gym_function2: SunishoreGymFunction2,
        check_party_number: CheckPartyNumber,
        open_berry_pouch: OpenBerryPouch,
        cmd_179: Cmd_179,
        cmd_17a: Cmd_17a,
        cmd_17b: Cmd_17b,
        set_nature_pokemon: SetNaturePokemon,
        cmd_17d: Cmd_17d,
        cmd_17e: Cmd_17e,
        cmd_17f: Cmd_17f,
        cmd_180: Cmd_180,
        cmd_181: Cmd_181,
        check_deoxis: CheckDeoxis,
        cmd_183: Cmd_183,
        cmd_184: Cmd_184,
        cmd_185: void,
        change_ow_position: ChangeOwPosition,
        set_ow_position: SetOwPosition,
        change_ow_movement: ChangeOwMovement,
        release_ow: ReleaseOw,
        set_tile_passable: SetTilePassable,
        set_tile_locked: SetTileLocked,
        set_ows_follow: SetOwsFollow,
        show_clock_save: void,
        hide_clock_save: void,
        cmd_18f: Cmd_18f,
        set_save_data: SetSaveData,
        chs_pokemenu: void,
        chs_pokemenu2: void,
        store_poke_menu2: StorePokeMenu2,
        chs_poke_contest: ChsPokeContest,
        store_poke_contest: StorePokeContest,
        show_poke_info: ShowPokeInfo,
        store_poke_move: StorePokeMove,
        check_poke_egg: CheckPokeEgg,
        compare_poke_nick: ComparePokeNick,
        check_party_number_union: CheckPartyNumberUnion,
        check_poke_party_health: CheckPokePartyHealth,
        check_poke_party_num_d_care: CheckPokePartyNumDCare,
        check_egg_union: CheckEggUnion,
        underground_function: UndergroundFunction,
        underground_function2: UndergroundFunction2,
        underground_start: void,
        take_money_d_care: TakeMoneyDCare,
        take_pokemon_d_care: TakePokemonDCare,
        act_egg_day_c_man: void,
        deact_egg_day_c_man: void,
        set_var_poke_and_money_d_care: SetVarPokeAndMoneyDCare,
        check_money_d_care: CheckMoneyDCare,
        egg_animation: void,
        set_var_poke_and_level_d_care: SetVarPokeAndLevelDCare,
        set_var_poke_chosen_d_care: SetVarPokeChosenDCare,
        give_poke_d_care: GivePokeDCare,
        add_people2: AddPeople2,
        remove_people2: RemovePeople2,
        mail_box: void,
        check_mail: CheckMail,
        show_record_list: ShowRecordList,
        check_time: CheckTime,
        check_id_player: CheckIdPlayer,
        random_text_stored: RandomTextStored,
        store_happy_poke: StoreHappyPoke,
        store_happy_status: StoreHappyStatus,
        set_var_data_day_care: SetVarDataDayCare,
        check_face_position: CheckFacePosition,
        store_poke_d_care_love: StorePokeDCareLove,
        check_status_solaceon_event: CheckStatusSolaceonEvent,
        check_poke_party: CheckPokeParty,
        copy_pokemon_height: CopyPokemonHeight,
        set_variable_pokemon_height: SetVariablePokemonHeight,
        compare_pokemon_height: ComparePokemonHeight,
        check_pokemon_height: CheckPokemonHeight,
        show_move_info: void,
        store_poke_delete: StorePokeDelete,
        store_move_delete: StoreMoveDelete,
        check_move_num_delete: CheckMoveNumDelete,
        store_delete_move: StoreDeleteMove,
        check_delete_move: CheckDeleteMove,
        setvar_move_delete: SetvarMoveDelete,
        cmd_1cc: void,
        de_activate_leader: DeActivateLeader,
        hm_functions: HmFunctions,
        flash_duration: FlashDuration,
        defog_duration: DefogDuration,
        give_accessories: GiveAccessories,
        check_accessories: CheckAccessories,
        cmd_1d4: Cmd_1d4,
        give_accessories2: GiveAccessories2,
        check_accessories2: CheckAccessories2,
        berry_poffin: BerryPoffin,
        set_var_b_tower_chs: SetVarBTowerChs,
        battle_room_result: BattleRoomResult,
        activate_b_tower: void,
        store_b_tower_data: StoreBTowerData,
        close_b_tower: void,
        call_b_tower_functions: CallBTowerFunctions,
        random_team_b_tower: RandomTeamBTower,
        store_prize_num_b_tower: StorePrizeNumBTower,
        store_people_id_b_tower: StorePeopleIdBTower,
        call_b_tower_wire_function: CallBTowerWireFunction,
        store_p_chosen_wire_b_tower: StorePChosenWireBTower,
        store_rank_data_wire_b_tower: StoreRankDataWireBTower,
        cmd_1e4: Cmd_1e4,
        random_event: RandomEvent,
        check_sinnoh_pokedex: CheckSinnohPokedex,
        check_national_pokedex: CheckNationalPokedex,
        show_sinnoh_sheet: void,
        show_national_sheet: void,
        cmd_1ec: void,
        store_trophy_pokemon: StoreTrophyPokemon,
        cmd_1ef: Cmd_1ef,
        cmd_1f0: Cmd_1f0,
        check_act_fossil: CheckActFossil,
        cmd_1f2: void,
        cmd_1f3: void,
        check_item_chosen: CheckItemChosen,
        compare_item_poke_fossil: CompareItemPokeFossil,
        check_pokemon_level: CheckPokemonLevel,
        check_is_pokemon_poisoned: CheckIsPokemonPoisoned,
        pre_wfc: void,
        store_furniture: StoreFurniture,
        copy_furniture: CopyFurniture,
        set_b_castle_function_id: SetBCastleFunctionId,
        b_castle_funct_return: BCastleFunctReturn,
        cmd_200: Cmd_200,
        check_effect_hm: CheckEffectHm,
        great_marsh_function: GreatMarshFunction,
        battle_poke_colosseum: BattlePokeColosseum,
        warp_last_elevator: void,
        open_geo_net: void,
        great_marsh_bynocule: void,
        store_poke_colosseum_lost: StorePokeColosseumLost,
        pokemon_picture: PokemonPicture,
        hide_picture: void,
        cmd_20a: Cmd_20a,
        cmd_20b: void,
        cmd_20c: void,
        setvar_mt_coronet: SetvarMtCoronet,
        cmd_20e: void,
        check_quic_trine_coordinates: CheckQuicTrineCoordinates,
        setvar_quick_train_coordinates: SetvarQuickTrainCoordinates,
        move_train_anm: MoveTrainAnm,
        store_poke_nature: StorePokeNature,
        check_poke_nature: CheckPokeNature,
        random_hallowes: RandomHallowes,
        start_amity: void,
        cmd_216: Cmd_216,
        cmd_217: Cmd_217,
        chs_r_s_poke: ChsRSPoke,
        set_s_poke: SetSPoke,
        check_s_poke: CheckSPoke,
        cmd_21b: void,
        act_swarm_poke: ActSwarmPoke,
        cmd_21d: Cmd_21d,
        cmd_21e: void,
        check_move_remember: CheckMoveRemember,
        cmd_220: void,
        store_poke_remember: StorePokeRemember,
        cmd_222: void,
        store_remember_move: void,
        teach_move: TeachMove,
        check_teach_move: CheckTeachMove,
        set_trade_id: SetTradeId,
        check_pokemon_trade: CheckPokemonTrade,
        trade_chosen_pokemon: TradeChosenPokemon,
        stop_trade: void,
        cmd_22b: void,
        close_oak_assistant_event: void,
        check_nat_pokedex_status: CheckNatPokedexStatus,
        check_ribbon_number: CheckRibbonNumber,
        check_ribbon: CheckRibbon,
        give_ribbon: GiveRibbon,
        setvar_ribbon: SetvarRibbon,
        check_happy_ribbon: CheckHappyRibbon,
        check_pokemart: CheckPokemart,
        check_furniture: CheckFurniture,
        cmd_236: Cmd_236,
        check_phrase_box_input: CheckPhraseBoxInput,
        check_status_phrase_box: CheckStatusPhraseBox,
        decide_rules: DecideRules,
        check_foot_step: CheckFootStep,
        heal_pokemon_animation: HealPokemonAnimation,
        store_elevator_direction: StoreElevatorDirection,
        ship_animation: ShipAnimation,
        cmd_23e: Cmd_23e,
        store_phrase_box1_w: StorePhraseBox1W,
        store_phrase_box2_w: StorePhraseBox2W,
        setvar_phrase_box1_w: SetvarPhraseBox1W,
        store_mt_coronet: StoreMtCoronet,
        check_first_poke_party: CheckFirstPokeParty,
        check_poke_type: CheckPokeType,
        check_phrase_box_input2: CheckPhraseBoxInput2,
        store_und_time: StoreUndTime,
        prepare_pc_animation: PreparePcAnimation,
        open_pc_animation: OpenPcAnimation,
        close_pc_animation: ClosePcAnimation,
        check_lotto_number: CheckLottoNumber,
        compare_lotto_number: CompareLottoNumber,
        setvar_id_poke_boxes: SetvarIdPokeBoxes,
        cmd_250: void,
        check_boxes_number: CheckBoxesNumber,
        stop_great_marsh: StopGreatMarsh,
        check_poke_catching_show: CheckPokeCatchingShow,
        close_catching_show: void,
        check_catching_show_records: CheckCatchingShowRecords,
        sprt_save: void,
        ret_sprt_save: void,
        elev_lg_animation: void,
        check_elev_lg_anm: CheckElevLgAnm,
        elev_ir_anm: void,
        stop_elev_anm: void,
        check_elev_position: CheckElevPosition,
        galact_anm: void,
        galact_anm2: void,
        main_event: MainEvent,
        check_accessories3: CheckAccessories3,
        act_deoxis_form_change: ActDeoxisFormChange,
        change_form_deoxis: ChangeFormDeoxis,
        check_coombe_event: CheckCoombeEvent,
        act_contest_map: void,
        cmd_266: void,
        pokecasino: Pokecasino,
        check_time2: CheckTime2,
        regigigas_anm: RegigigasAnm,
        cresselia_anm: CresseliaAnm,
        check_regi: CheckRegi,
        check_massage: CheckMassage,
        unown_message_box: UnownMessageBox,
        check_p_catching_show: CheckPCatchingShow,
        cmd_26f: void,
        shaymin_anm: ShayminAnm,
        thank_name_insert: ThankNameInsert,
        setvar_shaymin: SetvarShaymin,
        setvar_accessories2: SetvarAccessories2,
        cmd_274: Cmd_274,
        check_record_casino: CheckRecordCasino,
        check_coins_casino: CheckCoinsCasino,
        srt_random_num: SrtRandomNum,
        check_poke_level2: CheckPokeLevel2,
        cmd_279: Cmd_279,
        league_castle_view: void,
        cmd_27b: void,
        setvar_amity_pokemon: SetvarAmityPokemon,
        cmd_27d: Cmd_27d,
        check_first_time_v_shop: CheckFirstTimeVShop,
        cmd_27f: Cmd_27f,
        setvar_id_number: SetvarIdNumber,
        cmd_281: Cmd_281,
        setvar_unk: SetvarUnk,
        cmd_283: Cmd_283,
        check_ruin_maniac: CheckRuinManiac,
        check_turn_back: CheckTurnBack,
        check_ug_people_num: CheckUgPeopleNum,
        check_ug_fossil_num: CheckUgFossilNum,
        check_ug_traps_num: CheckUgTrapsNum,
        check_poffin_item: CheckPoffinItem,
        check_poffin_case_status: CheckPoffinCaseStatus,
        unk_funct2: UnkFunct2,
        pokemon_party_picture: PokemonPartyPicture,
        act_learning: void,
        set_sound_learning: SetSoundLearning,
        check_first_time_champion: CheckFirstTimeChampion,
        choose_poke_d_care: ChoosePokeDCare,
        store_poke_d_care: StorePokeDCare,
        cmd_292: Cmd_292,
        check_master_rank: CheckMasterRank,
        show_battle_points_box: ShowBattlePointsBox,
        hide_battle_points_box: void,
        update_battle_points_box: void,
        take_b_points: TakeBPoints,
        check_b_points: CheckBPoints,
        cmd_29c: Cmd_29c,
        choice_multi: ChoiceMulti,
        h_m_effect: HMEffect,
        camera_bump_effect: CameraBumpEffect,
        double_battle: DoubleBattle,
        apply_movement2: ApplyMovement2,
        cmd_2a2: Cmd_2a2,
        store_act_hero_friend_code: StoreActHeroFriendCode,
        store_act_other_friend_code: StoreActOtherFriendCode,
        choose_trade_pokemon: void,
        chs_prize_casino: ChsPrizeCasino,
        check_plate: CheckPlate,
        take_coins_casino: TakeCoinsCasino,
        check_coins_casino2: CheckCoinsCasino2,
        compare_phrase_box_input: ComparePhraseBoxInput,
        store_seal_num: StoreSealNum,
        activate_mystery_gift: void,
        check_follow_battle: CheckFollowBattle,
        cmd_2af: Cmd_2af,
        cmd_2b0: void,
        cmd_2b1: void,
        cmd_2b2: void,
        setvar_seal_random: SetvarSealRandom,
        darkrai_function: DarkraiFunction,
        cmd_2b6: Cmd_2b6,
        store_poke_num_party: StorePokeNumParty,
        store_poke_nickname: StorePokeNickname,
        close_multi_union: void,
        check_battle_union: CheckBattleUnion,
        cmd_2_b_b: void,
        check_wild_battle2: CheckWildBattle2,
        wild_battle2: WildBattle,
        store_trainer_card_star: StoreTrainerCardStar,
        bike_ride: void,
        cmd_2c0: Cmd_2c0,
        show_save_box: void,
        hide_save_box: void,
        cmd_2c3: Cmd_2c3,
        show_b_tower_some: ShowBTowerSome,
        delete_saves_b_factory: DeleteSavesBFactory,
        spin_trade_union: void,
        check_version_game: CheckVersionGame,
        show_b_arcade_recors: ShowBArcadeRecors,
        eterna_gym_anm: void,
        floral_clock_animation: void,
        check_poke_party2: CheckPokeParty2,
        check_poke_castle: CheckPokeCastle,
        act_team_galactic_events: ActTeamGalacticEvents,
        choose_wire_poke_b_castle: ChooseWirePokeBCastle,
        cmd_2d0: Cmd_2d0,
        cmd_2d1: Cmd_2d1,
        cmd_2d2: Cmd_2d2,
        cmd_2d3: Cmd_2d3,
        cmd_2d4: Cmd_2d4,
        cmd_2d5: Cmd_2d5,
        cmd_2d6: void,
        cmd_2d7: Cmd_2d7,
        cmd_2d8: Cmd_2d8,
        cmd_2d9: Cmd_2d9,
        cmd_2da: Cmd_2da,
        cmd_2db: Cmd_2db,
        cmd_2dc: Cmd_2dc,
        cmd_2dd: Cmd_2dd,
        cmd_2de: Cmd_2de,
        cmd_2df: Cmd_2df,
        cmd_2e0: Cmd_2e0,
        cmd_2e1: Cmd_2e1,
        cmd_2e2: void,
        cmd_2e3: void,
        cmd_2e4: Cmd_2e4,
        cmd_2e5: Cmd_2e5,
        cmd_2e6: Cmd_2e6,
        cmd_2e7: Cmd_2e7,
        cmd_2e8: Cmd_2e8,
        cmd_2e9: Cmd_2e9,
        cmd_2ea: Cmd_2ea,
        cmd_2eb: Cmd_2eb,
        cmd_2ec: Cmd_2ec,
        cmd_2ed: void,
        cmd_2ee: Cmd_2ee,
        cmd_2f0: void,
        cmd_2f2: void,
        cmd_2f3: Cmd_2f3,
        cmd_2f4: Cmd_2f4,
        cmd_2f5: Cmd_2f5,
        cmd_2f6: Cmd_2f6,
        cmd_2f7: Cmd_2f7,
        cmd_2f8: void,
        cmd_2f9: Cmd_2f9,
        cmd_2fa: Cmd_2fa,
        cmd_2fb: void,
        cmd_2fc: Cmd_2fc,
        cmd_2fd: Cmd_2fd,
        cmd_2fe: Cmd_2fe,
        cmd_2ff: Cmd_2ff,
        cmd_300: void,
        cmd_302: Cmd_302,
        cmd_303: Cmd_303,
        cmd_304: Cmd_304,
        cmd_305: Cmd_305,
        cmd_306: Cmd_306,
        cmd_307: Cmd_307,
        cmd_308: Cmd_308,
        cmd_309: void,
        cmd_30a: Cmd_30a,
        cmd_30b: void,
        cmd_30c: void,
        cmd_30d: Cmd_30d,
        cmd_30e: Cmd_30e,
        cmd_30f: Cmd_30f,
        cmd_310: void,
        cmd_311: Cmd_311,
        cmd_312: Cmd_312,
        cmd_313: Cmd_313,
        cmd_314: Cmd_314,
        cmd_315: Cmd_315,
        cmd_316: void,
        cmd_317: Cmd_317,
        wild_battle3: WildBattle,
        cmd_319: Cmd_319,
        cmd_31a: Cmd_31a,
        cmd_31b: Cmd_31b,
        cmd_31c: Cmd_31c,
        cmd_31d: Cmd_31d,
        cmd_31e: Cmd_31e,
        cmd_31f: void,
        cmd_320: void,
        cmd_321: Cmd_321,
        cmd_322: void,
        cmd_323: Cmd_323,
        cmd_324: Cmd_324,
        cmd_325: Cmd_325,
        cmd_326: Cmd_326,
        cmd_327: Cmd_327,
        portal_effect: PortalEffect,
        cmd_329: Cmd_329,
        cmd_32a: Cmd_32a,
        cmd_32b: Cmd_32b,
        cmd_32c: Cmd_32c,
        cmd_32d: void,
        cmd_32e: void,
        cmd_32f: Cmd_32f,
        cmd_330: void,
        cmd_331: void,
        cmd_332: void,
        cmd_333: Cmd_333,
        cmd_334: Cmd_334,
        cmd_335: Cmd_335,
        cmd_336: Cmd_336,
        cmd_337: Cmd_337,
        cmd_338: void,
        cmd_339: void,
        cmd_33a: Cmd_33a,
        cmd_33c: Cmd_33c,
        cmd_33d: Cmd_33d,
        cmd_33e: Cmd_33e,
        cmd_33f: Cmd_33f,
        cmd_340: Cmd_340,
        cmd_341: Cmd_341,
        cmd_342: Cmd_342,
        cmd_343: Cmd_343,
        cmd_344: Cmd_344,
        cmd_345: Cmd_345,
        cmd_346: Cmd_346,
        display_floor: DisplayFloor,
    };
    pub const Kind = enum(u16) {
        nop0 = lu16.init(0x0).inner,
        nop1 = lu16.init(0x1).inner,
        end = lu16.init(0x2).inner,
        return2 = lu16.init(0x3).inner,
        cmd_a = lu16.init(0xa).inner,
        @"if" = lu16.init(0x11).inner,
        if2 = lu16.init(0x12).inner,
        call_standard = lu16.init(0x14).inner,
        exit_standard = lu16.init(0x15).inner,
        jump = lu16.init(0x16).inner,
        call = lu16.init(0x1a).inner,
        @"return" = lu16.init(0x1b).inner,
        compare_last_result_jump = lu16.init(0x1c).inner,
        compare_last_result_call = lu16.init(0x1d).inner,
        set_flag = lu16.init(0x1e).inner,
        clear_flag = lu16.init(0x1f).inner,
        check_flag = lu16.init(0x20).inner,
        cmd_21 = lu16.init(0x21).inner,
        cmd_22 = lu16.init(0x22).inner,
        set_trainer_id = lu16.init(0x23).inner,
        cmd_24 = lu16.init(0x24).inner,
        clear_trainer_id = lu16.init(0x25).inner,
        script_cmd__add_value = lu16.init(0x26).inner,
        script_cmd__sub_value = lu16.init(0x27).inner,
        set_var = lu16.init(0x28).inner,
        copy_var = lu16.init(0x29).inner,
        message2 = lu16.init(0x2b).inner,
        message = lu16.init(0x2c).inner,
        message3 = lu16.init(0x2d).inner,
        message4 = lu16.init(0x2e).inner,
        message5 = lu16.init(0x2f).inner,
        cmd_30 = lu16.init(0x30).inner,
        wait_button = lu16.init(0x31).inner,
        cmd_32 = lu16.init(0x32).inner,
        cmd_33 = lu16.init(0x33).inner,
        close_msg_on_key_press = lu16.init(0x34).inner,
        freeze_message_box = lu16.init(0x35).inner,
        call_message_box = lu16.init(0x36).inner,
        color_msg_box = lu16.init(0x37).inner,
        type_message_box = lu16.init(0x38).inner,
        no_map_message_box = lu16.init(0x39).inner,
        call_text_msg_box = lu16.init(0x3a).inner,
        store_menu_status = lu16.init(0x3b).inner,
        show_menu = lu16.init(0x3c).inner,
        yes_no_box = lu16.init(0x3e).inner,
        multi = lu16.init(0x40).inner,
        multi2 = lu16.init(0x41).inner,
        cmd_42 = lu16.init(0x42).inner,
        close_multi = lu16.init(0x43).inner,
        multi3 = lu16.init(0x44).inner,
        multi4 = lu16.init(0x45).inner,
        txt_msg_scrp_multi = lu16.init(0x46).inner,
        close_multi4 = lu16.init(0x47).inner,
        play_fanfare = lu16.init(0x49).inner,
        multi_row = lu16.init(0x48).inner,
        play_fanfare2 = lu16.init(0x4a).inner,
        wait_fanfare = lu16.init(0x4b).inner,
        play_cry = lu16.init(0x4c).inner,
        wait_cry = lu16.init(0x4d).inner,
        soundfr = lu16.init(0x4e).inner,
        cmd_4f = lu16.init(0x4f).inner,
        play_sound = lu16.init(0x50).inner,
        stop = lu16.init(0x51).inner,
        restart = lu16.init(0x52).inner,
        cmd_53 = lu16.init(0x53).inner,
        switch_music = lu16.init(0x54).inner,
        store_saying_learned = lu16.init(0x55).inner,
        play_sound2 = lu16.init(0x57).inner,
        cmd_58 = lu16.init(0x58).inner,
        check_saying_learned = lu16.init(0x59).inner,
        swith_music2 = lu16.init(0x5a).inner,
        act_microphone = lu16.init(0x5b).inner,
        deact_microphone = lu16.init(0x5c).inner,
        cmd_5d = lu16.init(0x5d).inner,
        apply_movement = lu16.init(0x5e).inner,
        wait_movement = lu16.init(0x5f).inner,
        lock_all = lu16.init(0x60).inner,
        release_all = lu16.init(0x61).inner,
        lock = lu16.init(0x62).inner,
        release = lu16.init(0x63).inner,
        add_people = lu16.init(0x64).inner,
        remove_people = lu16.init(0x65).inner,
        lock_cam = lu16.init(0x66).inner,
        zoom_cam = lu16.init(0x67).inner,
        face_player = lu16.init(0x68).inner,
        check_sprite_position = lu16.init(0x69).inner,
        check_person_position = lu16.init(0x6b).inner,
        continue_follow = lu16.init(0x6c).inner,
        follow_hero = lu16.init(0x6d).inner,
        take_money = lu16.init(0x70).inner,
        check_money = lu16.init(0x71).inner,
        show_money = lu16.init(0x72).inner,
        hide_money = lu16.init(0x73).inner,
        update_money = lu16.init(0x74).inner,
        show_coins = lu16.init(0x75).inner,
        hide_coins = lu16.init(0x76).inner,
        update_coins = lu16.init(0x77).inner,
        check_coins = lu16.init(0x78).inner,
        give_coins = lu16.init(0x79).inner,
        take_coins = lu16.init(0x7a).inner,
        take_item = lu16.init(0x7b).inner,
        give_item = lu16.init(0x7c).inner,
        check_store_item = lu16.init(0x7d).inner,
        check_item = lu16.init(0x7e).inner,
        store_item_taken = lu16.init(0x7f).inner,
        store_item_type = lu16.init(0x80).inner,
        send_item_type1 = lu16.init(0x83).inner,
        cmd_84 = lu16.init(0x84).inner,
        check_underground_pc_status = lu16.init(0x85).inner,
        cmd_86 = lu16.init(0x86).inner,
        send_item_type2 = lu16.init(0x87).inner,
        cmd_88 = lu16.init(0x88).inner,
        cmd_89 = lu16.init(0x89).inner,
        cmd_8a = lu16.init(0x8a).inner,
        cmd_8b = lu16.init(0x8b).inner,
        cmd_8c = lu16.init(0x8c).inner,
        cmd_8d = lu16.init(0x8d).inner,
        cmd_8e = lu16.init(0x8e).inner,
        send_item_type3 = lu16.init(0x8f).inner,
        check_pokemon_party = lu16.init(0x93).inner,
        store_pokemon_party = lu16.init(0x94).inner,
        set_pokemon_party_stored = lu16.init(0x95).inner,
        give_pokemon = lu16.init(0x96).inner,
        give_egg = lu16.init(0x97).inner,
        check_move = lu16.init(0x99).inner,
        check_place_stored = lu16.init(0x9a).inner,
        cmd_9b = lu16.init(0x9b).inner,
        cmd_9c = lu16.init(0x9c).inner,
        cmd_9d = lu16.init(0x9d).inner,
        cmd_9e = lu16.init(0x9e).inner,
        cmd_9f = lu16.init(0x9f).inner,
        cmd_a0 = lu16.init(0xa0).inner,
        call_end = lu16.init(0xa1).inner,
        cmd__a2 = lu16.init(0xa2).inner,
        wfc_ = lu16.init(0xa3).inner,
        cmd_a4 = lu16.init(0xa4).inner,
        interview = lu16.init(0xa5).inner,
        dress_pokemon = lu16.init(0xa6).inner,
        display_dressed_pokemon = lu16.init(0xa7).inner,
        display_contest_pokemon = lu16.init(0xa8).inner,
        open_ball_capsule = lu16.init(0xa9).inner,
        open_sinnoh_maps = lu16.init(0xaa).inner,
        open_pc_function = lu16.init(0xab).inner,
        draw_union = lu16.init(0xac).inner,
        trainer_case_union = lu16.init(0xad).inner,
        trade_union = lu16.init(0xae).inner,
        record_mixing_union = lu16.init(0xaf).inner,
        end_game = lu16.init(0xb0).inner,
        hall_fame_anm = lu16.init(0xb1).inner,
        store_wfc_status = lu16.init(0xb2).inner,
        start_wfc = lu16.init(0xb3).inner,
        choose_starter = lu16.init(0xb4).inner,
        battle_starter = lu16.init(0xb5).inner,
        battle_id = lu16.init(0xb6).inner,
        set_var_battle = lu16.init(0xb7).inner,
        check_battle_type = lu16.init(0xb8).inner,
        set_var_battle2 = lu16.init(0xb9).inner,
        choose_poke_nick = lu16.init(0xbb).inner,
        fade_screen = lu16.init(0xbc).inner,
        reset_screen = lu16.init(0xbd).inner,
        warp = lu16.init(0xbe).inner,
        rock_climb_animation = lu16.init(0xbf).inner,
        surf_animation = lu16.init(0xc0).inner,
        waterfall_animation = lu16.init(0xc1).inner,
        flash_animation = lu16.init(0xc3).inner,
        defog_animation = lu16.init(0xc4).inner,
        prep_hm_effect = lu16.init(0xc5).inner,
        tuxedo = lu16.init(0xc6).inner,
        check_bike = lu16.init(0xc7).inner,
        ride_bike = lu16.init(0xc8).inner,
        ride_bike2 = lu16.init(0xc9).inner,
        give_poke_hiro_anm = lu16.init(0xcb).inner,
        stop_give_poke_hiro_anm = lu16.init(0xcc).inner,
        set_var_hero = lu16.init(0xcd).inner,
        set_variable_rival = lu16.init(0xce).inner,
        set_var_alter = lu16.init(0xcf).inner,
        set_var_poke = lu16.init(0xd0).inner,
        set_var_item = lu16.init(0xd1).inner,
        set_var_item_num = lu16.init(0xd2).inner,
        set_var_atk_item = lu16.init(0xd3).inner,
        set_var_atk = lu16.init(0xd4).inner,
        set_variable_number = lu16.init(0xd5).inner,
        set_var_poke_nick = lu16.init(0xd6).inner,
        set_var_obj = lu16.init(0xd7).inner,
        set_var_trainer = lu16.init(0xd8).inner,
        set_var_wi_fi_sprite = lu16.init(0xd9).inner,
        set_var_poke_stored = lu16.init(0xda).inner,
        set_var_str_hero = lu16.init(0xdb).inner,
        set_var_str_rival = lu16.init(0xdc).inner,
        store_starter = lu16.init(0xde).inner,
        cmd_df = lu16.init(0xdf).inner,
        set_var_item_stored = lu16.init(0xe0).inner,
        set_var_item_stored2 = lu16.init(0xe1).inner,
        set_var_swarm_poke = lu16.init(0xe2).inner,
        check_swarm_poke = lu16.init(0xe3).inner,
        start_battle_analysis = lu16.init(0xe4).inner,
        trainer_battle = lu16.init(0xe5).inner,
        endtrainer_battle = lu16.init(0xe6).inner,
        trainer_battle_stored = lu16.init(0xe7).inner,
        trainer_battle_stored2 = lu16.init(0xe8).inner,
        check_trainer_status = lu16.init(0xe9).inner,
        store_league_trainer = lu16.init(0xea).inner,
        lost_go_pc = lu16.init(0xeb).inner,
        check_trainer_lost = lu16.init(0xec).inner,
        check_trainer_status2 = lu16.init(0xed).inner,
        store_poke_party_defeated = lu16.init(0xee).inner,
        chs_friend = lu16.init(0xf2).inner,
        wire_battle_wait = lu16.init(0xf3).inner,
        cmd_f6 = lu16.init(0xf6).inner,
        pokecontest = lu16.init(0xf7).inner,
        start_ovation = lu16.init(0xf8).inner,
        stop_ovation = lu16.init(0xf9).inner,
        cmd_fa = lu16.init(0xfa).inner,
        cmd_fb = lu16.init(0xfb).inner,
        cmd_fc = lu16.init(0xfc).inner,
        setvar_other_entry = lu16.init(0xfd).inner,
        cmd_fe = lu16.init(0xfe).inner,
        setvat_hiro_entry = lu16.init(0xff).inner,
        cmd_100 = lu16.init(0x100).inner,
        black_flash_effect = lu16.init(0x101).inner,
        setvar_type_contest = lu16.init(0x102).inner,
        setvar_rank_contest = lu16.init(0x103).inner,
        cmd_104 = lu16.init(0x104).inner,
        cmd_105 = lu16.init(0x105).inner,
        cmd_106 = lu16.init(0x106).inner,
        cmd_107 = lu16.init(0x107).inner,
        store_people_id_contest = lu16.init(0x108).inner,
        cmd_109 = lu16.init(0x109).inner,
        setvat_hiro_entry2 = lu16.init(0x10a).inner,
        act_people_contest = lu16.init(0x10b).inner,
        cmd_10c = lu16.init(0x10c).inner,
        cmd_10d = lu16.init(0x10d).inner,
        cmd_10e = lu16.init(0x10e).inner,
        cmd_10f = lu16.init(0x10f).inner,
        cmd_110 = lu16.init(0x110).inner,
        flash_contest = lu16.init(0x111).inner,
        end_flash = lu16.init(0x112).inner,
        carpet_anm = lu16.init(0x113).inner,
        cmd_114 = lu16.init(0x114).inner,
        cmd_115 = lu16.init(0x115).inner,
        show_lnk_cnt_record = lu16.init(0x116).inner,
        cmd_117 = lu16.init(0x117).inner,
        cmd_118 = lu16.init(0x118).inner,
        store_pokerus = lu16.init(0x119).inner,
        warp_map_elevator = lu16.init(0x11b).inner,
        check_floor = lu16.init(0x11c).inner,
        start_lift = lu16.init(0x11d).inner,
        store_sin_pokemon_seen = lu16.init(0x11e).inner,
        cmd_11f = lu16.init(0x11f).inner,
        store_tot_pokemon_seen = lu16.init(0x120).inner,
        store_nat_pokemon_seen = lu16.init(0x121).inner,
        set_var_text_pokedex = lu16.init(0x123).inner,
        wild_battle = lu16.init(0x124).inner,
        starter_battle = lu16.init(0x125).inner,
        explanation_battle = lu16.init(0x126).inner,
        honey_tree_battle = lu16.init(0x127).inner,
        check_if_honey_slathered = lu16.init(0x128).inner,
        random_battle = lu16.init(0x129).inner,
        stop_random_battle = lu16.init(0x12a).inner,
        write_autograph = lu16.init(0x12b).inner,
        store_save_data = lu16.init(0x12c).inner,
        check_save_data = lu16.init(0x12d).inner,
        check_dress = lu16.init(0x12e).inner,
        check_contest_win = lu16.init(0x12f).inner,
        store_photo_name = lu16.init(0x130).inner,
        give_poketch = lu16.init(0x131).inner,
        check_ptch_appl = lu16.init(0x132).inner,
        act_pktch_appl = lu16.init(0x133).inner,
        store_poketch_app = lu16.init(0x134).inner,
        friend_b_t = lu16.init(0x135).inner,
        friend_b_t2 = lu16.init(0x136).inner,
        cmd_138 = lu16.init(0x138).inner,
        open_union_function2 = lu16.init(0x139).inner,
        start_union = lu16.init(0x13a).inner,
        link_closed = lu16.init(0x13b).inner,
        set_union_function_id = lu16.init(0x13c).inner,
        close_union_function = lu16.init(0x13d).inner,
        close_union_function2 = lu16.init(0x13e).inner,
        set_var_union_message = lu16.init(0x13f).inner,
        store_your_decision_union = lu16.init(0x140).inner,
        store_other_decision_union = lu16.init(0x141).inner,
        cmd_142 = lu16.init(0x142).inner,
        check_other_decision_union = lu16.init(0x143).inner,
        store_your_decision_union2 = lu16.init(0x144).inner,
        store_other_decision_union2 = lu16.init(0x145).inner,
        check_other_decision_union2 = lu16.init(0x146).inner,
        pokemart = lu16.init(0x147).inner,
        pokemart1 = lu16.init(0x148).inner,
        pokemart2 = lu16.init(0x149).inner,
        pokemart3 = lu16.init(0x14a).inner,
        defeat_go_pokecenter = lu16.init(0x14b).inner,
        act_bike = lu16.init(0x14c).inner,
        check_gender = lu16.init(0x14d).inner,
        heal_pokemon = lu16.init(0x14e).inner,
        deact_wireless = lu16.init(0x14f).inner,
        delete_entry = lu16.init(0x150).inner,
        cmd_151 = lu16.init(0x151).inner,
        underground_id = lu16.init(0x152).inner,
        union_room = lu16.init(0x153).inner,
        open_wi_fi_sprite = lu16.init(0x154).inner,
        store_wi_fi_sprite = lu16.init(0x155).inner,
        act_wi_fi_sprite = lu16.init(0x156).inner,
        cmd_157 = lu16.init(0x157).inner,
        activate_pokedex = lu16.init(0x158).inner,
        give_running_shoes = lu16.init(0x15a).inner,
        check_badge = lu16.init(0x15b).inner,
        enable_badge = lu16.init(0x15c).inner,
        disable_badge = lu16.init(0x15d).inner,
        check_follow = lu16.init(0x160).inner,
        start_follow = lu16.init(0x161).inner,
        stop_follow = lu16.init(0x162).inner,
        cmd_164 = lu16.init(0x164).inner,
        cmd_166 = lu16.init(0x166).inner,
        prepare_door_animation = lu16.init(0x168).inner,
        wait_action = lu16.init(0x169).inner,
        wait_close = lu16.init(0x16a).inner,
        open_door = lu16.init(0x16b).inner,
        close_door = lu16.init(0x16c).inner,
        act_dcare_function = lu16.init(0x16d).inner,
        store_p_d_care_num = lu16.init(0x16e).inner,
        pastoria_city_function = lu16.init(0x16f).inner,
        pastoria_city_function2 = lu16.init(0x170).inner,
        hearthrome_gym_function = lu16.init(0x171).inner,
        hearthrome_gym_function2 = lu16.init(0x172).inner,
        canalave_gym_function = lu16.init(0x173).inner,
        veilstone_gym_function = lu16.init(0x174).inner,
        sunishore_gym_function = lu16.init(0x175).inner,
        sunishore_gym_function2 = lu16.init(0x176).inner,
        check_party_number = lu16.init(0x177).inner,
        open_berry_pouch = lu16.init(0x178).inner,
        cmd_179 = lu16.init(0x179).inner,
        cmd_17a = lu16.init(0x17a).inner,
        cmd_17b = lu16.init(0x17b).inner,
        set_nature_pokemon = lu16.init(0x17c).inner,
        cmd_17d = lu16.init(0x17d).inner,
        cmd_17e = lu16.init(0x17e).inner,
        cmd_17f = lu16.init(0x17f).inner,
        cmd_180 = lu16.init(0x180).inner,
        cmd_181 = lu16.init(0x181).inner,
        check_deoxis = lu16.init(0x182).inner,
        cmd_183 = lu16.init(0x183).inner,
        cmd_184 = lu16.init(0x184).inner,
        cmd_185 = lu16.init(0x185).inner,
        change_ow_position = lu16.init(0x186).inner,
        set_ow_position = lu16.init(0x187).inner,
        change_ow_movement = lu16.init(0x188).inner,
        release_ow = lu16.init(0x189).inner,
        set_tile_passable = lu16.init(0x18a).inner,
        set_tile_locked = lu16.init(0x18b).inner,
        set_ows_follow = lu16.init(0x18c).inner,
        show_clock_save = lu16.init(0x18d).inner,
        hide_clock_save = lu16.init(0x18e).inner,
        cmd_18f = lu16.init(0x18f).inner,
        set_save_data = lu16.init(0x190).inner,
        chs_pokemenu = lu16.init(0x191).inner,
        chs_pokemenu2 = lu16.init(0x192).inner,
        store_poke_menu2 = lu16.init(0x193).inner,
        chs_poke_contest = lu16.init(0x194).inner,
        store_poke_contest = lu16.init(0x195).inner,
        show_poke_info = lu16.init(0x196).inner,
        store_poke_move = lu16.init(0x197).inner,
        check_poke_egg = lu16.init(0x198).inner,
        compare_poke_nick = lu16.init(0x199).inner,
        check_party_number_union = lu16.init(0x19a).inner,
        check_poke_party_health = lu16.init(0x19b).inner,
        check_poke_party_num_d_care = lu16.init(0x19c).inner,
        check_egg_union = lu16.init(0x19d).inner,
        underground_function = lu16.init(0x19e).inner,
        underground_function2 = lu16.init(0x19f).inner,
        underground_start = lu16.init(0x1a0).inner,
        take_money_d_care = lu16.init(0x1a3).inner,
        take_pokemon_d_care = lu16.init(0x1a4).inner,
        act_egg_day_c_man = lu16.init(0x1a8).inner,
        deact_egg_day_c_man = lu16.init(0x1a9).inner,
        set_var_poke_and_money_d_care = lu16.init(0x1aa).inner,
        check_money_d_care = lu16.init(0x1ab).inner,
        egg_animation = lu16.init(0x1ac).inner,
        set_var_poke_and_level_d_care = lu16.init(0x1ae).inner,
        set_var_poke_chosen_d_care = lu16.init(0x1af).inner,
        give_poke_d_care = lu16.init(0x1b0).inner,
        add_people2 = lu16.init(0x1b1).inner,
        remove_people2 = lu16.init(0x1b2).inner,
        mail_box = lu16.init(0x1b3).inner,
        check_mail = lu16.init(0x1b4).inner,
        show_record_list = lu16.init(0x1b5).inner,
        check_time = lu16.init(0x1b6).inner,
        check_id_player = lu16.init(0x1b7).inner,
        random_text_stored = lu16.init(0x1b8).inner,
        store_happy_poke = lu16.init(0x1b9).inner,
        store_happy_status = lu16.init(0x1ba).inner,
        set_var_data_day_care = lu16.init(0x1bc).inner,
        check_face_position = lu16.init(0x1bd).inner,
        store_poke_d_care_love = lu16.init(0x1be).inner,
        check_status_solaceon_event = lu16.init(0x1bf).inner,
        check_poke_party = lu16.init(0x1c0).inner,
        copy_pokemon_height = lu16.init(0x1c1).inner,
        set_variable_pokemon_height = lu16.init(0x1c2).inner,
        compare_pokemon_height = lu16.init(0x1c3).inner,
        check_pokemon_height = lu16.init(0x1c4).inner,
        show_move_info = lu16.init(0x1c5).inner,
        store_poke_delete = lu16.init(0x1c6).inner,
        store_move_delete = lu16.init(0x1c7).inner,
        check_move_num_delete = lu16.init(0x1c8).inner,
        store_delete_move = lu16.init(0x1c9).inner,
        check_delete_move = lu16.init(0x1ca).inner,
        setvar_move_delete = lu16.init(0x1cb).inner,
        cmd_1cc = lu16.init(0x1cc).inner,
        de_activate_leader = lu16.init(0x1cd).inner,
        hm_functions = lu16.init(0x1cf).inner,
        flash_duration = lu16.init(0x1d0).inner,
        defog_duration = lu16.init(0x1d1).inner,
        give_accessories = lu16.init(0x1d2).inner,
        check_accessories = lu16.init(0x1d3).inner,
        cmd_1d4 = lu16.init(0x1d4).inner,
        give_accessories2 = lu16.init(0x1d5).inner,
        check_accessories2 = lu16.init(0x1d6).inner,
        berry_poffin = lu16.init(0x1d7).inner,
        set_var_b_tower_chs = lu16.init(0x1d8).inner,
        battle_room_result = lu16.init(0x1d9).inner,
        activate_b_tower = lu16.init(0x1da).inner,
        store_b_tower_data = lu16.init(0x1db).inner,
        close_b_tower = lu16.init(0x1dc).inner,
        call_b_tower_functions = lu16.init(0x1dd).inner,
        random_team_b_tower = lu16.init(0x1de).inner,
        store_prize_num_b_tower = lu16.init(0x1df).inner,
        store_people_id_b_tower = lu16.init(0x1e0).inner,
        call_b_tower_wire_function = lu16.init(0x1e1).inner,
        store_p_chosen_wire_b_tower = lu16.init(0x1e2).inner,
        store_rank_data_wire_b_tower = lu16.init(0x1e3).inner,
        cmd_1e4 = lu16.init(0x1e4).inner,
        random_event = lu16.init(0x1e5).inner,
        check_sinnoh_pokedex = lu16.init(0x1e8).inner,
        check_national_pokedex = lu16.init(0x1e9).inner,
        show_sinnoh_sheet = lu16.init(0x1ea).inner,
        show_national_sheet = lu16.init(0x1eb).inner,
        cmd_1ec = lu16.init(0x1ec).inner,
        store_trophy_pokemon = lu16.init(0x1ed).inner,
        cmd_1ef = lu16.init(0x1ef).inner,
        cmd_1f0 = lu16.init(0x1f0).inner,
        check_act_fossil = lu16.init(0x1f1).inner,
        cmd_1f2 = lu16.init(0x1f2).inner,
        cmd_1f3 = lu16.init(0x1f3).inner,
        check_item_chosen = lu16.init(0x1f4).inner,
        compare_item_poke_fossil = lu16.init(0x1f5).inner,
        check_pokemon_level = lu16.init(0x1f6).inner,
        check_is_pokemon_poisoned = lu16.init(0x1f7).inner,
        pre_wfc = lu16.init(0x1f8).inner,
        store_furniture = lu16.init(0x1f9).inner,
        copy_furniture = lu16.init(0x1fb).inner,
        set_b_castle_function_id = lu16.init(0x1fe).inner,
        b_castle_funct_return = lu16.init(0x1ff).inner,
        cmd_200 = lu16.init(0x200).inner,
        check_effect_hm = lu16.init(0x201).inner,
        great_marsh_function = lu16.init(0x202).inner,
        battle_poke_colosseum = lu16.init(0x203).inner,
        warp_last_elevator = lu16.init(0x204).inner,
        open_geo_net = lu16.init(0x205).inner,
        great_marsh_bynocule = lu16.init(0x206).inner,
        store_poke_colosseum_lost = lu16.init(0x207).inner,
        pokemon_picture = lu16.init(0x208).inner,
        hide_picture = lu16.init(0x209).inner,
        cmd_20a = lu16.init(0x20a).inner,
        cmd_20b = lu16.init(0x20b).inner,
        cmd_20c = lu16.init(0x20c).inner,
        setvar_mt_coronet = lu16.init(0x20d).inner,
        cmd_20e = lu16.init(0x20e).inner,
        check_quic_trine_coordinates = lu16.init(0x20f).inner,
        setvar_quick_train_coordinates = lu16.init(0x210).inner,
        move_train_anm = lu16.init(0x211).inner,
        store_poke_nature = lu16.init(0x212).inner,
        check_poke_nature = lu16.init(0x213).inner,
        random_hallowes = lu16.init(0x214).inner,
        start_amity = lu16.init(0x215).inner,
        cmd_216 = lu16.init(0x216).inner,
        cmd_217 = lu16.init(0x217).inner,
        chs_r_s_poke = lu16.init(0x218).inner,
        set_s_poke = lu16.init(0x219).inner,
        check_s_poke = lu16.init(0x21a).inner,
        cmd_21b = lu16.init(0x21b).inner,
        act_swarm_poke = lu16.init(0x21c).inner,
        cmd_21d = lu16.init(0x21d).inner,
        cmd_21e = lu16.init(0x21e).inner,
        check_move_remember = lu16.init(0x21f).inner,
        cmd_220 = lu16.init(0x220).inner,
        store_poke_remember = lu16.init(0x221).inner,
        cmd_222 = lu16.init(0x222).inner,
        store_remember_move = lu16.init(0x223).inner,
        teach_move = lu16.init(0x224).inner,
        check_teach_move = lu16.init(0x225).inner,
        set_trade_id = lu16.init(0x226).inner,
        check_pokemon_trade = lu16.init(0x228).inner,
        trade_chosen_pokemon = lu16.init(0x229).inner,
        stop_trade = lu16.init(0x22a).inner,
        cmd_22b = lu16.init(0x22b).inner,
        close_oak_assistant_event = lu16.init(0x22c).inner,
        check_nat_pokedex_status = lu16.init(0x22d).inner,
        check_ribbon_number = lu16.init(0x22f).inner,
        check_ribbon = lu16.init(0x230).inner,
        give_ribbon = lu16.init(0x231).inner,
        setvar_ribbon = lu16.init(0x232).inner,
        check_happy_ribbon = lu16.init(0x233).inner,
        check_pokemart = lu16.init(0x234).inner,
        check_furniture = lu16.init(0x235).inner,
        cmd_236 = lu16.init(0x236).inner,
        check_phrase_box_input = lu16.init(0x237).inner,
        check_status_phrase_box = lu16.init(0x238).inner,
        decide_rules = lu16.init(0x239).inner,
        check_foot_step = lu16.init(0x23a).inner,
        heal_pokemon_animation = lu16.init(0x23b).inner,
        store_elevator_direction = lu16.init(0x23c).inner,
        ship_animation = lu16.init(0x23d).inner,
        cmd_23e = lu16.init(0x23e).inner,
        store_phrase_box1_w = lu16.init(0x243).inner,
        store_phrase_box2_w = lu16.init(0x244).inner,
        setvar_phrase_box1_w = lu16.init(0x245).inner,
        store_mt_coronet = lu16.init(0x246).inner,
        check_first_poke_party = lu16.init(0x247).inner,
        check_poke_type = lu16.init(0x248).inner,
        check_phrase_box_input2 = lu16.init(0x249).inner,
        store_und_time = lu16.init(0x24a).inner,
        prepare_pc_animation = lu16.init(0x24b).inner,
        open_pc_animation = lu16.init(0x24c).inner,
        close_pc_animation = lu16.init(0x24d).inner,
        check_lotto_number = lu16.init(0x24e).inner,
        compare_lotto_number = lu16.init(0x24f).inner,
        setvar_id_poke_boxes = lu16.init(0x251).inner,
        cmd_250 = lu16.init(0x250).inner,
        check_boxes_number = lu16.init(0x252).inner,
        stop_great_marsh = lu16.init(0x253).inner,
        check_poke_catching_show = lu16.init(0x254).inner,
        close_catching_show = lu16.init(0x255).inner,
        check_catching_show_records = lu16.init(0x256).inner,
        sprt_save = lu16.init(0x257).inner,
        ret_sprt_save = lu16.init(0x258).inner,
        elev_lg_animation = lu16.init(0x259).inner,
        check_elev_lg_anm = lu16.init(0x25a).inner,
        elev_ir_anm = lu16.init(0x25b).inner,
        stop_elev_anm = lu16.init(0x25c).inner,
        check_elev_position = lu16.init(0x25d).inner,
        galact_anm = lu16.init(0x25e).inner,
        galact_anm2 = lu16.init(0x25f).inner,
        main_event = lu16.init(0x260).inner,
        check_accessories3 = lu16.init(0x261).inner,
        act_deoxis_form_change = lu16.init(0x262).inner,
        change_form_deoxis = lu16.init(0x263).inner,
        check_coombe_event = lu16.init(0x264).inner,
        act_contest_map = lu16.init(0x265).inner,
        cmd_266 = lu16.init(0x266).inner,
        pokecasino = lu16.init(0x267).inner,
        check_time2 = lu16.init(0x268).inner,
        regigigas_anm = lu16.init(0x269).inner,
        cresselia_anm = lu16.init(0x26a).inner,
        check_regi = lu16.init(0x26b).inner,
        check_massage = lu16.init(0x26c).inner,
        unown_message_box = lu16.init(0x26d).inner,
        check_p_catching_show = lu16.init(0x26e).inner,
        cmd_26f = lu16.init(0x26f).inner,
        shaymin_anm = lu16.init(0x270).inner,
        thank_name_insert = lu16.init(0x271).inner,
        setvar_shaymin = lu16.init(0x272).inner,
        setvar_accessories2 = lu16.init(0x273).inner,
        cmd_274 = lu16.init(0x274).inner,
        check_record_casino = lu16.init(0x275).inner,
        check_coins_casino = lu16.init(0x276).inner,
        srt_random_num = lu16.init(0x277).inner,
        check_poke_level2 = lu16.init(0x278).inner,
        cmd_279 = lu16.init(0x279).inner,
        league_castle_view = lu16.init(0x27a).inner,
        cmd_27b = lu16.init(0x27b).inner,
        setvar_amity_pokemon = lu16.init(0x27c).inner,
        cmd_27d = lu16.init(0x27d).inner,
        check_first_time_v_shop = lu16.init(0x27e).inner,
        cmd_27f = lu16.init(0x27f).inner,
        setvar_id_number = lu16.init(0x280).inner,
        cmd_281 = lu16.init(0x281).inner,
        setvar_unk = lu16.init(0x282).inner,
        cmd_283 = lu16.init(0x283).inner,
        check_ruin_maniac = lu16.init(0x284).inner,
        check_turn_back = lu16.init(0x285).inner,
        check_ug_people_num = lu16.init(0x286).inner,
        check_ug_fossil_num = lu16.init(0x287).inner,
        check_ug_traps_num = lu16.init(0x288).inner,
        check_poffin_item = lu16.init(0x289).inner,
        check_poffin_case_status = lu16.init(0x28a).inner,
        unk_funct2 = lu16.init(0x28b).inner,
        pokemon_party_picture = lu16.init(0x28c).inner,
        act_learning = lu16.init(0x28d).inner,
        set_sound_learning = lu16.init(0x28e).inner,
        check_first_time_champion = lu16.init(0x28f).inner,
        choose_poke_d_care = lu16.init(0x290).inner,
        store_poke_d_care = lu16.init(0x291).inner,
        cmd_292 = lu16.init(0x292).inner,
        check_master_rank = lu16.init(0x293).inner,
        show_battle_points_box = lu16.init(0x294).inner,
        hide_battle_points_box = lu16.init(0x295).inner,
        update_battle_points_box = lu16.init(0x296).inner,
        take_b_points = lu16.init(0x299).inner,
        check_b_points = lu16.init(0x29a).inner,
        cmd_29c = lu16.init(0x29c).inner,
        choice_multi = lu16.init(0x29d).inner,
        h_m_effect = lu16.init(0x29e).inner,
        camera_bump_effect = lu16.init(0x29f).inner,
        double_battle = lu16.init(0x2a0).inner,
        apply_movement2 = lu16.init(0x2a1).inner,
        cmd_2a2 = lu16.init(0x2a2).inner,
        store_act_hero_friend_code = lu16.init(0x2a3).inner,
        store_act_other_friend_code = lu16.init(0x2a4).inner,
        choose_trade_pokemon = lu16.init(0x2a5).inner,
        chs_prize_casino = lu16.init(0x2a6).inner,
        check_plate = lu16.init(0x2a7).inner,
        take_coins_casino = lu16.init(0x2a8).inner,
        check_coins_casino2 = lu16.init(0x2a9).inner,
        compare_phrase_box_input = lu16.init(0x2aa).inner,
        store_seal_num = lu16.init(0x2ab).inner,
        activate_mystery_gift = lu16.init(0x2ac).inner,
        check_follow_battle = lu16.init(0x2ad).inner,
        cmd_2af = lu16.init(0x2af).inner,
        cmd_2b0 = lu16.init(0x2b0).inner,
        cmd_2b1 = lu16.init(0x2b1).inner,
        cmd_2b2 = lu16.init(0x2b2).inner,
        setvar_seal_random = lu16.init(0x2b3).inner,
        darkrai_function = lu16.init(0x2b5).inner,
        cmd_2b6 = lu16.init(0x2b6).inner,
        store_poke_num_party = lu16.init(0x2b7).inner,
        store_poke_nickname = lu16.init(0x2b8).inner,
        close_multi_union = lu16.init(0x2b9).inner,
        check_battle_union = lu16.init(0x2ba).inner,
        cmd_2_b_b = lu16.init(0x2bb).inner,
        check_wild_battle2 = lu16.init(0x2bc).inner,
        wild_battle2 = lu16.init(0x2bd).inner,
        store_trainer_card_star = lu16.init(0x2be).inner,
        bike_ride = lu16.init(0x2bf).inner,
        cmd_2c0 = lu16.init(0x2c0).inner,
        show_save_box = lu16.init(0x2c1).inner,
        hide_save_box = lu16.init(0x2c2).inner,
        cmd_2c3 = lu16.init(0x2c3).inner,
        show_b_tower_some = lu16.init(0x2c4).inner,
        delete_saves_b_factory = lu16.init(0x2c5).inner,
        spin_trade_union = lu16.init(0x2c6).inner,
        check_version_game = lu16.init(0x2c7).inner,
        show_b_arcade_recors = lu16.init(0x2c8).inner,
        eterna_gym_anm = lu16.init(0x2c9).inner,
        floral_clock_animation = lu16.init(0x2ca).inner,
        check_poke_party2 = lu16.init(0x2cb).inner,
        check_poke_castle = lu16.init(0x2cc).inner,
        act_team_galactic_events = lu16.init(0x2cd).inner,
        choose_wire_poke_b_castle = lu16.init(0x2cf).inner,
        cmd_2d0 = lu16.init(0x2d0).inner,
        cmd_2d1 = lu16.init(0x2d1).inner,
        cmd_2d2 = lu16.init(0x2d2).inner,
        cmd_2d3 = lu16.init(0x2d3).inner,
        cmd_2d4 = lu16.init(0x2d4).inner,
        cmd_2d5 = lu16.init(0x2d5).inner,
        cmd_2d6 = lu16.init(0x2d6).inner,
        cmd_2d7 = lu16.init(0x2d7).inner,
        cmd_2d8 = lu16.init(0x2d8).inner,
        cmd_2d9 = lu16.init(0x2d9).inner,
        cmd_2da = lu16.init(0x2da).inner,
        cmd_2db = lu16.init(0x2db).inner,
        cmd_2dc = lu16.init(0x2dc).inner,
        cmd_2dd = lu16.init(0x2dd).inner,
        cmd_2de = lu16.init(0x2de).inner,
        cmd_2df = lu16.init(0x2df).inner,
        cmd_2e0 = lu16.init(0x2e0).inner,
        cmd_2e1 = lu16.init(0x2e1).inner,
        cmd_2e2 = lu16.init(0x2e2).inner,
        cmd_2e3 = lu16.init(0x2e3).inner,
        cmd_2e4 = lu16.init(0x2e4).inner,
        cmd_2e5 = lu16.init(0x2e5).inner,
        cmd_2e6 = lu16.init(0x2e6).inner,
        cmd_2e7 = lu16.init(0x2e7).inner,
        cmd_2e8 = lu16.init(0x2e8).inner,
        cmd_2e9 = lu16.init(0x2e9).inner,
        cmd_2ea = lu16.init(0x2ea).inner,
        cmd_2eb = lu16.init(0x2eb).inner,
        cmd_2ec = lu16.init(0x2ec).inner,
        cmd_2ed = lu16.init(0x2ed).inner,
        cmd_2ee = lu16.init(0x2ee).inner,
        cmd_2f0 = lu16.init(0x2f0).inner,
        cmd_2f2 = lu16.init(0x2f2).inner,
        cmd_2f3 = lu16.init(0x2f3).inner,
        cmd_2f4 = lu16.init(0x2f4).inner,
        cmd_2f5 = lu16.init(0x2f5).inner,
        cmd_2f6 = lu16.init(0x2f6).inner,
        cmd_2f7 = lu16.init(0x2f7).inner,
        cmd_2f8 = lu16.init(0x2f8).inner,
        cmd_2f9 = lu16.init(0x2f9).inner,
        cmd_2fa = lu16.init(0x2fa).inner,
        cmd_2fb = lu16.init(0x2fb).inner,
        cmd_2fc = lu16.init(0x2fc).inner,
        cmd_2fd = lu16.init(0x2fd).inner,
        cmd_2fe = lu16.init(0x2fe).inner,
        cmd_2ff = lu16.init(0x2ff).inner,
        cmd_300 = lu16.init(0x300).inner,
        cmd_302 = lu16.init(0x302).inner,
        cmd_303 = lu16.init(0x303).inner,
        cmd_304 = lu16.init(0x304).inner,
        cmd_305 = lu16.init(0x305).inner,
        cmd_306 = lu16.init(0x306).inner,
        cmd_307 = lu16.init(0x307).inner,
        cmd_308 = lu16.init(0x308).inner,
        cmd_309 = lu16.init(0x309).inner,
        cmd_30a = lu16.init(0x30a).inner,
        cmd_30b = lu16.init(0x30b).inner,
        cmd_30c = lu16.init(0x30c).inner,
        cmd_30d = lu16.init(0x30d).inner,
        cmd_30e = lu16.init(0x30e).inner,
        cmd_30f = lu16.init(0x30f).inner,
        cmd_310 = lu16.init(0x310).inner,
        cmd_311 = lu16.init(0x311).inner,
        cmd_312 = lu16.init(0x312).inner,
        cmd_313 = lu16.init(0x313).inner,
        cmd_314 = lu16.init(0x314).inner,
        cmd_315 = lu16.init(0x315).inner,
        cmd_316 = lu16.init(0x316).inner,
        cmd_317 = lu16.init(0x317).inner,
        wild_battle3 = lu16.init(0x318).inner,
        cmd_319 = lu16.init(0x319).inner,
        cmd_31a = lu16.init(0x31a).inner,
        cmd_31b = lu16.init(0x31b).inner,
        cmd_31c = lu16.init(0x31c).inner,
        cmd_31d = lu16.init(0x31d).inner,
        cmd_31e = lu16.init(0x31e).inner,
        cmd_31f = lu16.init(0x31f).inner,
        cmd_320 = lu16.init(0x320).inner,
        cmd_321 = lu16.init(0x321).inner,
        cmd_322 = lu16.init(0x322).inner,
        cmd_323 = lu16.init(0x323).inner,
        cmd_324 = lu16.init(0x324).inner,
        cmd_325 = lu16.init(0x325).inner,
        cmd_326 = lu16.init(0x326).inner,
        cmd_327 = lu16.init(0x327).inner,
        portal_effect = lu16.init(0x328).inner,
        cmd_329 = lu16.init(0x329).inner,
        cmd_32a = lu16.init(0x32a).inner,
        cmd_32b = lu16.init(0x32b).inner,
        cmd_32c = lu16.init(0x32c).inner,
        cmd_32d = lu16.init(0x32d).inner,
        cmd_32e = lu16.init(0x32e).inner,
        cmd_32f = lu16.init(0x32f).inner,
        cmd_330 = lu16.init(0x330).inner,
        cmd_331 = lu16.init(0x331).inner,
        cmd_332 = lu16.init(0x332).inner,
        cmd_333 = lu16.init(0x333).inner,
        cmd_334 = lu16.init(0x334).inner,
        cmd_335 = lu16.init(0x335).inner,
        cmd_336 = lu16.init(0x336).inner,
        cmd_337 = lu16.init(0x337).inner,
        cmd_338 = lu16.init(0x338).inner,
        cmd_339 = lu16.init(0x339).inner,
        cmd_33a = lu16.init(0x33a).inner,
        cmd_33c = lu16.init(0x33c).inner,
        cmd_33d = lu16.init(0x33d).inner,
        cmd_33e = lu16.init(0x33e).inner,
        cmd_33f = lu16.init(0x33f).inner,
        cmd_340 = lu16.init(0x340).inner,
        cmd_341 = lu16.init(0x341).inner,
        cmd_342 = lu16.init(0x342).inner,
        cmd_343 = lu16.init(0x343).inner,
        cmd_344 = lu16.init(0x344).inner,
        cmd_345 = lu16.init(0x345).inner,
        cmd_346 = lu16.init(0x346).inner,
        display_floor = lu16.init(0x347).inner,
    };
    pub const Return2 = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_a = packed struct {
        a: u8,
        b: u8,
    };
    pub const If = packed struct {
        @"var": lu16,
        nr: lu16,
    };
    pub const If2 = packed struct {
        @"var": lu16,
        nr: lu16,
    };
    pub const CallStandard = packed struct {
        a: lu16,
    };
    pub const Jump = packed struct {
        adr: li32,
    };
    pub const Call = packed struct {
        adr: li32,
    };
    pub const CompareLastResultJump = packed struct {
        cond: u8,
        adr: li32,
    };
    pub const CompareLastResultCall = packed struct {
        cond: u8,
        adr: li32,
    };
    pub const SetFlag = packed struct {
        a: lu16,
    };
    pub const ClearFlag = packed struct {
        a: lu16,
    };
    pub const CheckFlag = packed struct {
        a: lu16,
    };
    pub const Cmd_21 = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_22 = packed struct {
        a: lu16,
    };
    pub const SetTrainerId = packed struct {
        a: lu16,
    };
    pub const Cmd_24 = packed struct {
        a: lu16,
    };
    pub const ClearTrainerId = packed struct {
        a: lu16,
    };
    pub const ScriptCmd_AddValue = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const ScriptCmd_SubValue = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const SetVar = packed struct {
        destination: lu16,
        value: lu16,
    };
    pub const CopyVar = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Message2 = packed struct {
        nr: u8,
    };
    pub const Message = packed struct {
        nr: u8,
    };
    pub const Message3 = packed struct {
        nr: lu16,
    };
    pub const Message4 = packed struct {
        nr: lu16,
    };
    pub const Message5 = packed struct {
        nr: u8,
    };
    pub const CallMessageBox = packed struct {
        a: u8,
        b: u8,
        c: lu16,
        d: lu16,
    };
    pub const ColorMsgBox = packed struct {
        a: u8,
        b: lu16,
    };
    pub const TypeMessageBox = packed struct {
        a: u8,
    };
    pub const CallTextMsgBox = packed struct {
        a: u8,
        b: lu16,
    };
    pub const StoreMenuStatus = packed struct {
        a: lu16,
    };
    pub const YesNoBox = packed struct {
        nr: lu16,
    };
    pub const Multi = packed struct {
        a: u8,
        b: u8,
        c: u8,
        d: u8,
        e: lu16,
    };
    pub const Multi2 = packed struct {
        a: u8,
        b: u8,
        c: u8,
        d: u8,
        e: lu16,
    };
    pub const Cmd_42 = packed struct {
        a: u8,
        b: u8,
    };
    pub const Multi3 = packed struct {
        a: u8,
        b: u8,
        c: u8,
        d: u8,
        e: lu16,
    };
    pub const Multi4 = packed struct {
        a: u8,
        b: u8,
        c: u8,
        d: u8,
        e: lu16,
    };
    pub const TxtMsgScrpMulti = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const PlayFanfare = packed struct {
        nr: lu16,
    };
    pub const MultiRow = packed struct {
        a: u8,
    };
    pub const PlayFanfare2 = packed struct {
        nr: lu16,
    };
    pub const WaitFanfare = packed struct {
        a: lu16,
    };
    pub const PlayCry = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Soundfr = packed struct {
        a: lu16,
    };
    pub const PlaySound = packed struct {
        a: lu16,
    };
    pub const Stop = packed struct {
        a: lu16,
    };
    pub const Cmd_53 = packed struct {
        a: lu16,
    };
    pub const SwitchMusic = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const StoreSayingLearned = packed struct {
        a: lu16,
    };
    pub const PlaySound2 = packed struct {
        a: lu16,
    };
    pub const Cmd_58 = packed struct {
        a: u8,
    };
    pub const CheckSayingLearned = packed struct {
        a: lu16,
    };
    pub const SwithMusic2 = packed struct {
        a: lu16,
    };
    pub const ApplyMovement = packed struct {
        a: lu16,
        adr: lu32,
    };
    pub const Lock = packed struct {
        a: lu16,
    };
    pub const Release = packed struct {
        a: lu16,
    };
    pub const AddPeople = packed struct {
        a: lu16,
    };
    pub const RemovePeople = packed struct {
        a: lu16,
    };
    pub const LockCam = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const CheckSpritePosition = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const CheckPersonPosition = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const ContinueFollow = packed struct {
        a: lu16,
        b: u8,
    };
    pub const FollowHero = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const TakeMoney = packed struct {
        a: lu32,
    };
    pub const CheckMoney = packed struct {
        a: lu16,
        b: lu32,
    };
    pub const ShowMoney = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const ShowCoins = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const CheckCoins = packed struct {
        a: lu16,
    };
    pub const GiveCoins = packed struct {
        a: lu16,
    };
    pub const TakeCoins = packed struct {
        a: lu16,
    };
    pub const TakeItem = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const GiveItem = packed struct {
        itemid: lu16,
        quantity: lu16,
        @"return": lu16,
    };
    pub const CheckStoreItem = packed struct {
        itemid: lu16,
        b: lu16,
        c: lu16,
    };
    pub const CheckItem = packed struct {
        itemid: lu16,
        quantity: lu16,
        @"return": lu16,
    };
    pub const StoreItemTaken = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const StoreItemType = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const SendItemType1 = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const Cmd_84 = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const CheckUndergroundPcStatus = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const Cmd_86 = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const SendItemType2 = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const Cmd_88 = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const Cmd_89 = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const Cmd_8a = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const Cmd_8b = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const Cmd_8c = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const Cmd_8d = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const Cmd_8e = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const SendItemType3 = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const CheckPokemonParty = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const StorePokemonParty = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const SetPokemonPartyStored = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const GivePokemon = packed struct {
        species: lu16,
        level: lu16,
        item: lu16,
        res: lu16,
    };
    pub const GiveEgg = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const CheckMove = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const CheckPlaceStored = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_9b = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_a4 = packed struct {
        a: lu16,
    };
    pub const DressPokemon = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const DisplayDressedPokemon = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const DisplayContestPokemon = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const OpenPcFunction = packed struct {
        a: u8,
    };
    pub const StoreWfcStatus = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const StartWfc = packed struct {
        a: lu16,
    };
    pub const BattleId = packed struct {
        a: lu16,
    };
    pub const SetVarBattle = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const CheckBattleType = packed struct {
        a: lu16,
    };
    pub const SetVarBattle2 = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const ChoosePokeNick = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const FadeScreen = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
        d: lu16,
    };
    pub const Warp = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
        d: lu16,
        e: lu16,
    };
    pub const RockClimbAnimation = packed struct {
        a: lu16,
    };
    pub const SurfAnimation = packed struct {
        a: lu16,
    };
    pub const WaterfallAnimation = packed struct {
        a: lu16,
    };
    pub const PrepHmEffect = packed struct {
        a: lu16,
    };
    pub const CheckBike = packed struct {
        a: lu16,
    };
    pub const RideBike = packed struct {
        a: u8,
    };
    pub const RideBike2 = packed struct {
        a: u8,
    };
    pub const GivePokeHiroAnm = packed struct {
        a: lu16,
    };
    pub const SetVarHero = packed struct {
        a: u8,
    };
    pub const SetVariableRival = packed struct {
        a: u8,
    };
    pub const SetVarAlter = packed struct {
        a: u8,
    };
    pub const SetVarPoke = packed struct {
        a: u8,
        b: lu16,
    };
    pub const SetVarItem = packed struct {
        a: u8,
        b: lu16,
    };
    pub const SetVarItemNum = packed struct {
        a: u8,
        b: lu16,
    };
    pub const SetVarAtkItem = packed struct {
        a: u8,
        b: lu16,
    };
    pub const SetVarAtk = packed struct {
        a: u8,
        b: lu16,
    };
    pub const SetVariableNumber = packed struct {
        a: u8,
        b: lu16,
    };
    pub const SetVarPokeNick = packed struct {
        a: u8,
        b: lu16,
    };
    pub const SetVarObj = packed struct {
        a: u8,
        b: lu16,
    };
    pub const SetVarTrainer = packed struct {
        a: u8,
        b: lu16,
    };
    pub const SetVarWiFiSprite = packed struct {
        a: u8,
    };
    pub const SetVarPokeStored = packed struct {
        a: u8,
        b: lu16,
        c: lu16,
        d: u8,
    };
    pub const SetVarStrHero = packed struct {
        a: u8,
    };
    pub const SetVarStrRival = packed struct {
        a: u8,
    };
    pub const StoreStarter = packed struct {
        a: lu16,
    };
    pub const Cmd_df = packed struct {
        a: u8,
        b: lu16,
    };
    pub const SetVarItemStored = packed struct {
        a: u8,
        b: lu16,
    };
    pub const SetVarItemStored2 = packed struct {
        a: u8,
        b: lu16,
    };
    pub const SetVarSwarmPoke = packed struct {
        a: u8,
        b: lu16,
    };
    pub const CheckSwarmPoke = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const StartBattleAnalysis = packed struct {
        a: lu16,
    };
    pub const TrainerBattle = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const EndtrainerBattle = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const TrainerBattleStored = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const TrainerBattleStored2 = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const CheckTrainerStatus = packed struct {
        a: lu16,
    };
    pub const StoreLeagueTrainer = packed struct {
        a: lu16,
    };
    pub const CheckTrainerLost = packed struct {
        a: lu16,
    };
    pub const CheckTrainerStatus2 = packed struct {
        a: lu16,
    };
    pub const StorePokePartyDefeated = packed struct {
        a: lu16,
    };
    pub const ChsFriend = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
        d: lu16,
    };
    pub const WireBattleWait = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
        d: lu16,
    };
    pub const StartOvation = packed struct {
        a: lu16,
    };
    pub const StopOvation = packed struct {
        a: lu16,
    };
    pub const Cmd_fa = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
        d: lu16,
    };
    pub const Cmd_fb = packed struct {
        a: lu16,
    };
    pub const Cmd_fc = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const SetvarOtherEntry = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_fe = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const SetvatHiroEntry = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const SetvarTypeContest = packed struct {
        a: lu16,
    };
    pub const SetvarRankContest = packed struct {
        a: lu16,
    };
    pub const Cmd_104 = packed struct {
        a: lu16,
    };
    pub const Cmd_105 = packed struct {
        a: lu16,
    };
    pub const Cmd_106 = packed struct {
        a: lu16,
    };
    pub const Cmd_107 = packed struct {
        a: lu16,
    };
    pub const StorePeopleIdContest = packed struct {
        a: lu16,
    };
    pub const Cmd_109 = packed struct {
        a: lu16,
    };
    pub const SetvatHiroEntry2 = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const ActPeopleContest = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_10c = packed struct {
        a: lu16,
    };
    pub const Cmd_10d = packed struct {
        a: lu16,
    };
    pub const Cmd_10e = packed struct {
        a: lu16,
    };
    pub const Cmd_10f = packed struct {
        a: lu16,
    };
    pub const Cmd_110 = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
        d: lu16,
    };
    pub const FlashContest = packed struct {
        a: lu16,
    };
    pub const Cmd_115 = packed struct {
        a: lu16,
    };
    pub const StorePokerus = packed struct {
        a: lu16,
    };
    pub const WarpMapElevator = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
        d: lu16,
        e: lu16,
    };
    pub const CheckFloor = packed struct {
        a: lu16,
    };
    pub const StartLift = packed struct {
        a: u8,
        b: u8,
        c: lu16,
        d: lu16,
    };
    pub const StoreSinPokemonSeen = packed struct {
        a: lu16,
    };
    pub const Cmd_11f = packed struct {
        a: lu16,
    };
    pub const StoreTotPokemonSeen = packed struct {
        a: lu16,
    };
    pub const StoreNatPokemonSeen = packed struct {
        a: lu16,
    };
    pub const SetVarTextPokedex = packed struct {
        a: u8,
        b: lu16,
    };
    pub const WildBattle = packed struct {
        species: lu16,
        level: lu16,
    };
    pub const StarterBattle = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const CheckIfHoneySlathered = packed struct {
        a: lu16,
    };
    pub const StoreSaveData = packed struct {
        a: lu16,
    };
    pub const CheckSaveData = packed struct {
        a: lu16,
    };
    pub const CheckDress = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const CheckContestWin = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const StorePhotoName = packed struct {
        a: lu16,
    };
    pub const CheckPtchAppl = packed struct {
        a: lu16,
    };
    pub const ActPktchAppl = packed struct {
        a: lu16,
    };
    pub const StorePoketchApp = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const FriendBT = packed struct {
        nr: lu16,
    };
    pub const Cmd_138 = packed struct {
        a: lu16,
    };
    pub const OpenUnionFunction2 = packed struct {
        a: lu16,
    };
    pub const SetUnionFunctionId = packed struct {
        a: lu16,
    };
    pub const SetVarUnionMessage = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const StoreYourDecisionUnion = packed struct {
        a: lu16,
    };
    pub const StoreOtherDecisionUnion = packed struct {
        a: lu16,
    };
    pub const CheckOtherDecisionUnion = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const StoreYourDecisionUnion2 = packed struct {
        a: lu16,
    };
    pub const StoreOtherDecisionUnion2 = packed struct {
        a: lu16,
    };
    pub const CheckOtherDecisionUnion2 = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Pokemart = packed struct {
        a: lu16,
    };
    pub const Pokemart1 = packed struct {
        a: lu16,
    };
    pub const Pokemart2 = packed struct {
        a: lu16,
    };
    pub const Pokemart3 = packed struct {
        a: lu16,
    };
    pub const ActBike = packed struct {
        a: lu16,
    };
    pub const CheckGender = packed struct {
        a: lu16,
    };
    pub const UndergroundId = packed struct {
        a: lu16,
    };
    pub const StoreWiFiSprite = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const ActWiFiSprite = packed struct {
        a: lu16,
    };
    pub const Cmd_157 = packed struct {
        a: lu16,
    };
    pub const CheckBadge = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const EnableBadge = packed struct {
        a: lu16,
    };
    pub const DisableBadge = packed struct {
        a: lu16,
    };
    pub const CheckFollow = packed struct {
        a: lu16,
    };
    pub const Cmd_166 = packed struct {
        a: lu16,
    };
    pub const PrepareDoorAnimation = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
        d: lu16,
        e: u8,
    };
    pub const WaitAction = packed struct {
        a: u8,
    };
    pub const WaitClose = packed struct {
        a: u8,
    };
    pub const OpenDoor = packed struct {
        a: u8,
    };
    pub const CloseDoor = packed struct {
        a: u8,
    };
    pub const StorePDCareNum = packed struct {
        a: lu16,
    };
    pub const SunishoreGymFunction = packed struct {
        a: u8,
    };
    pub const SunishoreGymFunction2 = packed struct {
        a: u8,
    };
    pub const CheckPartyNumber = packed struct {
        a: lu16,
    };
    pub const OpenBerryPouch = packed struct {
        a: u8,
    };
    pub const Cmd_179 = packed struct {
        a: lu16,
    };
    pub const Cmd_17a = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_17b = packed struct {
        a: u8,
        b: lu16,
        c: lu16,
    };
    pub const SetNaturePokemon = packed struct {
        a: u8,
        b: lu16,
    };
    pub const Cmd_17d = packed struct {
        a: lu16,
    };
    pub const Cmd_17e = packed struct {
        a: lu16,
    };
    pub const Cmd_17f = packed struct {
        a: lu16,
    };
    pub const Cmd_180 = packed struct {
        a: lu16,
    };
    pub const Cmd_181 = packed struct {
        a: lu16,
    };
    pub const CheckDeoxis = packed struct {
        a: lu16,
    };
    pub const Cmd_183 = packed struct {
        a: lu16,
    };
    pub const Cmd_184 = packed struct {
        a: lu16,
    };
    pub const ChangeOwPosition = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const SetOwPosition = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
        d: lu16,
        e: lu16,
    };
    pub const ChangeOwMovement = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const ReleaseOw = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const SetTilePassable = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const SetTileLocked = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const SetOwsFollow = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_18f = packed struct {
        a: lu16,
    };
    pub const SetSaveData = packed struct {
        a: lu16,
    };
    pub const StorePokeMenu2 = packed struct {
        a: lu16,
    };
    pub const ChsPokeContest = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
        d: lu16,
    };
    pub const StorePokeContest = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const ShowPokeInfo = packed struct {
        a: lu16,
    };
    pub const StorePokeMove = packed struct {
        a: lu16,
    };
    pub const CheckPokeEgg = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const ComparePokeNick = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const CheckPartyNumberUnion = packed struct {
        a: lu16,
    };
    pub const CheckPokePartyHealth = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const CheckPokePartyNumDCare = packed struct {
        a: lu16,
    };
    pub const CheckEggUnion = packed struct {
        a: lu16,
    };
    pub const UndergroundFunction = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const UndergroundFunction2 = packed struct {
        a: lu16,
    };
    pub const TakeMoneyDCare = packed struct {
        a: lu16,
    };
    pub const TakePokemonDCare = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const SetVarPokeAndMoneyDCare = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const CheckMoneyDCare = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const SetVarPokeAndLevelDCare = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const SetVarPokeChosenDCare = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const GivePokeDCare = packed struct {
        a: lu16,
    };
    pub const AddPeople2 = packed struct {
        a: lu16,
    };
    pub const RemovePeople2 = packed struct {
        a: lu16,
    };
    pub const CheckMail = packed struct {
        a: lu16,
    };
    pub const ShowRecordList = packed struct {
        a: lu16,
    };
    pub const CheckTime = packed struct {
        a: lu16,
    };
    pub const CheckIdPlayer = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const RandomTextStored = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const StoreHappyPoke = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const StoreHappyStatus = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const SetVarDataDayCare = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
        d: lu16,
    };
    pub const CheckFacePosition = packed struct {
        a: lu16,
    };
    pub const StorePokeDCareLove = packed struct {
        a: lu16,
    };
    pub const CheckStatusSolaceonEvent = packed struct {
        a: lu16,
    };
    pub const CheckPokeParty = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const CopyPokemonHeight = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const SetVariablePokemonHeight = packed struct {
        a: lu16,
    };
    pub const ComparePokemonHeight = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const CheckPokemonHeight = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const StorePokeDelete = packed struct {
        a: lu16,
    };
    pub const StoreMoveDelete = packed struct {
        a: lu16,
    };
    pub const CheckMoveNumDelete = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const StoreDeleteMove = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const CheckDeleteMove = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const SetvarMoveDelete = packed struct {
        a: u8,
        b: lu16,
        c: lu16,
    };
    pub const DeActivateLeader = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
        d: lu16,
        e: lu16,
    };
    pub const HmFunctions = packed struct {
        a: enum(u8) {
            @"1" = 1,
            @"2" = 2,
        },
        b: packed union {
            @"1": void,
            @"2": packed struct {
                b: lu16,
            },
        },
    };
    pub const FlashDuration = packed struct {
        a: u8,
    };
    pub const DefogDuration = packed struct {
        a: u8,
    };
    pub const GiveAccessories = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const CheckAccessories = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const Cmd_1d4 = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const GiveAccessories2 = packed struct {
        a: lu16,
    };
    pub const CheckAccessories2 = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const BerryPoffin = packed struct {
        a: lu16,
    };
    pub const SetVarBTowerChs = packed struct {
        a: lu16,
    };
    pub const BattleRoomResult = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const StoreBTowerData = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const CallBTowerFunctions = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const RandomTeamBTower = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
        d: lu16,
    };
    pub const StorePrizeNumBTower = packed struct {
        a: lu16,
    };
    pub const StorePeopleIdBTower = packed struct {
        a: lu16,
    };
    pub const CallBTowerWireFunction = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const StorePChosenWireBTower = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const StoreRankDataWireBTower = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_1e4 = packed struct {
        a: lu16,
    };
    pub const RandomEvent = packed struct {
        a: lu16,
    };
    pub const CheckSinnohPokedex = packed struct {
        a: lu16,
    };
    pub const CheckNationalPokedex = packed struct {
        a: lu16,
    };
    pub const StoreTrophyPokemon = packed struct {
        a: lu16,
    };
    pub const Cmd_1ef = packed struct {
        a: lu16,
    };
    pub const Cmd_1f0 = packed struct {
        a: lu16,
    };
    pub const CheckActFossil = packed struct {
        a: lu16,
    };
    pub const CheckItemChosen = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const CompareItemPokeFossil = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const CheckPokemonLevel = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const CheckIsPokemonPoisoned = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const StoreFurniture = packed struct {
        a: lu16,
    };
    pub const CopyFurniture = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const SetBCastleFunctionId = packed struct {
        a: u8,
    };
    pub const BCastleFunctReturn = packed struct {
        a: u8,
        b: lu16,
        c: lu16,
        d: u8,
    };
    pub const Cmd_200 = packed struct {
        a: lu16,
    };
    pub const CheckEffectHm = packed struct {
        a: lu16,
    };
    pub const GreatMarshFunction = packed struct {
        a: u8,
    };
    pub const BattlePokeColosseum = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
        d: lu16,
        e: lu16,
    };
    pub const StorePokeColosseumLost = packed struct {
        a: lu16,
    };
    pub const PokemonPicture = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_20a = packed struct {
        a: lu16,
    };
    pub const SetvarMtCoronet = packed struct {
        a: u8,
        b: lu16,
    };
    pub const CheckQuicTrineCoordinates = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const SetvarQuickTrainCoordinates = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const MoveTrainAnm = packed struct {
        a: u8,
    };
    pub const StorePokeNature = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const CheckPokeNature = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const RandomHallowes = packed struct {
        a: lu16,
    };
    pub const Cmd_216 = packed struct {
        a: lu16,
    };
    pub const Cmd_217 = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const ChsRSPoke = packed struct {
        a: lu16,
    };
    pub const SetSPoke = packed struct {
        a: lu16,
    };
    pub const CheckSPoke = packed struct {
        a: lu16,
    };
    pub const ActSwarmPoke = packed struct {
        a: u8,
    };
    pub const Cmd_21d = packed struct {
        a: enum(u16) {
            @"0" = lu16.init(0).inner,
            @"1" = lu16.init(1).inner,
            @"2" = lu16.init(2).inner,
            @"3" = lu16.init(3).inner,
            @"4" = lu16.init(4).inner,
            @"5" = lu16.init(5).inner,
        },
        b: packed union {
            @"0": packed struct {
                b: lu16,
                c: lu16,
            },
            @"1": packed struct {
                b: lu16,
                c: lu16,
            },
            @"2": packed struct {
                b: lu16,
                c: lu16,
            },
            @"3": packed struct {
                b: lu16,
                c: lu16,
            },
            @"4": packed struct {
                b: lu16,
            },
            @"5": packed struct {
                b: lu16,
            },
        },
    };
    pub const CheckMoveRemember = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const StorePokeRemember = packed struct {
        a: lu16,
    };
    pub const StoreRememberMove = packed struct {
        a: lu16,
    };
    pub const TeachMove = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const CheckTeachMove = packed struct {
        a: lu16,
    };
    pub const SetTradeId = packed struct {
        a: u8,
    };
    pub const CheckPokemonTrade = packed struct {
        a: lu16,
    };
    pub const TradeChosenPokemon = packed struct {
        a: lu16,
    };
    pub const CheckNatPokedexStatus = packed struct {
        a: u8,
        b: lu16,
    };
    pub const CheckRibbonNumber = packed struct {
        a: lu16,
    };
    pub const CheckRibbon = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const GiveRibbon = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const SetvarRibbon = packed struct {
        a: u8,
        b: lu16,
    };
    pub const CheckHappyRibbon = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const CheckPokemart = packed struct {
        a: lu16,
    };
    pub const CheckFurniture = packed struct {
        a: enum(u16) {
            @"0" = lu16.init(0).inner,
            @"1" = lu16.init(1).inner,
            @"2" = lu16.init(2).inner,
            @"3" = lu16.init(3).inner,
            @"4" = lu16.init(4).inner,
            @"5" = lu16.init(5).inner,
            @"6" = lu16.init(6).inner,
        },
        b: packed union {
            @"0": packed struct {
                b: lu16,
            },
            @"1": packed struct {
                b: lu16,
                c: lu16,
                d: lu16,
            },
            @"2": void,
            @"3": packed struct {
                b: lu16,
                c: lu16,
                d: lu16,
            },
            @"4": packed struct {
                b: lu16,
                c: lu16,
            },
            @"5": packed struct {
                b: lu16,
                c: lu16,
                d: lu16,
            },
            @"6": packed struct {
                b: lu16,
            },
        },
    };
    pub const Cmd_236 = packed struct {
        a: lu16,
    };
    pub const CheckPhraseBoxInput = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
        d: lu16,
    };
    pub const CheckStatusPhraseBox = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const DecideRules = packed struct {
        a: lu16,
    };
    pub const CheckFootStep = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const HealPokemonAnimation = packed struct {
        a: lu16,
    };
    pub const StoreElevatorDirection = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const ShipAnimation = packed struct {
        a: u8,
        b: u8,
        c: lu16,
        d: lu16,
        e: lu16,
    };
    pub const Cmd_23e = packed struct {
        a: enum(u16) {
            @"1" = lu16.init(1).inner,
            @"2" = lu16.init(2).inner,
            @"3" = lu16.init(3).inner,
            @"5" = lu16.init(5).inner,
            @"6" = lu16.init(6).inner,
        },
        b: packed union {
            @"1": packed struct {
                b: lu16,
            },
            @"2": packed struct {
                b: lu16,
            },
            @"3": packed struct {
                b: lu16,
            },
            @"5": packed struct {
                b: lu16,
                c: lu16,
            },
            @"6": packed struct {
                b: lu16,
                c: lu16,
            },
        },
    };
    pub const StorePhraseBox1W = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const StorePhraseBox2W = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
        d: lu16,
    };
    pub const SetvarPhraseBox1W = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const StoreMtCoronet = packed struct {
        a: lu16,
    };
    pub const CheckFirstPokeParty = packed struct {
        a: lu16,
    };
    pub const CheckPokeType = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const CheckPhraseBoxInput2 = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
        d: lu16,
        e: lu16,
    };
    pub const StoreUndTime = packed struct {
        a: lu16,
    };
    pub const PreparePcAnimation = packed struct {
        a: u8,
    };
    pub const OpenPcAnimation = packed struct {
        a: u8,
    };
    pub const ClosePcAnimation = packed struct {
        a: u8,
    };
    pub const CheckLottoNumber = packed struct {
        a: lu16,
    };
    pub const CompareLottoNumber = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
        d: lu16,
    };
    pub const SetvarIdPokeBoxes = packed struct {
        a: u8,
        b: lu16,
    };
    pub const CheckBoxesNumber = packed struct {
        a: lu16,
    };
    pub const StopGreatMarsh = packed struct {
        a: lu16,
    };
    pub const CheckPokeCatchingShow = packed struct {
        a: lu16,
    };
    pub const CheckCatchingShowRecords = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const CheckElevLgAnm = packed struct {
        a: lu16,
    };
    pub const CheckElevPosition = packed struct {
        a: lu16,
    };
    pub const MainEvent = packed struct {
        a: lu16,
    };
    pub const CheckAccessories3 = packed struct {
        a: u8,
        b: lu16,
    };
    pub const ActDeoxisFormChange = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const ChangeFormDeoxis = packed struct {
        a: lu16,
    };
    pub const CheckCoombeEvent = packed struct {
        a: lu16,
    };
    pub const Pokecasino = packed struct {
        a: lu16,
    };
    pub const CheckTime2 = packed struct {
        a: lu16,
    };
    pub const RegigigasAnm = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
        d: lu16,
        e: lu16,
    };
    pub const CresseliaAnm = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const CheckRegi = packed struct {
        a: lu16,
    };
    pub const CheckMassage = packed struct {
        a: lu16,
    };
    pub const UnownMessageBox = packed struct {
        a: lu16,
    };
    pub const CheckPCatchingShow = packed struct {
        a: lu16,
    };
    pub const ShayminAnm = packed struct {
        a: lu16,
        b: u8,
    };
    pub const ThankNameInsert = packed struct {
        a: lu16,
    };
    pub const SetvarShaymin = packed struct {
        a: u8,
    };
    pub const SetvarAccessories2 = packed struct {
        a: u8,
        b: lu16,
    };
    pub const Cmd_274 = packed struct {
        a: lu16,
        b: lu32,
    };
    pub const CheckRecordCasino = packed struct {
        a: lu16,
    };
    pub const CheckCoinsCasino = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const SrtRandomNum = packed struct {
        a: lu16,
    };
    pub const CheckPokeLevel2 = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_279 = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const SetvarAmityPokemon = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_27d = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const CheckFirstTimeVShop = packed struct {
        a: lu16,
    };
    pub const Cmd_27f = packed struct {
        a: lu16,
    };
    pub const SetvarIdNumber = packed struct {
        a: u8,
        b: lu16,
        c: u8,
        d: u8,
    };
    pub const Cmd_281 = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const SetvarUnk = packed struct {
        a: lu16,
    };
    pub const Cmd_283 = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const CheckRuinManiac = packed struct {
        a: lu16,
    };
    pub const CheckTurnBack = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const CheckUgPeopleNum = packed struct {
        a: lu16,
    };
    pub const CheckUgFossilNum = packed struct {
        a: lu16,
    };
    pub const CheckUgTrapsNum = packed struct {
        a: lu16,
    };
    pub const CheckPoffinItem = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
        d: lu16,
        e: lu16,
        f: lu16,
        g: lu16,
    };
    pub const CheckPoffinCaseStatus = packed struct {
        a: lu16,
    };
    pub const UnkFunct2 = packed struct {
        a: u8,
        b: lu16,
    };
    pub const PokemonPartyPicture = packed struct {
        a: lu16,
    };
    pub const SetSoundLearning = packed struct {
        a: lu16,
    };
    pub const CheckFirstTimeChampion = packed struct {
        a: lu16,
    };
    pub const ChoosePokeDCare = packed struct {
        a: lu16,
    };
    pub const StorePokeDCare = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_292 = packed struct {
        a: u8,
        b: lu16,
    };
    pub const CheckMasterRank = packed struct {
        a: lu16,
    };
    pub const ShowBattlePointsBox = packed struct {
        a: u8,
        b: u8,
    };
    pub const TakeBPoints = packed struct {
        a: lu16,
    };
    pub const CheckBPoints = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_29c = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const ChoiceMulti = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const HMEffect = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const CameraBumpEffect = packed struct {
        a: lu16,
    };
    pub const DoubleBattle = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const ApplyMovement2 = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const Cmd_2a2 = packed struct {
        a: lu16,
    };
    pub const StoreActHeroFriendCode = packed struct {
        a: lu16,
    };
    pub const StoreActOtherFriendCode = packed struct {
        a: lu16,
    };
    pub const ChsPrizeCasino = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const CheckPlate = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const TakeCoinsCasino = packed struct {
        a: lu16,
    };
    pub const CheckCoinsCasino2 = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const ComparePhraseBoxInput = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
        d: lu16,
        e: lu16,
    };
    pub const StoreSealNum = packed struct {
        a: lu16,
    };
    pub const CheckFollowBattle = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_2af = packed struct {
        a: lu16,
    };
    pub const SetvarSealRandom = packed struct {
        a: u8,
        b: lu16,
    };
    pub const DarkraiFunction = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const Cmd_2b6 = packed struct {
        a: lu16,
        b: u8,
    };
    pub const StorePokeNumParty = packed struct {
        a: lu16,
    };
    pub const StorePokeNickname = packed struct {
        a: lu16,
    };
    pub const CheckBattleUnion = packed struct {
        a: lu16,
    };
    pub const CheckWildBattle2 = packed struct {
        a: lu16,
    };
    pub const StoreTrainerCardStar = packed struct {
        a: lu16,
    };
    pub const Cmd_2c0 = packed struct {
        a: lu16,
    };
    pub const Cmd_2c3 = packed struct {
        a: u8,
    };
    pub const ShowBTowerSome = packed struct {
        a: u8,
    };
    pub const DeleteSavesBFactory = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const CheckVersionGame = packed struct {
        a: lu16,
    };
    pub const ShowBArcadeRecors = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const CheckPokeParty2 = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const CheckPokeCastle = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const ActTeamGalacticEvents = packed struct {
        a: u8,
        b: lu16,
    };
    pub const ChooseWirePokeBCastle = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_2d0 = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_2d1 = packed struct {
        a: lu16,
    };
    pub const Cmd_2d2 = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const Cmd_2d3 = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const Cmd_2d4 = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const Cmd_2d5 = packed struct {
        a: lu16,
    };
    pub const Cmd_2d7 = packed struct {
        a: lu16,
    };
    pub const Cmd_2d8 = packed struct {
        a: u8,
    };
    pub const Cmd_2d9 = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const Cmd_2da = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const Cmd_2db = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const Cmd_2dc = packed struct {
        a: lu16,
    };
    pub const Cmd_2dd = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_2de = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
        d: lu16,
        e: lu16,
    };
    pub const Cmd_2df = packed struct {
        a: lu16,
    };
    pub const Cmd_2e0 = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_2e1 = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_2e4 = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const Cmd_2e5 = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const Cmd_2e6 = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const Cmd_2e7 = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_2e8 = packed struct {
        a: lu16,
    };
    pub const Cmd_2e9 = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const Cmd_2ea = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_2eb = packed struct {
        a: lu16,
    };
    pub const Cmd_2ec = packed struct {
        a: u8,
        b: u8,
        c: lu16,
        d: lu16,
    };
    pub const Cmd_2ee = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
        d: lu16,
    };
    pub const Cmd_2f3 = packed struct {
        a: u8,
        b: lu16,
    };
    pub const Cmd_2f4 = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
        d: lu16,
    };
    pub const Cmd_2f5 = packed struct {
        a: u8,
        b: lu32,
        c: u8,
        d: u8,
    };
    pub const Cmd_2f6 = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const Cmd_2f7 = packed struct {
        a: lu16,
    };
    pub const Cmd_2f9 = packed struct {
        a: lu16,
    };
    pub const Cmd_2fa = packed struct {
        a: lu16,
    };
    pub const Cmd_2fc = packed struct {
        a: lu16,
    };
    pub const Cmd_2fd = packed struct {
        a: u8,
        b: lu16,
    };
    pub const Cmd_2fe = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_2ff = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_302 = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
        d: lu16,
        e: lu16,
    };
    pub const Cmd_303 = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_304 = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
        d: lu16,
    };
    pub const Cmd_305 = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_306 = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_307 = packed struct {
        a: lu16,
    };
    pub const Cmd_308 = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_30a = packed struct {
        a: lu16,
    };
    pub const Cmd_30d = packed struct {
        a: lu16,
    };
    pub const Cmd_30e = packed struct {
        a: lu16,
    };
    pub const Cmd_30f = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_311 = packed struct {
        a: lu16,
    };
    pub const Cmd_312 = packed struct {
        a: lu16,
    };
    pub const Cmd_313 = packed struct {
        a: lu16,
    };
    pub const Cmd_314 = packed struct {
        a: lu16,
    };
    pub const Cmd_315 = packed struct {
        a: lu16,
    };
    pub const Cmd_317 = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const Cmd_319 = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_31a = packed struct {
        a: lu16,
    };
    pub const Cmd_31b = packed struct {
        a: lu16,
    };
    pub const Cmd_31c = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_31d = packed struct {
        a: lu16,
    };
    pub const Cmd_31e = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_321 = packed struct {
        a: lu16,
    };
    pub const Cmd_323 = packed struct {
        a: lu16,
    };
    pub const Cmd_324 = packed struct {
        a: u8,
        b: u8,
        c: u8,
        d: u8,
        e: lu16,
        f: lu16,
    };
    pub const Cmd_325 = packed struct {
        a: lu16,
    };
    pub const Cmd_326 = packed struct {
        a: lu16,
    };
    pub const Cmd_327 = packed struct {
        a: lu16,
    };
    pub const PortalEffect = packed struct {
        a: lu16,
    };
    pub const Cmd_329 = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
        d: lu16,
    };
    pub const Cmd_32a = packed struct {
        a: lu16,
    };
    pub const Cmd_32b = packed struct {
        a: lu16,
    };
    pub const Cmd_32c = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
        d: lu16,
    };
    pub const Cmd_32f = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_333 = packed struct {
        a: lu16,
    };
    pub const Cmd_334 = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_335 = packed struct {
        a: lu16,
        b: lu32,
    };
    pub const Cmd_336 = packed struct {
        a: lu16,
    };
    pub const Cmd_337 = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_33a = packed struct {
        a: u8,
    };
    pub const Cmd_33c = packed struct {
        a: u8,
        b: lu16,
    };
    pub const Cmd_33d = packed struct {
        a: u8,
        b: lu16,
    };
    pub const Cmd_33e = packed struct {
        a: u8,
        b: lu16,
    };
    pub const Cmd_33f = packed struct {
        a: u8,
        b: lu16,
    };
    pub const Cmd_340 = packed struct {
        a: u8,
        b: lu16,
    };
    pub const Cmd_341 = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_342 = packed struct {
        a: u8,
    };
    pub const Cmd_343 = packed struct {
        a: u8,
        b: lu16,
    };
    pub const Cmd_344 = packed struct {
        a: u8,
        b: lu16,
    };
    pub const Cmd_345 = packed struct {
        a: u8,
        b: lu16,
    };
    pub const Cmd_346 = packed struct {
        a: u8,
    };
    pub const DisplayFloor = packed struct {
        a: u8,
        b: u8,
    };
};

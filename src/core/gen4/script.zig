const rom = @import("../rom.zig");
const script = @import("../script.zig");
const std = @import("std");

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
            .@"return",
            .return2,
            .jump,
            => return true,
            else => return false,
        }
    }
}.isEnd);

// These commands are only valid in dia/pearl/plat
pub const Command = extern union {
    kind: Kind,
    nop0: Arg0,
    nop1: Arg0,
    end: Arg0,
    return2: Return2,
    cmd_a: Cmd_a,
    @"if": If,
    if2: If2,
    call_standard: CallStandard,
    exit_standard: Arg0,
    jump: Jump,
    call: Call,
    @"return": Arg0,
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
    cmd_30: Arg0,
    wait_button: Arg0,
    cmd_32: Arg0,
    cmd_33: Arg0,
    close_msg_on_key_press: Arg0,
    freeze_message_box: Arg0,
    call_message_box: CallMessageBox,
    color_msg_box: ColorMsgBox,
    type_message_box: TypeMessageBox,
    no_map_message_box: Arg0,
    call_text_msg_box: Arg0,
    store_menu_status: StoreMenuStatus,
    show_menu: Arg0,
    yes_no_box: YesNoBox,
    multi: Multi,
    multi2: Multi2,
    cmd_42: Cmd_42,
    close_multi: Arg0,
    multi3: Multi3,
    multi4: Multi4,
    txt_msg_scrp_multi: TxtMsgScrpMulti,
    close_multi4: Arg0,
    play_fanfare: PlayFanfare,
    multi_row: MultiRow,
    play_fanfare2: PlayFanfare2,
    wait_fanfare: WaitFanfare,
    play_cry: PlayCry,
    wait_cry: Arg0,
    soundfr: Soundfr,
    cmd_4f: Arg0,
    play_sound: PlaySound,
    stop: Stop,
    restart: Arg0,
    cmd_53: Cmd_53,
    switch_music: SwitchMusic,
    store_saying_learned: StoreSayingLearned,
    play_sound2: PlaySound2,
    cmd_58: Cmd_58,
    check_saying_learned: CheckSayingLearned,
    swith_music2: SwithMusic2,
    act_microphone: Arg0,
    deact_microphone: Arg0,
    cmd_5d: Arg0,
    apply_movement: ApplyMovement,
    wait_movement: Arg0,
    lock_all: Arg0,
    release_all: Arg0,
    lock: Lock,
    release: Release,
    add_people: AddPeople,
    remove_people: RemovePeople,
    lock_cam: LockCam,
    zoom_cam: Arg0,
    face_player: Arg0,
    check_sprite_position: CheckSpritePosition,
    check_person_position: CheckPersonPosition,
    continue_follow: ContinueFollow,
    follow_hero: FollowHero,
    take_money: TakeMoney,
    check_money: CheckMoney,
    show_money: ShowMoney,
    hide_money: Arg0,
    update_money: Arg0,
    show_coins: ShowCoins,
    hide_coins: Arg0,
    update_coins: Arg0,
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
    cmd_9c: Arg0,
    cmd_9d: Arg0,
    cmd_9e: Arg0,
    cmd_9f: Arg0,
    cmd_a0: Arg0,
    call_end: Arg0,
    cmd__a2: Arg0,
    wfc_: Arg0,
    cmd_a4: Cmd_a4,
    interview: Arg0,
    dress_pokemon: DressPokemon,
    display_dressed_pokemon: DisplayDressedPokemon,
    display_contest_pokemon: DisplayContestPokemon,
    open_ball_capsule: Arg0,
    open_sinnoh_maps: Arg0,
    open_pc_function: OpenPcFunction,
    draw_union: Arg0,
    trainer_case_union: Arg0,
    trade_union: Arg0,
    record_mixing_union: Arg0,
    end_game: Arg0,
    hall_fame_anm: Arg0,
    store_wfc_status: StoreWfcStatus,
    start_wfc: StartWfc,
    choose_starter: Arg0,
    battle_starter: Arg0,
    battle_id: BattleId,
    set_var_battle: SetVarBattle,
    check_battle_type: CheckBattleType,
    set_var_battle2: SetVarBattle2,
    choose_poke_nick: ChoosePokeNick,
    fade_screen: FadeScreen,
    reset_screen: Arg0,
    warp: Warp,
    rock_climb_animation: RockClimbAnimation,
    surf_animation: Arg0,
    waterfall_animation: WaterfallAnimation,
    flash_animation: Arg0,
    defog_animation: Arg0,
    prep_hm_effect: PrepHmEffect,
    tuxedo: Arg0,
    check_bike: CheckBike,
    ride_bike: RideBike,
    ride_bike2: RideBike2,
    give_poke_hiro_anm: GivePokeHiroAnm,
    stop_give_poke_hiro_anm: Arg0,
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
    lost_go_pc: Arg0,
    check_trainer_lost: CheckTrainerLost,
    check_trainer_status2: CheckTrainerStatus2,
    store_poke_party_defeated: StorePokePartyDefeated,
    chs_friend: ChsFriend,
    wire_battle_wait: WireBattleWait,
    cmd_f6: Arg0,
    pokecontest: Arg0,
    start_ovation: StartOvation,
    stop_ovation: StopOvation,
    cmd_fa: Cmd_fa,
    cmd_fb: Cmd_fb,
    cmd_fc: Cmd_fc,
    setvar_other_entry: SetvarOtherEntry,
    cmd_fe: Cmd_fe,
    setvat_hiro_entry: SetvatHiroEntry,
    cmd_100: Arg0,
    black_flash_effect: Arg0,
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
    end_flash: Arg0,
    carpet_anm: Arg0,
    cmd_114: Arg0,
    cmd_115: Cmd_115,
    show_lnk_cnt_record: Arg0,
    cmd_117: Arg0,
    cmd_118: Arg0,
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
    explanation_battle: Arg0,
    honey_tree_battle: Arg0,
    check_if_honey_slathered: CheckIfHoneySlathered,
    random_battle: Arg0,
    stop_random_battle: Arg0,
    write_autograph: Arg0,
    store_save_data: StoreSaveData,
    check_save_data: CheckSaveData,
    check_dress: CheckDress,
    check_contest_win: CheckContestWin,
    store_photo_name: StorePhotoName,
    give_poketch: Arg0,
    check_ptch_appl: CheckPtchAppl,
    act_pktch_appl: ActPktchAppl,
    store_poketch_app: StorePoketchApp,
    friend_b_t: FriendBT,
    friend_b_t2: Arg0,
    cmd_138: Cmd_138,
    open_union_function2: OpenUnionFunction2,
    start_union: Arg0,
    link_closed: Arg0,
    set_union_function_id: SetUnionFunctionId,
    close_union_function: Arg0,
    close_union_function2: Arg0,
    set_var_union_message: SetVarUnionMessage,
    store_your_decision_union: StoreYourDecisionUnion,
    store_other_decision_union: StoreOtherDecisionUnion,
    cmd_142: Arg0,
    check_other_decision_union: CheckOtherDecisionUnion,
    store_your_decision_union2: StoreYourDecisionUnion2,
    store_other_decision_union2: StoreOtherDecisionUnion2,
    check_other_decision_union2: CheckOtherDecisionUnion2,
    pokemart: Pokemart,
    pokemart1: Pokemart1,
    pokemart2: Pokemart2,
    pokemart3: Pokemart3,
    defeat_go_pokecenter: Arg0,
    act_bike: ActBike,
    check_gender: CheckGender,
    heal_pokemon: Arg0,
    deact_wireless: Arg0,
    delete_entry: Arg0,
    cmd_151: Arg0,
    underground_id: UndergroundId,
    union_room: Arg0,
    open_wi_fi_sprite: Arg0,
    store_wi_fi_sprite: StoreWiFiSprite,
    act_wi_fi_sprite: ActWiFiSprite,
    cmd_157: Cmd_157,
    activate_pokedex: Arg0,
    give_running_shoes: Arg0,
    check_badge: CheckBadge,
    enable_badge: EnableBadge,
    disable_badge: DisableBadge,
    check_follow: CheckFollow,
    start_follow: Arg0,
    stop_follow: Arg0,
    cmd_164: Arg0,
    cmd_166: Cmd_166,
    prepare_door_animation: PrepareDoorAnimation,
    wait_action: WaitAction,
    wait_close: WaitClose,
    open_door: OpenDoor,
    close_door: CloseDoor,
    act_dcare_function: Arg0,
    store_p_d_care_num: StorePDCareNum,
    pastoria_city_function: Arg0,
    pastoria_city_function2: Arg0,
    hearthrome_gym_function: Arg0,
    hearthrome_gym_function2: Arg0,
    canalave_gym_function: Arg0,
    veilstone_gym_function: Arg0,
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
    cmd_185: Arg0,
    change_ow_position: ChangeOwPosition,
    set_ow_position: SetOwPosition,
    change_ow_movement: ChangeOwMovement,
    release_ow: ReleaseOw,
    set_tile_passable: SetTilePassable,
    set_tile_locked: SetTileLocked,
    set_ows_follow: SetOwsFollow,
    show_clock_save: Arg0,
    hide_clock_save: Arg0,
    cmd_18f: Cmd_18f,
    set_save_data: SetSaveData,
    chs_pokemenu: Arg0,
    chs_pokemenu2: Arg0,
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
    underground_start: Arg0,
    take_money_d_care: TakeMoneyDCare,
    take_pokemon_d_care: TakePokemonDCare,
    act_egg_day_c_man: Arg0,
    deact_egg_day_c_man: Arg0,
    set_var_poke_and_money_d_care: SetVarPokeAndMoneyDCare,
    check_money_d_care: CheckMoneyDCare,
    egg_animation: Arg0,
    set_var_poke_and_level_d_care: SetVarPokeAndLevelDCare,
    set_var_poke_chosen_d_care: SetVarPokeChosenDCare,
    give_poke_d_care: GivePokeDCare,
    add_people2: AddPeople2,
    remove_people2: RemovePeople2,
    mail_box: Arg0,
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
    show_move_info: Arg0,
    store_poke_delete: StorePokeDelete,
    store_move_delete: StoreMoveDelete,
    check_move_num_delete: CheckMoveNumDelete,
    store_delete_move: StoreDeleteMove,
    check_delete_move: CheckDeleteMove,
    setvar_move_delete: SetvarMoveDelete,
    cmd_1cc: Arg0,
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
    activate_b_tower: Arg0,
    store_b_tower_data: StoreBTowerData,
    close_b_tower: Arg0,
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
    show_sinnoh_sheet: Arg0,
    show_national_sheet: Arg0,
    cmd_1ec: Arg0,
    store_trophy_pokemon: StoreTrophyPokemon,
    cmd_1ef: Cmd_1ef,
    cmd_1f0: Cmd_1f0,
    check_act_fossil: CheckActFossil,
    cmd_1f2: Arg0,
    cmd_1f3: Arg0,
    check_item_chosen: CheckItemChosen,
    compare_item_poke_fossil: CompareItemPokeFossil,
    check_pokemon_level: CheckPokemonLevel,
    check_is_pokemon_poisoned: CheckIsPokemonPoisoned,
    pre_wfc: Arg0,
    store_furniture: StoreFurniture,
    copy_furniture: CopyFurniture,
    set_b_castle_function_id: SetBCastleFunctionId,
    b_castle_funct_return: BCastleFunctReturn,
    cmd_200: Cmd_200,
    check_effect_hm: CheckEffectHm,
    great_marsh_function: GreatMarshFunction,
    battle_poke_colosseum: BattlePokeColosseum,
    warp_last_elevator: Arg0,
    open_geo_net: Arg0,
    great_marsh_bynocule: Arg0,
    store_poke_colosseum_lost: StorePokeColosseumLost,
    pokemon_picture: PokemonPicture,
    hide_picture: Arg0,
    cmd_20a: Cmd_20a,
    cmd_20b: Arg0,
    cmd_20c: Arg0,
    setvar_mt_coronet: SetvarMtCoronet,
    cmd_20e: Arg0,
    check_quic_trine_coordinates: CheckQuicTrineCoordinates,
    setvar_quick_train_coordinates: SetvarQuickTrainCoordinates,
    move_train_anm: MoveTrainAnm,
    store_poke_nature: StorePokeNature,
    check_poke_nature: CheckPokeNature,
    random_hallowes: RandomHallowes,
    start_amity: Arg0,
    cmd_216: Cmd_216,
    cmd_217: Cmd_217,
    chs_r_s_poke: ChsRSPoke,
    set_s_poke: SetSPoke,
    check_s_poke: CheckSPoke,
    cmd_21b: Arg0,
    act_swarm_poke: ActSwarmPoke,
    cmd_21d: Cmd_21d,
    cmd_21e: Arg0,
    check_move_remember: CheckMoveRemember,
    cmd_220: Arg0,
    store_poke_remember: StorePokeRemember,
    cmd_222: Arg0,
    store_remember_move: Arg0,
    teach_move: TeachMove,
    check_teach_move: CheckTeachMove,
    set_trade_id: SetTradeId,
    check_pokemon_trade: CheckPokemonTrade,
    trade_chosen_pokemon: TradeChosenPokemon,
    stop_trade: Arg0,
    cmd_22b: Arg0,
    close_oak_assistant_event: Arg0,
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
    cmd_250: Arg0,
    check_boxes_number: CheckBoxesNumber,
    stop_great_marsh: StopGreatMarsh,
    check_poke_catching_show: CheckPokeCatchingShow,
    close_catching_show: Arg0,
    check_catching_show_records: CheckCatchingShowRecords,
    sprt_save: Arg0,
    ret_sprt_save: Arg0,
    elev_lg_animation: Arg0,
    check_elev_lg_anm: CheckElevLgAnm,
    elev_ir_anm: Arg0,
    stop_elev_anm: Arg0,
    check_elev_position: CheckElevPosition,
    galact_anm: Arg0,
    galact_anm2: Arg0,
    main_event: MainEvent,
    check_accessories3: CheckAccessories3,
    act_deoxis_form_change: ActDeoxisFormChange,
    change_form_deoxis: ChangeFormDeoxis,
    check_coombe_event: CheckCoombeEvent,
    act_contest_map: Arg0,
    cmd_266: Arg0,
    pokecasino: Pokecasino,
    check_time2: CheckTime2,
    regigigas_anm: RegigigasAnm,
    cresselia_anm: CresseliaAnm,
    check_regi: CheckRegi,
    check_massage: CheckMassage,
    unown_message_box: UnownMessageBox,
    check_p_catching_show: CheckPCatchingShow,
    cmd_26f: Arg0,
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
    league_castle_view: Arg0,
    cmd_27b: Arg0,
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
    act_learning: Arg0,
    set_sound_learning: SetSoundLearning,
    check_first_time_champion: CheckFirstTimeChampion,
    choose_poke_d_care: ChoosePokeDCare,
    store_poke_d_care: StorePokeDCare,
    cmd_292: Cmd_292,
    check_master_rank: CheckMasterRank,
    show_battle_points_box: ShowBattlePointsBox,
    hide_battle_points_box: Arg0,
    update_battle_points_box: Arg0,
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
    choose_trade_pokemon: Arg0,
    chs_prize_casino: ChsPrizeCasino,
    check_plate: CheckPlate,
    take_coins_casino: TakeCoinsCasino,
    check_coins_casino2: CheckCoinsCasino2,
    compare_phrase_box_input: ComparePhraseBoxInput,
    store_seal_num: StoreSealNum,
    activate_mystery_gift: Arg0,
    check_follow_battle: CheckFollowBattle,
    cmd_2af: Cmd_2af,
    cmd_2b0: Arg0,
    cmd_2b1: Arg0,
    cmd_2b2: Arg0,
    setvar_seal_random: SetvarSealRandom,
    darkrai_function: DarkraiFunction,
    cmd_2b6: Cmd_2b6,
    store_poke_num_party: StorePokeNumParty,
    store_poke_nickname: StorePokeNickname,
    close_multi_union: Arg0,
    check_battle_union: CheckBattleUnion,
    cmd_2_b_b: Arg0,
    check_wild_battle2: CheckWildBattle2,
    wild_battle2: WildBattle,
    store_trainer_card_star: StoreTrainerCardStar,
    bike_ride: Arg0,
    cmd_2c0: Cmd_2c0,
    show_save_box: Arg0,
    hide_save_box: Arg0,
    cmd_2c3: Cmd_2c3,
    show_b_tower_some: ShowBTowerSome,
    delete_saves_b_factory: DeleteSavesBFactory,
    spin_trade_union: Arg0,
    check_version_game: CheckVersionGame,
    show_b_arcade_recors: ShowBArcadeRecors,
    eterna_gym_anm: Arg0,
    floral_clock_animation: Arg0,
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
    cmd_2d6: Arg0,
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
    cmd_2e2: Arg0,
    cmd_2e3: Arg0,
    cmd_2e4: Cmd_2e4,
    cmd_2e5: Cmd_2e5,
    cmd_2e6: Cmd_2e6,
    cmd_2e7: Cmd_2e7,
    cmd_2e8: Cmd_2e8,
    cmd_2e9: Cmd_2e9,
    cmd_2ea: Cmd_2ea,
    cmd_2eb: Cmd_2eb,
    cmd_2ec: Cmd_2ec,
    cmd_2ed: Arg0,
    cmd_2ee: Cmd_2ee,
    cmd_2f0: Arg0,
    cmd_2f2: Arg0,
    cmd_2f3: Cmd_2f3,
    cmd_2f4: Cmd_2f4,
    cmd_2f5: Cmd_2f5,
    cmd_2f6: Cmd_2f6,
    cmd_2f7: Cmd_2f7,
    cmd_2f8: Arg0,
    cmd_2f9: Cmd_2f9,
    cmd_2fa: Cmd_2fa,
    cmd_2fb: Arg0,
    cmd_2fc: Cmd_2fc,
    cmd_2fd: Cmd_2fd,
    cmd_2fe: Cmd_2fe,
    cmd_2ff: Cmd_2ff,
    cmd_300: Arg0,
    cmd_302: Cmd_302,
    cmd_303: Cmd_303,
    cmd_304: Cmd_304,
    cmd_305: Cmd_305,
    cmd_306: Cmd_306,
    cmd_307: Cmd_307,
    cmd_308: Cmd_308,
    cmd_309: Arg0,
    cmd_30a: Cmd_30a,
    cmd_30b: Arg0,
    cmd_30c: Arg0,
    cmd_30d: Cmd_30d,
    cmd_30e: Cmd_30e,
    cmd_30f: Cmd_30f,
    cmd_310: Arg0,
    cmd_311: Cmd_311,
    cmd_312: Cmd_312,
    cmd_313: Cmd_313,
    cmd_314: Cmd_314,
    cmd_315: Cmd_315,
    cmd_316: Arg0,
    cmd_317: Cmd_317,
    wild_battle3: WildBattle,
    cmd_319: Cmd_319,
    cmd_31a: Cmd_31a,
    cmd_31b: Cmd_31b,
    cmd_31c: Cmd_31c,
    cmd_31d: Cmd_31d,
    cmd_31e: Cmd_31e,
    cmd_31f: Arg0,
    cmd_320: Arg0,
    cmd_321: Cmd_321,
    cmd_322: Arg0,
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
    cmd_32d: Arg0,
    cmd_32e: Arg0,
    cmd_32f: Cmd_32f,
    cmd_330: Arg0,
    cmd_331: Arg0,
    cmd_332: Arg0,
    cmd_333: Cmd_333,
    cmd_334: Cmd_334,
    cmd_335: Cmd_335,
    cmd_336: Cmd_336,
    cmd_337: Cmd_337,
    cmd_338: Arg0,
    cmd_339: Arg0,
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

    pub const Kind = enum(u16) {
        nop0 = @intFromEnum(lu16.init(0x0)),
        nop1 = @intFromEnum(lu16.init(0x1)),
        end = @intFromEnum(lu16.init(0x2)),
        return2 = @intFromEnum(lu16.init(0x3)),
        cmd_a = @intFromEnum(lu16.init(0xa)),
        @"if" = @intFromEnum(lu16.init(0x11)),
        if2 = @intFromEnum(lu16.init(0x12)),
        call_standard = @intFromEnum(lu16.init(0x14)),
        exit_standard = @intFromEnum(lu16.init(0x15)),
        jump = @intFromEnum(lu16.init(0x16)),
        call = @intFromEnum(lu16.init(0x1a)),
        @"return" = @intFromEnum(lu16.init(0x1b)),
        compare_last_result_jump = @intFromEnum(lu16.init(0x1c)),
        compare_last_result_call = @intFromEnum(lu16.init(0x1d)),
        set_flag = @intFromEnum(lu16.init(0x1e)),
        clear_flag = @intFromEnum(lu16.init(0x1f)),
        check_flag = @intFromEnum(lu16.init(0x20)),
        cmd_21 = @intFromEnum(lu16.init(0x21)),
        cmd_22 = @intFromEnum(lu16.init(0x22)),
        set_trainer_id = @intFromEnum(lu16.init(0x23)),
        cmd_24 = @intFromEnum(lu16.init(0x24)),
        clear_trainer_id = @intFromEnum(lu16.init(0x25)),
        script_cmd__add_value = @intFromEnum(lu16.init(0x26)),
        script_cmd__sub_value = @intFromEnum(lu16.init(0x27)),
        set_var = @intFromEnum(lu16.init(0x28)),
        copy_var = @intFromEnum(lu16.init(0x29)),
        message2 = @intFromEnum(lu16.init(0x2b)),
        message = @intFromEnum(lu16.init(0x2c)),
        message3 = @intFromEnum(lu16.init(0x2d)),
        message4 = @intFromEnum(lu16.init(0x2e)),
        message5 = @intFromEnum(lu16.init(0x2f)),
        cmd_30 = @intFromEnum(lu16.init(0x30)),
        wait_button = @intFromEnum(lu16.init(0x31)),
        cmd_32 = @intFromEnum(lu16.init(0x32)),
        cmd_33 = @intFromEnum(lu16.init(0x33)),
        close_msg_on_key_press = @intFromEnum(lu16.init(0x34)),
        freeze_message_box = @intFromEnum(lu16.init(0x35)),
        call_message_box = @intFromEnum(lu16.init(0x36)),
        color_msg_box = @intFromEnum(lu16.init(0x37)),
        type_message_box = @intFromEnum(lu16.init(0x38)),
        no_map_message_box = @intFromEnum(lu16.init(0x39)),
        call_text_msg_box = @intFromEnum(lu16.init(0x3a)),
        store_menu_status = @intFromEnum(lu16.init(0x3b)),
        show_menu = @intFromEnum(lu16.init(0x3c)),
        yes_no_box = @intFromEnum(lu16.init(0x3e)),
        multi = @intFromEnum(lu16.init(0x40)),
        multi2 = @intFromEnum(lu16.init(0x41)),
        cmd_42 = @intFromEnum(lu16.init(0x42)),
        close_multi = @intFromEnum(lu16.init(0x43)),
        multi3 = @intFromEnum(lu16.init(0x44)),
        multi4 = @intFromEnum(lu16.init(0x45)),
        txt_msg_scrp_multi = @intFromEnum(lu16.init(0x46)),
        close_multi4 = @intFromEnum(lu16.init(0x47)),
        play_fanfare = @intFromEnum(lu16.init(0x49)),
        multi_row = @intFromEnum(lu16.init(0x48)),
        play_fanfare2 = @intFromEnum(lu16.init(0x4a)),
        wait_fanfare = @intFromEnum(lu16.init(0x4b)),
        play_cry = @intFromEnum(lu16.init(0x4c)),
        wait_cry = @intFromEnum(lu16.init(0x4d)),
        soundfr = @intFromEnum(lu16.init(0x4e)),
        cmd_4f = @intFromEnum(lu16.init(0x4f)),
        play_sound = @intFromEnum(lu16.init(0x50)),
        stop = @intFromEnum(lu16.init(0x51)),
        restart = @intFromEnum(lu16.init(0x52)),
        cmd_53 = @intFromEnum(lu16.init(0x53)),
        switch_music = @intFromEnum(lu16.init(0x54)),
        store_saying_learned = @intFromEnum(lu16.init(0x55)),
        play_sound2 = @intFromEnum(lu16.init(0x57)),
        cmd_58 = @intFromEnum(lu16.init(0x58)),
        check_saying_learned = @intFromEnum(lu16.init(0x59)),
        swith_music2 = @intFromEnum(lu16.init(0x5a)),
        act_microphone = @intFromEnum(lu16.init(0x5b)),
        deact_microphone = @intFromEnum(lu16.init(0x5c)),
        cmd_5d = @intFromEnum(lu16.init(0x5d)),
        apply_movement = @intFromEnum(lu16.init(0x5e)),
        wait_movement = @intFromEnum(lu16.init(0x5f)),
        lock_all = @intFromEnum(lu16.init(0x60)),
        release_all = @intFromEnum(lu16.init(0x61)),
        lock = @intFromEnum(lu16.init(0x62)),
        release = @intFromEnum(lu16.init(0x63)),
        add_people = @intFromEnum(lu16.init(0x64)),
        remove_people = @intFromEnum(lu16.init(0x65)),
        lock_cam = @intFromEnum(lu16.init(0x66)),
        zoom_cam = @intFromEnum(lu16.init(0x67)),
        face_player = @intFromEnum(lu16.init(0x68)),
        check_sprite_position = @intFromEnum(lu16.init(0x69)),
        check_person_position = @intFromEnum(lu16.init(0x6b)),
        continue_follow = @intFromEnum(lu16.init(0x6c)),
        follow_hero = @intFromEnum(lu16.init(0x6d)),
        take_money = @intFromEnum(lu16.init(0x70)),
        check_money = @intFromEnum(lu16.init(0x71)),
        show_money = @intFromEnum(lu16.init(0x72)),
        hide_money = @intFromEnum(lu16.init(0x73)),
        update_money = @intFromEnum(lu16.init(0x74)),
        show_coins = @intFromEnum(lu16.init(0x75)),
        hide_coins = @intFromEnum(lu16.init(0x76)),
        update_coins = @intFromEnum(lu16.init(0x77)),
        check_coins = @intFromEnum(lu16.init(0x78)),
        give_coins = @intFromEnum(lu16.init(0x79)),
        take_coins = @intFromEnum(lu16.init(0x7a)),
        take_item = @intFromEnum(lu16.init(0x7b)),
        give_item = @intFromEnum(lu16.init(0x7c)),
        check_store_item = @intFromEnum(lu16.init(0x7d)),
        check_item = @intFromEnum(lu16.init(0x7e)),
        store_item_taken = @intFromEnum(lu16.init(0x7f)),
        store_item_type = @intFromEnum(lu16.init(0x80)),
        send_item_type1 = @intFromEnum(lu16.init(0x83)),
        cmd_84 = @intFromEnum(lu16.init(0x84)),
        check_underground_pc_status = @intFromEnum(lu16.init(0x85)),
        cmd_86 = @intFromEnum(lu16.init(0x86)),
        send_item_type2 = @intFromEnum(lu16.init(0x87)),
        cmd_88 = @intFromEnum(lu16.init(0x88)),
        cmd_89 = @intFromEnum(lu16.init(0x89)),
        cmd_8a = @intFromEnum(lu16.init(0x8a)),
        cmd_8b = @intFromEnum(lu16.init(0x8b)),
        cmd_8c = @intFromEnum(lu16.init(0x8c)),
        cmd_8d = @intFromEnum(lu16.init(0x8d)),
        cmd_8e = @intFromEnum(lu16.init(0x8e)),
        send_item_type3 = @intFromEnum(lu16.init(0x8f)),
        check_pokemon_party = @intFromEnum(lu16.init(0x93)),
        store_pokemon_party = @intFromEnum(lu16.init(0x94)),
        set_pokemon_party_stored = @intFromEnum(lu16.init(0x95)),
        give_pokemon = @intFromEnum(lu16.init(0x96)),
        give_egg = @intFromEnum(lu16.init(0x97)),
        check_move = @intFromEnum(lu16.init(0x99)),
        check_place_stored = @intFromEnum(lu16.init(0x9a)),
        cmd_9b = @intFromEnum(lu16.init(0x9b)),
        cmd_9c = @intFromEnum(lu16.init(0x9c)),
        cmd_9d = @intFromEnum(lu16.init(0x9d)),
        cmd_9e = @intFromEnum(lu16.init(0x9e)),
        cmd_9f = @intFromEnum(lu16.init(0x9f)),
        cmd_a0 = @intFromEnum(lu16.init(0xa0)),
        call_end = @intFromEnum(lu16.init(0xa1)),
        cmd__a2 = @intFromEnum(lu16.init(0xa2)),
        wfc_ = @intFromEnum(lu16.init(0xa3)),
        cmd_a4 = @intFromEnum(lu16.init(0xa4)),
        interview = @intFromEnum(lu16.init(0xa5)),
        dress_pokemon = @intFromEnum(lu16.init(0xa6)),
        display_dressed_pokemon = @intFromEnum(lu16.init(0xa7)),
        display_contest_pokemon = @intFromEnum(lu16.init(0xa8)),
        open_ball_capsule = @intFromEnum(lu16.init(0xa9)),
        open_sinnoh_maps = @intFromEnum(lu16.init(0xaa)),
        open_pc_function = @intFromEnum(lu16.init(0xab)),
        draw_union = @intFromEnum(lu16.init(0xac)),
        trainer_case_union = @intFromEnum(lu16.init(0xad)),
        trade_union = @intFromEnum(lu16.init(0xae)),
        record_mixing_union = @intFromEnum(lu16.init(0xaf)),
        end_game = @intFromEnum(lu16.init(0xb0)),
        hall_fame_anm = @intFromEnum(lu16.init(0xb1)),
        store_wfc_status = @intFromEnum(lu16.init(0xb2)),
        start_wfc = @intFromEnum(lu16.init(0xb3)),
        choose_starter = @intFromEnum(lu16.init(0xb4)),
        battle_starter = @intFromEnum(lu16.init(0xb5)),
        battle_id = @intFromEnum(lu16.init(0xb6)),
        set_var_battle = @intFromEnum(lu16.init(0xb7)),
        check_battle_type = @intFromEnum(lu16.init(0xb8)),
        set_var_battle2 = @intFromEnum(lu16.init(0xb9)),
        choose_poke_nick = @intFromEnum(lu16.init(0xbb)),
        fade_screen = @intFromEnum(lu16.init(0xbc)),
        reset_screen = @intFromEnum(lu16.init(0xbd)),
        warp = @intFromEnum(lu16.init(0xbe)),
        rock_climb_animation = @intFromEnum(lu16.init(0xbf)),
        surf_animation = @intFromEnum(lu16.init(0xc0)),
        waterfall_animation = @intFromEnum(lu16.init(0xc1)),
        flash_animation = @intFromEnum(lu16.init(0xc3)),
        defog_animation = @intFromEnum(lu16.init(0xc4)),
        prep_hm_effect = @intFromEnum(lu16.init(0xc5)),
        tuxedo = @intFromEnum(lu16.init(0xc6)),
        check_bike = @intFromEnum(lu16.init(0xc7)),
        ride_bike = @intFromEnum(lu16.init(0xc8)),
        ride_bike2 = @intFromEnum(lu16.init(0xc9)),
        give_poke_hiro_anm = @intFromEnum(lu16.init(0xcb)),
        stop_give_poke_hiro_anm = @intFromEnum(lu16.init(0xcc)),
        set_var_hero = @intFromEnum(lu16.init(0xcd)),
        set_variable_rival = @intFromEnum(lu16.init(0xce)),
        set_var_alter = @intFromEnum(lu16.init(0xcf)),
        set_var_poke = @intFromEnum(lu16.init(0xd0)),
        set_var_item = @intFromEnum(lu16.init(0xd1)),
        set_var_item_num = @intFromEnum(lu16.init(0xd2)),
        set_var_atk_item = @intFromEnum(lu16.init(0xd3)),
        set_var_atk = @intFromEnum(lu16.init(0xd4)),
        set_variable_number = @intFromEnum(lu16.init(0xd5)),
        set_var_poke_nick = @intFromEnum(lu16.init(0xd6)),
        set_var_obj = @intFromEnum(lu16.init(0xd7)),
        set_var_trainer = @intFromEnum(lu16.init(0xd8)),
        set_var_wi_fi_sprite = @intFromEnum(lu16.init(0xd9)),
        set_var_poke_stored = @intFromEnum(lu16.init(0xda)),
        set_var_str_hero = @intFromEnum(lu16.init(0xdb)),
        set_var_str_rival = @intFromEnum(lu16.init(0xdc)),
        store_starter = @intFromEnum(lu16.init(0xde)),
        cmd_df = @intFromEnum(lu16.init(0xdf)),
        set_var_item_stored = @intFromEnum(lu16.init(0xe0)),
        set_var_item_stored2 = @intFromEnum(lu16.init(0xe1)),
        set_var_swarm_poke = @intFromEnum(lu16.init(0xe2)),
        check_swarm_poke = @intFromEnum(lu16.init(0xe3)),
        start_battle_analysis = @intFromEnum(lu16.init(0xe4)),
        trainer_battle = @intFromEnum(lu16.init(0xe5)),
        endtrainer_battle = @intFromEnum(lu16.init(0xe6)),
        trainer_battle_stored = @intFromEnum(lu16.init(0xe7)),
        trainer_battle_stored2 = @intFromEnum(lu16.init(0xe8)),
        check_trainer_status = @intFromEnum(lu16.init(0xe9)),
        store_league_trainer = @intFromEnum(lu16.init(0xea)),
        lost_go_pc = @intFromEnum(lu16.init(0xeb)),
        check_trainer_lost = @intFromEnum(lu16.init(0xec)),
        check_trainer_status2 = @intFromEnum(lu16.init(0xed)),
        store_poke_party_defeated = @intFromEnum(lu16.init(0xee)),
        chs_friend = @intFromEnum(lu16.init(0xf2)),
        wire_battle_wait = @intFromEnum(lu16.init(0xf3)),
        cmd_f6 = @intFromEnum(lu16.init(0xf6)),
        pokecontest = @intFromEnum(lu16.init(0xf7)),
        start_ovation = @intFromEnum(lu16.init(0xf8)),
        stop_ovation = @intFromEnum(lu16.init(0xf9)),
        cmd_fa = @intFromEnum(lu16.init(0xfa)),
        cmd_fb = @intFromEnum(lu16.init(0xfb)),
        cmd_fc = @intFromEnum(lu16.init(0xfc)),
        setvar_other_entry = @intFromEnum(lu16.init(0xfd)),
        cmd_fe = @intFromEnum(lu16.init(0xfe)),
        setvat_hiro_entry = @intFromEnum(lu16.init(0xff)),
        cmd_100 = @intFromEnum(lu16.init(0x100)),
        black_flash_effect = @intFromEnum(lu16.init(0x101)),
        setvar_type_contest = @intFromEnum(lu16.init(0x102)),
        setvar_rank_contest = @intFromEnum(lu16.init(0x103)),
        cmd_104 = @intFromEnum(lu16.init(0x104)),
        cmd_105 = @intFromEnum(lu16.init(0x105)),
        cmd_106 = @intFromEnum(lu16.init(0x106)),
        cmd_107 = @intFromEnum(lu16.init(0x107)),
        store_people_id_contest = @intFromEnum(lu16.init(0x108)),
        cmd_109 = @intFromEnum(lu16.init(0x109)),
        setvat_hiro_entry2 = @intFromEnum(lu16.init(0x10a)),
        act_people_contest = @intFromEnum(lu16.init(0x10b)),
        cmd_10c = @intFromEnum(lu16.init(0x10c)),
        cmd_10d = @intFromEnum(lu16.init(0x10d)),
        cmd_10e = @intFromEnum(lu16.init(0x10e)),
        cmd_10f = @intFromEnum(lu16.init(0x10f)),
        cmd_110 = @intFromEnum(lu16.init(0x110)),
        flash_contest = @intFromEnum(lu16.init(0x111)),
        end_flash = @intFromEnum(lu16.init(0x112)),
        carpet_anm = @intFromEnum(lu16.init(0x113)),
        cmd_114 = @intFromEnum(lu16.init(0x114)),
        cmd_115 = @intFromEnum(lu16.init(0x115)),
        show_lnk_cnt_record = @intFromEnum(lu16.init(0x116)),
        cmd_117 = @intFromEnum(lu16.init(0x117)),
        cmd_118 = @intFromEnum(lu16.init(0x118)),
        store_pokerus = @intFromEnum(lu16.init(0x119)),
        warp_map_elevator = @intFromEnum(lu16.init(0x11b)),
        check_floor = @intFromEnum(lu16.init(0x11c)),
        start_lift = @intFromEnum(lu16.init(0x11d)),
        store_sin_pokemon_seen = @intFromEnum(lu16.init(0x11e)),
        cmd_11f = @intFromEnum(lu16.init(0x11f)),
        store_tot_pokemon_seen = @intFromEnum(lu16.init(0x120)),
        store_nat_pokemon_seen = @intFromEnum(lu16.init(0x121)),
        set_var_text_pokedex = @intFromEnum(lu16.init(0x123)),
        wild_battle = @intFromEnum(lu16.init(0x124)),
        starter_battle = @intFromEnum(lu16.init(0x125)),
        explanation_battle = @intFromEnum(lu16.init(0x126)),
        honey_tree_battle = @intFromEnum(lu16.init(0x127)),
        check_if_honey_slathered = @intFromEnum(lu16.init(0x128)),
        random_battle = @intFromEnum(lu16.init(0x129)),
        stop_random_battle = @intFromEnum(lu16.init(0x12a)),
        write_autograph = @intFromEnum(lu16.init(0x12b)),
        store_save_data = @intFromEnum(lu16.init(0x12c)),
        check_save_data = @intFromEnum(lu16.init(0x12d)),
        check_dress = @intFromEnum(lu16.init(0x12e)),
        check_contest_win = @intFromEnum(lu16.init(0x12f)),
        store_photo_name = @intFromEnum(lu16.init(0x130)),
        give_poketch = @intFromEnum(lu16.init(0x131)),
        check_ptch_appl = @intFromEnum(lu16.init(0x132)),
        act_pktch_appl = @intFromEnum(lu16.init(0x133)),
        store_poketch_app = @intFromEnum(lu16.init(0x134)),
        friend_b_t = @intFromEnum(lu16.init(0x135)),
        friend_b_t2 = @intFromEnum(lu16.init(0x136)),
        cmd_138 = @intFromEnum(lu16.init(0x138)),
        open_union_function2 = @intFromEnum(lu16.init(0x139)),
        start_union = @intFromEnum(lu16.init(0x13a)),
        link_closed = @intFromEnum(lu16.init(0x13b)),
        set_union_function_id = @intFromEnum(lu16.init(0x13c)),
        close_union_function = @intFromEnum(lu16.init(0x13d)),
        close_union_function2 = @intFromEnum(lu16.init(0x13e)),
        set_var_union_message = @intFromEnum(lu16.init(0x13f)),
        store_your_decision_union = @intFromEnum(lu16.init(0x140)),
        store_other_decision_union = @intFromEnum(lu16.init(0x141)),
        cmd_142 = @intFromEnum(lu16.init(0x142)),
        check_other_decision_union = @intFromEnum(lu16.init(0x143)),
        store_your_decision_union2 = @intFromEnum(lu16.init(0x144)),
        store_other_decision_union2 = @intFromEnum(lu16.init(0x145)),
        check_other_decision_union2 = @intFromEnum(lu16.init(0x146)),
        pokemart = @intFromEnum(lu16.init(0x147)),
        pokemart1 = @intFromEnum(lu16.init(0x148)),
        pokemart2 = @intFromEnum(lu16.init(0x149)),
        pokemart3 = @intFromEnum(lu16.init(0x14a)),
        defeat_go_pokecenter = @intFromEnum(lu16.init(0x14b)),
        act_bike = @intFromEnum(lu16.init(0x14c)),
        check_gender = @intFromEnum(lu16.init(0x14d)),
        heal_pokemon = @intFromEnum(lu16.init(0x14e)),
        deact_wireless = @intFromEnum(lu16.init(0x14f)),
        delete_entry = @intFromEnum(lu16.init(0x150)),
        cmd_151 = @intFromEnum(lu16.init(0x151)),
        underground_id = @intFromEnum(lu16.init(0x152)),
        union_room = @intFromEnum(lu16.init(0x153)),
        open_wi_fi_sprite = @intFromEnum(lu16.init(0x154)),
        store_wi_fi_sprite = @intFromEnum(lu16.init(0x155)),
        act_wi_fi_sprite = @intFromEnum(lu16.init(0x156)),
        cmd_157 = @intFromEnum(lu16.init(0x157)),
        activate_pokedex = @intFromEnum(lu16.init(0x158)),
        give_running_shoes = @intFromEnum(lu16.init(0x15a)),
        check_badge = @intFromEnum(lu16.init(0x15b)),
        enable_badge = @intFromEnum(lu16.init(0x15c)),
        disable_badge = @intFromEnum(lu16.init(0x15d)),
        check_follow = @intFromEnum(lu16.init(0x160)),
        start_follow = @intFromEnum(lu16.init(0x161)),
        stop_follow = @intFromEnum(lu16.init(0x162)),
        cmd_164 = @intFromEnum(lu16.init(0x164)),
        cmd_166 = @intFromEnum(lu16.init(0x166)),
        prepare_door_animation = @intFromEnum(lu16.init(0x168)),
        wait_action = @intFromEnum(lu16.init(0x169)),
        wait_close = @intFromEnum(lu16.init(0x16a)),
        open_door = @intFromEnum(lu16.init(0x16b)),
        close_door = @intFromEnum(lu16.init(0x16c)),
        act_dcare_function = @intFromEnum(lu16.init(0x16d)),
        store_p_d_care_num = @intFromEnum(lu16.init(0x16e)),
        pastoria_city_function = @intFromEnum(lu16.init(0x16f)),
        pastoria_city_function2 = @intFromEnum(lu16.init(0x170)),
        hearthrome_gym_function = @intFromEnum(lu16.init(0x171)),
        hearthrome_gym_function2 = @intFromEnum(lu16.init(0x172)),
        canalave_gym_function = @intFromEnum(lu16.init(0x173)),
        veilstone_gym_function = @intFromEnum(lu16.init(0x174)),
        sunishore_gym_function = @intFromEnum(lu16.init(0x175)),
        sunishore_gym_function2 = @intFromEnum(lu16.init(0x176)),
        check_party_number = @intFromEnum(lu16.init(0x177)),
        open_berry_pouch = @intFromEnum(lu16.init(0x178)),
        cmd_179 = @intFromEnum(lu16.init(0x179)),
        cmd_17a = @intFromEnum(lu16.init(0x17a)),
        cmd_17b = @intFromEnum(lu16.init(0x17b)),
        set_nature_pokemon = @intFromEnum(lu16.init(0x17c)),
        cmd_17d = @intFromEnum(lu16.init(0x17d)),
        cmd_17e = @intFromEnum(lu16.init(0x17e)),
        cmd_17f = @intFromEnum(lu16.init(0x17f)),
        cmd_180 = @intFromEnum(lu16.init(0x180)),
        cmd_181 = @intFromEnum(lu16.init(0x181)),
        check_deoxis = @intFromEnum(lu16.init(0x182)),
        cmd_183 = @intFromEnum(lu16.init(0x183)),
        cmd_184 = @intFromEnum(lu16.init(0x184)),
        cmd_185 = @intFromEnum(lu16.init(0x185)),
        change_ow_position = @intFromEnum(lu16.init(0x186)),
        set_ow_position = @intFromEnum(lu16.init(0x187)),
        change_ow_movement = @intFromEnum(lu16.init(0x188)),
        release_ow = @intFromEnum(lu16.init(0x189)),
        set_tile_passable = @intFromEnum(lu16.init(0x18a)),
        set_tile_locked = @intFromEnum(lu16.init(0x18b)),
        set_ows_follow = @intFromEnum(lu16.init(0x18c)),
        show_clock_save = @intFromEnum(lu16.init(0x18d)),
        hide_clock_save = @intFromEnum(lu16.init(0x18e)),
        cmd_18f = @intFromEnum(lu16.init(0x18f)),
        set_save_data = @intFromEnum(lu16.init(0x190)),
        chs_pokemenu = @intFromEnum(lu16.init(0x191)),
        chs_pokemenu2 = @intFromEnum(lu16.init(0x192)),
        store_poke_menu2 = @intFromEnum(lu16.init(0x193)),
        chs_poke_contest = @intFromEnum(lu16.init(0x194)),
        store_poke_contest = @intFromEnum(lu16.init(0x195)),
        show_poke_info = @intFromEnum(lu16.init(0x196)),
        store_poke_move = @intFromEnum(lu16.init(0x197)),
        check_poke_egg = @intFromEnum(lu16.init(0x198)),
        compare_poke_nick = @intFromEnum(lu16.init(0x199)),
        check_party_number_union = @intFromEnum(lu16.init(0x19a)),
        check_poke_party_health = @intFromEnum(lu16.init(0x19b)),
        check_poke_party_num_d_care = @intFromEnum(lu16.init(0x19c)),
        check_egg_union = @intFromEnum(lu16.init(0x19d)),
        underground_function = @intFromEnum(lu16.init(0x19e)),
        underground_function2 = @intFromEnum(lu16.init(0x19f)),
        underground_start = @intFromEnum(lu16.init(0x1a0)),
        take_money_d_care = @intFromEnum(lu16.init(0x1a3)),
        take_pokemon_d_care = @intFromEnum(lu16.init(0x1a4)),
        act_egg_day_c_man = @intFromEnum(lu16.init(0x1a8)),
        deact_egg_day_c_man = @intFromEnum(lu16.init(0x1a9)),
        set_var_poke_and_money_d_care = @intFromEnum(lu16.init(0x1aa)),
        check_money_d_care = @intFromEnum(lu16.init(0x1ab)),
        egg_animation = @intFromEnum(lu16.init(0x1ac)),
        set_var_poke_and_level_d_care = @intFromEnum(lu16.init(0x1ae)),
        set_var_poke_chosen_d_care = @intFromEnum(lu16.init(0x1af)),
        give_poke_d_care = @intFromEnum(lu16.init(0x1b0)),
        add_people2 = @intFromEnum(lu16.init(0x1b1)),
        remove_people2 = @intFromEnum(lu16.init(0x1b2)),
        mail_box = @intFromEnum(lu16.init(0x1b3)),
        check_mail = @intFromEnum(lu16.init(0x1b4)),
        show_record_list = @intFromEnum(lu16.init(0x1b5)),
        check_time = @intFromEnum(lu16.init(0x1b6)),
        check_id_player = @intFromEnum(lu16.init(0x1b7)),
        random_text_stored = @intFromEnum(lu16.init(0x1b8)),
        store_happy_poke = @intFromEnum(lu16.init(0x1b9)),
        store_happy_status = @intFromEnum(lu16.init(0x1ba)),
        set_var_data_day_care = @intFromEnum(lu16.init(0x1bc)),
        check_face_position = @intFromEnum(lu16.init(0x1bd)),
        store_poke_d_care_love = @intFromEnum(lu16.init(0x1be)),
        check_status_solaceon_event = @intFromEnum(lu16.init(0x1bf)),
        check_poke_party = @intFromEnum(lu16.init(0x1c0)),
        copy_pokemon_height = @intFromEnum(lu16.init(0x1c1)),
        set_variable_pokemon_height = @intFromEnum(lu16.init(0x1c2)),
        compare_pokemon_height = @intFromEnum(lu16.init(0x1c3)),
        check_pokemon_height = @intFromEnum(lu16.init(0x1c4)),
        show_move_info = @intFromEnum(lu16.init(0x1c5)),
        store_poke_delete = @intFromEnum(lu16.init(0x1c6)),
        store_move_delete = @intFromEnum(lu16.init(0x1c7)),
        check_move_num_delete = @intFromEnum(lu16.init(0x1c8)),
        store_delete_move = @intFromEnum(lu16.init(0x1c9)),
        check_delete_move = @intFromEnum(lu16.init(0x1ca)),
        setvar_move_delete = @intFromEnum(lu16.init(0x1cb)),
        cmd_1cc = @intFromEnum(lu16.init(0x1cc)),
        de_activate_leader = @intFromEnum(lu16.init(0x1cd)),
        hm_functions = @intFromEnum(lu16.init(0x1cf)),
        flash_duration = @intFromEnum(lu16.init(0x1d0)),
        defog_duration = @intFromEnum(lu16.init(0x1d1)),
        give_accessories = @intFromEnum(lu16.init(0x1d2)),
        check_accessories = @intFromEnum(lu16.init(0x1d3)),
        cmd_1d4 = @intFromEnum(lu16.init(0x1d4)),
        give_accessories2 = @intFromEnum(lu16.init(0x1d5)),
        check_accessories2 = @intFromEnum(lu16.init(0x1d6)),
        berry_poffin = @intFromEnum(lu16.init(0x1d7)),
        set_var_b_tower_chs = @intFromEnum(lu16.init(0x1d8)),
        battle_room_result = @intFromEnum(lu16.init(0x1d9)),
        activate_b_tower = @intFromEnum(lu16.init(0x1da)),
        store_b_tower_data = @intFromEnum(lu16.init(0x1db)),
        close_b_tower = @intFromEnum(lu16.init(0x1dc)),
        call_b_tower_functions = @intFromEnum(lu16.init(0x1dd)),
        random_team_b_tower = @intFromEnum(lu16.init(0x1de)),
        store_prize_num_b_tower = @intFromEnum(lu16.init(0x1df)),
        store_people_id_b_tower = @intFromEnum(lu16.init(0x1e0)),
        call_b_tower_wire_function = @intFromEnum(lu16.init(0x1e1)),
        store_p_chosen_wire_b_tower = @intFromEnum(lu16.init(0x1e2)),
        store_rank_data_wire_b_tower = @intFromEnum(lu16.init(0x1e3)),
        cmd_1e4 = @intFromEnum(lu16.init(0x1e4)),
        random_event = @intFromEnum(lu16.init(0x1e5)),
        check_sinnoh_pokedex = @intFromEnum(lu16.init(0x1e8)),
        check_national_pokedex = @intFromEnum(lu16.init(0x1e9)),
        show_sinnoh_sheet = @intFromEnum(lu16.init(0x1ea)),
        show_national_sheet = @intFromEnum(lu16.init(0x1eb)),
        cmd_1ec = @intFromEnum(lu16.init(0x1ec)),
        store_trophy_pokemon = @intFromEnum(lu16.init(0x1ed)),
        cmd_1ef = @intFromEnum(lu16.init(0x1ef)),
        cmd_1f0 = @intFromEnum(lu16.init(0x1f0)),
        check_act_fossil = @intFromEnum(lu16.init(0x1f1)),
        cmd_1f2 = @intFromEnum(lu16.init(0x1f2)),
        cmd_1f3 = @intFromEnum(lu16.init(0x1f3)),
        check_item_chosen = @intFromEnum(lu16.init(0x1f4)),
        compare_item_poke_fossil = @intFromEnum(lu16.init(0x1f5)),
        check_pokemon_level = @intFromEnum(lu16.init(0x1f6)),
        check_is_pokemon_poisoned = @intFromEnum(lu16.init(0x1f7)),
        pre_wfc = @intFromEnum(lu16.init(0x1f8)),
        store_furniture = @intFromEnum(lu16.init(0x1f9)),
        copy_furniture = @intFromEnum(lu16.init(0x1fb)),
        set_b_castle_function_id = @intFromEnum(lu16.init(0x1fe)),
        b_castle_funct_return = @intFromEnum(lu16.init(0x1ff)),
        cmd_200 = @intFromEnum(lu16.init(0x200)),
        check_effect_hm = @intFromEnum(lu16.init(0x201)),
        great_marsh_function = @intFromEnum(lu16.init(0x202)),
        battle_poke_colosseum = @intFromEnum(lu16.init(0x203)),
        warp_last_elevator = @intFromEnum(lu16.init(0x204)),
        open_geo_net = @intFromEnum(lu16.init(0x205)),
        great_marsh_bynocule = @intFromEnum(lu16.init(0x206)),
        store_poke_colosseum_lost = @intFromEnum(lu16.init(0x207)),
        pokemon_picture = @intFromEnum(lu16.init(0x208)),
        hide_picture = @intFromEnum(lu16.init(0x209)),
        cmd_20a = @intFromEnum(lu16.init(0x20a)),
        cmd_20b = @intFromEnum(lu16.init(0x20b)),
        cmd_20c = @intFromEnum(lu16.init(0x20c)),
        setvar_mt_coronet = @intFromEnum(lu16.init(0x20d)),
        cmd_20e = @intFromEnum(lu16.init(0x20e)),
        check_quic_trine_coordinates = @intFromEnum(lu16.init(0x20f)),
        setvar_quick_train_coordinates = @intFromEnum(lu16.init(0x210)),
        move_train_anm = @intFromEnum(lu16.init(0x211)),
        store_poke_nature = @intFromEnum(lu16.init(0x212)),
        check_poke_nature = @intFromEnum(lu16.init(0x213)),
        random_hallowes = @intFromEnum(lu16.init(0x214)),
        start_amity = @intFromEnum(lu16.init(0x215)),
        cmd_216 = @intFromEnum(lu16.init(0x216)),
        cmd_217 = @intFromEnum(lu16.init(0x217)),
        chs_r_s_poke = @intFromEnum(lu16.init(0x218)),
        set_s_poke = @intFromEnum(lu16.init(0x219)),
        check_s_poke = @intFromEnum(lu16.init(0x21a)),
        cmd_21b = @intFromEnum(lu16.init(0x21b)),
        act_swarm_poke = @intFromEnum(lu16.init(0x21c)),
        cmd_21d = @intFromEnum(lu16.init(0x21d)),
        cmd_21e = @intFromEnum(lu16.init(0x21e)),
        check_move_remember = @intFromEnum(lu16.init(0x21f)),
        cmd_220 = @intFromEnum(lu16.init(0x220)),
        store_poke_remember = @intFromEnum(lu16.init(0x221)),
        cmd_222 = @intFromEnum(lu16.init(0x222)),
        store_remember_move = @intFromEnum(lu16.init(0x223)),
        teach_move = @intFromEnum(lu16.init(0x224)),
        check_teach_move = @intFromEnum(lu16.init(0x225)),
        set_trade_id = @intFromEnum(lu16.init(0x226)),
        check_pokemon_trade = @intFromEnum(lu16.init(0x228)),
        trade_chosen_pokemon = @intFromEnum(lu16.init(0x229)),
        stop_trade = @intFromEnum(lu16.init(0x22a)),
        cmd_22b = @intFromEnum(lu16.init(0x22b)),
        close_oak_assistant_event = @intFromEnum(lu16.init(0x22c)),
        check_nat_pokedex_status = @intFromEnum(lu16.init(0x22d)),
        check_ribbon_number = @intFromEnum(lu16.init(0x22f)),
        check_ribbon = @intFromEnum(lu16.init(0x230)),
        give_ribbon = @intFromEnum(lu16.init(0x231)),
        setvar_ribbon = @intFromEnum(lu16.init(0x232)),
        check_happy_ribbon = @intFromEnum(lu16.init(0x233)),
        check_pokemart = @intFromEnum(lu16.init(0x234)),
        check_furniture = @intFromEnum(lu16.init(0x235)),
        cmd_236 = @intFromEnum(lu16.init(0x236)),
        check_phrase_box_input = @intFromEnum(lu16.init(0x237)),
        check_status_phrase_box = @intFromEnum(lu16.init(0x238)),
        decide_rules = @intFromEnum(lu16.init(0x239)),
        check_foot_step = @intFromEnum(lu16.init(0x23a)),
        heal_pokemon_animation = @intFromEnum(lu16.init(0x23b)),
        store_elevator_direction = @intFromEnum(lu16.init(0x23c)),
        ship_animation = @intFromEnum(lu16.init(0x23d)),
        cmd_23e = @intFromEnum(lu16.init(0x23e)),
        store_phrase_box1_w = @intFromEnum(lu16.init(0x243)),
        store_phrase_box2_w = @intFromEnum(lu16.init(0x244)),
        setvar_phrase_box1_w = @intFromEnum(lu16.init(0x245)),
        store_mt_coronet = @intFromEnum(lu16.init(0x246)),
        check_first_poke_party = @intFromEnum(lu16.init(0x247)),
        check_poke_type = @intFromEnum(lu16.init(0x248)),
        check_phrase_box_input2 = @intFromEnum(lu16.init(0x249)),
        store_und_time = @intFromEnum(lu16.init(0x24a)),
        prepare_pc_animation = @intFromEnum(lu16.init(0x24b)),
        open_pc_animation = @intFromEnum(lu16.init(0x24c)),
        close_pc_animation = @intFromEnum(lu16.init(0x24d)),
        check_lotto_number = @intFromEnum(lu16.init(0x24e)),
        compare_lotto_number = @intFromEnum(lu16.init(0x24f)),
        setvar_id_poke_boxes = @intFromEnum(lu16.init(0x251)),
        cmd_250 = @intFromEnum(lu16.init(0x250)),
        check_boxes_number = @intFromEnum(lu16.init(0x252)),
        stop_great_marsh = @intFromEnum(lu16.init(0x253)),
        check_poke_catching_show = @intFromEnum(lu16.init(0x254)),
        close_catching_show = @intFromEnum(lu16.init(0x255)),
        check_catching_show_records = @intFromEnum(lu16.init(0x256)),
        sprt_save = @intFromEnum(lu16.init(0x257)),
        ret_sprt_save = @intFromEnum(lu16.init(0x258)),
        elev_lg_animation = @intFromEnum(lu16.init(0x259)),
        check_elev_lg_anm = @intFromEnum(lu16.init(0x25a)),
        elev_ir_anm = @intFromEnum(lu16.init(0x25b)),
        stop_elev_anm = @intFromEnum(lu16.init(0x25c)),
        check_elev_position = @intFromEnum(lu16.init(0x25d)),
        galact_anm = @intFromEnum(lu16.init(0x25e)),
        galact_anm2 = @intFromEnum(lu16.init(0x25f)),
        main_event = @intFromEnum(lu16.init(0x260)),
        check_accessories3 = @intFromEnum(lu16.init(0x261)),
        act_deoxis_form_change = @intFromEnum(lu16.init(0x262)),
        change_form_deoxis = @intFromEnum(lu16.init(0x263)),
        check_coombe_event = @intFromEnum(lu16.init(0x264)),
        act_contest_map = @intFromEnum(lu16.init(0x265)),
        cmd_266 = @intFromEnum(lu16.init(0x266)),
        pokecasino = @intFromEnum(lu16.init(0x267)),
        check_time2 = @intFromEnum(lu16.init(0x268)),
        regigigas_anm = @intFromEnum(lu16.init(0x269)),
        cresselia_anm = @intFromEnum(lu16.init(0x26a)),
        check_regi = @intFromEnum(lu16.init(0x26b)),
        check_massage = @intFromEnum(lu16.init(0x26c)),
        unown_message_box = @intFromEnum(lu16.init(0x26d)),
        check_p_catching_show = @intFromEnum(lu16.init(0x26e)),
        cmd_26f = @intFromEnum(lu16.init(0x26f)),
        shaymin_anm = @intFromEnum(lu16.init(0x270)),
        thank_name_insert = @intFromEnum(lu16.init(0x271)),
        setvar_shaymin = @intFromEnum(lu16.init(0x272)),
        setvar_accessories2 = @intFromEnum(lu16.init(0x273)),
        cmd_274 = @intFromEnum(lu16.init(0x274)),
        check_record_casino = @intFromEnum(lu16.init(0x275)),
        check_coins_casino = @intFromEnum(lu16.init(0x276)),
        srt_random_num = @intFromEnum(lu16.init(0x277)),
        check_poke_level2 = @intFromEnum(lu16.init(0x278)),
        cmd_279 = @intFromEnum(lu16.init(0x279)),
        league_castle_view = @intFromEnum(lu16.init(0x27a)),
        cmd_27b = @intFromEnum(lu16.init(0x27b)),
        setvar_amity_pokemon = @intFromEnum(lu16.init(0x27c)),
        cmd_27d = @intFromEnum(lu16.init(0x27d)),
        check_first_time_v_shop = @intFromEnum(lu16.init(0x27e)),
        cmd_27f = @intFromEnum(lu16.init(0x27f)),
        setvar_id_number = @intFromEnum(lu16.init(0x280)),
        cmd_281 = @intFromEnum(lu16.init(0x281)),
        setvar_unk = @intFromEnum(lu16.init(0x282)),
        cmd_283 = @intFromEnum(lu16.init(0x283)),
        check_ruin_maniac = @intFromEnum(lu16.init(0x284)),
        check_turn_back = @intFromEnum(lu16.init(0x285)),
        check_ug_people_num = @intFromEnum(lu16.init(0x286)),
        check_ug_fossil_num = @intFromEnum(lu16.init(0x287)),
        check_ug_traps_num = @intFromEnum(lu16.init(0x288)),
        check_poffin_item = @intFromEnum(lu16.init(0x289)),
        check_poffin_case_status = @intFromEnum(lu16.init(0x28a)),
        unk_funct2 = @intFromEnum(lu16.init(0x28b)),
        pokemon_party_picture = @intFromEnum(lu16.init(0x28c)),
        act_learning = @intFromEnum(lu16.init(0x28d)),
        set_sound_learning = @intFromEnum(lu16.init(0x28e)),
        check_first_time_champion = @intFromEnum(lu16.init(0x28f)),
        choose_poke_d_care = @intFromEnum(lu16.init(0x290)),
        store_poke_d_care = @intFromEnum(lu16.init(0x291)),
        cmd_292 = @intFromEnum(lu16.init(0x292)),
        check_master_rank = @intFromEnum(lu16.init(0x293)),
        show_battle_points_box = @intFromEnum(lu16.init(0x294)),
        hide_battle_points_box = @intFromEnum(lu16.init(0x295)),
        update_battle_points_box = @intFromEnum(lu16.init(0x296)),
        take_b_points = @intFromEnum(lu16.init(0x299)),
        check_b_points = @intFromEnum(lu16.init(0x29a)),
        cmd_29c = @intFromEnum(lu16.init(0x29c)),
        choice_multi = @intFromEnum(lu16.init(0x29d)),
        h_m_effect = @intFromEnum(lu16.init(0x29e)),
        camera_bump_effect = @intFromEnum(lu16.init(0x29f)),
        double_battle = @intFromEnum(lu16.init(0x2a0)),
        apply_movement2 = @intFromEnum(lu16.init(0x2a1)),
        cmd_2a2 = @intFromEnum(lu16.init(0x2a2)),
        store_act_hero_friend_code = @intFromEnum(lu16.init(0x2a3)),
        store_act_other_friend_code = @intFromEnum(lu16.init(0x2a4)),
        choose_trade_pokemon = @intFromEnum(lu16.init(0x2a5)),
        chs_prize_casino = @intFromEnum(lu16.init(0x2a6)),
        check_plate = @intFromEnum(lu16.init(0x2a7)),
        take_coins_casino = @intFromEnum(lu16.init(0x2a8)),
        check_coins_casino2 = @intFromEnum(lu16.init(0x2a9)),
        compare_phrase_box_input = @intFromEnum(lu16.init(0x2aa)),
        store_seal_num = @intFromEnum(lu16.init(0x2ab)),
        activate_mystery_gift = @intFromEnum(lu16.init(0x2ac)),
        check_follow_battle = @intFromEnum(lu16.init(0x2ad)),
        cmd_2af = @intFromEnum(lu16.init(0x2af)),
        cmd_2b0 = @intFromEnum(lu16.init(0x2b0)),
        cmd_2b1 = @intFromEnum(lu16.init(0x2b1)),
        cmd_2b2 = @intFromEnum(lu16.init(0x2b2)),
        setvar_seal_random = @intFromEnum(lu16.init(0x2b3)),
        darkrai_function = @intFromEnum(lu16.init(0x2b5)),
        cmd_2b6 = @intFromEnum(lu16.init(0x2b6)),
        store_poke_num_party = @intFromEnum(lu16.init(0x2b7)),
        store_poke_nickname = @intFromEnum(lu16.init(0x2b8)),
        close_multi_union = @intFromEnum(lu16.init(0x2b9)),
        check_battle_union = @intFromEnum(lu16.init(0x2ba)),
        cmd_2_b_b = @intFromEnum(lu16.init(0x2bb)),
        check_wild_battle2 = @intFromEnum(lu16.init(0x2bc)),
        wild_battle2 = @intFromEnum(lu16.init(0x2bd)),
        store_trainer_card_star = @intFromEnum(lu16.init(0x2be)),
        bike_ride = @intFromEnum(lu16.init(0x2bf)),
        cmd_2c0 = @intFromEnum(lu16.init(0x2c0)),
        show_save_box = @intFromEnum(lu16.init(0x2c1)),
        hide_save_box = @intFromEnum(lu16.init(0x2c2)),
        cmd_2c3 = @intFromEnum(lu16.init(0x2c3)),
        show_b_tower_some = @intFromEnum(lu16.init(0x2c4)),
        delete_saves_b_factory = @intFromEnum(lu16.init(0x2c5)),
        spin_trade_union = @intFromEnum(lu16.init(0x2c6)),
        check_version_game = @intFromEnum(lu16.init(0x2c7)),
        show_b_arcade_recors = @intFromEnum(lu16.init(0x2c8)),
        eterna_gym_anm = @intFromEnum(lu16.init(0x2c9)),
        floral_clock_animation = @intFromEnum(lu16.init(0x2ca)),
        check_poke_party2 = @intFromEnum(lu16.init(0x2cb)),
        check_poke_castle = @intFromEnum(lu16.init(0x2cc)),
        act_team_galactic_events = @intFromEnum(lu16.init(0x2cd)),
        choose_wire_poke_b_castle = @intFromEnum(lu16.init(0x2cf)),
        cmd_2d0 = @intFromEnum(lu16.init(0x2d0)),
        cmd_2d1 = @intFromEnum(lu16.init(0x2d1)),
        cmd_2d2 = @intFromEnum(lu16.init(0x2d2)),
        cmd_2d3 = @intFromEnum(lu16.init(0x2d3)),
        cmd_2d4 = @intFromEnum(lu16.init(0x2d4)),
        cmd_2d5 = @intFromEnum(lu16.init(0x2d5)),
        cmd_2d6 = @intFromEnum(lu16.init(0x2d6)),
        cmd_2d7 = @intFromEnum(lu16.init(0x2d7)),
        cmd_2d8 = @intFromEnum(lu16.init(0x2d8)),
        cmd_2d9 = @intFromEnum(lu16.init(0x2d9)),
        cmd_2da = @intFromEnum(lu16.init(0x2da)),
        cmd_2db = @intFromEnum(lu16.init(0x2db)),
        cmd_2dc = @intFromEnum(lu16.init(0x2dc)),
        cmd_2dd = @intFromEnum(lu16.init(0x2dd)),
        cmd_2de = @intFromEnum(lu16.init(0x2de)),
        cmd_2df = @intFromEnum(lu16.init(0x2df)),
        cmd_2e0 = @intFromEnum(lu16.init(0x2e0)),
        cmd_2e1 = @intFromEnum(lu16.init(0x2e1)),
        cmd_2e2 = @intFromEnum(lu16.init(0x2e2)),
        cmd_2e3 = @intFromEnum(lu16.init(0x2e3)),
        cmd_2e4 = @intFromEnum(lu16.init(0x2e4)),
        cmd_2e5 = @intFromEnum(lu16.init(0x2e5)),
        cmd_2e6 = @intFromEnum(lu16.init(0x2e6)),
        cmd_2e7 = @intFromEnum(lu16.init(0x2e7)),
        cmd_2e8 = @intFromEnum(lu16.init(0x2e8)),
        cmd_2e9 = @intFromEnum(lu16.init(0x2e9)),
        cmd_2ea = @intFromEnum(lu16.init(0x2ea)),
        cmd_2eb = @intFromEnum(lu16.init(0x2eb)),
        cmd_2ec = @intFromEnum(lu16.init(0x2ec)),
        cmd_2ed = @intFromEnum(lu16.init(0x2ed)),
        cmd_2ee = @intFromEnum(lu16.init(0x2ee)),
        cmd_2f0 = @intFromEnum(lu16.init(0x2f0)),
        cmd_2f2 = @intFromEnum(lu16.init(0x2f2)),
        cmd_2f3 = @intFromEnum(lu16.init(0x2f3)),
        cmd_2f4 = @intFromEnum(lu16.init(0x2f4)),
        cmd_2f5 = @intFromEnum(lu16.init(0x2f5)),
        cmd_2f6 = @intFromEnum(lu16.init(0x2f6)),
        cmd_2f7 = @intFromEnum(lu16.init(0x2f7)),
        cmd_2f8 = @intFromEnum(lu16.init(0x2f8)),
        cmd_2f9 = @intFromEnum(lu16.init(0x2f9)),
        cmd_2fa = @intFromEnum(lu16.init(0x2fa)),
        cmd_2fb = @intFromEnum(lu16.init(0x2fb)),
        cmd_2fc = @intFromEnum(lu16.init(0x2fc)),
        cmd_2fd = @intFromEnum(lu16.init(0x2fd)),
        cmd_2fe = @intFromEnum(lu16.init(0x2fe)),
        cmd_2ff = @intFromEnum(lu16.init(0x2ff)),
        cmd_300 = @intFromEnum(lu16.init(0x300)),
        cmd_302 = @intFromEnum(lu16.init(0x302)),
        cmd_303 = @intFromEnum(lu16.init(0x303)),
        cmd_304 = @intFromEnum(lu16.init(0x304)),
        cmd_305 = @intFromEnum(lu16.init(0x305)),
        cmd_306 = @intFromEnum(lu16.init(0x306)),
        cmd_307 = @intFromEnum(lu16.init(0x307)),
        cmd_308 = @intFromEnum(lu16.init(0x308)),
        cmd_309 = @intFromEnum(lu16.init(0x309)),
        cmd_30a = @intFromEnum(lu16.init(0x30a)),
        cmd_30b = @intFromEnum(lu16.init(0x30b)),
        cmd_30c = @intFromEnum(lu16.init(0x30c)),
        cmd_30d = @intFromEnum(lu16.init(0x30d)),
        cmd_30e = @intFromEnum(lu16.init(0x30e)),
        cmd_30f = @intFromEnum(lu16.init(0x30f)),
        cmd_310 = @intFromEnum(lu16.init(0x310)),
        cmd_311 = @intFromEnum(lu16.init(0x311)),
        cmd_312 = @intFromEnum(lu16.init(0x312)),
        cmd_313 = @intFromEnum(lu16.init(0x313)),
        cmd_314 = @intFromEnum(lu16.init(0x314)),
        cmd_315 = @intFromEnum(lu16.init(0x315)),
        cmd_316 = @intFromEnum(lu16.init(0x316)),
        cmd_317 = @intFromEnum(lu16.init(0x317)),
        wild_battle3 = @intFromEnum(lu16.init(0x318)),
        cmd_319 = @intFromEnum(lu16.init(0x319)),
        cmd_31a = @intFromEnum(lu16.init(0x31a)),
        cmd_31b = @intFromEnum(lu16.init(0x31b)),
        cmd_31c = @intFromEnum(lu16.init(0x31c)),
        cmd_31d = @intFromEnum(lu16.init(0x31d)),
        cmd_31e = @intFromEnum(lu16.init(0x31e)),
        cmd_31f = @intFromEnum(lu16.init(0x31f)),
        cmd_320 = @intFromEnum(lu16.init(0x320)),
        cmd_321 = @intFromEnum(lu16.init(0x321)),
        cmd_322 = @intFromEnum(lu16.init(0x322)),
        cmd_323 = @intFromEnum(lu16.init(0x323)),
        cmd_324 = @intFromEnum(lu16.init(0x324)),
        cmd_325 = @intFromEnum(lu16.init(0x325)),
        cmd_326 = @intFromEnum(lu16.init(0x326)),
        cmd_327 = @intFromEnum(lu16.init(0x327)),
        portal_effect = @intFromEnum(lu16.init(0x328)),
        cmd_329 = @intFromEnum(lu16.init(0x329)),
        cmd_32a = @intFromEnum(lu16.init(0x32a)),
        cmd_32b = @intFromEnum(lu16.init(0x32b)),
        cmd_32c = @intFromEnum(lu16.init(0x32c)),
        cmd_32d = @intFromEnum(lu16.init(0x32d)),
        cmd_32e = @intFromEnum(lu16.init(0x32e)),
        cmd_32f = @intFromEnum(lu16.init(0x32f)),
        cmd_330 = @intFromEnum(lu16.init(0x330)),
        cmd_331 = @intFromEnum(lu16.init(0x331)),
        cmd_332 = @intFromEnum(lu16.init(0x332)),
        cmd_333 = @intFromEnum(lu16.init(0x333)),
        cmd_334 = @intFromEnum(lu16.init(0x334)),
        cmd_335 = @intFromEnum(lu16.init(0x335)),
        cmd_336 = @intFromEnum(lu16.init(0x336)),
        cmd_337 = @intFromEnum(lu16.init(0x337)),
        cmd_338 = @intFromEnum(lu16.init(0x338)),
        cmd_339 = @intFromEnum(lu16.init(0x339)),
        cmd_33a = @intFromEnum(lu16.init(0x33a)),
        cmd_33c = @intFromEnum(lu16.init(0x33c)),
        cmd_33d = @intFromEnum(lu16.init(0x33d)),
        cmd_33e = @intFromEnum(lu16.init(0x33e)),
        cmd_33f = @intFromEnum(lu16.init(0x33f)),
        cmd_340 = @intFromEnum(lu16.init(0x340)),
        cmd_341 = @intFromEnum(lu16.init(0x341)),
        cmd_342 = @intFromEnum(lu16.init(0x342)),
        cmd_343 = @intFromEnum(lu16.init(0x343)),
        cmd_344 = @intFromEnum(lu16.init(0x344)),
        cmd_345 = @intFromEnum(lu16.init(0x345)),
        cmd_346 = @intFromEnum(lu16.init(0x346)),
        display_floor = @intFromEnum(lu16.init(0x347)),
    };
    pub const Arg0 = extern struct {
        kind: Kind align(1),
    };
    pub const Return2 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_a = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: u8 align(1),
    };
    pub const If = extern struct {
        kind: Kind align(1),
        @"var": lu16 align(1),
        nr: lu16 align(1),
    };
    pub const If2 = extern struct {
        kind: Kind align(1),
        @"var": lu16 align(1),
        nr: lu16 align(1),
    };
    pub const CallStandard = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Jump = extern struct {
        kind: Kind align(1),
        adr: li32 align(1),
    };
    pub const Call = extern struct {
        kind: Kind align(1),
        adr: li32 align(1),
    };
    pub const CompareLastResultJump = extern struct {
        kind: Kind align(1),
        cond: u8 align(1),
        adr: li32 align(1),
    };
    pub const CompareLastResultCall = extern struct {
        kind: Kind align(1),
        cond: u8 align(1),
        adr: li32 align(1),
    };
    pub const SetFlag = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const ClearFlag = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckFlag = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_21 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_22 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const SetTrainerId = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_24 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const ClearTrainerId = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const ScriptCmd_AddValue = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const ScriptCmd_SubValue = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const SetVar = extern struct {
        kind: Kind align(1),
        destination: lu16 align(1),
        value: lu16 align(1),
    };
    pub const CopyVar = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Message2 = extern struct {
        kind: Kind align(1),
        nr: u8 align(1),
    };
    pub const Message = extern struct {
        kind: Kind align(1),
        nr: u8 align(1),
    };
    pub const Message3 = extern struct {
        kind: Kind align(1),
        nr: lu16 align(1),
    };
    pub const Message4 = extern struct {
        kind: Kind align(1),
        nr: lu16 align(1),
    };
    pub const Message5 = extern struct {
        kind: Kind align(1),
        nr: u8 align(1),
    };
    pub const CallMessageBox = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: u8 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
    };
    pub const ColorMsgBox = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const TypeMessageBox = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const CallTextMsgBox = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const StoreMenuStatus = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const YesNoBox = extern struct {
        kind: Kind align(1),
        nr: lu16 align(1),
    };
    pub const Multi = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: u8 align(1),
        c: u8 align(1),
        d: u8 align(1),
        e: lu16 align(1),
    };
    pub const Multi2 = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: u8 align(1),
        c: u8 align(1),
        d: u8 align(1),
        e: lu16 align(1),
    };
    pub const Cmd_42 = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: u8 align(1),
    };
    pub const Multi3 = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: u8 align(1),
        c: u8 align(1),
        d: u8 align(1),
        e: lu16 align(1),
    };
    pub const Multi4 = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: u8 align(1),
        c: u8 align(1),
        d: u8 align(1),
        e: lu16 align(1),
    };
    pub const TxtMsgScrpMulti = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const PlayFanfare = extern struct {
        kind: Kind align(1),
        nr: lu16 align(1),
    };
    pub const MultiRow = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const PlayFanfare2 = extern struct {
        kind: Kind align(1),
        nr: lu16 align(1),
    };
    pub const WaitFanfare = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const PlayCry = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Soundfr = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const PlaySound = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Stop = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_53 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const SwitchMusic = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const StoreSayingLearned = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const PlaySound2 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_58 = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const CheckSayingLearned = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const SwithMusic2 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const ApplyMovement = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        adr: lu32 align(1),
    };
    pub const Lock = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Release = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const AddPeople = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const RemovePeople = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const LockCam = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const CheckSpritePosition = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const CheckPersonPosition = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const ContinueFollow = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: u8 align(1),
    };
    pub const FollowHero = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const TakeMoney = extern struct {
        kind: Kind align(1),
        a: lu32 align(1),
    };
    pub const CheckMoney = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu32 align(1),
    };
    pub const ShowMoney = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const ShowCoins = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const CheckCoins = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const GiveCoins = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const TakeCoins = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const TakeItem = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const GiveItem = extern struct {
        kind: Kind align(1),
        itemid: lu16 align(1),
        quantity: lu16 align(1),
        @"return": lu16 align(1),
    };
    pub const CheckStoreItem = extern struct {
        kind: Kind align(1),
        itemid: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const CheckItem = extern struct {
        kind: Kind align(1),
        itemid: lu16 align(1),
        quantity: lu16 align(1),
        @"return": lu16 align(1),
    };
    pub const StoreItemTaken = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const StoreItemType = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const SendItemType1 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const Cmd_84 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const CheckUndergroundPcStatus = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const Cmd_86 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const SendItemType2 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const Cmd_88 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const Cmd_89 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const Cmd_8a = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const Cmd_8b = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const Cmd_8c = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const Cmd_8d = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const Cmd_8e = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const SendItemType3 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const CheckPokemonParty = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const StorePokemonParty = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const SetPokemonPartyStored = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const GivePokemon = extern struct {
        kind: Kind align(1),
        species: lu16 align(1),
        level: lu16 align(1),
        item: lu16 align(1),
        res: lu16 align(1),
    };
    pub const GiveEgg = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const CheckMove = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const CheckPlaceStored = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_9b = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_a4 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const DressPokemon = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const DisplayDressedPokemon = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const DisplayContestPokemon = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const OpenPcFunction = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const StoreWfcStatus = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const StartWfc = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const BattleId = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const SetVarBattle = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const CheckBattleType = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const SetVarBattle2 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const ChoosePokeNick = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const FadeScreen = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
    };
    pub const Warp = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
        e: lu16 align(1),
    };
    pub const RockClimbAnimation = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const SurfAnimation = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const WaterfallAnimation = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const PrepHmEffect = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckBike = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const RideBike = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const RideBike2 = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const GivePokeHiroAnm = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const SetVarHero = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const SetVariableRival = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const SetVarAlter = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const SetVarPoke = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const SetVarItem = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const SetVarItemNum = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const SetVarAtkItem = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const SetVarAtk = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const SetVariableNumber = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const SetVarPokeNick = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const SetVarObj = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const SetVarTrainer = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const SetVarWiFiSprite = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const SetVarPokeStored = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
        d: u8 align(1),
    };
    pub const SetVarStrHero = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const SetVarStrRival = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const StoreStarter = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_df = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const SetVarItemStored = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const SetVarItemStored2 = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const SetVarSwarmPoke = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const CheckSwarmPoke = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const StartBattleAnalysis = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const TrainerBattle = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const EndtrainerBattle = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const TrainerBattleStored = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const TrainerBattleStored2 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const CheckTrainerStatus = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const StoreLeagueTrainer = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckTrainerLost = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckTrainerStatus2 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const StorePokePartyDefeated = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const ChsFriend = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
    };
    pub const WireBattleWait = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
    };
    pub const StartOvation = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const StopOvation = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_fa = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
    };
    pub const Cmd_fb = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_fc = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const SetvarOtherEntry = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_fe = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const SetvatHiroEntry = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const SetvarTypeContest = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const SetvarRankContest = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_104 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_105 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_106 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_107 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const StorePeopleIdContest = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_109 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const SetvatHiroEntry2 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const ActPeopleContest = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_10c = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_10d = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_10e = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_10f = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_110 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
    };
    pub const FlashContest = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_115 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const StorePokerus = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const WarpMapElevator = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
        e: lu16 align(1),
    };
    pub const CheckFloor = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const StartLift = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: u8 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
    };
    pub const StoreSinPokemonSeen = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_11f = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const StoreTotPokemonSeen = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const StoreNatPokemonSeen = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const SetVarTextPokedex = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const WildBattle = extern struct {
        kind: Kind align(1),
        species: lu16 align(1),
        level: lu16 align(1),
    };
    pub const StarterBattle = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const CheckIfHoneySlathered = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const StoreSaveData = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckSaveData = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckDress = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const CheckContestWin = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const StorePhotoName = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckPtchAppl = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const ActPktchAppl = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const StorePoketchApp = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const FriendBT = extern struct {
        kind: Kind align(1),
        nr: lu16 align(1),
    };
    pub const Cmd_138 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const OpenUnionFunction2 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const SetUnionFunctionId = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const SetVarUnionMessage = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const StoreYourDecisionUnion = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const StoreOtherDecisionUnion = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckOtherDecisionUnion = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const StoreYourDecisionUnion2 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const StoreOtherDecisionUnion2 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckOtherDecisionUnion2 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Pokemart = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Pokemart1 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Pokemart2 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Pokemart3 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const ActBike = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckGender = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const UndergroundId = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const StoreWiFiSprite = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const ActWiFiSprite = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_157 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckBadge = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const EnableBadge = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const DisableBadge = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckFollow = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_166 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const PrepareDoorAnimation = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
        e: u8 align(1),
    };
    pub const WaitAction = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const WaitClose = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const OpenDoor = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const CloseDoor = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const StorePDCareNum = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const SunishoreGymFunction = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const SunishoreGymFunction2 = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const CheckPartyNumber = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const OpenBerryPouch = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const Cmd_179 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_17a = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_17b = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const SetNaturePokemon = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_17d = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_17e = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_17f = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_180 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_181 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckDeoxis = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_183 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_184 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const ChangeOwPosition = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const SetOwPosition = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
        e: lu16 align(1),
    };
    pub const ChangeOwMovement = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const ReleaseOw = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const SetTilePassable = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const SetTileLocked = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const SetOwsFollow = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_18f = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const SetSaveData = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const StorePokeMenu2 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const ChsPokeContest = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
    };
    pub const StorePokeContest = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const ShowPokeInfo = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const StorePokeMove = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckPokeEgg = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const ComparePokeNick = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const CheckPartyNumberUnion = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckPokePartyHealth = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const CheckPokePartyNumDCare = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckEggUnion = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const UndergroundFunction = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const UndergroundFunction2 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const TakeMoneyDCare = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const TakePokemonDCare = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const SetVarPokeAndMoneyDCare = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const CheckMoneyDCare = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const SetVarPokeAndLevelDCare = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const SetVarPokeChosenDCare = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const GivePokeDCare = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const AddPeople2 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const RemovePeople2 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckMail = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const ShowRecordList = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckTime = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckIdPlayer = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const RandomTextStored = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const StoreHappyPoke = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const StoreHappyStatus = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const SetVarDataDayCare = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
    };
    pub const CheckFacePosition = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const StorePokeDCareLove = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckStatusSolaceonEvent = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckPokeParty = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const CopyPokemonHeight = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const SetVariablePokemonHeight = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const ComparePokemonHeight = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const CheckPokemonHeight = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const StorePokeDelete = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const StoreMoveDelete = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckMoveNumDelete = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const StoreDeleteMove = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const CheckDeleteMove = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const SetvarMoveDelete = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const DeActivateLeader = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
        e: lu16 align(1),
    };
    pub const HmFunctions = extern struct {
        kind: Kind align(1),
        a: extern union {
            kind: Kind2,
            @"1": extern struct {
                kind: Kind2 align(1),
            },
            @"2": extern struct {
                kind: Kind2 align(1),
                b: lu16 align(1),
            },
        },

        pub const Kind2 = enum(u8) {
            @"1" = 1,
            @"2" = 2,
        };
    };
    pub const FlashDuration = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const DefogDuration = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const GiveAccessories = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const CheckAccessories = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const Cmd_1d4 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const GiveAccessories2 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckAccessories2 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const BerryPoffin = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const SetVarBTowerChs = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const BattleRoomResult = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const StoreBTowerData = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const CallBTowerFunctions = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const RandomTeamBTower = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
    };
    pub const StorePrizeNumBTower = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const StorePeopleIdBTower = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CallBTowerWireFunction = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const StorePChosenWireBTower = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const StoreRankDataWireBTower = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_1e4 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const RandomEvent = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckSinnohPokedex = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckNationalPokedex = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const StoreTrophyPokemon = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_1ef = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_1f0 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckActFossil = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckItemChosen = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const CompareItemPokeFossil = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const CheckPokemonLevel = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const CheckIsPokemonPoisoned = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const StoreFurniture = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CopyFurniture = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const SetBCastleFunctionId = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const BCastleFunctReturn = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
        d: u8 align(1),
    };
    pub const Cmd_200 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckEffectHm = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const GreatMarshFunction = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const BattlePokeColosseum = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
        e: lu16 align(1),
    };
    pub const StorePokeColosseumLost = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const PokemonPicture = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_20a = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const SetvarMtCoronet = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const CheckQuicTrineCoordinates = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const SetvarQuickTrainCoordinates = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const MoveTrainAnm = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const StorePokeNature = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const CheckPokeNature = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const RandomHallowes = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_216 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_217 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const ChsRSPoke = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const SetSPoke = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckSPoke = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const ActSwarmPoke = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const Cmd_21d = extern struct {
        kind: Kind align(1),
        a: extern union {
            kind: Kind2,
            @"0": extern struct {
                kind: Kind2 align(1),
                b: lu16 align(1),
                c: lu16 align(1),
            },
            @"1": extern struct {
                kind: Kind2 align(1),
                b: lu16 align(1),
                c: lu16 align(1),
            },
            @"2": extern struct {
                kind: Kind2 align(1),
                b: lu16 align(1),
                c: lu16 align(1),
            },
            @"3": extern struct {
                kind: Kind2 align(1),
                b: lu16 align(1),
                c: lu16 align(1),
            },
            @"4": extern struct {
                kind: Kind2 align(1),
                b: lu16 align(1),
            },
            @"5": extern struct {
                kind: Kind2 align(1),
                b: lu16 align(1),
            },
        },

        pub const Kind2 = enum(u16) {
            @"0" = @intFromEnum(lu16.init(0)),
            @"1" = @intFromEnum(lu16.init(1)),
            @"2" = @intFromEnum(lu16.init(2)),
            @"3" = @intFromEnum(lu16.init(3)),
            @"4" = @intFromEnum(lu16.init(4)),
            @"5" = @intFromEnum(lu16.init(5)),
        };
    };
    pub const CheckMoveRemember = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const StorePokeRemember = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const StoreRememberMove = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const TeachMove = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const CheckTeachMove = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const SetTradeId = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const CheckPokemonTrade = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const TradeChosenPokemon = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckNatPokedexStatus = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const CheckRibbonNumber = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckRibbon = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const GiveRibbon = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const SetvarRibbon = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const CheckHappyRibbon = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const CheckPokemart = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckFurniture = extern struct {
        kind: Kind align(1),
        a: extern union {
            kind: Kind2,
            @"0": extern struct {
                kind: Kind2 align(1),
                b: lu16 align(1),
            },
            @"1": extern struct {
                kind: Kind2 align(1),
                b: lu16 align(1),
                c: lu16 align(1),
                d: lu16 align(1),
            },
            @"2": extern struct {
                kind: Kind2 align(1),
            },
            @"3": extern struct {
                kind: Kind2 align(1),
                b: lu16 align(1),
                c: lu16 align(1),
                d: lu16 align(1),
            },
            @"4": extern struct {
                kind: Kind2 align(1),
                b: lu16 align(1),
                c: lu16 align(1),
            },
            @"5": extern struct {
                kind: Kind2 align(1),
                b: lu16 align(1),
                c: lu16 align(1),
                d: lu16 align(1),
            },
            @"6": extern struct {
                kind: Kind2 align(1),
                b: lu16 align(1),
            },
        },

        pub const Kind2 = enum(u16) {
            @"0" = @intFromEnum(lu16.init(0)),
            @"1" = @intFromEnum(lu16.init(1)),
            @"2" = @intFromEnum(lu16.init(2)),
            @"3" = @intFromEnum(lu16.init(3)),
            @"4" = @intFromEnum(lu16.init(4)),
            @"5" = @intFromEnum(lu16.init(5)),
            @"6" = @intFromEnum(lu16.init(6)),
        };
    };
    pub const Cmd_236 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckPhraseBoxInput = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
    };
    pub const CheckStatusPhraseBox = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const DecideRules = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckFootStep = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const HealPokemonAnimation = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const StoreElevatorDirection = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const ShipAnimation = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: u8 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
        e: lu16 align(1),
    };
    pub const Cmd_23e = extern struct {
        kind: Kind align(1),
        a: extern union {
            kind: Kind2,
            @"1": extern struct {
                kind: Kind2 align(1),
                b: lu16 align(1),
            },
            @"2": extern struct {
                kind: Kind2 align(1),
                b: lu16 align(1),
            },
            @"3": extern struct {
                kind: Kind2 align(1),
                b: lu16 align(1),
            },
            @"5": extern struct {
                kind: Kind2 align(1),
                b: lu16 align(1),
                c: lu16 align(1),
            },
            @"6": extern struct {
                kind: Kind2 align(1),
                b: lu16 align(1),
                c: lu16 align(1),
            },
        },

        pub const Kind2 = enum(u16) {
            @"1" = @intFromEnum(lu16.init(1)),
            @"2" = @intFromEnum(lu16.init(2)),
            @"3" = @intFromEnum(lu16.init(3)),
            @"5" = @intFromEnum(lu16.init(5)),
            @"6" = @intFromEnum(lu16.init(6)),
        };
    };
    pub const StorePhraseBox1W = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const StorePhraseBox2W = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
    };
    pub const SetvarPhraseBox1W = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const StoreMtCoronet = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckFirstPokeParty = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckPokeType = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const CheckPhraseBoxInput2 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
        e: lu16 align(1),
    };
    pub const StoreUndTime = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const PreparePcAnimation = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const OpenPcAnimation = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const ClosePcAnimation = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const CheckLottoNumber = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CompareLottoNumber = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
    };
    pub const SetvarIdPokeBoxes = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const CheckBoxesNumber = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const StopGreatMarsh = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckPokeCatchingShow = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckCatchingShowRecords = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const CheckElevLgAnm = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckElevPosition = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const MainEvent = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckAccessories3 = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const ActDeoxisFormChange = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const ChangeFormDeoxis = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckCoombeEvent = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Pokecasino = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckTime2 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const RegigigasAnm = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
        e: lu16 align(1),
    };
    pub const CresseliaAnm = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const CheckRegi = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckMassage = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const UnownMessageBox = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckPCatchingShow = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const ShayminAnm = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: u8 align(1),
    };
    pub const ThankNameInsert = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const SetvarShaymin = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const SetvarAccessories2 = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_274 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu32 align(1),
    };
    pub const CheckRecordCasino = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckCoinsCasino = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const SrtRandomNum = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckPokeLevel2 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_279 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const SetvarAmityPokemon = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_27d = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const CheckFirstTimeVShop = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_27f = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const SetvarIdNumber = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
        c: u8 align(1),
        d: u8 align(1),
    };
    pub const Cmd_281 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const SetvarUnk = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_283 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const CheckRuinManiac = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckTurnBack = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const CheckUgPeopleNum = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckUgFossilNum = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckUgTrapsNum = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckPoffinItem = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
        e: lu16 align(1),
        f: lu16 align(1),
        g: lu16 align(1),
    };
    pub const CheckPoffinCaseStatus = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const UnkFunct2 = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const PokemonPartyPicture = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const SetSoundLearning = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckFirstTimeChampion = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const ChoosePokeDCare = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const StorePokeDCare = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_292 = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const CheckMasterRank = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const ShowBattlePointsBox = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: u8 align(1),
    };
    pub const TakeBPoints = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckBPoints = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_29c = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const ChoiceMulti = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const HMEffect = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const CameraBumpEffect = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const DoubleBattle = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const ApplyMovement2 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const Cmd_2a2 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const StoreActHeroFriendCode = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const StoreActOtherFriendCode = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const ChsPrizeCasino = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const CheckPlate = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const TakeCoinsCasino = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckCoinsCasino2 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const ComparePhraseBoxInput = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
        e: lu16 align(1),
    };
    pub const StoreSealNum = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckFollowBattle = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_2af = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const SetvarSealRandom = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const DarkraiFunction = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const Cmd_2b6 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: u8 align(1),
    };
    pub const StorePokeNumParty = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const StorePokeNickname = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckBattleUnion = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const CheckWildBattle2 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const StoreTrainerCardStar = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_2c0 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_2c3 = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const ShowBTowerSome = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const DeleteSavesBFactory = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const CheckVersionGame = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const ShowBArcadeRecors = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const CheckPokeParty2 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const CheckPokeCastle = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const ActTeamGalacticEvents = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const ChooseWirePokeBCastle = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_2d0 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_2d1 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_2d2 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const Cmd_2d3 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const Cmd_2d4 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const Cmd_2d5 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_2d7 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_2d8 = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const Cmd_2d9 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const Cmd_2da = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const Cmd_2db = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const Cmd_2dc = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_2dd = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_2de = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
        e: lu16 align(1),
    };
    pub const Cmd_2df = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_2e0 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_2e1 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_2e4 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const Cmd_2e5 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const Cmd_2e6 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const Cmd_2e7 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_2e8 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_2e9 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const Cmd_2ea = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_2eb = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_2ec = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: u8 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
    };
    pub const Cmd_2ee = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
    };
    pub const Cmd_2f3 = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_2f4 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
    };
    pub const Cmd_2f5 = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu32 align(1),
        c: u8 align(1),
        d: u8 align(1),
    };
    pub const Cmd_2f6 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const Cmd_2f7 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_2f9 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_2fa = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_2fc = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_2fd = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_2fe = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_2ff = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_302 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
        e: lu16 align(1),
    };
    pub const Cmd_303 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_304 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
    };
    pub const Cmd_305 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_306 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_307 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_308 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_30a = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_30d = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_30e = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_30f = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_311 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_312 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_313 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_314 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_315 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_317 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
    };
    pub const Cmd_319 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_31a = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_31b = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_31c = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_31d = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_31e = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_321 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_323 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_324 = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: u8 align(1),
        c: u8 align(1),
        d: u8 align(1),
        e: lu16 align(1),
        f: lu16 align(1),
    };
    pub const Cmd_325 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_326 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_327 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const PortalEffect = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_329 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
    };
    pub const Cmd_32a = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_32b = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_32c = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
    };
    pub const Cmd_32f = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_333 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_334 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_335 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu32 align(1),
    };
    pub const Cmd_336 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
    };
    pub const Cmd_337 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_33a = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const Cmd_33c = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_33d = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_33e = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_33f = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_340 = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_341 = extern struct {
        kind: Kind align(1),
        a: lu16 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_342 = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const Cmd_343 = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_344 = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_345 = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
    };
    pub const Cmd_346 = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const DisplayFloor = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: u8 align(1),
    };

    comptime {
        @setEvalBranchQuota(1000000);
        std.debug.assert(script.isPacked(@This()));
    }
};

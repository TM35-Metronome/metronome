const rom = @import("../rom.zig");
const script = @import("../script.zig");

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
    return @bytesToSlice(li32, data[0 .. len * 4]);
}

pub const CommandDecoder = script.CommandDecoder(Command, struct {
    fn isEnd(cmd: Command) bool {
        switch (cmd.tag) {
            Command.Kind.End,
            Command.Kind.Return,
            Command.Kind.Return2,
            Command.Kind.Jump,
            => return true,
            else => return false,
        }
    }
}.isEnd);

// These commands are only valid in dia/pearl/plat
pub const Command = packed struct {
    tag: Kind,
    data: extern union {
        Nop0: Nop0,
        Nop1: Nop1,
        End: End,
        Return2: Return2,
        Cmd_a: Cmd_a,
        If: If,
        If2: If2,
        CallStandard: CallStandard,
        ExitStandard: ExitStandard,
        Jump: Jump,
        Call: Call,
        Return: Return,
        CompareLastResultJump: CompareLastResultJump,
        CompareLastResultCall: CompareLastResultCall,
        SetFlag: SetFlag,
        ClearFlag: ClearFlag,
        CheckFlag: CheckFlag,
        Cmd_21: Cmd_21,
        Cmd_22: Cmd_22,
        SetTrainerId: SetTrainerId,
        Cmd_24: Cmd_24,
        ClearTrainerId: ClearTrainerId,
        ScriptCmd_AddValue: ScriptCmd_AddValue,
        ScriptCmd_SubValue: ScriptCmd_SubValue,
        SetVar: SetVar,
        CopyVar: CopyVar,
        Message2: Message2,
        Message: Message,
        Message3: Message3,
        Message4: Message4,
        Message5: Message5,
        Cmd_30: Cmd_30,
        WaitButton: WaitButton,
        Cmd_32: Cmd_32,
        Cmd_33: Cmd_33,
        CloseMsgOnKeyPress: CloseMsgOnKeyPress,
        FreezeMessageBox: FreezeMessageBox,
        CallMessageBox: CallMessageBox,
        ColorMsgBox: ColorMsgBox,
        TypeMessageBox: TypeMessageBox,
        NoMapMessageBox: NoMapMessageBox,
        CallTextMsgBox: CallTextMsgBox,
        StoreMenuStatus: StoreMenuStatus,
        ShowMenu: ShowMenu,
        YesNoBox: YesNoBox,
        Multi: Multi,
        Multi2: Multi2,
        Cmd_42: Cmd_42,
        CloseMulti: CloseMulti,
        Multi3: Multi3,
        Multi4: Multi4,
        TxtMsgScrpMulti: TxtMsgScrpMulti,
        CloseMulti4: CloseMulti4,
        PlayFanfare: PlayFanfare,
        MultiRow: MultiRow,
        PlayFanfare2: PlayFanfare2,
        WaitFanfare: WaitFanfare,
        PlayCry: PlayCry,
        WaitCry: WaitCry,
        Soundfr: Soundfr,
        Cmd_4f: Cmd_4f,
        PlaySound: PlaySound,
        Stop: Stop,
        Restart: Restart,
        Cmd_53: Cmd_53,
        SwitchMusic: SwitchMusic,
        StoreSayingLearned: StoreSayingLearned,
        PlaySound2: PlaySound2,
        Cmd_58: Cmd_58,
        CheckSayingLearned: CheckSayingLearned,
        SwithMusic2: SwithMusic2,
        ActMicrophone: ActMicrophone,
        DeactMicrophone: DeactMicrophone,
        Cmd_5d: Cmd_5d,
        ApplyMovement: ApplyMovement,
        WaitMovement: WaitMovement,
        LockAll: LockAll,
        ReleaseAll: ReleaseAll,
        Lock: Lock,
        Release: Release,
        AddPeople: AddPeople,
        RemovePeople: RemovePeople,
        LockCam: LockCam,
        ZoomCam: ZoomCam,
        FacePlayer: FacePlayer,
        CheckSpritePosition: CheckSpritePosition,
        CheckPersonPosition: CheckPersonPosition,
        ContinueFollow: ContinueFollow,
        FollowHero: FollowHero,
        TakeMoney: TakeMoney,
        CheckMoney: CheckMoney,
        ShowMoney: ShowMoney,
        HideMoney: HideMoney,
        UpdateMoney: UpdateMoney,
        ShowCoins: ShowCoins,
        HideCoins: HideCoins,
        UpdateCoins: UpdateCoins,
        CheckCoins: CheckCoins,
        GiveCoins: GiveCoins,
        TakeCoins: TakeCoins,
        TakeItem: TakeItem,
        GiveItem: GiveItem,
        CheckStoreItem: CheckStoreItem,
        CheckItem: CheckItem,
        StoreItemTaken: StoreItemTaken,
        StoreItemType: StoreItemType,
        SendItemType1: SendItemType1,
        Cmd_84: Cmd_84,
        CheckUndergroundPcStatus: CheckUndergroundPcStatus,
        Cmd_86: Cmd_86,
        SendItemType2: SendItemType2,
        Cmd_88: Cmd_88,
        Cmd_89: Cmd_89,
        Cmd_8a: Cmd_8a,
        Cmd_8b: Cmd_8b,
        Cmd_8c: Cmd_8c,
        Cmd_8d: Cmd_8d,
        Cmd_8e: Cmd_8e,
        SendItemType3: SendItemType3,
        CheckPokemonParty: CheckPokemonParty,
        StorePokemonParty: StorePokemonParty,
        SetPokemonPartyStored: SetPokemonPartyStored,
        GivePokemon: GivePokemon,
        GiveEgg: GiveEgg,
        CheckMove: CheckMove,
        CheckPlaceStored: CheckPlaceStored,
        Cmd_9b: Cmd_9b,
        Cmd_9c: Cmd_9c,
        Cmd_9d: Cmd_9d,
        Cmd_9e: Cmd_9e,
        Cmd_9f: Cmd_9f,
        Cmd_a0: Cmd_a0,
        CallEnd: CallEnd,
        Cmd_A2: Cmd_A2,
        Wfc_: Wfc_,
        Cmd_a4: Cmd_a4,
        Interview: Interview,
        DressPokemon: DressPokemon,
        DisplayDressedPokemon: DisplayDressedPokemon,
        DisplayContestPokemon: DisplayContestPokemon,
        OpenBallCapsule: OpenBallCapsule,
        OpenSinnohMaps: OpenSinnohMaps,
        OpenPcFunction: OpenPcFunction,
        DrawUnion: DrawUnion,
        TrainerCaseUnion: TrainerCaseUnion,
        TradeUnion: TradeUnion,
        RecordMixingUnion: RecordMixingUnion,
        EndGame: EndGame,
        HallFameAnm: HallFameAnm,
        StoreWfcStatus: StoreWfcStatus,
        StartWfc: StartWfc,
        ChooseStarter: ChooseStarter,
        BattleStarter: BattleStarter,
        BattleId: BattleId,
        SetVarBattle: SetVarBattle,
        CheckBattleType: CheckBattleType,
        SetVarBattle2: SetVarBattle2,
        ChoosePokeNick: ChoosePokeNick,
        FadeScreen: FadeScreen,
        ResetScreen: ResetScreen,
        Warp: Warp,
        RockClimbAnimation: RockClimbAnimation,
        SurfAnimation: SurfAnimation,
        WaterfallAnimation: WaterfallAnimation,
        FlashAnimation: FlashAnimation,
        DefogAnimation: DefogAnimation,
        PrepHmEffect: PrepHmEffect,
        Tuxedo: Tuxedo,
        CheckBike: CheckBike,
        RideBike: RideBike,
        RideBike2: RideBike2,
        GivePokeHiroAnm: GivePokeHiroAnm,
        StopGivePokeHiroAnm: StopGivePokeHiroAnm,
        SetVarHero: SetVarHero,
        SetVariableRival: SetVariableRival,
        SetVarAlter: SetVarAlter,
        SetVarPoke: SetVarPoke,
        SetVarItem: SetVarItem,
        SetVarItemNum: SetVarItemNum,
        SetVarAtkItem: SetVarAtkItem,
        SetVarAtk: SetVarAtk,
        SetVariableNumber: SetVariableNumber,
        SetVarPokeNick: SetVarPokeNick,
        SetVarObj: SetVarObj,
        SetVarTrainer: SetVarTrainer,
        SetVarWiFiSprite: SetVarWiFiSprite,
        SetVarPokeStored: SetVarPokeStored,
        SetVarStrHero: SetVarStrHero,
        SetVarStrRival: SetVarStrRival,
        StoreStarter: StoreStarter,
        Cmd_df: Cmd_df,
        SetVarItemStored: SetVarItemStored,
        SetVarItemStored2: SetVarItemStored2,
        SetVarSwarmPoke: SetVarSwarmPoke,
        CheckSwarmPoke: CheckSwarmPoke,
        StartBattleAnalysis: StartBattleAnalysis,
        TrainerBattle: TrainerBattle,
        EndtrainerBattle: EndtrainerBattle,
        TrainerBattleStored: TrainerBattleStored,
        TrainerBattleStored2: TrainerBattleStored2,
        CheckTrainerStatus: CheckTrainerStatus,
        StoreLeagueTrainer: StoreLeagueTrainer,
        LostGoPc: LostGoPc,
        CheckTrainerLost: CheckTrainerLost,
        CheckTrainerStatus2: CheckTrainerStatus2,
        StorePokePartyDefeated: StorePokePartyDefeated,
        ChsFriend: ChsFriend,
        WireBattleWait: WireBattleWait,
        Cmd_f6: Cmd_f6,
        Pokecontest: Pokecontest,
        StartOvation: StartOvation,
        StopOvation: StopOvation,
        Cmd_fa: Cmd_fa,
        Cmd_fb: Cmd_fb,
        Cmd_fc: Cmd_fc,
        SetvarOtherEntry: SetvarOtherEntry,
        Cmd_fe: Cmd_fe,
        SetvatHiroEntry: SetvatHiroEntry,
        Cmd_100: Cmd_100,
        BlackFlashEffect: BlackFlashEffect,
        SetvarTypeContest: SetvarTypeContest,
        SetvarRankContest: SetvarRankContest,
        Cmd_104: Cmd_104,
        Cmd_105: Cmd_105,
        Cmd_106: Cmd_106,
        Cmd_107: Cmd_107,
        StorePeopleIdContest: StorePeopleIdContest,
        Cmd_109: Cmd_109,
        SetvatHiroEntry2: SetvatHiroEntry2,
        ActPeopleContest: ActPeopleContest,
        Cmd_10c: Cmd_10c,
        Cmd_10d: Cmd_10d,
        Cmd_10e: Cmd_10e,
        Cmd_10f: Cmd_10f,
        Cmd_110: Cmd_110,
        FlashContest: FlashContest,
        EndFlash: EndFlash,
        CarpetAnm: CarpetAnm,
        Cmd_114: Cmd_114,
        Cmd_115: Cmd_115,
        ShowLnkCntRecord: ShowLnkCntRecord,
        Cmd_117: Cmd_117,
        Cmd_118: Cmd_118,
        StorePokerus: StorePokerus,
        WarpMapElevator: WarpMapElevator,
        CheckFloor: CheckFloor,
        StartLift: StartLift,
        StoreSinPokemonSeen: StoreSinPokemonSeen,
        Cmd_11f: Cmd_11f,
        StoreTotPokemonSeen: StoreTotPokemonSeen,
        StoreNatPokemonSeen: StoreNatPokemonSeen,
        SetVarTextPokedex: SetVarTextPokedex,
        WildBattle: WildBattle,
        StarterBattle: StarterBattle,
        ExplanationBattle: ExplanationBattle,
        HoneyTreeBattle: HoneyTreeBattle,
        CheckIfHoneySlathered: CheckIfHoneySlathered,
        RandomBattle: RandomBattle,
        StopRandomBattle: StopRandomBattle,
        WriteAutograph: WriteAutograph,
        StoreSaveData: StoreSaveData,
        CheckSaveData: CheckSaveData,
        CheckDress: CheckDress,
        CheckContestWin: CheckContestWin,
        StorePhotoName: StorePhotoName,
        GivePoketch: GivePoketch,
        CheckPtchAppl: CheckPtchAppl,
        ActPktchAppl: ActPktchAppl,
        StorePoketchApp: StorePoketchApp,
        FriendBT: FriendBT,
        FriendBT2: FriendBT2,
        Cmd_138: Cmd_138,
        OpenUnionFunction2: OpenUnionFunction2,
        StartUnion: StartUnion,
        LinkClosed: LinkClosed,
        SetUnionFunctionId: SetUnionFunctionId,
        CloseUnionFunction: CloseUnionFunction,
        CloseUnionFunction2: CloseUnionFunction2,
        SetVarUnionMessage: SetVarUnionMessage,
        StoreYourDecisionUnion: StoreYourDecisionUnion,
        StoreOtherDecisionUnion: StoreOtherDecisionUnion,
        Cmd_142: Cmd_142,
        CheckOtherDecisionUnion: CheckOtherDecisionUnion,
        StoreYourDecisionUnion2: StoreYourDecisionUnion2,
        StoreOtherDecisionUnion2: StoreOtherDecisionUnion2,
        CheckOtherDecisionUnion2: CheckOtherDecisionUnion2,
        Pokemart: Pokemart,
        Pokemart1: Pokemart1,
        Pokemart2: Pokemart2,
        Pokemart3: Pokemart3,
        DefeatGoPokecenter: DefeatGoPokecenter,
        ActBike: ActBike,
        CheckGender: CheckGender,
        HealPokemon: HealPokemon,
        DeactWireless: DeactWireless,
        DeleteEntry: DeleteEntry,
        Cmd_151: Cmd_151,
        UndergroundId: UndergroundId,
        UnionRoom: UnionRoom,
        OpenWiFiSprite: OpenWiFiSprite,
        StoreWiFiSprite: StoreWiFiSprite,
        ActWiFiSprite: ActWiFiSprite,
        Cmd_157: Cmd_157,
        ActivatePokedex: ActivatePokedex,
        GiveRunningShoes: GiveRunningShoes,
        CheckBadge: CheckBadge,
        EnableBadge: EnableBadge,
        DisableBadge: DisableBadge,
        CheckFollow: CheckFollow,
        StartFollow: StartFollow,
        StopFollow: StopFollow,
        Cmd_164: Cmd_164,
        Cmd_166: Cmd_166,
        PrepareDoorAnimation: PrepareDoorAnimation,
        WaitAction: WaitAction,
        WaitClose: WaitClose,
        OpenDoor: OpenDoor,
        CloseDoor: CloseDoor,
        ActDcareFunction: ActDcareFunction,
        StorePDCareNum: StorePDCareNum,
        PastoriaCityFunction: PastoriaCityFunction,
        PastoriaCityFunction2: PastoriaCityFunction2,
        HearthromeGymFunction: HearthromeGymFunction,
        HearthromeGymFunction2: HearthromeGymFunction2,
        CanalaveGymFunction: CanalaveGymFunction,
        VeilstoneGymFunction: VeilstoneGymFunction,
        SunishoreGymFunction: SunishoreGymFunction,
        SunishoreGymFunction2: SunishoreGymFunction2,
        CheckPartyNumber: CheckPartyNumber,
        OpenBerryPouch: OpenBerryPouch,
        Cmd_179: Cmd_179,
        Cmd_17a: Cmd_17a,
        Cmd_17b: Cmd_17b,
        SetNaturePokemon: SetNaturePokemon,
        Cmd_17d: Cmd_17d,
        Cmd_17e: Cmd_17e,
        Cmd_17f: Cmd_17f,
        Cmd_180: Cmd_180,
        Cmd_181: Cmd_181,
        CheckDeoxis: CheckDeoxis,
        Cmd_183: Cmd_183,
        Cmd_184: Cmd_184,
        Cmd_185: Cmd_185,
        ChangeOwPosition: ChangeOwPosition,
        SetOwPosition: SetOwPosition,
        ChangeOwMovement: ChangeOwMovement,
        ReleaseOw: ReleaseOw,
        SetTilePassable: SetTilePassable,
        SetTileLocked: SetTileLocked,
        SetOwsFollow: SetOwsFollow,
        ShowClockSave: ShowClockSave,
        HideClockSave: HideClockSave,
        Cmd_18f: Cmd_18f,
        SetSaveData: SetSaveData,
        ChsPokemenu: ChsPokemenu,
        ChsPokemenu2: ChsPokemenu2,
        StorePokeMenu2: StorePokeMenu2,
        ChsPokeContest: ChsPokeContest,
        StorePokeContest: StorePokeContest,
        ShowPokeInfo: ShowPokeInfo,
        StorePokeMove: StorePokeMove,
        CheckPokeEgg: CheckPokeEgg,
        ComparePokeNick: ComparePokeNick,
        CheckPartyNumberUnion: CheckPartyNumberUnion,
        CheckPokePartyHealth: CheckPokePartyHealth,
        CheckPokePartyNumDCare: CheckPokePartyNumDCare,
        CheckEggUnion: CheckEggUnion,
        UndergroundFunction: UndergroundFunction,
        UndergroundFunction2: UndergroundFunction2,
        UndergroundStart: UndergroundStart,
        TakeMoneyDCare: TakeMoneyDCare,
        TakePokemonDCare: TakePokemonDCare,
        ActEggDayCMan: ActEggDayCMan,
        DeactEggDayCMan: DeactEggDayCMan,
        SetVarPokeAndMoneyDCare: SetVarPokeAndMoneyDCare,
        CheckMoneyDCare: CheckMoneyDCare,
        EggAnimation: EggAnimation,
        SetVarPokeAndLevelDCare: SetVarPokeAndLevelDCare,
        SetVarPokeChosenDCare: SetVarPokeChosenDCare,
        GivePokeDCare: GivePokeDCare,
        AddPeople2: AddPeople2,
        RemovePeople2: RemovePeople2,
        MailBox: MailBox,
        CheckMail: CheckMail,
        ShowRecordList: ShowRecordList,
        CheckTime: CheckTime,
        CheckIdPlayer: CheckIdPlayer,
        RandomTextStored: RandomTextStored,
        StoreHappyPoke: StoreHappyPoke,
        StoreHappyStatus: StoreHappyStatus,
        SetVarDataDayCare: SetVarDataDayCare,
        CheckFacePosition: CheckFacePosition,
        StorePokeDCareLove: StorePokeDCareLove,
        CheckStatusSolaceonEvent: CheckStatusSolaceonEvent,
        CheckPokeParty: CheckPokeParty,
        CopyPokemonHeight: CopyPokemonHeight,
        SetVariablePokemonHeight: SetVariablePokemonHeight,
        ComparePokemonHeight: ComparePokemonHeight,
        CheckPokemonHeight: CheckPokemonHeight,
        ShowMoveInfo: ShowMoveInfo,
        StorePokeDelete: StorePokeDelete,
        StoreMoveDelete: StoreMoveDelete,
        CheckMoveNumDelete: CheckMoveNumDelete,
        StoreDeleteMove: StoreDeleteMove,
        CheckDeleteMove: CheckDeleteMove,
        SetvarMoveDelete: SetvarMoveDelete,
        Cmd_1cc: Cmd_1cc,
        DeActivateLeader: DeActivateLeader,
        HmFunctions: HmFunctions,
        FlashDuration: FlashDuration,
        DefogDuration: DefogDuration,
        GiveAccessories: GiveAccessories,
        CheckAccessories: CheckAccessories,
        Cmd_1d4: Cmd_1d4,
        GiveAccessories2: GiveAccessories2,
        CheckAccessories2: CheckAccessories2,
        BerryPoffin: BerryPoffin,
        SetVarBTowerChs: SetVarBTowerChs,
        BattleRoomResult: BattleRoomResult,
        ActivateBTower: ActivateBTower,
        StoreBTowerData: StoreBTowerData,
        CloseBTower: CloseBTower,
        CallBTowerFunctions: CallBTowerFunctions,
        RandomTeamBTower: RandomTeamBTower,
        StorePrizeNumBTower: StorePrizeNumBTower,
        StorePeopleIdBTower: StorePeopleIdBTower,
        CallBTowerWireFunction: CallBTowerWireFunction,
        StorePChosenWireBTower: StorePChosenWireBTower,
        StoreRankDataWireBTower: StoreRankDataWireBTower,
        Cmd_1e4: Cmd_1e4,
        RandomEvent: RandomEvent,
        CheckSinnohPokedex: CheckSinnohPokedex,
        CheckNationalPokedex: CheckNationalPokedex,
        ShowSinnohSheet: ShowSinnohSheet,
        ShowNationalSheet: ShowNationalSheet,
        Cmd_1ec: Cmd_1ec,
        StoreTrophyPokemon: StoreTrophyPokemon,
        Cmd_1ef: Cmd_1ef,
        Cmd_1f0: Cmd_1f0,
        CheckActFossil: CheckActFossil,
        Cmd_1f2: Cmd_1f2,
        Cmd_1f3: Cmd_1f3,
        CheckItemChosen: CheckItemChosen,
        CompareItemPokeFossil: CompareItemPokeFossil,
        CheckPokemonLevel: CheckPokemonLevel,
        CheckIsPokemonPoisoned: CheckIsPokemonPoisoned,
        PreWfc: PreWfc,
        StoreFurniture: StoreFurniture,
        CopyFurniture: CopyFurniture,
        SetBCastleFunctionId: SetBCastleFunctionId,
        BCastleFunctReturn: BCastleFunctReturn,
        Cmd_200: Cmd_200,
        CheckEffectHm: CheckEffectHm,
        GreatMarshFunction: GreatMarshFunction,
        BattlePokeColosseum: BattlePokeColosseum,
        WarpLastElevator: WarpLastElevator,
        OpenGeoNet: OpenGeoNet,
        GreatMarshBynocule: GreatMarshBynocule,
        StorePokeColosseumLost: StorePokeColosseumLost,
        PokemonPicture: PokemonPicture,
        HidePicture: HidePicture,
        Cmd_20a: Cmd_20a,
        Cmd_20b: Cmd_20b,
        Cmd_20c: Cmd_20c,
        SetvarMtCoronet: SetvarMtCoronet,
        Cmd_20e: Cmd_20e,
        CheckQuicTrineCoordinates: CheckQuicTrineCoordinates,
        SetvarQuickTrainCoordinates: SetvarQuickTrainCoordinates,
        MoveTrainAnm: MoveTrainAnm,
        StorePokeNature: StorePokeNature,
        CheckPokeNature: CheckPokeNature,
        RandomHallowes: RandomHallowes,
        StartAmity: StartAmity,
        Cmd_216: Cmd_216,
        Cmd_217: Cmd_217,
        ChsRSPoke: ChsRSPoke,
        SetSPoke: SetSPoke,
        CheckSPoke: CheckSPoke,
        Cmd_21b: Cmd_21b,
        ActSwarmPoke: ActSwarmPoke,
        Cmd_21d: Cmd_21d,
        Cmd_21e: Cmd_21e,
        CheckMoveRemember: CheckMoveRemember,
        Cmd_220: Cmd_220,
        StorePokeRemember: StorePokeRemember,
        Cmd_222: Cmd_222,
        StoreRememberMove: StoreRememberMove,
        TeachMove: TeachMove,
        CheckTeachMove: CheckTeachMove,
        SetTradeId: SetTradeId,
        CheckPokemonTrade: CheckPokemonTrade,
        TradeChosenPokemon: TradeChosenPokemon,
        StopTrade: StopTrade,
        Cmd_22b: Cmd_22b,
        CloseOakAssistantEvent: CloseOakAssistantEvent,
        CheckNatPokedexStatus: CheckNatPokedexStatus,
        CheckRibbonNumber: CheckRibbonNumber,
        CheckRibbon: CheckRibbon,
        GiveRibbon: GiveRibbon,
        SetvarRibbon: SetvarRibbon,
        CheckHappyRibbon: CheckHappyRibbon,
        CheckPokemart: CheckPokemart,
        CheckFurniture: CheckFurniture,
        Cmd_236: Cmd_236,
        CheckPhraseBoxInput: CheckPhraseBoxInput,
        CheckStatusPhraseBox: CheckStatusPhraseBox,
        DecideRules: DecideRules,
        CheckFootStep: CheckFootStep,
        HealPokemonAnimation: HealPokemonAnimation,
        StoreElevatorDirection: StoreElevatorDirection,
        ShipAnimation: ShipAnimation,
        Cmd_23e: Cmd_23e,
        StorePhraseBox1W: StorePhraseBox1W,
        StorePhraseBox2W: StorePhraseBox2W,
        SetvarPhraseBox1W: SetvarPhraseBox1W,
        StoreMtCoronet: StoreMtCoronet,
        CheckFirstPokeParty: CheckFirstPokeParty,
        CheckPokeType: CheckPokeType,
        CheckPhraseBoxInput2: CheckPhraseBoxInput2,
        StoreUndTime: StoreUndTime,
        PreparePcAnimation: PreparePcAnimation,
        OpenPcAnimation: OpenPcAnimation,
        ClosePcAnimation: ClosePcAnimation,
        CheckLottoNumber: CheckLottoNumber,
        CompareLottoNumber: CompareLottoNumber,
        SetvarIdPokeBoxes: SetvarIdPokeBoxes,
        Cmd_250: Cmd_250,
        CheckBoxesNumber: CheckBoxesNumber,
        StopGreatMarsh: StopGreatMarsh,
        CheckPokeCatchingShow: CheckPokeCatchingShow,
        CloseCatchingShow: CloseCatchingShow,
        CheckCatchingShowRecords: CheckCatchingShowRecords,
        SprtSave: SprtSave,
        RetSprtSave: RetSprtSave,
        ElevLgAnimation: ElevLgAnimation,
        CheckElevLgAnm: CheckElevLgAnm,
        ElevIrAnm: ElevIrAnm,
        StopElevAnm: StopElevAnm,
        CheckElevPosition: CheckElevPosition,
        GalactAnm: GalactAnm,
        GalactAnm2: GalactAnm2,
        MainEvent: MainEvent,
        CheckAccessories3: CheckAccessories3,
        ActDeoxisFormChange: ActDeoxisFormChange,
        ChangeFormDeoxis: ChangeFormDeoxis,
        CheckCoombeEvent: CheckCoombeEvent,
        ActContestMap: ActContestMap,
        Cmd_266: Cmd_266,
        Pokecasino: Pokecasino,
        CheckTime2: CheckTime2,
        RegigigasAnm: RegigigasAnm,
        CresseliaAnm: CresseliaAnm,
        CheckRegi: CheckRegi,
        CheckMassage: CheckMassage,
        UnownMessageBox: UnownMessageBox,
        CheckPCatchingShow: CheckPCatchingShow,
        Cmd_26f: Cmd_26f,
        ShayminAnm: ShayminAnm,
        ThankNameInsert: ThankNameInsert,
        SetvarShaymin: SetvarShaymin,
        SetvarAccessories2: SetvarAccessories2,
        Cmd_274: Cmd_274,
        CheckRecordCasino: CheckRecordCasino,
        CheckCoinsCasino: CheckCoinsCasino,
        SrtRandomNum: SrtRandomNum,
        CheckPokeLevel2: CheckPokeLevel2,
        Cmd_279: Cmd_279,
        LeagueCastleView: LeagueCastleView,
        Cmd_27b: Cmd_27b,
        SetvarAmityPokemon: SetvarAmityPokemon,
        Cmd_27d: Cmd_27d,
        CheckFirstTimeVShop: CheckFirstTimeVShop,
        Cmd_27f: Cmd_27f,
        SetvarIdNumber: SetvarIdNumber,
        Cmd_281: Cmd_281,
        SetvarUnk: SetvarUnk,
        Cmd_283: Cmd_283,
        CheckRuinManiac: CheckRuinManiac,
        CheckTurnBack: CheckTurnBack,
        CheckUgPeopleNum: CheckUgPeopleNum,
        CheckUgFossilNum: CheckUgFossilNum,
        CheckUgTrapsNum: CheckUgTrapsNum,
        CheckPoffinItem: CheckPoffinItem,
        CheckPoffinCaseStatus: CheckPoffinCaseStatus,
        UnkFunct2: UnkFunct2,
        PokemonPartyPicture: PokemonPartyPicture,
        ActLearning: ActLearning,
        SetSoundLearning: SetSoundLearning,
        CheckFirstTimeChampion: CheckFirstTimeChampion,
        ChoosePokeDCare: ChoosePokeDCare,
        StorePokeDCare: StorePokeDCare,
        Cmd_292: Cmd_292,
        CheckMasterRank: CheckMasterRank,
        ShowBattlePointsBox: ShowBattlePointsBox,
        HideBattlePointsBox: HideBattlePointsBox,
        UpdateBattlePointsBox: UpdateBattlePointsBox,
        TakeBPoints: TakeBPoints,
        CheckBPoints: CheckBPoints,
        Cmd_29c: Cmd_29c,
        ChoiceMulti: ChoiceMulti,
        HMEffect: HMEffect,
        CameraBumpEffect: CameraBumpEffect,
        DoubleBattle: DoubleBattle,
        ApplyMovement2: ApplyMovement2,
        Cmd_2a2: Cmd_2a2,
        StoreActHeroFriendCode: StoreActHeroFriendCode,
        StoreActOtherFriendCode: StoreActOtherFriendCode,
        ChooseTradePokemon: ChooseTradePokemon,
        ChsPrizeCasino: ChsPrizeCasino,
        CheckPlate: CheckPlate,
        TakeCoinsCasino: TakeCoinsCasino,
        CheckCoinsCasino2: CheckCoinsCasino2,
        ComparePhraseBoxInput: ComparePhraseBoxInput,
        StoreSealNum: StoreSealNum,
        ActivateMysteryGift: ActivateMysteryGift,
        CheckFollowBattle: CheckFollowBattle,
        Cmd_2af: Cmd_2af,
        Cmd_2b0: Cmd_2b0,
        Cmd_2b1: Cmd_2b1,
        Cmd_2b2: Cmd_2b2,
        SetvarSealRandom: SetvarSealRandom,
        DarkraiFunction: DarkraiFunction,
        Cmd_2b6: Cmd_2b6,
        StorePokeNumParty: StorePokeNumParty,
        StorePokeNickname: StorePokeNickname,
        CloseMultiUnion: CloseMultiUnion,
        CheckBattleUnion: CheckBattleUnion,
        Cmd_2BB: Cmd_2BB,
        CheckWildBattle2: CheckWildBattle2,
        WildBattle2: WildBattle,
        StoreTrainerCardStar: StoreTrainerCardStar,
        BikeRide: BikeRide,
        Cmd_2c0: Cmd_2c0,
        ShowSaveBox: ShowSaveBox,
        HideSaveBox: HideSaveBox,
        Cmd_2c3: Cmd_2c3,
        ShowBTowerSome: ShowBTowerSome,
        DeleteSavesBFactory: DeleteSavesBFactory,
        SpinTradeUnion: SpinTradeUnion,
        CheckVersionGame: CheckVersionGame,
        ShowBArcadeRecors: ShowBArcadeRecors,
        EternaGymAnm: EternaGymAnm,
        FloralClockAnimation: FloralClockAnimation,
        CheckPokeParty2: CheckPokeParty2,
        CheckPokeCastle: CheckPokeCastle,
        ActTeamGalacticEvents: ActTeamGalacticEvents,
        ChooseWirePokeBCastle: ChooseWirePokeBCastle,
        Cmd_2d0: Cmd_2d0,
        Cmd_2d1: Cmd_2d1,
        Cmd_2d2: Cmd_2d2,
        Cmd_2d3: Cmd_2d3,
        Cmd_2d4: Cmd_2d4,
        Cmd_2d5: Cmd_2d5,
        Cmd_2d6: Cmd_2d6,
        Cmd_2d7: Cmd_2d7,
        Cmd_2d8: Cmd_2d8,
        Cmd_2d9: Cmd_2d9,
        Cmd_2da: Cmd_2da,
        Cmd_2db: Cmd_2db,
        Cmd_2dc: Cmd_2dc,
        Cmd_2dd: Cmd_2dd,
        Cmd_2de: Cmd_2de,
        Cmd_2df: Cmd_2df,
        Cmd_2e0: Cmd_2e0,
        Cmd_2e1: Cmd_2e1,
        Cmd_2e2: Cmd_2e2,
        Cmd_2e3: Cmd_2e3,
        Cmd_2e4: Cmd_2e4,
        Cmd_2e5: Cmd_2e5,
        Cmd_2e6: Cmd_2e6,
        Cmd_2e7: Cmd_2e7,
        Cmd_2e8: Cmd_2e8,
        Cmd_2e9: Cmd_2e9,
        Cmd_2ea: Cmd_2ea,
        Cmd_2eb: Cmd_2eb,
        Cmd_2ec: Cmd_2ec,
        Cmd_2ed: Cmd_2ed,
        Cmd_2ee: Cmd_2ee,
        Cmd_2f0: Cmd_2f0,
        Cmd_2f2: Cmd_2f2,
        Cmd_2f3: Cmd_2f3,
        Cmd_2f4: Cmd_2f4,
        Cmd_2f5: Cmd_2f5,
        Cmd_2f6: Cmd_2f6,
        Cmd_2f7: Cmd_2f7,
        Cmd_2f8: Cmd_2f8,
        Cmd_2f9: Cmd_2f9,
        Cmd_2fa: Cmd_2fa,
        Cmd_2fb: Cmd_2fb,
        Cmd_2fc: Cmd_2fc,
        Cmd_2fd: Cmd_2fd,
        Cmd_2fe: Cmd_2fe,
        Cmd_2ff: Cmd_2ff,
        Cmd_300: Cmd_300,
        Cmd_302: Cmd_302,
        Cmd_303: Cmd_303,
        Cmd_304: Cmd_304,
        Cmd_305: Cmd_305,
        Cmd_306: Cmd_306,
        Cmd_307: Cmd_307,
        Cmd_308: Cmd_308,
        Cmd_309: Cmd_309,
        Cmd_30a: Cmd_30a,
        Cmd_30b: Cmd_30b,
        Cmd_30c: Cmd_30c,
        Cmd_30d: Cmd_30d,
        Cmd_30e: Cmd_30e,
        Cmd_30f: Cmd_30f,
        Cmd_310: Cmd_310,
        Cmd_311: Cmd_311,
        Cmd_312: Cmd_312,
        Cmd_313: Cmd_313,
        Cmd_314: Cmd_314,
        Cmd_315: Cmd_315,
        Cmd_316: Cmd_316,
        Cmd_317: Cmd_317,
        WildBattle3: WildBattle,
        Cmd_319: Cmd_319,
        Cmd_31a: Cmd_31a,
        Cmd_31b: Cmd_31b,
        Cmd_31c: Cmd_31c,
        Cmd_31d: Cmd_31d,
        Cmd_31e: Cmd_31e,
        Cmd_31f: Cmd_31f,
        Cmd_320: Cmd_320,
        Cmd_321: Cmd_321,
        Cmd_322: Cmd_322,
        Cmd_323: Cmd_323,
        Cmd_324: Cmd_324,
        Cmd_325: Cmd_325,
        Cmd_326: Cmd_326,
        Cmd_327: Cmd_327,
        PortalEffect: PortalEffect,
        Cmd_329: Cmd_329,
        Cmd_32a: Cmd_32a,
        Cmd_32b: Cmd_32b,
        Cmd_32c: Cmd_32c,
        Cmd_32d: Cmd_32d,
        Cmd_32e: Cmd_32e,
        Cmd_32f: Cmd_32f,
        Cmd_330: Cmd_330,
        Cmd_331: Cmd_331,
        Cmd_332: Cmd_332,
        Cmd_333: Cmd_333,
        Cmd_334: Cmd_334,
        Cmd_335: Cmd_335,
        Cmd_336: Cmd_336,
        Cmd_337: Cmd_337,
        Cmd_338: Cmd_338,
        Cmd_339: Cmd_339,
        Cmd_33a: Cmd_33a,
        Cmd_33c: Cmd_33c,
        Cmd_33d: Cmd_33d,
        Cmd_33e: Cmd_33e,
        Cmd_33f: Cmd_33f,
        Cmd_340: Cmd_340,
        Cmd_341: Cmd_341,
        Cmd_342: Cmd_342,
        Cmd_343: Cmd_343,
        Cmd_344: Cmd_344,
        Cmd_345: Cmd_345,
        Cmd_346: Cmd_346,
        DisplayFloor: DisplayFloor,
    },
    pub const Kind = packed enum(u16) {
        Nop0 = lu16.init(0x0).valueNative(),
        Nop1 = lu16.init(0x1).valueNative(),
        End = lu16.init(0x2).valueNative(),
        Return2 = lu16.init(0x3).valueNative(),
        Cmd_a = lu16.init(0xa).valueNative(),
        If = lu16.init(0x11).valueNative(),
        If2 = lu16.init(0x12).valueNative(),
        CallStandard = lu16.init(0x14).valueNative(),
        ExitStandard = lu16.init(0x15).valueNative(),
        Jump = lu16.init(0x16).valueNative(),
        Call = lu16.init(0x1a).valueNative(),
        Return = lu16.init(0x1b).valueNative(),
        CompareLastResultJump = lu16.init(0x1c).valueNative(),
        CompareLastResultCall = lu16.init(0x1d).valueNative(),
        SetFlag = lu16.init(0x1e).valueNative(),
        ClearFlag = lu16.init(0x1f).valueNative(),
        CheckFlag = lu16.init(0x20).valueNative(),
        Cmd_21 = lu16.init(0x21).valueNative(),
        Cmd_22 = lu16.init(0x22).valueNative(),
        SetTrainerId = lu16.init(0x23).valueNative(),
        Cmd_24 = lu16.init(0x24).valueNative(),
        ClearTrainerId = lu16.init(0x25).valueNative(),
        ScriptCmd_AddValue = lu16.init(0x26).valueNative(),
        ScriptCmd_SubValue = lu16.init(0x27).valueNative(),
        SetVar = lu16.init(0x28).valueNative(),
        CopyVar = lu16.init(0x29).valueNative(),
        Message2 = lu16.init(0x2b).valueNative(),
        Message = lu16.init(0x2c).valueNative(),
        Message3 = lu16.init(0x2d).valueNative(),
        Message4 = lu16.init(0x2e).valueNative(),
        Message5 = lu16.init(0x2f).valueNative(),
        Cmd_30 = lu16.init(0x30).valueNative(),
        WaitButton = lu16.init(0x31).valueNative(),
        Cmd_32 = lu16.init(0x32).valueNative(),
        Cmd_33 = lu16.init(0x33).valueNative(),
        CloseMsgOnKeyPress = lu16.init(0x34).valueNative(),
        FreezeMessageBox = lu16.init(0x35).valueNative(),
        CallMessageBox = lu16.init(0x36).valueNative(),
        ColorMsgBox = lu16.init(0x37).valueNative(),
        TypeMessageBox = lu16.init(0x38).valueNative(),
        NoMapMessageBox = lu16.init(0x39).valueNative(),
        CallTextMsgBox = lu16.init(0x3a).valueNative(),
        StoreMenuStatus = lu16.init(0x3b).valueNative(),
        ShowMenu = lu16.init(0x3c).valueNative(),
        YesNoBox = lu16.init(0x3e).valueNative(),
        Multi = lu16.init(0x40).valueNative(),
        Multi2 = lu16.init(0x41).valueNative(),
        Cmd_42 = lu16.init(0x42).valueNative(),
        CloseMulti = lu16.init(0x43).valueNative(),
        Multi3 = lu16.init(0x44).valueNative(),
        Multi4 = lu16.init(0x45).valueNative(),
        TxtMsgScrpMulti = lu16.init(0x46).valueNative(),
        CloseMulti4 = lu16.init(0x47).valueNative(),
        PlayFanfare = lu16.init(0x49).valueNative(),
        MultiRow = lu16.init(0x48).valueNative(),
        PlayFanfare2 = lu16.init(0x4a).valueNative(),
        WaitFanfare = lu16.init(0x4b).valueNative(),
        PlayCry = lu16.init(0x4c).valueNative(),
        WaitCry = lu16.init(0x4d).valueNative(),
        Soundfr = lu16.init(0x4e).valueNative(),
        Cmd_4f = lu16.init(0x4f).valueNative(),
        PlaySound = lu16.init(0x50).valueNative(),
        Stop = lu16.init(0x51).valueNative(),
        Restart = lu16.init(0x52).valueNative(),
        Cmd_53 = lu16.init(0x53).valueNative(),
        SwitchMusic = lu16.init(0x54).valueNative(),
        StoreSayingLearned = lu16.init(0x55).valueNative(),
        PlaySound2 = lu16.init(0x57).valueNative(),
        Cmd_58 = lu16.init(0x58).valueNative(),
        CheckSayingLearned = lu16.init(0x59).valueNative(),
        SwithMusic2 = lu16.init(0x5a).valueNative(),
        ActMicrophone = lu16.init(0x5b).valueNative(),
        DeactMicrophone = lu16.init(0x5c).valueNative(),
        Cmd_5d = lu16.init(0x5d).valueNative(),
        ApplyMovement = lu16.init(0x5e).valueNative(),
        WaitMovement = lu16.init(0x5f).valueNative(),
        LockAll = lu16.init(0x60).valueNative(),
        ReleaseAll = lu16.init(0x61).valueNative(),
        Lock = lu16.init(0x62).valueNative(),
        Release = lu16.init(0x63).valueNative(),
        AddPeople = lu16.init(0x64).valueNative(),
        RemovePeople = lu16.init(0x65).valueNative(),
        LockCam = lu16.init(0x66).valueNative(),
        ZoomCam = lu16.init(0x67).valueNative(),
        FacePlayer = lu16.init(0x68).valueNative(),
        CheckSpritePosition = lu16.init(0x69).valueNative(),
        CheckPersonPosition = lu16.init(0x6b).valueNative(),
        ContinueFollow = lu16.init(0x6c).valueNative(),
        FollowHero = lu16.init(0x6d).valueNative(),
        TakeMoney = lu16.init(0x70).valueNative(),
        CheckMoney = lu16.init(0x71).valueNative(),
        ShowMoney = lu16.init(0x72).valueNative(),
        HideMoney = lu16.init(0x73).valueNative(),
        UpdateMoney = lu16.init(0x74).valueNative(),
        ShowCoins = lu16.init(0x75).valueNative(),
        HideCoins = lu16.init(0x76).valueNative(),
        UpdateCoins = lu16.init(0x77).valueNative(),
        CheckCoins = lu16.init(0x78).valueNative(),
        GiveCoins = lu16.init(0x79).valueNative(),
        TakeCoins = lu16.init(0x7a).valueNative(),
        TakeItem = lu16.init(0x7b).valueNative(),
        GiveItem = lu16.init(0x7c).valueNative(),
        CheckStoreItem = lu16.init(0x7d).valueNative(),
        CheckItem = lu16.init(0x7e).valueNative(),
        StoreItemTaken = lu16.init(0x7f).valueNative(),
        StoreItemType = lu16.init(0x80).valueNative(),
        SendItemType1 = lu16.init(0x83).valueNative(),
        Cmd_84 = lu16.init(0x84).valueNative(),
        CheckUndergroundPcStatus = lu16.init(0x85).valueNative(),
        Cmd_86 = lu16.init(0x86).valueNative(),
        SendItemType2 = lu16.init(0x87).valueNative(),
        Cmd_88 = lu16.init(0x88).valueNative(),
        Cmd_89 = lu16.init(0x89).valueNative(),
        Cmd_8a = lu16.init(0x8a).valueNative(),
        Cmd_8b = lu16.init(0x8b).valueNative(),
        Cmd_8c = lu16.init(0x8c).valueNative(),
        Cmd_8d = lu16.init(0x8d).valueNative(),
        Cmd_8e = lu16.init(0x8e).valueNative(),
        SendItemType3 = lu16.init(0x8f).valueNative(),
        CheckPokemonParty = lu16.init(0x93).valueNative(),
        StorePokemonParty = lu16.init(0x94).valueNative(),
        SetPokemonPartyStored = lu16.init(0x95).valueNative(),
        GivePokemon = lu16.init(0x96).valueNative(),
        GiveEgg = lu16.init(0x97).valueNative(),
        CheckMove = lu16.init(0x99).valueNative(),
        CheckPlaceStored = lu16.init(0x9a).valueNative(),
        Cmd_9b = lu16.init(0x9b).valueNative(),
        Cmd_9c = lu16.init(0x9c).valueNative(),
        Cmd_9d = lu16.init(0x9d).valueNative(),
        Cmd_9e = lu16.init(0x9e).valueNative(),
        Cmd_9f = lu16.init(0x9f).valueNative(),
        Cmd_a0 = lu16.init(0xa0).valueNative(),
        CallEnd = lu16.init(0xa1).valueNative(),
        Cmd_A2 = lu16.init(0xa2).valueNative(),
        Wfc_ = lu16.init(0xa3).valueNative(),
        Cmd_a4 = lu16.init(0xa4).valueNative(),
        Interview = lu16.init(0xa5).valueNative(),
        DressPokemon = lu16.init(0xa6).valueNative(),
        DisplayDressedPokemon = lu16.init(0xa7).valueNative(),
        DisplayContestPokemon = lu16.init(0xa8).valueNative(),
        OpenBallCapsule = lu16.init(0xa9).valueNative(),
        OpenSinnohMaps = lu16.init(0xaa).valueNative(),
        OpenPcFunction = lu16.init(0xab).valueNative(),
        DrawUnion = lu16.init(0xac).valueNative(),
        TrainerCaseUnion = lu16.init(0xad).valueNative(),
        TradeUnion = lu16.init(0xae).valueNative(),
        RecordMixingUnion = lu16.init(0xaf).valueNative(),
        EndGame = lu16.init(0xb0).valueNative(),
        HallFameAnm = lu16.init(0xb1).valueNative(),
        StoreWfcStatus = lu16.init(0xb2).valueNative(),
        StartWfc = lu16.init(0xb3).valueNative(),
        ChooseStarter = lu16.init(0xb4).valueNative(),
        BattleStarter = lu16.init(0xb5).valueNative(),
        BattleId = lu16.init(0xb6).valueNative(),
        SetVarBattle = lu16.init(0xb7).valueNative(),
        CheckBattleType = lu16.init(0xb8).valueNative(),
        SetVarBattle2 = lu16.init(0xb9).valueNative(),
        ChoosePokeNick = lu16.init(0xbb).valueNative(),
        FadeScreen = lu16.init(0xbc).valueNative(),
        ResetScreen = lu16.init(0xbd).valueNative(),
        Warp = lu16.init(0xbe).valueNative(),
        RockClimbAnimation = lu16.init(0xbf).valueNative(),
        SurfAnimation = lu16.init(0xc0).valueNative(),
        WaterfallAnimation = lu16.init(0xc1).valueNative(),
        FlashAnimation = lu16.init(0xc3).valueNative(),
        DefogAnimation = lu16.init(0xc4).valueNative(),
        PrepHmEffect = lu16.init(0xc5).valueNative(),
        Tuxedo = lu16.init(0xc6).valueNative(),
        CheckBike = lu16.init(0xc7).valueNative(),
        RideBike = lu16.init(0xc8).valueNative(),
        RideBike2 = lu16.init(0xc9).valueNative(),
        GivePokeHiroAnm = lu16.init(0xcb).valueNative(),
        StopGivePokeHiroAnm = lu16.init(0xcc).valueNative(),
        SetVarHero = lu16.init(0xcd).valueNative(),
        SetVariableRival = lu16.init(0xce).valueNative(),
        SetVarAlter = lu16.init(0xcf).valueNative(),
        SetVarPoke = lu16.init(0xd0).valueNative(),
        SetVarItem = lu16.init(0xd1).valueNative(),
        SetVarItemNum = lu16.init(0xd2).valueNative(),
        SetVarAtkItem = lu16.init(0xd3).valueNative(),
        SetVarAtk = lu16.init(0xd4).valueNative(),
        SetVariableNumber = lu16.init(0xd5).valueNative(),
        SetVarPokeNick = lu16.init(0xd6).valueNative(),
        SetVarObj = lu16.init(0xd7).valueNative(),
        SetVarTrainer = lu16.init(0xd8).valueNative(),
        SetVarWiFiSprite = lu16.init(0xd9).valueNative(),
        SetVarPokeStored = lu16.init(0xda).valueNative(),
        SetVarStrHero = lu16.init(0xdb).valueNative(),
        SetVarStrRival = lu16.init(0xdc).valueNative(),
        StoreStarter = lu16.init(0xde).valueNative(),
        Cmd_df = lu16.init(0xdf).valueNative(),
        SetVarItemStored = lu16.init(0xe0).valueNative(),
        SetVarItemStored2 = lu16.init(0xe1).valueNative(),
        SetVarSwarmPoke = lu16.init(0xe2).valueNative(),
        CheckSwarmPoke = lu16.init(0xe3).valueNative(),
        StartBattleAnalysis = lu16.init(0xe4).valueNative(),
        TrainerBattle = lu16.init(0xe5).valueNative(),
        EndtrainerBattle = lu16.init(0xe6).valueNative(),
        TrainerBattleStored = lu16.init(0xe7).valueNative(),
        TrainerBattleStored2 = lu16.init(0xe8).valueNative(),
        CheckTrainerStatus = lu16.init(0xe9).valueNative(),
        StoreLeagueTrainer = lu16.init(0xea).valueNative(),
        LostGoPc = lu16.init(0xeb).valueNative(),
        CheckTrainerLost = lu16.init(0xec).valueNative(),
        CheckTrainerStatus2 = lu16.init(0xed).valueNative(),
        StorePokePartyDefeated = lu16.init(0xee).valueNative(),
        ChsFriend = lu16.init(0xf2).valueNative(),
        WireBattleWait = lu16.init(0xf3).valueNative(),
        Cmd_f6 = lu16.init(0xf6).valueNative(),
        Pokecontest = lu16.init(0xf7).valueNative(),
        StartOvation = lu16.init(0xf8).valueNative(),
        StopOvation = lu16.init(0xf9).valueNative(),
        Cmd_fa = lu16.init(0xfa).valueNative(),
        Cmd_fb = lu16.init(0xfb).valueNative(),
        Cmd_fc = lu16.init(0xfc).valueNative(),
        SetvarOtherEntry = lu16.init(0xfd).valueNative(),
        Cmd_fe = lu16.init(0xfe).valueNative(),
        SetvatHiroEntry = lu16.init(0xff).valueNative(),
        Cmd_100 = lu16.init(0x100).valueNative(),
        BlackFlashEffect = lu16.init(0x101).valueNative(),
        SetvarTypeContest = lu16.init(0x102).valueNative(),
        SetvarRankContest = lu16.init(0x103).valueNative(),
        Cmd_104 = lu16.init(0x104).valueNative(),
        Cmd_105 = lu16.init(0x105).valueNative(),
        Cmd_106 = lu16.init(0x106).valueNative(),
        Cmd_107 = lu16.init(0x107).valueNative(),
        StorePeopleIdContest = lu16.init(0x108).valueNative(),
        Cmd_109 = lu16.init(0x109).valueNative(),
        SetvatHiroEntry2 = lu16.init(0x10a).valueNative(),
        ActPeopleContest = lu16.init(0x10b).valueNative(),
        Cmd_10c = lu16.init(0x10c).valueNative(),
        Cmd_10d = lu16.init(0x10d).valueNative(),
        Cmd_10e = lu16.init(0x10e).valueNative(),
        Cmd_10f = lu16.init(0x10f).valueNative(),
        Cmd_110 = lu16.init(0x110).valueNative(),
        FlashContest = lu16.init(0x111).valueNative(),
        EndFlash = lu16.init(0x112).valueNative(),
        CarpetAnm = lu16.init(0x113).valueNative(),
        Cmd_114 = lu16.init(0x114).valueNative(),
        Cmd_115 = lu16.init(0x115).valueNative(),
        ShowLnkCntRecord = lu16.init(0x116).valueNative(),
        Cmd_117 = lu16.init(0x117).valueNative(),
        Cmd_118 = lu16.init(0x118).valueNative(),
        StorePokerus = lu16.init(0x119).valueNative(),
        WarpMapElevator = lu16.init(0x11b).valueNative(),
        CheckFloor = lu16.init(0x11c).valueNative(),
        StartLift = lu16.init(0x11d).valueNative(),
        StoreSinPokemonSeen = lu16.init(0x11e).valueNative(),
        Cmd_11f = lu16.init(0x11f).valueNative(),
        StoreTotPokemonSeen = lu16.init(0x120).valueNative(),
        StoreNatPokemonSeen = lu16.init(0x121).valueNative(),
        SetVarTextPokedex = lu16.init(0x123).valueNative(),
        WildBattle = lu16.init(0x124).valueNative(),
        StarterBattle = lu16.init(0x125).valueNative(),
        ExplanationBattle = lu16.init(0x126).valueNative(),
        HoneyTreeBattle = lu16.init(0x127).valueNative(),
        CheckIfHoneySlathered = lu16.init(0x128).valueNative(),
        RandomBattle = lu16.init(0x129).valueNative(),
        StopRandomBattle = lu16.init(0x12a).valueNative(),
        WriteAutograph = lu16.init(0x12b).valueNative(),
        StoreSaveData = lu16.init(0x12c).valueNative(),
        CheckSaveData = lu16.init(0x12d).valueNative(),
        CheckDress = lu16.init(0x12e).valueNative(),
        CheckContestWin = lu16.init(0x12f).valueNative(),
        StorePhotoName = lu16.init(0x130).valueNative(),
        GivePoketch = lu16.init(0x131).valueNative(),
        CheckPtchAppl = lu16.init(0x132).valueNative(),
        ActPktchAppl = lu16.init(0x133).valueNative(),
        StorePoketchApp = lu16.init(0x134).valueNative(),
        FriendBT = lu16.init(0x135).valueNative(),
        FriendBT2 = lu16.init(0x136).valueNative(),
        Cmd_138 = lu16.init(0x138).valueNative(),
        OpenUnionFunction2 = lu16.init(0x139).valueNative(),
        StartUnion = lu16.init(0x13a).valueNative(),
        LinkClosed = lu16.init(0x13b).valueNative(),
        SetUnionFunctionId = lu16.init(0x13c).valueNative(),
        CloseUnionFunction = lu16.init(0x13d).valueNative(),
        CloseUnionFunction2 = lu16.init(0x13e).valueNative(),
        SetVarUnionMessage = lu16.init(0x13f).valueNative(),
        StoreYourDecisionUnion = lu16.init(0x140).valueNative(),
        StoreOtherDecisionUnion = lu16.init(0x141).valueNative(),
        Cmd_142 = lu16.init(0x142).valueNative(),
        CheckOtherDecisionUnion = lu16.init(0x143).valueNative(),
        StoreYourDecisionUnion2 = lu16.init(0x144).valueNative(),
        StoreOtherDecisionUnion2 = lu16.init(0x145).valueNative(),
        CheckOtherDecisionUnion2 = lu16.init(0x146).valueNative(),
        Pokemart = lu16.init(0x147).valueNative(),
        Pokemart1 = lu16.init(0x148).valueNative(),
        Pokemart2 = lu16.init(0x149).valueNative(),
        Pokemart3 = lu16.init(0x14a).valueNative(),
        DefeatGoPokecenter = lu16.init(0x14b).valueNative(),
        ActBike = lu16.init(0x14c).valueNative(),
        CheckGender = lu16.init(0x14d).valueNative(),
        HealPokemon = lu16.init(0x14e).valueNative(),
        DeactWireless = lu16.init(0x14f).valueNative(),
        DeleteEntry = lu16.init(0x150).valueNative(),
        Cmd_151 = lu16.init(0x151).valueNative(),
        UndergroundId = lu16.init(0x152).valueNative(),
        UnionRoom = lu16.init(0x153).valueNative(),
        OpenWiFiSprite = lu16.init(0x154).valueNative(),
        StoreWiFiSprite = lu16.init(0x155).valueNative(),
        ActWiFiSprite = lu16.init(0x156).valueNative(),
        Cmd_157 = lu16.init(0x157).valueNative(),
        ActivatePokedex = lu16.init(0x158).valueNative(),
        GiveRunningShoes = lu16.init(0x15a).valueNative(),
        CheckBadge = lu16.init(0x15b).valueNative(),
        EnableBadge = lu16.init(0x15c).valueNative(),
        DisableBadge = lu16.init(0x15d).valueNative(),
        CheckFollow = lu16.init(0x160).valueNative(),
        StartFollow = lu16.init(0x161).valueNative(),
        StopFollow = lu16.init(0x162).valueNative(),
        Cmd_164 = lu16.init(0x164).valueNative(),
        Cmd_166 = lu16.init(0x166).valueNative(),
        PrepareDoorAnimation = lu16.init(0x168).valueNative(),
        WaitAction = lu16.init(0x169).valueNative(),
        WaitClose = lu16.init(0x16a).valueNative(),
        OpenDoor = lu16.init(0x16b).valueNative(),
        CloseDoor = lu16.init(0x16c).valueNative(),
        ActDcareFunction = lu16.init(0x16d).valueNative(),
        StorePDCareNum = lu16.init(0x16e).valueNative(),
        PastoriaCityFunction = lu16.init(0x16f).valueNative(),
        PastoriaCityFunction2 = lu16.init(0x170).valueNative(),
        HearthromeGymFunction = lu16.init(0x171).valueNative(),
        HearthromeGymFunction2 = lu16.init(0x172).valueNative(),
        CanalaveGymFunction = lu16.init(0x173).valueNative(),
        VeilstoneGymFunction = lu16.init(0x174).valueNative(),
        SunishoreGymFunction = lu16.init(0x175).valueNative(),
        SunishoreGymFunction2 = lu16.init(0x176).valueNative(),
        CheckPartyNumber = lu16.init(0x177).valueNative(),
        OpenBerryPouch = lu16.init(0x178).valueNative(),
        Cmd_179 = lu16.init(0x179).valueNative(),
        Cmd_17a = lu16.init(0x17a).valueNative(),
        Cmd_17b = lu16.init(0x17b).valueNative(),
        SetNaturePokemon = lu16.init(0x17c).valueNative(),
        Cmd_17d = lu16.init(0x17d).valueNative(),
        Cmd_17e = lu16.init(0x17e).valueNative(),
        Cmd_17f = lu16.init(0x17f).valueNative(),
        Cmd_180 = lu16.init(0x180).valueNative(),
        Cmd_181 = lu16.init(0x181).valueNative(),
        CheckDeoxis = lu16.init(0x182).valueNative(),
        Cmd_183 = lu16.init(0x183).valueNative(),
        Cmd_184 = lu16.init(0x184).valueNative(),
        Cmd_185 = lu16.init(0x185).valueNative(),
        ChangeOwPosition = lu16.init(0x186).valueNative(),
        SetOwPosition = lu16.init(0x187).valueNative(),
        ChangeOwMovement = lu16.init(0x188).valueNative(),
        ReleaseOw = lu16.init(0x189).valueNative(),
        SetTilePassable = lu16.init(0x18a).valueNative(),
        SetTileLocked = lu16.init(0x18b).valueNative(),
        SetOwsFollow = lu16.init(0x18c).valueNative(),
        ShowClockSave = lu16.init(0x18d).valueNative(),
        HideClockSave = lu16.init(0x18e).valueNative(),
        Cmd_18f = lu16.init(0x18f).valueNative(),
        SetSaveData = lu16.init(0x190).valueNative(),
        ChsPokemenu = lu16.init(0x191).valueNative(),
        ChsPokemenu2 = lu16.init(0x192).valueNative(),
        StorePokeMenu2 = lu16.init(0x193).valueNative(),
        ChsPokeContest = lu16.init(0x194).valueNative(),
        StorePokeContest = lu16.init(0x195).valueNative(),
        ShowPokeInfo = lu16.init(0x196).valueNative(),
        StorePokeMove = lu16.init(0x197).valueNative(),
        CheckPokeEgg = lu16.init(0x198).valueNative(),
        ComparePokeNick = lu16.init(0x199).valueNative(),
        CheckPartyNumberUnion = lu16.init(0x19a).valueNative(),
        CheckPokePartyHealth = lu16.init(0x19b).valueNative(),
        CheckPokePartyNumDCare = lu16.init(0x19c).valueNative(),
        CheckEggUnion = lu16.init(0x19d).valueNative(),
        UndergroundFunction = lu16.init(0x19e).valueNative(),
        UndergroundFunction2 = lu16.init(0x19f).valueNative(),
        UndergroundStart = lu16.init(0x1a0).valueNative(),
        TakeMoneyDCare = lu16.init(0x1a3).valueNative(),
        TakePokemonDCare = lu16.init(0x1a4).valueNative(),
        ActEggDayCMan = lu16.init(0x1a8).valueNative(),
        DeactEggDayCMan = lu16.init(0x1a9).valueNative(),
        SetVarPokeAndMoneyDCare = lu16.init(0x1aa).valueNative(),
        CheckMoneyDCare = lu16.init(0x1ab).valueNative(),
        EggAnimation = lu16.init(0x1ac).valueNative(),
        SetVarPokeAndLevelDCare = lu16.init(0x1ae).valueNative(),
        SetVarPokeChosenDCare = lu16.init(0x1af).valueNative(),
        GivePokeDCare = lu16.init(0x1b0).valueNative(),
        AddPeople2 = lu16.init(0x1b1).valueNative(),
        RemovePeople2 = lu16.init(0x1b2).valueNative(),
        MailBox = lu16.init(0x1b3).valueNative(),
        CheckMail = lu16.init(0x1b4).valueNative(),
        ShowRecordList = lu16.init(0x1b5).valueNative(),
        CheckTime = lu16.init(0x1b6).valueNative(),
        CheckIdPlayer = lu16.init(0x1b7).valueNative(),
        RandomTextStored = lu16.init(0x1b8).valueNative(),
        StoreHappyPoke = lu16.init(0x1b9).valueNative(),
        StoreHappyStatus = lu16.init(0x1ba).valueNative(),
        SetVarDataDayCare = lu16.init(0x1bc).valueNative(),
        CheckFacePosition = lu16.init(0x1bd).valueNative(),
        StorePokeDCareLove = lu16.init(0x1be).valueNative(),
        CheckStatusSolaceonEvent = lu16.init(0x1bf).valueNative(),
        CheckPokeParty = lu16.init(0x1c0).valueNative(),
        CopyPokemonHeight = lu16.init(0x1c1).valueNative(),
        SetVariablePokemonHeight = lu16.init(0x1c2).valueNative(),
        ComparePokemonHeight = lu16.init(0x1c3).valueNative(),
        CheckPokemonHeight = lu16.init(0x1c4).valueNative(),
        ShowMoveInfo = lu16.init(0x1c5).valueNative(),
        StorePokeDelete = lu16.init(0x1c6).valueNative(),
        StoreMoveDelete = lu16.init(0x1c7).valueNative(),
        CheckMoveNumDelete = lu16.init(0x1c8).valueNative(),
        StoreDeleteMove = lu16.init(0x1c9).valueNative(),
        CheckDeleteMove = lu16.init(0x1ca).valueNative(),
        SetvarMoveDelete = lu16.init(0x1cb).valueNative(),
        Cmd_1cc = lu16.init(0x1cc).valueNative(),
        DeActivateLeader = lu16.init(0x1cd).valueNative(),
        HmFunctions = lu16.init(0x1cf).valueNative(),
        FlashDuration = lu16.init(0x1d0).valueNative(),
        DefogDuration = lu16.init(0x1d1).valueNative(),
        GiveAccessories = lu16.init(0x1d2).valueNative(),
        CheckAccessories = lu16.init(0x1d3).valueNative(),
        Cmd_1d4 = lu16.init(0x1d4).valueNative(),
        GiveAccessories2 = lu16.init(0x1d5).valueNative(),
        CheckAccessories2 = lu16.init(0x1d6).valueNative(),
        BerryPoffin = lu16.init(0x1d7).valueNative(),
        SetVarBTowerChs = lu16.init(0x1d8).valueNative(),
        BattleRoomResult = lu16.init(0x1d9).valueNative(),
        ActivateBTower = lu16.init(0x1da).valueNative(),
        StoreBTowerData = lu16.init(0x1db).valueNative(),
        CloseBTower = lu16.init(0x1dc).valueNative(),
        CallBTowerFunctions = lu16.init(0x1dd).valueNative(),
        RandomTeamBTower = lu16.init(0x1de).valueNative(),
        StorePrizeNumBTower = lu16.init(0x1df).valueNative(),
        StorePeopleIdBTower = lu16.init(0x1e0).valueNative(),
        CallBTowerWireFunction = lu16.init(0x1e1).valueNative(),
        StorePChosenWireBTower = lu16.init(0x1e2).valueNative(),
        StoreRankDataWireBTower = lu16.init(0x1e3).valueNative(),
        Cmd_1e4 = lu16.init(0x1e4).valueNative(),
        RandomEvent = lu16.init(0x1e5).valueNative(),
        CheckSinnohPokedex = lu16.init(0x1e8).valueNative(),
        CheckNationalPokedex = lu16.init(0x1e9).valueNative(),
        ShowSinnohSheet = lu16.init(0x1ea).valueNative(),
        ShowNationalSheet = lu16.init(0x1eb).valueNative(),
        Cmd_1ec = lu16.init(0x1ec).valueNative(),
        StoreTrophyPokemon = lu16.init(0x1ed).valueNative(),
        Cmd_1ef = lu16.init(0x1ef).valueNative(),
        Cmd_1f0 = lu16.init(0x1f0).valueNative(),
        CheckActFossil = lu16.init(0x1f1).valueNative(),
        Cmd_1f2 = lu16.init(0x1f2).valueNative(),
        Cmd_1f3 = lu16.init(0x1f3).valueNative(),
        CheckItemChosen = lu16.init(0x1f4).valueNative(),
        CompareItemPokeFossil = lu16.init(0x1f5).valueNative(),
        CheckPokemonLevel = lu16.init(0x1f6).valueNative(),
        CheckIsPokemonPoisoned = lu16.init(0x1f7).valueNative(),
        PreWfc = lu16.init(0x1f8).valueNative(),
        StoreFurniture = lu16.init(0x1f9).valueNative(),
        CopyFurniture = lu16.init(0x1fb).valueNative(),
        SetBCastleFunctionId = lu16.init(0x1fe).valueNative(),
        BCastleFunctReturn = lu16.init(0x1ff).valueNative(),
        Cmd_200 = lu16.init(0x200).valueNative(),
        CheckEffectHm = lu16.init(0x201).valueNative(),
        GreatMarshFunction = lu16.init(0x202).valueNative(),
        BattlePokeColosseum = lu16.init(0x203).valueNative(),
        WarpLastElevator = lu16.init(0x204).valueNative(),
        OpenGeoNet = lu16.init(0x205).valueNative(),
        GreatMarshBynocule = lu16.init(0x206).valueNative(),
        StorePokeColosseumLost = lu16.init(0x207).valueNative(),
        PokemonPicture = lu16.init(0x208).valueNative(),
        HidePicture = lu16.init(0x209).valueNative(),
        Cmd_20a = lu16.init(0x20a).valueNative(),
        Cmd_20b = lu16.init(0x20b).valueNative(),
        Cmd_20c = lu16.init(0x20c).valueNative(),
        SetvarMtCoronet = lu16.init(0x20d).valueNative(),
        Cmd_20e = lu16.init(0x20e).valueNative(),
        CheckQuicTrineCoordinates = lu16.init(0x20f).valueNative(),
        SetvarQuickTrainCoordinates = lu16.init(0x210).valueNative(),
        MoveTrainAnm = lu16.init(0x211).valueNative(),
        StorePokeNature = lu16.init(0x212).valueNative(),
        CheckPokeNature = lu16.init(0x213).valueNative(),
        RandomHallowes = lu16.init(0x214).valueNative(),
        StartAmity = lu16.init(0x215).valueNative(),
        Cmd_216 = lu16.init(0x216).valueNative(),
        Cmd_217 = lu16.init(0x217).valueNative(),
        ChsRSPoke = lu16.init(0x218).valueNative(),
        SetSPoke = lu16.init(0x219).valueNative(),
        CheckSPoke = lu16.init(0x21a).valueNative(),
        Cmd_21b = lu16.init(0x21b).valueNative(),
        ActSwarmPoke = lu16.init(0x21c).valueNative(),
        Cmd_21d = lu16.init(0x21d).valueNative(),
        Cmd_21e = lu16.init(0x21e).valueNative(),
        CheckMoveRemember = lu16.init(0x21f).valueNative(),
        Cmd_220 = lu16.init(0x220).valueNative(),
        StorePokeRemember = lu16.init(0x221).valueNative(),
        Cmd_222 = lu16.init(0x222).valueNative(),
        StoreRememberMove = lu16.init(0x223).valueNative(),
        TeachMove = lu16.init(0x224).valueNative(),
        CheckTeachMove = lu16.init(0x225).valueNative(),
        SetTradeId = lu16.init(0x226).valueNative(),
        CheckPokemonTrade = lu16.init(0x228).valueNative(),
        TradeChosenPokemon = lu16.init(0x229).valueNative(),
        StopTrade = lu16.init(0x22a).valueNative(),
        Cmd_22b = lu16.init(0x22b).valueNative(),
        CloseOakAssistantEvent = lu16.init(0x22c).valueNative(),
        CheckNatPokedexStatus = lu16.init(0x22d).valueNative(),
        CheckRibbonNumber = lu16.init(0x22f).valueNative(),
        CheckRibbon = lu16.init(0x230).valueNative(),
        GiveRibbon = lu16.init(0x231).valueNative(),
        SetvarRibbon = lu16.init(0x232).valueNative(),
        CheckHappyRibbon = lu16.init(0x233).valueNative(),
        CheckPokemart = lu16.init(0x234).valueNative(),
        CheckFurniture = lu16.init(0x235).valueNative(),
        Cmd_236 = lu16.init(0x236).valueNative(),
        CheckPhraseBoxInput = lu16.init(0x237).valueNative(),
        CheckStatusPhraseBox = lu16.init(0x238).valueNative(),
        DecideRules = lu16.init(0x239).valueNative(),
        CheckFootStep = lu16.init(0x23a).valueNative(),
        HealPokemonAnimation = lu16.init(0x23b).valueNative(),
        StoreElevatorDirection = lu16.init(0x23c).valueNative(),
        ShipAnimation = lu16.init(0x23d).valueNative(),
        Cmd_23e = lu16.init(0x23e).valueNative(),
        StorePhraseBox1W = lu16.init(0x243).valueNative(),
        StorePhraseBox2W = lu16.init(0x244).valueNative(),
        SetvarPhraseBox1W = lu16.init(0x245).valueNative(),
        StoreMtCoronet = lu16.init(0x246).valueNative(),
        CheckFirstPokeParty = lu16.init(0x247).valueNative(),
        CheckPokeType = lu16.init(0x248).valueNative(),
        CheckPhraseBoxInput2 = lu16.init(0x249).valueNative(),
        StoreUndTime = lu16.init(0x24a).valueNative(),
        PreparePcAnimation = lu16.init(0x24b).valueNative(),
        OpenPcAnimation = lu16.init(0x24c).valueNative(),
        ClosePcAnimation = lu16.init(0x24d).valueNative(),
        CheckLottoNumber = lu16.init(0x24e).valueNative(),
        CompareLottoNumber = lu16.init(0x24f).valueNative(),
        SetvarIdPokeBoxes = lu16.init(0x251).valueNative(),
        Cmd_250 = lu16.init(0x250).valueNative(),
        CheckBoxesNumber = lu16.init(0x252).valueNative(),
        StopGreatMarsh = lu16.init(0x253).valueNative(),
        CheckPokeCatchingShow = lu16.init(0x254).valueNative(),
        CloseCatchingShow = lu16.init(0x255).valueNative(),
        CheckCatchingShowRecords = lu16.init(0x256).valueNative(),
        SprtSave = lu16.init(0x257).valueNative(),
        RetSprtSave = lu16.init(0x258).valueNative(),
        ElevLgAnimation = lu16.init(0x259).valueNative(),
        CheckElevLgAnm = lu16.init(0x25a).valueNative(),
        ElevIrAnm = lu16.init(0x25b).valueNative(),
        StopElevAnm = lu16.init(0x25c).valueNative(),
        CheckElevPosition = lu16.init(0x25d).valueNative(),
        GalactAnm = lu16.init(0x25e).valueNative(),
        GalactAnm2 = lu16.init(0x25f).valueNative(),
        MainEvent = lu16.init(0x260).valueNative(),
        CheckAccessories3 = lu16.init(0x261).valueNative(),
        ActDeoxisFormChange = lu16.init(0x262).valueNative(),
        ChangeFormDeoxis = lu16.init(0x263).valueNative(),
        CheckCoombeEvent = lu16.init(0x264).valueNative(),
        ActContestMap = lu16.init(0x265).valueNative(),
        Cmd_266 = lu16.init(0x266).valueNative(),
        Pokecasino = lu16.init(0x267).valueNative(),
        CheckTime2 = lu16.init(0x268).valueNative(),
        RegigigasAnm = lu16.init(0x269).valueNative(),
        CresseliaAnm = lu16.init(0x26a).valueNative(),
        CheckRegi = lu16.init(0x26b).valueNative(),
        CheckMassage = lu16.init(0x26c).valueNative(),
        UnownMessageBox = lu16.init(0x26d).valueNative(),
        CheckPCatchingShow = lu16.init(0x26e).valueNative(),
        Cmd_26f = lu16.init(0x26f).valueNative(),
        ShayminAnm = lu16.init(0x270).valueNative(),
        ThankNameInsert = lu16.init(0x271).valueNative(),
        SetvarShaymin = lu16.init(0x272).valueNative(),
        SetvarAccessories2 = lu16.init(0x273).valueNative(),
        Cmd_274 = lu16.init(0x274).valueNative(),
        CheckRecordCasino = lu16.init(0x275).valueNative(),
        CheckCoinsCasino = lu16.init(0x276).valueNative(),
        SrtRandomNum = lu16.init(0x277).valueNative(),
        CheckPokeLevel2 = lu16.init(0x278).valueNative(),
        Cmd_279 = lu16.init(0x279).valueNative(),
        LeagueCastleView = lu16.init(0x27a).valueNative(),
        Cmd_27b = lu16.init(0x27b).valueNative(),
        SetvarAmityPokemon = lu16.init(0x27c).valueNative(),
        Cmd_27d = lu16.init(0x27d).valueNative(),
        CheckFirstTimeVShop = lu16.init(0x27e).valueNative(),
        Cmd_27f = lu16.init(0x27f).valueNative(),
        SetvarIdNumber = lu16.init(0x280).valueNative(),
        Cmd_281 = lu16.init(0x281).valueNative(),
        SetvarUnk = lu16.init(0x282).valueNative(),
        Cmd_283 = lu16.init(0x283).valueNative(),
        CheckRuinManiac = lu16.init(0x284).valueNative(),
        CheckTurnBack = lu16.init(0x285).valueNative(),
        CheckUgPeopleNum = lu16.init(0x286).valueNative(),
        CheckUgFossilNum = lu16.init(0x287).valueNative(),
        CheckUgTrapsNum = lu16.init(0x288).valueNative(),
        CheckPoffinItem = lu16.init(0x289).valueNative(),
        CheckPoffinCaseStatus = lu16.init(0x28a).valueNative(),
        UnkFunct2 = lu16.init(0x28b).valueNative(),
        PokemonPartyPicture = lu16.init(0x28c).valueNative(),
        ActLearning = lu16.init(0x28d).valueNative(),
        SetSoundLearning = lu16.init(0x28e).valueNative(),
        CheckFirstTimeChampion = lu16.init(0x28f).valueNative(),
        ChoosePokeDCare = lu16.init(0x290).valueNative(),
        StorePokeDCare = lu16.init(0x291).valueNative(),
        Cmd_292 = lu16.init(0x292).valueNative(),
        CheckMasterRank = lu16.init(0x293).valueNative(),
        ShowBattlePointsBox = lu16.init(0x294).valueNative(),
        HideBattlePointsBox = lu16.init(0x295).valueNative(),
        UpdateBattlePointsBox = lu16.init(0x296).valueNative(),
        TakeBPoints = lu16.init(0x299).valueNative(),
        CheckBPoints = lu16.init(0x29a).valueNative(),
        Cmd_29c = lu16.init(0x29c).valueNative(),
        ChoiceMulti = lu16.init(0x29d).valueNative(),
        HMEffect = lu16.init(0x29e).valueNative(),
        CameraBumpEffect = lu16.init(0x29f).valueNative(),
        DoubleBattle = lu16.init(0x2a0).valueNative(),
        ApplyMovement2 = lu16.init(0x2a1).valueNative(),
        Cmd_2a2 = lu16.init(0x2a2).valueNative(),
        StoreActHeroFriendCode = lu16.init(0x2a3).valueNative(),
        StoreActOtherFriendCode = lu16.init(0x2a4).valueNative(),
        ChooseTradePokemon = lu16.init(0x2a5).valueNative(),
        ChsPrizeCasino = lu16.init(0x2a6).valueNative(),
        CheckPlate = lu16.init(0x2a7).valueNative(),
        TakeCoinsCasino = lu16.init(0x2a8).valueNative(),
        CheckCoinsCasino2 = lu16.init(0x2a9).valueNative(),
        ComparePhraseBoxInput = lu16.init(0x2aa).valueNative(),
        StoreSealNum = lu16.init(0x2ab).valueNative(),
        ActivateMysteryGift = lu16.init(0x2ac).valueNative(),
        CheckFollowBattle = lu16.init(0x2ad).valueNative(),
        Cmd_2af = lu16.init(0x2af).valueNative(),
        Cmd_2b0 = lu16.init(0x2b0).valueNative(),
        Cmd_2b1 = lu16.init(0x2b1).valueNative(),
        Cmd_2b2 = lu16.init(0x2b2).valueNative(),
        SetvarSealRandom = lu16.init(0x2b3).valueNative(),
        DarkraiFunction = lu16.init(0x2b5).valueNative(),
        Cmd_2b6 = lu16.init(0x2b6).valueNative(),
        StorePokeNumParty = lu16.init(0x2b7).valueNative(),
        StorePokeNickname = lu16.init(0x2b8).valueNative(),
        CloseMultiUnion = lu16.init(0x2b9).valueNative(),
        CheckBattleUnion = lu16.init(0x2ba).valueNative(),
        Cmd_2BB = lu16.init(0x2bb).valueNative(),
        CheckWildBattle2 = lu16.init(0x2bc).valueNative(),
        WildBattle2 = lu16.init(0x2bd).valueNative(),
        StoreTrainerCardStar = lu16.init(0x2be).valueNative(),
        BikeRide = lu16.init(0x2bf).valueNative(),
        Cmd_2c0 = lu16.init(0x2c0).valueNative(),
        ShowSaveBox = lu16.init(0x2c1).valueNative(),
        HideSaveBox = lu16.init(0x2c2).valueNative(),
        Cmd_2c3 = lu16.init(0x2c3).valueNative(),
        ShowBTowerSome = lu16.init(0x2c4).valueNative(),
        DeleteSavesBFactory = lu16.init(0x2c5).valueNative(),
        SpinTradeUnion = lu16.init(0x2c6).valueNative(),
        CheckVersionGame = lu16.init(0x2c7).valueNative(),
        ShowBArcadeRecors = lu16.init(0x2c8).valueNative(),
        EternaGymAnm = lu16.init(0x2c9).valueNative(),
        FloralClockAnimation = lu16.init(0x2ca).valueNative(),
        CheckPokeParty2 = lu16.init(0x2cb).valueNative(),
        CheckPokeCastle = lu16.init(0x2cc).valueNative(),
        ActTeamGalacticEvents = lu16.init(0x2cd).valueNative(),
        ChooseWirePokeBCastle = lu16.init(0x2cf).valueNative(),
        Cmd_2d0 = lu16.init(0x2d0).valueNative(),
        Cmd_2d1 = lu16.init(0x2d1).valueNative(),
        Cmd_2d2 = lu16.init(0x2d2).valueNative(),
        Cmd_2d3 = lu16.init(0x2d3).valueNative(),
        Cmd_2d4 = lu16.init(0x2d4).valueNative(),
        Cmd_2d5 = lu16.init(0x2d5).valueNative(),
        Cmd_2d6 = lu16.init(0x2d6).valueNative(),
        Cmd_2d7 = lu16.init(0x2d7).valueNative(),
        Cmd_2d8 = lu16.init(0x2d8).valueNative(),
        Cmd_2d9 = lu16.init(0x2d9).valueNative(),
        Cmd_2da = lu16.init(0x2da).valueNative(),
        Cmd_2db = lu16.init(0x2db).valueNative(),
        Cmd_2dc = lu16.init(0x2dc).valueNative(),
        Cmd_2dd = lu16.init(0x2dd).valueNative(),
        Cmd_2de = lu16.init(0x2de).valueNative(),
        Cmd_2df = lu16.init(0x2df).valueNative(),
        Cmd_2e0 = lu16.init(0x2e0).valueNative(),
        Cmd_2e1 = lu16.init(0x2e1).valueNative(),
        Cmd_2e2 = lu16.init(0x2e2).valueNative(),
        Cmd_2e3 = lu16.init(0x2e3).valueNative(),
        Cmd_2e4 = lu16.init(0x2e4).valueNative(),
        Cmd_2e5 = lu16.init(0x2e5).valueNative(),
        Cmd_2e6 = lu16.init(0x2e6).valueNative(),
        Cmd_2e7 = lu16.init(0x2e7).valueNative(),
        Cmd_2e8 = lu16.init(0x2e8).valueNative(),
        Cmd_2e9 = lu16.init(0x2e9).valueNative(),
        Cmd_2ea = lu16.init(0x2ea).valueNative(),
        Cmd_2eb = lu16.init(0x2eb).valueNative(),
        Cmd_2ec = lu16.init(0x2ec).valueNative(),
        Cmd_2ed = lu16.init(0x2ed).valueNative(),
        Cmd_2ee = lu16.init(0x2ee).valueNative(),
        Cmd_2f0 = lu16.init(0x2f0).valueNative(),
        Cmd_2f2 = lu16.init(0x2f2).valueNative(),
        Cmd_2f3 = lu16.init(0x2f3).valueNative(),
        Cmd_2f4 = lu16.init(0x2f4).valueNative(),
        Cmd_2f5 = lu16.init(0x2f5).valueNative(),
        Cmd_2f6 = lu16.init(0x2f6).valueNative(),
        Cmd_2f7 = lu16.init(0x2f7).valueNative(),
        Cmd_2f8 = lu16.init(0x2f8).valueNative(),
        Cmd_2f9 = lu16.init(0x2f9).valueNative(),
        Cmd_2fa = lu16.init(0x2fa).valueNative(),
        Cmd_2fb = lu16.init(0x2fb).valueNative(),
        Cmd_2fc = lu16.init(0x2fc).valueNative(),
        Cmd_2fd = lu16.init(0x2fd).valueNative(),
        Cmd_2fe = lu16.init(0x2fe).valueNative(),
        Cmd_2ff = lu16.init(0x2ff).valueNative(),
        Cmd_300 = lu16.init(0x300).valueNative(),
        Cmd_302 = lu16.init(0x302).valueNative(),
        Cmd_303 = lu16.init(0x303).valueNative(),
        Cmd_304 = lu16.init(0x304).valueNative(),
        Cmd_305 = lu16.init(0x305).valueNative(),
        Cmd_306 = lu16.init(0x306).valueNative(),
        Cmd_307 = lu16.init(0x307).valueNative(),
        Cmd_308 = lu16.init(0x308).valueNative(),
        Cmd_309 = lu16.init(0x309).valueNative(),
        Cmd_30a = lu16.init(0x30a).valueNative(),
        Cmd_30b = lu16.init(0x30b).valueNative(),
        Cmd_30c = lu16.init(0x30c).valueNative(),
        Cmd_30d = lu16.init(0x30d).valueNative(),
        Cmd_30e = lu16.init(0x30e).valueNative(),
        Cmd_30f = lu16.init(0x30f).valueNative(),
        Cmd_310 = lu16.init(0x310).valueNative(),
        Cmd_311 = lu16.init(0x311).valueNative(),
        Cmd_312 = lu16.init(0x312).valueNative(),
        Cmd_313 = lu16.init(0x313).valueNative(),
        Cmd_314 = lu16.init(0x314).valueNative(),
        Cmd_315 = lu16.init(0x315).valueNative(),
        Cmd_316 = lu16.init(0x316).valueNative(),
        Cmd_317 = lu16.init(0x317).valueNative(),
        WildBattle3 = lu16.init(0x318).valueNative(),
        Cmd_319 = lu16.init(0x319).valueNative(),
        Cmd_31a = lu16.init(0x31a).valueNative(),
        Cmd_31b = lu16.init(0x31b).valueNative(),
        Cmd_31c = lu16.init(0x31c).valueNative(),
        Cmd_31d = lu16.init(0x31d).valueNative(),
        Cmd_31e = lu16.init(0x31e).valueNative(),
        Cmd_31f = lu16.init(0x31f).valueNative(),
        Cmd_320 = lu16.init(0x320).valueNative(),
        Cmd_321 = lu16.init(0x321).valueNative(),
        Cmd_322 = lu16.init(0x322).valueNative(),
        Cmd_323 = lu16.init(0x323).valueNative(),
        Cmd_324 = lu16.init(0x324).valueNative(),
        Cmd_325 = lu16.init(0x325).valueNative(),
        Cmd_326 = lu16.init(0x326).valueNative(),
        Cmd_327 = lu16.init(0x327).valueNative(),
        PortalEffect = lu16.init(0x328).valueNative(),
        Cmd_329 = lu16.init(0x329).valueNative(),
        Cmd_32a = lu16.init(0x32a).valueNative(),
        Cmd_32b = lu16.init(0x32b).valueNative(),
        Cmd_32c = lu16.init(0x32c).valueNative(),
        Cmd_32d = lu16.init(0x32d).valueNative(),
        Cmd_32e = lu16.init(0x32e).valueNative(),
        Cmd_32f = lu16.init(0x32f).valueNative(),
        Cmd_330 = lu16.init(0x330).valueNative(),
        Cmd_331 = lu16.init(0x331).valueNative(),
        Cmd_332 = lu16.init(0x332).valueNative(),
        Cmd_333 = lu16.init(0x333).valueNative(),
        Cmd_334 = lu16.init(0x334).valueNative(),
        Cmd_335 = lu16.init(0x335).valueNative(),
        Cmd_336 = lu16.init(0x336).valueNative(),
        Cmd_337 = lu16.init(0x337).valueNative(),
        Cmd_338 = lu16.init(0x338).valueNative(),
        Cmd_339 = lu16.init(0x339).valueNative(),
        Cmd_33a = lu16.init(0x33a).valueNative(),
        Cmd_33c = lu16.init(0x33c).valueNative(),
        Cmd_33d = lu16.init(0x33d).valueNative(),
        Cmd_33e = lu16.init(0x33e).valueNative(),
        Cmd_33f = lu16.init(0x33f).valueNative(),
        Cmd_340 = lu16.init(0x340).valueNative(),
        Cmd_341 = lu16.init(0x341).valueNative(),
        Cmd_342 = lu16.init(0x342).valueNative(),
        Cmd_343 = lu16.init(0x343).valueNative(),
        Cmd_344 = lu16.init(0x344).valueNative(),
        Cmd_345 = lu16.init(0x345).valueNative(),
        Cmd_346 = lu16.init(0x346).valueNative(),
        DisplayFloor = lu16.init(0x347).valueNative(),
    };
    pub const Nop0 = packed struct {};
    pub const Nop1 = packed struct {};
    pub const End = packed struct {};
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
    pub const ExitStandard = packed struct {};
    pub const Jump = packed struct {
        adr: li32,
    };
    pub const Call = packed struct {
        adr: li32,
    };
    pub const Return = packed struct {};
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
    pub const Cmd_30 = packed struct {};
    pub const WaitButton = packed struct {};
    pub const Cmd_32 = packed struct {};
    pub const Cmd_33 = packed struct {};
    pub const CloseMsgOnKeyPress = packed struct {};
    pub const FreezeMessageBox = packed struct {};
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
    pub const NoMapMessageBox = packed struct {};
    pub const CallTextMsgBox = packed struct {
        a: u8,
        b: lu16,
    };
    pub const StoreMenuStatus = packed struct {
        a: lu16,
    };
    pub const ShowMenu = packed struct {};
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
    pub const CloseMulti = packed struct {};
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
    pub const CloseMulti4 = packed struct {};
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
    pub const WaitCry = packed struct {};
    pub const Soundfr = packed struct {
        a: lu16,
    };
    pub const Cmd_4f = packed struct {};
    pub const PlaySound = packed struct {
        a: lu16,
    };
    pub const Stop = packed struct {
        a: lu16,
    };
    pub const Restart = packed struct {};
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
    pub const ActMicrophone = packed struct {};
    pub const DeactMicrophone = packed struct {};
    pub const Cmd_5d = packed struct {};
    pub const ApplyMovement = packed struct {
        a: lu16,
        adr: lu32,
    };
    pub const WaitMovement = packed struct {};
    pub const LockAll = packed struct {};
    pub const ReleaseAll = packed struct {};
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
    pub const ZoomCam = packed struct {};
    pub const FacePlayer = packed struct {};
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
    pub const HideMoney = packed struct {};
    pub const UpdateMoney = packed struct {};
    pub const ShowCoins = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const HideCoins = packed struct {};
    pub const UpdateCoins = packed struct {};
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
        pkmn: lu16,
        lvl: lu16,
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
    pub const Cmd_9c = packed struct {};
    pub const Cmd_9d = packed struct {};
    pub const Cmd_9e = packed struct {};
    pub const Cmd_9f = packed struct {};
    pub const Cmd_a0 = packed struct {};
    pub const CallEnd = packed struct {};
    pub const Cmd_A2 = packed struct {};
    pub const Wfc_ = packed struct {};
    pub const Cmd_a4 = packed struct {
        a: lu16,
    };
    pub const Interview = packed struct {};
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
    pub const OpenBallCapsule = packed struct {};
    pub const OpenSinnohMaps = packed struct {};
    pub const OpenPcFunction = packed struct {
        a: u8,
    };
    pub const DrawUnion = packed struct {};
    pub const TrainerCaseUnion = packed struct {};
    pub const TradeUnion = packed struct {};
    pub const RecordMixingUnion = packed struct {};
    pub const EndGame = packed struct {};
    pub const HallFameAnm = packed struct {};
    pub const StoreWfcStatus = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const StartWfc = packed struct {
        a: lu16,
    };
    pub const ChooseStarter = packed struct {};
    pub const BattleStarter = packed struct {};
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
    pub const ResetScreen = packed struct {};
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
    pub const FlashAnimation = packed struct {};
    pub const DefogAnimation = packed struct {};
    pub const PrepHmEffect = packed struct {
        a: lu16,
    };
    pub const Tuxedo = packed struct {};
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
    pub const StopGivePokeHiroAnm = packed struct {};
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
    pub const LostGoPc = packed struct {};
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
    pub const Cmd_f6 = packed struct {};
    pub const Pokecontest = packed struct {};
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
    pub const Cmd_100 = packed struct {};
    pub const BlackFlashEffect = packed struct {};
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
    pub const EndFlash = packed struct {};
    pub const CarpetAnm = packed struct {};
    pub const Cmd_114 = packed struct {};
    pub const Cmd_115 = packed struct {
        a: lu16,
    };
    pub const ShowLnkCntRecord = packed struct {};
    pub const Cmd_117 = packed struct {};
    pub const Cmd_118 = packed struct {};
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
    pub const ExplanationBattle = packed struct {};
    pub const HoneyTreeBattle = packed struct {};
    pub const CheckIfHoneySlathered = packed struct {
        a: lu16,
    };
    pub const RandomBattle = packed struct {};
    pub const StopRandomBattle = packed struct {};
    pub const WriteAutograph = packed struct {};
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
    pub const GivePoketch = packed struct {};
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
    pub const FriendBT2 = packed struct {};
    pub const Cmd_138 = packed struct {
        a: lu16,
    };
    pub const OpenUnionFunction2 = packed struct {
        a: lu16,
    };
    pub const StartUnion = packed struct {};
    pub const LinkClosed = packed struct {};
    pub const SetUnionFunctionId = packed struct {
        a: lu16,
    };
    pub const CloseUnionFunction = packed struct {};
    pub const CloseUnionFunction2 = packed struct {};
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
    pub const Cmd_142 = packed struct {};
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
    pub const DefeatGoPokecenter = packed struct {};
    pub const ActBike = packed struct {
        a: lu16,
    };
    pub const CheckGender = packed struct {
        a: lu16,
    };
    pub const HealPokemon = packed struct {};
    pub const DeactWireless = packed struct {};
    pub const DeleteEntry = packed struct {};
    pub const Cmd_151 = packed struct {};
    pub const UndergroundId = packed struct {
        a: lu16,
    };
    pub const UnionRoom = packed struct {};
    pub const OpenWiFiSprite = packed struct {};
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
    pub const ActivatePokedex = packed struct {};
    pub const GiveRunningShoes = packed struct {};
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
    pub const StartFollow = packed struct {};
    pub const StopFollow = packed struct {};
    pub const Cmd_164 = packed struct {};
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
    pub const ActDcareFunction = packed struct {};
    pub const StorePDCareNum = packed struct {
        a: lu16,
    };
    pub const PastoriaCityFunction = packed struct {};
    pub const PastoriaCityFunction2 = packed struct {};
    pub const HearthromeGymFunction = packed struct {};
    pub const HearthromeGymFunction2 = packed struct {};
    pub const CanalaveGymFunction = packed struct {};
    pub const VeilstoneGymFunction = packed struct {};
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
    pub const Cmd_185 = packed struct {};
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
    pub const ShowClockSave = packed struct {};
    pub const HideClockSave = packed struct {};
    pub const Cmd_18f = packed struct {
        a: lu16,
    };
    pub const SetSaveData = packed struct {
        a: lu16,
    };
    pub const ChsPokemenu = packed struct {};
    pub const ChsPokemenu2 = packed struct {};
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
    pub const UndergroundStart = packed struct {};
    pub const TakeMoneyDCare = packed struct {
        a: lu16,
    };
    pub const TakePokemonDCare = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const ActEggDayCMan = packed struct {};
    pub const DeactEggDayCMan = packed struct {};
    pub const SetVarPokeAndMoneyDCare = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const CheckMoneyDCare = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const EggAnimation = packed struct {};
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
    pub const MailBox = packed struct {};
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
    pub const ShowMoveInfo = packed struct {};
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
    pub const Cmd_1cc = packed struct {};
    pub const DeActivateLeader = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
        d: lu16,
        e: lu16,
    };
    pub const HmFunctions = packed struct {
        a: packed enum(u8) {
            @"1" = 1,
            @"2" = 2,
        },
        b: packed union {
            @"1": packed struct {},
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
    pub const ActivateBTower = packed struct {};
    pub const StoreBTowerData = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const CloseBTower = packed struct {};
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
    pub const ShowSinnohSheet = packed struct {};
    pub const ShowNationalSheet = packed struct {};
    pub const Cmd_1ec = packed struct {};
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
    pub const Cmd_1f2 = packed struct {};
    pub const Cmd_1f3 = packed struct {};
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
    pub const PreWfc = packed struct {};
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
    pub const WarpLastElevator = packed struct {};
    pub const OpenGeoNet = packed struct {};
    pub const GreatMarshBynocule = packed struct {};
    pub const StorePokeColosseumLost = packed struct {
        a: lu16,
    };
    pub const PokemonPicture = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const HidePicture = packed struct {};
    pub const Cmd_20a = packed struct {
        a: lu16,
    };
    pub const Cmd_20b = packed struct {};
    pub const Cmd_20c = packed struct {};
    pub const SetvarMtCoronet = packed struct {
        a: u8,
        b: lu16,
    };
    pub const Cmd_20e = packed struct {};
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
    pub const StartAmity = packed struct {};
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
    pub const Cmd_21b = packed struct {};
    pub const ActSwarmPoke = packed struct {
        a: u8,
    };
    pub const Cmd_21d = packed struct {
        a: packed enum(u16) {
            @"0" = lu16.init(0).valueNative(),
            @"1" = lu16.init(1).valueNative(),
            @"2" = lu16.init(2).valueNative(),
            @"3" = lu16.init(3).valueNative(),
            @"4" = lu16.init(4).valueNative(),
            @"5" = lu16.init(5).valueNative(),
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
    pub const Cmd_21e = packed struct {};
    pub const CheckMoveRemember = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_220 = packed struct {};
    pub const StorePokeRemember = packed struct {
        a: lu16,
    };
    pub const Cmd_222 = packed struct {};
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
    pub const StopTrade = packed struct {};
    pub const Cmd_22b = packed struct {};
    pub const CloseOakAssistantEvent = packed struct {};
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
        a: packed enum(u16) {
            @"0" = lu16.init(0).valueNative(),
            @"1" = lu16.init(1).valueNative(),
            @"2" = lu16.init(2).valueNative(),
            @"3" = lu16.init(3).valueNative(),
            @"4" = lu16.init(4).valueNative(),
            @"5" = lu16.init(5).valueNative(),
            @"6" = lu16.init(6).valueNative(),
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
            @"2": packed struct {},
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
        a: packed enum(u16) {
            @"1" = lu16.init(1).valueNative(),
            @"2" = lu16.init(2).valueNative(),
            @"3" = lu16.init(3).valueNative(),
            @"5" = lu16.init(5).valueNative(),
            @"6" = lu16.init(6).valueNative(),
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
    pub const Cmd_250 = packed struct {};
    pub const CheckBoxesNumber = packed struct {
        a: lu16,
    };
    pub const StopGreatMarsh = packed struct {
        a: lu16,
    };
    pub const CheckPokeCatchingShow = packed struct {
        a: lu16,
    };
    pub const CloseCatchingShow = packed struct {};
    pub const CheckCatchingShowRecords = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const SprtSave = packed struct {};
    pub const RetSprtSave = packed struct {};
    pub const ElevLgAnimation = packed struct {};
    pub const CheckElevLgAnm = packed struct {
        a: lu16,
    };
    pub const ElevIrAnm = packed struct {};
    pub const StopElevAnm = packed struct {};
    pub const CheckElevPosition = packed struct {
        a: lu16,
    };
    pub const GalactAnm = packed struct {};
    pub const GalactAnm2 = packed struct {};
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
    pub const ActContestMap = packed struct {};
    pub const Cmd_266 = packed struct {};
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
    pub const Cmd_26f = packed struct {};
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
    pub const LeagueCastleView = packed struct {};
    pub const Cmd_27b = packed struct {};
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
    pub const ActLearning = packed struct {};
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
    pub const HideBattlePointsBox = packed struct {};
    pub const UpdateBattlePointsBox = packed struct {};
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
    pub const ChooseTradePokemon = packed struct {};
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
    pub const ActivateMysteryGift = packed struct {};
    pub const CheckFollowBattle = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_2af = packed struct {
        a: lu16,
    };
    pub const Cmd_2b0 = packed struct {};
    pub const Cmd_2b1 = packed struct {};
    pub const Cmd_2b2 = packed struct {};
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
    pub const CloseMultiUnion = packed struct {};
    pub const CheckBattleUnion = packed struct {
        a: lu16,
    };
    pub const Cmd_2BB = packed struct {};
    pub const CheckWildBattle2 = packed struct {
        a: lu16,
    };
    pub const StoreTrainerCardStar = packed struct {
        a: lu16,
    };
    pub const BikeRide = packed struct {};
    pub const Cmd_2c0 = packed struct {
        a: lu16,
    };
    pub const ShowSaveBox = packed struct {};
    pub const HideSaveBox = packed struct {};
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
    pub const SpinTradeUnion = packed struct {};
    pub const CheckVersionGame = packed struct {
        a: lu16,
    };
    pub const ShowBArcadeRecors = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
    };
    pub const EternaGymAnm = packed struct {};
    pub const FloralClockAnimation = packed struct {};
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
    pub const Cmd_2d6 = packed struct {};
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
    pub const Cmd_2e2 = packed struct {};
    pub const Cmd_2e3 = packed struct {};
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
    pub const Cmd_2ed = packed struct {};
    pub const Cmd_2ee = packed struct {
        a: lu16,
        b: lu16,
        c: lu16,
        d: lu16,
    };
    pub const Cmd_2f0 = packed struct {};
    pub const Cmd_2f2 = packed struct {};
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
    pub const Cmd_2f8 = packed struct {};
    pub const Cmd_2f9 = packed struct {
        a: lu16,
    };
    pub const Cmd_2fa = packed struct {
        a: lu16,
    };
    pub const Cmd_2fb = packed struct {};
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
    pub const Cmd_300 = packed struct {};
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
    pub const Cmd_309 = packed struct {};
    pub const Cmd_30a = packed struct {
        a: lu16,
    };
    pub const Cmd_30b = packed struct {};
    pub const Cmd_30c = packed struct {};
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
    pub const Cmd_310 = packed struct {};
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
    pub const Cmd_316 = packed struct {};
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
    pub const Cmd_31f = packed struct {};
    pub const Cmd_320 = packed struct {};
    pub const Cmd_321 = packed struct {
        a: lu16,
    };
    pub const Cmd_322 = packed struct {};
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
    pub const Cmd_32d = packed struct {};
    pub const Cmd_32e = packed struct {};
    pub const Cmd_32f = packed struct {
        a: lu16,
        b: lu16,
    };
    pub const Cmd_330 = packed struct {};
    pub const Cmd_331 = packed struct {};
    pub const Cmd_332 = packed struct {};
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
    pub const Cmd_338 = packed struct {};
    pub const Cmd_339 = packed struct {};
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

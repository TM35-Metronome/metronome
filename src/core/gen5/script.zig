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
            Command.Kind.Jump,
            => return true,
            else => return false,
        }
    }
}.isEnd);

pub const Command = packed struct {
    tag: Kind,
    data: extern union {
        End: End,
        ReturnAfterDelay: ReturnAfterDelay,
        CallRoutine: CallRoutine,
        EndFunction: EndFunction,
        Logic06: Logic06,
        Logic07: Logic07,
        CompareTo: CompareTo,
        StoreVar: StoreVar,
        ClearVar: ClearVar,
        Unknown_0B: Unknown_0B,
        Unknown_0C: Unknown_0C,
        Unknown_0D: Unknown_0D,
        Unknown_0E: Unknown_0E,
        Unknown_0F: Unknown_0F,
        StoreFlag: StoreFlag,
        Condition: Condition,
        Unknown_12: Unknown_12,
        Unknown_13: Unknown_13,
        Unknown_14: Unknown_14,
        Unknown_16: Unknown_16,
        Unknown_17: Unknown_17,
        Compare: Compare,
        CallStd: CallStd,
        ReturnStd: ReturnStd,
        Jump: Jump,
        If: If,
        Unknown_21: Unknown_21,
        Unknown_22: Unknown_22,
        SetFlag: SetFlag,
        ClearFlag: ClearFlag,
        SetVarFlagStatus: SetVarFlagStatus,
        SetVar26: SetVar26,
        SetVar27: SetVar27,
        SetVarEqVal: SetVarEqVal,
        SetVar29: SetVar29,
        SetVar2A: SetVar2A,
        SetVar2B: SetVar2B,
        Unknown_2D: Unknown_2D,
        LockAll: LockAll,
        UnlockAll: UnlockAll,
        WaitMoment: WaitMoment,
        WaitButton: WaitButton,
        MusicalMessage: MusicalMessage,
        EventGreyMessage: EventGreyMessage,
        CloseMusicalMessage: CloseMusicalMessage,
        ClosedEventGreyMessage: ClosedEventGreyMessage,
        BubbleMessage: BubbleMessage,
        CloseBubbleMessage: CloseBubbleMessage,
        ShowMessageAt: ShowMessageAt,
        CloseShowMessageAt: CloseShowMessageAt,
        Message: Message,
        Message2: Message2,
        CloseMessageKP: CloseMessageKP,
        CloseMessageKP2: CloseMessageKP2,
        MoneyBox: MoneyBox,
        CloseMoneyBox: CloseMoneyBox,
        UpdateMoneyBox: UpdateMoneyBox,
        BorderedMessage: BorderedMessage,
        CloseBorderedMessage: CloseBorderedMessage,
        PaperMessage: PaperMessage,
        ClosePaperMessage: ClosePaperMessage,
        YesNo: YesNo,
        Message3: Message3,
        DoubleMessage: DoubleMessage,
        AngryMessage: AngryMessage,
        CloseAngryMessage: CloseAngryMessage,
        SetVarHero: SetVarHero,
        SetVarItem: SetVarItem,
        unknown_4E: unknown_4E,
        SetVarItem2: SetVarItem2,
        SetVarItem3: SetVarItem3,
        SetVarMove: SetVarMove,
        SetVarBag: SetVarBag,
        SetVarPartyPoke: SetVarPartyPoke,
        SetVarPartyPoke2: SetVarPartyPoke2,
        SetVar_Unknown: SetVar_Unknown,
        SetVarType: SetVarType,
        SetVarPoke: SetVarPoke,
        SetVarPoke2: SetVarPoke2,
        SetVarLocation: SetVarLocation,
        SetVarPokeNick: SetVarPokeNick,
        SetVar_Unknown2: SetVar_Unknown2,
        SetVarStoreValue5C: SetVarStoreValue5C,
        SetVarMusicalInfo: SetVarMusicalInfo,
        SetVarNations: SetVarNations,
        SetVarActivities: SetVarActivities,
        SetVarPower: SetVarPower,
        SetVarTrainerType: SetVarTrainerType,
        SetVarTrainerType2: SetVarTrainerType2,
        SetVarGeneralWord: SetVarGeneralWord,
        ApplyMovement: ApplyMovement,
        WaitMovement: WaitMovement,
        StoreHeroPosition: StoreHeroPosition,
        Unknown_67: Unknown_67,
        StoreHeroPosition2: StoreHeroPosition2,
        StoreNPCPosition: StoreNPCPosition,
        Unknown_6A: Unknown_6A,
        AddNPC: AddNPC,
        RemoveNPC: RemoveNPC,
        SetOWPosition: SetOWPosition,
        Unknown_6E: Unknown_6E,
        Unknown_6F: Unknown_6F,
        Unknown_70: Unknown_70,
        Unknown_71: Unknown_71,
        Unknown_72: Unknown_72,
        Unknown_73: Unknown_73,
        FacePlayer: FacePlayer,
        Release: Release,
        ReleaseAll: ReleaseAll,
        Lock: Lock,
        Unknown_78: Unknown_78,
        Unknown_79: Unknown_79,
        MoveNPCTo: MoveNPCTo,
        Unknown_7C: Unknown_7C,
        Unknown_7D: Unknown_7D,
        TeleportUpNPC: TeleportUpNPC,
        Unknown_7F: Unknown_7F,
        Unknown_80: Unknown_80,
        Unknown_81: Unknown_81,
        Unknown_82: Unknown_82,
        SetVar83: SetVar83,
        SetVar84: SetVar84,
        SingleTrainerBattle: SingleTrainerBattle,
        DoubleTrainerBattle: DoubleTrainerBattle,
        Unknown_87: Unknown_87,
        Unknown_88: Unknown_88,
        Unknown_8A: Unknown_8A,
        PlayTrainerMusic: PlayTrainerMusic,
        EndBattle: EndBattle,
        StoreBattleResult: StoreBattleResult,
        DisableTrainer: DisableTrainer,
        DVar90: DVar90,
        DVar92: DVar92,
        DVar93: DVar93,
        TrainerBattle: TrainerBattle,
        DeactivateTrainerID: DeactivateTrainerID,
        Unknown_96: Unknown_96,
        StoreActiveTrainerID: StoreActiveTrainerID,
        ChangeMusic: ChangeMusic,
        FadeToDefaultMusic: FadeToDefaultMusic,
        Unknown_9F: Unknown_9F,
        Unknown_A2: Unknown_A2,
        Unknown_A3: Unknown_A3,
        Unknown_A4: Unknown_A4,
        Unknown_A5: Unknown_A5,
        PlaySound: PlaySound,
        WaitSoundA7: WaitSoundA7,
        WaitSound: WaitSound,
        PlayFanfare: PlayFanfare,
        WaitFanfare: WaitFanfare,
        PlayCry: PlayCry,
        WaitCry: WaitCry,
        SetTextScriptMessage: SetTextScriptMessage,
        CloseMulti: CloseMulti,
        Unknown_B1: Unknown_B1,
        Multi2: Multi2,
        FadeScreen: FadeScreen,
        ResetScreen: ResetScreen,
        Screen_B5: Screen_B5,
        TakeItem: TakeItem,
        CheckItemBagSpace: CheckItemBagSpace,
        CheckItemBagNumber: CheckItemBagNumber,
        StoreItemCount: StoreItemCount,
        Unknown_BA: Unknown_BA,
        Unknown_BB: Unknown_BB,
        Unknown_BC: Unknown_BC,
        Warp: Warp,
        TeleportWarp: TeleportWarp,
        FallWarp: FallWarp,
        FastWarp: FastWarp,
        UnionWarp: UnionWarp,
        TeleportWarp2: TeleportWarp2,
        SurfAnimation: SurfAnimation,
        SpecialAnimation: SpecialAnimation,
        SpecialAnimation2: SpecialAnimation2,
        CallAnimation: CallAnimation,
        StoreRandomNumber: StoreRandomNumber,
        StoreVarItem: StoreVarItem,
        StoreVar_CD: StoreVar_CD,
        StoreVar_CE: StoreVar_CE,
        StoreVar_CF: StoreVar_CF,
        StoreDate: StoreDate,
        Store_D1: Store_D1,
        Store_D2: Store_D2,
        Store_D3: Store_D3,
        StoreBirthDay: StoreBirthDay,
        StoreBadge: StoreBadge,
        SetBadge: SetBadge,
        StoreBadgeNumber: StoreBadgeNumber,
        CheckMoney: CheckMoney,
        GivePokemon: GivePokemon,
        BootPCSound: BootPCSound,
        WildBattle: WildBattle,
        FadeIntoBlack: FadeIntoBlack,
    },
    pub const Kind = packed enum(u16) {
        End = lu16.init(0x02).value(),
        ReturnAfterDelay = lu16.init(0x03).value(),
        CallRoutine = lu16.init(0x04).value(),
        EndFunction = lu16.init(0x05).value(),
        Logic06 = lu16.init(0x06).value(),
        Logic07 = lu16.init(0x07).value(),
        CompareTo = lu16.init(0x08).value(),
        StoreVar = lu16.init(0x09).value(),
        ClearVar = lu16.init(0x0A).value(),
        Unknown_0B = lu16.init(0x0B).value(),
        Unknown_0C = lu16.init(0x0C).value(),
        Unknown_0D = lu16.init(0x0D).value(),
        Unknown_0E = lu16.init(0x0E).value(),
        Unknown_0F = lu16.init(0x0F).value(),
        StoreFlag = lu16.init(0x10).value(),
        Condition = lu16.init(0x11).value(),
        Unknown_12 = lu16.init(0x12).value(),
        Unknown_13 = lu16.init(0x13).value(),
        Unknown_14 = lu16.init(0x14).value(),
        Unknown_16 = lu16.init(0x16).value(),
        Unknown_17 = lu16.init(0x17).value(),
        Compare = lu16.init(0x19).value(),
        CallStd = lu16.init(0x1C).value(),
        ReturnStd = lu16.init(0x1D).value(),
        Jump = lu16.init(0x1E).value(),
        If = lu16.init(0x1F).value(),
        Unknown_21 = lu16.init(0x21).value(),
        Unknown_22 = lu16.init(0x22).value(),
        SetFlag = lu16.init(0x23).value(),
        ClearFlag = lu16.init(0x24).value(),
        SetVarFlagStatus = lu16.init(0x25).value(),
        SetVar26 = lu16.init(0x26).value(),
        SetVar27 = lu16.init(0x27).value(),
        SetVarEqVal = lu16.init(0x28).value(),
        SetVar29 = lu16.init(0x29).value(),
        SetVar2A = lu16.init(0x2A).value(),
        SetVar2B = lu16.init(0x2B).value(),
        Unknown_2D = lu16.init(0x2D).value(),
        LockAll = lu16.init(0x2E).value(),
        UnlockAll = lu16.init(0x2F).value(),
        WaitMoment = lu16.init(0x30).value(),
        WaitButton = lu16.init(0x32).value(),
        MusicalMessage = lu16.init(0x33).value(),
        EventGreyMessage = lu16.init(0x34).value(),
        CloseMusicalMessage = lu16.init(0x35).value(),
        ClosedEventGreyMessage = lu16.init(0x36).value(),
        BubbleMessage = lu16.init(0x38).value(),
        CloseBubbleMessage = lu16.init(0x39).value(),
        ShowMessageAt = lu16.init(0x3A).value(),
        CloseShowMessageAt = lu16.init(0x3B).value(),
        Message = lu16.init(0x3C).value(),
        Message2 = lu16.init(0x3D).value(),
        CloseMessageKP = lu16.init(0x3E).value(),
        CloseMessageKP2 = lu16.init(0x3F).value(),
        MoneyBox = lu16.init(0x40).value(),
        CloseMoneyBox = lu16.init(0x41).value(),
        UpdateMoneyBox = lu16.init(0x42).value(),
        BorderedMessage = lu16.init(0x43).value(),
        CloseBorderedMessage = lu16.init(0x44).value(),
        PaperMessage = lu16.init(0x45).value(),
        ClosePaperMessage = lu16.init(0x46).value(),
        YesNo = lu16.init(0x47).value(),
        Message3 = lu16.init(0x48).value(),
        DoubleMessage = lu16.init(0x49).value(),
        AngryMessage = lu16.init(0x4A).value(),
        CloseAngryMessage = lu16.init(0x4B).value(),
        SetVarHero = lu16.init(0x4C).value(),
        SetVarItem = lu16.init(0x4D).value(),
        unknown_4E = lu16.init(0x4E).value(),
        SetVarItem2 = lu16.init(0x4F).value(),
        SetVarItem3 = lu16.init(0x50).value(),
        SetVarMove = lu16.init(0x51).value(),
        SetVarBag = lu16.init(0x52).value(),
        SetVarPartyPoke = lu16.init(0x53).value(),
        SetVarPartyPoke2 = lu16.init(0x54).value(),
        SetVar_Unknown = lu16.init(0x55).value(),
        SetVarType = lu16.init(0x56).value(),
        SetVarPoke = lu16.init(0x57).value(),
        SetVarPoke2 = lu16.init(0x58).value(),
        SetVarLocation = lu16.init(0x59).value(),
        SetVarPokeNick = lu16.init(0x5A).value(),
        SetVar_Unknown2 = lu16.init(0x5B).value(),
        SetVarStoreValue5C = lu16.init(0x5C).value(),
        SetVarMusicalInfo = lu16.init(0x5D).value(),
        SetVarNations = lu16.init(0x5E).value(),
        SetVarActivities = lu16.init(0x5F).value(),
        SetVarPower = lu16.init(0x60).value(),
        SetVarTrainerType = lu16.init(0x61).value(),
        SetVarTrainerType2 = lu16.init(0x62).value(),
        SetVarGeneralWord = lu16.init(0x63).value(),
        ApplyMovement = lu16.init(0x64).value(),
        WaitMovement = lu16.init(0x65).value(),
        StoreHeroPosition = lu16.init(0x66).value(),
        Unknown_67 = lu16.init(0x67).value(),
        StoreHeroPosition2 = lu16.init(0x68).value(),
        StoreNPCPosition = lu16.init(0x69).value(),
        Unknown_6A = lu16.init(0x6A).value(),
        AddNPC = lu16.init(0x6B).value(),
        RemoveNPC = lu16.init(0x6C).value(),
        SetOWPosition = lu16.init(0x6D).value(),
        Unknown_6E = lu16.init(0x6E).value(),
        Unknown_6F = lu16.init(0x6F).value(),
        Unknown_70 = lu16.init(0x70).value(),
        Unknown_71 = lu16.init(0x71).value(),
        Unknown_72 = lu16.init(0x72).value(),
        Unknown_73 = lu16.init(0x73).value(),
        FacePlayer = lu16.init(0x74).value(),
        Release = lu16.init(0x75).value(),
        ReleaseAll = lu16.init(0x76).value(),
        Lock = lu16.init(0x77).value(),
        Unknown_78 = lu16.init(0x78).value(),
        Unknown_79 = lu16.init(0x79).value(),
        MoveNPCTo = lu16.init(0x7B).value(),
        Unknown_7C = lu16.init(0x7C).value(),
        Unknown_7D = lu16.init(0x7D).value(),
        TeleportUpNPC = lu16.init(0x7E).value(),
        Unknown_7F = lu16.init(0x7F).value(),
        Unknown_80 = lu16.init(0x80).value(),
        Unknown_81 = lu16.init(0x81).value(),
        Unknown_82 = lu16.init(0x82).value(),
        SetVar83 = lu16.init(0x83).value(),
        SetVar84 = lu16.init(0x84).value(),
        SingleTrainerBattle = lu16.init(0x85).value(),
        DoubleTrainerBattle = lu16.init(0x86).value(),
        Unknown_87 = lu16.init(0x87).value(),
        Unknown_88 = lu16.init(0x88).value(),
        Unknown_8A = lu16.init(0x8A).value(),
        PlayTrainerMusic = lu16.init(0x8B).value(),
        EndBattle = lu16.init(0x8C).value(),
        StoreBattleResult = lu16.init(0x8D).value(),
        DisableTrainer = lu16.init(0x8E).value(),
        DVar90 = lu16.init(0x90).value(),
        DVar92 = lu16.init(0x92).value(),
        DVar93 = lu16.init(0x93).value(),
        TrainerBattle = lu16.init(0x94).value(),
        DeactivateTrainerID = lu16.init(0x95).value(),
        Unknown_96 = lu16.init(0x96).value(),
        StoreActiveTrainerID = lu16.init(0x97).value(),
        ChangeMusic = lu16.init(0x98).value(),
        FadeToDefaultMusic = lu16.init(0x9E).value(),
        Unknown_9F = lu16.init(0x9F).value(),
        Unknown_A2 = lu16.init(0xA2).value(),
        Unknown_A3 = lu16.init(0xA3).value(),
        Unknown_A4 = lu16.init(0xA4).value(),
        Unknown_A5 = lu16.init(0xA5).value(),
        PlaySound = lu16.init(0xA6).value(),
        WaitSoundA7 = lu16.init(0xA7).value(),
        WaitSound = lu16.init(0xA8).value(),
        PlayFanfare = lu16.init(0xA9).value(),
        WaitFanfare = lu16.init(0xAA).value(),
        PlayCry = lu16.init(0xAB).value(),
        WaitCry = lu16.init(0xAC).value(),
        SetTextScriptMessage = lu16.init(0xAF).value(),
        CloseMulti = lu16.init(0xB0).value(),
        Unknown_B1 = lu16.init(0xB1).value(),
        Multi2 = lu16.init(0xB2).value(),
        FadeScreen = lu16.init(0xB3).value(),
        ResetScreen = lu16.init(0xB4).value(),
        Screen_B5 = lu16.init(0xB5).value(),
        TakeItem = lu16.init(0xB6).value(),
        CheckItemBagSpace = lu16.init(0xB7).value(),
        CheckItemBagNumber = lu16.init(0xB8).value(),
        StoreItemCount = lu16.init(0xB9).value(),
        Unknown_BA = lu16.init(0xBA).value(),
        Unknown_BB = lu16.init(0xBB).value(),
        Unknown_BC = lu16.init(0xBC).value(),
        Warp = lu16.init(0xBE).value(),
        TeleportWarp = lu16.init(0xBF).value(),
        FallWarp = lu16.init(0xC1).value(),
        FastWarp = lu16.init(0xC2).value(),
        UnionWarp = lu16.init(0xC3).value(),
        TeleportWarp2 = lu16.init(0xC4).value(),
        SurfAnimation = lu16.init(0xC5).value(),
        SpecialAnimation = lu16.init(0xC6).value(),
        SpecialAnimation2 = lu16.init(0xC7).value(),
        CallAnimation = lu16.init(0xC8).value(),
        StoreRandomNumber = lu16.init(0xCB).value(),
        StoreVarItem = lu16.init(0xCC).value(),
        StoreVar_CD = lu16.init(0xCD).value(),
        StoreVar_CE = lu16.init(0xCE).value(),
        StoreVar_CF = lu16.init(0xCF).value(),
        StoreDate = lu16.init(0xD0).value(),
        Store_D1 = lu16.init(0xD1).value(),
        Store_D2 = lu16.init(0xD2).value(),
        Store_D3 = lu16.init(0xD3).value(),
        StoreBirthDay = lu16.init(0xD4).value(),
        StoreBadge = lu16.init(0xD5).value(),
        SetBadge = lu16.init(0xD6).value(),
        StoreBadgeNumber = lu16.init(0xD7).value(),
        CheckMoney = lu16.init(0xFB).value(),
        GivePokemon = lu16.init(0x10C).value(),
        BootPCSound = lu16.init(0x130).value(),
        WildBattle = lu16.init(0x174).value(),
        FadeIntoBlack = lu16.init(0x1AC).value(),
    };
    pub const End = packed struct {};
    pub const ReturnAfterDelay = packed struct {
        arg: lu16,
    };
    pub const CallRoutine = packed struct {
        arg: li32,
    };
    pub const EndFunction = packed struct {
        arg: lu16,
    };
    pub const Logic06 = packed struct {
        arg: lu16,
    };
    pub const Logic07 = packed struct {
        arg: lu16,
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
    pub const ReturnStd = packed struct {};
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
    pub const LockAll = packed struct {};
    pub const UnlockAll = packed struct {};
    pub const WaitMoment = packed struct {};
    pub const WaitButton = packed struct {};
    pub const MusicalMessage = packed struct {
        id: lu16,
    };
    pub const EventGreyMessage = packed struct {
        id: lu16,
        location: u8,
    };
    pub const CloseMusicalMessage = packed struct {};
    pub const ClosedEventGreyMessage = packed struct {};
    pub const BubbleMessage = packed struct {
        id: lu16,
        location: u8,
    };
    pub const CloseBubbleMessage = packed struct {};
    pub const ShowMessageAt = packed struct {
        id: lu16,
        xcoord: lu16,
        ycoord: lu16,
        zcoord: lu16,
    };
    pub const CloseShowMessageAt = packed struct {};
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
    pub const CloseMessageKP = packed struct {};
    pub const CloseMessageKP2 = packed struct {};
    pub const MoneyBox = packed struct {
        xcoord: lu16,
        ycoord: lu16,
    };
    pub const CloseMoneyBox = packed struct {};
    pub const UpdateMoneyBox = packed struct {};
    pub const BorderedMessage = packed struct {
        id: lu16,
        color: lu16,
    };
    pub const CloseBorderedMessage = packed struct {};
    pub const PaperMessage = packed struct {
        id: lu16,
        transcoord: lu16,
    };
    pub const ClosePaperMessage = packed struct {};
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
    pub const CloseAngryMessage = packed struct {};
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
    pub const WaitMovement = packed struct {};
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
    pub const Unknown_6E = packed struct {
        arg: lu16,
    };
    pub const Unknown_6F = packed struct {
        arg: lu16,
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
    pub const FacePlayer = packed struct {};
    pub const Release = packed struct {
        npc: lu16,
    };
    pub const ReleaseAll = packed struct {};
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
    pub const Unknown_80 = packed struct {
        arg: lu16,
    };
    pub const Unknown_81 = packed struct {};
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
    pub const EndBattle = packed struct {};
    pub const StoreBattleResult = packed struct {
        variable: lu16,
    };
    pub const DisableTrainer = packed struct {};
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
    pub const FadeToDefaultMusic = packed struct {};
    pub const Unknown_9F = packed struct {};
    pub const Unknown_A2 = packed struct {
        sound: lu16,
        arg2: lu16,
    };
    pub const Unknown_A3 = packed struct {
        arg: lu16,
    };
    pub const Unknown_A4 = packed struct {
        arg: lu16,
    };
    pub const Unknown_A5 = packed struct {
        arg: lu16,
        arg2: lu16,
    };
    pub const PlaySound = packed struct {
        id: lu16,
    };
    pub const WaitSoundA7 = packed struct {};
    pub const WaitSound = packed struct {};
    pub const PlayFanfare = packed struct {
        id: lu16,
    };
    pub const WaitFanfare = packed struct {};
    pub const PlayCry = packed struct {
        id: lu16,
        arg2: lu16,
    };
    pub const WaitCry = packed struct {};
    pub const SetTextScriptMessage = packed struct {
        id: lu16,
        arg2: lu16,
        arg3: lu16,
    };
    pub const CloseMulti = packed struct {};
    pub const Unknown_B1 = packed struct {};
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
    pub const Unknown_BC = packed struct {
        arg: lu16,
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
    pub const UnionWarp = packed struct {};
    pub const TeleportWarp2 = packed struct {
        mapid: lu16,
        xcoord: lu16,
        ycoord: lu16,
        zcoord: lu16,
        herofacing: lu16,
    };
    pub const SurfAnimation = packed struct {};
    pub const SpecialAnimation = packed struct {
        arg: lu16,
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
    pub const StoreVarItem = packed struct {
        arg: lu16,
    };
    pub const StoreVar_CD = packed struct {
        arg: lu16,
    };
    pub const StoreVar_CE = packed struct {
        arg: lu16,
    };
    pub const StoreVar_CF = packed struct {
        arg: lu16,
    };
    pub const StoreDate = packed struct {
        month: lu16,
        date: lu16,
    };
    pub const Store_D1 = packed struct {
        arg: lu16,
        arg2: lu16,
    };
    pub const Store_D2 = packed struct {
        arg: lu16,
    };
    pub const Store_D3 = packed struct {
        arg: lu16,
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
        id: lu16,
        item: lu16,
        level: lu16,
    };
    pub const BootPCSound = packed struct {};
    pub const WildBattle = packed struct {
        species: lu16,
        level: u8,
    };
    pub const FadeIntoBlack = packed struct {};
};

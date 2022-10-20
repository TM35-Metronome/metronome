const std = @import("std");

const gen3 = @import("../gen3.zig");
const rom = @import("../rom.zig");
const script = @import("../script.zig");

const mem = std.mem;

const lu16 = rom.int.lu16;
const lu32 = rom.int.lu32;

pub const CommandDecoder = script.CommandDecoder(Command, struct {
    fn isEnd(cmd: Command) bool {
        switch (cmd.kind) {
            .end,
            .@"return",
            => return true,
            else => return false,
        }
    }
}.isEnd);

pub const STD_10 = 10;
pub const STD_FIND_ITEM = 1;
pub const STD_MSG_BOX_AUTO_CLOSE = 6;
pub const STD_MSG_BOX_DEFAULT = 4;
pub const STD_MSG_BOX_GET_POINTS = 9;
pub const STD_MSG_BOX_NPC = 2;
pub const STD_MSG_BOX_SIGN = 3;
pub const STD_MSG_BOX_YES_NO = 5;
pub const STD_OBTAIN_DECORATION = 7;
pub const STD_OBTAIN_ITEM = 0;
pub const STD_REGISTER_MATCH_CALL = 8;

pub const Command = extern union {
    kind: Kind,
    // Does nothing.
    nop: Arg0,

    // Does nothing.
    nop1: Arg0,

    // Terminates script execution.
    end: Arg0,

    // Jumps back to after the last-executed call statement, and continues script execution from there.
    @"return": Arg0,

    // Jumps to destination and continues script execution from there. The location of the calling script is remembered and can be returned to later.
    call: Jump,

    // Jumps to destination and continues script execution from there.
    goto: Jump,

    // If the result of the last comparison matches condition (see Comparison operators), jumps to destination and continues script execution from there.
    goto_if: CondJump,

    // If the result of the last comparison matches condition (see Comparison operators), calls destination.
    call_if: CondJump,

    // Jumps to the standard function at index function.
    gotostd: Func(u8),

    // Calls the standard function at index function.
    callstd: Func(u8),

    // If the result of the last comparison matches condition (see Comparison operators), jumps to the standard function at index function.
    gotostd_if: CondFunc,

    // If the result of the last comparison matches condition (see Comparison operators), calls the standard function at index function.
    callstd_if: CondFunc,

    // Executes a script stored in a default RAM location.
    gotoram: Arg0,

    // Terminates script execution and "resets the script RAM".
    killscript: Arg0,

    // Sets some status related to Mystery Event.
    setmysteryeventstatus: setmysteryeventstatus,

    // Sets the specified script bank to value.
    loadword: loadword,

    // Sets the specified script bank to value.
    loadbyte: loadbyte,

    // Sets the byte at offset to value.
    writebytetoaddr: writebytetoaddr,

    // Copies the byte value at source into the specified script bank.
    loadbytefromaddr: DestSrc(u8, lu32),

    // Not sure. Judging from XSE's description I think it takes the least-significant byte in bank source and writes it to destination.
    setptrbyte: setptrbyte,

    // Copies the contents of bank source into bank destination.
    copylocal: DestSrc(u8, u8),

    // Copies the byte at source to destination, replacing whatever byte was previously there.
    copybyte: DestSrc(lu32, lu32),

    // Changes the value of destination to value.
    setvar: DestVal,

    // Changes the value of destination by adding value to it. Overflow is not prevented (0xFFFF + 1 = 0x0000).
    addvar: DestVal,

    // Changes the value of destination by subtracting value to it. Overflow is not prevented (0x0000 - 1 = 0xFFFF).
    subvar: DestVal,

    // Copies the value of source into destination.
    copyvar: DestSrc(lu16, lu16),

    // If source is not a variable, then this function acts like setvar. Otherwise, it acts like copyvar.
    setorcopyvar: DestSrc(lu16, lu16),

    // Compares the values of script banks a and b, after forcing the values to bytes.
    compare_local_to_local: AB(u8, u8),

    // Compares the least-significant byte of the value of script bank a to a fixed byte value (b).
    compare_local_to_value: AB(u8, u8),

    // Compares the least-significant byte of the value of script bank a to the byte located at offset b.
    compare_local_to_addr: AB(u8, lu32),

    // Compares the byte located at offset a to the least-significant byte of the value of script bank b.
    compare_addr_to_local: AB(lu32, u8),

    // Compares the byte located at offset a to a fixed byte value (b).
    compare_addr_to_value: AB(lu32, u8),

    // Compares the byte located at offset a to the byte located at offset b.
    compare_addr_to_addr: AB(lu32, lu32),

    // Compares the value of `var` to a fixed word value (b).
    compare_var_to_value: compare_var_to_value,

    // Compares the value of `var1` to the value of `var2`.
    compare_var_to_var: compare_var_to_var,

    // Calls the native C function stored at `func`.
    callnative: Func(lu32),

    // Replaces the script with the function stored at `func`. Execution returns to the bytecode script when func returns TRUE.
    gotonative: Func(lu32),

    // Calls a special function; that is, a function designed for use by scripts and listed in a table of pointers.
    special: Func(lu16),

    // Calls a special function. That function's output (if any) will be written to the variable you specify.
    specialvar: specialvar,

    // Blocks script execution until a command or ASM code manually unblocks it. Generally used with specific commands and specials. If this command runs, and a subsequent command or piece of ASM does not unblock state, the script will remain blocked indefinitely (essentially a hang).
    waitstate: Arg0,

    // Blocks script execution for time (frames? milliseconds?).
    delay: delay,

    // Sets arg to 1.
    setflag: Arg1,

    // Sets arg to 0.
    clearflag: Arg1,

    // Compares arg to 1.
    checkflag: Arg1,

    // Initializes the RTC`s local time offset to the given hour and minute. In FireRed, this command is a nop.
    initclock: initclock,

    // Runs time based events. In FireRed, this command is a nop.
    dodailyevents: Arg0,

    // Sets the values of variables 0x8000, 0x8001, and 0x8002 to the current hour, minute, and second. In FRLG, this command sets those variables to zero.
    gettime: Arg0,

    // Plays the specified (sound_number) sound. Only one sound may play at a time, with newer ones interrupting older ones.
    playse: Song,

    // Blocks script execution until the currently-playing sound (triggered by playse) finishes playing.
    waitse: Arg0,

    // Plays the specified (fanfare_number) fanfare.
    playfanfare: Song,

    // Blocks script execution until all currently-playing fanfares finish.
    waitfanfare: Arg0,

    // Plays the specified (song_number) song. The byte is apparently supposed to be 0x00.
    playbgm: playbgm,

    // Saves the specified (song_number) song to be played later.
    savebgm: Song,

    // Crossfades the currently-playing song into the map's default song.
    fadedefaultbgm: Arg0,

    // Crossfades the currently-playng song into the specified (song_number) song.
    fadenewbgm: Song,

    // Fades out the currently-playing song.
    fadeoutbgm: Speed,

    // Fades the previously-playing song back in.
    fadeinbgm: Speed,

    // Sends the player to Warp warp on Map bank.map. If the specified warp is 0xFF, then the player will instead be sent to (X, Y) on the map.
    warp: Warp,

    // Clone of warp that does not play a sound effect.
    warpsilent: Warp,

    // Clone of warp that plays a door opening animation before stepping upwards into it.
    warpdoor: Warp,

    // Warps the player to another map using a hole animation.
    warphole: warphole,

    // Clone of warp that uses a teleport effect. It is apparently only used in R/S/E.
    warpteleport: Warp,

    // Sets the warp destination to be used later.
    setwarp: Warp,

    // Sets the warp destination that a warp to Warp 127 on Map 127.127 will connect to. Useful when a map has warps that need to go to script-controlled locations (i.e. elevators).
    setdynamicwarp: Warp,

    // Sets the destination that diving or emerging from a dive will take the player to.
    setdivewarp: Warp,

    // Sets the destination that falling into a hole will take the player to.
    setholewarp: Warp,

    // Retrieves the player's zero-indexed X- and Y-coordinates in the map, and stores them in the specified variables.
    getplayerxy: getplayerxy,

    // Retrieves the number of Pokemon in the player's party, and stores that number in variable 0x800D (LASTRESULT).
    getpartysize: Arg0,

    // Attempts to add quantity of item index to the player's Bag. If the player has enough room, the item will be added and variable 0x800D (LASTRESULT) will be set to 0x0001; otherwise, LASTRESULT is set to 0x0000.
    additem: additem,

    // Removes quantity of item index from the player's Bag.
    removeitem: removeitem,

    // Checks if the player has enough space in their Bag to hold quantity more of item index. Sets variable 0x800D (LASTRESULT) to 0x0001 if there is room, or 0x0000 is there is no room.
    checkitemspace: checkitemspace,

    // Checks if the player has quantity or more of item index in their Bag. Sets variable 0x800D (LASTRESULT) to 0x0001 if the player has enough of the item, or 0x0000 if they have fewer than quantity of the item.
    checkitem: checkitem,

    // Checks which Bag pocket the specified (index) item belongs in, and writes the value to variable 0x800D (LASTRESULT). This script is used to show the name of the proper Bag pocket when the player receives an item via callstd (simplified to giveitem in XSE).
    checkitemtype: checkitemtype,

    // Adds a quantity amount of item index to the player's PC. Both arguments can be variables.
    givepcitem: givepcitem,

    // Checks for quantity amount of item index in the player's PC. Both arguments can be variables.
    checkpcitem: checkpcitem,

    // Adds decoration to the player's PC. In FireRed, this command is a nop. (The argument is read, but not used for anything.)
    givedecoration: givedecoration,

    // Removes a decoration from the player's PC. In FireRed, this command is a nop. (The argument is read, but not used for anything.)
    takedecoration: takedecoration,

    // Checks for decoration in the player's PC. In FireRed, this command is a nop. (The argument is read, but not used for anything.)
    checkdecor: checkdecor,

    // Checks if the player has enough space in their PC to hold decoration. Sets variable 0x800D (LASTRESULT) to 0x0001 if there is room, or 0x0000 is there is no room. In FireRed, this command is a nop. (The argument is read, but not used for anything.)
    checkdecorspace: checkdecorspace,

    // Applies the movement data at movements to the specified (index) Object. Also closes any standard message boxes that are still open.
    // If no map is specified, then the current map is used.
    applymovement: applymovement,

    // Really only useful if the object has followed from one map to another (e.g. Wally during the catching event).
    applymovementmap: applymovementmap,

    // Blocks script execution until the movements being applied to the specified (index) Object finish. If the specified Object is 0x0000, then the command will block script execution until all Objects affected by applymovement finish their movements. If the specified Object is not currently being manipulated with applymovement, then this command does nothing.
    // If no map is specified, then the current map is used.
    waitmovement: waitmovement,
    waitmovementmap: waitmovementmap,

    // Attempts to hide the specified (index) Object on the specified (map_group, map_num) map, by setting its visibility flag if it has a valid one. If the Object does not have a valid visibility flag, this command does nothing.
    // If no map is specified, then the current map is used.
    removeobject: removeobject,
    removeobjectmap: removeobjectmap,

    // Unsets the specified (index) Object's visibility flag on the specified (map_group, map_num) map if it has a valid one. If the Object does not have a valid visibility flag, this command does nothing.
    // If no map is specified, then the current map is used.
    addobject: addobject,
    addobjectmap: addobjectmap,

    // Sets the specified (index) Object's position on the current map.
    setobjectxy: setobjectxy,
    showobjectat: showobjectat,
    hideobjectat: hideobjectat,

    // If the script was called by an Object, then that Object will turn to face toward the metatile that the player is standing on.
    faceplayer: Arg0,
    turnobject: turnobject,

    // If the Trainer flag for Trainer index is not set, this command does absolutely nothing.
    trainerbattle: trainerbattle,

    // Starts a trainer battle using the battle information stored in RAM (usually by trainerbattle, which actually calls this command behind-the-scenes), and blocks script execution until the battle finishes.
    trainerbattlebegin: Arg0,

    // Goes to address after the trainerbattle command (called by the battle functions, see battle_setup.c)
    gotopostbattlescript: Arg0,

    // Goes to address specified in the trainerbattle command (called by the battle functions, see battle_setup.c)
    gotobeatenscript: Arg0,

    // Compares Flag (trainer + 0x500) to 1. (If the flag is set, then the trainer has been defeated by the player.)
    checktrainerflag: Trainer,

    // Sets Flag (trainer + 0x500).
    settrainerflag: Trainer,

    // Clears Flag (trainer + 0x500).
    cleartrainerflag: Trainer,
    setobjectxyperm: setobjectxyperm,
    moveobjectoffscreen: moveobjectoffscreen,
    setobjectmovementtype: setobjectmovementtype,

    // If a standard message box (or its text) is being drawn on-screen, this command blocks script execution until the box and its text have been fully drawn.
    waitmessage: Arg0,

    // Starts displaying a standard message box containing the specified text. If text is a pointer, then the string at that offset will be loaded and used. If text is script bank 0, then the value of script bank 0 will be treated as a pointer to the text. (You can use loadpointer to place a string pointer in a script bank.)
    message: message,

    // Closes the current message box.
    closemessage: Arg0,

    // Ceases movement for all Objects on-screen.
    lockall: Arg0,

    // If the script was called by an Object, then that Object's movement will cease.
    lock: Arg0,

    // Resumes normal movement for all Objects on-screen, and closes any standard message boxes that are still open.
    releaseall: Arg0,

    // If the script was called by an Object, then that Object's movement will resume. This command also closes any standard message boxes that are still open.
    release: Arg0,

    // Blocks script execution until the player presses any key.
    waitbuttonpress: Arg0,

    // Displays a YES/NO multichoice box at the specified coordinates, and blocks script execution until the user makes a selection. Their selection is stored in variable 0x800D (LASTRESULT); 0x0000 for "NO" or if the user pressed B, and 0x0001 for "YES".
    yesnobox: yesnobox,

    // Displays a multichoice box from which the user can choose a selection, and blocks script execution until a selection is made. Lists of options are predefined and the one to be used is specified with list. If b is set to a non-zero value, then the user will not be allowed to back out of the multichoice with the B button.
    multichoice: multichoice,

    // Displays a multichoice box from which the user can choose a selection, and blocks script execution until a selection is made. Lists of options are predefined and the one to be used is specified with list. The default argument determines the initial position of the cursor when the box is first opened; it is zero-indexed, and if it is too large, it is treated as 0x00. If b is set to a non-zero value, then the user will not be allowed to back out of the multichoice with the B button.
    multichoicedefault: multichoicedefault,

    // Displays a multichoice box from which the user can choose a selection, and blocks script execution until a selection is made. Lists of options are predefined and the one to be used is specified with list. The per_row argument determines how many list items will be shown on a single row of the box.
    multichoicegrid: multichoicegrid,

    // Nopped in Emerald.
    drawbox: Arg0,

    // Nopped in Emerald, but still consumes parameters.
    erasebox: erasebox,

    // Nopped in Emerald, but still consumes parameters.
    drawboxtext: drawboxtext,

    // Displays a box containing the front sprite for the specified (species) Pokemon species.
    drawmonpic: drawmonpic,

    // Hides all boxes displayed with drawmonpic.
    erasemonpic: Arg0,

    // Draws an image of the winner of the contest. In FireRed, this command is a nop. (The argument is discarded.)
    drawcontestwinner: drawcontestwinner,

    // Displays the string at pointer as braille text in a standard message box. The string must be formatted to use braille characters and needs to provide six extra starting characters that are skipped (in RS, these characters determined the box's size and position, but in Emerald these are calculated automatically).
    braillemessage: braillemessage,

    // Gives the player one of the specified (species) Pokemon at level level holding item. The unknown arguments should all be zeroes.
    givemon: givemon,
    giveegg: giveegg,
    setmonmove: setmonmove,

    // Checks if at least one Pokemon in the player's party knows the specified (index) attack. If so, variable 0x800D (LASTRESULT) is set to the (zero-indexed) slot number of the first Pokemon that knows the move. If not, LASTRESULT is set to 0x0006. Variable 0x8004 is also set to this Pokemon's species.
    checkpartymove: checkpartymove,

    // Writes the name of the Pokemon at index species to the specified buffer.
    bufferspeciesname: bufferspeciesname,

    // Writes the name of the species of the first Pokemon in the player's party to the specified buffer.
    bufferleadmonspeciesname: bufferleadmonspeciesname,

    // Writes the nickname of the Pokemon in slot slot (zero-indexed) of the player's party to the specified buffer. If an empty or invalid slot is specified, ten spaces ("") are written to the buffer.
    bufferpartymonnick: bufferpartymonnick,

    // Writes the name of the item at index item to the specified buffer. If the specified index is larger than the number of items in the game (0x176), the name of item 0 ("????????") is buffered instead.
    bufferitemname: bufferitemname,

    // Writes the name of the decoration at index decoration to the specified buffer. In FireRed, this command is a nop.
    bufferdecorationname: bufferdecorationname,

    // Writes the name of the move at index move to the specified buffer.
    buffermovename: buffermovename,

    // Converts the value of input to a decimal string, and writes that string to the specified buffer.
    buffernumberstring: buffernumberstring,

    // Writes the standard string identified by index to the specified buffer. This command has no protections in place at all, so specifying an invalid standard string (e.x. 0x2B) can and usually will cause data corruption.
    bufferstdstring: bufferstdstring,

    // Copies the string at offset to the specified buffer.
    bufferstring: bufferstring,

    // Opens the Pokemart system, offering the specified products for sale.
    pokemart: pokemart,

    // Opens the Pokemart system and treats the list of items as decorations.
    pokemartdecoration: pokemartdecoration,

    // Apparent clone of pokemartdecoration.
    pokemartdecoration2: pokemartdecoration2,

    // Starts up the slot machine minigame.
    playslotmachine: playslotmachine,

    // Sets a berry tree's specific berry and growth stage. In FireRed, this command is a nop.
    setberrytree: setberrytree,

    // This allows you to choose a Pokemon to use in a contest. In FireRed, this command sets the byte at 0x03000EA8 to 0x01.
    choosecontestmon: Arg0,

    // Starts a contest. In FireRed, this command is a nop.
    startcontest: Arg0,

    // Shows the results of a contest. In FireRed, this command is a nop.
    showcontestresults: Arg0,

    // Starts a contest over a link connection. In FireRed, this command is a nop.
    contestlinktransfer: Arg0,

    // Stores a random integer between 0 and limit in variable 0x800D (LASTRESULT).
    random: random,

    // If check is 0x00, this command adds value to the player's money.
    givemoney: givemoney,

    // If check is 0x00, this command subtracts value from the player's money.
    takemoney: takemoney,

    // If check is 0x00, this command will check if the player has value or more money; script variable 0x800D (LASTRESULT) is set to 0x0001 if the player has enough money, or 0x0000 if the do not.
    checkmoney: checkmoney,

    // Spawns a secondary box showing how much money the player has.
    showmoneybox: showmoneybox,

    // Hides the secondary box spawned by showmoney.
    hidemoneybox: Arg0,

    // Updates the secondary box spawned by showmoney. Consumes but does not use arguments.
    updatemoneybox: updatemoneybox,

    // Gets the price reduction for the index given. In FireRed, this command is a nop.
    getpricereduction: getpricereduction,

    // Fades the screen to and from black and white. Mode 0x00 fades from black, mode 0x01 fades out to black, mode 0x2 fades in from white, and mode 0x3 fades out to white.
    fadescreen: fadescreen,

    // Fades the screen to and from black and white. Mode 0x00 fades from black, mode 0x01 fades out to black, mode 0x2 fades in from white, and mode 0x3 fades out to white. Other modes may exist.
    fadescreenspeed: fadescreenspeed,
    setflashradius: setflashradius,
    animateflash: animateflash,
    messageautoscroll: Pointer,

    // Executes the specified field move animation.
    dofieldeffect: dofieldeffect,

    // Sets up the field effect argument argument with the value value.
    setfieldeffectargument: setfieldeffectargument,

    // Blocks script execution until all playing field move animations complete.
    waitfieldeffect: waitfieldeffect,

    // Sets which healing place the player will return to if all of the Pokemon in their party faint.
    setrespawn: setrespawn,

    // Checks the player's gender. If male, then 0x0000 is stored in variable 0x800D (LASTRESULT). If female, then 0x0001 is stored in LASTRESULT.
    checkplayergender: Arg0,

    // Plays the specified (species) Pokemon's cry. You can use waitcry to block script execution until the sound finishes.
    playmoncry: playmoncry,

    // Changes the metatile at (x, y) on the current map.
    setmetatile: setmetatile,

    // Queues a weather change to the default weather for the map.
    resetweather: Arg0,

    // Queues a weather change to type weather.
    setweather: setweather,

    // Executes the weather change queued with resetweather or setweather. The current weather will smoothly fade into the queued weather.
    doweather: Arg0,

    // This command manages cases in which maps have tiles that change state when stepped on (specifically, cracked/breakable floors).
    setstepcallback: setstepcallback,
    setmaplayoutindex: setmaplayoutindex,
    setobjectpriority: setobjectpriority,
    resetobjectpriority: resetobjectpriority,
    createvobject: createvobject,
    turnvobject: turnvobject,

    // Opens the door metatile at (X, Y) with an animation.
    opendoor: opendoor,

    // Closes the door metatile at (X, Y) with an animation.
    closedoor: closedoor,

    // Waits for the door animation started with opendoor or closedoor to finish.
    waitdooranim: Arg0,

    // Sets the door tile at (x, y) to be open without an animation.
    setdooropen: setdooropen,

    // Sets the door tile at (x, y) to be closed without an animation.
    setdoorclosed: setdoorclosed,

    // In Emerald, this command consumes its parameters and does nothing. In FireRed, this command is a nop.
    addelevmenuitem: addelevmenuitem,

    // In FireRed and Emerald, this command is a nop.
    showelevmenu: Arg0,
    checkcoins: checkcoins,
    givecoins: givecoins,
    takecoins: takecoins,

    // Prepares to start a wild battle against a species at Level level holding item. Running this command will not affect normal wild battles. You start the prepared battle with dowildbattle.
    setwildbattle: setwildbattle,

    // Starts a wild battle against the Pokemon generated by setwildbattle. Blocks script execution until the battle finishes.
    dowildbattle: Arg0,
    setvaddress: Pointer,
    vgoto: Pointer,
    vcall: Pointer,
    vgoto_if: CondJump,
    vcall_if: CondJump,
    vmessage: Pointer,
    vloadptr: Pointer,
    vbufferstring: CondJump,

    // Spawns a secondary box showing how many Coins the player has.
    showcoinsbox: Coord,

    // Hides the secondary box spawned by showcoins. It consumes its arguments but doesn't use them.
    hidecoinsbox: Coord,

    // Updates the secondary box spawned by showcoins. It consumes its arguments but doesn't use them.
    updatecoinsbox: Coord,

    // Increases the value of the specified game stat by 1. The stat's value will not be allowed to exceed 0x00FFFFFF.
    incrementgamestat: incrementgamestat,

    // Sets the destination that using an Escape Rope or Dig will take the player to.
    setescapewarp: Warp,

    // Blocks script execution until cry finishes.
    waitmoncry: Arg0,

    // Writes the name of the specified (box) PC box to the specified buffer.
    bufferboxname: bufferboxname,

    // Sets the color of the text in standard message boxes. 0x00 produces blue (male) text, 0x01 produces red (female) text, 0xFF resets the color to the default for the current OW's gender, and all other values produce black text.
    textcolor: textcolor,

    // The exact purpose of this command is unknown, but it is related to the blue help-text box that appears on the bottom of the screen when the Main Menu is opened.
    loadhelp: Pointer,

    // The exact purpose of this command is unknown, but it is related to the blue help-text box that appears on the bottom of the screen when the Main Menu is opened.
    unloadhelp: Arg0,

    // After using this command, all standard message boxes will use the signpost frame.
    signmsg: Arg0,

    // Ends the effects of signmsg, returning message box frames to normal.
    normalmsg: Arg0,

    // Compares the value of a hidden variable to a dword.
    comparehiddenvar: comparehiddenvar,

    // Makes the Pokemon in the specified slot of the player's party obedient. It will not randomly disobey orders in battle.
    setmonobedient: Slot,

    // Checks if the Pokemon in the specified slot of the player's party is obedient. If the Pokemon is disobedient, 0x0001 is written to script variable 0x800D (LASTRESULT). If the Pokemon is obedient (or if the specified slot is empty or invalid), 0x0000 is written.
    checkmonobedience: Slot,

    // Depending on factors I haven't managed to understand yet, this command may cause script execution to jump to the offset specified by the pointer at 0x020375C0.
    execram: Arg0,

    // Sets worldmapflag to 1. This allows the player to Fly to the corresponding map, if that map has a flightspot.
    setworldmapflag: setworldmapflag,

    // Clone of warpteleport? It is apparently only used in FR/LG, and only with specials.[source]
    warpteleport2: Warp,

    // Changes the location where the player caught the Pokemon in the specified slot of their party.
    setmonmetlocation: setmonmetlocation,
    mossdeepgym1: mossdeepgym1,
    mossdeepgym2: Arg0,

    // In FireRed, this command is a nop.
    mossdeepgym3: mossdeepgym3,
    mossdeepgym4: Arg0,
    warp7: warp7,
    cmd_d8: Arg0,
    cmd_d9: Arg0,
    hidebox2: Arg0,
    message3: Pointer,
    fadescreenswapbuffers: fadescreenswapbuffers,
    buffertrainerclassname: buffertrainerclassname,
    buffertrainername: buffertrainername,
    pokenavcall: Pointer,
    warp8: warp8,
    buffercontesttypestring: buffercontesttypestring,

    // Writes the name of the specified (item) item to the specified buffer. If the specified item is a Berry (0x85 - 0xAE) or Poke Ball (0x4) and if the quantity is 2 or more, the buffered string will be pluralized ("IES" or "S" appended). If the specified item is the Enigma Berry, I have no idea what this command does (but testing showed no pluralization). If the specified index is larger than the number of items in the game (0x176), the name of item 0 ("????????") is buffered instead.
    bufferitemnameplural: bufferitemnameplural,

    pub const Kind = enum(u8) {
        nop = 0x00,
        nop1 = 0x01,
        end = 0x02,
        @"return" = 0x03,
        call = 0x04,
        goto = 0x05,
        goto_if = 0x06,
        call_if = 0x07,
        gotostd = 0x08,
        callstd = 0x09,
        gotostd_if = 0x0a,
        callstd_if = 0x0b,
        gotoram = 0x0c,
        killscript = 0x0d,
        setmysteryeventstatus = 0x0e,
        loadword = 0x0f,
        loadbyte = 0x10,
        writebytetoaddr = 0x11,
        loadbytefromaddr = 0x12,
        setptrbyte = 0x13,
        copylocal = 0x14,
        copybyte = 0x15,
        setvar = 0x16,
        addvar = 0x17,
        subvar = 0x18,
        copyvar = 0x19,
        setorcopyvar = 0x1a,
        compare_local_to_local = 0x1b,
        compare_local_to_value = 0x1c,
        compare_local_to_addr = 0x1d,
        compare_addr_to_local = 0x1e,
        compare_addr_to_value = 0x1f,
        compare_addr_to_addr = 0x20,
        compare_var_to_value = 0x21,
        compare_var_to_var = 0x22,
        callnative = 0x23,
        gotonative = 0x24,
        special = 0x25,
        specialvar = 0x26,
        waitstate = 0x27,
        delay = 0x28,
        setflag = 0x29,
        clearflag = 0x2a,
        checkflag = 0x2b,
        initclock = 0x2c,
        dodailyevents = 0x2d,
        gettime = 0x2e,
        playse = 0x2f,
        waitse = 0x30,
        playfanfare = 0x31,
        waitfanfare = 0x32,
        playbgm = 0x33,
        savebgm = 0x34,
        fadedefaultbgm = 0x35,
        fadenewbgm = 0x36,
        fadeoutbgm = 0x37,
        fadeinbgm = 0x38,
        warp = 0x39,
        warpsilent = 0x3a,
        warpdoor = 0x3b,
        warphole = 0x3c,
        warpteleport = 0x3d,
        setwarp = 0x3e,
        setdynamicwarp = 0x3f,
        setdivewarp = 0x40,
        setholewarp = 0x41,
        getplayerxy = 0x42,
        getpartysize = 0x43,
        additem = 0x44,
        removeitem = 0x45,
        checkitemspace = 0x46,
        checkitem = 0x47,
        checkitemtype = 0x48,
        givepcitem = 0x49,
        checkpcitem = 0x4a,
        givedecoration = 0x4b,
        takedecoration = 0x4c,
        checkdecor = 0x4d,
        checkdecorspace = 0x4e,
        applymovement = 0x4f,
        applymovementmap = 0x50,
        waitmovement = 0x51,
        waitmovementmap = 0x52,
        removeobject = 0x53,
        removeobjectmap = 0x54,
        addobject = 0x55,
        addobjectmap = 0x56,
        setobjectxy = 0x57,
        showobjectat = 0x58,
        hideobjectat = 0x59,
        faceplayer = 0x5a,
        turnobject = 0x5b,
        trainerbattle = 0x5c,
        trainerbattlebegin = 0x5d,
        gotopostbattlescript = 0x5e,
        gotobeatenscript = 0x5f,
        checktrainerflag = 0x60,
        settrainerflag = 0x61,
        cleartrainerflag = 0x62,
        setobjectxyperm = 0x63,
        moveobjectoffscreen = 0x64,
        setobjectmovementtype = 0x65,
        waitmessage = 0x66,
        message = 0x67,
        closemessage = 0x68,
        lockall = 0x69,
        lock = 0x6a,
        releaseall = 0x6b,
        release = 0x6c,
        waitbuttonpress = 0x6d,
        yesnobox = 0x6e,
        multichoice = 0x6f,
        multichoicedefault = 0x70,
        multichoicegrid = 0x71,
        drawbox = 0x72,
        erasebox = 0x73,
        drawboxtext = 0x74,
        drawmonpic = 0x75,
        erasemonpic = 0x76,
        drawcontestwinner = 0x77,
        braillemessage = 0x78,
        givemon = 0x79,
        giveegg = 0x7a,
        setmonmove = 0x7b,
        checkpartymove = 0x7c,
        bufferspeciesname = 0x7d,
        bufferleadmonspeciesname = 0x7e,
        bufferpartymonnick = 0x7f,
        bufferitemname = 0x80,
        bufferdecorationname = 0x81,
        buffermovename = 0x82,
        buffernumberstring = 0x83,
        bufferstdstring = 0x84,
        bufferstring = 0x85,
        pokemart = 0x86,
        pokemartdecoration = 0x87,
        pokemartdecoration2 = 0x88,
        playslotmachine = 0x89,
        setberrytree = 0x8a,
        choosecontestmon = 0x8b,
        startcontest = 0x8c,
        showcontestresults = 0x8d,
        contestlinktransfer = 0x8e,
        random = 0x8f,
        givemoney = 0x90,
        takemoney = 0x91,
        checkmoney = 0x92,
        showmoneybox = 0x93,
        hidemoneybox = 0x94,
        updatemoneybox = 0x95,
        getpricereduction = 0x96,
        fadescreen = 0x97,
        fadescreenspeed = 0x98,
        setflashradius = 0x99,
        animateflash = 0x9a,
        messageautoscroll = 0x9b,
        dofieldeffect = 0x9c,
        setfieldeffectargument = 0x9d,
        waitfieldeffect = 0x9e,
        setrespawn = 0x9f,
        checkplayergender = 0xa0,
        playmoncry = 0xa1,
        setmetatile = 0xa2,
        resetweather = 0xa3,
        setweather = 0xa4,
        doweather = 0xa5,
        setstepcallback = 0xa6,
        setmaplayoutindex = 0xa7,
        setobjectpriority = 0xa8,
        resetobjectpriority = 0xa9,
        createvobject = 0xaa,
        turnvobject = 0xab,
        opendoor = 0xac,
        closedoor = 0xad,
        waitdooranim = 0xae,
        setdooropen = 0xaf,
        setdoorclosed = 0xb0,
        addelevmenuitem = 0xb1,
        showelevmenu = 0xb2,
        checkcoins = 0xb3,
        givecoins = 0xb4,
        takecoins = 0xb5,
        setwildbattle = 0xb6,
        dowildbattle = 0xb7,
        setvaddress = 0xb8,
        vgoto = 0xb9,
        vcall = 0xba,
        vgoto_if = 0xbb,
        vcall_if = 0xbc,
        vmessage = 0xbd,
        vloadptr = 0xbe,
        vbufferstring = 0xbf,
        showcoinsbox = 0xc0,
        hidecoinsbox = 0xc1,
        updatecoinsbox = 0xc2,
        incrementgamestat = 0xc3,
        setescapewarp = 0xc4,
        waitmoncry = 0xc5,
        bufferboxname = 0xc6,
        textcolor = 0xc7,
        loadhelp = 0xc8,
        unloadhelp = 0xc9,
        signmsg = 0xca,
        normalmsg = 0xcb,
        comparehiddenvar = 0xcc,
        setmonobedient = 0xcd,
        checkmonobedience = 0xce,
        execram = 0xcf,
        setworldmapflag = 0xd0,
        warpteleport2 = 0xd1,
        setmonmetlocation = 0xd2,
        mossdeepgym1 = 0xd3,
        mossdeepgym2 = 0xd4,
        mossdeepgym3 = 0xd5,
        mossdeepgym4 = 0xd6,
        warp7 = 0xd7,
        cmd_d8 = 0xd8,
        cmd_d9 = 0xd9,
        hidebox2 = 0xda,
        message3 = 0xdb,
        fadescreenswapbuffers = 0xdc,
        buffertrainerclassname = 0xdd,
        buffertrainername = 0xde,
        pokenavcall = 0xdf,
        warp8 = 0xe0,
        buffercontesttypestring = 0xe1,
        bufferitemnameplural = 0xe2,
    };

    pub const Arg0 = extern struct {
        kind: Kind align(1),
    };
    pub const Jump = extern struct {
        kind: Kind align(1),
        destination: lu32 align(1),
    };
    pub const CondJump = extern struct {
        kind: Kind align(1),
        condition: u8 align(1),
        destination: lu32 align(1),
    };
    pub fn Func(comptime T: type) type {
        return extern struct {
            kind: Kind align(1),
            function: T align(1),
        };
    }
    pub const CondFunc = extern struct {
        kind: Kind align(1),
        condition: u8 align(1),
        function: u8 align(1),
    };
    pub const setmysteryeventstatus = extern struct {
        kind: Kind align(1),
        value: u8 align(1),
    };
    pub const loadword = extern struct {
        kind: Kind align(1),
        destination: u8 align(1),
        value: gen3.Ptr([*:0xff]u8) align(1),
    };
    pub const loadbyte = extern struct {
        kind: Kind align(1),
        destination: u8 align(1),
        value: u8 align(1),
    };
    pub const writebytetoaddr = extern struct {
        kind: Kind align(1),
        value: u8 align(1),
        offset: lu32 align(1),
    };
    pub fn DestSrc(comptime Dst: type, comptime Src: type) type {
        return extern struct {
            kind: Kind align(1),
            dest: Dst align(1),
            src: Src align(1),
        };
    }
    pub const setptrbyte = extern struct {
        kind: Kind align(1),
        source: u8 align(1),
        destination: lu32 align(1),
    };
    pub const DestVal = extern struct {
        kind: Kind align(1),
        destination: lu16 align(1),
        value: lu16 align(1),
    };
    pub fn AB(comptime A: type, comptime B: type) type {
        return extern struct {
            kind: Kind align(1),
            a: A align(1),
            b: B align(1),
        };
    }
    pub const compare_var_to_value = extern struct {
        kind: Kind align(1),
        @"var": lu16 align(1),
        value: lu16 align(1),
    };
    pub const compare_var_to_var = extern struct {
        kind: Kind align(1),
        var1: lu16 align(1),
        var2: lu16 align(1),
    };
    pub const specialvar = extern struct {
        kind: Kind align(1),
        output: lu16 align(1),
        special_function: lu16 align(1),
    };
    pub const delay = extern struct {
        kind: Kind align(1),
        time: lu16 align(1),
    };
    pub const Arg1 = extern struct {
        kind: Kind align(1),
        arg: lu16 align(1),
    };
    pub const initclock = extern struct {
        kind: Kind align(1),
        hour: lu16 align(1),
        minute: lu16 align(1),
    };
    pub const playbgm = extern struct {
        kind: Kind align(1),
        song_number: lu16 align(1),
        unknown: u8 align(1),
    };
    pub const Song = extern struct {
        kind: Kind align(1),
        song_number: lu16 align(1),
    };
    pub const Speed = extern struct {
        kind: Kind align(1),
        speed: u8 align(1),
    };
    pub const Warp = extern struct {
        kind: Kind align(1),
        map: lu16 align(1),
        warp: u8 align(1),
        x: lu16 align(1),
        y: lu16 align(1),
    };
    pub const warphole = extern struct {
        kind: Kind align(1),
        map: lu16 align(1),
    };
    pub const getplayerxy = extern struct {
        kind: Kind align(1),
        x: lu16 align(1),
        y: lu16 align(1),
    };
    pub const additem = extern struct {
        kind: Kind align(1),
        index: lu16 align(1),
        quantity: lu16 align(1),
    };
    pub const removeitem = extern struct {
        kind: Kind align(1),
        index: lu16 align(1),
        quantity: lu16 align(1),
    };
    pub const checkitemspace = extern struct {
        kind: Kind align(1),
        index: lu16 align(1),
        quantity: lu16 align(1),
    };
    pub const checkitem = extern struct {
        kind: Kind align(1),
        index: lu16 align(1),
        quantity: lu16 align(1),
    };
    pub const checkitemtype = extern struct {
        kind: Kind align(1),
        index: lu16 align(1),
    };
    pub const givepcitem = extern struct {
        kind: Kind align(1),
        index: lu16 align(1),
        quantity: lu16 align(1),
    };
    pub const checkpcitem = extern struct {
        kind: Kind align(1),
        index: lu16 align(1),
        quantity: lu16 align(1),
    };
    pub const givedecoration = extern struct {
        kind: Kind align(1),
        decoration: lu16 align(1),
    };
    pub const takedecoration = extern struct {
        kind: Kind align(1),
        decoration: lu16 align(1),
    };
    pub const checkdecor = extern struct {
        kind: Kind align(1),
        decoration: lu16 align(1),
    };
    pub const checkdecorspace = extern struct {
        kind: Kind align(1),
        decoration: lu16 align(1),
    };
    pub const applymovement = extern struct {
        kind: Kind align(1),
        index: lu16 align(1),
        movements: lu32 align(1),
    };
    pub const applymovementmap = extern struct {
        kind: Kind align(1),
        index: lu16 align(1),
        movements: lu32 align(1),
        map: lu16 align(1),
    };
    pub const waitmovement = extern struct {
        kind: Kind align(1),
        index: lu16 align(1),
    };
    pub const waitmovementmap = extern struct {
        kind: Kind align(1),
        index: lu16 align(1),
        map: lu16 align(1),
    };
    pub const removeobject = extern struct {
        kind: Kind align(1),
        index: lu16 align(1),
    };
    pub const removeobjectmap = extern struct {
        kind: Kind align(1),
        index: lu16 align(1),
        map: lu16 align(1),
    };
    pub const addobject = extern struct {
        kind: Kind align(1),
        index: lu16 align(1),
    };
    pub const addobjectmap = extern struct {
        kind: Kind align(1),
        index: lu16 align(1),
        map: lu16 align(1),
    };
    pub const setobjectxy = extern struct {
        kind: Kind align(1),
        index: lu16 align(1),
        x: lu16 align(1),
        y: lu16 align(1),
    };
    pub const showobjectat = extern struct {
        kind: Kind align(1),
        index: lu16 align(1),
        map: lu16 align(1),
    };
    pub const hideobjectat = extern struct {
        kind: Kind align(1),
        index: lu16 align(1),
        map: lu16 align(1),
    };
    pub const turnobject = extern struct {
        kind: Kind align(1),
        index: lu16 align(1),
        direction: u8 align(1),
    };

    pub const TrainerBattleType = enum(u8) {
        trainer_battle_single = 0,
        trainer_battle_continue_script_no_music = 1,
        trainer_battle_continue_script = 2,
        trainer_battle_single_no_intro_text = 3,
        trainer_battle_double = 4,
        trainer_battle_rematch = 5,
        trainer_battle_continue_script_double = 6,
        trainer_battle_rematch_double = 7,
        trainer_battle_continue_script_double_no_music = 8,
        trainer_battle_pyramid = 9,
        trainer_battle_set_trainer_a = 10,
        trainer_battle_set_trainer_b = 11,
        trainer_battle12 = 12,
    };

    pub const trainerbattle = extern struct {
        kind: Kind align(1),
        pointers: extern union {
            type: TrainerBattleType,
            trainer_battle_single: extern struct {
                type: TrainerBattleType align(1),
                trainer: lu16 align(1),
                local_id: lu16 align(1),
                pointer1: lu32 align(1), // text
                pointer2: lu32 align(1), // text
            },
            trainer_battle_continue_script_no_music: extern struct {
                type: TrainerBattleType align(1),
                trainer: lu16 align(1),
                local_id: lu16 align(1),
                pointer1: lu32 align(1), // text
                pointer2: lu32 align(1), // text
                pointer3: lu32 align(1), // event script
            },
            trainer_battle_continue_script: extern struct {
                type: TrainerBattleType align(1),
                trainer: lu16 align(1),
                local_id: lu16 align(1),
                pointer1: lu32 align(1), // text
                pointer2: lu32 align(1), // text
                pointer3: lu32 align(1), // event script
            },
            trainer_battle_single_no_intro_text: extern struct {
                type: TrainerBattleType align(1),
                trainer: lu16 align(1),
                local_id: lu16 align(1),
                pointer1: lu32 align(1), // text
            },
            trainer_battle_double: extern struct {
                type: TrainerBattleType align(1),
                trainer: lu16 align(1),
                local_id: lu16 align(1),
                pointer1: lu32 align(1), // text
                pointer2: lu32 align(1), // text
                pointer3: lu32 align(1), // text
            },
            trainer_battle_rematch: extern struct {
                type: TrainerBattleType align(1),
                trainer: lu16 align(1),
                local_id: lu16 align(1),
                pointer1: lu32 align(1), // text
                pointer2: lu32 align(1), // text
            },
            trainer_battle_continue_script_double: extern struct {
                type: TrainerBattleType align(1),
                trainer: lu16 align(1),
                local_id: lu16 align(1),
                pointer1: lu32 align(1), // text
                pointer2: lu32 align(1), // text
                pointer3: lu32 align(1), // text
                pointer4: lu32 align(1), // event script
            },
            trainer_battle_rematch_double: extern struct {
                type: TrainerBattleType align(1),
                trainer: lu16 align(1),
                local_id: lu16 align(1),
                pointer1: lu32 align(1), // text
                pointer2: lu32 align(1), // text
                pointer3: lu32 align(1), // text
            },
            trainer_battle_continue_script_double_no_music: extern struct {
                type: TrainerBattleType align(1),
                trainer: lu16 align(1),
                local_id: lu16 align(1),
                pointer1: lu32 align(1), // text
                pointer2: lu32 align(1), // text
                pointer3: lu32 align(1), // text
                pointer4: lu32 align(1), // event script
            },
            trainer_battle_pyramid: extern struct {
                type: TrainerBattleType align(1),
                trainer: lu16 align(1),
                local_id: lu16 align(1),
                pointer1: lu32 align(1), // text
                pointer2: lu32 align(1), // text
            },
            trainer_battle_set_trainer_a: extern struct {
                type: TrainerBattleType align(1),
                trainer: lu16 align(1),
                local_id: lu16 align(1),
                pointer1: lu32 align(1), // text
                pointer2: lu32 align(1), // text
            },
            trainer_battle_set_trainer_b: extern struct {
                type: TrainerBattleType align(1),
                trainer: lu16 align(1),
                local_id: lu16 align(1),
                pointer1: lu32 align(1), // text
                pointer2: lu32 align(1), // text
            },
            trainer_battle12: extern struct {
                type: TrainerBattleType align(1),
                trainer: lu16 align(1),
                local_id: lu16 align(1),
                pointer1: lu32 align(1), // text
                pointer2: lu32 align(1), // text
            },
        },
    };
    pub const Trainer = extern struct {
        kind: Kind align(1),
        trainer: lu16 align(1),
    };
    pub const setobjectxyperm = extern struct {
        kind: Kind align(1),
        index: lu16 align(1),
        x: lu16 align(1),
        y: lu16 align(1),
    };
    pub const moveobjectoffscreen = extern struct {
        kind: Kind align(1),
        index: lu16 align(1),
    };
    pub const setobjectmovementtype = extern struct {
        kind: Kind align(1),
        word: lu16 align(1),
        byte: u8 align(1),
    };
    pub const message = extern struct {
        kind: Kind align(1),
        text: gen3.Ptr([*:0xff]u8) align(1),
    };
    pub const yesnobox = extern struct {
        kind: Kind align(1),
        x: u8 align(1),
        y: u8 align(1),
    };
    pub const multichoice = extern struct {
        kind: Kind align(1),
        x: u8 align(1),
        y: u8 align(1),
        list: u8 align(1),
        b: u8 align(1),
    };
    pub const multichoicedefault = extern struct {
        kind: Kind align(1),
        x: u8 align(1),
        y: u8 align(1),
        list: u8 align(1),
        default: u8 align(1),
        b: u8 align(1),
    };
    pub const multichoicegrid = extern struct {
        kind: Kind align(1),
        x: u8 align(1),
        y: u8 align(1),
        list: u8 align(1),
        per_row: u8 align(1),
        b: u8 align(1),
    };
    pub const erasebox = extern struct {
        kind: Kind align(1),
        byte1: u8 align(1),
        byte2: u8 align(1),
        byte3: u8 align(1),
        byte4: u8 align(1),
    };
    pub const drawboxtext = extern struct {
        kind: Kind align(1),
        byte1: u8 align(1),
        byte2: u8 align(1),
        byte3: u8 align(1),
        byte4: u8 align(1),
    };
    pub const drawmonpic = extern struct {
        kind: Kind align(1),
        species: lu16 align(1),
        x: u8 align(1),
        y: u8 align(1),
    };
    pub const drawcontestwinner = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
    };
    pub const braillemessage = extern struct {
        kind: Kind align(1),
        text: lu32 align(1),
    };
    pub const givemon = extern struct {
        kind: Kind align(1),
        species: lu16 align(1),
        level: u8 align(1),
        item: lu16 align(1),
        unknown1: lu32 align(1),
        unknown2: lu32 align(1),
        unknown3: u8 align(1),
    };
    pub const giveegg = extern struct {
        kind: Kind align(1),
        species: lu16 align(1),
    };
    pub const setmonmove = extern struct {
        kind: Kind align(1),
        index: u8 align(1),
        slot: u8 align(1),
        move: lu16 align(1),
    };
    pub const checkpartymove = extern struct {
        kind: Kind align(1),
        index: lu16 align(1),
    };
    pub const bufferspeciesname = extern struct {
        kind: Kind align(1),
        out: u8 align(1),
        species: lu16 align(1),
    };
    pub const bufferleadmonspeciesname = extern struct {
        kind: Kind align(1),
        out: u8 align(1),
    };
    pub const bufferpartymonnick = extern struct {
        kind: Kind align(1),
        out: u8 align(1),
        slot: lu16 align(1),
    };
    pub const bufferitemname = extern struct {
        kind: Kind align(1),
        out: u8 align(1),
        item: lu16 align(1),
    };
    pub const bufferdecorationname = extern struct {
        kind: Kind align(1),
        out: u8 align(1),
        decoration: lu16 align(1),
    };
    pub const buffermovename = extern struct {
        kind: Kind align(1),
        out: u8 align(1),
        move: lu16 align(1),
    };
    pub const buffernumberstring = extern struct {
        kind: Kind align(1),
        out: u8 align(1),
        input: lu16 align(1),
    };
    pub const bufferstdstring = extern struct {
        kind: Kind align(1),
        out: u8 align(1),
        index: lu16 align(1),
    };
    pub const bufferstring = extern struct {
        kind: Kind align(1),
        out: u8 align(1),
        offset: lu32 align(1),
    };
    pub const pokemart = extern struct {
        kind: Kind align(1),
        products: lu32 align(1),
    };
    pub const pokemartdecoration = extern struct {
        kind: Kind align(1),
        products: lu32 align(1),
    };
    pub const pokemartdecoration2 = extern struct {
        kind: Kind align(1),
        products: lu32 align(1),
    };
    pub const playslotmachine = extern struct {
        kind: Kind align(1),
        word: lu16 align(1),
    };
    pub const setberrytree = extern struct {
        kind: Kind align(1),
        tree_id: u8 align(1),
        berry: u8 align(1),
        growth_stage: u8 align(1),
    };
    pub const random = extern struct {
        kind: Kind align(1),
        limit: lu16 align(1),
    };
    pub const givemoney = extern struct {
        kind: Kind align(1),
        value: lu32 align(1),
        check: u8 align(1),
    };
    pub const takemoney = extern struct {
        kind: Kind align(1),
        value: lu32 align(1),
        check: u8 align(1),
    };
    pub const checkmoney = extern struct {
        kind: Kind align(1),
        value: lu32 align(1),
        check: u8 align(1),
    };
    pub const showmoneybox = extern struct {
        kind: Kind align(1),
        x: u8 align(1),
        y: u8 align(1),
        check: u8 align(1),
    };
    pub const updatemoneybox = extern struct {
        kind: Kind align(1),
        x: u8 align(1),
        y: u8 align(1),
    };
    pub const getpricereduction = extern struct {
        kind: Kind align(1),
        index: lu16 align(1),
    };
    pub const fadescreen = extern struct {
        kind: Kind align(1),
        effect: u8 align(1),
    };
    pub const fadescreenspeed = extern struct {
        kind: Kind align(1),
        effect: u8 align(1),
        speed: u8 align(1),
    };
    pub const setflashradius = extern struct {
        kind: Kind align(1),
        word: lu16 align(1),
    };
    pub const animateflash = extern struct {
        kind: Kind align(1),
        byte: u8 align(1),
    };
    pub const dofieldeffect = extern struct {
        kind: Kind align(1),
        animation: lu16 align(1),
    };
    pub const setfieldeffectargument = extern struct {
        kind: Kind align(1),
        argument: u8 align(1),
        param: lu16 align(1),
    };
    pub const waitfieldeffect = extern struct {
        kind: Kind align(1),
        animation: lu16 align(1),
    };
    pub const setrespawn = extern struct {
        kind: Kind align(1),
        heallocation: lu16 align(1),
    };
    pub const playmoncry = extern struct {
        kind: Kind align(1),
        species: lu16 align(1),
        effect: lu16 align(1),
    };
    pub const setmetatile = extern struct {
        kind: Kind align(1),
        x: lu16 align(1),
        y: lu16 align(1),
        metatile_number: lu16 align(1),
        tile_attrib: lu16 align(1),
    };
    pub const setweather = extern struct {
        kind: Kind align(1),
        type: lu16 align(1),
    };
    pub const setstepcallback = extern struct {
        kind: Kind align(1),
        subroutine: u8 align(1),
    };
    pub const setmaplayoutindex = extern struct {
        kind: Kind align(1),
        index: lu16 align(1),
    };
    pub const setobjectpriority = extern struct {
        kind: Kind align(1),
        index: lu16 align(1),
        map: lu16 align(1),
        priority: u8 align(1),
    };
    pub const resetobjectpriority = extern struct {
        kind: Kind align(1),
        index: lu16 align(1),
        map: lu16 align(1),
    };
    pub const createvobject = extern struct {
        kind: Kind align(1),
        sprite: u8 align(1),
        byte2: u8 align(1),
        x: lu16 align(1),
        y: lu16 align(1),
        elevation: u8 align(1),
        direction: u8 align(1),
    };
    pub const turnvobject = extern struct {
        kind: Kind align(1),
        index: u8 align(1),
        direction: u8 align(1),
    };
    pub const opendoor = extern struct {
        kind: Kind align(1),
        x: lu16 align(1),
        y: lu16 align(1),
    };
    pub const closedoor = extern struct {
        kind: Kind align(1),
        x: lu16 align(1),
        y: lu16 align(1),
    };
    pub const setdooropen = extern struct {
        kind: Kind align(1),
        x: lu16 align(1),
        y: lu16 align(1),
    };
    pub const setdoorclosed = extern struct {
        kind: Kind align(1),
        x: lu16 align(1),
        y: lu16 align(1),
    };
    pub const addelevmenuitem = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        b: lu16 align(1),
        c: lu16 align(1),
        d: lu16 align(1),
    };
    pub const checkcoins = extern struct {
        kind: Kind align(1),
        out: lu16 align(1),
    };
    pub const givecoins = extern struct {
        kind: Kind align(1),
        count: lu16 align(1),
    };
    pub const takecoins = extern struct {
        kind: Kind align(1),
        count: lu16 align(1),
    };
    pub const setwildbattle = extern struct {
        kind: Kind align(1),
        species: lu16 align(1),
        level: u8 align(1),
        item: lu16 align(1),
    };

    pub const Coord = extern struct {
        kind: Kind align(1),
        x: u8 align(1),
        y: u8 align(1),
    };
    pub const incrementgamestat = extern struct {
        kind: Kind align(1),
        stat: u8 align(1),
    };
    pub const bufferboxname = extern struct {
        kind: Kind align(1),
        out: u8 align(1),
        box: lu16 align(1),
    };
    pub const textcolor = extern struct {
        kind: Kind align(1),
        color: u8 align(1),
    };
    pub const comparehiddenvar = extern struct {
        kind: Kind align(1),
        a: u8 align(1),
        value: lu32 align(1),
    };
    pub const Slot = extern struct {
        kind: Kind align(1),
        slot: lu16 align(1),
    };
    pub const setworldmapflag = extern struct {
        kind: Kind align(1),
        worldmapflag: lu16 align(1),
    };
    pub const setmonmetlocation = extern struct {
        kind: Kind align(1),
        slot: lu16 align(1),
        location: u8 align(1),
    };
    pub const mossdeepgym1 = extern struct {
        kind: Kind align(1),
        unknown: lu16 align(1),
    };
    pub const mossdeepgym3 = extern struct {
        kind: Kind align(1),
        @"var": lu16 align(1),
    };
    pub const warp7 = extern struct {
        kind: Kind align(1),
        map: lu16 align(1),
        byte: u8 align(1),
        word1: lu16 align(1),
        word2: lu16 align(1),
    };
    pub const fadescreenswapbuffers = extern struct {
        kind: Kind align(1),
        byte: u8 align(1),
    };
    pub const buffertrainerclassname = extern struct {
        kind: Kind align(1),
        out: u8 align(1),
        class: lu16 align(1),
    };
    pub const buffertrainername = extern struct {
        kind: Kind align(1),
        out: u8 align(1),
        trainer: lu16 align(1),
    };
    pub const Pointer = extern struct {
        kind: Kind align(1),
        pointer: lu32 align(1),
    };
    pub const warp8 = extern struct {
        kind: Kind align(1),
        map: lu16 align(1),
        byte: u8 align(1),
        word1: lu16 align(1),
        word2: lu16 align(1),
    };
    pub const buffercontesttypestring = extern struct {
        kind: Kind align(1),
        out: u8 align(1),
        word: lu16 align(1),
    };
    pub const bufferitemnameplural = extern struct {
        kind: Kind align(1),
        out: u8 align(1),
        item: lu16 align(1),
        quantity: lu16 align(1),
    };

    comptime {
        @setEvalBranchQuota(1000000);
        std.debug.assert(script.isPacked(@This()));
    }
};

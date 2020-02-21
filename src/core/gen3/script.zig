const rom = @import("../rom.zig");
const script = @import("../script.zig");

const lu16 = rom.int.lu16;
const lu32 = rom.int.lu32;

pub const CommandDecoder = script.CommandDecoder(Command, struct {
    fn isEnd(cmd: Command) bool {
        switch (cmd.tag) {
            Command.Kind.end,
            Command.Kind.@"return",
            => return true,
            else => return false,
        }
    }
}.isEnd);

pub const STD_OBTAIN_ITEM = 0;
pub const STD_FIND_ITEM = 1;
pub const STD_OBTAIN_DECORATION = 7;
pub const STD_REGISTER_MATCH_CALL = 8;

pub const Command = packed struct {
    tag: Kind,
    data: extern union {
        // Does nothing.
        nop: nop,

        // Does nothing.
        nop1: nop1,

        // Terminates script execution.
        end: end,

        // Jumps back to after the last-executed call statement, and continues script execution from there.
        @"return": @"return",

        // Jumps to destination and continues script execution from there. The location of the calling script is remembered and can be returned to later.
        call: call,

        // Jumps to destination and continues script execution from there.
        goto: goto,

        // If the result of the last comparison matches condition (see Comparison operators), jumps to destination and continues script execution from there.
        goto_if: goto_if,

        // If the result of the last comparison matches condition (see Comparison operators), calls destination.
        call_if: call_if,

        // Jumps to the standard function at index function.
        gotostd: gotostd,

        // Calls the standard function at index function.
        callstd: callstd,

        // If the result of the last comparison matches condition (see Comparison operators), jumps to the standard function at index function.
        gotostd_if: gotostd_if,

        // If the result of the last comparison matches condition (see Comparison operators), calls the standard function at index function.
        callstd_if: callstd_if,

        // Executes a script stored in a default RAM location.
        gotoram: gotoram,

        // Terminates script execution and "resets the script RAM".
        killscript: killscript,

        // Sets some status related to Mystery Event.
        setmysteryeventstatus: setmysteryeventstatus,

        // Sets the specified script bank to value.
        loadword: loadword,

        // Sets the specified script bank to value.
        loadbyte: loadbyte,

        // Sets the byte at offset to value.
        writebytetoaddr: writebytetoaddr,

        // Copies the byte value at source into the specified script bank.
        loadbytefromaddr: loadbytefromaddr,

        // Not sure. Judging from XSE's description I think it takes the least-significant byte in bank source and writes it to destination.
        setptrbyte: setptrbyte,

        // Copies the contents of bank source into bank destination.
        copylocal: copylocal,

        // Copies the byte at source to destination, replacing whatever byte was previously there.
        copybyte: copybyte,

        // Changes the value of destination to value.
        setvar: setvar,

        //  // Changes the value of destination by adding value to it. Overflow is not prevented (0xFFFF + 1 = 0x0000).
        addvar: addvar,

        //  // Changes the value of destination by subtracting value to it. Overflow is not prevented (0x0000 - 1 = 0xFFFF).
        subvar: subvar,

        // Copies the value of source into destination.
        copyvar: copyvar,

        // If source is not a variable, then this function acts like setvar. Otherwise, it acts like copyvar.
        setorcopyvar: setorcopyvar,

        // Compares the values of script banks a and b, after forcing the values to bytes.
        compare_local_to_local: compare_local_to_local,

        // Compares the least-significant byte of the value of script bank a to a fixed byte value (b).
        compare_local_to_value: compare_local_to_value,

        // Compares the least-significant byte of the value of script bank a to the byte located at offset b.
        compare_local_to_addr: compare_local_to_addr,

        // Compares the byte located at offset a to the least-significant byte of the value of script bank b.
        compare_addr_to_local: compare_addr_to_local,

        // Compares the byte located at offset a to a fixed byte value (b).
        compare_addr_to_value: compare_addr_to_value,

        // Compares the byte located at offset a to the byte located at offset b.
        compare_addr_to_addr: compare_addr_to_addr,

        // Compares the value of `var` to a fixed word value (b).
        compare_var_to_value: compare_var_to_value,

        // Compares the value of `var1` to the value of `var2`.
        compare_var_to_var: compare_var_to_var,

        // Calls the native C function stored at `func`.
        callnative: callnative,

        // Replaces the script with the function stored at `func`. Execution returns to the bytecode script when func returns TRUE.
        gotonative: gotonative,

        // Calls a special function; that is, a function designed for use by scripts and listed in a table of pointers.
        special: special,

        // Calls a special function. That function's output (if any) will be written to the variable you specify.
        specialvar: specialvar,

        // Blocks script execution until a command or ASM code manually unblocks it. Generally used with specific commands and specials. If this command runs, and a subsequent command or piece of ASM does not unblock state, the script will remain blocked indefinitely (essentially a hang).
        waitstate: waitstate,

        // Blocks script execution for time (frames? milliseconds?).
        delay: delay,

        // Sets a to 1.
        setflag: setflag,

        // Sets a to 0.
        clearflag: clearflag,

        // Compares a to 1.
        checkflag: checkflag,

        // Initializes the RTC`s local time offset to the given hour and minute. In FireRed, this command is a nop.
        initclock: initclock,

        // Runs time based events. In FireRed, this command is a nop.
        dodailyevents: dodailyevents,

        // Sets the values of variables 0x8000, 0x8001, and 0x8002 to the current hour, minute, and second. In FRLG, this command sets those variables to zero.
        gettime: gettime,

        // Plays the specified (sound_number) sound. Only one sound may play at a time, with newer ones interrupting older ones.
        playse: playse,

        // Blocks script execution until the currently-playing sound (triggered by playse) finishes playing.
        waitse: waitse,

        // Plays the specified (fanfare_number) fanfare.
        playfanfare: playfanfare,

        // Blocks script execution until all currently-playing fanfares finish.
        waitfanfare: waitfanfare,

        // Plays the specified (song_number) song. The byte is apparently supposed to be 0x00.
        playbgm: playbgm,

        // Saves the specified (song_number) song to be played later.
        savebgm: savebgm,

        // Crossfades the currently-playing song into the map's default song.
        fadedefaultbgm: fadedefaultbgm,

        // Crossfades the currently-playng song into the specified (song_number) song.
        fadenewbgm: fadenewbgm,

        // Fades out the currently-playing song.
        fadeoutbgm: fadeoutbgm,

        // Fades the previously-playing song back in.
        fadeinbgm: fadeinbgm,

        // Sends the player to Warp warp on Map bank.map. If the specified warp is 0xFF, then the player will instead be sent to (X, Y) on the map.
        warp: warp,

        // Clone of warp that does not play a sound effect.
        warpsilent: warpsilent,

        // Clone of warp that plays a door opening animation before stepping upwards into it.
        warpdoor: warpdoor,

        // Warps the player to another map using a hole animation.
        warphole: warphole,

        // Clone of warp that uses a teleport effect. It is apparently only used in R/S/E.
        warpteleport: warpteleport,

        // Sets the warp destination to be used later.
        setwarp: setwarp,

        // Sets the warp destination that a warp to Warp 127 on Map 127.127 will connect to. Useful when a map has warps that need to go to script-controlled locations (i.e. elevators).
        setdynamicwarp: setdynamicwarp,

        // Sets the destination that diving or emerging from a dive will take the player to.
        setdivewarp: setdivewarp,

        // Sets the destination that falling into a hole will take the player to.
        setholewarp: setholewarp,

        // Retrieves the player's zero-indexed X- and Y-coordinates in the map, and stores them in the specified variables.
        getplayerxy: getplayerxy,

        // Retrieves the number of Pokemon in the player's party, and stores that number in variable 0x800D (LASTRESULT).
        getpartysize: getpartysize,

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
        faceplayer: faceplayer,
        turnobject: turnobject,

        // If the Trainer flag for Trainer index is not set, this command does absolutely nothing.
        trainerbattle: trainerbattle,

        // Starts a trainer battle using the battle information stored in RAM (usually by trainerbattle, which actually calls this command behind-the-scenes), and blocks script execution until the battle finishes.
        trainerbattlebegin: trainerbattlebegin,

        // Goes to address after the trainerbattle command (called by the battle functions, see battle_setup.c)
        gotopostbattlescript: gotopostbattlescript,

        // Goes to address specified in the trainerbattle command (called by the battle functions, see battle_setup.c)
        gotobeatenscript: gotobeatenscript,

        // Compares Flag (trainer + 0x500) to 1. (If the flag is set, then the trainer has been defeated by the player.)
        checktrainerflag: checktrainerflag,

        // Sets Flag (trainer + 0x500).
        settrainerflag: settrainerflag,

        // Clears Flag (trainer + 0x500).
        cleartrainerflag: cleartrainerflag,
        setobjectxyperm: setobjectxyperm,
        moveobjectoffscreen: moveobjectoffscreen,
        setobjectmovementtype: setobjectmovementtype,

        // If a standard message box (or its text) is being drawn on-screen, this command blocks script execution until the box and its text have been fully drawn.
        waitmessage: waitmessage,

        // Starts displaying a standard message box containing the specified text. If text is a pointer, then the string at that offset will be loaded and used. If text is script bank 0, then the value of script bank 0 will be treated as a pointer to the text. (You can use loadpointer to place a string pointer in a script bank.)
        message: message,

        // Closes the current message box.
        closemessage: closemessage,

        // Ceases movement for all Objects on-screen.
        lockall: lockall,

        // If the script was called by an Object, then that Object's movement will cease.
        lock: lock,

        // Resumes normal movement for all Objects on-screen, and closes any standard message boxes that are still open.
        releaseall: releaseall,

        // If the script was called by an Object, then that Object's movement will resume. This command also closes any standard message boxes that are still open.
        release: release,

        // Blocks script execution until the player presses any key.
        waitbuttonpress: waitbuttonpress,

        // Displays a YES/NO multichoice box at the specified coordinates, and blocks script execution until the user makes a selection. Their selection is stored in variable 0x800D (LASTRESULT); 0x0000 for "NO" or if the user pressed B, and 0x0001 for "YES".
        yesnobox: yesnobox,

        // Displays a multichoice box from which the user can choose a selection, and blocks script execution until a selection is made. Lists of options are predefined and the one to be used is specified with list. If b is set to a non-zero value, then the user will not be allowed to back out of the multichoice with the B button.
        multichoice: multichoice,

        // Displays a multichoice box from which the user can choose a selection, and blocks script execution until a selection is made. Lists of options are predefined and the one to be used is specified with list. The default argument determines the initial position of the cursor when the box is first opened; it is zero-indexed, and if it is too large, it is treated as 0x00. If b is set to a non-zero value, then the user will not be allowed to back out of the multichoice with the B button.
        multichoicedefault: multichoicedefault,

        // Displays a multichoice box from which the user can choose a selection, and blocks script execution until a selection is made. Lists of options are predefined and the one to be used is specified with list. The per_row argument determines how many list items will be shown on a single row of the box.
        multichoicegrid: multichoicegrid,

        // Nopped in Emerald.
        drawbox: drawbox,

        // Nopped in Emerald, but still consumes parameters.
        erasebox: erasebox,

        // Nopped in Emerald, but still consumes parameters.
        drawboxtext: drawboxtext,

        // Displays a box containing the front sprite for the specified (species) Pokemon species.
        drawmonpic: drawmonpic,

        // Hides all boxes displayed with drawmonpic.
        erasemonpic: erasemonpic,

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
        choosecontestmon: choosecontestmon,

        // Starts a contest. In FireRed, this command is a nop.
        startcontest: startcontest,

        // Shows the results of a contest. In FireRed, this command is a nop.
        showcontestresults: showcontestresults,

        // Starts a contest over a link connection. In FireRed, this command is a nop.
        contestlinktransfer: contestlinktransfer,

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
        hidemoneybox: hidemoneybox,

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
        messageautoscroll: messageautoscroll,

        // Executes the specified field move animation.
        dofieldeffect: dofieldeffect,

        // Sets up the field effect argument argument with the value value.
        setfieldeffectargument: setfieldeffectargument,

        // Blocks script execution until all playing field move animations complete.
        waitfieldeffect: waitfieldeffect,

        // Sets which healing place the player will return to if all of the Pokemon in their party faint.
        setrespawn: setrespawn,

        // Checks the player's gender. If male, then 0x0000 is stored in variable 0x800D (LASTRESULT). If female, then 0x0001 is stored in LASTRESULT.
        checkplayergender: checkplayergender,

        // Plays the specified (species) Pokemon's cry. You can use waitcry to block script execution until the sound finishes.
        playmoncry: playmoncry,

        // Changes the metatile at (x, y) on the current map.
        setmetatile: setmetatile,

        // Queues a weather change to the default weather for the map.
        resetweather: resetweather,

        // Queues a weather change to type weather.
        setweather: setweather,

        // Executes the weather change queued with resetweather or setweather. The current weather will smoothly fade into the queued weather.
        doweather: doweather,

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
        waitdooranim: waitdooranim,

        // Sets the door tile at (x, y) to be open without an animation.
        setdooropen: setdooropen,

        // Sets the door tile at (x, y) to be closed without an animation.
        setdoorclosed: setdoorclosed,

        // In Emerald, this command consumes its parameters and does nothing. In FireRed, this command is a nop.
        addelevmenuitem: addelevmenuitem,

        // In FireRed and Emerald, this command is a nop.
        showelevmenu: showelevmenu,
        checkcoins: checkcoins,
        givecoins: givecoins,
        takecoins: takecoins,

        // Prepares to start a wild battle against a species at Level level holding item. Running this command will not affect normal wild battles. You start the prepared battle with dowildbattle.
        setwildbattle: setwildbattle,

        // Starts a wild battle against the Pokemon generated by setwildbattle. Blocks script execution until the battle finishes.
        dowildbattle: dowildbattle,
        setvaddress: setvaddress,
        vgoto: vgoto,
        vcall: vcall,
        vgoto_if: vgoto_if,
        vcall_if: vcall_if,
        vmessage: vmessage,
        vloadptr: vloadptr,
        vbufferstring: vbufferstring,

        // Spawns a secondary box showing how many Coins the player has.
        showcoinsbox: showcoinsbox,

        // Hides the secondary box spawned by showcoins. It consumes its arguments but doesn't use them.
        hidecoinsbox: hidecoinsbox,

        // Updates the secondary box spawned by showcoins. It consumes its arguments but doesn't use them.
        updatecoinsbox: updatecoinsbox,

        // Increases the value of the specified game stat by 1. The stat's value will not be allowed to exceed 0x00FFFFFF.
        incrementgamestat: incrementgamestat,

        // Sets the destination that using an Escape Rope or Dig will take the player to.
        setescapewarp: setescapewarp,

        // Blocks script execution until cry finishes.
        waitmoncry: waitmoncry,

        // Writes the name of the specified (box) PC box to the specified buffer.
        bufferboxname: bufferboxname,

        // Sets the color of the text in standard message boxes. 0x00 produces blue (male) text, 0x01 produces red (female) text, 0xFF resets the color to the default for the current OW's gender, and all other values produce black text.
        textcolor: textcolor,

        // The exact purpose of this command is unknown, but it is related to the blue help-text box that appears on the bottom of the screen when the Main Menu is opened.
        loadhelp: loadhelp,

        // The exact purpose of this command is unknown, but it is related to the blue help-text box that appears on the bottom of the screen when the Main Menu is opened.
        unloadhelp: unloadhelp,

        // After using this command, all standard message boxes will use the signpost frame.
        signmsg: signmsg,

        // Ends the effects of signmsg, returning message box frames to normal.
        normalmsg: normalmsg,

        // Compares the value of a hidden variable to a dword.
        comparehiddenvar: comparehiddenvar,

        // Makes the Pokemon in the specified slot of the player's party obedient. It will not randomly disobey orders in battle.
        setmonobedient: setmonobedient,

        // Checks if the Pokemon in the specified slot of the player's party is obedient. If the Pokemon is disobedient, 0x0001 is written to script variable 0x800D (LASTRESULT). If the Pokemon is obedient (or if the specified slot is empty or invalid), 0x0000 is written.
        checkmonobedience: checkmonobedience,

        // Depending on factors I haven't managed to understand yet, this command may cause script execution to jump to the offset specified by the pointer at 0x020375C0.
        execram: execram,

        // Sets worldmapflag to 1. This allows the player to Fly to the corresponding map, if that map has a flightspot.
        setworldmapflag: setworldmapflag,

        // Clone of warpteleport? It is apparently only used in FR/LG, and only with specials.[source]
        warpteleport2: warpteleport2,

        // Changes the location where the player caught the Pokemon in the specified slot of their party.
        setmonmetlocation: setmonmetlocation,
        mossdeepgym1: mossdeepgym1,
        mossdeepgym2: mossdeepgym2,

        // In FireRed, this command is a nop.
        mossdeepgym3: mossdeepgym3,
        mossdeepgym4: mossdeepgym4,
        warp7: warp7,
        cmd_d8: cmdD8,
        cmd_d9: cmdD9,
        hidebox2: hidebox2,
        message3: message3,
        fadescreenswapbuffers: fadescreenswapbuffers,
        buffertrainerclassname: buffertrainerclassname,
        buffertrainername: buffertrainername,
        pokenavcall: pokenavcall,
        warp8: warp8,
        buffercontesttypestring: buffercontesttypestring,

        // Writes the name of the specified (item) item to the specified buffer. If the specified item is a Berry (0x85 - 0xAE) or Poke Ball (0x4) and if the quantity is 2 or more, the buffered string will be pluralized ("IES" or "S" appended). If the specified item is the Enigma Berry, I have no idea what this command does (but testing showed no pluralization). If the specified index is larger than the number of items in the game (0x176), the name of item 0 ("????????") is buffered instead.
        bufferitemnameplural: bufferitemnameplural,
    },

    pub const Kind = packed enum(u8) {
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

    pub const nop = packed struct {};
    pub const nop1 = packed struct {};
    pub const end = packed struct {};
    pub const @"return" = packed struct {};
    pub const call = packed struct {
        destination: lu32,
    };
    pub const goto = packed struct {
        destination: lu32,
    };
    pub const goto_if = packed struct {
        condition: u8,
        destination: lu32,
    };
    pub const call_if = packed struct {
        condition: u8,
        destination: lu32,
    };
    pub const gotostd = packed struct {
        function: u8,
    };
    pub const callstd = packed struct {
        function: u8,
    };
    pub const gotostd_if = packed struct {
        condition: u8,
        function: u8,
    };
    pub const callstd_if = packed struct {
        condition: u8,
        function: u8,
    };
    pub const gotoram = packed struct {};
    pub const killscript = packed struct {};
    pub const setmysteryeventstatus = packed struct {
        value: u8,
    };
    pub const loadword = packed struct {
        destination: u8,
        value: lu32,
    };
    pub const loadbyte = packed struct {
        destination: u8,
        value: u8,
    };
    pub const writebytetoaddr = packed struct {
        value: u8,
        offset: lu32,
    };
    pub const loadbytefromaddr = packed struct {
        destination: u8,
        source: lu32,
    };
    pub const setptrbyte = packed struct {
        source: u8,
        destination: lu32,
    };
    pub const copylocal = packed struct {
        destination: u8,
        source: u8,
    };
    pub const copybyte = packed struct {
        destination: lu32,
        source: lu32,
    };
    pub const setvar = packed struct {
        destination: lu16,
        value: lu16,
    };
    pub const addvar = packed struct {
        destination: lu16,
        value: lu16,
    };
    pub const subvar = packed struct {
        destination: lu16,
        value: lu16,
    };
    pub const copyvar = packed struct {
        destination: lu16,
        source: lu16,
    };
    pub const setorcopyvar = packed struct {
        destination: lu16,
        source: lu16,
    };
    pub const compare_local_to_local = packed struct {
        byte1: u8,
        byte2: u8,
    };
    pub const compare_local_to_value = packed struct {
        a: u8,
        b: u8,
    };
    pub const compare_local_to_addr = packed struct {
        a: u8,
        b: lu32,
    };
    pub const compare_addr_to_local = packed struct {
        a: lu32,
        b: u8,
    };
    pub const compare_addr_to_value = packed struct {
        a: lu32,
        b: u8,
    };
    pub const compare_addr_to_addr = packed struct {
        a: lu32,
        b: lu32,
    };
    pub const compare_var_to_value = packed struct {
        @"var": lu16,
        value: lu16,
    };
    pub const compare_var_to_var = packed struct {
        var1: lu16,
        var2: lu16,
    };
    pub const callnative = packed struct {
        func: lu32,
    };
    pub const gotonative = packed struct {
        func: lu32,
    };
    pub const special = packed struct {
        special_function: lu16,
    };
    pub const specialvar = packed struct {
        output: lu16,
        special_function: lu16,
    };
    pub const waitstate = packed struct {};
    pub const delay = packed struct {
        time: lu16,
    };
    pub const setflag = packed struct {
        a: lu16,
    };
    pub const clearflag = packed struct {
        a: lu16,
    };
    pub const checkflag = packed struct {
        a: lu16,
    };
    pub const initclock = packed struct {
        hour: lu16,
        minute: lu16,
    };
    pub const dodailyevents = packed struct {};
    pub const gettime = packed struct {};
    pub const playse = packed struct {
        sound_number: lu16,
    };
    pub const waitse = packed struct {};
    pub const playfanfare = packed struct {
        fanfare_number: lu16,
    };
    pub const waitfanfare = packed struct {};
    pub const playbgm = packed struct {
        song_number: lu16,
        unknown: u8,
    };
    pub const savebgm = packed struct {
        song_number: lu16,
    };
    pub const fadedefaultbgm = packed struct {};
    pub const fadenewbgm = packed struct {
        song_number: lu16,
    };
    pub const fadeoutbgm = packed struct {
        speed: u8,
    };
    pub const fadeinbgm = packed struct {
        speed: u8,
    };
    pub const warp = packed struct {
        map: lu16,
        warp: u8,
        x: lu16,
        y: lu16,
    };
    pub const warpsilent = packed struct {
        map: lu16,
        warp: u8,
        x: lu16,
        y: lu16,
    };
    pub const warpdoor = packed struct {
        map: lu16,
        warp: u8,
        x: lu16,
        y: lu16,
    };
    pub const warphole = packed struct {
        map: lu16,
    };
    pub const warpteleport = packed struct {
        map: lu16,
        warp: u8,
        x: lu16,
        y: lu16,
    };
    pub const setwarp = packed struct {
        map: lu16,
        warp: u8,
        x: lu16,
        y: lu16,
    };
    pub const setdynamicwarp = packed struct {
        map: lu16,
        warp: u8,
        x: lu16,
        y: lu16,
    };
    pub const setdivewarp = packed struct {
        map: lu16,
        warp: u8,
        x: lu16,
        y: lu16,
    };
    pub const setholewarp = packed struct {
        map: lu16,
        warp: u8,
        x: lu16,
        y: lu16,
    };
    pub const getplayerxy = packed struct {
        x: lu16,
        y: lu16,
    };
    pub const getpartysize = packed struct {};
    pub const additem = packed struct {
        index: lu16,
        quantity: lu16,
    };
    pub const removeitem = packed struct {
        index: lu16,
        quantity: lu16,
    };
    pub const checkitemspace = packed struct {
        index: lu16,
        quantity: lu16,
    };
    pub const checkitem = packed struct {
        index: lu16,
        quantity: lu16,
    };
    pub const checkitemtype = packed struct {
        index: lu16,
    };
    pub const givepcitem = packed struct {
        index: lu16,
        quantity: lu16,
    };
    pub const checkpcitem = packed struct {
        index: lu16,
        quantity: lu16,
    };
    pub const givedecoration = packed struct {
        decoration: lu16,
    };
    pub const takedecoration = packed struct {
        decoration: lu16,
    };
    pub const checkdecor = packed struct {
        decoration: lu16,
    };
    pub const checkdecorspace = packed struct {
        decoration: lu16,
    };
    pub const applymovement = packed struct {
        index: lu16,
        movements: lu32,
    };
    pub const applymovementmap = packed struct {
        index: lu16,
        movements: lu32,
        map: lu16,
    };
    pub const waitmovement = packed struct {
        index: lu16,
    };
    pub const waitmovementmap = packed struct {
        index: lu16,
        map: lu16,
    };
    pub const removeobject = packed struct {
        index: lu16,
    };
    pub const removeobjectmap = packed struct {
        index: lu16,
        map: lu16,
    };
    pub const addobject = packed struct {
        index: lu16,
    };
    pub const addobjectmap = packed struct {
        index: lu16,
        map: lu16,
    };
    pub const setobjectxy = packed struct {
        index: lu16,
        x: lu16,
        y: lu16,
    };
    pub const showobjectat = packed struct {
        index: lu16,
        map: lu16,
    };
    pub const hideobjectat = packed struct {
        index: lu16,
        map: lu16,
    };
    pub const faceplayer = packed struct {};
    pub const turnobject = packed struct {
        index: lu16,
        direction: u8,
    };

    pub const TrainerBattleType = packed enum(u8) {
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

    pub const trainerbattle = packed struct {
        type: TrainerBattleType,
        trainer: lu16,
        local_id: lu16,
        pointers: packed union {
            trainer_battle_single: packed struct {
                pointer1: lu32, // text
                pointer2: lu32, // text
            },
            trainer_battle_continue_script_no_music: packed struct {
                pointer1: lu32, // text
                pointer2: lu32, // text
                pointer3: lu32, // event script
            },
            trainer_battle_continue_script: packed struct {
                pointer1: lu32, // text
                pointer2: lu32, // text
                pointer3: lu32, // event script
            },
            trainer_battle_single_no_intro_text: packed struct {
                pointer1: lu32, // text
            },
            trainer_battle_double: packed struct {
                pointer1: lu32, // text
                pointer2: lu32, // text
                pointer3: lu32, // text
            },
            trainer_battle_rematch: packed struct {
                pointer1: lu32, // text
                pointer2: lu32, // text
            },
            trainer_battle_continue_script_double: packed struct {
                pointer1: lu32, // text
                pointer2: lu32, // text
                pointer3: lu32, // text
                pointer4: lu32, // event script
            },
            trainer_battle_rematch_double: packed struct {
                pointer1: lu32, // text
                pointer2: lu32, // text
                pointer3: lu32, // text
            },
            trainer_battle_continue_script_double_no_music: packed struct {
                pointer1: lu32, // text
                pointer2: lu32, // text
                pointer3: lu32, // text
                pointer4: lu32, // event script
            },
            trainer_battle_pyramid: packed struct {
                pointer1: lu32, // text
                pointer2: lu32, // text
            },
            trainer_battle_set_trainer_a: packed struct {
                pointer1: lu32, // text
                pointer2: lu32, // text
            },
            trainer_battle_set_trainer_b: packed struct {
                pointer1: lu32, // text
                pointer2: lu32, // text
            },
            trainer_battle12: packed struct {
                pointer1: lu32, // text
                pointer2: lu32, // text
            },
        },
    };
    pub const trainerbattlebegin = packed struct {};
    pub const gotopostbattlescript = packed struct {};
    pub const gotobeatenscript = packed struct {};
    pub const checktrainerflag = packed struct {
        trainer: lu16,
    };
    pub const settrainerflag = packed struct {
        trainer: lu16,
    };
    pub const cleartrainerflag = packed struct {
        trainer: lu16,
    };
    pub const setobjectxyperm = packed struct {
        index: lu16,
        x: lu16,
        y: lu16,
    };
    pub const moveobjectoffscreen = packed struct {
        index: lu16,
    };
    pub const setobjectmovementtype = packed struct {
        word: lu16,
        byte: u8,
    };
    pub const waitmessage = packed struct {};
    pub const message = packed struct {
        text: lu32,
    };
    pub const closemessage = packed struct {};
    pub const lockall = packed struct {};
    pub const lock = packed struct {};
    pub const releaseall = packed struct {};
    pub const release = packed struct {};
    pub const waitbuttonpress = packed struct {};
    pub const yesnobox = packed struct {
        x: u8,
        y: u8,
    };
    pub const multichoice = packed struct {
        x: u8,
        y: u8,
        list: u8,
        b: u8,
    };
    pub const multichoicedefault = packed struct {
        x: u8,
        y: u8,
        list: u8,
        default: u8,
        b: u8,
    };
    pub const multichoicegrid = packed struct {
        x: u8,
        y: u8,
        list: u8,
        per_row: u8,
        b: u8,
    };
    pub const drawbox = packed struct {};
    pub const erasebox = packed struct {
        byte1: u8,
        byte2: u8,
        byte3: u8,
        byte4: u8,
    };
    pub const drawboxtext = packed struct {
        byte1: u8,
        byte2: u8,
        byte3: u8,
        byte4: u8,
    };
    pub const drawmonpic = packed struct {
        species: lu16,
        x: u8,
        y: u8,
    };
    pub const erasemonpic = packed struct {};
    pub const drawcontestwinner = packed struct {
        a: u8,
    };
    pub const braillemessage = packed struct {
        text: lu32,
    };
    pub const givemon = packed struct {
        species: lu16,
        level: u8,
        item: lu16,
        unknown1: lu32,
        unknown2: lu32,
        unknown3: u8,
    };
    pub const giveegg = packed struct {
        species: lu16,
    };
    pub const setmonmove = packed struct {
        index: u8,
        slot: u8,
        move: lu16,
    };
    pub const checkpartymove = packed struct {
        index: lu16,
    };
    pub const bufferspeciesname = packed struct {
        out: u8,
        species: lu16,
    };
    pub const bufferleadmonspeciesname = packed struct {
        out: u8,
    };
    pub const bufferpartymonnick = packed struct {
        out: u8,
        slot: lu16,
    };
    pub const bufferitemname = packed struct {
        out: u8,
        item: lu16,
    };
    pub const bufferdecorationname = packed struct {
        out: u8,
        decoration: lu16,
    };
    pub const buffermovename = packed struct {
        out: u8,
        move: lu16,
    };
    pub const buffernumberstring = packed struct {
        out: u8,
        input: lu16,
    };
    pub const bufferstdstring = packed struct {
        out: u8,
        index: lu16,
    };
    pub const bufferstring = packed struct {
        out: u8,
        offset: lu32,
    };
    pub const pokemart = packed struct {
        products: lu32,
    };
    pub const pokemartdecoration = packed struct {
        products: lu32,
    };
    pub const pokemartdecoration2 = packed struct {
        products: lu32,
    };
    pub const playslotmachine = packed struct {
        word: lu16,
    };
    pub const setberrytree = packed struct {
        tree_id: u8,
        berry: u8,
        growth_stage: u8,
    };
    pub const choosecontestmon = packed struct {};
    pub const startcontest = packed struct {};
    pub const showcontestresults = packed struct {};
    pub const contestlinktransfer = packed struct {};
    pub const random = packed struct {
        limit: lu16,
    };
    pub const givemoney = packed struct {
        value: lu32,
        check: u8,
    };
    pub const takemoney = packed struct {
        value: lu32,
        check: u8,
    };
    pub const checkmoney = packed struct {
        value: lu32,
        check: u8,
    };
    pub const showmoneybox = packed struct {
        x: u8,
        y: u8,
        check: u8,
    };
    pub const hidemoneybox = packed struct {};
    pub const updatemoneybox = packed struct {
        x: u8,
        y: u8,
    };
    pub const getpricereduction = packed struct {
        index: lu16,
    };
    pub const fadescreen = packed struct {
        effect: u8,
    };
    pub const fadescreenspeed = packed struct {
        effect: u8,
        speed: u8,
    };
    pub const setflashradius = packed struct {
        word: lu16,
    };
    pub const animateflash = packed struct {
        byte: u8,
    };
    pub const messageautoscroll = packed struct {
        pointer: lu32,
    };
    pub const dofieldeffect = packed struct {
        animation: lu16,
    };
    pub const setfieldeffectargument = packed struct {
        argument: u8,
        param: lu16,
    };
    pub const waitfieldeffect = packed struct {
        animation: lu16,
    };
    pub const setrespawn = packed struct {
        heallocation: lu16,
    };
    pub const checkplayergender = packed struct {};
    pub const playmoncry = packed struct {
        species: lu16,
        effect: lu16,
    };
    pub const setmetatile = packed struct {
        x: lu16,
        y: lu16,
        metatile_number: lu16,
        tile_attrib: lu16,
    };
    pub const resetweather = packed struct {};
    pub const setweather = packed struct {
        type: lu16,
    };
    pub const doweather = packed struct {};
    pub const setstepcallback = packed struct {
        subroutine: u8,
    };
    pub const setmaplayoutindex = packed struct {
        index: lu16,
    };
    pub const setobjectpriority = packed struct {
        index: lu16,
        map: lu16,
        priority: u8,
    };
    pub const resetobjectpriority = packed struct {
        index: lu16,
        map: lu16,
    };
    pub const createvobject = packed struct {
        sprite: u8,
        byte2: u8,
        x: lu16,
        y: lu16,
        elevation: u8,
        direction: u8,
    };
    pub const turnvobject = packed struct {
        index: u8,
        direction: u8,
    };
    pub const opendoor = packed struct {
        x: lu16,
        y: lu16,
    };
    pub const closedoor = packed struct {
        x: lu16,
        y: lu16,
    };
    pub const waitdooranim = packed struct {};
    pub const setdooropen = packed struct {
        x: lu16,
        y: lu16,
    };
    pub const setdoorclosed = packed struct {
        x: lu16,
        y: lu16,
    };
    pub const addelevmenuitem = packed struct {
        a: u8,
        b: lu16,
        c: lu16,
        d: lu16,
    };
    pub const showelevmenu = packed struct {};
    pub const checkcoins = packed struct {
        out: lu16,
    };
    pub const givecoins = packed struct {
        count: lu16,
    };
    pub const takecoins = packed struct {
        count: lu16,
    };
    pub const setwildbattle = packed struct {
        species: lu16,
        level: u8,
        item: lu16,
    };
    pub const dowildbattle = packed struct {};
    pub const setvaddress = packed struct {
        pointer: lu32,
    };
    pub const vgoto = packed struct {
        pointer: lu32,
    };
    pub const vcall = packed struct {
        pointer: lu32,
    };
    pub const vgoto_if = packed struct {
        byte: u8,
        pointer: lu32,
    };
    pub const vcall_if = packed struct {
        byte: u8,
        pointer: lu32,
    };
    pub const vmessage = packed struct {
        pointer: lu32,
    };
    pub const vloadptr = packed struct {
        pointer: lu32,
    };
    pub const vbufferstring = packed struct {
        byte: u8,
        pointer: lu32,
    };
    pub const showcoinsbox = packed struct {
        x: u8,
        y: u8,
    };
    pub const hidecoinsbox = packed struct {
        x: u8,
        y: u8,
    };
    pub const updatecoinsbox = packed struct {
        x: u8,
        y: u8,
    };
    pub const incrementgamestat = packed struct {
        stat: u8,
    };
    pub const setescapewarp = packed struct {
        map: lu16,
        warp: u8,
        x: lu16,
        y: lu16,
    };
    pub const waitmoncry = packed struct {};
    pub const bufferboxname = packed struct {
        out: u8,
        box: lu16,
    };
    pub const textcolor = packed struct {
        color: u8,
    };
    pub const loadhelp = packed struct {
        pointer: lu32,
    };
    pub const unloadhelp = packed struct {};
    pub const signmsg = packed struct {};
    pub const normalmsg = packed struct {};
    pub const comparehiddenvar = packed struct {
        a: u8,
        value: lu32,
    };
    pub const setmonobedient = packed struct {
        slot: lu16,
    };
    pub const checkmonobedience = packed struct {
        slot: lu16,
    };
    pub const execram = packed struct {};
    pub const setworldmapflag = packed struct {
        worldmapflag: lu16,
    };
    pub const warpteleport2 = packed struct {
        map: lu16,
        warp: u8,
        x: lu16,
        y: lu16,
    };
    pub const setmonmetlocation = packed struct {
        slot: lu16,
        location: u8,
    };
    pub const mossdeepgym1 = packed struct {
        unknown: lu16,
    };
    pub const mossdeepgym2 = packed struct {};
    pub const mossdeepgym3 = packed struct {
        @"var": lu16,
    };
    pub const mossdeepgym4 = packed struct {};
    pub const warp7 = packed struct {
        map: lu16,
        byte: u8,
        word1: lu16,
        word2: lu16,
    };
    pub const cmdD8 = packed struct {};
    pub const cmdD9 = packed struct {};
    pub const hidebox2 = packed struct {};
    pub const message3 = packed struct {
        pointer: lu32,
    };
    pub const fadescreenswapbuffers = packed struct {
        byte: u8,
    };
    pub const buffertrainerclassname = packed struct {
        out: u8,
        class: lu16,
    };
    pub const buffertrainername = packed struct {
        out: u8,
        trainer: lu16,
    };
    pub const pokenavcall = packed struct {
        pointer: lu32,
    };
    pub const warp8 = packed struct {
        map: lu16,
        byte: u8,
        word1: lu16,
        word2: lu16,
    };
    pub const buffercontesttypestring = packed struct {
        out: u8,
        word: lu16,
    };
    pub const bufferitemnameplural = packed struct {
        out: u8,
        item: lu16,
        quantity: lu16,
    };
};

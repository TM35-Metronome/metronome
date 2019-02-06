const Kind = @import("enum.zig").Kind;

const lu16 = u16;
const lu32 = u32;

pub const Command = packed struct {
    tag: Kind,

    data: packed union {
        // Does nothing.
        nop: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Does nothing.
        nop1: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Terminates script execution.
        end: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Jumps back to after the last-executed call statement, and continues script execution from there.
        @"return": packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Jumps to destination and continues script execution from there. The location of the calling script is remembered and can be returned to later.
        call: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            destination: lu32,
        },

        // Jumps to destination and continues script execution from there.
        goto: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            destination: lu32,
        },

        // If the result of the last comparison matches condition (see Comparison operators), jumps to destination and continues script execution from there.
        goto_if: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            condition: u8,
            destination: lu32,
        },

        // If the result of the last comparison matches condition (see Comparison operators), calls destination.
        call_if: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            condition: u8,
            destination: lu32,
        },

        // Jumps to the standard function at index function.
        gotostd: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            function: u8,
        },

        // callstd function names
        //  STD_OBTAIN_ITEM = 0
        //  STD_FIND_ITEM = 1
        //  STD_OBTAIN_DECORATION = 7
        //  STD_REGISTER_MATCH_CALL = 8

        // Calls the standard function at index function.
        callstd: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            function: u8,
        },

        // If the result of the last comparison matches condition (see Comparison operators), jumps to the standard function at index function.
        gotostd_if: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            condition: u8,
            function: u8,
        },

        // If the result of the last comparison matches condition (see Comparison operators), calls the standard function at index function.
        callstd_if: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            condition: u8,
            function: u8,
        },

        // Executes a script stored in a default RAM location.
        gotoram: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Terminates script execution and "resets the script RAM".
        killscript: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Sets some status related to Mystery Event.
        setmysteryeventstatus: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            value: u8,
        },

        // Sets the specified script bank to value.
        loadword: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            destination: u8,
            value: lu32,
        },

        // Sets the specified script bank to value.
        loadbyte: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            destination: u8,
            value: u8,
        },

        // Sets the byte at offset to value.
        writebytetoaddr: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            value: u8,
            offset: lu32,
        },

        // Copies the byte value at source into the specified script bank.
        loadbytefromaddr: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            destination: u8,
            source: lu32,
        },

        // Not sure. Judging from XSE's description I think it takes the least-significant byte in bank source and writes it to destination.
        setptrbyte: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            source: u8,
            destination: lu32,
        },

        // Copies the contents of bank source into bank destination.
        copylocal: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            destination: u8,
            source: u8,
        },

        // Copies the byte at source to destination, replacing whatever byte was previously there.
        copybyte: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            destination: lu32,
            source: lu32,
        },

        // Changes the value of destination to value.
        setvar: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            destination: lu16,
            value: lu16,
        },

        //  // Changes the value of destination by adding value to it. Overflow is not prevented (0xFFFF + 1 = 0x0000).
        addvar: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            destination: lu16,
            value: lu16,
        },

        //  // Changes the value of destination by subtracting value to it. Overflow is not prevented (0x0000 - 1 = 0xFFFF).
        subvar: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            destination: lu16,
            value: lu16,
        },

        // Copies the value of source into destination.
        copyvar: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            destination: lu16,
            source: lu16,
        },

        // If source is not a variable, then this function acts like setvar. Otherwise, it acts like copyvar.
        setorcopyvar: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            destination: lu16,
            source: lu16,
        },

        // Compares the values of script banks a and b, after forcing the values to bytes.
        compare_local_to_local: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            byte1: u8,
            byte2: u8,
        },

        // Compares the least-significant byte of the value of script bank a to a fixed byte value (b).
        compare_local_to_value: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            a: u8,
            b: u8,
        },

        // Compares the least-significant byte of the value of script bank a to the byte located at offset b.
        compare_local_to_addr: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            a: u8,
            b: lu32,
        },

        // Compares the byte located at offset a to the least-significant byte of the value of script bank b.
        compare_addr_to_local: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            a: lu32,
            b: u8,
        },

        // Compares the byte located at offset a to a fixed byte value (b).
        compare_addr_to_value: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            a: lu32,
            b: u8,
        },

        // Compares the byte located at offset a to the byte located at offset b.
        compare_addr_to_addr: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            a: lu32,
            b: lu32,
        },

        // Compares the value of `var` to a fixed word value (b).
        compare_var_to_value: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            @"var": lu16,
            value: lu16,
        },

        // Compares the value of `var1` to the value of `var2`.
        compare_var_to_var: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            var1: lu16,
            var2: lu16,
        },

        // Calls the native C function stored at `func`.
        callnative: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            func: lu32,
        },

        // Replaces the script with the function stored at `func`. Execution returns to the bytecode script when func returns TRUE.
        gotonative: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            func: lu32,
        },

        // Calls a special function; that is, a function designed for use by scripts and listed in a table of pointers.
        special: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            special_function: lu16,
        },

        // Calls a special function. That function's output (if any) will be written to the variable you specify.
        specialvar: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            output: lu16,
            special_function: lu16,
        },

        // Blocks script execution until a command or ASM code manually unblocks it. Generally used with specific commands and specials. If this command runs, and a subsequent command or piece of ASM does not unblock state, the script will remain blocked indefinitely (essentially a hang).
        waitstate: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Blocks script execution for time (frames? milliseconds?).
        delay: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            time: lu16,
        },

        // Sets a to 1.
        setflag: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            a: lu16,
        },

        // Sets a to 0.
        clearflag: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            a: lu16,
        },

        // Compares a to 1.
        checkflag: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            a: lu16,
        },

        // Initializes the RTC`s local time offset to the given hour and minute. In FireRed, this command is a nop.
        initclock: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            hour: lu16,
            minute: lu16,
        },

        // Runs time based events. In FireRed, this command is a nop.
        dodailyevents: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Sets the values of variables 0x8000, 0x8001, and 0x8002 to the current hour, minute, and second. In FRLG, this command sets those variables to zero.
        gettime: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Plays the specified (sound_number) sound. Only one sound may play at a time, with newer ones interrupting older ones.
        playse: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            sound_number: lu16,
        },

        // Blocks script execution until the currently-playing sound (triggered by playse) finishes playing.
        waitse: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Plays the specified (fanfare_number) fanfare.
        playfanfare: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            fanfare_number: lu16,
        },

        // Blocks script execution until all currently-playing fanfares finish.
        waitfanfare: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Plays the specified (song_number) song. The byte is apparently supposed to be 0x00.
        playbgm: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            song_number: lu16,
            unknown: u8,
        },

        // Saves the specified (song_number) song to be played later.
        savebgm: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            song_number: lu16,
        },

        // Crossfades the currently-playing song into the map's default song.
        fadedefaultbgm: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Crossfades the currently-playng song into the specified (song_number) song.
        fadenewbgm: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            song_number: lu16,
        },

        // Fades out the currently-playing song.
        fadeoutbgm: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            speed: u8,
        },

        // Fades the previously-playing song back in.
        fadeinbgm: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            speed: u8,
        },

        // Sends the player to Warp warp on Map bank.map. If the specified warp is 0xFF, then the player will instead be sent to (X, Y) on the map.
        warp: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            map: lu16,
            warp: u8,
            X: lu16,
            Y: lu16,
        },

        // Clone of warp that does not play a sound effect.
        warpsilent: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            map: lu16,
            warp: u8,
            X: lu16,
            Y: lu16,
        },

        // Clone of warp that plays a door opening animation before stepping upwards into it.
        warpdoor: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            map: lu16,
            warp: u8,
            X: lu16,
            Y: lu16,
        },

        // Warps the player to another map using a hole animation.
        warphole: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            map: lu16,
        },

        // Clone of warp that uses a teleport effect. It is apparently only used in R/S/E.
        warpteleport: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            map: lu16,
            warp: u8,
            X: lu16,
            Y: lu16,
        },

        // Sets the warp destination to be used later.
        setwarp: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            map: lu16,
            warp: u8,
            X: lu16,
            Y: lu16,
        },

        // Sets the warp destination that a warp to Warp 127 on Map 127.127 will connect to. Useful when a map has warps that need to go to script-controlled locations (i.e. elevators).
        setdynamicwarp: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            map: lu16,
            warp: u8,
            X: lu16,
            Y: lu16,
        },

        // Sets the destination that diving or emerging from a dive will take the player to.
        setdivewarp: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            map: lu16,
            warp: u8,
            X: lu16,
            Y: lu16,
        },

        // Sets the destination that falling into a hole will take the player to.
        setholewarp: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            map: lu16,
            warp: u8,
            X: lu16,
            Y: lu16,
        },

        // Retrieves the player's zero-indexed X- and Y-coordinates in the map, and stores them in the specified variables.
        getplayerxy: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            X: lu16,
            Y: lu16,
        },

        // Retrieves the number of Pokemon in the player's party, and stores that number in variable 0x800D (LASTRESULT).
        getpartysize: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Attempts to add quantity of item index to the player's Bag. If the player has enough room, the item will be added and variable 0x800D (LASTRESULT) will be set to 0x0001; otherwise, LASTRESULT is set to 0x0000.
        giveitem: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            index: lu16,
            quantity: lu16,
        },

        // Removes quantity of item index from the player's Bag.
        takeitem: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            index: lu16,
            quantity: lu16,
        },

        // Checks if the player has enough space in their Bag to hold quantity more of item index. Sets variable 0x800D (LASTRESULT) to 0x0001 if there is room, or 0x0000 is there is no room.
        checkitemspace: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            index: lu16,
            quantity: lu16,
        },

        // Checks if the player has quantity or more of item index in their Bag. Sets variable 0x800D (LASTRESULT) to 0x0001 if the player has enough of the item, or 0x0000 if they have fewer than quantity of the item.
        checkitem: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            index: lu16,
            quantity: lu16,
        },

        // Checks which Bag pocket the specified (index) item belongs in, and writes the value to variable 0x800D (LASTRESULT). This script is used to show the name of the proper Bag pocket when the player receives an item via callstd (simplified to giveitem in XSE).
        checkitemtype: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            index: lu16,
        },

        // Adds a quantity amount of item index to the player's PC. Both arguments can be variables.
        givepcitem: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            index: lu16,
            quantity: lu16,
        },

        // Checks for quantity amount of item index in the player's PC. Both arguments can be variables.
        checkpcitem: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            index: lu16,
            quantity: lu16,
        },

        // Adds decoration to the player's PC. In FireRed, this command is a nop. (The argument is read, but not used for anything.)
        givedecoration: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            decoration: lu16,
        },

        // Removes a decoration from the player's PC. In FireRed, this command is a nop. (The argument is read, but not used for anything.)
        takedecoration: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            decoration: lu16,
        },

        // Checks for decoration in the player's PC. In FireRed, this command is a nop. (The argument is read, but not used for anything.)
        checkdecor: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            decoration: lu16,
        },

        // Checks if the player has enough space in their PC to hold decoration. Sets variable 0x800D (LASTRESULT) to 0x0001 if there is room, or 0x0000 is there is no room. In FireRed, this command is a nop. (The argument is read, but not used for anything.)
        checkdecorspace: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            decoration: lu16,
        },

        // Applies the movement data at movements to the specified (index) Object. Also closes any standard message boxes that are still open.
        // If no map is specified, then the current map is used.
        applymovement: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            index: lu16,
            movements: lu32,
        },

        // Really only useful if the object has followed from one map to another (e.g. Wally during the catching event).
        applymovementmap: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            index: lu16,
            movements: lu32,
            map: lu16,
        },

        // Blocks script execution until the movements being applied to the specified (index) Object finish. If the specified Object is 0x0000, then the command will block script execution until all Objects affected by applymovement finish their movements. If the specified Object is not currently being manipulated with applymovement, then this command does nothing.
        // If no map is specified, then the current map is used.
        waitmovement: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            index: lu16,
        },

        waitmovementmap: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            index: lu16,
            map: lu16,
        },

        // Attempts to hide the specified (index) Object on the specified (map_group, map_num) map, by setting its visibility flag if it has a valid one. If the Object does not have a valid visibility flag, this command does nothing.
        // If no map is specified, then the current map is used.
        removeobject: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            index: lu16,
        },
        removeobjectmap: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            index: lu16,
            map: lu16,
        },

        // Unsets the specified (index) Object's visibility flag on the specified (map_group, map_num) map if it has a valid one. If the Object does not have a valid visibility flag, this command does nothing.
        // If no map is specified, then the current map is used.
        addobject: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            index: lu16,
        },

        addobjectmap: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            index: lu16,
            map: lu16,
        },

        // Sets the specified (index) Object's position on the current map.
        setobjectxy: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            index: lu16,
            x: lu16,
            y: lu16,
        },

        showobjectat: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            index: lu16,
            map: lu16,
        },

        hideobjectat: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            index: lu16,
            map: lu16,
        },

        // If the script was called by an Object, then that Object will turn to face toward the metatile that the player is standing on.
        faceplayer: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        turnobject: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            index: lu16,
            direction: u8,
        },

        // TRAINER_BATTLE_SINGLE
        // TRAINER_BATTLE_CONTINUE_SCRIPT_NO_MUSIC
        // TRAINER_BATTLE_CONTINUE_SCRIPT
        // TRAINER_BATTLE_SINGLE_NO_INTRO_TEXT
        // TRAINER_BATTLE_DOUBLE
        // TRAINER_BATTLE_REMATCH
        // TRAINER_BATTLE_CONTINUE_SCRIPT_DOUBLE
        // TRAINER_BATTLE_REMATCH_DOUBLE
        // TRAINER_BATTLE_CONTINUE_SCRIPT_DOUBLE_NO_MUSIC
        // TRAINER_BATTLE_PYRAMID
        // TRAINER_BATTLE_SET_TRAINER_A
        // TRAINER_BATTLE_SET_TRAINER_B
        // TRAINER_BATTLE_12

        // If the Trainer flag for Trainer index is not set, this command does absolutely nothing.
        trainerbattle: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            type: u8,
            trainer: lu16,
            local_id: lu16,
            pointers: packed union {
                TRAINER_BATTLE_SINGLE: packed struct {
                    pointer1: lu32, // text
                    pointer2: lu32, // text
                },
                TRAINER_BATTLE_CONTINUE_SCRIPT_NO_MUSIC: packed struct {
                    pointer1: lu32, // text
                    pointer2: lu32, // text
                    pointer3: lu32, // event script
                },
                TRAINER_BATTLE_CONTINUE_SCRIPT: packed struct {
                    pointer1: lu32, // text
                    pointer2: lu32, // text
                    pointer3: lu32, // event script
                },
                TRAINER_BATTLE_SINGLE_NO_INTRO_TEXT: packed struct {
                    pointer1: lu32, // text
                },
                TRAINER_BATTLE_DOUBLE: packed struct {
                    pointer1: lu32, // text
                    pointer2: lu32, // text
                    pointer3: lu32, // text
                },
                TRAINER_BATTLE_REMATCH: packed struct {
                    pointer1: lu32, // text
                    pointer2: lu32, // text
                },
                TRAINER_BATTLE_CONTINUE_SCRIPT_DOUBLE: packed struct {
                    pointer1: lu32, // text
                    pointer2: lu32, // text
                    pointer3: lu32, // text
                    pointer4: lu32, // event script
                },
                TRAINER_BATTLE_REMATCH_DOUBLE: packed struct {
                    pointer1: lu32, // text
                    pointer2: lu32, // text
                    pointer3: lu32, // text
                },
                TRAINER_BATTLE_CONTINUE_SCRIPT_DOUBLE_NO_MUSIC: packed struct {
                    pointer1: lu32, // text
                    pointer2: lu32, // text
                    pointer3: lu32, // text
                    pointer4: lu32, // event script
                },
                TRAINER_BATTLE_PYRAMID: packed struct {
                    pointer1: lu32, // text
                    pointer2: lu32, // text
                },
                TRAINER_BATTLE_SET_TRAINER_A: packed struct {
                    pointer1: lu32, // text
                    pointer2: lu32, // text
                },
                TRAINER_BATTLE_SET_TRAINER_B: packed struct {
                    pointer1: lu32, // text
                    pointer2: lu32, // text
                },
                TRAINER_BATTLE_12: packed struct {
                    pointer1: lu32, // text
                    pointer2: lu32, // text
                },
            },
        },

        // Starts a trainer battle using the battle information stored in RAM (usually by trainerbattle, which actually calls this command behind-the-scenes), and blocks script execution until the battle finishes.
        trainerbattlebegin: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Goes to address after the trainerbattle command (called by the battle functions, see battle_setup.c)
        gotopostbattlescript: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Goes to address specified in the trainerbattle command (called by the battle functions, see battle_setup.c)
        gotobeatenscript: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Compares Flag (trainer + 0x500) to 1. (If the flag is set, then the trainer has been defeated by the player.)
        checktrainerflag: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            trainer: lu16,
        },

        // Sets Flag (trainer + 0x500).
        settrainerflag: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            trainer: lu16,
        },

        // Clears Flag (trainer + 0x500).
        cleartrainerflag: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            trainer: lu16,
        },

        setobjectxyperm: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            index: lu16,
            x: lu16,
            y: lu16,
        },

        moveobjectoffscreen: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            index: lu16,
        },

        setobjectmovementtype: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            word: lu16,
            byte: u8,
        },

        // If a standard message box (or its text) is being drawn on-screen, this command blocks script execution until the box and its text have been fully drawn.
        waitmessage: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Starts displaying a standard message box containing the specified text. If text is a pointer, then the string at that offset will be loaded and used. If text is script bank 0, then the value of script bank 0 will be treated as a pointer to the text. (You can use loadpointer to place a string pointer in a script bank.)
        message: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            text: lu32,
        },

        // Closes the current message box.
        closemessage: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Ceases movement for all Objects on-screen.
        lockall: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // If the script was called by an Object, then that Object's movement will cease.
        lock: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Resumes normal movement for all Objects on-screen, and closes any standard message boxes that are still open.
        releaseall: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // If the script was called by an Object, then that Object's movement will resume. This command also closes any standard message boxes that are still open.
        release: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Blocks script execution until the player presses any key.
        waitbuttonpress: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Displays a YES/NO multichoice box at the specified coordinates, and blocks script execution until the user makes a selection. Their selection is stored in variable 0x800D (LASTRESULT); 0x0000 for "NO" or if the user pressed B, and 0x0001 for "YES".
        yesnobox: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            x: u8,
            y: u8,
        },

        // Displays a multichoice box from which the user can choose a selection, and blocks script execution until a selection is made. Lists of options are predefined and the one to be used is specified with list. If b is set to a non-zero value, then the user will not be allowed to back out of the multichoice with the B button.
        multichoice: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            x: u8,
            y: u8,
            list: u8,
            b: u8,
        },

        // Displays a multichoice box from which the user can choose a selection, and blocks script execution until a selection is made. Lists of options are predefined and the one to be used is specified with list. The default argument determines the initial position of the cursor when the box is first opened; it is zero-indexed, and if it is too large, it is treated as 0x00. If b is set to a non-zero value, then the user will not be allowed to back out of the multichoice with the B button.
        multichoicedefault: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            x: u8,
            y: u8,
            list: u8,
            default: u8,
            b: u8,
        },

        // Displays a multichoice box from which the user can choose a selection, and blocks script execution until a selection is made. Lists of options are predefined and the one to be used is specified with list. The per_row argument determines how many list items will be shown on a single row of the box.
        multichoicegrid: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            x: u8,
            y: u8,
            list: u8,
            per_row: u8,
            B: u8,
        },

        // Nopped in Emerald.
        drawbox: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Nopped in Emerald, but still consumes parameters.
        erasebox: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            byte1: u8,
            byte2: u8,
            byte3: u8,
            byte4: u8,
        },

        // Nopped in Emerald, but still consumes parameters.
        drawboxtext: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            byte1: u8,
            byte2: u8,
            byte3: u8,
            byte4: u8,
        },

        // Displays a box containing the front sprite for the specified (species) Pokemon species.
        drawmonpic: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            species: lu16,
            x: u8,
            y: u8,
        },

        // Hides all boxes displayed with drawmonpic.
        erasemonpic: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Draws an image of the winner of the contest. In FireRed, this command is a nop. (The argument is discarded.)
        drawcontestwinner: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            a: u8,
        },

        // Displays the string at pointer as braille text in a standard message box. The string must be formatted to use braille characters and needs to provide six extra starting characters that are skipped (in RS, these characters determined the box's size and position, but in Emerald these are calculated automatically).
        braillemessage: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            text: lu32,
        },

        // Gives the player one of the specified (species) Pokemon at level level holding item. The unknown arguments should all be zeroes.
        givemon: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            species: lu16,
            level: u8,
            item: lu16,
            unknown1: lu32,
            unknown2: lu32,
            unknown3: u8,
        },

        giveegg: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            species: lu16,
        },

        setmonmove: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            index: u8,
            slot: u8,
            move: lu16,
        },

        // Checks if at least one Pokemon in the player's party knows the specified (index) attack. If so, variable 0x800D (LASTRESULT) is set to the (zero-indexed) slot number of the first Pokemon that knows the move. If not, LASTRESULT is set to 0x0006. Variable 0x8004 is also set to this Pokemon's species.
        checkpartymove: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            index: lu16,
        },

        // Writes the name of the Pokemon at index species to the specified buffer.
        bufferspeciesname: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            out: u8,
            species: lu16,
        },

        // Writes the name of the species of the first Pokemon in the player's party to the specified buffer.
        bufferleadmonspeciesname: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            out: u8,
        },

        // Writes the nickname of the Pokemon in slot slot (zero-indexed) of the player's party to the specified buffer. If an empty or invalid slot is specified, ten spaces ("") are written to the buffer.
        bufferpartymonnick: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            out: u8,
            slot: lu16,
        },

        // Writes the name of the item at index item to the specified buffer. If the specified index is larger than the number of items in the game (0x176), the name of item 0 ("????????") is buffered instead.
        bufferitemname: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            out: u8,
            item: lu16,
        },

        // Writes the name of the decoration at index decoration to the specified buffer. In FireRed, this command is a nop.
        bufferdecorationname: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            out: u8,
            decoration: lu16,
        },

        // Writes the name of the move at index move to the specified buffer.
        buffermovename: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            out: u8,
            move: lu16,
        },

        // Converts the value of input to a decimal string, and writes that string to the specified buffer.
        buffernumberstring: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            out: u8,
            input: lu16,
        },

        // Writes the standard string identified by index to the specified buffer. This command has no protections in place at all, so specifying an invalid standard string (e.x. 0x2B) can and usually will cause data corruption.
        bufferstdstring: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            out: u8,
            index: lu16,
        },

        // Copies the string at offset to the specified buffer.
        bufferstring: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            out: u8,
            offset: lu32,
        },

        // Opens the Pokemart system, offering the specified products for sale.
        pokemart: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            products: lu32,
        },

        // Opens the Pokemart system and treats the list of items as decorations.
        pokemartdecoration: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            products: lu32,
        },

        // Apparent clone of pokemartdecoration.
        pokemartdecoration2: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            products: lu32,
        },

        // Starts up the slot machine minigame.
        playslotmachine: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            word: lu16,
        },

        // Sets a berry tree's specific berry and growth stage. In FireRed, this command is a nop.
        setberrytree: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            tree_id: u8,
            berry: u8,
            growth_stage: u8,
        },

        // This allows you to choose a Pokemon to use in a contest. In FireRed, this command sets the byte at 0x03000EA8 to 0x01.
        choosecontestmon: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Starts a contest. In FireRed, this command is a nop.
        startcontest: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Shows the results of a contest. In FireRed, this command is a nop.
        showcontestresults: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Starts a contest over a link connection. In FireRed, this command is a nop.
        contestlinktransfer: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Stores a random integer between 0 and limit in variable 0x800D (LASTRESULT).
        random: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            limit: lu16,
        },

        // If check is 0x00, this command adds value to the player's money.
        givemoney: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            value: lu32,
            check: u8,
        },

        // If check is 0x00, this command subtracts value from the player's money.
        takemoney: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            value: lu32,
            check: u8,
        },

        // If check is 0x00, this command will check if the player has value or more money; script variable 0x800D (LASTRESULT) is set to 0x0001 if the player has enough money, or 0x0000 if the do not.
        checkmoney: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            value: lu32,
            check: u8,
        },

        // Spawns a secondary box showing how much money the player has.
        showmoneybox: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            x: u8,
            y: u8,
            check: u8,
        },

        // Hides the secondary box spawned by showmoney.
        hidemoneybox: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Updates the secondary box spawned by showmoney. Consumes but does not use arguments.
        updatemoneybox: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            x: u8,
            y: u8,
        },

        // Gets the price reduction for the index given. In FireRed, this command is a nop.
        getpricereduction: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            index: lu16,
        },

        // Fades the screen to and from black and white. Mode 0x00 fades from black, mode 0x01 fades out to black, mode 0x2 fades in from white, and mode 0x3 fades out to white.
        fadescreen: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            effect: u8,
        },

        // Fades the screen to and from black and white. Mode 0x00 fades from black, mode 0x01 fades out to black, mode 0x2 fades in from white, and mode 0x3 fades out to white. Other modes may exist.
        fadescreenspeed: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            effect: u8,
            speed: u8,
        },

        setflashradius: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            word: lu16,
        },

        animateflash: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            byte: u8,
        },

        messageautoscroll: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            pointer: lu32,
        },

        // Executes the specified field move animation.
        dofieldeffect: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            animation: lu16,
        },

        // Sets up the field effect argument argument with the value value.
        setfieldeffectargument: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            argument: u8,
            param: lu16,
        },

        // Blocks script execution until all playing field move animations complete.
        waitfieldeffect: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            animation: lu16,
        },

        // Sets which healing place the player will return to if all of the Pokemon in their party faint.
        setrespawn: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            heallocation: lu16,
        },

        // Checks the player's gender. If male, then 0x0000 is stored in variable 0x800D (LASTRESULT). If female, then 0x0001 is stored in LASTRESULT.
        checkplayergender: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Plays the specified (species) Pokemon's cry. You can use waitcry to block script execution until the sound finishes.
        playmoncry: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            species: lu16,
            effect: lu16,
        },

        // Changes the metatile at (x, y) on the current map.
        setmetatile: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            x: lu16,
            y: lu16,
            metatile_number: lu16,
            tile_attrib: lu16,
        },

        // Queues a weather change to the default weather for the map.
        resetweather: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Queues a weather change to type weather.
        setweather: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            type: lu16,
        },

        // Executes the weather change queued with resetweather or setweather. The current weather will smoothly fade into the queued weather.
        doweather: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // This command manages cases in which maps have tiles that change state when stepped on (specifically, cracked/breakable floors).
        setstepcallback: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            subroutine: u8,
        },

        setmaplayoutindex: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            index: lu16,
        },

        setobjectpriority: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            index: lu16,
            map: lu16,
            priority: u8,
        },

        resetobjectpriority: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            index: lu16,
            map: lu16,
        },

        createvobject: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            sprite: u8,
            byte2: u8,
            x: lu16,
            y: lu16,
            elevation: u8,
            direction: u8,
        },

        turnvobject: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            index: u8,
            direction: u8,
        },

        // Opens the door metatile at (X, Y) with an animation.
        opendoor: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            x: lu16,
            y: lu16,
        },

        // Closes the door metatile at (X, Y) with an animation.
        closedoor: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            x: lu16,
            y: lu16,
        },

        // Waits for the door animation started with opendoor or closedoor to finish.
        waitdooranim: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Sets the door tile at (x, y) to be open without an animation.
        setdooropen: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            x: lu16,
            y: lu16,
        },

        // Sets the door tile at (x, y) to be closed without an animation.
        setdoorclosed: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            x: lu16,
            y: lu16,
        },

        // In Emerald, this command consumes its parameters and does nothing. In FireRed, this command is a nop.
        addelevmenuitem: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            a: u8,
            b: lu16,
            c: lu16,
            d: lu16,
        },

        // In FireRed and Emerald, this command is a nop.
        showelevmenu: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        checkcoins: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            out: lu16,
        },

        givecoins: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            count: lu16,
        },

        takecoins: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            count: lu16,
        },

        // Prepares to start a wild battle against a species at Level level holding item. Running this command will not affect normal wild battles. You start the prepared battle with dowildbattle.
        setwildbattle: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            species: lu16,
            level: u8,
            item: lu16,
        },

        // Starts a wild battle against the Pokemon generated by setwildbattle. Blocks script execution until the battle finishes.
        dowildbattle: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        setvaddress: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            pointer: lu32,
        },

        vgoto: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            pointer: lu32,
        },

        vcall: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            pointer: lu32,
        },

        vgoto_if: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            byte: u8,
            pointer: lu32,
        },

        vcall_if: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            byte: u8,
            pointer: lu32,
        },

        vmessage: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            pointer: lu32,
        },

        vloadptr: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            pointer: lu32,
        },

        vbufferstring: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            byte: u8,
            pointer: lu32,
        },

        // Spawns a secondary box showing how many Coins the player has.
        showcoinsbox: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            x: u8,
            y: u8,
        },

        // Hides the secondary box spawned by showcoins. It consumes its arguments but doesn't use them.
        hidecoinsbox: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            x: u8,
            y: u8,
        },

        // Updates the secondary box spawned by showcoins. It consumes its arguments but doesn't use them.
        updatecoinsbox: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            x: u8,
            y: u8,
        },

        // Increases the value of the specified game stat by 1. The stat's value will not be allowed to exceed 0x00FFFFFF.
        incrementgamestat: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            stat: u8,
        },

        // Sets the destination that using an Escape Rope or Dig will take the player to.
        setescapewarp: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            map: lu16,
            warp: u8,
            x: lu16,
            y: lu16,
        },

        // Blocks script execution until cry finishes.
        waitmoncry: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Writes the name of the specified (box) PC box to the specified buffer.
        bufferboxname: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            out: u8,
            box: lu16,
        },

        // Sets the color of the text in standard message boxes. 0x00 produces blue (male) text, 0x01 produces red (female) text, 0xFF resets the color to the default for the current OW's gender, and all other values produce black text.
        textcolor: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            color: u8,
        },

        // The exact purpose of this command is unknown, but it is related to the blue help-text box that appears on the bottom of the screen when the Main Menu is opened.
        loadhelp: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            pointer: lu32,
        },

        // The exact purpose of this command is unknown, but it is related to the blue help-text box that appears on the bottom of the screen when the Main Menu is opened.
        unloadhelp: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // After using this command, all standard message boxes will use the signpost frame.
        signmsg: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Ends the effects of signmsg, returning message box frames to normal.
        normalmsg: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Compares the value of a hidden variable to a dword.
        comparehiddenvar: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            a: u8,
            value: lu32,
        },

        // Makes the Pokemon in the specified slot of the player's party obedient. It will not randomly disobey orders in battle.
        setmonobedient: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            slot: lu16,
        },

        // Checks if the Pokemon in the specified slot of the player's party is obedient. If the Pokemon is disobedient, 0x0001 is written to script variable 0x800D (LASTRESULT). If the Pokemon is obedient (or if the specified slot is empty or invalid), 0x0000 is written.
        checkmonobedience: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            slot: lu16,
        },

        // Depending on factors I haven't managed to understand yet, this command may cause script execution to jump to the offset specified by the pointer at 0x020375C0.
        execram: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // Sets worldmapflag to 1. This allows the player to Fly to the corresponding map, if that map has a flightspot.
        setworldmapflag: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            worldmapflag: lu16,
        },

        // Clone of warpteleport? It is apparently only used in FR/LG, and only with specials.[source]
        warpteleport2: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            map: lu16,
            warp: u8,
            x: lu16,
            y: lu16,
        },

        // Changes the location where the player caught the Pokemon in the specified slot of their party.
        setmonmetlocation: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            slot: lu16,
            location: u8,
        },

        mossdeepgym1: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            unknown: lu16,
        },

        mossdeepgym2: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        // In FireRed, this command is a nop.
        mossdeepgym3: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            @"var": lu16,
        },

        mossdeepgym4: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        warp7: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            map: lu16,
            byte: u8,
            word1: lu16,
            word2: lu16,
        },

        cmdD8: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        cmdD9: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        hidebox2: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
        },

        message3: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            pointer: lu32,
        },

        fadescreenswapbuffers: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            byte: u8,
        },

        buffertrainerclassname: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            out: u8,
            class: lu16,
        },

        buffertrainername: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            out: u8,
            trainer: lu16,
        },

        pokenavcall: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            pointer: lu32,
        },

        warp8: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            map: lu16,
            byte: u8,
            word1: lu16,
            word2: lu16,
        },

        buffercontesttypestring: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            out: u8,
            word: lu16,
        },

        // Writes the name of the specified (item) item to the specified buffer. If the specified item is a Berry (0x85 - 0xAE) or Poke Ball (0x4) and if the quantity is 2 or more, the buffered string will be pluralized ("IES" or "S" appended). If the specified item is the Enigma Berry, I have no idea what this command does (but testing showed no pluralization). If the specified index is larger than the number of items in the game (0x176), the name of item 0 ("????????") is buffered instead.
        bufferitemnameplural: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            out: u8,
            item: lu16,
            quantity: lu16,
        },
    },
};

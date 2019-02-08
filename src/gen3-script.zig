const fun = @import("fun-with-zig");
const builtin = @import("builtin");
const std = @import("std");

const lu16 = fun.platform.lu16;
const lu32 = fun.platform.lu32;

const meta = std.meta;
const trait = meta.trait;
const mem = std.mem;
const debug = std.debug;

/// Find the field name which is most likly to be the tag of 'union_field'.
/// This function looks at all fields declared before 'union_field'. If one
/// of these field is an enum which has the same fields as the 'union_field's
/// type, then that is assume to be the tag of 'union_field'.
pub fn findTagFieldName(comptime Container: type, comptime union_field: []const u8) ?[]const u8 {
    if (!trait.is(builtin.TypeId.Struct)(Container))
        @compileError(@typeName(Container) ++ " is not a struct.");

    const container_fields = meta.fields(Container);
    const u_index = for (container_fields) |f, i| {
        if (mem.eql(u8, f.name, union_field))
            break i;
    } else {
        @compileError("No field called " ++ union_field ++ " in " ++ @typeName(Container));
    };

    const Union = container_fields[u_index].field_type;
    if (!trait.is(builtin.TypeId.Union)(Union))
        @compileError(union_field ++ " is not a union.");

    // Check all fields before 'union_field'.
    outer: for (container_fields[0..u_index]) |field| {
        const Enum = field.field_type;
        if (!trait.is(builtin.TypeId.Enum)(Enum))
            continue;

        // Check if 'Enum' and 'Union' have the same names
        // of their fields.
        const u_fields = meta.fields(Union);
        const e_fields = meta.fields(Enum);
        if (u_fields.len != e_fields.len)
            continue;

        // The 'Enum' and 'Union' have to have the same fields
        // in the same order. It's too slow otherwise (an it keeps
        // this impl simple)
        for (u_fields) |u_field, i| {
            const e_field = e_fields[i];
            if (!mem.eql(u8, u_field.name, e_field.name))
                continue :outer;
        }

        return field.name;
    }

    return null;
}

fn testFindTagFieldName(comptime Container: type, comptime union_field: []const u8, expect: ?[]const u8) void {
    if (comptime findTagFieldName(Container, union_field)) |actual| {
        debug.assertOrPanic(expect != null);
        debug.assertOrPanic(mem.eql(u8, expect.?, actual));
    } else {
        debug.assertOrPanic(expect == null);
    }
}

test "findTagFieldName" {
    const Union = union {
        A: void,
        B: u8,
        C: u16,
    };

    const Tag = enum {
        A,
        B,
        C,
    };
    testFindTagFieldName(struct {
        tag: Tag,
        un: Union,
    }, "un", "tag");
    testFindTagFieldName(struct {
        tag: Tag,
        not_tag: u8,
        un: Union,
        not_tag2: struct {},
        not_tag3: enum {
            A,
            B,
            Q,
        },
    }, "un", "tag");
    testFindTagFieldName(struct {
        not_tag: u8,
        un: Union,
        not_tag2: struct {},
        not_tag3: enum {
            A,
            B,
            Q,
        },
    }, "un", null);
}

/// Calculates the packed size of 'value'. The packed size is the size 'value'
/// would have if unions did not have to have the size of their biggest field.
pub fn packedLength(value: var) error{InvalidTag}!usize {
    const T = @typeOf(value);
    switch (@typeInfo(T)) {
        builtin.TypeId.Void => return 0,
        builtin.TypeId.Int => |i| {
            if (i.bits % 8 != 0)
                @compileError("Does not support none power of two intergers");
            return usize(i.bits / 8);
        },
        builtin.TypeId.Enum => |e| {
            if (e.layout != builtin.TypeInfo.ContainerLayout.Packed)
                @compileError(@typeName(T) ++ " is not packed");

            return packedLength(@enumToInt(value)) catch unreachable;
        },
        builtin.TypeId.Array => |a| {
            var res: usize = 0;
            for (value) |item|
                res += try packedLength(item);

            return res;
        },
        builtin.TypeId.Struct => |s| {
            if (s.layout != builtin.TypeInfo.ContainerLayout.Packed)
                @compileError(@typeName(T) ++ " is not packed");

            var res: usize = 0;
            inline for (s.fields) |struct_field|
                switch (@typeInfo(struct_field.field_type)) {
                builtin.TypeId.Union => |u| next: {
                    if (u.layout != builtin.TypeInfo.ContainerLayout.Packed)
                        @compileError(@typeName(struct_field.field_type) ++ " is not packed");
                    if (u.tag_type != null)
                        @compileError(@typeName(struct_field.field_type) ++ " cannot have a tag.");

                    // Find the field most likly to be this unions tag.
                    const tag_field = (comptime findTagFieldName(T, struct_field.name)) orelse @compileError("Could not find a tag for " ++ struct_field.name);
                    const tag = @field(value, tag_field);
                    const union_value = @field(value, struct_field.name);
                    const TagEnum = @typeOf(tag);

                    // Switch over all tags. 'TagEnum' have the same field names as
                    // 'union' so if one member of 'TagEnum' matches 'tag', then
                    // we can add the size of ''@field(union, tag_name)' to res and
                    // break out.
                    inline for (@typeInfo(TagEnum).Enum.fields) |enum_field| {
                        if (@field(TagEnum, enum_field.name) == tag) {
                            const union_field = @field(union_value, enum_field.name);
                            res += try packedLength(union_field);
                            break :next;
                        }
                    }

                    // If no member of 'TagEnum' match, then 'tag' must be a value
                    // it is not suppose to be.
                    return error.InvalidTag;
                },
                else => res += try packedLength(@field(value, struct_field.name)),
            };
            return res;
        },
        else => @compileError(@typeName(T) ++ " not supported"),
    }
}

fn testPackedLength(value: var, expect: error{InvalidTag}!usize) void {
    if (packedLength(value)) |size| {
        const expected_size = expect catch unreachable;
        debug.assertOrPanic(size == expected_size);
    } else |err| {
        const expected_err = if (expect) |_| unreachable else |e| e;
        debug.assertOrPanic(expected_err == err);
    }
}

test "packedLength" {
    const E = packed enum(u8) {
        A,
        B,
        C,
    };

    const U = packed union {
        A: void,
        B: u8,
        C: u16,
    };

    const S = packed struct {
        tag: E,
        pad: u8,
        data: U,
    };

    testPackedLength(S{ .tag = E.A, .pad = 0, .data = U{ .A = {} } }, 2);
    testPackedLength(S{ .tag = E.B, .pad = 0, .data = U{ .B = 0 } }, 3);
    testPackedLength(S{ .tag = E.C, .pad = 0, .data = U{ .C = 0 } }, 4);
}

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

        pub const TrainerBattleType = packed enum(u8) {
            TRAINER_BATTLE_SINGLE = 0,
            TRAINER_BATTLE_CONTINUE_SCRIPT_NO_MUSIC = 1,
            TRAINER_BATTLE_CONTINUE_SCRIPT = 2,
            TRAINER_BATTLE_SINGLE_NO_INTRO_TEXT = 3,
            TRAINER_BATTLE_DOUBLE = 4,
            TRAINER_BATTLE_REMATCH = 5,
            TRAINER_BATTLE_CONTINUE_SCRIPT_DOUBLE = 6,
            TRAINER_BATTLE_REMATCH_DOUBLE = 7,
            TRAINER_BATTLE_CONTINUE_SCRIPT_DOUBLE_NO_MUSIC = 8,
            TRAINER_BATTLE_PYRAMID = 9,
            TRAINER_BATTLE_SET_TRAINER_A = 10,
            TRAINER_BATTLE_SET_TRAINER_B = 11,
            TRAINER_BATTLE_12 = 12,
        };

        // If the Trainer flag for Trainer index is not set, this command does absolutely nothing.
        trainerbattle: packed struct {
            // Tag was here. Any struct that doesnt have this comment should be removed
            type: TrainerBattleType,
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
        giveitem = 0x44,
        takeitem = 0x45,
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
        cmdD8 = 0xd8,
        cmdD9 = 0xd9,
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
};

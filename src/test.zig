const std = @import("std");

test {
    @setEvalBranchQuota(100000000);
    // std.testing.refAllDeclsRecursive(@import("util.zig"));

    std.testing.refAllDeclsRecursive(@import("core/tm35-apply.zig"));
    std.testing.refAllDeclsRecursive(@import("core/tm35-disassemble-scripts.zig"));
    std.testing.refAllDeclsRecursive(@import("core/tm35-gen3-offsets.zig"));
    std.testing.refAllDeclsRecursive(@import("core/tm35-identify.zig"));
    std.testing.refAllDeclsRecursive(@import("core/tm35-load.zig"));
    std.testing.refAllDeclsRecursive(@import("core/tm35-nds-extract.zig"));

    std.testing.refAllDeclsRecursive(@import("other/tm35-balance-pokemons.zig"));
    std.testing.refAllDeclsRecursive(@import("other/tm35-generate-site.zig"));
    std.testing.refAllDeclsRecursive(@import("other/tm35-misc.zig"));
    std.testing.refAllDeclsRecursive(@import("other/tm35-noop.zig"));
    std.testing.refAllDeclsRecursive(@import("other/tm35-no-trade-evolutions.zig"));

    std.testing.refAllDeclsRecursive(@import("randomizers/tm35-randomize-pokemons.zig"));
    std.testing.refAllDeclsRecursive(@import("randomizers/tm35-randomize-machines.zig"));
    std.testing.refAllDeclsRecursive(@import("randomizers/tm35-randomize-names.zig"));
    std.testing.refAllDeclsRecursive(@import("randomizers/tm35-randomize-trainers.zig"));
    std.testing.refAllDeclsRecursive(@import("randomizers/tm35-randomize-field-items.zig"));
    std.testing.refAllDeclsRecursive(@import("randomizers/tm35-randomize-starters.zig"));
    std.testing.refAllDeclsRecursive(@import("randomizers/tm35-randomize-static-encounters.zig"));
    std.testing.refAllDeclsRecursive(@import("randomizers/tm35-randomize-wild-encounters.zig"));
    std.testing.refAllDeclsRecursive(@import("randomizers/tm35-random-stones.zig"));
}

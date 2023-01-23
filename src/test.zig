const std = @import("std");

test {
    @setEvalBranchQuota(100000000);
    std.testing.refAllDeclsRecursive(@import("common/util.zig"));

    std.testing.refAllDeclsRecursive(@import("core/tm35-apply.zig"));
    std.testing.refAllDeclsRecursive(@import("core/tm35-disassemble-scripts.zig"));
    std.testing.refAllDeclsRecursive(@import("core/tm35-gen3-offsets.zig"));
    std.testing.refAllDeclsRecursive(@import("core/tm35-identify.zig"));
    std.testing.refAllDeclsRecursive(@import("core/tm35-load.zig"));
    std.testing.refAllDeclsRecursive(@import("core/tm35-nds-extract.zig"));

    std.testing.refAllDeclsRecursive(@import("other/tm35-generate-site.zig"));
    std.testing.refAllDeclsRecursive(@import("other/tm35-misc.zig"));
    std.testing.refAllDeclsRecursive(@import("other/tm35-noop.zig"));
    std.testing.refAllDeclsRecursive(@import("other/tm35-no-trade-evolutions.zig"));

    std.testing.refAllDeclsRecursive(@import("randomizers/tm35-rand-pokemons.zig"));
    std.testing.refAllDeclsRecursive(@import("randomizers/tm35-rand-machines.zig"));
    std.testing.refAllDeclsRecursive(@import("randomizers/tm35-rand-names.zig"));
    std.testing.refAllDeclsRecursive(@import("randomizers/tm35-rand-trainers.zig"));
    std.testing.refAllDeclsRecursive(@import("randomizers/tm35-rand-pokeball-items.zig"));
    std.testing.refAllDeclsRecursive(@import("randomizers/tm35-rand-starters.zig"));
    std.testing.refAllDeclsRecursive(@import("randomizers/tm35-rand-static.zig"));
    std.testing.refAllDeclsRecursive(@import("randomizers/tm35-rand-wild.zig"));
    std.testing.refAllDeclsRecursive(@import("randomizers/tm35-random-stones.zig"));
}

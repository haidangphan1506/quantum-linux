hl.config({
     decoration = {
        rounding       = 10,
        rounding_power = 2,

        -- Change transparency of focused and unfocused windows
        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = false,
            range        = 4,
            render_power = 3,
            color        = 0xee1a1a1a,
        },

        blur = {
            enabled   = true,
            size      = 3,
            passes    = 1,
            vibrancy  = 0.1696,
        },
    },
})

-- Bar tren cung kieu macOS (Quantum Shell, namespace quantum-bar): nen trong suot co blur
hl.layer_rule({
    name  = "blur-quantum-bar",
    match = { namespace = "^quantum-bar$" },
    blur  = true,
    ignore_alpha = 0.2,
})

-- Mission Control (Quantum Shell, namespace quantum-overview): nen mo phia sau
hl.layer_rule({
    name  = "blur-quantum-overview",
    match = { namespace = "^quantum-overview$" },
    blur  = true,
    -- chi blur khi nen con dam (alpha > 0.15): luc dong, nen mo dan thi het blur ngay,
    -- khong de ca man hinh bi nhoe cho toi khi lop overview bien mat
    ignore_alpha = 0.15,
})

-- Launchpad (Quantum Shell, namespace quantum-launchpad): nen mo phia sau
hl.layer_rule({
    name  = "blur-quantum-launchpad",
    match = { namespace = "^quantum-launchpad$" },
    blur  = true,
    ignore_alpha = 0.15,
})

-- Dock kieu macOS (Quantum Shell, namespace quantum-dock): kinh mo trong suot
hl.layer_rule({
    name  = "blur-quantum-dock",
    match = { namespace = "^quantum-dock$" },
    blur  = true,
    ignore_alpha = 0.2,
})

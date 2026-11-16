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
            size      = 10,     -- mo dam nhu kinh macOS
            passes    = 3,
            vibrancy  = 0.1696,
            noise     = 0.02,
        },
    },
})

-- Bar tren cung kieu macOS (Quantum Shell, namespace quantum-bar): nen trong suot co blur
hl.layer_rule({
    name  = "blur-quantum-bar",
    match = { namespace = "^quantum-bar$" },
    blur  = true,
    blur_popups = true,   -- popup cua bar (Claude, he thong...) cung mo nhu kinh
    ignore_alpha = 0.05,
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
    ignore_alpha = 0.05,
})

-- Control Center (Wi-Fi, am luong...) + Assistant (Quantum Shell, namespace quantum-panel):
-- kinh mo kieu macOS. Layer phu ca man hinh nhung trong suot -> ignore_alpha chi blur o panel.
hl.layer_rule({
    name  = "blur-quantum-panel",
    match = { namespace = "^quantum-panel$" },
    blur  = true,
    ignore_alpha = 0.05,
})

-- Menu kieu macOS cua bar (quantum-menu): kinh mo
hl.layer_rule({
    name  = "blur-quantum-menu",
    match = { namespace = "^quantum-menu$" },
    blur  = true,
    ignore_alpha = 0.05,
})

-- Kinh mo kieu macOS cho cac lop con lai cua Quantum Shell (launcher, thong bao, OSD...)
hl.layer_rule({
    name  = "blur-quantum-launcher",
    match = { namespace = "^quantum-launcher$" },
    blur  = true,
    ignore_alpha = 0.05,
})

hl.layer_rule({
    name  = "blur-quantum-notifications",
    match = { namespace = "^quantum-notifications$" },
    blur  = true,
    ignore_alpha = 0.05,
})

hl.layer_rule({
    name  = "blur-quantum-osd",
    match = { namespace = "^quantum-osd$" },
    blur  = true,
    ignore_alpha = 0.05,
})

hl.layer_rule({
    name  = "blur-quantum-switcher",
    match = { namespace = "^quantum-switcher$" },
    blur  = true,
    ignore_alpha = 0.05,
})

hl.layer_rule({
    name  = "blur-quantum-session",
    match = { namespace = "^quantum-session$" },
    blur  = true,
    ignore_alpha = 0.05,
})

hl.layer_rule({
    name  = "blur-quantum-wallpapers",
    match = { namespace = "^quantum-wallpapers$" },
    blur  = true,
    ignore_alpha = 0.05,
})

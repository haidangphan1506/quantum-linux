local vars = require("variable")

-- All keybind/action pairs live in variable.lua (vars.keybinds); bind them here.
for _, kb in ipairs(vars.keybinds) do
    hl.bind(kb.key, kb.action, kb.opts)
end

--#!
--##! Window
--#/# bind = SUPER + ←/↑/→/↓,, -- Focus in direction
for i = 1, 4 do
    local arrowkey = { "H", "L", "K", "J" }
    local focusdir = { "l", "r", "u", "d" }
    hl.bind("SUPER + " .. arrowkey[i], hl.dsp.focus({ direction = focusdir[i] }),
        { description = "Window: Focus " .. arrowkey[i] })
end
--#/# bind = SUPER + SHIFT, ←/↑/→/↓,, -- Move in direction
for i = 1, 4 do
    local arrowkey = { "H", "L", "K", "J" }
    local focusdir = { "l", "r", "u", "d" }
    hl.bind("SUPER + SHIFT + " .. arrowkey[i], hl.dsp.window.move({ direction = focusdir[i] }),
        { description = "Window: Mlove " .. arrowkey[i] })
end

for i = 1, 2 do
    local keys = { "H", "L" }
    local prefix = { "r-", "r+" }
    local descdir = { "left", "right" }
    hl.bind("CTRL + SUPER + " .. keys[i], hl.dsp.focus({ workspace = prefix[i] .. "1" }), {description = "Workspace: Focus " .. descdir[i]})
end

for i = 1, 2 do
    local keys = { "H", "L" }
    local prefix = { "r-", "r+" }
    hl.bind("CTRL + SUPER + SHIFT + ".. keys[i] , hl.dsp.window.move({ workspace = prefix[i] .. "1" })) -- # [hidden]
end

hl.bind("SUPER + ESCAPE",
    hl.dsp.window.move({ workspace = "special:special", follow = true })
    , { description = "Window: Send to scratchpad" })

hl.bind("SUPER + TAB", 
    hl.dsp.window.move({ workspace = "e+0" }),
    hl.dsp.workspace.toggle_special("special")
    , { description = "Window: Bring back from scratchpad" })

hl.bind("SUPER + SPACE", hl.dsp.global("quickshell:searchToggleRelease"))
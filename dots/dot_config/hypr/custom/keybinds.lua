--#/# unbind defaults
hl.unbind("SUPER + Tab")
hl.unbind("SUPER + SHIFT + L")
-- hl.unbind("SUPER + Tab")

hl.bind("SUPER + Space", hl.dsp.global("quickshell:searchToggleRelease"))

--#/# bind = SUPER, Escape, -- Send window to scratchpad
hl.bind("SUPER + Escape", hl.dsp.window.move({ workspace = "special:special", follow = true }),
    { description = "Window: Send to scratchpad" })
--#/# bind = SUPER, Tab, -- Send window back to the normal workspace
hl.bind("SUPER + Tab", function()
    local ws = hl.get_active_monitor().active_workspace
    if ws then
        hl.dispatch(hl.dsp.window.move({ workspace = ws.id }))
    end
end, { description = "Window: Send back from scratchpad" })



--#/# bind = SUPER + vim motions, -- Focus in direction
for i = 1, 4 do
    local keys = { "H", "L", "K", "J" }
    local focusdir = { "l", "r", "u", "d" }
    hl.bind("SUPER + " .. keys[i], hl.dsp.focus({ direction = focusdir[i] }),
        { description = "Window: Focus " .. keys[i] })
end
--#/# bind = SUPER+SHIFT, vim motions, -- Move in direction
for i = 1, 4 do
    local keys = { "H", "L", "K", "J" }
    local focusdir = { "l", "r", "u", "d" }
    hl.bind("SUPER + SHIFT + " .. keys[i], hl.dsp.window.move({ direction = focusdir[i] })) --,{ description = "Window: Move " .. keys[i] })
end
--#/# bind = CTRL+SUPER+SHIFT, vim motions, -- move window to workspace left/right
for i = 1, 2 do
    local keys = { "H", "L" }
    local prefix = { "r-", "r+" }
    hl.bind("CTRL + SUPER + SHIFT + " .. keys[i], hl.dsp.window.move({ workspace = prefix[i] .. "1" })) -- # [hidden]
end
--#/# bind = CTRL+SUPER, vim motions,, -- Focus left/right
for i = 1, 2 do
    local keys = { "H", "L" }
    local prefix = { "r-", "r+" }
    local descdir = { "left", "right" }
    hl.bind("CTRL + SUPER + " .. keys[i], hl.dsp.focus({ workspace = prefix[i] .. "1" })) --, {description = "Workspace: Focus " .. descdir[i]})
end


-- PC monitor profile: matched by description (stable across ports/cables,
-- unlike the connector name), so this only kicks in when that specific
-- external display is actually plugged into the laptop. When it's absent
-- (e.g. right now, on battery), the "" catch-all rule above applies instead
-- -- monitor rules are matched most-specific-first, and this one is declared
-- after the catch-all so it takes priority when present.
--
-- Once connected, get the real description with:
--   hyprctl monitors -j | jq '.[].description'
-- and the icc profile is whatever you use for that display's SDR calibration.
local pcMonitorMatch = "MOCK Big PC Monitor" -- TODO: replace with real "<make model serial>" (no "desc:" prefix)
local laptopPanel = "eDP-1"

hl.monitor({
    output = "desc:" .. pcMonitorMatch,
    mode = "5120x1440@144",
    position = "0x0",
    scale = 1.33,
    icc = "$HOME/.config/hypr/icc/MSI_491CQP.icc" -- TODO: mock path, drop the real ICC profile here
})

-- Dedicated named rule for the laptop panel, mirroring the "" catch-all values.
-- Needed because a fresh hl.monitor() call only inherits fields from a previous
-- rule with the *same* name -- without this, toggling `disabled` below would
-- silently reset mode/position/scale to their defaults instead of preserving them.
hl.monitor({
    output = laptopPanel,
    mode = "preferred",
    position = "auto",
    scale = 1.2
})

-- Disable the laptop screen while the PC monitor is connected, and restore it
-- when unplugged. monitor.added/removed also fire for monitors already present
-- at Hyprland startup, so this covers both hotplug and boot-with-dock-attached.
hl.on("monitor.added", function(mon)
    if mon.description:find(pcMonitorMatch, 1, true) then
        hl.monitor({ output = laptopPanel, disabled = true })
    end
end)
hl.on("monitor.removed", function(mon)
    if mon.description:find(pcMonitorMatch, 1, true) then
        hl.monitor({ output = laptopPanel, disabled = false })
    end
end)

-- hl.gesture() is additive, not an override: a new gesture is rejected (and logged
-- as "will be overshadowed") if it overlaps the axis of one already registered for
-- the same finger count. Since hyprland/general.lua registers its own gestures first,
-- the defaults being replaced here must be explicitly unset before re-registering them.
hl.gesture({ fingers = 3, direction = "swipe", action = "unset" })
hl.gesture({ fingers = 3, direction = "pinch", action = "unset" })
hl.gesture({ fingers = 4, direction = "horizontal", action = "unset" })
hl.gesture({ fingers = 4, direction = "up", action = "unset" })
hl.gesture({ fingers = 4, direction = "down", action = "unset" })

hl.gesture({
    fingers = 4,
    direction = "swipe",
    action = "move"
})
hl.gesture({
    fingers = 3,
    direction = "pinch",
    action = "fullscreen"
})
hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace"
})
hl.gesture({
    fingers = 3,
    direction = "up",
    action = function()
        hl.dispatch(hl.dsp.global("quickshell:overviewWorkspacesToggle"))
    end
})
hl.gesture({
    fingers = 3,
    direction = "down",
    action = function()
        hl.dispatch(hl.dsp.global("quickshell:overviewWorkspacesToggle"))
    end
})
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
local pcMonitorMatch = "Microstep MPG 491C OLED" -- TODO: replace with real "<make model serial>" (no "desc:" prefix)
local laptopPanel = "eDP-1"

hl.monitor({ 
    output = "desc:" .. pcMonitorMatch,
    mode = "5120x1440@144",
    position = "0x0",
    scale = 1.25,
    bitdepth = 10,
    cm = "srgb",
    icc = HOME .. "/.config/hypr/icc/MSI_491CQP.icm",
    vrr = 1,
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

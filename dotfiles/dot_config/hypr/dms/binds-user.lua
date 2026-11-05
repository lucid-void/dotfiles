-- Your keybinds. dms setup never overwrites this file.
-- Loaded after binds.lua: binding a stock key here replaces it, hl.unbind("SUPER + X") frees it.
-- Saving in the DMS keybind editor rewrites this file and keeps only hl.bind/hl.unbind lines.

-- hjkl: workspace left/right (stock binds use these for monitor focus/move)
hl.unbind("SUPER + CTRL + H")
hl.bind("SUPER + CTRL + H", hl.dsp.focus({ workspace = "r-1" }))
hl.unbind("SUPER + CTRL + L")
hl.bind("SUPER + CTRL + L", hl.dsp.focus({ workspace = "r+1" }))
hl.unbind("SUPER + SHIFT + CTRL + H")
hl.bind("SUPER + SHIFT + CTRL + H", hl.dsp.window.move({ workspace = "r-1" }))
hl.unbind("SUPER + SHIFT + CTRL + L")
hl.bind("SUPER + SHIFT + CTRL + L", hl.dsp.window.move({ workspace = "r+1" }))

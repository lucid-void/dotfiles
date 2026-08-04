-- Disable the default Picture-in-Picture size rule (hyprland/rules.lua)
-- without editing that file. See custom/env.lua for disable_window_rules.
local pipTitle = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$"
disable_window_rules(function(spec)
    return spec.size ~= nil and spec.match and spec.match.title == pipTitle
end)

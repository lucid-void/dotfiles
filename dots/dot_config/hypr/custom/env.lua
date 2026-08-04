-- Window-rule registry --
-- This file is sourced BEFORE hyprland/rules.lua (see ~/.config/hypr/hyprland.lua),
-- so wrapping hl.window_rule here captures a handle to every rule the defaults
-- create. custom/rules.lua can then disable them without editing hyprland/rules.lua.

windowRuleRegistry = {}

if not hl.__windowRuleWrapped then
    hl.__windowRuleWrapped = true
    local createWindowRule = hl.window_rule
    hl.window_rule = function(spec)
        local rule = createWindowRule(spec)
        if rule then
            windowRuleRegistry[#windowRuleRegistry + 1] = { rule = rule, spec = spec }
        end
        return rule
    end
end

-- Disables every registered rule whose spec satisfies `predicate`.
-- Returns how many were disabled, so a silent typo in a matcher is visible.
function disable_window_rules(predicate)
    local disabled = 0
    for _, entry in ipairs(windowRuleRegistry) do
        if predicate(entry.spec) then
            entry.rule:set_enabled(false)
            disabled = disabled + 1
        end
    end
    return disabled
end

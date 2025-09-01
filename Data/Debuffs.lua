local ADDON, ns = ...
ns = ns or {}
ns.Data = ns.Data or {}
local Data = ns.Data

-- Curated list of dangerous debuff spellIDs; expand as needed
Data.DangerousDebuffs = {
    [240559] = true, -- example
    [240443] = true, -- example
    [209858] = true, -- example
}

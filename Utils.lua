local ADDON, ns = ...
ns = ns or {}
ns.Utils = ns.Utils or {}
local Utils = ns.Utils

-- Returns a table of dispel types your character can handle.
function Utils.GetPlayerDispelTypes()
    local class = select(2, UnitClass("player"))
    local t = {}
    if class == "PRIEST" then
        t.Magic = true; t.Disease = true
    elseif class == "PALADIN" then
        t.Magic = IsPlayerSpell(4987); t.Disease = true; t.Poison = true
    elseif class == "SHAMAN" then
        t.Curse = true; t.Magic = IsPlayerSpell(77130)
    elseif class == "DRUID" then
        t.Curse = true; t.Poison = true; t.Magic = IsPlayerSpell(88423)
    elseif class == "MONK" then
        t.Poison = true; t.Disease = true; t.Magic = IsPlayerSpell(115450)
    elseif class == "EVOKER" then
        t.Poison = true; t.Disease = true; t.Curse = true; t.Magic = IsPlayerSpell(365585)
    elseif class == "MAGE" then
        t.Curse = true
    elseif class == "HUNTER" then
        t.Enrage = true
    end
    return t
end

-- Safely get a harmful aura (debuff) via modern API; falls back gracefully.
local function GetHarmfulAuraByIndex(unit, index)
    if C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex then
        return C_UnitAuras.GetDebuffDataByIndex(unit, index)
    end
    -- Very old clients fallback (should exist, but your error suggests it didn’t)
    if UnitAura then
        local name, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId = UnitAura(unit, index, "HARMFUL")
        if not name then return nil end
        return {
            name = name,
            icon = icon,
            applications = count,
            dispelName = debuffType, -- maps to “Magic”, “Curse”, etc.
            duration = duration,
            expirationTime = expirationTime,
            sourceUnit = source,
            isStealable = isStealable,
            spellId = spellId,
        }
    end
    return nil
end

-- Returns: isDispellable, dispelType, spellId
function Utils.IsDispellableByPlayer(unit)
    local dispels = Utils.GetPlayerDispelTypes()
    for i = 1, 40 do
        local aura = GetHarmfulAuraByIndex(unit, i)
        if not aura then break end
        local debuffType = aura.dispelName
        if debuffType and dispels[debuffType] then
            return true, debuffType, aura.spellId
        end
    end
    return false
end

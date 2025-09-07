local WowHealerUI = _G.WowHealerUI or {}
_G.WowHealerUI = WowHealerUI

WowHealerUI.ItemLevel = WowHealerUI.ItemLevel or {}
local ItemLevel = WowHealerUI.ItemLevel

local pendingGUID, pendingUnit
local cache = {} -- guid -> { ilvl = number, t = GetTime() }

local SLOTS = {
    1,2,3,5,6,7,8,9,10,11,12,13,14,15,16,17 -- head.. offhand
}

local function ComputeUnitIlvl(unit)
    local sum, count = 0, 0
    for _, slot in ipairs(SLOTS) do
        local link = GetInventoryItemLink(unit, slot)
        if link then
            local ilvl = GetDetailedItemLevelInfo(link)
            if ilvl and ilvl > 0 then
                sum = sum + ilvl
                count = count + 1
            end
        end
    end
    if count > 0 then
        return sum / count
    end
end

function ItemLevel:GetIlvl(unit)
    if UnitIsUnit(unit, "player") and GetAverageItemLevel then
        local _, eq = GetAverageItemLevel()
        if eq and eq > 0 then return eq end
    end

    local guid = UnitGUID(unit)
    if not guid then return nil end

    -- fresh cached?
    local c = cache[guid]
    if c and (GetTime() - c.t) < 120 then
        return c.ilvl
    end

    -- can we inspect now?
    if not InCombatLockdown() and CanInspect(unit) and CheckInteractDistance(unit, 1) then
        pendingGUID, pendingUnit = guid, unit
        NotifyInspect(unit)
    end

    return c and c.ilvl or nil
end

local f = CreateFrame("Frame")
f:RegisterEvent("INSPECT_READY")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "INSPECT_READY" and arg1 and pendingGUID and arg1 == pendingGUID and pendingUnit then
        local ilvl = ComputeUnitIlvl(pendingUnit)
        if ilvl then
            cache[pendingGUID] = { ilvl = ilvl, t = GetTime() }
        end
        ClearInspectPlayer()
        pendingGUID, pendingUnit = nil, nil

        -- trigger your UI refresh to show new ilvl
        -- e.g., call RefreshAll() or update the specific button
        if WowHealerUI and WowHealerUI.Modules and WowHealerUI.Modules.GroupView then
            -- safest: full refresh to repaint rightFS with the cached value
            C_Timer.After(0, function() WowHealerUI.Modules.GroupView:RefreshAllSafe() end)
        end
    end
end)

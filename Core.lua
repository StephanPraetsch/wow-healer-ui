local ADDON_NAME = ...
local WowHealerUI = {}
_G.WowHealerUI = WowHealerUI

-- SavedVariables defaults
local defaults = {
    enabled = true,
    minimap = {
        hide = false,
        pos = 225,
    },
    hideQuests = true,
}

local function DeepCopy(src, dst)
    if type(src) ~= "table" then return src end
    dst = dst or {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = DeepCopy(v, dst[k] or {})
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

local function ApplyDefaults(db, defs)
    if type(db) ~= "table" then db = {} end
    return DeepCopy(defs, db)
end

WowHealerUI.DB = WowHealerUI.DB or {}

WowHealerUI.RegisteredModules = {}
function WowHealerUI:RegisterModule(name, mod)
    self.RegisteredModules[name] = mod
end

function WowHealerUI:ForEachModule(funcName, ...)
    for _, mod in pairs(self.RegisteredModules) do
        if type(mod[funcName]) == "function" then
            pcall(mod[funcName], mod, ...)
        end
    end
end

function WowHealerUI:IsEnabled()
    return WowHealerUI_DB and WowHealerUI_DB.enabled
end

-- Objective Tracker suppression helpers
local function reallyHideTracker()
    if not ObjectiveTrackerFrame then return end
    if ObjectiveTrackerFrame.UnregisterAllEvents then ObjectiveTrackerFrame:UnregisterAllEvents() end
    ObjectiveTrackerFrame:Hide()
end

local function reallyShowTracker()
    if not ObjectiveTrackerFrame then return end
    ObjectiveTrackerFrame:Show()
end

-- Public API to apply current preference immediately
function WowHealerUI:ApplyObjectiveTrackerPreference()
    if WowHealerUI_DB and WowHealerUI_DB.hideQuests and WowHealerUI:IsEnabled() then
        -- Schedule a few hides to beat layout churn
        C_Timer.After(0, reallyHideTracker)
        C_Timer.After(0.1, reallyHideTracker)
        C_Timer.After(0.5, reallyHideTracker)
    else
        reallyShowTracker()
    end
end

-- Initialize a robust suppressor that runs independent of panel updates
function WowHealerUI:_InitObjectiveTrackerSuppressor()
    if self._trackerSuppressor then return end

    local sup = CreateFrame("Frame")
    self._trackerSuppressor = sup

    local function ensureHiddenIfEnabled()
        if WowHealerUI_DB and WowHealerUI_DB.hideQuests and WowHealerUI:IsEnabled() then
            C_Timer.After(0, reallyHideTracker)   -- next frame
            C_Timer.After(0.1, reallyHideTracker) -- after initial layout
            C_Timer.After(0.5, reallyHideTracker) -- after UI settles
        end
    end

    sup:SetScript("OnEvent", function()
        ensureHiddenIfEnabled()
    end)

    sup:RegisterEvent("PLAYER_LOGIN")
    sup:RegisterEvent("PLAYER_ENTERING_WORLD")
    sup:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    sup:RegisterEvent("SCENARIO_UPDATE")
    sup:RegisterEvent("SCENARIO_CRITERIA_UPDATE")

    -- If the frame exists, hard-hook Show to keep it hidden when preference is ON
    C_Timer.After(0, function()
        if ObjectiveTrackerFrame and not sup._hooked then
            sup._hooked = true
            hooksecurefunc(ObjectiveTrackerFrame, "Show", function()
                if WowHealerUI_DB and WowHealerUI_DB.hideQuests and WowHealerUI:IsEnabled() then
                    reallyHideTracker()
                end
            end)
            ensureHiddenIfEnabled()
        end
    end)
end

-- Event frame
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")

f:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        WowHealerUI_DB = ApplyDefaults(WowHealerUI_DB, defaults)
        WowHealerUI.DB = WowHealerUI_DB

        -- Initialize modules
        WowHealerUI:ForEachModule("OnInit")

        -- Start the objective tracker suppressor early
        WowHealerUI:_InitObjectiveTrackerSuppressor()

    elseif event == "PLAYER_LOGIN" then
        -- Enable/disable after login, show UI appropriately
        WowHealerUI:ForEachModule("OnLogin")
        -- Ensure tracker preference is applied on login
        WowHealerUI:ApplyObjectiveTrackerPreference()

    elseif event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReload = ...
        WowHealerUI:ForEachModule("OnPlayerEnteringWorld", isInitialLogin, isReload)
    end
end)

-- API for other files
function WowHealerUI:ToggleEnabled(on)
    WowHealerUI_DB.enabled = on and true or false
    self:ForEachModule("OnEnableChanged", WowHealerUI_DB.enabled)
    -- Re-apply objective tracker preference on toggle
    self:ApplyObjectiveTrackerPreference()
end

-- Simple utility: role detection
function WowHealerUI:GetUnitRole(unit)
    local assigned = UnitGroupRolesAssigned(unit)
    if assigned and assigned ~= "NONE" then return assigned end
    return "NONE"
end

-- Utility: class color
function WowHealerUI:GetClassColor(unit)
    local _, class = UnitClass(unit)
    if class and RAID_CLASS_COLORS[class] then
        local c = RAID_CLASS_COLORS[class]
        return c.r, c.g, c.b
    end
    return 1, 1, 1
end

-- Utility: iterate debuffs safely across versions
local function IterateDebuffs(unit, cb)
    if C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex then
        for i = 1, 40 do
            local aura = C_UnitAuras.GetDebuffDataByIndex(unit, i)
            if not aura or not aura.name then break end
            local name = aura.name
            local icon = aura.icon
            local count = aura.applications or aura.charges or aura.stackCount or 0
            local debuffType = aura.dispelName
            local duration = aura.duration
            local expirationTime = aura.expirationTime
            local source = aura.sourceUnit
            local isStealable = aura.isStealable
            local nameplateShowPersonal = aura.nameplateShowPersonal
            local spellId = aura.spellId
            local canApplyAura = aura.canApplyAura
            local isBossAura = aura.isBossAura
            local castByPlayer = aura.isFromPlayerOrPlayerPet
            local nameplateShowAll = aura.nameplateShowAll
            local timeMod = aura.timeMod
            local continue = cb(name, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId, canApplyAura, isBossAura, castByPlayer, nameplateShowAll, timeMod)
            if continue == false then break end
        end
        return
    end

    if type(UnitDebuff) == "function" then
        for i = 1, 40 do
            local name, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId, canApplyAura, isBossDebuff, castByPlayer, nameplateShowAll, timeMod =
            UnitDebuff(unit, i)
            if not name then break end
            local continue = cb(name, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId, canApplyAura, isBossDebuff, castByPlayer, nameplateShowAll, timeMod)
            if continue == false then break end
        end
    end
end

-- Utility: dispellable by player
local CanDispel = {
    PRIEST  = { Magic=true, Disease=true },
    SHAMAN  = { Magic=true, Curse=true },
    PALADIN = { Magic=true, Disease=true, Poison=true },
    DRUID   = { Magic=true, Curse=true, Poison=true },
    MONK    = { Magic=true, Disease=true, Poison=true },
    EVOKER  = { Magic=true, Curse=true, Poison=true },
}
function WowHealerUI:IsDispellable(unit)
    local _, class = UnitClass("player")
    local dispels = CanDispel[class or ""]
    if not dispels then return false end
    local found = false
    IterateDebuffs(unit, function(name, icon, count, debuffType)
        if debuffType and dispels[debuffType] then
            found = true
            return false -- stop
        end
    end)
    return found
end

-- Utility: dangerous debuff (heuristic)
function WowHealerUI:IsDangerousDebuff(unit)
    local danger = false
    IterateDebuffs(unit, function(name, icon, count, debuffType, duration, expirationTime, source, _, _, spellId, _, isBossAura)
        if isBossAura or (count and count >= 5) then
            danger = true
            return false
        end
    end)
    return danger
end

-- Expose icon path
WowHealerUI.ICON_TEXTURE = "Interface\\Icons\\Spell_Holy_FlashHeal"

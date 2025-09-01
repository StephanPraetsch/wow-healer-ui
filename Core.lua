local ADDON, ns = ...

-- Root addon frame
WOWHealerUI = CreateFrame("Frame")
WOWHealerUI.name = "wow-healer-ui"
WOWHealerUI.version = "1.0.0"
WOWHealerUI.author = "Stephan Prätsch"

-- Namespace locals
ns = ns or {}
local Config = ns.Config or {}
local Utils = ns.Utils or {}

-- Saved variables bootstrap
local function EnsureDB()
    WOWHealerUI_DB = WOWHealerUI_DB or {
        enabled = true,
        replacePlayerFrame = true,
        hideObjectiveTracker = true,
        rightPanel = true,
        showDangerousHighlight = true,
        showDispellableHighlight = true,
        clickCast = {
            -- Defaults: LeftButton targets, RightButton casts a spell name (edit in options)
            type1 = "target",
            type2 = "spell",
            spell2 = "Heal",
        },
        rightPanelPos = nil, -- optional saved position if you enable dragging
    }
end

-- Robust Objective Tracker control
local function ApplyObjectiveTrackerVisibility()
    local f = ObjectiveTrackerFrame
    if not f then return end

    local wantHidden = WOWHealerUI_DB and WOWHealerUI_DB.hideObjectiveTracker
    if wantHidden then
        -- Keep it hidden even if Blizzard tries to show it
        f:Hide()
        f:SetAlpha(0)
        if not f._WHUI_OnShowHooked then
            f:HookScript("OnShow", function(self) self:Hide() end)
            f._WHUI_OnShowHooked = true
        end
    else
        -- Restore normal behavior
        f:SetAlpha(1)
        f:Show()
        -- We don't unhook the OnShow script (safe to leave); it only hides when setting is on.
    end
end
WOWHealerUI.ApplyObjectiveTrackerVisibility = ApplyObjectiveTrackerVisibility

-- Centralized UI setup
local function SetupUI()
    if not (WOWHealerUI_DB and WOWHealerUI_DB.enabled) then
        -- Disable our frames and restore tracker if we were hiding it
        if ns.Frames and ns.Frames.GroupFrame then ns.Frames.GroupFrame:Hide() end
        if ns.Frames and ns.Frames.RightPanel then ns.Frames.RightPanel:Hide() end
        return
    end

    if ns and ns.Frames then
        local Frames = ns.Frames
        if WOWHealerUI_DB.replacePlayerFrame and Frames.GroupFrame then
            Frames.GroupFrame:UpdateUnits()
            Frames.GroupFrame:Show()
        elseif Frames.GroupFrame then
            Frames.GroupFrame:Hide()
        end

        if WOWHealerUI_DB.rightPanel and Frames.RightPanel then
            Frames.RightPanel:Show()
            Frames.RightPanel:Refresh()
        elseif Frames.RightPanel then
            Frames.RightPanel:Hide()
        end
    end

    ApplyObjectiveTrackerVisibility()
end

-- Event handlers
function WOWHealerUI:ADDON_LOADED(addonName)
    if addonName ~= ADDON then return end
    -- No-op for now
end

function WOWHealerUI:PLAYER_LOGIN()
    EnsureDB()
    if ns and ns.Config and ns.Config.InitOptionsPanel then
        ns.Config.InitOptionsPanel()
    end
    ApplyObjectiveTrackerVisibility()
    SetupUI()
end

function WOWHealerUI:PLAYER_ENTERING_WORLD()
    ApplyObjectiveTrackerVisibility()
    SetupUI()
end

function WOWHealerUI:GROUP_ROSTER_UPDATE()
    if ns and ns.Frames and ns.Frames.GroupFrame and ns.Frames.GroupFrame.UpdateUnits then
        ns.Frames.GroupFrame:UpdateUnits()
    end
end

function WOWHealerUI:PLAYER_ROLES_ASSIGNED()
    if ns and ns.Frames and ns.Frames.GroupFrame and ns.Frames.GroupFrame.UpdateUnits then
        ns.Frames.GroupFrame:UpdateUnits()
    end
end

function WOWHealerUI:UNIT_AURA(unit)
    if ns and ns.Frames and ns.Frames.GroupFrame and ns.Frames.GroupFrame.OnUnitAura then
        ns.Frames.GroupFrame:OnUnitAura(unit)
    end
end

function WOWHealerUI:ZONE_CHANGED_NEW_AREA()
    ApplyObjectiveTrackerVisibility()
    if ns and ns.Frames and ns.Frames.RightPanel then
        ns.Frames.RightPanel:Refresh()
    end
end

function WOWHealerUI:SCENARIO_UPDATE()
    ApplyObjectiveTrackerVisibility()
end

function WOWHealerUI:CHALLENGE_MODE_START()
    ApplyObjectiveTrackerVisibility()
    if ns and ns.Frames and ns.Frames.RightPanel then ns.Frames.RightPanel:Refresh() end
end
function WOWHealerUI:CHALLENGE_MODE_RESET()
    ApplyObjectiveTrackerVisibility()
    if ns and ns.Frames and ns.Frames.RightPanel then ns.Frames.RightPanel:Refresh() end
end
function WOWHealerUI:CHALLENGE_MODE_COMPLETED()
    ApplyObjectiveTrackerVisibility()
    if ns and ns.Frames and ns.Frames.RightPanel then ns.Frames.RightPanel:Refresh() end
end

function WOWHealerUI:ENCOUNTER_START()
    if ns and ns.Frames and ns.Frames.RightPanel then ns.Frames.RightPanel:Refresh() end
end
function WOWHealerUI:ENCOUNTER_END()
    if ns and ns.Frames and ns.Frames.RightPanel then ns.Frames.RightPanel:Refresh() end
end

function WOWHealerUI:PLAYER_REGEN_ENABLED()
    -- After combat, apply tracker visibility in case changes were blocked in combat
    ApplyObjectiveTrackerVisibility()
end

-- Event registration
WOWHealerUI:RegisterEvent("ADDON_LOADED")
WOWHealerUI:RegisterEvent("PLAYER_LOGIN")
WOWHealerUI:RegisterEvent("PLAYER_ENTERING_WORLD")
WOWHealerUI:RegisterEvent("GROUP_ROSTER_UPDATE")
WOWHealerUI:RegisterEvent("PLAYER_ROLES_ASSIGNED")
WOWHealerUI:RegisterEvent("UNIT_AURA")
WOWHealerUI:RegisterEvent("ZONE_CHANGED_NEW_AREA")
WOWHealerUI:RegisterEvent("SCENARIO_UPDATE")
WOWHealerUI:RegisterEvent("CHALLENGE_MODE_START")
WOWHealerUI:RegisterEvent("CHALLENGE_MODE_RESET")
WOWHealerUI:RegisterEvent("CHALLENGE_MODE_COMPLETED")
WOWHealerUI:RegisterEvent("ENCOUNTER_START")
WOWHealerUI:RegisterEvent("ENCOUNTER_END")
WOWHealerUI:RegisterEvent("PLAYER_REGEN_ENABLED")

WOWHealerUI:SetScript("OnEvent", function(self, event, ...)
    if self[event] then
        self[event](self, ...)
    end
end)

-- Slash command
SLASH_WOWHEALERUI1 = "/whui"
SlashCmdList["WOWHEALERUI"] = function(msg)
    msg = (msg or ""):lower()
    if msg == "toggle" then
        WOWHealerUI_DB.enabled = not WOWHealerUI_DB.enabled
        if WOWHealerUI_DB.enabled then
            SetupUI()
        else
            if ns and ns.Frames and ns.Frames.GroupFrame then ns.Frames.GroupFrame:Hide() end
            if ns and ns.Frames and ns.Frames.RightPanel then ns.Frames.RightPanel:Hide() end
            -- If we were hiding the tracker, restore when disabling the addon
            if WOWHealerUI_DB.hideObjectiveTracker then
                WOWHealerUI_DB.hideObjectiveTracker = false
                ApplyObjectiveTrackerVisibility()
            end
        end
        print("|cff66ccffwow-healer-ui|r enabled:", WOWHealerUI_DB.enabled and "ON" or "OFF")
    else
        if ns and ns.Config and ns.Config.OpenOptionsPanel then
            ns.Config.OpenOptionsPanel()
        else
            print("/whui toggle - enable/disable, or open Options -> AddOns -> wow-healer-ui")
        end
    end
end

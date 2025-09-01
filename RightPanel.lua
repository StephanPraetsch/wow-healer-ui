local ADDON_NAME = ...
local WowHealerUI = _G.WowHealerUI

local Panel = {}
WowHealerUI:RegisterModule("RightPanel", Panel)

local FRAME
local labels = {}
local anchorX, anchorY = -130, -500 -- offsets from TOPRIGHT

local function SetText(key, text)
    if labels[key] then
        labels[key]:SetText(text or "")
    end
end

local function SecondsToClock(s)
    if not s or s < 0 then s = 0 end
    local m = math.floor(s/60)
    local sec = math.floor(s % 60)
    return string.format("%d:%02d", m, sec)
end

local function IsInDungeonParty()
    local inInstance, instType = IsInInstance()
    return inInstance and instType == "party"
end

local function IsMythicPlus()
    if not IsInDungeonParty() then return false end
    local name, instanceType, difficulty = GetInstanceInfo()
    return difficulty == 8
end

local function IsRaidInstance()
    local inInstance, instType = IsInInstance()
    return inInstance and instType == "raid"
end

-- Instance name always available on entering dungeon
local function GetInstanceName()
    local name = select(1, GetInstanceInfo())
    return name or ""
end

-- Challenge Mode map and limit (limit is the base time in seconds)
local function GetMapNameAndLimit()
    if not C_ChallengeMode or not C_ChallengeMode.GetActiveChallengeMapID then return nil, nil end
    local mapID = C_ChallengeMode.GetActiveChallengeMapID()
    if not mapID or not C_ChallengeMode.GetMapUIInfo then return nil, nil end
    local name, _, timeLimit = C_ChallengeMode.GetMapUIInfo(mapID)
    return name, timeLimit
end

-- Key level when active
local function GetKeyLevel()
    if C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
        local level = C_ChallengeMode.GetActiveKeystoneInfo()
        return tonumber(level)
    end
end

-- Return numeric remaining time for the active key (primary: run state; refine via widget; fallback to world timers)
local function GetActiveKeySecondsText()
    local _, elapsedTime, _  = GetWorldElapsedTime(1)
    local current_map_id = C_ChallengeMode.GetActiveChallengeMapID()
    if not current_map_id then
        return "not started"
    end
    local _, _, max_time = C_ChallengeMode.GetMapUIInfo(current_map_id)
    local remaining = max_time - elapsedTime
    if remaining > 0 then
        return SecondsToClock(remaining) .. " / " .. SecondsToClock(max_time)
    else
        return "|cffff2020" .. SecondsToClock(remaining) .. " / " .. SecondsToClock(max_time) .. "|r"
    end
end

local function UpdateRaidBosses()
    local name = select(1, GetInstanceInfo())
    local encounters = {}
    if EJ_GetEncounterInfo then
        local i = 1
        while true do
            local bossName = EJ_GetEncounterInfoByIndex(i, nil)
            if not bossName then break end
            table.insert(encounters, { name=bossName, dead=false })
            i = i + 1
        end
    end
    return name, encounters
end

local function ClearPanel()
    SetText("title", "")
    SetText("line1", "")
    SetText("line2", "")
    SetText("line3", "")
    SetText("line4", "")
    SetText("line5", "")
    SetText("line6", "")
end

local function UpdatePanel()
    if not WowHealerUI:IsEnabled() then
        FRAME:Hide()
        return
    end
    FRAME:Show()

    -- Keep objective tracker hidden
    WowHealerUI:HideObjectiveTracker()

    if IsInDungeonParty() then
        -- Title: show instance name immediately on entering the dungeon
        local titleName = GetInstanceName()

        -- If Mythic+ and an active key is detected, append +
        if IsMythicPlus() then
            local level = GetKeyLevel()
            if level and level > 0 then
                titleName = string.format("%s +%d", titleName, level)
            end
        end
        SetText("title", titleName)

        if IsMythicPlus() then
            SetText("line1", GetActiveKeySecondsText())
        else
            SetText("line1", "Remaining: not started")
        end

        local progressPercentage = ProgressPercentage()
        SetText("line2", progressPercentage)

        -- Current pull: XX.XX%
        SetText("line3", "")

        SetText("line4", "")
        SetText("line5", "")
        SetText("line6", "")

    elseif IsRaidInstance() then
        local raidName, bosses = UpdateRaidBosses()
        SetText("title", raidName or "Raid")
        SetText("line1", "")
        SetText("line2", "")
        SetText("line3", "")
        if bosses and #bosses > 0 then
            local maxLines = 3
            local shown = 0
            for i, b in ipairs(bosses) do
                shown = shown + 1
                SetText("line"..(3+shown), string.format("%s: %s", b.name, b.dead and "Dead" or "Alive"))
                if shown >= maxLines then break end
            end
            for j=3+shown+1, 6 do
                SetText("line"..j, "")
            end
        else
            SetText("line4", "")
            SetText("line5", "")
            SetText("line6", "")
        end

    else
        -- Open world: panel empty
        ClearPanel()
    end
end

-- Update every second in dungeon to keep timer/progress fresh
local accum = 0
local function OnFrameUpdate(self, elapsed)
    if not WowHealerUI:IsEnabled() then return end
    if not IsInDungeonParty() then return end
    accum = accum + elapsed
    if accum >= 1 then
        accum = 0
        UpdatePanel()
    end
end

function Panel:OnInit()
    FRAME = CreateFrame("Frame", "WowHealerUIRightPanel", UIParent, "BackdropTemplate")
    FRAME:SetSize(320, 220)
    FRAME:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1 })
    FRAME:SetBackdropColor(0,0,0,0.4)
    FRAME:SetBackdropBorderColor(0.2,0.2,0.2,1)
    FRAME:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", anchorX, anchorY)

    local y = -12
    local function addLabel(key, font, text, offsetY)
        local fs = FRAME:CreateFontString(nil, "OVERLAY", font)
        fs:SetPoint("TOPLEFT", 10, y)
        fs:SetText(text or "")
        labels[key] = fs
        y = y - (offsetY or 18)
    end

    addLabel("title", "GameFontNormalLarge", "")
    addLabel("line1", "GameFontHighlight", "")
    addLabel("line2", "GameFontHighlight", "")
    addLabel("line3", "GameFontHighlight", "")
    addLabel("line4", "GameFontHighlight", "")
    addLabel("line5", "GameFontHighlight", "")
    addLabel("line6", "GameFontHighlight", "")

    WowHealerUI:HideObjectiveTracker()

    FRAME:RegisterEvent("PLAYER_LOGIN")
    FRAME:RegisterEvent("PLAYER_ENTERING_WORLD")
    FRAME:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    FRAME:RegisterEvent("SCENARIO_UPDATE")
    FRAME:RegisterEvent("SCENARIO_CRITERIA_UPDATE")
    FRAME:RegisterEvent("CHALLENGE_MODE_START")
    FRAME:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    FRAME:RegisterEvent("CHALLENGE_MODE_RESET")
    FRAME:SetScript("OnEvent", function(self, event)
        WowHealerUI:HideObjectiveTracker()
        UpdatePanel()
    end)

    FRAME:SetScript("OnUpdate", OnFrameUpdate)
end

function Panel:OnLogin()
    WowHealerUI:HideObjectiveTracker()
    UpdatePanel()
end

function Panel:OnEnableChanged(enabled)
    if enabled then
        WowHealerUI:HideObjectiveTracker()
    else
        if ObjectiveTrackerFrame and ObjectiveTrackerFrame.RegisterAllEvents then
            ObjectiveTrackerFrame:RegisterAllEvents()
            ObjectiveTrackerFrame:Show()
        end
    end
    UpdatePanel()
end

function Panel:OnPlayerEnteringWorld()
    WowHealerUI:HideObjectiveTracker()
    UpdatePanel()
end

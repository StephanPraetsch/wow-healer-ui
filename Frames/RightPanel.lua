local ADDON, ns = ...
ns = ns or {}
ns.Frames = ns.Frames or {}

local RightPanel = CreateFrame("Frame", "WHUI_RightPanel", UIParent, "BackdropTemplate")
ns.Frames.RightPanel = RightPanel

RightPanel:SetSize(260, 200)
RightPanel:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -130, -500)
RightPanel:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background" })
RightPanel:Hide()

RightPanel.title = RightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
RightPanel.title:SetPoint("TOPLEFT", 10, -10)
RightPanel.title:SetText("Healer Info")

RightPanel.body = RightPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
RightPanel.body:SetPoint("TOPLEFT", RightPanel.title, "BOTTOMLEFT", 0, -10)
RightPanel.body:SetJustifyH("LEFT")
RightPanel.body:SetJustifyV("TOP")
RightPanel.body:SetSize(240, 160)

local function GetKeystoneInfo()
    local mapID = C_ChallengeMode.GetActiveChallengeMapID()
    if mapID then
        local name, id, timeLimit = C_ChallengeMode.GetMapUIInfo(mapID)
        local level = C_ChallengeMode.GetActiveKeystoneInfo()
        if name and level then
            return string.format("%s +%d", name, level)
        end
    end
end

local function GetRaidBossStatus()
    local inInstance, instType = IsInInstance()
    if not inInstance or instType ~= "raid" then return end

    local name, _, difficultyID, _, _, _, _, mapID = GetInstanceInfo()
    local numEnc = GetNumSavedInstances()
    local lines = {}
    table.insert(lines, string.format("%s", name or "Raid"))
    -- Try encounter info via EJ where possible
    local _, _, difficulty, _, _, _, _, instanceMapID = GetInstanceInfo()

    local num = EJ_GetNumEncountersForCurrentInstance() or 0
    if num > 0 then
        for i = 1, num do
            local bossName, _, encounterID = EJ_GetEncounterInfoByIndex(i)
            if bossName then
                local killed = IsEncounterComplete(encounterID)
                table.insert(lines, string.format("- %s: %s", bossName, killed and "|cff55ff55Dead|r" or "|cffff5555Alive|r"))
            end
        end
        return table.concat(lines, "\n")
    end

    -- Fallback: saved instance bosses
    for i = 1, numEnc do
        local instName, id, reset, diff, locked, extended, _, isRaid, maxPlayers, diffName, numEncounters, encounterProgress = GetSavedInstanceInfo(i)
        if instName == name then
            table.insert(lines, string.format("%s (%s)", instName, diffName or ""))
            table.insert(lines, string.format("Progress: %d/%d", encounterProgress or 0, numEncounters or 0))
            return table.concat(lines, "\n")
        end
    end
    return name
end

function RightPanel:Refresh()
    if not WOWHealerUI_DB.enabled or not WOWHealerUI_DB.rightPanel then
        self:Hide()
        return
    end

    local inInstance, instType = IsInInstance()

    if inInstance and instType == "party" then
        local keyLine = GetKeystoneInfo()
        self.title:SetText("Mythic+")
        self.body:SetText(keyLine or "")
        self:Show()
        return
    end

    if inInstance and instType == "raid" then
        self.title:SetText("Raid")
        self.body:SetText(GetRaidBossStatus() or "")
        self:Show()
        return
    end

    -- Open world
    self.title:SetText("Healer Info")
    self.body:SetText("")
    self:Show()
end

local name, ns = ...

local Panel = {}
WowHealerUI:RegisterModule("MythicPlusPanel", Panel)

local LibGetFrame = LibStub and LibStub('LibGetFrame-1.0')

-- Locals
local FRAME
local activeNameplates = {}
local fontStringPool
local titleFS
local activeSecondsFS
local progressPercentageFS

local percentString = '%.2f%%';

-- Pool functions (define BEFORE CreateObjectPool, and do not reference FRAME here)
local function poolInit(pool)
    local fs = UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:Hide()
    return fs
end

local function poolReset(pool, fs)
    if not fs then
        return
    end
    fs:ClearAllPoints()
    fs:SetText("")
    fs:Hide()
    fs:SetParent(UIParent)
end

local function IsMMPELoaded()
    return type(_G.MMPE) == "table"
end

local function IsMythicPlus()
    local _, _, difficulty = GetInstanceInfo()
    return difficulty == 8
end

local function IsDungeonFinished()
    local stepInfo = select(3, C_Scenario.GetStepInfo())
    return (stepInfo and stepInfo < 1)
end

local function ShouldShowNameplateTexts()
    return IsMythicPlus() and not IsDungeonFinished() and WowHealerUI:IsEnabled() and IsMMPELoaded() and not MMPE:ShouldShowNameplateTexts()
end

local function ShowPanel()
    return IsMythicPlus() and WowHealerUI:IsEnabled()
end

local function GetNPCID(guid)
    if not guid then
        return nil
    end
    local targetType, _, _, _, _, npcID = strsplit("-", guid)
    if (targetType == "Creature" or targetType == "Vehicle") and npcID then
        return tonumber(npcID)
    else
        return "null"
    end
end

local function RemoveNameplateText(unit)
    local fs = activeNameplates[unit]
    if fs then
        fontStringPool:Release(fs)
        activeNameplates[unit] = nil
    end
end

local function CreateNameplateText(unit)
    if not (LibGetFrame and LibGetFrame.GetUnitNameplate) then
        return
    end
    if not UnitExists(unit) then
        return
    end

    local guid = UnitGUID(unit)
    local npcID = guid and select(6, strsplit("-", guid))
    if not npcID then
        return
    end

    if activeNameplates[unit] then
        fontStringPool:Release(activeNameplates[unit])
        activeNameplates[unit] = nil
    end

    local plate = LibGetFrame.GetUnitNameplate(unit)
    if not plate then
        return
    end

    local fs = fontStringPool:Acquire()

    local parent = plate.UnitFrame or plate
    fs:SetParent(parent)
    fs:SetDrawLayer("OVERLAY", 7)
    fs:SetAlpha(1)
    fs:SetTextColor(1, 1, 1, 1)
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", parent, "RIGHT", 6, 0)

    local lvl = parent.GetFrameLevel and parent:GetFrameLevel() or 0
    if fs.SetFrameLevel then
        fs:SetFrameLevel(lvl + 10)
    end

    local npcId = GetNPCID(guid)
    local estProg, _ = MMPE:GetEstimatedProgress(npcId)

    fs:SetScale(1.0)
    fs:SetJustifyH("LEFT")
    if estProg then
        local message = string.format("%.2f", estProg) .. "%"
        fs:SetText(message)
        fs:Show()
    end

    activeNameplates[unit] = fs
end

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

local function ReadForcesPercent()
    if type(C_Scenario) ~= "table" or type(C_Scenario.GetCriteriaInfo) ~= "function" then
        return 0
    end

    -- Try to find the Enemy Forces criteria; fall back to first with a valid total
    local quantity, totalQuantity = 0, 1
    local found = false

    -- Prefer explicit forces criteria
    for i = 1, 20 do
        local ok, name, _, _, q, tq = pcall(C_Scenario.GetCriteriaInfo, i)
        if not ok or not name then break end
        if type(tq) == "number" and tq > 0 then
            if type(name) == "string" and (name:find("Enemy Forces") or name:find("Forces")) then
                quantity = (type(q) == "number" and q) or 0
                totalQuantity = tq
                found = true
                break
            end
        end
    end

    -- Fallback: first criteria with total > 0
    if not found then
        for i = 1, 20 do
            local ok, name, _, _, q, tq = pcall(C_Scenario.GetCriteriaInfo, i)
            if not ok or not name then break end
            if type(tq) == "number" and tq > 0 then
                quantity = (type(q) == "number" and q) or 0
                totalQuantity = tq
                break
            end
        end
    end

    if totalQuantity <= 0 then totalQuantity = 1 end
    local pct = (quantity / totalQuantity) * 100
    if pct < 0 then pct = 0 end
    if pct > 100 then pct = 100 end
    return pct
end

local function ProgressPercentage()
    local pct = ReadForcesPercent()
    return string.format("%.2f%%", pct)
end

local function GetKeyLevel()
    if C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
        local level = C_ChallengeMode.GetActiveKeystoneInfo()
        return tonumber(level)
    end
end

local function GetInstanceName()
    return select(1, GetInstanceInfo())
end

local function UpdatePanel()
    if not ShowPanel() then
        FRAME:Hide()
        return
    end
    FRAME:Show()
    if IsMythicPlus() then
        local level = GetKeyLevel()
        if level and level > 0 then
            titleFS:SetText(string.format("%s +%d", GetInstanceName(), level))
            activeSecondsFS:SetText(GetActiveKeySecondsText())
            if IsMMPELoaded() then
                local current = MMPE:GetCurrentQuantity()
                local pull = MMPE:GetPulledProgress()
                local total = (current + pull)
                local max = MMPE:GetMaxQuantity()
                local currentPct = percentString:format((current / max) * 100)
                local pullPct = percentString:format((pull / max) * 100)
                local totalPct = percentString:format((total / max) * 100)
                progressPercentageFS:SetText(currentPct .. " + " .. pullPct .. " = " .. totalPct)
            else
                progressPercentageFS:SetText(ProgressPercentage())
            end
        else
            titleFS:SetText(GetInstanceName())
        end
    else
        titleFS:SetText("")
        activeSecondsFS:SetText("")
        progressPercentageFS:SetText("")
    end

end

local function RefreshAllNameplates()
    for unit, fs in pairs(activeNameplates) do
        fontStringPool:Release(fs)
        activeNameplates[unit] = nil
    end

    if not ShouldShowNameplateTexts() then
        return
    end

    local plates = C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates()
    if not plates then
        return
    end

    for _, plate in ipairs(plates) do
        local unit = plate.namePlateUnitToken or plate.unit or plate.displayedUnit or plate.unitToken
        if unit and UnitExists(unit) then
            CreateNameplateText(unit)
        end
    end
end

local function RunNextFrame(fn)
    C_Timer.After(0, fn)
end

local function OnAddNameplate(unit)
    if ShouldShowNameplateTexts() then
        RunNextFrame(function()
            CreateNameplateText(unit)
        end)
    end
end

local function OnRemoveNameplate(unit)
    RemoveNameplateText(unit)
end

-- Update every second to refresh labels if needed
local accum = 0
local function OnFrameUpdate(self, elapsed)
    if not WowHealerUI:IsEnabled() then
        return
    end
    accum = accum + elapsed
    if accum >= 1 then
        accum = 0
        RefreshAllNameplates()
        UpdatePanel()
    end
end

function Panel:OnInit()
    FRAME = CreateFrame("Frame", "MythicPlusPanel", UIParent, "BackdropTemplate")
    FRAME:SetSize(250, 100)
    FRAME:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    FRAME:SetBackdropColor(0, 0, 0, 0.4)
    FRAME:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
    FRAME:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -320, -240)
    FRAME:SetMovable(true)
    FRAME:EnableMouse(true)
    FRAME:SetScript("OnUpdate", OnFrameUpdate)

    fontStringPool = CreateObjectPool(poolInit, poolReset)

    FRAME:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and IsShiftKeyDown() then
            self:StartMoving()
            self.isMoving = true
        end
    end)

    FRAME:SetScript("OnMouseUp", function(self, button)
        if self.isMoving then
            self:StopMovingOrSizing()
            self.isMoving = false
        end
    end)

    FRAME:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    FRAME:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    FRAME:SetScript("OnEvent", function(_, event, unit)
        if event == "NAME_PLATE_UNIT_ADDED" then
            OnAddNameplate(unit)
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            OnRemoveNameplate(unit)
        end
    end)

    titleFS = FRAME:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleFS:SetPoint("TOPLEFT", 10, -12)
    titleFS:SetText("")

    activeSecondsFS = FRAME:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    activeSecondsFS:SetPoint("TOPLEFT", 10, -30)
    activeSecondsFS:SetText("")

    progressPercentageFS = FRAME:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    progressPercentageFS:SetPoint("TOPLEFT", 10, -48)
    progressPercentageFS:SetText("")

end

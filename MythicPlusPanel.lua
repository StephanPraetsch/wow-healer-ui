local name, ns = ...

local Panel = {}
WowHealerUI:RegisterModule("MythicPlusPanel", Panel)

local LibGetFrame = LibStub('LibGetFrame-1.0');

activeNameplates = {}
fontStringPool = CreateObjectPool(init, reset) --[[@as ObjectPool<FontString>]]

local function IsMythicPlus()
    local _, _, difficulty = GetInstanceInfo()
    return difficulty == 8
end

local function IsDungeonFinished()
    local stepInfo = select(3, C_Scenario.GetStepInfo())
    return (stepInfo and stepInfo < 1)
end

local function ShouldShowNameplateTexts()
    if IsMythicPlus() and not IsDungeonFinished() then
        return true
    end
    return false
end

local function GetNPCID(guid)
    if guid == nil then
        return nil
    end
    local targetType, _, _, _, _, npcID = strsplit("-", guid)
    if targetType == "Creature" or targetType == "Vehicle" and npcID then
        return tonumber(npcID)
    end
end

local function CreateNameplateText(unit)
    local npcID = GetNPCID(UnitGUID(unit))
    if npcID then
        if activeNameplates[unit] then
            RemoveNameplateText(unit)
        end
        local nameplate = LibGetFrame.GetUnitNameplate(unit)
        if nameplate then
            activeNameplates[unit] = fontStringPool:Acquire()
            activeNameplates[unit]:SetParent(nameplate)
            activeNameplates[unit]:SetText("omfg")
            activeNameplates[unit]:SetScale(1.0)
        end
    end
end

local function OnAddNameplate(unit)
    print("OnAddNameplate", unit)
    if ShouldShowNameplateTexts() then
        RunNextFrame(function()
            CreateNameplateText(unit)
            --UpdateNameplateValue(unit)
            --UpdateNameplatePosition(unit)
        end)
    end
end

local function RemoveNameplateText(unit)
    if activeNameplates[unit] ~= nil then
        fontStringPool:Release(activeNameplates[unit])
        activeNameplates[unit] = nil
    end
end

local function OnRemoveNameplate(unit)
    RemoveNameplateText(unit)
    activeNameplates[unit] = nil
end

local function UpdateNameplateValue(unit)
    print("UpdateNameplateValue", unit)
    local npcID = GetNPCID(UnitGUID(unit))
    if npcID then
        --local estProg, count = self:GetEstimatedProgress(npcID)
        if count and count > 0 then
            -- TODO name plate
            --local message = string.format("%.2f", estProg) .. "%"
            local message = "sph"

            activeNameplates[unit]:SetText(message)
            activeNameplates[unit]:Show()
            return true
        end
    end
    if activeNameplates[unit] then
        activeNameplates[unit]:SetText("")
        activeNameplates[unit]:Hide()
    end
    return false
end

local function UpdateNameplateValues()
    for unit, _ in pairs(activeNameplates) do
        UpdateNameplateValue(unit)
    end
end

local function UpdatePanel()
    UpdateNameplateValues()
end

-- Update every second in dungeon to keep timer/progress fresh
local accum = 0
local function OnFrameUpdate(self, elapsed)
    if not WowHealerUI:IsEnabled() then return end
    accum = accum + elapsed
    if accum >= 1 then
        accum = 0
        UpdatePanel()
    end
end

function Panel:OnInit()
    print("init MythicPlusPanel")

    FRAME = CreateFrame("Frame", "MythicPlusPanel", UIParent, "BackdropTemplate")
    FRAME:SetSize(250, 150)
    FRAME:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1 })
    FRAME:SetBackdropColor(0,0,0,0.4)
    FRAME:SetBackdropBorderColor(0.2,0.2,0.2,1)
    FRAME:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -320, -240)
    FRAME:SetMovable(true)
    FRAME:EnableMouse(true)
    FRAME:SetScript("OnUpdate", OnFrameUpdate)

    -- Register events
    FRAME:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    FRAME:RegisterEvent("NAME_PLATE_UNIT_REMOVED")

    -- Dispatch events
    FRAME:SetScript("OnEvent", function(_, event, unit)
        if event == "NAME_PLATE_UNIT_ADDED" then
            OnAddNameplate(unit)
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            OnRemoveNameplate(unit)
        end
    end)

    print("init MythicPlusPanel - done")
end

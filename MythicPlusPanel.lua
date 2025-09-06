local name, ns = ...

local Panel = {}
WowHealerUI:RegisterModule("MythicPlusPanel", Panel)

local LibGetFrame = LibStub and LibStub('LibGetFrame-1.0')

-- Locals
local FRAME
local activeNameplates = {}
local fontStringPool

-- Pool functions (define BEFORE CreateObjectPool, and do not reference FRAME here)
local function poolInit(pool)
    local fs = UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:Hide()
    return fs
end

local function poolReset(pool, fs)
    if not fs then return end
    fs:ClearAllPoints()
    fs:SetText("")
    fs:Hide()
    fs:SetParent(UIParent)
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
    return IsMythicPlus() and not IsDungeonFinished()
end

local function GetNPCID(guid)
    if not guid then return nil end
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
    if not (LibGetFrame and LibGetFrame.GetUnitNameplate) then return end
    if not UnitExists(unit) then return end

    local guid = UnitGUID(unit)
    local npcID = guid and select(6, strsplit("-", guid))
    if not npcID then return end

    if activeNameplates[unit] then
        fontStringPool:Release(activeNameplates[unit])
        activeNameplates[unit] = nil
    end

    local plate = LibGetFrame.GetUnitNameplate(unit)
    if not plate then return end

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

    local guid = UnitGUID(unit)
    local npcId = GetNPCID(guid)
    --local estProg, count = _G.MMPE:GetEstimatedProgress(npcId)
    local message = string.format("%.2f", 2) .. "%"

    fs:SetScale(1.0)
    fs:SetJustifyH("LEFT")
    fs:SetText("foo '" .. message .. "' bar")
    fs:Show()

    activeNameplates[unit] = fs
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
    if not WowHealerUI:IsEnabled() then return end
    accum = accum + elapsed
    if accum >= 1 then
        accum = 0
        -- Update any text if needed
    end
end

function Panel:OnInit()
    FRAME = CreateFrame("Frame", "MythicPlusPanel", UIParent, "BackdropTemplate")
    FRAME:SetSize(250, 150)
    FRAME:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1 })
    FRAME:SetBackdropColor(0,0,0,0.4)
    FRAME:SetBackdropBorderColor(0.2,0.2,0.2,1)
    FRAME:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -320, -240)
    FRAME:SetMovable(true)
    FRAME:EnableMouse(true)
    FRAME:SetScript("OnUpdate", OnFrameUpdate)

    fontStringPool = CreateObjectPool(poolInit, poolReset)

    FRAME:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    FRAME:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    FRAME:SetScript("OnEvent", function(_, event, unit)
        if event == "NAME_PLATE_UNIT_ADDED" then
            OnAddNameplate(unit)
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            OnRemoveNameplate(unit)
        end
    end)

end

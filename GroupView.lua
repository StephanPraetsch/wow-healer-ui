local ADDON_NAME = ...
local WowHealerUI = _G.WowHealerUI

local GroupView = {}
WowHealerUI:RegisterModule("GroupView", GroupView)

local ROOT
local UNIT_BUTTONS = {}
local RAID_GROUP_HEADERS = {}
local HILIGHT_COLOR = { r=1, g=1, b=0.2 }

-- Configuration
local BUTTON_WIDTH, BUTTON_HEIGHT = 200, 28
local FONT = "GameFontNormal"

-- Unit sorting helpers
local function RoleSort(u1, u2)
    local prio = { TANK=1, HEALER=2, DAMAGER=3, NONE=4 }
    local r1 = prio[WowHealerUI:GetUnitRole(u1)] or 4
    local r2 = prio[WowHealerUI:GetUnitRole(u2)] or 4
    if r1 ~= r2 then return r1 < r2 end
    return (UnitName(u1) or "") < (UnitName(u2) or "")
end

local function BuildUnitList()
    local units = {}
    if IsInRaid() then
        for i=1, GetNumGroupMembers() do
            table.insert(units, "raid"..i)
        end
    elseif IsInGroup() then
        table.insert(units, "player")
        for i=1, GetNumSubgroupMembers() do
            table.insert(units, "party"..i)
        end
    else
        table.insert(units, "player")
    end
    return units
end

local function GetRaidGroupIndex(unit)
    if not IsInRaid() then return 1 end
    local unitName = UnitName(unit)
    for i=1, GetNumGroupMembers() do
        local raidName, rank, subgroup = GetRaidRosterInfo(i)
        if raidName == unitName then
            return subgroup or 1
        end
    end
    return 1
end

local function CreateUnitButton(parent)
    local b = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate,BackdropTemplate")
    b:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    b:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1 })
    b:SetBackdropColor(0,0,0,0.5)
    b:SetBackdropBorderColor(0.2,0.2,0.2,1)

    b:RegisterForClicks("AnyDown")

    -- Secure spell targeting: left targets, right can be set to a spell externally
    b:SetAttribute("*type1", "target")
    b:SetAttribute("*type2", "spell")
    b:SetAttribute("spell", nil)

    local nameFS = b:CreateFontString(nil, "OVERLAY", FONT)
    nameFS:SetPoint("LEFT", 6, 0)
    nameFS:SetWidth(90)
    nameFS:SetJustifyH("LEFT")
    b.nameFS = nameFS

    local hpBar = CreateFrame("StatusBar", nil, b)
    hpBar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    hpBar:SetSize(80, 10)
    hpBar:SetPoint("RIGHT", -6, 6)
    hpBar:SetMinMaxValues(0,1)
    hpBar.bg = b:CreateTexture(nil, "BACKGROUND")
    hpBar.bg:SetAllPoints(hpBar)
    hpBar.bg:SetColorTexture(0.1,0.1,0.1,0.8)
    b.hpBar = hpBar

    local resBar = CreateFrame("StatusBar", nil, b)
    resBar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    resBar:SetSize(80, 6)
    resBar:SetPoint("RIGHT", -6, -7)
    resBar:SetMinMaxValues(0,1)
    resBar.bg = b:CreateTexture(nil, "BACKGROUND")
    resBar.bg:SetAllPoints(resBar)
    resBar.bg:SetColorTexture(0.1,0.1,0.1,0.8)
    b.resBar = resBar

    local ilvlFS = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ilvlFS:SetPoint("RIGHT", resBar, "LEFT", -6, 0)
    ilvlFS:SetText("ilvl")
    b.ilvlFS = ilvlFS

    -- Hover highlight
    b:SetScript("OnEnter", function(self)
        if not WowHealerUI:IsEnabled() then return end
        self:SetBackdropBorderColor(1,1,0.2,1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(UnitName(self.unit) or "Unknown")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        if not WowHealerUI:IsEnabled() then return end
        self:SetBackdropBorderColor(0.2,0.2,0.2,1)
        GameTooltip:Hide()
    end)

    -- Secure unit assignment for targeting
    b:SetAttribute("unit", nil)

    return b
end

local function UpdateUnitButton(b)
    local unit = b.unit
    if not unit or not UnitExists(unit) then
        b:Hide()
        return
    end

    b:Show()

    -- Class color name
    local r,g,bl = WowHealerUI:GetClassColor(unit)
    local name = UnitName(unit) or "Unknown"
    b.nameFS:SetText(name)
    b.nameFS:SetTextColor(r,g,bl)

    -- Health
    local hp = UnitHealth(unit)
    local hpMax = UnitHealthMax(unit)
    hp = math.max(0, math.min(hp, hpMax))
    local hpPerc = hpMax > 0 and hp / hpMax or 0
    b.hpBar:SetMinMaxValues(0,1)
    b.hpBar:SetValue(hpPerc)
    b.hpBar:SetStatusBarColor(0.2, 0.8, 0.2)

    -- Resource
    local powerType = UnitPowerType(unit)
    local power = UnitPower(unit, powerType)
    local powerMax = UnitPowerMax(unit, powerType)
    local pPerc = powerMax > 0 and power / powerMax or 0
    b.resBar:SetMinMaxValues(0,1)
    b.resBar:SetValue(pPerc)
    if powerType == 0 then
        b.resBar:SetStatusBarColor(0.2, 0.4, 0.9) -- mana
    else
        b.resBar:SetStatusBarColor(0.9, 0.8, 0.2) -- others
    end

    -- iLvl (self only; inspect restricted)
    local ilvlText = "-"
    if C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel and UnitIsPlayer(unit) then
        if UnitIsUnit(unit, "player") then
            local ok, avgItemLevel = pcall(C_PaperDollInfo.GetInspectItemLevel, unit)
            if ok and avgItemLevel and avgItemLevel > 0 then
                ilvlText = string.format("%.0f", avgItemLevel)
            end
        end
    end
    b.ilvlFS:SetText(ilvlText)

    -- Debuff highlights (safe)
    local disp = false
    local danger = false
    if WowHealerUI.IsDispellable then
        disp = WowHealerUI:IsDispellable(unit)
    end
    if WowHealerUI.IsDangerousDebuff then
        danger = WowHealerUI:IsDangerousDebuff(unit)
    end

    if danger then
        b:SetBackdropBorderColor(1, 0.5, 0, 1) -- orange
    elseif disp then
        b:SetBackdropBorderColor(1, 1, 1, 1) -- white
    else
        b:SetBackdropBorderColor(0.2,0.2,0.2,1)
    end

    -- Secure attributes to allow click targeting and mouseover casts
    b:SetAttribute("unit", unit)

    b:SetScript("OnEnter", function(self)
        if not WowHealerUI:IsEnabled() then return end
        self:SetBackdropBorderColor(1,1,0.2,1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(UnitName(self.unit) or "Unknown")
        GameTooltip:Show()
    end)
end

local function LayoutGroup(units)
    for _, b in ipairs(UNIT_BUTTONS) do
        b:Hide()
        b.unit = nil
    end

    local idx = 1
    if IsInRaid() then
        local groups = {}
        for _, unit in ipairs(units) do
            local g = GetRaidGroupIndex(unit)
            groups[g] = groups[g] or {}
            table.insert(groups[g], unit)
        end
        local col = 0
        for g=1,8 do
            local gu = groups[g]
            if gu and #gu > 0 then
                table.sort(gu, function(a,b) return (UnitName(a) or "") < (UnitName(b) or "") end)
                for i, unit in ipairs(gu) do
                    local b = UNIT_BUTTONS[idx] or CreateUnitButton(ROOT); UNIT_BUTTONS[idx] = b
                    b.unit = unit
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", ROOT, "TOPLEFT", col*(BUTTON_WIDTH+8), -(i-1)*(BUTTON_HEIGHT+4))
                    UpdateUnitButton(b)
                    idx = idx + 1
                end
                col = col + 1
            end
        end
    else
        table.sort(units, RoleSort)
        for i, unit in ipairs(units) do
            local b = UNIT_BUTTONS[idx] or CreateUnitButton(ROOT); UNIT_BUTTONS[idx] = b
            b.unit = unit
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", ROOT, "TOPLEFT", 0, -(i-1)*(BUTTON_HEIGHT+4))
            UpdateUnitButton(b)
            idx = idx + 1
        end
    end

    for i=idx, #UNIT_BUTTONS do
        UNIT_BUTTONS[i]:Hide()
    end
end

local function RefreshAll()
    if not WowHealerUI:IsEnabled() then
        if ROOT then ROOT:Hide() end
        return
    end
    if not ROOT then return end
    ROOT:Show()
    local units = BuildUnitList()
    LayoutGroup(units)
end

function GroupView:OnInit()
    ROOT = CreateFrame("Frame", "WowHealerUIGroupView", UIParent, "BackdropTemplate")
    ROOT:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -200)
    ROOT:SetSize(4*(BUTTON_WIDTH+8), 10*(BUTTON_HEIGHT+4))
    ROOT:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8x8" })
    ROOT:SetBackdropColor(0,0,0,0.2)
    ROOT:Show()

    ROOT:RegisterEvent("GROUP_ROSTER_UPDATE")
    ROOT:RegisterEvent("PLAYER_ROLES_ASSIGNED")
    ROOT:RegisterEvent("PLAYER_ENTERING_WORLD")
    ROOT:RegisterEvent("UNIT_HEALTH")
    ROOT:RegisterEvent("UNIT_MAXHEALTH")
    ROOT:RegisterEvent("UNIT_POWER_UPDATE")
    ROOT:RegisterEvent("UNIT_MAXPOWER")
    ROOT:RegisterEvent("UNIT_AURA")
    ROOT:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    ROOT:RegisterEvent("INSPECT_READY")

    ROOT:SetScript("OnEvent", function(self, event, arg1)
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_AURA" then
            for _, b in ipairs(UNIT_BUTTONS) do
                if b.unit == arg1 then
                    UpdateUnitButton(b)
                end
            end
        else
            RefreshAll()
        end
    end)
end

function GroupView:OnLogin()
    RefreshAll()
end

function GroupView:OnEnableChanged(enabled)
    RefreshAll()
end

function GroupView:OnPlayerEnteringWorld()
    RefreshAll()
end
